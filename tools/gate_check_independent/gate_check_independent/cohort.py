"""Parse the documented results document into counted recordings.

Age and class are screened here, before any engine is scored. A missing age
or class, an integer age outside 6–8, and an integer class outside 1–3 are
``OUT_OF_COHORT``. A decision is never returned for a cohort that still
contains such a child.

Rule 7: the expected age is class + 5, and one year either side is fine.
Inside the cohort that warns only for class 1 with age 8, and class 3 with
age 6. A mismatch is a warning, never a rejection.

A word missing either engine result is not a pair. If any word in a
recording is missing an engine result, that recording is
``UNPAIRED_RECORDING``, including when other words in it were judged by
both engines.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from gate_check_independent.errors import GateCheckError
from gate_check_independent.types import (
    SCHEMA_VERSION,
    VALID_AGES,
    VALID_CLASSES,
    Child,
    Cohort,
    RecordingTotals,
)

def parse_cohort(payload: object) -> Cohort:
    """Validate ``payload`` and return the cohort the gate will score."""

    if not isinstance(payload, Mapping):
        raise GateCheckError("INVALID_INPUT", "results must be a JSON object")
    version = payload.get("schema_version")
    if isinstance(version, bool) or version != SCHEMA_VERSION:
        raise GateCheckError(
            "INVALID_INPUT",
            f"schema_version must be the integer {SCHEMA_VERSION}",
        )
    raw_children = payload.get("children")
    if not isinstance(raw_children, list) or not raw_children:
        raise GateCheckError("INVALID_INPUT", "children must be a non-empty list")

    parsed: list[_PendingChild] = []
    seen_children: set[str] = set()
    seen_recordings: set[str] = set()
    for index, raw_child in enumerate(raw_children):
        pending = _parse_child(raw_child, f"children[{index}]", seen_recordings)
        if pending.child_id in seen_children:
            raise GateCheckError(
                "INVALID_INPUT",
                f"children[{index}].child_id: duplicate id {pending.child_id!r}",
            )
        seen_children.add(pending.child_id)
        parsed.append(pending)

    _screen_eligibility(parsed)
    confirmed: list[Child] = []
    warnings: list[str] = []
    for child in parsed:
        if child.age is None or child.school_class is None:
            raise GateCheckError("OUT_OF_COHORT", f"{child.child_id} failed the cohort screen")
        confirmed.append(
            Child(
                child_id=child.child_id,
                age=child.age,
                school_class=child.school_class,
                recordings=child.recordings,
            )
        )
        warning = _age_class_warning(child.child_id, child.age, child.school_class)
        if warning is not None:
            warnings.append(warning)
    return Cohort(children=tuple(confirmed), warnings=tuple(warnings))


class _PendingChild:
    def __init__(
        self,
        child_id: str,
        age: int | None,
        school_class: int | None,
        recordings: tuple[RecordingTotals, ...],
    ) -> None:
        self.child_id = child_id
        self.age = age
        self.school_class = school_class
        self.recordings = recordings


def _screen_eligibility(children: list[_PendingChild]) -> None:
    problems: list[str] = []
    for child in children:
        if child.age is None:
            problems.append(f"{child.child_id} is missing an age")
        elif child.age not in VALID_AGES:
            problems.append(f"{child.child_id} age {child.age} is outside 6-8")
        if child.school_class is None:
            problems.append(f"{child.child_id} is missing a class")
        elif child.school_class not in VALID_CLASSES:
            problems.append(f"{child.child_id} class {child.school_class} is outside 1-3")
    if not problems:
        return
    joined = "; ".join(problems)
    raise GateCheckError(
        "OUT_OF_COHORT",
        f"{len(problems)} cohort member(s) outside ages 6-8 and classes 1-3: {joined}",
    )


def _parse_child(
    raw: object,
    path: str,
    seen_recordings: set[str],
) -> _PendingChild:
    body = _object(raw, path)
    child_id = _identifier(body.get("child_id"), f"{path}.child_id")
    age = _parse_age(body, f"{path}.age")
    school_class = _parse_class(body, f"{path}.school_class")
    raw_recordings = body.get("recordings")
    if not isinstance(raw_recordings, list) or not raw_recordings:
        raise GateCheckError("INVALID_INPUT", f"{path}.recordings must be a non-empty list")
    recordings: list[RecordingTotals] = []
    for index, raw_recording in enumerate(raw_recordings):
        recording = _parse_recording(
            raw_recording,
            f"{path}.recordings[{index}]",
            child_id,
            seen_recordings,
        )
        recordings.append(recording)
    return _PendingChild(child_id, age, school_class, tuple(recordings))


def _parse_age(body: Mapping[str, Any], path: str) -> int | None:
    """Return an integer age, or None when the age is absent or JSON null.

    Non-integers are schema errors. The cohort screen decides whether a
    returned integer is inside 6–8.
    """

    if "age" not in body or body.get("age") is None:
        return None
    age = body.get("age")
    if isinstance(age, bool) or not isinstance(age, int):
        raise GateCheckError("INVALID_INPUT", f"{path} must be an integer, or null if unknown")
    return age


def _parse_class(body: Mapping[str, Any], path: str) -> int | None:
    """Return an integer class, or None when the class is absent or JSON null."""

    if "school_class" not in body or body.get("school_class") is None:
        return None
    school_class = body.get("school_class")
    if isinstance(school_class, bool) or not isinstance(school_class, int):
        raise GateCheckError("INVALID_INPUT", f"{path} must be an integer, or null if unknown")
    return school_class


def _parse_recording(
    raw: object,
    path: str,
    child_id: str,
    seen_recordings: set[str],
) -> RecordingTotals:
    body = _object(raw, path)
    recording_id = _identifier(body.get("recording_id"), f"{path}.recording_id")
    if recording_id in seen_recordings:
        raise GateCheckError(
            "INVALID_INPUT",
            f"{path}.recording_id: duplicate id {recording_id!r}",
        )
    seen_recordings.add(recording_id)
    has_cells = "cells" in body
    has_words = "words" in body
    if has_cells == has_words:
        raise GateCheckError(
            "INVALID_INPUT",
            f"{path} must contain exactly one of 'cells' or 'words'",
        )
    if has_cells:
        counts, saw_pair, saw_gap = _counts_from_cells(body.get("cells"), f"{path}.cells")
    else:
        counts, saw_pair, saw_gap = _counts_from_words(body.get("words"), f"{path}.words")
    if saw_gap or not saw_pair:
        raise GateCheckError(
            "UNPAIRED_RECORDING",
            f"recording {recording_id} has no matching pair",
        )
    return _totals(recording_id, child_id, counts, path)


def _age_class_warning(child_id: str, age: int, school_class: int) -> str | None:
    """Rule 7. Expected age is class + 5, and ±1 year does not warn.

    On the ages 6–8 and classes 1–3 grid this warns only for class 1 with
    age 8, and class 3 with age 6.
    """

    expected_age = school_class + 5
    if abs(age - expected_age) <= 1:
        return None
    return (
        f"child {child_id} age {age} is paired with class {school_class}; "
        f"expected age is {expected_age} ± 1"
    )


def _counts_from_cells(
    raw: object,
    path: str,
) -> tuple[dict[tuple[bool, bool, bool], int], bool, bool]:
    if not isinstance(raw, list) or not raw:
        raise GateCheckError("INVALID_INPUT", f"{path} must be a non-empty list")
    counts: dict[tuple[bool, bool, bool], int] = {}
    saw_pair = False
    saw_gap = False
    for index, item in enumerate(raw):
        cell = _object(item, f"{path}[{index}]")
        key, paired = _judged_pattern(cell, f"{path}[{index}]")
        count = _count(cell.get("n"), f"{path}[{index}].n")
        if not paired:
            saw_gap = True
            continue
        saw_pair = True
        if key is None:
            continue
        counts[key] = counts.get(key, 0) + count
    return counts, saw_pair, saw_gap


def _counts_from_words(
    raw: object,
    path: str,
) -> tuple[dict[tuple[bool, bool, bool], int], bool, bool]:
    if not isinstance(raw, list) or not raw:
        raise GateCheckError("INVALID_INPUT", f"{path} must be a non-empty list")
    counts: dict[tuple[bool, bool, bool], int] = {}
    saw_pair = False
    saw_gap = False
    for index, item in enumerate(raw):
        word = _object(item, f"{path}[{index}]")
        key, paired = _judged_pattern(word, f"{path}[{index}]")
        if not paired:
            saw_gap = True
            continue
        saw_pair = True
        if key is None:
            continue
        counts[key] = counts.get(key, 0) + 1
    return counts, saw_pair, saw_gap


def _judged_pattern(
    body: Mapping[str, Any],
    path: str,
) -> tuple[tuple[bool, bool, bool] | None, bool]:
    """Return ``(pattern, paired)``.

    ``paired`` is false when either engine call is missing or JSON null.
    Any such word makes the whole recording ``UNPAIRED_RECORDING``. A missing
    ``reference_correct`` is a schema error. JSON null for the reference, with
    both engines present, is unjudged: ``paired`` is true and the pattern is
    None, so the word is excluded from agreement, false-accept, and false-reject.
    """

    if "reference_correct" not in body:
        raise GateCheckError("INVALID_INPUT", f"{path}.reference_correct is required")
    reference = body.get("reference_correct")
    if reference is not None and not isinstance(reference, bool):
        raise GateCheckError("INVALID_INPUT", f"{path}.reference_correct must be a boolean or null")
    apple = _optional_boolean(body, "apple_correct", path)
    sarvam = _optional_boolean(body, "sarvam_correct", path)
    if apple is None or sarvam is None:
        return None, False
    if reference is None:
        return None, True
    return (reference, apple, sarvam), True


def _totals(
    recording_id: str,
    child_id: str,
    counts: dict[tuple[bool, bool, bool], int],
    path: str,
) -> RecordingTotals:
    words = 0
    reference_correct = 0
    apple_matches = 0
    sarvam_matches = 0
    apple_false_accepts = 0
    sarvam_false_accepts = 0
    apple_false_rejects = 0
    sarvam_false_rejects = 0
    for (reference_correct_bit, apple_correct, sarvam_correct), count in counts.items():
        words += count
        if reference_correct_bit:
            reference_correct += count
        if apple_correct == reference_correct_bit:
            apple_matches += count
        elif reference_correct_bit:
            apple_false_rejects += count
        else:
            apple_false_accepts += count
        if sarvam_correct == reference_correct_bit:
            sarvam_matches += count
        elif reference_correct_bit:
            sarvam_false_rejects += count
        else:
            sarvam_false_accepts += count
    if words == 0:
        raise GateCheckError("INVALID_INPUT", f"{path} has no judged words")
    return RecordingTotals(
        recording_id=recording_id,
        child_id=child_id,
        words=words,
        reference_correct=reference_correct,
        apple_matches=apple_matches,
        sarvam_matches=sarvam_matches,
        apple_false_accepts=apple_false_accepts,
        sarvam_false_accepts=sarvam_false_accepts,
        apple_false_rejects=apple_false_rejects,
        sarvam_false_rejects=sarvam_false_rejects,
    )


def _object(raw: object, path: str) -> Mapping[str, Any]:
    if not isinstance(raw, Mapping):
        raise GateCheckError("INVALID_INPUT", f"{path} must be a JSON object")
    return raw


def _identifier(raw: object, path: str) -> str:
    if not isinstance(raw, str) or raw == "":
        raise GateCheckError("INVALID_INPUT", f"{path} must be a non-empty string")
    return raw


def _optional_boolean(body: Mapping[str, Any], key: str, path: str) -> bool | None:
    """An engine call. Missing or JSON null means this engine did not score the word."""

    if key not in body or body.get(key) is None:
        return None
    value = body.get(key)
    if not isinstance(value, bool):
        raise GateCheckError("INVALID_INPUT", f"{path}.{key} must be a boolean, or null if this engine has no result")
    return value


def _count(raw: object, path: str) -> int:
    if isinstance(raw, bool) or not isinstance(raw, int) or raw < 0:
        raise GateCheckError("INVALID_INPUT", f"{path} must be a non-negative integer")
    return raw
