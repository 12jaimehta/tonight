"""Paired child-cluster bootstrap of the pooled agreement difference.

The ruled interval is a 95% percentile interval from 10,000 draws of a fixed
seed. The cluster is the child: every recording of a drawn child moves
together, because recordings from the same child are not independent.

- statistic = pooled Sarvam agreement minus pooled Apple agreement,
  word-weighted across the recordings in the resampled children
- generator = ``random.Random`` (MT19937), seeded once per call
- draws = ``randrange`` over the child list, with no extra bit mixing
- interval = two-sided Hyndman–Fan type-7 percentile

A lower endpoint of exactly zero overlaps zero. Callers treat Sarvam as the
winner only when that endpoint is strictly positive.
"""

from __future__ import annotations

import random
from collections.abc import Sequence
from dataclasses import dataclass
from fractions import Fraction

from gate_check_independent.errors import GateCheckError
from gate_check_independent.types import Child, RecordingTotals


@dataclass(frozen=True)
class AgreementInterval:
    low: Fraction
    high: Fraction
    confidence: Fraction
    resamples: int
    seed: int

    @property
    def strictly_above_zero(self) -> bool:
        return self.low > 0


def pooled_agreement_delta(recordings: Sequence[RecordingTotals]) -> Fraction:
    """Word-weighted Sarvam agreement minus word-weighted Apple agreement."""

    words = 0
    difference = 0
    for recording in recordings:
        words += recording.words
        difference += recording.match_difference
    if words == 0:
        raise GateCheckError(
            "INSUFFICIENT_DATA",
            "agreement difference needs at least one judged word",
        )
    return Fraction(difference, words)


def percentile_type7(sorted_samples: Sequence[Fraction], probability: Fraction) -> Fraction:
    """Hyndman–Fan type-7 sample quantile, in exact rationals.

    Position ``h = 1 + (n - 1) * p`` on the 1-based sample, with linear
    interpolation. Equivalently, index ``(n - 1) * p`` on the 0-based sample.
    """

    if not sorted_samples:
        raise GateCheckError("INSUFFICIENT_DATA", "bootstrap sample is empty")
    if probability < 0 or probability > 1:
        raise GateCheckError("INVALID_INPUT", "quantile probability must be in [0, 1]")
    if len(sorted_samples) == 1:
        return sorted_samples[0]
    position = (len(sorted_samples) - 1) * probability
    lower_index = int(position)
    if lower_index >= len(sorted_samples) - 1:
        return sorted_samples[-1]
    weight = position - lower_index
    if weight == 0:
        return sorted_samples[lower_index]
    lower = sorted_samples[lower_index]
    upper = sorted_samples[lower_index + 1]
    return lower + (upper - lower) * weight


def resampled_deltas(
    children: Sequence[Child],
    *,
    resamples: int,
    seed: int,
) -> list[Fraction]:
    """Return one pooled agreement difference per bootstrap replicate.

    Each replicate draws ``len(children)`` children with replacement. All of
    a drawn child's recordings stay together. The generator is
    ``random.Random(seed)`` and the only calls made on it are ``randrange(n)``.
    """

    if not children:
        raise GateCheckError("INSUFFICIENT_DATA", "bootstrap needs at least one child")
    population = tuple(children)
    count = len(population)
    generator = random.Random(seed)
    deltas: list[Fraction] = []
    for _ in range(resamples):
        draw = tuple(population[generator.randrange(count)] for _ in range(count))
        recordings = tuple(recording for child in draw for recording in child.recordings)
        deltas.append(pooled_agreement_delta(recordings))
    return deltas


def agreement_interval(
    children: Sequence[Child],
    *,
    resamples: int,
    seed: int,
    confidence: Fraction,
) -> AgreementInterval:
    """Two-sided percentile interval for the paired agreement difference."""

    if not isinstance(confidence, Fraction):
        raise GateCheckError("INVALID_INPUT", "confidence must be a Fraction")
    if not 0 < confidence < 1:
        raise GateCheckError("INVALID_INPUT", "confidence must be strictly between 0 and 1")
    samples = resampled_deltas(children, resamples=resamples, seed=seed)
    samples.sort()
    tail = (1 - confidence) / 2
    return AgreementInterval(
        low=percentile_type7(samples, tail),
        high=percentile_type7(samples, 1 - tail),
        confidence=confidence,
        resamples=resamples,
        seed=seed,
    )
