"""Pass-bar boundaries. Comparisons are exact rationals."""

from fractions import Fraction

import pytest

from builders import agreed, cell, child, recording, study
from gate_check_independent import evaluate
from gate_check_independent.errors import GateCheckError

# Bootstrap cost is irrelevant on a single recording: every replicate matches.
FAST = {"resamples": 20, "seed": 1}


def test_agreement_exactly_nine_tenths_passes() -> None:
    # 1800/2000 = 9/10 and the false-reject rate is 200/2000 = 1/10.
    payload = study(
        [
            child(
                "c",
                7,
                [recording("r", [agreed(True, True, 1800), agreed(True, False, 200)])],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(9, 10)
    assert result.apple.false_reject_rate == Fraction(1, 10)
    assert result.apple.passes
    assert result.sarvam.passes
    assert result.decision == "APPLE"


def test_one_match_under_nine_tenths_fails() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [recording("r", [agreed(True, True, 1799), agreed(True, False, 201)])],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(1799, 2000)
    assert result.apple.agreement < Fraction(9, 10)
    assert result.apple.agreement_ok is False
    assert result.decision == "NO_GO"


def test_pooled_agreement_is_not_the_mean_of_child_rates() -> None:
    # Child rates are 1 and 2/5. Their mean is 7/10. The pooled rate is 9/10.
    payload = study(
        [
            child("big", 6, [recording("big-r", [agreed(True, True, 100)])]),
            child(
                "small",
                8,
                [recording("small-r", [agreed(True, True, 8), agreed(True, False, 12)])],
            ),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(9, 10)
    assert result.apple.false_reject_rate == Fraction(1, 10)
    assert result.apple.passes
    assert result.decision == "APPLE"


def test_unequal_children_below_nine_tenths_fail_even_if_a_mean_would_pass() -> None:
    # Rates 1 and 4/5. The unweighted mean is 9/10. Pooled matches are 100/120.
    payload = study(
        [
            child("small", 6, [recording("s", [agreed(True, True, 20)])]),
            child("big", 7, [recording("b", [agreed(True, True, 80), agreed(True, False, 20)])]),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(100, 120)
    assert result.apple.agreement < Fraction(9, 10)
    assert result.decision == "NO_GO"


def test_false_accept_exactly_one_twentieth_passes() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [agreed(True, True, 20), agreed(False, False, 19), agreed(False, True, 1)],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.false_accept_rate == Fraction(1, 20)
    assert result.apple.false_accept_ok
    assert result.apple.per_child_ok
    assert result.apple.passes
    assert result.decision == "APPLE"


def test_false_accept_one_nineteenth_fails_while_the_child_cap_holds() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [agreed(True, True, 20), agreed(False, False, 18), agreed(False, True, 1)],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.false_accept_rate == Fraction(1, 19)
    assert result.apple.false_accept_rate > Fraction(1, 20)
    assert result.apple.children[0].rate == Fraction(1, 19)
    assert result.apple.children[0].within_cap
    assert result.apple.false_accept_ok is False
    assert result.decision == "NO_GO"


def test_one_extra_false_accept_on_four_hundred_crosses_five_percent() -> None:
    passing = _false_accept_payload(20)
    failing = _false_accept_payload(21)
    passed = evaluate(passing, **FAST)
    failed = evaluate(failing, **FAST)
    assert passed.apple.false_accept_rate == Fraction(1, 20)
    assert passed.decision == "APPLE"
    assert failed.apple.false_accept_rate == Fraction(21, 400)
    assert failed.apple.children[0].within_cap
    assert failed.decision == "NO_GO"


def test_child_cap_exactly_one_tenth_passes_with_pooled_false_accept_at_five_percent() -> None:
    payload = study(
        [
            child(
                "edge",
                6,
                [
                    recording(
                        "edge-r",
                        [agreed(True, True, 100), agreed(False, True, 10), agreed(False, False, 90)],
                    )
                ],
            ),
            child(
                "clean",
                8,
                [recording("clean-r", [agreed(True, True, 100), agreed(False, False, 100)])],
            ),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.children[0].rate == Fraction(1, 10)
    assert result.apple.false_accept_rate == Fraction(1, 20)
    assert result.apple.passes
    assert result.decision == "APPLE"


def test_child_cap_eleven_hundredths_fails_while_pooled_false_accept_is_five_percent() -> None:
    payload = study(
        [
            child(
                "over",
                6,
                [
                    recording(
                        "over-r",
                        [agreed(True, True, 100), agreed(False, True, 11), agreed(False, False, 89)],
                    )
                ],
            ),
            child(
                "clean",
                8,
                [recording("clean-r", [agreed(True, True, 100), agreed(False, False, 120)])],
            ),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.children[0].rate == Fraction(11, 100)
    assert result.apple.false_accept_rate == Fraction(1, 20)
    assert result.apple.false_accept_ok
    assert result.apple.per_child_ok is False
    assert result.decision == "NO_GO"


def test_child_with_no_incorrect_reference_does_not_fail_the_cap() -> None:
    payload = study(
        [
            child("na", 6, [recording("na-r", [agreed(True, True, 30)])]),
            child(
                "some",
                7,
                [
                    recording(
                        "some-r",
                        [agreed(True, True, 30), agreed(False, True, 1), agreed(False, False, 19)],
                    )
                ],
            ),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.children[0].rate is None
    assert result.apple.children[0].within_cap
    assert result.apple.false_accept_rate == Fraction(1, 20)
    assert result.apple.passes
    assert result.decision == "APPLE"


def test_child_cap_pools_that_childs_recordings() -> None:
    # The first recording alone is 1/1. Together with the child's other words it is 1/10.
    payload = study(
        [
            child(
                "split",
                7,
                [
                    recording("hot", [agreed(True, True, 5), agreed(False, True, 1)]),
                    recording("rest", [agreed(True, True, 5), agreed(False, False, 9)]),
                ],
            ),
            child("clean", 8, [recording("clean-r", [agreed(True, True, 20), agreed(False, False, 10)])]),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.children[0].rate == Fraction(1, 10)
    assert result.apple.false_accept_rate == Fraction(1, 20)
    assert result.decision == "APPLE"


def test_splitting_recordings_does_not_hide_a_child_over_the_cap() -> None:
    payload = study(
        [
            child(
                "split",
                7,
                [
                    recording("hot", [agreed(False, True, 2)]),
                    recording("rest", [agreed(False, False, 8)]),
                ],
            ),
            child("clean", 8, [recording("clean-r", [agreed(True, True, 40), agreed(False, False, 30)])]),
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.children[0].rate == Fraction(1, 5)
    assert result.apple.false_accept_rate == Fraction(1, 20)
    assert result.decision == "NO_GO"


def test_false_reject_exactly_one_tenth_passes_with_room_in_agreement() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [agreed(True, True, 90), agreed(True, False, 10), agreed(False, False, 100)],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.false_reject_rate == Fraction(1, 10)
    assert result.apple.agreement == Fraction(190, 200)
    assert result.apple.passes
    assert result.decision == "APPLE"


def test_false_reject_over_one_tenth_fails_while_agreement_stays_above_ninety() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [agreed(True, True, 89), agreed(True, False, 11), agreed(False, False, 100)],
                    )
                ],
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(189, 200)
    assert result.apple.agreement_ok
    assert result.apple.false_reject_rate == Fraction(11, 100)
    assert result.apple.false_reject_ok is False
    assert result.decision == "NO_GO"


def test_undefined_false_reject_does_not_pass() -> None:
    payload = study([child("c", 7, [recording("r", [agreed(False, False, 20)])])])
    result = evaluate(payload, **FAST)
    assert result.apple.agreement == Fraction(1)
    assert result.apple.false_accept_rate == Fraction(0)
    assert result.apple.false_reject_rate is None
    assert result.apple.false_reject_ok is False
    assert result.decision == "NO_GO"


def test_one_child_over_the_cap_is_no_go_for_both_engines() -> None:
    children = []
    for index in range(4):
        children.append(
            child(
                f"c{index}",
                7,
                [
                    recording(
                        f"c{index}-r",
                        [agreed(True, True, 20), agreed(False, True, 1), agreed(False, False, 49)],
                    )
                ],
            )
        )
    children.append(child("x", 8, [recording("x-r", [agreed(True, True, 20), agreed(False, True, 1)])]))
    result = evaluate(study(children), **FAST)
    assert result.apple.false_accept_rate == Fraction(5, 201)
    assert result.apple.false_accept_rate <= Fraction(1, 20)
    assert result.apple.children[-1].rate == Fraction(1)
    assert result.decision == "NO_GO"


def test_resamples_must_be_positive() -> None:
    payload = study([child("c", 7, [recording("r", [agreed(True, True, 10)])])])
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, resamples=0, seed=1)
    assert caught.value.code == "INVALID_INPUT"


def _false_accept_payload(false_accepts: int) -> dict:
    return study(
        [
            child(
                "c",
                6,
                [
                    recording(
                        "r",
                        [
                            agreed(True, True, 400),
                            agreed(False, True, false_accepts),
                            agreed(False, False, 400 - false_accepts),
                        ],
                    )
                ],
            )
        ]
    )
