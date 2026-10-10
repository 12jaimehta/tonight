-- Stubs for a stock Postgres service container. Supabase's auth, storage, pg_cron,
-- and pg_net are not installed there. The migration files are not edited.

create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;

create schema if not exists storage;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text,
  created_at timestamptz not null default now()
);

create schema if not exists cron;

create table if not exists cron.job (
  jobid bigint generated always as identity primary key,
  jobname text unique,
  schedule text not null,
  command text not null
);

create or replace function cron.schedule(job_name text, schedule text, command text)
returns bigint
language plpgsql
as $$
declare
  id bigint;
begin
  delete from cron.job where jobname = job_name;
  insert into cron.job (jobname, schedule, command)
  values (job_name, schedule, command)
  returning jobid into id;
  return id;
end;
$$;

create or replace function cron.unschedule(job_name text)
returns boolean
language plpgsql
as $$
begin
  delete from cron.job where jobname = job_name;
  return found;
end;
$$;

create schema if not exists net;

create table if not exists net.http_request (
  id bigint generated always as identity primary key,
  url text not null,
  headers jsonb not null,
  body jsonb not null
);

create or replace function net.http_post(url text, headers jsonb, body jsonb)
returns bigint
language plpgsql
as $$
declare
  request_id bigint;
begin
  insert into net.http_request (url, headers, body)
  values (url, headers, body)
  returning net.http_request.id into request_id;
  return request_id;
end;
$$;
