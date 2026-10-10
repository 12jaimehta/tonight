# Tonight backend

Local Supabase project for Tonight. Nothing here is deployed, and this repo is not linked to a live project.

`auth.uid()` (and the `auth.users` account row it belongs to) and Storage are the only Supabase-shaped pieces. The tables, checks, triggers, and deletion jobs are ordinary Postgres.

## What is here

`backend/supabase` is the CLI project. `config.toml` lives in that directory.

The migration creates:

- `parent`. One row per account. `id` is the auth user id. The table has no child content.
- `child_profile`. Nickname, age band, and school class. v1 only allows the age band `6-8`. School class is text, not a Postgres enum. There is no date of birth, photo, homework text, audio, or transcript column.
- `consent_record`. A parent grants `on_device_speech`, `server_speech`, and `study_audio` in any non-empty combination. Withdrawing sets `withdrawn_at` once, from the database clock, and writes a `consent_audit` row. Any other update is rejected, and a second withdrawal is rejected.
- `consent_audit`. Insert-only. A trigger rejects `UPDATE` and `DELETE` for every role, including the service role. The audit has no foreign key, so deleting a parent does not try to delete the audit.
- `entitlement`. StoreKit product, status, and expiry for that parent.
- `storage_deletion_queue`. Holds child prefixes that should leave Storage 24 hours after a withdrawal.

Row level security is on for every table. A parent can see and write only rows with `parent_id = auth.uid()`, and only the parent row whose `id = auth.uid()`. There is no policy for `anon`. The service role bypasses RLS, which is what the deletion jobs use.

`study-audio` is a private bucket (`public = false`). An object name has to start with the parent id (`auth.uid()::text || '/%'`). The path the deletion job understands is `{parent_id}/{child_profile_id}/{filename}`. The service role may delete objects in that bucket.

Two `pg_cron` jobs run in the database:

- Once a day, delete `study-audio` objects older than 90 days.
- Every 15 minutes, delete objects whose queued prefix is due. The queue is filled only when a consent row that includes `server_speech` or `study_audio` is withdrawn. `delete_after` is `withdrawn_at` plus 24 hours. Withdrawing `on_device_speech` alone does not enqueue anything.

The CLI image already preloads `pg_cron`. This CLI version has no `config.toml` switch for the extension, so the migration runs `create extension if not exists pg_cron` and schedules the jobs.

Apple sign-in and email OTP are enabled in `config.toml`. The Apple client id and secret are `env(APPLE_CLIENT_ID)` and `env(APPLE_SECRET)`. Phone sign-up is off. Real values stay out of git. Copy `backend/.env.example` to `backend/supabase/.env` and leave the values empty for a local start.

`functions/sarvam-proxy` is the Edge Function the app calls at `/functions/v1/sarvam-proxy`. It requires `Authorization: Bearer` with a parent JWT. The body identifies the child with `child_profile_id` and includes `audio_base64`. The function checks that this parent has an active `server_speech` consent for that child: not withdrawn, and `version` present. If not, it returns 403 and does not call Sarvam. When consent is active it forwards the audio to Sarvam with `SARVAM_API_KEY`. The key is read from the environment only. The function does not write audio to Storage, disk, or the database. Its own log line is latency and cost, and that line does not include audio, transcript text, or a nickname. On the hosted project, keep request-body logging off, because the request body contains audio. Sarvam's transcript response has no cost field, so the cost is an estimate from the WAV duration at the published rate of ₹30 per hour, rounded up to the next second. If a response includes a numeric `cost`, that value is logged instead.

## Run locally

From `backend/supabase`:

```sh
cp ../.env.example .env
supabase start
```

Do not run `supabase link`. Do not deploy. `supabase start` is the whole local loop: database, Auth, Storage, and the function runtime. Email OTP shows up in the local mail inbox (Inbucket), not in a real inbox.

Function tests do not use the network. From `backend/supabase/functions/sarvam-proxy`:

```sh
deno test --deny-net
```

## Week-1 checks

Before any real project is used:

- The live project is pinned to Mumbai, AWS region `ap-south-1`.
- Storage encryption at rest is on.

`project-ref` is not chosen yet. When it exists, the iOS app should call:

```text
https://<project-ref>.supabase.co/functions/v1/sarvam-proxy
```

## Deletion cron settings

`storage-purge` is called by `public.invoke_storage_purge`. That function reads two values, in this order:

1. Vault secrets named `supabase_url` and `service_role_key` (`vault.decrypted_secrets`).
2. Database settings `app.settings.supabase_url` and `app.settings.service_role_key`, for a local database only. Hosted Supabase rejects `ALTER DATABASE ... SET app.settings.*`.

If either value is missing, the function raises `storage-purge is not configured` and does not call the network. Set them in Vault before relying on the cron:

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'supabase_url');
select vault.create_secret('<service-role-key>', 'service_role_key');
```

On the hosted project the same two names can be created in the Vault UI. Do not put the service role key in the iOS app. Edge Function runtime still uses the injected `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` environment variables.

Alerts (`deletion-sla-alerts`) and the purge (`storage-purge-due`) are separate cron jobs. A purge error does not roll back an alert insert.

The `study-audio` bucket is gone. Queue rows use `bucket_id = 'none'`. The purge marks those rows done without listing Storage.

## Later, when the Mumbai project is created

These are later steps. They are not part of local setup and they are not run from this scaffold.

1. Create the Supabase project in `ap-south-1`.
2. Confirm the region and that Storage encryption at rest is on.
3. Enable `pg_cron` on that project if `create extension` is not already allowed.
4. Put `SARVAM_API_KEY`, `APPLE_CLIENT_ID`, `APPLE_SECRET`, and `SUPABASE_JWT_SECRET` in the project secrets. Do not put them in the app.
5. From `backend/supabase`, run `supabase db push` to apply the migration.
6. Deploy the function with `supabase functions deploy sarvam-proxy`.

The iOS tree may still name a different path. This backend's path is the one above.
