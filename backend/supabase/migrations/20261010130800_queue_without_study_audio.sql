-- P0-9 DEL-06, DEL-15, DEL-16.
-- The study-audio bucket was removed. New queue rows must not name it.
-- Rows that already name it are rewritten so a later purge can finish them
-- without listing a bucket that is not there.

alter table public.storage_deletion_queue
  alter column bucket_id set default 'none';

update public.storage_deletion_queue
set bucket_id = 'none'
where bucket_id = 'study-audio';

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
      'none',
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

revoke all on function public.enqueue_child_erasure(uuid, uuid) from public, anon, authenticated;
grant execute on function public.enqueue_child_erasure(uuid, uuid) to service_role;
