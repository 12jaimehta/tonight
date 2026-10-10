-- Child withdrawal, child delete, and the purge call, on the migrated schema.
\set ON_ERROR_STOP on

insert into auth.users (id)
values ('11111111-1111-1111-1111-111111111111');

insert into public.parent (id)
values ('11111111-1111-1111-1111-111111111111');

insert into public.child_profile (id, parent_id, nickname)
values (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  'Aarav'
);

insert into public.consent_record (
  id, parent_id, child_profile_id, version, scopes, method
) values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  '22222222-2222-2222-2222-222222222222',
  '2026-10-09',
  array['on_device_speech', 'server_speech'],
  'screen'
);

select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
set role authenticated;

update public.consent_record
set withdrawn_at = now()
where id = '33333333-3333-3333-3333-333333333333';

reset role;

do $$
declare
  queued int;
begin
  select count(*) into queued
  from public.storage_deletion_queue
  where child_profile_id = '22222222-2222-2222-2222-222222222222'
    and deleted_at is null;
  if queued <> 1 then
    raise exception 'withdrawal should enqueue one row, got %', queued;
  end if;
  if not exists (
    select 1 from public.consent_audit
    where child_profile_id = '22222222-2222-2222-2222-222222222222'
      and action = 'withdrawn'
  ) then
    raise exception 'withdrawal should write a withdrawn audit row';
  end if;
end
$$;

set role authenticated;

delete from public.child_profile
where id = '22222222-2222-2222-2222-222222222222';

reset role;

do $$
declare
  queued int;
begin
  select count(*) into queued
  from public.storage_deletion_queue
  where child_profile_id = '22222222-2222-2222-2222-222222222222'
    and deleted_at is null;
  if queued <> 1 then
    raise exception 'child delete should keep the single queued row, got %', queued;
  end if;
  if not exists (
    select 1 from public.consent_audit
    where child_profile_id = '22222222-2222-2222-2222-222222222222'
      and action = 'delete_all'
  ) then
    raise exception 'child delete should write a delete_all audit row';
  end if;
end
$$;

do $$
begin
  perform public.purge_due_study_audio();
  raise exception 'purge should fail before it is configured';
exception
  when sqlstate '55000' then
    if position('storage-purge is not configured' in sqlerrm) = 0 then
      raise exception 'unexpected purge error: %', sqlerrm;
    end if;
end
$$;

select set_config('app.settings.supabase_url', 'https://project-ref.supabase.co', false);
select set_config('app.settings.service_role_key', 'service-role-key', false);
select public.purge_due_study_audio();

do $$
declare
  call net.http_request;
begin
  select * into call from net.http_request order by id desc limit 1;
  if call.url is distinct from 'https://project-ref.supabase.co/functions/v1/storage-purge' then
    raise exception 'purge called %', call.url;
  end if;
  if call.body->>'mode' is distinct from 'due' then
    raise exception 'purge body %', call.body;
  end if;
  if call.headers->>'Authorization' is distinct from 'Bearer service-role-key' then
    raise exception 'purge authorization %', call.headers;
  end if;
end
$$;
