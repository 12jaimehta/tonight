-- P0-9 DEL-06, DEL-16, DEL-15.
-- Deleting storage.objects removes metadata only. The storage-purge function
-- calls the Storage API and marks the queue row done after a list comes back empty.

create or replace function public.purge_study_audio_older_than_90_days()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  raise notice 'study-audio bytes are deleted by storage-purge, not by SQL';
end;
$$;

create or replace function public.purge_due_study_audio()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  raise notice 'study-audio bytes are deleted by storage-purge, not by SQL';
end;
$$;
