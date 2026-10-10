"""Parse the documented results document into counted recordings.

Age and class are screened here, before any engine is scored. A missing age
or class, an integer age outside 6–8, and an integer class outside 1–3 are
``OUT_OF_COHORT``. A decision is never returned for a cohort that still
contains such a child. An in-range age/class pair other than 6→1, 7→2, 8→3
is a warning on the cohort.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from gate_check_independent.errors import GateCheckError
from gate_check_independent.types import (
    EXPECTED_CLASS_FOR_AGE,
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
        expected = EXPECTED_CLASS_FOR_AGE[child.age]
        if child.school_class != expected:
            warnings.append(
                f"child {child.child_id} age {child.age} is paired with class "
                f"{child.school_class}; expected class {expected}"
            )
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
        counts = _counts_from_cells(body.get("cells"), f"{path}.cells")
    else:
        counts = _counts_from_words(body.get("words"), f"{path}.words")
    return _totals(recording_id, child_id, counts, path)


def _counts_from_cells(raw: object, path: str) -> dict[tuple[bool, bool, bool], int]:
    if not isinstance(raw, list) or not raw:
        raise GateCheckError("INVALID_INPUT", f"{path} must be a non-empty list")
    counts: dict[tuple[bool, bool, bool], int] = {}
    for index, item in enumerate(raw):
        cell = _object(item, f"{path}[{index}]")
        key = _judged_pattern(cell, f"{path}[{index}]")
        count = _count(cell.get("n"), f"{path}[{index}].n")
        if key is None:
            continue
        counts[key] = counts.get(key, 0) + count
    return counts


def _counts_from_words(raw: object, path: str) -> dict[tuple[bool, bool, bool], int]:
    if not isinstance(raw, list) or not raw:
        raise GateCheckError("INVALID_INPUT", f"{path} must be a non-empty list")
    counts: dict[tuple[bool, bool, bool], int] = {}
    for index, item in enumerate(raw):
        word = _object(item, f"{path}[{index}]")
        key = _judged_pattern(word, f"{path}[{index}]")
        if key is None:
            continue
        counts[key] = counts.get(key, 0) + 1
    return counts


def _judged_pattern(body: Mapping[str, Any], path: str) -> tuple[bool, bool, bool] | None:
    """Return the judged pattern, or None when the adult left the word unjudged.

    A missing ``reference_correct`` is a schema error. JSON null is unjudged
    and is excluded from agreement, false-accept, and false-reject.
    """

    if "reference_correct" not in body:
        raise GateCheckError("INVALID_INPUT", f"{path}.reference_correct is required")
    reference = body.get("reference_correct")
    apple = _boolean(body.get("apple_correct"), f"{path}.apple_correct")
    sarvam = _boolean(body.get("sarvam_correct"), f"{path}.sarvam_correct")
    if reference is None:
        return None
    if not isinstance(reference, bool):
        raise GateCheckError("INVALID_INPUT", f"{path}.reference_correct must be a boolean or null")
    return (reference, apple, sarvam)


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


def _boolean(raw: object, path: str) -> bool:
    if not isinstance(raw, bool):
        raise GateCheckError("INVALID_INPUT", f"{path} must be a boolean")
    return raw


def _count(raw: object, path: str) -> int:
    if isinstance(raw, bool) or not isinstance(raw, int) or raw < 0:
        raise GateCheckError("INVALID_INPUT", f"{path} must be a non-negative integer")
    return raw
