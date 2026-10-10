-- P0-9 DEL-16, DEL-06, DEL-15.
-- The 90-day job deletes object bytes through storage-purge. It does not
-- stop at deleting storage.objects rows.

create or replace function public.purge_study_audio_older_than_90_days()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.invoke_storage_purge('retention');
end;
$$;

revoke all on function public.purge_study_audio_older_than_90_days() from public, anon, authenticated;
grant execute on function public.purge_study_audio_older_than_90_days() to service_role;

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
end
$$;
