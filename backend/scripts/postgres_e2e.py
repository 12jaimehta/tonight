#!/usr/bin/env python3
"""Apply the migrations to Postgres and run child-delete → queue → purge.

Uses DATABASE_URL. On a stock Postgres image the Supabase edges are stubbed
and `create extension pg_cron` is skipped because that extension is not
installed. The migration files themselves are not changed. This does not
link or deploy a Supabase project.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
SCRIPTS = Path(__file__).resolve().parent


def main() -> None:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        raise SystemExit("DATABASE_URL is required")
    apply(url, SCRIPTS / "postgres_e2e_prelude.sql", stub_cron=False)
    for path in sorted(MIGRATIONS.glob("*.sql")):
        apply(url, path, stub_cron=True)
    apply(url, SCRIPTS / "postgres_e2e_test.sql", stub_cron=False)
    print("postgres e2e: child delete reached the queue and purge posted mode due")


def apply(url: str, path: Path, stub_cron: bool) -> None:
    sql = path.read_text(encoding="utf-8")
    if stub_cron:
        sql = sql.replace(
            "create extension if not exists pg_cron;",
            "-- stubbed for the stock Postgres CI service; see postgres_e2e_prelude.sql\nselect 1;",
        )
    completed = subprocess.run(
        ["psql", url, "-v", "ON_ERROR_STOP=1", "-f", "-"],
        input=sql,
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        sys.stderr.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        raise SystemExit(f"{path.name} failed")
    print(f"applied {path.name}")


if __name__ == "__main__":
    main()
