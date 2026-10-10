-- P0-8 DEL-11, DEL-21.
-- Cron already calls purge_due_study_audio(). That function now invokes the
-- storage-purge Edge Function, which deletes object bytes. A row that is still
-- unfinished after 24 hours raises the same alert as a late completion.

alter table public.deletion_sla_alert
  alter column completed_at drop not null;

comment on table public.deletion_sla_alert is
  'Raised when a deletion finishes after 24 hours, or is still unfinished after 24 hours.';

create or replace function public.invoke_storage_purge(mode text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  base_url text := current_setting('app.settings.supabase_url', true);
  service_key text := current_setting('app.settings.service_role_key', true);
begin
  if base_url is null or service_key is null or length(base_url) = 0 or length(service_key) = 0 then
    raise exception 'storage-purge is not configured'
      using errcode = '55000';
  end if;
  perform net.http_post(
    url := rtrim(base_url, '/') || '/functions/v1/storage-purge',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || service_key,
      'apikey', service_key
    ),
    body := jsonb_build_object('mode', mode)
  );
end;
$$;

create or replace function public.purge_due_study_audio()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.invoke_storage_purge('due');
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
    coalesce(queue.deleted_at, now()) - coalesce(queue.received_at, queue.enqueued_at)
  from public.storage_deletion_queue as queue
  where (
      (
        queue.deleted_at is not null
        and queue.deleted_at - coalesce(queue.received_at, queue.enqueued_at) > interval '24 hours'
      )
      or (
        queue.deleted_at is null
        and now() - coalesce(queue.received_at, queue.enqueued_at) > interval '24 hours'
      )
    )
    and not exists (
      select 1 from public.deletion_sla_alert as alert where alert.queue_id = queue.id
    );
end;
$$;

revoke all on function public.invoke_storage_purge(text) from public, anon, authenticated;
revoke all on function public.purge_due_study_audio() from public, anon, authenticated;
revoke all on function public.raise_deletion_sla_alerts() from public, anon, authenticated;
grant execute on function public.invoke_storage_purge(text) to service_role;
grant execute on function public.purge_due_study_audio() to service_role;
grant execute on function public.raise_deletion_sla_alerts() to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'study-audio-24h-withdrawal') then
    perform cron.unschedule('study-audio-24h-withdrawal');
  end if;
  -- Alerts run even when the HTTP call is not configured yet.
  perform cron.schedule(
    'study-audio-24h-withdrawal',
    '*/5 * * * *',
    'select public.raise_deletion_sla_alerts(); select public.purge_due_study_audio()'
  );
end
$$;
