#!/usr/bin/env python3
"""Independent Stage B cross-check for the speech gate harness (MET-14).

Integer counts and reduced rationals. Child-level bootstrap, B = 10000, seed 20261010.
Decisions are compared before any decimal rounding.
"""

from __future__ import annotations

import json
import math
import pathlib
import sys
from typing import Any

B = 10_000
SEED = 20_261_010
AGREEMENT_BAR = (9, 10)
FAR_BAR = (1, 20)
FRR_BAR = (1, 10)


def rational(numerator: int, denominator: int) -> tuple[int, int]:
    if denominator == 0:
        raise ValueError("zero denominator")
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    factor = math.gcd(numerator, denominator)
    return (numerator // factor, denominator // factor)


def cmp_rational(left: tuple[int, int], right: tuple[int, int]) -> int:
    difference = left[0] * right[1] - right[0] * left[1]
    if difference > 0:
        return 1
    if difference < 0:
        return -1
    return 0


def text(value: tuple[int, int]) -> str:
    return f"{value[0]}/{value[1]}"


class HarnessError(Exception):
    def __init__(self, code: str, recording_id: str) -> None:
        super().__init__(f"{code} {recording_id}")
        self.code = code
        self.recording_id = recording_id


def _rate(numerator: int, denominator: int) -> tuple[int, int]:
    if denominator == 0:
        return (0, 1)
    return rational(numerator, denominator)


class LCG:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFF

    def next_u32(self) -> int:
        self.state = (self.state * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF
        return self.state


def _counts(rows: list[dict[str, Any]], engine: str) -> dict[str, int]:
    agreements = false_accepts = false_rejects = 0
    reference_correct = reference_incorrect = 0
    for row in rows:
        reference = bool(row["referenceCorrect"])
        heard = bool(row[engine])
        if heard == reference:
            agreements += 1
        if reference:
            reference_correct += 1
            if not heard:
                false_rejects += 1
        else:
            reference_incorrect += 1
            if heard:
                false_accepts += 1
    return {
        "paired": len(rows),
        "agreements": agreements,
        "falseAccepts": false_accepts,
        "referenceIncorrect": reference_incorrect,
        "falseRejects": false_rejects,
        "referenceCorrect": reference_correct,
    }


def _per_child_far(rows: list[dict[str, Any]], engine: str) -> dict[str, str]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        grouped.setdefault(row["childID"], []).append(row)
    rates: dict[str, str] = {}
    for child in sorted(grouped):
        counts = _counts(grouped[child], engine)
        rates[child] = text(_rate(counts["falseAccepts"], counts["referenceIncorrect"]))
    return rates


class _RationalKey:
    def __init__(self, value: tuple[int, int]) -> None:
        self.value = value

    def __lt__(self, other: "_RationalKey") -> bool:
        return cmp_rational(self.value, other.value) < 0


def _percentile_sorted(samples: list[tuple[int, int]]) -> tuple[tuple[int, int], tuple[int, int]]:
    ordered = sorted(samples, key=_RationalKey)
    lower = (25 * (B - 1)) // 1000
    upper = (975 * (B - 1) + 999) // 1000
    return ordered[lower], ordered[upper]


def _bootstrap_ci(
    groups: dict[str, list[dict[str, Any]]], children: list[str], engine: str
) -> dict[str, list[str]]:
    generator = LCG(SEED)
    agreements: list[tuple[int, int]] = []
    false_accepts: list[tuple[int, int]] = []
    for _ in range(B):
        sample: list[dict[str, Any]] = []
        for _pick in range(len(children)):
            draw = generator.next_u32()
            mixed = (draw ^ (draw >> 16)) & 0xFFFFFFFF
            child = children[mixed % len(children)]
            sample.extend(groups[child])
        counts = _counts(sample, engine)
        agreements.append(_rate(counts["agreements"], counts["paired"]))
        false_accepts.append(_rate(counts["falseAccepts"], counts["referenceIncorrect"]))
    agreement_ci = _percentile_sorted(agreements)
    far_ci = _percentile_sorted(false_accepts)
    return {
        "agreementCI": [text(agreement_ci[0]), text(agreement_ci[1])],
        "falseAcceptCI": [text(far_ci[0]), text(far_ci[1])],
    }


def _passes(agreement_ci: tuple[int, int], far_ci_upper: tuple[int, int], frr: tuple[int, int]) -> bool:
    return (
        cmp_rational(agreement_ci, AGREEMENT_BAR) >= 0
        and cmp_rational(far_ci_upper, FAR_BAR) <= 0
        and cmp_rational(frr, FRR_BAR) <= 0
    )


def evaluate(document: dict[str, Any]) -> dict[str, Any]:
    cohort = set(document["cohort"])
    recordings = document["recordings"]
    for row in recordings:
        if row.get("appleCorrect") is None or row.get("sarvamCorrect") is None:
            raise HarnessError("UNPAIRED_RECORDING", row["id"])
    for row in recordings:
        if row["childID"] not in cohort:
            raise HarnessError("OUT_OF_COHORT", row["id"])
    if not recordings:
        raise HarnessError("UNPAIRED_RECORDING", "")

    groups: dict[str, list[dict[str, Any]]] = {}
    for row in recordings:
        groups.setdefault(row["childID"], []).append(row)
    children = sorted(groups)

    engines: dict[str, Any] = {}
    passes: dict[str, bool] = {}
    agreement_point: dict[str, tuple[int, int]] = {}
    for engine, field in (("apple", "appleCorrect"), ("sarvam", "sarvamCorrect")):
        counts = _counts(recordings, field)
        agreement = _rate(counts["agreements"], counts["paired"])
        far = _rate(counts["falseAccepts"], counts["referenceIncorrect"])
        frr = _rate(counts["falseRejects"], counts["referenceCorrect"])
        intervals = _bootstrap_ci(groups, children, field)
        agreement_ci = tuple(int(part) for part in intervals["agreementCI"][0].split("/"))
        far_upper = tuple(int(part) for part in intervals["falseAcceptCI"][1].split("/"))
        engines[engine] = {
            **counts,
            "agreement": text(agreement),
            "falseAcceptRate": text(far),
            "falseRejectRate": text(frr),
            "perChildFalseAccept": _per_child_far(recordings, field),
            **intervals,
        }
        agreement_point[engine] = agreement
        passes[engine] = _passes(agreement_ci, far_upper, frr)

    if passes["apple"] and passes["sarvam"]:
        order = cmp_rational(agreement_point["apple"], agreement_point["sarvam"])
        decision = "APPLE" if order >= 0 else "SARVAM"
    elif passes["apple"]:
        decision = "APPLE"
    elif passes["sarvam"]:
        decision = "SARVAM"
    else:
        decision = "NO_GO"
    return {"decision": decision, "apple": engines["apple"], "sarvam": engines["sarvam"]}


def homogeneous(child_count: int, items: int, apple_correct: int, sarvam_correct: int) -> dict[str, Any]:
    """Every item is reference-correct. The first N engine answers match."""
    recordings = []
    cohort = []
    for child_index in range(child_count):
        child = f"c{child_index:02d}"
        cohort.append(child)
        for item in range(items):
            recordings.append(
                {
                    "id": f"{child}-{item}",
                    "childID": child,
                    "referenceCorrect": True,
                    "appleCorrect": item < apple_correct,
                    "sarvamCorrect": item < sarvam_correct,
                }
            )
    return {"cohort": cohort, "recordings": recordings}


def apple_pass() -> dict[str, Any]:
    """Apple matches every item. Sarvam false-accepts the incorrect references."""
    recordings = []
    cohort = []
    for child_index in range(8):
        child = f"c{child_index}"
        cohort.append(child)
        for item in range(8):
            reference = item < 6
            recordings.append(
                {
                    "id": f"{child}-{item}",
                    "childID": child,
                    "referenceCorrect": reference,
                    "appleCorrect": reference,
                    "sarvamCorrect": True,
                }
            )
    return {"cohort": cohort, "recordings": recordings}


def sarvam_pass() -> dict[str, Any]:
    document = apple_pass()
    for row in document["recordings"]:
        row["appleCorrect"], row["sarvamCorrect"] = row["sarvamCorrect"], row["appleCorrect"]
    return document


def no_go() -> dict[str, Any]:
    document = homogeneous(4, 10, 4, 4)
    return document


def close_call() -> dict[str, Any]:
    """901/1000 vs 900/1000. Both round to 0.90 at two places. Sarvam is greater before rounding."""
    return homogeneous(4, 1000, 900, 901)


def unpaired() -> dict[str, Any]:
    document = homogeneous(1, 1, 1, 1)
    document["recordings"][0]["sarvamCorrect"] = None
    return document


def out_of_cohort() -> dict[str, Any]:
    document = homogeneous(1, 1, 1, 1)
    document["cohort"] = ["someone-else"]
    return document


FIXTURES = {
    "apple_pass": apple_pass,
    "sarvam_pass": sarvam_pass,
    "no_go": no_go,
    "close_call": close_call,
    "unpaired": unpaired,
    "out_of_cohort": out_of_cohort,
}


def fixture_dir() -> pathlib.Path:
    return (
        pathlib.Path(__file__).resolve().parents[1]
        / "Packages"
        / "Tonight"
        / "Tests"
        / "GateHarnessTests"
        / "Fixtures"
    )


def main() -> None:
    write = "--write" in sys.argv
    root = fixture_dir()
    root.mkdir(parents=True, exist_ok=True)
    failed = False
    for name, builder in FIXTURES.items():
        document = builder()
        source = root / f"{name}.json"
        golden = root / f"{name}.golden.json"
        if write or not source.exists():
            source.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        loaded = json.loads(source.read_text(encoding="utf-8"))
        try:
            report = evaluate(loaded)
            payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
        except HarnessError as error:
            payload = json.dumps({"error": error.code, "recordingID": error.recording_id}, indent=2) + "\n"
        if write or not golden.exists():
            golden.write_text(payload, encoding="utf-8")
            print(f"wrote {name}")
            continue
        expected = golden.read_text(encoding="utf-8")
        if payload != expected:
            failed = True
            print(f"MISMATCH {name}", file=sys.stderr)
        else:
            print(f"ok {name} {json.loads(payload).get('decision') or json.loads(payload).get('error')}")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
