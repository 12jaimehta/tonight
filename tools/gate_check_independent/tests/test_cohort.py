"""Cohort screening and the results-file schema."""

import json
from pathlib import Path

import pytest

from builders import OMIT, agreed, cell, child, recording, study
from gate_check_independent import evaluate
from gate_check_independent.errors import GateCheckError

FAST = {"resamples": 5, "seed": 1}
EXAMPLES = Path(__file__).resolve().parents[1] / "examples"
WORD = [agreed(True, True, 1)]


def test_missing_age_is_out_of_cohort_and_not_a_decision() -> None:
    payload = study(
        [
            child("kept", 7, [recording("kept-r", [agreed(True, True, 20)])]),
            child("lost", OMIT, [recording("lost-r", [agreed(True, True, 20)])]),
        ]
    )
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"
    assert "lost" in caught.value.message


def test_null_age_is_out_of_cohort() -> None:
    payload = study([child("c", None, [recording("r", WORD)])])
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"
    assert "missing an age" in caught.value.message


@pytest.mark.parametrize("age", [5, 9, 4, 10, 0, -1])
def test_integer_age_outside_6_to_8_is_out_of_cohort(age: int) -> None:
    payload = study([child("c", age, [recording("r", WORD)])])
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"
    assert str(age) in caught.value.message


@pytest.mark.parametrize("age", [6, 7, 8])
def test_ages_6_7_and_8_can_be_scored(age: int) -> None:
    payload = study(
        [child("c", age, [recording("r", [agreed(True, True, 10), agreed(False, False, 1)])])]
    )
    assert evaluate(payload, **FAST).decision == "APPLE"


@pytest.mark.parametrize("school_class", [0, 4, 5, -1])
def test_class_outside_1_to_3_is_out_of_cohort(school_class: int) -> None:
    payload = study([child("c", 7, [recording("r", WORD)], school_class=school_class)])
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"
    assert f"class {school_class}" in caught.value.message


def test_missing_class_is_out_of_cohort() -> None:
    payload = study([child("c", 7, [recording("r", WORD)])])
    del payload["children"][0]["school_class"]
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"
    assert "missing a class" in caught.value.message


def test_null_class_is_out_of_cohort() -> None:
    payload = study([child("c", 7, [recording("r", WORD)], school_class=None)])
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"
    assert "missing a class" in caught.value.message


@pytest.mark.parametrize(
    ("age", "school_class", "warns"),
    [
        (6, 1, False),
        (7, 1, False),
        (8, 1, True),
        (6, 2, False),
        (7, 2, False),
        (8, 2, False),
        (6, 3, True),
        (7, 3, False),
        (8, 3, False),
    ],
)
def test_rule_7_age_class_pairs(age: int, school_class: int, warns: bool) -> None:
    """Expected age is class + 5, and ±1 year does not warn. Mismatches are not rejected."""

    payload = study(
        [
            child(
                "c",
                age,
                [recording("r", [agreed(True, True, 10), agreed(False, False, 1)])],
                school_class=school_class,
            )
        ]
    )
    result = evaluate(payload, **FAST)
    assert result.decision == "APPLE"
    if warns:
        expected_age = school_class + 5
        assert result.warnings == (
            f"child c age {age} is paired with class {school_class}; expected age is {expected_age} ± 1",
        )
    else:
        assert result.warnings == ()


def test_matching_age_and_class_has_no_warning() -> None:
    payload = study(
        [child("c", 8, [recording("r", [agreed(True, True, 10), agreed(False, False, 1)])])]
    )
    result = evaluate(payload, **FAST)
    assert result.warnings == ()
    assert payload["children"][0]["school_class"] == 3


def test_every_out_of_cohort_child_is_named() -> None:
    payload = study(
        [
            child("a", 5, [recording("a-r", WORD)]),
            child("b", None, [recording("b-r", WORD)]),
            child("c", 7, [recording("c-r", WORD)]),
        ]
    )
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"
    assert "a age 5" in caught.value.message
    assert "b is missing an age" in caught.value.message
    assert "c " not in caught.value.message


def test_out_of_range_class_on_a_file_is_rejected() -> None:
    shifted = json.loads((EXAMPLES / "exactly_5_percent_false_accept.json").read_text(encoding="utf-8"))
    shifted["children"][0]["school_class"] = 9
    with pytest.raises(GateCheckError) as caught:
        evaluate(shifted, **FAST)
    assert caught.value.code == "OUT_OF_COHORT"


def test_recording_with_no_sarvam_result_is_unpaired() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "lonely",
                        [{"reference_correct": True, "apple_correct": True, "sarvam_correct": None, "n": 10}],
                    )
                ],
            )
        ]
    )
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "UNPAIRED_RECORDING"
    assert "lonely" in caught.value.message
    assert "no matching pair" in caught.value.message


def test_recording_missing_an_engine_key_is_unpaired() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [recording("half", [{"reference_correct": False, "apple_correct": False, "n": 4}])],
            )
        ]
    )
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "UNPAIRED_RECORDING"
    assert "half" in caught.value.message


def test_one_unpaired_recording_rejects_the_study() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    recording("ok", [agreed(True, True, 10), agreed(False, False, 1)]),
                    recording("missing-apple", [{"reference_correct": True, "sarvam_correct": True, "n": 3}]),
                ],
            )
        ]
    )
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "UNPAIRED_RECORDING"
    assert "missing-apple" in caught.value.message


def test_g33_three_words_without_sarvam_unpair_a_recording_that_still_has_pairs() -> None:
    """G33 / N-31. Dropping the gaps would still be APPLE, so paired words remain."""

    paired_cells = [agreed(True, True, 10), agreed(False, False, 1)]
    alone = study([child("c", 7, [recording("r", paired_cells)])])
    assert evaluate(alone, **FAST).decision == "APPLE"
    gaps = [
        {"reference_correct": True, "apple_correct": True, "sarvam_correct": None, "n": 1},
        {"reference_correct": True, "apple_correct": False, "sarvam_correct": None, "n": 1},
        {"reference_correct": False, "apple_correct": False, "sarvam_correct": None, "n": 1},
    ]
    g33 = study([child("c", 7, [recording("r", paired_cells + gaps)])])
    with pytest.raises(GateCheckError) as caught:
        evaluate(g33, **FAST)
    assert caught.value.code == "UNPAIRED_RECORDING"
    assert "r" in caught.value.message


def test_three_word_objects_without_sarvam_unpair_the_recording() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [
                    {
                        "recording_id": "r",
                        "words": [
                            {"reference_correct": True, "apple_correct": True, "sarvam_correct": True},
                            {"reference_correct": False, "apple_correct": False, "sarvam_correct": False},
                            {"reference_correct": True, "apple_correct": True, "sarvam_correct": None},
                            {"reference_correct": True, "apple_correct": True},
                            {"reference_correct": False, "apple_correct": False, "sarvam_correct": None},
                        ],
                    }
                ],
            )
        ]
    )
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "UNPAIRED_RECORDING"


def test_engine_call_that_is_not_a_boolean_or_null_is_invalid_input() -> None:
    payload = study(
        [
            child(
                "c",
                7,
                [recording("r", [{"reference_correct": True, "apple_correct": True, "sarvam_correct": "yes", "n": 1}])],
            )
        ]
    )
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "INVALID_INPUT"


def test_non_integer_class_is_invalid_input() -> None:
    payload = study([child("c", 7, [recording("r", WORD)], school_class="2")])
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "INVALID_INPUT"


@pytest.mark.parametrize(
    "age",
    ["7", 6.5, 7.0, True, False],
)
def test_non_integer_age_is_invalid_input(age: object) -> None:
    payload = study([child("c", age, [recording("r", WORD)])])
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "INVALID_INPUT"


def test_words_and_cells_describe_the_same_recording() -> None:
    cells = study(
        [
            child(
                "c",
                7,
                [
                    recording(
                        "r",
                        [cell(True, True, False, 2), cell(False, False, True, 1)],
                    )
                ],
            )
        ]
    )
    words = study(
        [
            child(
                "c",
                7,
                [
                    {
                        "recording_id": "r",
                        "words": [
                            {"reference_correct": True, "apple_correct": True, "sarvam_correct": False},
                            {"reference_correct": True, "apple_correct": True, "sarvam_correct": False, "note": "extra"},
                            {"reference_correct": False, "apple_correct": False, "sarvam_correct": True},
                        ],
                    }
                ],
            )
        ]
    )
    assert evaluate(cells, **FAST) == evaluate(words, **FAST)


def test_duplicate_cells_are_summed() -> None:
    combined = study([child("c", 7, [recording("r", [agreed(True, True, 19), agreed(False, False, 1)])])])
    split = study(
        [
            child(
                "c",
                7,
                [recording("r", [agreed(True, True, 10), agreed(True, True, 9), agreed(False, False, 1)])],
            )
        ]
    )
    assert evaluate(combined, **FAST) == evaluate(split, **FAST)


@pytest.mark.parametrize(
    ("payload", "fragment"),
    [
        ([], "JSON object"),
        ({"children": []}, "schema_version"),
        ({"schema_version": True, "children": [child("c", 7, [recording("r", WORD)])]}, "schema_version"),
        ({"schema_version": 2, "children": [child("c", 7, [recording("r", WORD)])]}, "schema_version"),
        (study([]), "children"),
        (study([child("c", 7, [])]), "recordings"),
        (study([child("", 7, [recording("r", WORD)])]), "child_id"),
        (
            study(
                [
                    child("c", 7, [recording("r", WORD)]),
                    child("c", 8, [recording("s", WORD)]),
                ]
            ),
            "duplicate",
        ),
        (
            study([child("c", 7, [recording("r", WORD), recording("r", WORD)])]),
            "duplicate",
        ),
        (study([child("c", 7, [recording("r", [])])]), "cells"),
        (study([child("c", 7, [{"recording_id": "r"}])]), "exactly one"),
        (
            study(
                [
                    child(
                        "c",
                        7,
                        [{"recording_id": "r", "cells": WORD, "words": [{"reference_correct": True}]}],
                    )
                ]
            ),
            "exactly one",
        ),
        (
            study([child("c", 7, [recording("r", [agreed(True, True, -1)])])]),
            "non-negative",
        ),
        (
            study(
                [
                    child(
                        "c",
                        7,
                        [recording("r", [{"reference_correct": 1, "apple_correct": True, "sarvam_correct": True, "n": 1}])],
                    )
                ]
            ),
            "boolean",
        ),
    ],
)
def test_schema_errors(payload: object, fragment: str) -> None:
    with pytest.raises(GateCheckError) as caught:
        evaluate(payload, **FAST)
    assert caught.value.code == "INVALID_INPUT"
    assert fragment in caught.value.message
