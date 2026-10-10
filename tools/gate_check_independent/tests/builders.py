"""Small builders for results documents. OMIT leaves the age key off the child."""

from __future__ import annotations

from typing import Any

OMIT = object()
_CLASS_FOR_AGE = {6: 1, 7: 2, 8: 3}


def cell(reference: bool | None, apple: bool, sarvam: bool, n: int) -> dict[str, Any]:
    return {
        "reference_correct": reference,
        "apple_correct": apple,
        "sarvam_correct": sarvam,
        "n": n,
    }


def agreed(reference: bool, correct: bool, n: int) -> dict[str, Any]:
    """A cell where Apple and Sarvam make the same call."""

    return cell(reference, correct, correct, n)


def recording(recording_id: str, cells: list[dict[str, Any]]) -> dict[str, Any]:
    return {"recording_id": recording_id, "cells": cells}


def child(
    child_id: str,
    age: Any = OMIT,
    recordings: list[dict[str, Any]] | None = None,
    **extra: Any,
) -> dict[str, Any]:
    body: dict[str, Any] = {"child_id": child_id, "recordings": recordings or []}
    if age is not OMIT:
        body["age"] = age
    if isinstance(age, int) and not isinstance(age, bool) and age in _CLASS_FOR_AGE:
        body["school_class"] = _CLASS_FOR_AGE[age]
    else:
        body["school_class"] = 1
    body.update(extra)
    return body


def study(children: list[dict[str, Any]], **extra: Any) -> dict[str, Any]:
    body: dict[str, Any] = {"schema_version": 1, "children": children}
    body.update(extra)
    return body
