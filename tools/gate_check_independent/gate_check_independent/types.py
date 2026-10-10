"""Shared constants and counted-recording types.

Thresholds are the M0 decision bars, written as exact rationals:

- agreement at least 90/100
- pooled false-accept at most 5/100
- per-child false-accept at most 10/100
- pooled false-reject at most 10/100
- Sarvam's agreement margin at least 5/100
"""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction

AGREEMENT_MINIMUM = Fraction(9, 10)
POOLED_FALSE_ACCEPT_MAXIMUM = Fraction(1, 20)
CHILD_FALSE_ACCEPT_MAXIMUM = Fraction(1, 10)
FALSE_REJECT_MAXIMUM = Fraction(1, 10)
SARVAM_AGREEMENT_MARGIN = Fraction(1, 20)

VALID_AGES = frozenset({6, 7, 8})
SCHEMA_VERSION = 1

# The plan requires a paired interval but does not name a confidence level,
# a draw count, or a seed. These defaults are part of this checker's contract.
DEFAULT_SEED = 20261009
DEFAULT_RESAMPLES = 10_000
DEFAULT_CONFIDENCE = Fraction(95, 100)


@dataclass(frozen=True)
class RecordingTotals:
    """Word counts for one recording scored by both engines.

    A match is an engine call that equals the adult reference. A false accept
    is a reference-incorrect word the engine called correct. A false reject is
    a reference-correct word the engine called incorrect.
    """

    recording_id: str
    child_id: str
    words: int
    reference_correct: int
    apple_matches: int
    sarvam_matches: int
    apple_false_accepts: int
    sarvam_false_accepts: int
    apple_false_rejects: int
    sarvam_false_rejects: int

    @property
    def reference_incorrect(self) -> int:
        return self.words - self.reference_correct

    @property
    def match_difference(self) -> int:
        """Sarvam matches minus Apple matches. Positive favours Sarvam."""

        return self.sarvam_matches - self.apple_matches


@dataclass(frozen=True)
class Child:
    child_id: str
    age: int
    recordings: tuple[RecordingTotals, ...]


@dataclass(frozen=True)
class Cohort:
    children: tuple[Child, ...]

    @property
    def recordings(self) -> tuple[RecordingTotals, ...]:
        return tuple(
            recording for child in self.children for recording in child.recordings
        )
