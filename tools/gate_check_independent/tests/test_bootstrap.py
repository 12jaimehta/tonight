"""The paired interval uses this checker's own generator and quantile."""

import random
from fractions import Fraction

from builders import cell, child, recording, study
from gate_check_independent.bootstrap import (
    agreement_interval,
    percentile_type7,
    pooled_agreement_delta,
    resampled_deltas,
)
from gate_check_independent.cohort import parse_cohort
from gate_check_independent.types import DEFAULT_CONFIDENCE


def test_type7_interpolates_in_rationals() -> None:
    samples = [Fraction(0), Fraction(1), Fraction(2), Fraction(3)]
    assert percentile_type7(samples, Fraction(0)) == Fraction(0)
    assert percentile_type7(samples, Fraction(1)) == Fraction(3)
    assert percentile_type7(samples, Fraction(1, 2)) == Fraction(3, 2)
    assert percentile_type7(samples, Fraction(1, 4)) == Fraction(3, 4)
    assert percentile_type7([Fraction(5, 2)], Fraction(1, 3)) == Fraction(5, 2)


def test_pooled_delta_is_word_weighted() -> None:
    cohort = parse_cohort(
        study(
            [
                child("short", 7, [recording("short-r", [cell(True, False, True, 10)])]),
                child("long", 8, [recording("long-r", [cell(True, True, True, 1000)])]),
            ]
        )
    )
    recordings = cohort.recordings
    assert pooled_agreement_delta(recordings) == Fraction(10, 1010)
    assert pooled_agreement_delta((recordings[0], recordings[0])) == Fraction(1)
    assert pooled_agreement_delta((recordings[1], recordings[1])) == Fraction(0)


def test_draws_are_plain_randrange_calls() -> None:
    cohort = parse_cohort(
        study(
            [
                child("a", 6, [recording("a-r", [cell(True, False, True, 4)])]),
                child("b", 8, [recording("b-r", [cell(True, True, False, 6)])]),
            ]
        )
    )
    recordings = cohort.recordings
    deltas = resampled_deltas(recordings, resamples=5, seed=5)
    generator = random.Random(5)
    expected = []
    for _ in range(5):
        draw = tuple(recordings[generator.randrange(2)] for _ in range(2))
        expected.append(pooled_agreement_delta(draw))
    assert deltas == expected


def test_same_seed_replays_and_a_different_seed_does_not() -> None:
    cohort = parse_cohort(
        study(
            [
                child("a", 7, [recording("a-r", [cell(True, False, True, 10)])]),
                child("b", 7, [recording("b-r", [cell(True, True, False, 10)])]),
                child("c", 7, [recording("c-r", [cell(True, True, True, 10)])]),
            ]
        )
    )
    first = resampled_deltas(cohort.recordings, resamples=30, seed=1)
    replay = resampled_deltas(cohort.recordings, resamples=30, seed=1)
    other = resampled_deltas(cohort.recordings, resamples=30, seed=2)
    assert first == replay
    assert first != other


def test_default_confidence_is_ninety_five_percent() -> None:
    cohort = parse_cohort(study([child("c", 7, [recording("r", [cell(True, True, True, 10)])])]))
    interval = agreement_interval(
        cohort.recordings,
        resamples=8,
        seed=0,
        confidence=DEFAULT_CONFIDENCE,
    )
    assert interval.confidence == Fraction(95, 100)
    assert interval.low == Fraction(0)
    assert interval.high == Fraction(0)


def test_uniform_recordings_collapse_for_every_seed() -> None:
    cohort = parse_cohort(
        study(
            [
                child(
                    f"c{index}",
                    7,
                    [
                        recording(
                            f"c{index}-r",
                            [
                                cell(True, True, True, 90),
                                cell(True, False, True, 5),
                                cell(True, False, False, 5),
                            ],
                        )
                    ],
                )
                for index in range(3)
            ]
        )
    )
    for seed in (0, 1, -4, 20261009):
        interval = agreement_interval(
            cohort.recordings,
            resamples=25,
            seed=seed,
            confidence=Fraction(9, 10),
        )
        assert interval.low == interval.high == Fraction(1, 20)
