-- P0-8 DEL-21, DEL-11.
-- The purge cron reads the project URL and service role key from Vault.
-- Hosted Supabase does not allow ALTER DATABASE ... SET app.settings.*.
-- Local tests may still set those with set_config or ALTER DATABASE.
-- A missing value raises a clear error from invoke_storage_purge.
-- Alerts are a different cron job, so that error does not roll back the alert insert.

create or replace function public.storage_purge_setting(setting_name text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  from_vault text;
  from_setting text;
begin
  begin
    execute
      'select decrypted_secret from vault.decrypted_secrets where name = $1 limit 1'
      into from_vault
      using setting_name;
  exception
    when sqlstate '42P01' or sqlstate '3F000' then
      from_vault := null;
  end;
  if from_vault is not null and length(btrim(from_vault)) > 0 then
    return btrim(from_vault);
  end if;
  from_setting := current_setting('app.settings.' || setting_name, true);
  if from_setting is null then
    return null;
  end if;
  return nullif(btrim(from_setting), '');
end;
$$;

create or replace function public.invoke_storage_purge(mode text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  base_url text := public.storage_purge_setting('supabase_url');
  service_key text := public.storage_purge_setting('service_role_key');
begin
  if base_url is null or service_key is null then
    raise exception
      'storage-purge is not configured: set Vault secrets supabase_url and service_role_key, or app.settings.supabase_url and app.settings.service_role_key'
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

revoke all on function public.storage_purge_setting(text) from public, anon, authenticated;
revoke all on function public.invoke_storage_purge(text) from public, anon, authenticated;
grant execute on function public.storage_purge_setting(text) to service_role;
grant execute on function public.invoke_storage_purge(text) to service_role;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'study-audio-24h-withdrawal') then
    perform cron.unschedule('study-audio-24h-withdrawal');
  end if;
  if exists (select 1 from cron.job where jobname = 'deletion-sla-alerts') then
    perform cron.unschedule('deletion-sla-alerts');
  end if;
  if exists (select 1 from cron.job where jobname = 'storage-purge-due') then
    perform cron.unschedule('storage-purge-due');
  end if;
  perform cron.schedule(
    'deletion-sla-alerts',
    '*/5 * * * *',
    'select public.raise_deletion_sla_alerts()'
  );
  perform cron.schedule(
    'storage-purge-due',
    '*/5 * * * *',
    'select public.purge_due_study_audio()'
  );
end
$$;
