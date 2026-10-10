#!/usr/bin/env python3
"""DEL-11. The latest withdrawal function is due immediately and alerts after 24 hours."""

import pathlib
import re
import sys


def latest_function(text: str, name: str) -> str:
    pattern = re.compile(
        rf"create or replace function public\.{name}\(\).*?\$\$;",
        re.IGNORECASE | re.DOTALL,
    )
    matches = pattern.findall(text)
    if not matches:
        raise SystemExit(f"missing function {name}")
    return matches[-1]


def main() -> None:
    root = pathlib.Path(__file__).resolve().parents[1] / "supabase" / "migrations"
    combined = "\n".join(path.read_text(encoding="utf-8") for path in sorted(root.glob("*.sql")))
    withdrawal = latest_function(combined, "consent_record_before_update")
    if "+ interval '24 hours'" in withdrawal:
        raise SystemExit("withdrawal still delays deletion by 24 hours")
    if "now()" not in withdrawal:
        raise SystemExit("withdrawal does not enqueue with now()")
    if "deletion_sla_alert" not in combined:
        raise SystemExit("missing deletion_sla_alert")
    if "> interval '24 hours'" not in combined:
        raise SystemExit("missing the 24 hour SLA comparison")
    purge = latest_function(combined, "purge_due_study_audio")
    if "delete from storage.objects" in purge.lower():
        raise SystemExit("purge_due_study_audio still deletes storage metadata in SQL")
    if "invoke_storage_purge" not in purge:
        raise SystemExit("DEL-11 purge_due_study_audio does not call storage-purge")
    if "raise notice" in purge.lower():
        raise SystemExit("DEL-11 purge_due_study_audio is still a no-op notice")
    alerts = latest_function(combined, "raise_deletion_sla_alerts")
    if "deleted_at is null" not in alerts:
        raise SystemExit("DEL-21 stuck or failed deletions do not raise an alert")
    if "> interval '24 hours'" not in alerts:
        raise SystemExit("DEL-21 alert is missing the 24 hour comparison")
    entry = pathlib.Path(__file__).resolve().parents[1] / "supabase" / "functions" / "storage-purge" / "index.ts"
    entry_text = entry.read_text(encoding="utf-8")
    if "Deno.serve" not in entry_text or "handleStoragePurge" not in entry_text:
        raise SystemExit("DEL-11 storage-purge has no entry point")
    bucket = (root / "20261010130200_drop_study_audio_bucket.sql").read_text(encoding="utf-8").lower()
    for policy in (
        "study_audio_owner_select",
        "study_audio_owner_insert",
        "study_audio_owner_update",
        "study_audio_owner_delete",
    ):
        if f"drop policy if exists {policy}" not in bucket:
            raise SystemExit(f"missing drop of {policy}")
    if "delete from storage.buckets where id = 'study-audio'" not in bucket:
        raise SystemExit("study-audio bucket is still created for clients")
    erasure = (root / "20261010130300_delete_enqueues_erasure.sql").read_text(encoding="utf-8").lower()
    for needle in (
        "before delete on public.child_profile",
        "before delete on public.parent",
        "delete_all",
        "enqueue_child_erasure",
    ):
        if needle not in erasure:
            raise SystemExit(f"DEL-10 missing {needle}")
    entitlement = (root / "20261010130400_entitlement_service_role.sql").read_text(encoding="utf-8").lower()
    for needle in (
        "drop policy if exists entitlement_insert",
        "drop policy if exists entitlement_update",
        "revoke insert, update, delete on table public.entitlement from authenticated",
        "grant execute on function public.grant_entitlement",
    ):
        if needle not in entitlement:
            raise SystemExit(f"KIDS-08 missing {needle}")
    if "to authenticated" in entitlement and "grant execute" in entitlement:
        if "grant execute on function public.grant_entitlement" in entitlement and "to authenticated" in entitlement.split("grant execute", 1)[1]:
            raise SystemExit("authenticated role can still execute grant_entitlement")
    print("ok deletion SLA")


if __name__ == "__main__":
    main()
