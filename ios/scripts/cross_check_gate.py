#!/usr/bin/env python3
"""Compare GateHarness decisions with the pinned independent checker.

Decision, seed, and interval bounds must match on the shared fixtures.
QA goldens (tests/gate-goldens/compare.py) compare warnings by child id and
fail the job. This script does not compare warning text.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: cross_check_gate.py <gate-harness> <checker-root>", file=sys.stderr)
        return 2
    binary = Path(sys.argv[1])
    checker = Path(sys.argv[2])
    repo = Path(__file__).resolve().parents[2]
    fixtures = sorted((checker / "examples").glob("*.json"))
    fixtures += sorted((repo / "ios/Packages/Tonight/Tests/GateHarnessTests/Fixtures").glob("met*.json"))
    if not fixtures:
        print("no shared fixtures", file=sys.stderr)
        return 1
    failed = 0
    for path in fixtures:
        swift = run([str(binary), str(path)])
        python = run(
            [sys.executable, "-m", "gate_check_independent", str(path), "--format", "json"],
            env_pythonpath=str(checker),
        )
        problems = differences(swift, python)
        label = path.name
        if problems:
            failed += 1
            print(f"FAIL {label}")
            for problem in problems:
                print(f"  {problem}")
        else:
            token = swift.get("decision") or swift.get("error")
            print(f"OK {label} {token}")
    print(f"{len(fixtures) - failed}/{len(fixtures)} shared fixtures agree on the decision")
    return 1 if failed else 0


def run(command: list[str], env_pythonpath: str | None = None) -> dict:
    import os

    env = os.environ.copy()
    if env_pythonpath:
        current = env.get("PYTHONPATH", "")
        env["PYTHONPATH"] = env_pythonpath if not current else env_pythonpath + os.pathsep + current
    completed = subprocess.run(command, capture_output=True, text=True, env=env)
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"{command[0]} did not print JSON for the fixture ({exc}): {completed.stdout!r} {completed.stderr!r}"
        ) from exc
    if not isinstance(payload, dict):
        raise SystemExit(f"{command[0]} printed {type(payload).__name__}, expected an object")
    return payload


def differences(swift: dict, python: dict) -> list[str]:
    problems: list[str] = []
    swift_token = swift.get("decision") or swift.get("error")
    python_token = python.get("decision") or python.get("error")
    if swift_token != python_token:
        problems.append(f"decision {swift_token} != {python_token}")
        return problems
    if "decision" not in swift:
        return problems
    if swift.get("seed") != python.get("seed"):
        problems.append(f"seed {swift.get('seed')} != {python.get('seed')}")
    for side in ("low", "high"):
        left = (swift.get("interval") or {}).get(side)
        right = (python.get("interval") or {}).get(side)
        if left != right:
            problems.append(f"interval.{side} {left} != {right}")
    return problems


if __name__ == "__main__":
    raise SystemExit(main())
