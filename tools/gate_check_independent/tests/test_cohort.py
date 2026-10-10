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
    payload = study([child("c", age, [recording("r", [agreed(True, True, 10)])])])
    assert evaluate(payload, **FAST).decision == "APPLE"


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


def test_school_class_does_not_change_the_decision() -> None:
    base = json.loads((EXAMPLES / "exactly_090.json").read_text(encoding="utf-8"))
    shifted = json.loads((EXAMPLES / "exactly_090.json").read_text(encoding="utf-8"))
    shifted["children"][0]["school_class"] = 9
    shifted["children"][1]["school_class"] = "not-a-class"
    shifted["cohort"] = "pilot"
    assert evaluate(base, **FAST) == evaluate(shifted, **FAST)


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
    combined = study([child("c", 7, [recording("r", [agreed(True, True, 19)])])])
    split = study(
        [child("c", 7, [recording("r", [agreed(True, True, 10), agreed(True, True, 9)])])]
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
