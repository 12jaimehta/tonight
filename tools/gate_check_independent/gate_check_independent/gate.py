"""M0 speech-engine GO/NO-GO decision.

An engine passes when, on the pooled word judgments:

- agreement is at least 90%
- pooled false-accept is at most 5%
- every child's false-accept is at most 10% (a child with no
  reference-incorrect words is skipped)
- pooled false-reject is at most 10% (there is no per-child false-reject cap)

A recording with no reference-correct words is left out of the false-reject
count. A recording with no reference-incorrect words adds 0 to the
false-accept numerator and denominator. A child with no reference-incorrect
words is skipped for the per-child cap. A pooled denominator of 0 is
``INVALID_STUDY`` and never passes.

Decision order:

1. Both pass and Sarvam clearly beats Apple: SARVAM.
2. Both pass otherwise: APPLE.
3. Only one engine passes: that engine.
4. Neither passes: NO_GO.

Sarvam clearly beats Apple when its pooled agreement is at least 5 percentage
points higher, the child-cluster bootstrap interval sits strictly above zero,
and its pooled false-accept rate is less than or equal to Apple's. A tie on
false-accept is not worse.
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from typing import Any

from gate_check_independent.bootstrap import AgreementInterval, agreement_interval, pooled_agreement_delta
from gate_check_independent.cohort import parse_cohort
from gate_check_independent.errors import GateCheckError
from gate_check_independent.types import (
    AGREEMENT_MINIMUM,
    CHILD_FALSE_ACCEPT_MAXIMUM,
    DEFAULT_CONFIDENCE,
    DEFAULT_RESAMPLES,
    DEFAULT_SEED,
    FALSE_REJECT_MAXIMUM,
    POOLED_FALSE_ACCEPT_MAXIMUM,
    SARVAM_AGREEMENT_MARGIN,
    Child,
    Cohort,
    RecordingTotals,
)

EngineName = str


@dataclass(frozen=True)
class ChildFalseAccept:
    child_id: str
    false_accepts: int
    reference_incorrect: int
    rate: Fraction | None
    within_cap: bool


@dataclass(frozen=True)
class EngineScore:
    engine: str
    words: int
    matches: int
    reference_correct: int
    reference_incorrect: int
    false_accepts: int
    false_rejects: int
    false_accept_rate: Fraction | None
    false_reject_rate: Fraction | None
    agreement_ok: bool
    false_accept_ok: bool
    false_reject_ok: bool
    per_child_ok: bool
    children: tuple[ChildFalseAccept, ...]

    @property
    def agreement(self) -> Fraction:
        return Fraction(self.matches, self.words)

    @property
    def passes(self) -> bool:
        return (
            self.agreement_ok
            and self.false_accept_ok
            and self.false_reject_ok
            and self.per_child_ok
        )

    def comparable_false_accept(self) -> Fraction:
        """Rate used in the 'no worse' comparison. Not applicable counts as 0."""

        if self.false_accept_rate is None:
            return Fraction(0)
        return self.false_accept_rate


@dataclass(frozen=True)
class BeatBreakdown:
    both_pass: bool
    margin: bool
    interval_above_zero: bool
    false_accept_not_worse: bool

    @property
    def sarvam_wins(self) -> bool:
        return (
            self.both_pass
            and self.margin
            and self.interval_above_zero
            and self.false_accept_not_worse
        )


@dataclass(frozen=True)
class GateDecision:
    decision: str
    apple: EngineScore
    sarvam: EngineScore
    agreement_delta: Fraction
    interval: AgreementInterval
    beats: BeatBreakdown
    warnings: tuple[str, ...]


def evaluate(
    payload: object,
    *,
    seed: int = DEFAULT_SEED,
    resamples: int = DEFAULT_RESAMPLES,
    confidence: Fraction = DEFAULT_CONFIDENCE,
) -> GateDecision:
    """Score a parsed results document and return the gate decision."""

    _validate_settings(seed, resamples, confidence)
    cohort = parse_cohort(payload)
    _require_defined_denominators(cohort)
    apple = score_engine(cohort, "apple")
    sarvam = score_engine(cohort, "sarvam")
    delta = pooled_agreement_delta(cohort.recordings)
    interval = agreement_interval(
        cohort.children,
        resamples=resamples,
        seed=seed,
        confidence=confidence,
    )
    breakdown = beat_breakdown(
        apple_passes=apple.passes,
        sarvam_passes=sarvam.passes,
        delta=delta,
        ci_low=interval.low,
        apple_false_accept=apple.comparable_false_accept(),
        sarvam_false_accept=sarvam.comparable_false_accept(),
    )
    return GateDecision(
        decision=decide(apple_passes=apple.passes, sarvam_passes=sarvam.passes, beats=breakdown),
        apple=apple,
        sarvam=sarvam,
        agreement_delta=delta,
        interval=interval,
        beats=breakdown,
        warnings=cohort.warnings,
    )


def beat_breakdown(
    *,
    apple_passes: bool,
    sarvam_passes: bool,
    delta: Fraction,
    ci_low: Fraction,
    apple_false_accept: Fraction,
    sarvam_false_accept: Fraction,
) -> BeatBreakdown:
    """Evaluate the four 'clearly beats' clauses. The margin applies only when both pass."""

    return BeatBreakdown(
        both_pass=apple_passes and sarvam_passes,
        margin=delta >= SARVAM_AGREEMENT_MARGIN,
        interval_above_zero=ci_low > 0,
        false_accept_not_worse=sarvam_false_accept <= apple_false_accept,
    )


def decide(*, apple_passes: bool, sarvam_passes: bool, beats: BeatBreakdown) -> str:
    """Pick SARVAM, APPLE, or NO_GO from the pass bits and the beat breakdown."""

    if apple_passes and sarvam_passes:
        return "SARVAM" if beats.sarvam_wins else "APPLE"
    if sarvam_passes:
        return "SARVAM"
    if apple_passes:
        return "APPLE"
    return "NO_GO"


def score_engine(cohort: Cohort, engine: EngineName) -> EngineScore:
    words = 0
    matches = 0
    reference_correct = 0
    false_accepts = 0
    false_rejects = 0
    children: list[ChildFalseAccept] = []
    for child in cohort.children:
        child_accepts, child_incorrect, child_words, child_matches, child_correct, child_rejects = (
            _accumulate_child(child, engine)
        )
        words += child_words
        matches += child_matches
        reference_correct += child_correct
        false_accepts += child_accepts
        false_rejects += child_rejects
        children.append(_child_false_accept(child.child_id, child_accepts, child_incorrect))
    if words == 0:
        raise GateCheckError("INSUFFICIENT_DATA", "the cohort has no judged words")
    reference_incorrect = words - reference_correct
    agreement = Fraction(matches, words)
    if reference_incorrect == 0:
        false_accept_rate = None
        false_accept_ok = False
    else:
        false_accept_rate = Fraction(false_accepts, reference_incorrect)
        false_accept_ok = false_accept_rate <= POOLED_FALSE_ACCEPT_MAXIMUM
    if reference_correct == 0:
        false_reject_rate = None
        false_reject_ok = False
    else:
        false_reject_rate = Fraction(false_rejects, reference_correct)
        false_reject_ok = false_reject_rate <= FALSE_REJECT_MAXIMUM
    return EngineScore(
        engine=engine,
        words=words,
        matches=matches,
        reference_correct=reference_correct,
        reference_incorrect=reference_incorrect,
        false_accepts=false_accepts,
        false_rejects=false_rejects,
        false_accept_rate=false_accept_rate,
        false_reject_rate=false_reject_rate,
        agreement_ok=agreement >= AGREEMENT_MINIMUM,
        false_accept_ok=false_accept_ok,
        false_reject_ok=false_reject_ok,
        per_child_ok=all(child.within_cap for child in children),
        children=tuple(children),
    )


def decision_to_dict(result: GateDecision) -> dict[str, Any]:
    """JSON-ready report. Rates are numerator/denominator objects, not binary floats."""

    return {
        "schema_version": 1,
        "decision": result.decision,
        "seed": result.interval.seed,
        "warnings": list(result.warnings),
        "agreement_delta": _ratio(result.agreement_delta),
        "apple": _engine_dict(result.apple),
        "sarvam": _engine_dict(result.sarvam),
        "clearly_beats": {
            "sarvam_wins": result.beats.sarvam_wins,
            "both_pass": result.beats.both_pass,
            "margin_at_least_5pp": result.beats.margin,
            "interval_strictly_above_zero": result.beats.interval_above_zero,
            "false_accept_not_worse": result.beats.false_accept_not_worse,
        },
        "interval": {
            "method": "paired child-cluster bootstrap, Hyndman-Fan type 7 percentile",
            "generator": "random.Random",
            "confidence": _ratio(result.interval.confidence),
            "resamples": result.interval.resamples,
            "seed": result.interval.seed,
            "low": _ratio(result.interval.low),
            "high": _ratio(result.interval.high),
            "strictly_above_zero": result.interval.strictly_above_zero,
        },
    }


def _accumulate_child(
    child: Child,
    engine: EngineName,
) -> tuple[int, int, int, int, int, int]:
    false_accepts = 0
    reference_incorrect = 0
    words = 0
    matches = 0
    reference_correct = 0
    false_rejects = 0
    for recording in child.recordings:
        words += recording.words
        reference_correct += recording.reference_correct
        reference_incorrect += recording.reference_incorrect
        matches += _matches(recording, engine)
        false_accepts += _false_accepts(recording, engine)
        false_rejects += _false_rejects(recording, engine)
    return false_accepts, reference_incorrect, words, matches, reference_correct, false_rejects


def _child_false_accept(child_id: str, false_accepts: int, reference_incorrect: int) -> ChildFalseAccept:
    if reference_incorrect == 0:
        return ChildFalseAccept(
            child_id=child_id,
            false_accepts=false_accepts,
            reference_incorrect=0,
            rate=None,
            within_cap=True,
        )
    rate = Fraction(false_accepts, reference_incorrect)
    return ChildFalseAccept(
        child_id=child_id,
        false_accepts=false_accepts,
        reference_incorrect=reference_incorrect,
        rate=rate,
        within_cap=rate <= CHILD_FALSE_ACCEPT_MAXIMUM,
    )


def _matches(recording: RecordingTotals, engine: EngineName) -> int:
    if engine == "apple":
        return recording.apple_matches
    if engine == "sarvam":
        return recording.sarvam_matches
    raise GateCheckError("INVALID_INPUT", f"unknown engine {engine!r}")


def _false_accepts(recording: RecordingTotals, engine: EngineName) -> int:
    if engine == "apple":
        return recording.apple_false_accepts
    if engine == "sarvam":
        return recording.sarvam_false_accepts
    raise GateCheckError("INVALID_INPUT", f"unknown engine {engine!r}")


def _false_rejects(recording: RecordingTotals, engine: EngineName) -> int:
    if engine == "apple":
        return recording.apple_false_rejects
    if engine == "sarvam":
        return recording.sarvam_false_rejects
    raise GateCheckError("INVALID_INPUT", f"unknown engine {engine!r}")


def _require_defined_denominators(cohort: Cohort) -> None:
    """A pooled denominator of 0 makes the study invalid. It never passes."""

    reference_correct = 0
    reference_incorrect = 0
    for recording in cohort.recordings:
        reference_correct += recording.reference_correct
        reference_incorrect += recording.reference_incorrect
    problems: list[str] = []
    if reference_correct == 0:
        problems.append("pooled false-reject denominator is 0")
    if reference_incorrect == 0:
        problems.append("pooled false-accept denominator is 0")
    if problems:
        raise GateCheckError("INVALID_STUDY", "; ".join(problems))


def _validate_settings(seed: int, resamples: int, confidence: Fraction) -> None:
    if isinstance(seed, bool) or not isinstance(seed, int):
        raise GateCheckError("INVALID_INPUT", "seed must be an integer")
    if isinstance(resamples, bool) or not isinstance(resamples, int) or resamples < 1:
        raise GateCheckError("INVALID_INPUT", "resamples must be an integer of at least 1")
    if not isinstance(confidence, Fraction):
        raise GateCheckError("INVALID_INPUT", "confidence must be a Fraction")
    if not 0 < confidence < 1:
        raise GateCheckError("INVALID_INPUT", "confidence must be strictly between 0 and 1")


def _engine_dict(score: EngineScore) -> dict[str, Any]:
    return {
        "engine": score.engine,
        "passes": score.passes,
        "words": score.words,
        "matches": score.matches,
        "agreement": _ratio(score.agreement),
        "reference_correct": score.reference_correct,
        "reference_incorrect": score.reference_incorrect,
        "false_accepts": score.false_accepts,
        "false_accept_rate": _optional_rate(score.false_accept_rate, absent="not_applicable"),
        "false_rejects": score.false_rejects,
        "false_reject_rate": _optional_rate(score.false_reject_rate, absent="undefined"),
        "bars": {
            "agreement_at_least_90": score.agreement_ok,
            "pooled_false_accept_at_most_5": score.false_accept_ok,
            "per_child_false_accept_at_most_10": score.per_child_ok,
            "false_reject_at_most_10": score.false_reject_ok,
        },
        "children": [
            {
                "child_id": child.child_id,
                "false_accepts": child.false_accepts,
                "reference_incorrect": child.reference_incorrect,
                "false_accept_rate": _optional_rate(child.rate, absent="not_applicable"),
                "within_cap": child.within_cap,
            }
            for child in score.children
        ],
    }


def _optional_rate(rate: Fraction | None, *, absent: str) -> dict[str, Any]:
    if rate is None:
        return {"status": absent}
    return {"status": "ratio", **_ratio(rate)}


def _ratio(value: Fraction) -> dict[str, int]:
    return {"numerator": value.numerator, "denominator": value.denominator}
