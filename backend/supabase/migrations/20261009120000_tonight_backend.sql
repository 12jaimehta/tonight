-- Tonight local schema.
-- Plain Postgres, except two Supabase edges: auth.uid() (and auth.users) and storage.
-- The service role bypasses RLS, which is how the deletion jobs remove objects.

create extension if not exists pg_cron;

-- Allowed consent scopes for v1. A row may grant any non-empty subset.
create or replace function public.consent_scopes_valid(scopes text[])
returns boolean
language sql
immutable
as $$
  select scopes is not null
    and cardinality(scopes) >= 1
    and not exists (
      select 1
      from unnest(scopes) as scope
      where scope is null
        or scope not in ('on_device_speech', 'server_speech', 'study_audio')
    )
    and cardinality(scopes) = (
      select count(distinct scope)
      from unnest(scopes) as scope
    );
$$;

create table public.parent (
  id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table public.parent is
  'The account. One row per auth user. No child content.';

create table public.child_profile (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.parent (id) on delete cascade,
  nickname text,
  age_band text not null default '6-8',
  school_class text,
  created_at timestamptz not null default now(),
  constraint child_profile_age_band_v1 check (age_band = '6-8')
);

comment on column public.child_profile.age_band is
  'v1 allows only the 6-8 band.';
comment on column public.child_profile.school_class is
  'Free text stored as data, not a Postgres enum.';

create table public.consent_record (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.parent (id) on delete cascade,
  child_profile_id uuid not null references public.child_profile (id) on delete cascade,
  version text not null,
  scopes text[] not null,
  granted_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  method text not null,
  constraint consent_record_version_present check (length(btrim(version)) > 0),
  constraint consent_record_method_present check (length(btrim(method)) > 0),
  constraint consent_record_scopes_valid check (public.consent_scopes_valid(scopes)),
  constraint consent_record_withdrawn_after_grant check (
    withdrawn_at is null or withdrawn_at >= granted_at
  )
);

comment on table public.consent_record is
  'Grant is an insert. Withdrawal sets withdrawn_at once. No other update is allowed.';

-- Insert-only audit. No foreign keys: a parent delete must not try to delete these rows,
-- because the trigger below rejects DELETE for every role, including the service role.
create table public.consent_audit (
  id uuid primary key default gen_random_uuid(),
  consent_record_id uuid not null,
  parent_id uuid not null,
  child_profile_id uuid not null,
  action text not null,
  version text not null,
  scopes text[] not null,
  at timestamptz not null,
  method text not null,
  constraint consent_audit_action check (action in ('granted', 'withdrawn')),
  constraint consent_audit_scopes_valid check (public.consent_scopes_valid(scopes))
);

comment on table public.consent_audit is
  'Insert-only. UPDATE and DELETE are rejected by trigger.';

create table public.entitlement (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.parent (id) on delete cascade,
  storekit_product text not null,
  status text not null,
  expires_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint entitlement_product_present check (length(btrim(storekit_product)) > 0),
  constraint entitlement_status_present check (length(btrim(status)) > 0),
  constraint entitlement_parent_product unique (parent_id, storekit_product)
);

-- Objects (or a child prefix) waiting out the 24 hour clock after a speech or study-audio withdrawal.
-- Prefix shape is {parent_id}/{child_profile_id}/ so one child's audio is not another child's.
create table public.storage_deletion_queue (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null,
  child_profile_id uuid not null,
  bucket_id text not null default 'study-audio',
  object_prefix text not null,
  delete_after timestamptz not null,
  enqueued_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint storage_deletion_queue_prefix_chk check (
    object_prefix ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/$'
  )
);

create index child_profile_parent_id_idx on public.child_profile (parent_id);
create index consent_record_parent_child_idx
  on public.consent_record (parent_id, child_profile_id);
create index entitlement_parent_id_idx on public.entitlement (parent_id);
create index storage_deletion_queue_due_idx
  on public.storage_deletion_queue (delete_after)
  where deleted_at is null;

create or replace function public.consent_record_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.consent_audit (
    consent_record_id,
    parent_id,
    child_profile_id,
    action,
    version,
    scopes,
    at,
    method
  ) values (
    new.id,
    new.parent_id,
    new.child_profile_id,
    'granted',
    new.version,
    new.scopes,
    new.granted_at,
    new.method
  );
  return new;
end;
$$;

create or replace function public.consent_record_before_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.withdrawn_at is not null then
    raise exception 'consent withdrawal is final'
      using errcode = '55000';
  end if;

  if new.id is distinct from old.id
    or new.parent_id is distinct from old.parent_id
    or new.child_profile_id is distinct from old.child_profile_id
    or new.version is distinct from old.version
    or new.scopes is distinct from old.scopes
    or new.granted_at is distinct from old.granted_at
    or new.method is distinct from old.method
    or new.withdrawn_at is null
  then
    raise exception 'consent_record only allows setting withdrawn_at once'
      using errcode = '55000';
  end if;

  -- Database clock, so a client cannot stretch or backdate the withdrawal.
  new.withdrawn_at := now();

  insert into public.consent_audit (
    consent_record_id,
    parent_id,
    child_profile_id,
    action,
    version,
    scopes,
    at,
    method
  ) values (
    old.id,
    old.parent_id,
    old.child_profile_id,
    'withdrawn',
    old.version,
    old.scopes,
    new.withdrawn_at,
    old.method
  );

  -- On-device-only grants never start the storage clock.
  if old.scopes && array['server_speech', 'study_audio']::text[] then
    insert into public.storage_deletion_queue (
      parent_id,
      child_profile_id,
      bucket_id,
      object_prefix,
      delete_after
    ) values (
      old.parent_id,
      old.child_profile_id,
      'study-audio',
      old.parent_id::text || '/' || old.child_profile_id::text || '/',
      new.withdrawn_at + interval '24 hours'
    );
  end if;

  return new;
end;
$$;

create trigger consent_record_audit_grant
  after insert on public.consent_record
  for each row
  execute function public.consent_record_after_insert();

create trigger consent_record_withdrawal
  before update on public.consent_record
  for each row
  execute function public.consent_record_before_update();

create or replace function public.consent_audit_reject_change()
returns trigger
language plpgsql
as $$
begin
  raise exception 'consent_audit is insert-only'
    using errcode = '55000';
end;
$$;

create trigger consent_audit_no_update
  before update on public.consent_audit
  for each row
  execute function public.consent_audit_reject_change();

create trigger consent_audit_no_delete
  before delete on public.consent_audit
  for each row
  execute function public.consent_audit_reject_change();

create or replace function public.touch_entitlement_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger entitlement_touch_updated_at
  before update on public.entitlement
  for each row
  execute function public.touch_entitlement_updated_at();

alter table public.parent enable row level security;
alter table public.child_profile enable row level security;
alter table public.consent_record enable row level security;
alter table public.consent_audit enable row level security;
alter table public.entitlement enable row level security;
alter table public.storage_deletion_queue enable row level security;

-- No policies for anon. Default deny covers that role.

create policy parent_select
  on public.parent
  for select
  to authenticated
  using (id = auth.uid());

create policy parent_insert
  on public.parent
  for insert
  to authenticated
  with check (id = auth.uid());

create policy child_profile_select
  on public.child_profile
  for select
  to authenticated
  using (parent_id = auth.uid());

create policy child_profile_insert
  on public.child_profile
  for insert
  to authenticated
  with check (parent_id = auth.uid());

create policy child_profile_update
  on public.child_profile
  for update
  to authenticated
  using (parent_id = auth.uid())
  with check (parent_id = auth.uid());

create policy child_profile_delete
  on public.child_profile
  for delete
  to authenticated
  using (parent_id = auth.uid());

create policy consent_record_select
  on public.consent_record
  for select
  to authenticated
  using (parent_id = auth.uid());

create policy consent_record_insert
  on public.consent_record
  for insert
  to authenticated
  with check (
    parent_id = auth.uid()
    and exists (
      select 1
      from public.child_profile as child
      where child.id = child_profile_id
        and child.parent_id = auth.uid()
    )
  );

create policy consent_record_update
  on public.consent_record
  for update
  to authenticated
  using (parent_id = auth.uid())
  with check (parent_id = auth.uid());

create policy consent_audit_select
  on public.consent_audit
  for select
  to authenticated
  using (parent_id = auth.uid());

create policy entitlement_select
  on public.entitlement
  for select
  to authenticated
  using (parent_id = auth.uid());

create policy entitlement_insert
  on public.entitlement
  for insert
  to authenticated
  with check (parent_id = auth.uid());

create policy entitlement_update
  on public.entitlement
  for update
  to authenticated
  using (parent_id = auth.uid())
  with check (parent_id = auth.uid());

create policy entitlement_delete
  on public.entitlement
  for delete
  to authenticated
  using (parent_id = auth.uid());

-- storage_deletion_queue has RLS and no policy for anon or authenticated.
-- The withdrawal trigger and the cron functions run as the table owner.

revoke all on table public.parent from anon;
revoke all on table public.child_profile from anon;
revoke all on table public.consent_record from anon;
revoke all on table public.consent_audit from anon, authenticated;
revoke all on table public.entitlement from anon;
revoke all on table public.storage_deletion_queue from anon, authenticated;

grant select, insert on table public.parent to authenticated;
grant select, insert, update, delete on table public.child_profile to authenticated;
grant select, insert, update on table public.consent_record to authenticated;
grant select on table public.consent_audit to authenticated;
grant select, insert, update, delete on table public.entitlement to authenticated;

grant all on table public.parent to service_role;
grant all on table public.child_profile to service_role;
grant all on table public.consent_record to service_role;
grant select on table public.consent_audit to service_role;
grant all on table public.entitlement to service_role;
grant all on table public.storage_deletion_queue to service_role;

revoke all on function public.consent_record_after_insert() from public, anon, authenticated, service_role;
revoke all on function public.consent_record_before_update() from public, anon, authenticated, service_role;
revoke all on function public.consent_audit_reject_change() from public, anon, authenticated, service_role;
revoke all on function public.touch_entitlement_updated_at() from public, anon, authenticated, service_role;

-- Private study audio. Object names start with the parent id: {parent_id}/{child_profile_id}/{file}
insert into storage.buckets (id, name, "public")
values ('study-audio', 'study-audio', false)
on conflict (id) do update set "public" = false;

create policy study_audio_owner_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'study-audio'
    and name like (auth.uid()::text || '/%')
  );

create policy study_audio_owner_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'study-audio'
    and name like (auth.uid()::text || '/%')
  );

create policy study_audio_owner_update
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'study-audio'
    and name like (auth.uid()::text || '/%')
  )
  with check (
    bucket_id = 'study-audio'
    and name like (auth.uid()::text || '/%')
  );

create policy study_audio_owner_delete
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'study-audio'
    and name like (auth.uid()::text || '/%')
  );

create policy study_audio_service_delete
  on storage.objects
  for delete
  to service_role
  using (bucket_id = 'study-audio');

create or replace function public.purge_study_audio_older_than_90_days()
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  delete from storage.objects
  where bucket_id = 'study-audio'
    and created_at < now() - interval '90 days';
end;
$$;

create or replace function public.purge_due_study_audio()
returns void
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  delete from storage.objects as object
  using public.storage_deletion_queue as due
  where due.deleted_at is null
    and due.delete_after <= now()
    and object.bucket_id = due.bucket_id
    and starts_with(object.name, due.object_prefix);

  update public.storage_deletion_queue
  set deleted_at = now()
  where deleted_at is null
    and delete_after <= now();
end;
$$;

revoke all on function public.purge_study_audio_older_than_90_days() from public, anon, authenticated;
revoke all on function public.purge_due_study_audio() from public, anon, authenticated;
grant execute on function public.purge_study_audio_older_than_90_days() to service_role;
grant execute on function public.purge_due_study_audio() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'study-audio-90-day') then
    perform cron.unschedule('study-audio-90-day');
  end if;
  perform cron.schedule(
    'study-audio-90-day',
    '15 3 * * *',
    'select public.purge_study_audio_older_than_90_days()'
  );

  if exists (select 1 from cron.job where jobname = 'study-audio-24h-withdrawal') then
    perform cron.unschedule('study-audio-24h-withdrawal');
  end if;
  perform cron.schedule(
    'study-audio-24h-withdrawal',
    '*/15 * * * *',
    'select public.purge_due_study_audio()'
  );
end
$$;
