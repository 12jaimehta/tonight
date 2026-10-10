#!/usr/bin/env python3
"""Stage B speech gate, written from the decision table.

Counts stay integers. Rates stay reduced ratios. A child-level bootstrap
(B = 10000, seed 20261010) supplies intervals. This file does not follow
the Swift source; the shared fixtures are the cross-check.

Pass when the pooled agreement is at least 9/10, the pooled false-accept
rate is at most 1/20, the pooled false-reject rate is at most 1/10, and
every child with an incorrect reference is at most 1/10 false accepts.
A child with no incorrect reference is n/a and is skipped.

SARVAM only when both engines pass, Sarvam's agreement is at least
Apple + 5 percentage points, and the paired bootstrap interval of that
gap sits strictly above zero. Otherwise APPLE when Apple passes, else NO_GO.
"""

from __future__ import annotations

import json
import pathlib
import sys
from dataclasses import dataclass


BOOTSTRAP_DRAWS = 10_000
BOOTSTRAP_SEED = 20_261_010
SCORING_VERSION = 2
AGREEMENT_FLOOR = (9, 10)
POOLED_FALSE_ACCEPT_CEILING = (1, 20)
FALSE_REJECT_CEILING = (1, 10)
CHILD_FALSE_ACCEPT_CEILING = (1, 10)
SARVAM_MARGIN = (1, 20)
COHORT_AGES = range(6, 9)
COHORT_CLASSES = {"1", "2", "3"}


class Ratio:
    """Reduced ratio. Ordering uses cross-multiplication, never floats."""

    def __init__(self, numerator: int, denominator: int) -> None:
        if denominator == 0:
            raise ValueError("zero denominator")
        if denominator < 0:
            numerator, denominator = -numerator, -denominator
        factor = _gcd(abs(numerator), denominator)
        self.numerator = numerator // factor
        self.denominator = denominator // factor

    def text(self) -> str:
        return f"{self.numerator}/{self.denominator}"

    def cmp(self, other: "Ratio") -> int:
        gap = self.numerator * other.denominator - other.numerator * self.denominator
        return (gap > 0) - (gap < 0)

    def ge(self, other: "Ratio") -> bool:
        return self.cmp(other) >= 0

    def le(self, other: "Ratio") -> bool:
        return self.cmp(other) <= 0

    def gt(self, other: "Ratio") -> bool:
        return self.cmp(other) > 0

    def minus(self, other: "Ratio") -> "Ratio":
        return Ratio(
            self.numerator * other.denominator - other.numerator * self.denominator,
            self.denominator * other.denominator,
        )


def _gcd(left: int, right: int) -> int:
    while right:
        left, right = right, left % right
    return left or 1


def _zero() -> Ratio:
    return Ratio(0, 1)


class Rejected(Exception):
    def __init__(self, code: str, recording_id: str) -> None:
        super().__init__(code)
        self.code = code
        self.recording_id = recording_id


@dataclass
class Tally:
    paired: int = 0
    agreements: int = 0
    false_accepts: int = 0
    reference_incorrect: int = 0
    false_rejects: int = 0
    reference_correct: int = 0


class Draw:
    """Numerical Recipes LCG, masked to 32 bits. Seed 20261010."""

    def __init__(self, seed: int = BOOTSTRAP_SEED) -> None:
        self.state = seed & 0xFFFFFFFF

    def __iter__(self):
        return self

    def __next__(self) -> int:
        self.state = (self.state * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF
        return self.state


def _heard(row: dict, field: str) -> bool:
    return bool(row[field])


def tally(rows: list[dict], field: str) -> Tally:
    result = Tally(paired=len(rows))
    for row in rows:
        reference = bool(row["referenceCorrect"])
        heard = _heard(row, field)
        if heard == reference:
            result.agreements += 1
        if reference:
            result.reference_correct += 1
            if not heard:
                result.false_rejects += 1
        else:
            result.reference_incorrect += 1
            if heard:
                result.false_accepts += 1
    return result


def _portion(numerator: int, denominator: int) -> Ratio:
    if denominator == 0:
        return _zero()
    return Ratio(numerator, denominator)


class _Order:
    def __init__(self, ratio: Ratio) -> None:
        self.ratio = ratio

    def __lt__(self, other: "_Order") -> bool:
        return self.ratio.cmp(other.ratio) < 0


def _band_exact(samples: list[Ratio]) -> tuple[Ratio, Ratio]:
    ordered = sorted(samples, key=lambda item: _Order(item))
    low = (25 * (BOOTSTRAP_DRAWS - 1)) // 1000
    high = (975 * (BOOTSTRAP_DRAWS - 1) + 999) // 1000
    return ordered[low], ordered[high]


def _child_index(draw: int, count: int) -> int:
    mixed = (draw ^ (draw >> 16)) & 0xFFFFFFFF
    return mixed % count


def _resample(groups: dict[str, list[dict]], children: list[str], stream: Draw) -> list[dict]:
    picked: list[dict] = []
    width = len(children)
    for _ in range(width):
        picked.extend(groups[children[_child_index(next(stream), width)]])
    return picked


def _intervals(groups: dict[str, list[dict]], children: list[str], field: str) -> dict[str, list[str]]:
    stream = Draw()
    agreements: list[Ratio] = []
    false_accepts: list[Ratio] = []
    for _ in range(BOOTSTRAP_DRAWS):
        sample = _resample(groups, children, stream)
        counts = tally(sample, field)
        agreements.append(_portion(counts.agreements, counts.paired))
        false_accepts.append(_portion(counts.false_accepts, counts.reference_incorrect))
    agreement_band = _band_exact(agreements)
    false_accept_band = _band_exact(false_accepts)
    return {
        "agreementCI": [agreement_band[0].text(), agreement_band[1].text()],
        "falseAcceptCI": [false_accept_band[0].text(), false_accept_band[1].text()],
    }


def _gap_interval(groups: dict[str, list[dict]], children: list[str]) -> tuple[Ratio, Ratio]:
    stream = Draw()
    gaps: list[Ratio] = []
    for _ in range(BOOTSTRAP_DRAWS):
        sample = _resample(groups, children, stream)
        apple = tally(sample, "appleCorrect")
        sarvam = tally(sample, "sarvamCorrect")
        gaps.append(
            _portion(sarvam.agreements, sarvam.paired).minus(_portion(apple.agreements, apple.paired))
        )
    return _band_exact(gaps)


def _child_false_accepts(rows: list[dict], field: str) -> dict[str, str]:
    grouped: dict[str, list[dict]] = {}
    for row in rows:
        grouped.setdefault(row["childID"], []).append(row)
    labelled: dict[str, str] = {}
    for child in sorted(grouped):
        counts = tally(grouped[child], field)
        labelled[child] = "n/a" if counts.reference_incorrect == 0 else _portion(
            counts.false_accepts, counts.reference_incorrect
        ).text()
    return labelled


def _within_child_cap(rows: list[dict], field: str) -> bool:
    grouped: dict[str, list[dict]] = {}
    for row in rows:
        grouped.setdefault(row["childID"], []).append(row)
    ceiling = Ratio(*CHILD_FALSE_ACCEPT_CEILING)
    for child in grouped:
        counts = tally(grouped[child], field)
        if counts.reference_incorrect == 0:
            continue
        if not _portion(counts.false_accepts, counts.reference_incorrect).le(ceiling):
            return False
    return True


def _engine_passes(rows: list[dict], field: str, agreement: Ratio, false_accept: Ratio, false_reject: Ratio) -> bool:
    return (
        agreement.ge(Ratio(*AGREEMENT_FLOOR))
        and false_accept.le(Ratio(*POOLED_FALSE_ACCEPT_CEILING))
        and false_reject.le(Ratio(*FALSE_REJECT_CEILING))
        and _within_child_cap(rows, field)
    )


def _members(cohort: list) -> dict[str, dict]:
    found: dict[str, dict] = {}
    for item in cohort:
        if isinstance(item, str):
            found[item] = {"id": item, "age": None, "schoolClass": None}
        else:
            found[item["id"]] = {
                "id": item["id"],
                "age": item.get("age"),
                "schoolClass": item.get("schoolClass"),
            }
    return found


def _screen_cohort(document: dict) -> dict[str, dict]:
    members = _members(document["cohort"])
    for member in members.values():
        age = member["age"]
        if age is not None and age not in COHORT_AGES:
            raise Rejected("COHORT_REJECTED", member["id"])
        school_class = member["schoolClass"]
        if school_class is not None and school_class not in COHORT_CLASSES:
            raise Rejected("COHORT_REJECTED", member["id"])
    recordings = document["recordings"]
    for row in recordings:
        if row.get("appleCorrect") is None or row.get("sarvamCorrect") is None:
            raise Rejected("UNPAIRED_RECORDING", row["id"])
    if not recordings:
        raise Rejected("UNPAIRED_RECORDING", "")
    for row in recordings:
        member = members.get(row["childID"])
        if member is None:
            raise Rejected("OUT_OF_COHORT", row["id"])
        if row.get("age") is not None and (member["age"] is None or row["age"] != member["age"] or row["age"] not in COHORT_AGES):
            raise Rejected("COHORT_REJECTED", row["id"])
        school_class = row.get("schoolClass")
        if school_class is not None and (
            member["schoolClass"] is None or school_class != member["schoolClass"] or school_class not in COHORT_CLASSES
        ):
            raise Rejected("COHORT_REJECTED", row["id"])
    return members


def _choose(apple_ok: bool, sarvam_ok: bool, apple_agreement: Ratio, sarvam_agreement: Ratio, gap_low: Ratio) -> str:
    margin = sarvam_agreement.minus(apple_agreement)
    if apple_ok and sarvam_ok and margin.ge(Ratio(*SARVAM_MARGIN)) and gap_low.gt(_zero()):
        return "SARVAM"
    if apple_ok:
        return "APPLE"
    return "NO_GO"


def evaluate(document: dict) -> dict:
    _screen_cohort(document)
    recordings = document["recordings"]
    groups: dict[str, list[dict]] = {}
    for row in recordings:
        groups.setdefault(row["childID"], []).append(row)
    children = sorted(groups)
    engines: dict[str, dict] = {}
    passed: dict[str, bool] = {}
    point: dict[str, Ratio] = {}
    for name, field in (("apple", "appleCorrect"), ("sarvam", "sarvamCorrect")):
        counts = tally(recordings, field)
        agreement = _portion(counts.agreements, counts.paired)
        false_accept = _portion(counts.false_accepts, counts.reference_incorrect)
        false_reject = _portion(counts.false_rejects, counts.reference_correct)
        engines[name] = {
            "paired": counts.paired,
            "agreements": counts.agreements,
            "falseAccepts": counts.false_accepts,
            "referenceIncorrect": counts.reference_incorrect,
            "falseRejects": counts.false_rejects,
            "referenceCorrect": counts.reference_correct,
            "agreement": agreement.text(),
            "falseAcceptRate": false_accept.text(),
            "falseRejectRate": false_reject.text(),
            "perChildFalseAccept": _child_false_accepts(recordings, field),
            **_intervals(groups, children, field),
        }
        point[name] = agreement
        passed[name] = _engine_passes(recordings, field, agreement, false_accept, false_reject)
    gap_low, gap_high = _gap_interval(groups, children)
    return {
        "scoringVersion": SCORING_VERSION,
        "decision": _choose(passed["apple"], passed["sarvam"], point["apple"], point["sarvam"], gap_low),
        "deltaAgreement": point["sarvam"].minus(point["apple"]).text(),
        "deltaCI": [gap_low.text(), gap_high.text()],
        "apple": engines["apple"],
        "sarvam": engines["sarvam"],
    }


def _rows(child_count: int, items: int, apple_correct: int, sarvam_correct: int, reference: bool = True) -> dict:
    cohort = []
    recordings = []
    for child_index in range(child_count):
        child = f"c{child_index:02d}"
        cohort.append(child)
        for item in range(items):
            recordings.append(
                {
                    "id": f"{child}-{item}",
                    "childID": child,
                    "referenceCorrect": reference,
                    "appleCorrect": item < apple_correct,
                    "sarvamCorrect": item < sarvam_correct,
                }
            )
    return {"cohort": cohort, "recordings": recordings}


def apple_pass() -> dict:
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


def sarvam_pass() -> dict:
    document = apple_pass()
    for row in document["recordings"]:
        row["appleCorrect"], row["sarvamCorrect"] = row["sarvamCorrect"], row["appleCorrect"]
    return document


def no_go() -> dict:
    return _rows(4, 10, 4, 4)


def close_call() -> dict:
    return _rows(4, 1000, 900, 901)


def unpaired() -> dict:
    document = _rows(1, 1, 1, 1)
    document["recordings"][0]["sarvamCorrect"] = None
    return document


def out_of_cohort() -> dict:
    document = _rows(1, 1, 1, 1)
    document["cohort"] = ["someone-else"]
    return document


def exactly_090() -> dict:
    """Twenty children alternate 47/50 and 43/50. Pooled agreement is 900/1000."""
    recordings = []
    cohort = []
    for child_index in range(20):
        child = f"c{child_index:02d}"
        cohort.append(child)
        correct = 47 if child_index % 2 == 0 else 43
        for item in range(50):
            heard = item < correct
            recordings.append(
                {
                    "id": f"{child}-{item}",
                    "childID": child,
                    "referenceCorrect": True,
                    "appleCorrect": heard,
                    "sarvamCorrect": heard,
                }
            )
    return {"cohort": cohort, "recordings": recordings}


def exactly_plus_5pp() -> dict:
    """Every child is 18/20 versus 19/20. The gap is exactly 5 percentage points."""
    return _rows(4, 20, 18, 19)


def ci_includes_zero() -> dict:
    """Pooled gap is exactly 5 points, but one child reverses it often enough that the interval covers zero."""
    recordings = []
    cohort = []
    for child_index in range(10):
        child = f"c{child_index:02d}"
        cohort.append(child)
        sarvam_correct = 10 if child_index == 9 else 20
        for item in range(20):
            recordings.append(
                {
                    "id": f"{child}-{item}",
                    "childID": child,
                    "referenceCorrect": True,
                    "appleCorrect": item < 18,
                    "sarvamCorrect": item < sarvam_correct,
                }
            )
    return {"cohort": cohort, "recordings": recordings}


def per_child_fa_cap() -> dict:
    """Pooled false accepts are 1/20. One child is 1/1, over the 10% cap."""
    recordings = []
    cohort = ["good", "over"]
    for item in range(19):
        recordings.append(
            {
                "id": f"good-{item}",
                "childID": "good",
                "referenceCorrect": False,
                "appleCorrect": False,
                "sarvamCorrect": False,
            }
        )
    recordings.append(
        {
            "id": "over-0",
            "childID": "over",
            "referenceCorrect": False,
            "appleCorrect": True,
            "sarvamCorrect": True,
        }
    )
    return {"cohort": cohort, "recordings": recordings}


def per_child_fa_exact() -> dict:
    """One child is exactly 1/10 false accepts. The cap is inclusive."""
    recordings = []
    cohort = []
    for child_index in range(10):
        child = f"c{child_index:02d}"
        cohort.append(child)
        for item in range(10):
            false_accept = child_index == 0 and item == 0
            recordings.append(
                {
                    "id": f"{child}-{item}",
                    "childID": child,
                    "referenceCorrect": False,
                    "appleCorrect": false_accept,
                    "sarvamCorrect": false_accept,
                }
            )
    return {"cohort": cohort, "recordings": recordings}


def age_reject() -> dict:
    document = _rows(1, 1, 1, 1)
    document["cohort"] = [{"id": "c00", "age": 9, "schoolClass": "2"}]
    document["recordings"][0]["age"] = 9
    document["recordings"][0]["schoolClass"] = "2"
    return document


def class_reject() -> dict:
    document = _rows(1, 1, 1, 1)
    document["cohort"] = [{"id": "c00", "age": 7, "schoolClass": "5"}]
    document["recordings"][0]["age"] = 7
    document["recordings"][0]["schoolClass"] = "5"
    return document


FIXTURES = {
    "apple_pass": apple_pass,
    "sarvam_pass": sarvam_pass,
    "no_go": no_go,
    "close_call": close_call,
    "unpaired": unpaired,
    "out_of_cohort": out_of_cohort,
    "exactly_090": exactly_090,
    "exactly_plus_5pp": exactly_plus_5pp,
    "ci_includes_zero": ci_includes_zero,
    "per_child_fa_cap": per_child_fa_cap,
    "per_child_fa_exact": per_child_fa_exact,
    "age_reject": age_reject,
    "class_reject": class_reject,
}

EXPECTED = {
    "apple_pass": "APPLE",
    "sarvam_pass": "NO_GO",
    "no_go": "NO_GO",
    "close_call": "APPLE",
    "exactly_090": "APPLE",
    "exactly_plus_5pp": "SARVAM",
    "ci_includes_zero": "APPLE",
    "per_child_fa_cap": "NO_GO",
    "per_child_fa_exact": "APPLE",
    "unpaired": "UNPAIRED_RECORDING",
    "out_of_cohort": "OUT_OF_COHORT",
    "age_reject": "COHORT_REJECTED",
    "class_reject": "COHORT_REJECTED",
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


def _payload(document: dict) -> str:
    try:
        report = evaluate(document)
    except Rejected as error:
        report = {"error": error.code, "recordingID": error.recording_id}
    return json.dumps(report, indent=2, sort_keys=True) + "\n"


def main() -> None:
    write = "--write" in sys.argv
    root = fixture_dir()
    root.mkdir(parents=True, exist_ok=True)
    failed = False
    for name, builder in FIXTURES.items():
        source = root / f"{name}.json"
        golden = root / f"{name}.golden.json"
        if not source.exists():
            source.write_text(json.dumps(builder(), indent=2) + "\n", encoding="utf-8")
        loaded = json.loads(source.read_text(encoding="utf-8"))
        payload = _payload(loaded)
        decoded = json.loads(payload)
        outcome = decoded.get("decision") or decoded.get("error")
        if outcome != EXPECTED[name]:
            failed = True
            print(f"SPEC {name} got {outcome} want {EXPECTED[name]}", file=sys.stderr)
        if write or not golden.exists():
            golden.write_text(payload, encoding="utf-8")
            print(f"wrote {name} {outcome}")
            continue
        if golden.read_text(encoding="utf-8") != payload:
            failed = True
            print(f"MISMATCH {name}", file=sys.stderr)
        else:
            print(f"ok {name} {outcome}")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
