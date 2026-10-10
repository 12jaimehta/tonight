# Independent M0 gate check

Clean-room GO/NO-GO check for the Tonight speech-engine study. It reads a JSON results file and prints `APPLE`, `SARVAM`, or `NO_GO`.

The rules below are this program's reading of the M0 decisions paragraph, the locked ages 6–8, the updated T-006 decision rule, and the QA expected results (probes A–H, including MET-13, MET-34, and MET-36). Where that material does not specify a procedure, the choice is listed under [Where the plan is silent](#where-the-plan-is-silent) rather than left implicit.

```bash
cd tools/gate_check_independent
python -m pip install "pytest>=8,<9"
python -m pytest
python -m gate_check_independent examples/exactly_090.json
```

Text mode prints one token and nothing else. `NO_GO` exits 0. `OUT_OF_COHORT` and `INVALID_INPUT` exit 2, with the explanation on stderr. `--format json` prints the rates as numerator/denominator pairs.

```bash
python -m gate_check_independent examples/exactly_5pp.json --format json --seed 20261009
```

## Decision

Age is screened first. A child with no age, a null age, or an integer age outside {6, 7, 8} stops the run with `OUT_OF_COHORT`. That child is not dropped and is not scored.

Each engine is then scored on the pooled word judgments:

| Bar | Passes when |
|---|---|
| Agreement | matches / words ≥ 9/10 |
| Pooled false-accept | false accepts / reference-incorrect words ≤ 1/20, or there are no reference-incorrect words |
| Per-child false-accept | every child is ≤ 1/10, and a child with no reference-incorrect words is skipped |
| False-reject | false rejects / reference-correct words ≤ 1/10, and the rate is defined |

A match is an engine call equal to the adult reference. A false accept is a reference-incorrect word the engine called correct (an omitted or substituted word marked correct). A false reject is a reference-correct word the engine called incorrect. Comparisons use exact rationals.

1. Both engines pass, and Sarvam clearly beats Apple: `SARVAM`.
2. Both pass, and Sarvam does not clearly beat Apple: `APPLE`.
3. Only one engine passes: that engine.
4. Neither passes: `NO_GO`.

Sarvam clearly beats Apple only when all three hold:

- pooled agreement(Sarvam) − pooled agreement(Apple) ≥ 5/100
- the paired bootstrap interval's lower end is strictly greater than 0
- pooled false-accept(Sarvam) ≤ pooled false-accept(Apple); a rate with no reference-incorrect words counts as 0

The 5-point margin is on the full-sample pooled difference. The interval has to sit strictly above zero. An endpoint of exactly 0 overlaps zero, so Apple wins. The interval does not also have to clear 5 points.

Whisper is a study baseline and is not a decision outcome.

## Results file

`schema_version` must be `1`. `children` is a non-empty list. Each child has a non-empty string `child_id`, an integer `age`, and a non-empty `recordings` list. Each recording has a unique `recording_id` and exactly one of `cells` or `words`.

A cell is one pattern of the three booleans plus a non-negative integer `n`. Duplicate patterns in one recording are added together. A word is one judged token; the same three booleans are required. Both engines are judged on those same tokens.

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
            {"reference_correct": true, "apple_correct": true, "sarvam_correct": true, "n": 90},
            {"reference_correct": true, "apple_correct": false, "sarvam_correct": true, "n": 5},
            {"reference_correct": true, "apple_correct": false, "sarvam_correct": false, "n": 5}
          ]
        }
      ]
    }
  ]
}
```

`school_class` and any other unknown field are ignored. The recording objects are the bootstrap clusters: keep one take of a passage as one recording. A file with a single recording makes the interval a single point, because every resample is that recording.

| Example | Result |
|---|---|
| `examples/exactly_090.json` | `APPLE` |
| `examples/exactly_5_percent_false_accept.json` | `APPLE` |
| `examples/exactly_5pp.json` | `SARVAM` |
| `examples/sarvam_only.json` | `SARVAM` |
| `examples/child_false_accept_cap.json` | `NO_GO` |
| `examples/missing_age.json` | `OUT_OF_COHORT` |

`exactly_090.json` is pooled agreement 36/40 = 9/10 from child rates 19/20 and 17/20, with false-reject 4/40 = 1/10. `exactly_5pp.json` is a uniform +5 point gap whose interval is the point 5/100. `sarvam_only.json` is Apple at 85/100 and Sarvam at 97/100.

## Bootstrap

The plan asks for a paired interval on the same recordings and says an interval that overlaps zero means Apple wins. It does not name the generator, the seed, the draw count, the confidence level, or the quantile.

This checker uses:

- generator `random.Random` (MT19937), seeded once per call
- draws `randrange` over the recording list, with no further mixing
- default seed `20261009`, default `10000` resamples, default two-sided confidence `95/100`
- statistic: word-weighted pooled agreement difference on each resample
- Hyndman–Fan type-7 percentile, computed in rationals

`--seed`, `--resamples`, and `--confidence` override the defaults. The same seed replays the same interval. `--confidence` accepts `95/100` or `0.95`.

## Where the plan is silent

These are the points the source notes do not settle. The behaviour in this repo is the choice after each one.

- **Confidence, draw count, quantile, and generator.** Not stated. Defaults are 95% two-sided, 10,000 resamples, type-7 percentiles, and `random.Random` with seed `20261009`.
- **Cluster when a child has several recordings.** The note says a paired test on the same recordings. This checker resamples recordings independently and word-weights them. It does not keep every recording of a child inside one cluster. The per-child false-accept cap still pools all of that child's recordings.
- **False-reject as a pass bar.** The M0 decisions paragraph says false-reject ≤ 10% is part of the gate. The shorter T-006 update names agreement and false-accept only. This checker treats pooled false-reject ≤ 10% as a pass bar. It is not applied per child; the note states a per-child cap only for false-accept.
- **False-reject with no reference-correct words.** The rate is undefined. The engine does not pass.
- **Pooled false-accept with no reference-incorrect words.** Treated as not applicable and as passing (compared as 0). The per-child cap skips those children. The QA notes describe that per-child case as n/a.
- **School class.** Recruitment is classes 1–3, and the QA write-up describes a screen that also looked at class. The only required error result is a missing age (`OUT_OF_COHORT`). This checker screens age only. `school_class` does not affect the decision.
- **Out-of-range ages.** MET-13 names `OUT_OF_COHORT` for a missing age. An integer outside 6–8 uses that same code. A boolean, a string, or a non-integer number is `INVALID_INPUT`.
- **"No worse on false-accept."** Compared on the pooled rates. Equal rates are allowed. Per-child rates are not compared pairwise; they are already a pass/fail cap. Both engines see the same reference, so the denominators match.
- **Agreement counting.** Implemented as matches / judged words. The plan says word-level agreement of the app against the adult and that pooled ratios are integer rationals. It does not give a second formula (for example kappa, or a rate taken only over reference-correct words).
- **Results-file layout.** Not specified. The schema in this directory is the one the CLI reads.
- **Insertions.** Not a separate input. A false accept is a reference-incorrect judgment the engine called correct.

One consequence of these counting rules: an engine that meets both error caps has agreement of at least 90%. Agreement is exactly 90% only when there are no reference-incorrect words and the false-reject rate is exactly 10%. The agreement comparison is still applied on its own.
