-- P0-11 DEL-10, KIDS-06, PRIV-05.
-- Deleting a child or the parent account must enqueue storage erasure.
-- A cascade delete of consent_record would otherwise skip the withdrawal trigger.

alter table public.consent_audit drop constraint consent_audit_action;
alter table public.consent_audit add constraint consent_audit_action
  check (action in ('granted', 'withdrawn', 'delete_all'));

create or replace function public.enqueue_child_erasure(parent uuid, child uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  prefix text := parent::text || '/' || child::text || '/';
begin
  if not exists (
    select 1
    from public.storage_deletion_queue as queued
    where queued.child_profile_id = child
      and queued.object_prefix = prefix
      and queued.deleted_at is null
  ) then
    insert into public.storage_deletion_queue (
      parent_id,
      child_profile_id,
      bucket_id,
      object_prefix,
      delete_after,
      received_at
    ) values (
      parent,
      child,
      'study-audio',
      prefix,
      now(),
      now()
    );
  end if;

  insert into public.consent_audit (
    consent_record_id,
    parent_id,
    child_profile_id,
    action,
    version,
    scopes,
    at,
    method
  )
  select
    record.id,
    record.parent_id,
    record.child_profile_id,
    'delete_all',
    record.version,
    record.scopes,
    now(),
    'delete_all'
  from public.consent_record as record
  where record.child_profile_id = child;
end;
$$;

create or replace function public.child_profile_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_child_erasure(old.parent_id, old.id);
  return old;
end;
$$;

create or replace function public.parent_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_child_erasure(old.id, child.id)
  from public.child_profile as child
  where child.parent_id = old.id;
  return old;
end;
$$;

drop trigger if exists child_profile_enqueue_deletion on public.child_profile;
create trigger child_profile_enqueue_deletion
  before delete on public.child_profile
  for each row
  execute function public.child_profile_before_delete();

drop trigger if exists parent_enqueue_deletion on public.parent;
create trigger parent_enqueue_deletion
  before delete on public.parent
  for each row
  execute function public.parent_before_delete();

revoke all on function public.enqueue_child_erasure(uuid, uuid) from public, anon, authenticated;
revoke all on function public.child_profile_before_delete() from public, anon, authenticated;
revoke all on function public.parent_before_delete() from public, anon, authenticated;
