# Gate harness fixture schema

This is the M0 results file from the independent checker README. Rates in a results report are numerator/denominator pairs, not floats. Outcome codes are `APPLE`, `SARVAM`, `NO_GO`, `OUT_OF_COHORT`, `INVALID_STUDY`, `UNPAIRED_RECORDING`, and `INVALID_INPUT`.

`schema_version` must be `1`. `children` is a non-empty list. Each child has a non-empty string `child_id`, an integer `age`, an integer `school_class`, and a non-empty `recordings` list. Each recording has a unique `recording_id` and exactly one of `cells` or `words`.

A cell is one pattern of the booleans plus a non-negative integer `n`. `reference_correct` may be `null` for an unjudged word. Duplicate judged patterns in one recording are added together. A word object is one judged or unjudged token. Both engines are judged on the same tokens.

`apple_correct` or `sarvam_correct` may be missing or `null` when that engine has no result. That word is not correct and not incorrect, and it is left out of the counts. A recording that then has no word judged by both engines is `UNPAIRED_RECORDING`. That is an input error. The study is not scored, so the recording does not pass or fail the study by itself.

```json
{
  "schema_version": 1,
  "children": [
    {
      "child_id": "c1",
      "age": 7,
      "school_class": 2,
      "recordings": [
        {
          "recording_id": "c1-passage",
          "cells": [
            {"reference_correct": true, "apple_correct": true, "sarvam_correct": true, "n": 180},
            {"reference_correct": true, "apple_correct": false, "sarvam_correct": true, "n": 12},
            {"reference_correct": true, "apple_correct": false, "sarvam_correct": false, "n": 8},
            {"reference_correct": false, "apple_correct": false, "sarvam_correct": false, "n": 40}
          ]
        }
      ]
    }
  ]
}
```

## Screening

| Input | Code |
|---|---|
| Missing age, JSON null age, or age outside {6, 7, 8} | `OUT_OF_COHORT` |
| Missing class, JSON null class, or class outside {1, 2, 3} | `OUT_OF_COHORT` |
| In-range age more than 1 year from school class + 5 | warning only; the study is still scored |
| Pooled false-accept or false-reject denominator is 0 | `INVALID_STUDY` |
| Schema mismatch | `INVALID_INPUT` |
| Recording with no word judged by both engines | `UNPAIRED_RECORDING` |

The child is not dropped and is not scored when the code is `OUT_OF_COHORT`.

Expected age is school class + 5, tolerance ±1. Ages stay in {6, 7, 8} and classes stay in {1, 2, 3}; anything outside that is `OUT_OF_COHORT`, not a warning. Inside that range the warning fires only for class 1 with age 8 and class 3 with age 6. The other seven combinations do not warn. A mismatch never rejects the study. A pooled false-accept or false-reject denominator of 0 is still `INVALID_STUDY` and never passes.

This warning is narrower than the independent checker's exact pairs 6→1, 7→2, and 8→3. The results JSON field names stay the same (`decision`, `seed`, `warnings`, `interval`, and the rest of this file). The checker is not copied into this harness.

## Pass bar

Agreement is matches / judged words. Unjudged words (`reference_correct: null`) are excluded. A recording with no reference-correct words is left out of the false-reject count. A recording with no reference-incorrect words adds 0 to the false-accept numerator and denominator. A child with no reference-incorrect words is skipped for the per-child false-accept cap. Pooled false-accept allows a tie at 1/20.

| Bar | Passes when |
|---|---|
| Agreement | ≥ 9/10 |
| Pooled false-accept | ≤ 1/20 |
| Per-child false-accept | every child with reference-incorrect words is ≤ 1/10 |
| False-reject | ≤ 1/10 |

There is no per-child false-reject cap.

## Decision

1. Both engines pass, and Sarvam clearly beats Apple: `SARVAM`.
2. Both pass, and Sarvam does not clearly beat Apple: `APPLE`.
3. Only one engine passes: that engine.
4. Neither passes: `NO_GO`.

Sarvam clearly beats Apple only when all three hold:

- pooled agreement(Sarvam) − pooled agreement(Apple) ≥ 5/100
- the child-cluster bootstrap interval's lower end is strictly greater than 0
- pooled false-accept(Sarvam) ≤ pooled false-accept(Apple)

A tie on false-accept is not worse. An interval endpoint of exactly 0 stays `APPLE`.

## Bootstrap

95% two-sided percentile interval, 10,000 resamples, Hyndman–Fan type 7, seed `20261009`. The seed is a top-level `seed` on the results JSON and on `interval.seed`. Draws are `random.Random.randrange` over the child list. Every recording of a drawn child stays together.

## Results JSON

`schema_version`, `decision`, `seed`, `warnings`, `agreement_delta` (`numerator`, `denominator`), `apple`, `sarvam`, `clearly_beats`, and `interval` (`method`, `generator`, `confidence`, `resamples`, `seed`, `low`, `high`, `strictly_above_zero`).

Error JSON is `{ "error": "OUT_OF_COHORT" | "INVALID_STUDY" | "UNPAIRED_RECORDING" | "INVALID_INPUT", "message": "..." }`.

Large cohorts are built from cell counts in the test. The round-2 `*.golden.json` files are not expected results. QA goldens live in `tests/gate-goldens/`.

| Fixture | Result |
|---|---|
| `met36.json` | `SARVAM` (only Sarvam passes; denominators are defined) |
| `met34.json` | `APPLE` (both pass, Sarvam false-accept is worse) |
| `met13.json` | `OUT_OF_COHORT` |
| `met28.json` | `UNPAIRED_RECORDING` |
