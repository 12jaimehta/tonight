-- P0-8 DEL-11, DEL-21, DEL-06, PRIV-05.
-- 24 hours is the SLA ceiling. The queue is due at enqueue time, not 24 hours later.

alter table public.storage_deletion_queue
  add column if not exists received_at timestamptz not null default now();

create table if not exists public.deletion_sla_alert (
  id uuid primary key default gen_random_uuid(),
  queue_id uuid not null,
  received_at timestamptz not null,
  completed_at timestamptz not null,
  late_by interval not null,
  raised_at timestamptz not null default now(),
  constraint deletion_sla_alert_queue unique (queue_id)
);

comment on table public.deletion_sla_alert is
  'Raised when completed_at - received_at is longer than 24 hours.';

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

  if old.scopes && array['server_speech', 'study_audio']::text[] then
    insert into public.storage_deletion_queue (
      parent_id,
      child_profile_id,
      bucket_id,
      object_prefix,
      delete_after,
      received_at
    ) values (
      old.parent_id,
      old.child_profile_id,
      'study-audio',
      old.parent_id::text || '/' || old.child_profile_id::text || '/',
      now(),
      now()
    );
  end if;

  return new;
end;
$$;

create or replace function public.raise_deletion_sla_alerts()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.deletion_sla_alert (queue_id, received_at, completed_at, late_by)
  select
    queue.id,
    coalesce(queue.received_at, queue.enqueued_at),
    queue.deleted_at,
    queue.deleted_at - coalesce(queue.received_at, queue.enqueued_at)
  from public.storage_deletion_queue as queue
  where queue.deleted_at is not null
    and queue.deleted_at - coalesce(queue.received_at, queue.enqueued_at) > interval '24 hours'
    and not exists (
      select 1 from public.deletion_sla_alert as alert where alert.queue_id = queue.id
    );
end;
$$;

revoke all on function public.raise_deletion_sla_alerts() from public, anon, authenticated;
grant execute on function public.raise_deletion_sla_alerts() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'study-audio-24h-withdrawal') then
    perform cron.unschedule('study-audio-24h-withdrawal');
  end if;
  -- Cadence is well inside the 24 hour ceiling. The row is already due.
  perform cron.schedule(
    'study-audio-24h-withdrawal',
    '*/5 * * * *',
    'select public.purge_due_study_audio(); select public.raise_deletion_sla_alerts()'
  );
end
$$;
