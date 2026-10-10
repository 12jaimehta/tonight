# Independent M0 gate check

Clean-room GO/NO-GO check for the Tonight speech-engine study. It reads a JSON results file and prints `APPLE`, `SARVAM`, or `NO_GO`.

The rules are the M0 gate computation rules (PM, Oct 10 2026).

```bash
cd tools/gate_check_independent
python -m pip install "pytest>=8,<9"
python -m pytest
python -m gate_check_independent examples/exactly_5pp.json
```

Text mode prints one decision token on stdout. Stderr logs `seed=<n>` and any age/class warnings. `NO_GO` exits 0. `OUT_OF_COHORT`, `INVALID_STUDY`, and `INVALID_INPUT` exit 2. `--format json` prints rates as numerator/denominator pairs and logs the seed in the report.

```bash
python -m gate_check_independent examples/exactly_5pp.json --format json
```

## Decision

Age and class are screened first. A missing age, a null age, or an integer age outside {6, 7, 8} is `OUT_OF_COHORT`. A missing class, a null class, or an integer class outside {1, 2, 3} is the same error. The child is not dropped and is not scored.

An in-range age and class that are not the year-by-year pair below is a warning. The study is still scored. The computation rules require that warning and do not publish another pairing; this is the one-year step across classes 1–3.

| Age | Class |
|---|---|
| 6 | 1 |
| 7 | 2 |
| 8 | 3 |

Each engine is then scored on the pooled judged words:

| Bar | Passes when |
|---|---|
| Agreement | matches / judged words ≥ 9/10 |
| Pooled false-accept | false accepts / reference-incorrect words ≤ 1/20 |
| Per-child false-accept | every child with reference-incorrect words is ≤ 1/10 |
| False-reject | false rejects / reference-correct words ≤ 1/10 |

There is no per-child false-reject cap. A match is an engine call equal to the adult reference. A false accept is a reference-incorrect word the engine called correct. A false reject is a reference-correct word the engine called incorrect. Words the adult left unjudged (`reference_correct: null`) are excluded. Comparisons use exact rationals.

A recording with no reference-correct words is left out of the false-reject count. A recording with no reference-incorrect words adds 0 to the false-accept numerator and denominator. A child with no reference-incorrect words is skipped for the per-child cap. If the pooled false-accept denominator is 0, or the pooled false-reject denominator is 0, the result is `INVALID_STUDY` and the study does not pass.

1. Both engines pass, and Sarvam clearly beats Apple: `SARVAM`.
2. Both pass, and Sarvam does not clearly beat Apple: `APPLE`.
3. Only one engine passes: that engine.
4. Neither passes: `NO_GO`.

Sarvam clearly beats Apple only when all three hold:

- pooled agreement(Sarvam) − pooled agreement(Apple) ≥ 5/100
- the child-cluster bootstrap interval's lower end is strictly greater than 0
- pooled false-accept(Sarvam) ≤ pooled false-accept(Apple)

The 5-point margin is on the full-sample pooled difference. An endpoint of exactly 0 overlaps zero, so Apple wins. A tie on false-accept is not worse.

Whisper is a study baseline and is not a decision outcome.

## Bootstrap

The interval is a 95% two-sided percentile interval from 10,000 draws. The seed is logged with the result (default `20261009`).

The cluster is the child. Every recording of a drawn child stays together. The statistic on each draw is the word-weighted pooled agreement difference. The generator is `random.Random`, and each draw is `randrange` over the child list. The percentile is Hyndman–Fan type 7, in exact rationals.

`--seed`, `--resamples`, and `--confidence` override the defaults and the values used are the ones logged. `--confidence` accepts `95/100` or `0.95`.

## Results file

`schema_version` must be `1`. `children` is a non-empty list. Each child has a non-empty string `child_id`, an integer `age`, an integer `school_class`, and a non-empty `recordings` list. Each recording has a unique `recording_id` and exactly one of `cells` or `words`.

A cell is one pattern of the booleans plus a non-negative integer `n`. `reference_correct` may be `null` for an unjudged word. Duplicate judged patterns in one recording are added together. A word object is one judged or unjudged token. Both engines are judged on the same tokens.

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

| Example | Result |
|---|---|
| `examples/exactly_5_percent_false_accept.json` | `APPLE` |
| `examples/exactly_5pp.json` | `SARVAM` |
| `examples/sarvam_only.json` | `SARVAM` |
| `examples/child_false_accept_cap.json` | `NO_GO` |
| `examples/exactly_090.json` | `INVALID_STUDY` |
| `examples/missing_age.json` | `OUT_OF_COHORT` |

`exactly_090.json` is pooled agreement 36/40 = 9/10 with no reference-incorrect words, so the false-accept denominator is 0. `exactly_5pp.json` is a uniform +5 point gap (12/240) whose interval is that point. `sarvam_only.json` is Apple below the agreement bar and Sarvam above it.
