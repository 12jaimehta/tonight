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
    print("ok deletion SLA")


if __name__ == "__main__":
    main()
