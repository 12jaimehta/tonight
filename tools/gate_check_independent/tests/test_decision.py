"""Who wins once the pass bits and the paired interval are known."""

from fractions import Fraction

import pytest

from builders import agreed, cell, child, recording, study
from gate_check_independent import evaluate
from gate_check_independent.gate import BeatBreakdown, beat_breakdown, decide

FAST = {"resamples": 30, "seed": 3}


def _beats(
    *,
    apple_passes: bool = True,
    sarvam_passes: bool = True,
    delta: Fraction = Fraction(6, 100),
    ci_low: Fraction = Fraction(1, 100),
    apple_far: Fraction = Fraction(0),
    sarvam_far: Fraction = Fraction(0),
) -> BeatBreakdown:
    return beat_breakdown(
        apple_passes=apple_passes,
        sarvam_passes=sarvam_passes,
        delta=delta,
        ci_low=ci_low,
        apple_false_accept=apple_far,
        sarvam_false_accept=sarvam_far,
    )


def test_both_pass_and_clear_margin_interval_and_false_accept_picks_sarvam() -> None:
    beats = _beats(delta=Fraction(1, 20), ci_low=Fraction(1, 20))
    assert beats.sarvam_wins
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "SARVAM"


def test_margin_exactly_five_points_is_enough() -> None:
    beats = _beats(delta=Fraction(1, 20), ci_low=Fraction(1, 1000))
    assert beats.margin
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "SARVAM"


def test_margin_one_part_in_a_billion_under_five_points_picks_apple() -> None:
    beats = _beats(delta=Fraction(1, 20) - Fraction(1, 10**9), ci_low=Fraction(1, 100))
    assert beats.margin is False
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "APPLE"


def test_interval_that_touches_zero_picks_apple() -> None:
    # Probe D: +6pp with a CI of [0, +9pp].
    beats = _beats(delta=Fraction(6, 100), ci_low=Fraction(0))
    assert beats.interval_above_zero is False
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "APPLE"


def test_tiny_positive_lower_bound_clears_zero() -> None:
    beats = _beats(ci_low=Fraction(1, 10**9))
    assert beats.interval_above_zero
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "SARVAM"


def test_interval_entirely_below_zero_does_not_count_as_excluding_zero() -> None:
    beats = _beats(delta=Fraction(6, 100), ci_low=Fraction(-1, 10))
    assert beats.interval_above_zero is False
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "APPLE"


def test_equal_false_accept_is_not_worse() -> None:
    beats = _beats(apple_far=Fraction(1, 20), sarvam_far=Fraction(1, 20))
    assert beats.false_accept_not_worse
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "SARVAM"


def test_worse_false_accept_picks_apple_even_when_the_margin_and_interval_clear() -> None:
    # MET-34.
    beats = _beats(apple_far=Fraction(0), sarvam_far=Fraction(1, 20))
    assert beats.false_accept_not_worse is False
    assert decide(apple_passes=True, sarvam_passes=True, beats=beats) == "APPLE"


def test_only_sarvam_passing_does_not_need_the_margin() -> None:
    beats = _beats(apple_passes=False, delta=Fraction(0), ci_low=Fraction(-1, 10))
    assert beats.sarvam_wins is False
    assert decide(apple_passes=False, sarvam_passes=True, beats=beats) == "SARVAM"


def test_only_apple_passing_picks_apple() -> None:
    beats = _beats(sarvam_passes=False)
    assert decide(apple_passes=True, sarvam_passes=False, beats=beats) == "APPLE"


def test_neither_passing_is_no_go() -> None:
    beats = _beats(apple_passes=False, sarvam_passes=False, delta=Fraction(1, 5))
    assert decide(apple_passes=False, sarvam_passes=False, beats=beats) == "NO_GO"


def test_uniform_plus_two_points_picks_apple() -> None:
    result = evaluate(_uniform(90, 92), **FAST)
    assert result.agreement_delta == Fraction(1, 50)
    assert result.interval.low == result.agreement_delta
    assert result.interval.low > 0
    assert result.apple.passes and result.sarvam.passes
    assert result.decision == "APPLE"


def test_uniform_plus_six_points_picks_sarvam_with_a_degenerate_interval() -> None:
    payload = study(
        [
            child(f"c{index}", 7, [recording(f"c{index}-r", _plus_six_cells())])
            for index in range(4)
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.agreement_delta == Fraction(6, 100)
    assert result.interval.low == Fraction(6, 100)
    assert result.interval.high == Fraction(6, 100)
    assert result.beats.sarvam_wins
    assert result.decision == "SARVAM"


def test_exactly_five_points_on_two_thousand_words_picks_sarvam() -> None:
    result = evaluate(_margin_payload(100), **FAST)
    assert result.agreement_delta == Fraction(1, 20)
    assert result.apple.agreement == Fraction(9, 10)
    assert result.apple.false_reject_rate == Fraction(1, 10)
    assert result.interval.low == Fraction(1, 20)
    assert result.sarvam.comparable_false_accept() == result.apple.comparable_false_accept()
    assert result.decision == "SARVAM"


def test_one_word_under_five_points_picks_apple() -> None:
    result = evaluate(_margin_payload(99), **FAST)
    assert result.agreement_delta == Fraction(99, 2000)
    assert result.agreement_delta < Fraction(1, 20)
    assert result.interval.strictly_above_zero
    assert result.apple.passes and result.sarvam.passes
    assert result.beats.margin is False
    assert result.decision == "APPLE"


def test_margin_met_but_bootstrap_interval_crosses_zero_picks_apple() -> None:
    children = []
    ahead = [cell(True, True, True, 90), cell(True, False, True, 10)]
    behind = [cell(True, True, True, 80), cell(True, True, False, 20)]
    for index in range(10):
        children.append(child(f"a{index}", 7, [recording(f"a{index}-r", ahead)]))
    for index in range(2):
        children.append(child(f"b{index}", 8, [recording(f"b{index}-r", behind)]))
    result = evaluate(study(children), resamples=10_000, seed=20261009)
    assert result.agreement_delta == Fraction(1, 20)
    assert result.apple.passes and result.sarvam.passes
    assert result.interval.low == Fraction(-1, 40)
    assert result.interval.high == Fraction(1, 10)
    assert result.interval.low < 0
    assert result.decision == "APPLE"


@pytest.mark.parametrize("seed", [1, 7, 99])
def test_crossing_zero_stays_apple_for_other_seeds(seed: int) -> None:
    children = []
    ahead = [cell(True, True, True, 90), cell(True, False, True, 10)]
    behind = [cell(True, True, True, 80), cell(True, True, False, 20)]
    for index in range(10):
        children.append(child(f"a{index}", 6, [recording(f"a{index}-r", ahead)]))
    for index in range(2):
        children.append(child(f"b{index}", 7, [recording(f"b{index}-r", behind)]))
    result = evaluate(study(children), resamples=10_000, seed=seed)
    assert result.interval.low <= 0
    assert result.decision == "APPLE"


def test_only_sarvam_passes_when_apple_agreement_is_85_percent() -> None:
    # MET-36. Apple 85/100, Sarvam 97/100.
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [
                            cell(True, True, True, 85),
                            cell(True, False, True, 12),
                            cell(True, False, False, 3),
                        ],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(85, 100)
    assert result.apple.passes is False
    assert result.sarvam.agreement == Fraction(97, 100)
    assert result.sarvam.passes
    assert result.decision == "SARVAM"


def test_sarvam_at_exactly_ninety_still_wins_when_apple_fails() -> None:
    payload = study(
        [
            child(
                "c",
                6,
                [
                    recording(
                        "r",
                        [cell(True, True, True, 50), cell(True, False, True, 40), cell(True, False, False, 10)],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(1, 2)
    assert result.sarvam.agreement == Fraction(9, 10)
    assert result.decision == "SARVAM"


def test_only_apple_passes_when_sarvam_agreement_fails() -> None:
    payload = study(
        [
            child(
                "c",
                8,
                [
                    recording(
                        "r",
                        [
                            cell(True, True, True, 85),
                            cell(True, True, False, 12),
                            cell(True, False, False, 3),
                        ],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(97, 100)
    assert result.sarvam.agreement == Fraction(85, 100)
    assert result.decision == "APPLE"


def test_sarvam_false_accept_worse_than_apple_picks_apple() -> None:
    # Both pass, delta is +6pp, the interval is that point, Sarvam FAR is 5% and Apple's is 0.
    payload = study([child("c", 7, [recording("r", _met34_cells())])])
    result = evaluate(payload, **FAST)
    assert result.apple.passes and result.sarvam.passes
    assert result.agreement_delta == Fraction(6, 100)
    assert result.interval.low == Fraction(6, 100)
    assert result.apple.false_accept_rate == Fraction(0)
    assert result.sarvam.false_accept_rate == Fraction(1, 20)
    assert result.decision == "APPLE"


def test_sarvam_wins_when_margin_interval_and_false_accept_all_hold() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [
                            cell(True, True, True, 900),
                            cell(True, False, True, 100),
                            cell(False, True, True, 4),
                            cell(False, True, False, 1),
                            cell(False, False, False, 95),
                        ],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.false_accept_rate == Fraction(5, 100)
    assert result.sarvam.false_accept_rate == Fraction(4, 100)
    assert result.agreement_delta > Fraction(1, 20)
    assert result.interval.strictly_above_zero
    assert result.apple.passes and result.sarvam.passes
    assert result.decision == "SARVAM"


def test_false_reject_alone_can_eliminate_apple() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [
                            cell(True, True, True, 89),
                            cell(True, False, True, 11),
                            cell(False, False, False, 100),
                        ],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement_ok
    assert result.apple.false_reject_ok is False
    assert result.sarvam.passes
    assert result.decision == "SARVAM"


def test_child_cap_alone_can_eliminate_sarvam() -> None:
    payload = study(
        [
            child(
                "hot",
                6,
                [recording("hot-r", [cell(True, True, True, 50), cell(False, False, True, 1)])],
            ),
            child(
                "clean",
                8,
                [recording("clean-r", [cell(True, True, True, 50), cell(False, False, False, 20)])],
            ),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.sarvam.false_accept_rate == Fraction(1, 21)
    assert result.sarvam.false_accept_ok
    assert result.sarvam.children[0].rate == Fraction(1)
    assert result.sarvam.passes is False
    assert result.apple.passes
    assert result.decision == "APPLE"


def test_both_failing_agreement_is_no_go_even_if_sarvam_is_ahead() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [cell(True, True, True, 70), cell(True, False, True, 10), cell(True, False, False, 20)],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(70, 100)
    assert result.sarvam.agreement == Fraction(80, 100)
    assert result.decision == "NO_GO"


def _uniform(apple_matches: int, sarvam_matches: int) -> dict:
    both = apple_matches
    sarvam_only = sarvam_matches - apple_matches
    neither = 100 - sarvam_matches
    return study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [
                            cell(True, True, True, both),
                            cell(True, False, True, sarvam_only),
                            cell(True, False, False, neither),
                        ],
                    )
                ],
            )
        ]
    )


def _plus_six_cells() -> list[dict]:
    return [
        cell(True, True, True, 90),
        cell(True, False, True, 6),
        cell(True, False, False, 4),
    ]


def _margin_payload(sarvam_extra: int) -> dict:
    return study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [
                            cell(True, True, True, 1800),
                            cell(True, False, True, sarvam_extra),
                            cell(True, False, False, 200 - sarvam_extra),
                        ],
                    )
                ],
            )
        ]
    )


def _met34_cells() -> list[dict]:
    return [
        cell(True, True, True, 902),
        cell(True, True, False, 8),
        cell(True, False, True, 90),
        cell(False, False, True, 10),
        cell(False, False, False, 190),
    ]
