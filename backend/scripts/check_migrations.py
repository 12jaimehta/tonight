#!/usr/bin/env python3
"""Offline balance check for SQL migrations. Does not start Docker or call supabase."""

import pathlib


def check(text: str, path: str) -> None:
    i = 0
    n = len(text)
    paren = 0
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if ch == "-" and nxt == "-":
            newline = text.find("\n", i)
            if newline < 0:
                break
            i = newline
            continue
        if ch == "/" and nxt == "*":
            end = text.find("*/", i + 2)
            if end < 0:
                raise SystemExit(f"{path}: unterminated block comment")
            i = end + 2
            continue
        if ch == "'":
            i += 1
            while i < n:
                if text[i] == "'":
                    if i + 1 < n and text[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            else:
                raise SystemExit(f"{path}: unterminated string")
            continue
        if ch == "$":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            if j < n and text[j] == "$":
                tag = text[i : j + 1]
                end = text.find(tag, j + 1)
                if end < 0:
                    raise SystemExit(f"{path}: unterminated dollar quote {tag}")
                i = end + len(tag)
                continue
        if ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
            if paren < 0:
                raise SystemExit(f"{path}: extra closing parenthesis")
        i += 1
    if paren != 0:
        raise SystemExit(f"{path}: unbalanced parentheses ({paren})")


def main() -> None:
    root = pathlib.Path(__file__).resolve().parents[1] / "supabase" / "migrations"
    files = sorted(root.glob("*.sql"))
    if not files:
        raise SystemExit(f"no SQL migrations in {root}")
    created = False
    for path in files:
        text = path.read_text(encoding="utf-8")
        if not text.strip():
            raise SystemExit(f"{path}: empty migration")
        if ";" not in text:
            raise SystemExit(f"{path}: no SQL statement")
        lowered = text.lower()
        if "create table" in lowered:
            created = True
        if not any(token in lowered for token in ("create table", "alter table", "create or replace function", "drop policy")):
            raise SystemExit(f"{path}: expected a schema change")
        check(text, str(path))
        print(f"ok {path.name}")
    if not created:
        raise SystemExit("expected at least one create table")
    print(f"checked {len(files)} migration(s)")


if __name__ == "__main__":
    main()
