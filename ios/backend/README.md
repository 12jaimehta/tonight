# Tonight backend (planned)

Supabase in Mumbai, region `ap-south-1`. This project has not been created. The notes below are the setup to apply when it is.

Placeholder project URL: `https://project-ref.supabase.co`. The label `project-ref` stands in for the real project ref.

## Auth

Sign in with Apple and email OTP.

## Postgres

Tables `parent`, `consent_record`, and `entitlement`, with row level security.

## Storage

A private Storage bucket for study audio, with a 90-day deletion job.

## Sarvam proxy

Edge Function at `/functions/v1/sarvam-proxy`. The Sarvam key stays in the function, not in the app. The request and response the iOS client already assumes are in `sarvam-proxy.contract.json`.

## Week-1 checks

- Region pinning (`ap-south-1`)
- Storage encryption

## iOS client

The app talks to this project with `URLSession` only. The Supabase Swift SDK is not added yet.
