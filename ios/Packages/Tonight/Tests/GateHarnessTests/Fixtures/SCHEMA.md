# Gate harness fixture schema

The independent checker reads these files. Counts are integers. Rates are reduced ratios written as `numerator/denominator` (not floats, not percents). A ratio of `9/10` is exactly 90 percent. Compare with cross-multiplication.

Large cohorts (`close_call`, `exactly_090`, and the other names in `requiredGoldens` inside `GateHarnessTests.swift`) are built at test time from the seeds below. They are not stored as generated JSON. A missing `*.golden.json` fails the run. The harness does not write a golden unless someone passes `--write` to `ios/scripts/gate_harness.py`.

## Document (`*.json`)

```json
{
  "cohort": ["c0"],
  "recordings": [
    {
      "id": "c0-0",
      "childID": "c0",
      "referenceCorrect": true,
      "appleCorrect": true,
      "sarvamCorrect": false,
      "age": 7,
      "schoolClass": "2"
    }
  ]
}
```

| Field | Type | Unit / meaning |
|---|---|---|
| `cohort` | array of strings or objects | Children who may be scored. A string is an id only and skips the age screen. An object is a demographic member. |
| `cohort[].id` | string | Child id. Recordings use the same id in `childID`. |
| `cohort[].age` | integer or absent | Years. Required on an object member. In-cohort ages are 6, 7, and 8. Missing age on an object member is `OUT_OF_COHORT` and that child is not scored. |
| `cohort[].schoolClass` | string or absent | `"1"`, `"2"`, or `"3"`. Any other present value is `COHORT_REJECTED`. |
| `recordings[].id` | string | Recording id. |
| `recordings[].childID` | string | Must be a cohort id. Otherwise `OUT_OF_COHORT`. |
| `recordings[].referenceCorrect` | boolean | The reference word was correct. |
| `recordings[].appleCorrect` | boolean or null | Apple marked the word correct. Null is `UNPAIRED_RECORDING`. |
| `recordings[].sarvamCorrect` | boolean or null | Sarvam marked the word correct. Null is `UNPAIRED_RECORDING`. |
| `recordings[].age` | integer or absent | If present, must equal the member age and be in 6...8. |
| `recordings[].schoolClass` | string or absent | If present, must equal the member class and be in `"1"`...`"3"`. |

Agreement, false accepts, and false rejects are counted from these booleans. A false accept is `referenceCorrect == false` and the engine value `true`. A false reject is `referenceCorrect == true` and the engine value `false`. A child with no incorrect reference has per-child false-accept `n/a` and is not failed by the 10% cap.

## Decision (`decision` on the report, and in `*.golden.json`)

Enum: `APPLE`, `SARVAM`, `NO_GO`.

Pass bar, all required: pooled agreement `>= 9/10`, pooled false accepts `<= 1/20`, pooled false rejects `<= 1/10`, and every scored child `<= 1/10` false accepts. Exactly `9/10` passes.

| Condition | Decision |
|---|---|
| Only Sarvam passes (Apple fails) | `SARVAM` (MET-36) |
| Both pass, Sarvam agreement `>=` Apple `+ 1/20`, the paired bootstrap interval's lower end is `> 0`, and Sarvam's false-accept rate is `<=` Apple's | `SARVAM` |
| Both pass, but Sarvam's false-accept rate is worse than Apple's | `APPLE` (MET-34) |
| Both pass, but the gap is under `1/20` or the interval includes 0 | `APPLE` |
| Only Apple passes | `APPLE` |
| Neither passes | `NO_GO` |

`met36.json`, `met34.json`, and `met13.json` are the boundary documents. `met13.json` is a child with no age and must error with `OUT_OF_COHORT` rather than a decision.

## Seeds the tests expand

`rows(children, items, appleCorrect, sarvamCorrect)` makes children `c00`... and `items` recordings each. `referenceCorrect` is true. `appleCorrect` is true when `item < appleCorrect`. Same for Sarvam.

| Name | Seed |
|---|---|
| `apple_pass` | 8 children `c0`...`c7`, 8 items. `referenceCorrect` is `item < 6`. Apple matches the reference. Sarvam is always true. |
| `sarvam_pass` | `apple_pass` with Apple and Sarvam swapped. |
| `no_go` | `rows(4, 10, 4, 4)` |
| `close_call` | `rows(4, 1000, 900, 901)` |
| `exactly_090` | 20 children, 50 items, reference true. Even children hear 47, odd children hear 43, both engines. |
| `exactly_plus_5pp` | `rows(4, 20, 18, 19)` |
| `ci_includes_zero` | 10 children, 20 items, reference true. Apple is `item < 18`. Sarvam is `item < 10` for `c09` and `item < 20` otherwise. |
| `per_child_fa_cap` | Child `good` has 19 incorrect words, both engines false. Child `over` has 1 incorrect word, both engines true. |
| `per_child_fa_exact` | 10 children, 10 incorrect words each. Only `c00` item 0 is a false accept for both engines. |
| `unpaired` | One row whose `sarvamCorrect` is null. |
| `out_of_cohort` | The only recording's child is not in the cohort. |
| `age_reject` | Object member `c00` age 9 class `"2"`. |
| `class_reject` | Object member `c00` age 7 class `"5"`. |

## Report fields the goldens lock

`scoringVersion` (integer, currently 2), `decision`, `deltaAgreement` (`"n/d"`), `deltaCI` (two ratio strings, 2.5% and 97.5% of 10,000 child-level resamples, seed `20261010`), and for `apple` and `sarvam`: `paired`, `agreements`, `falseAccepts`, `referenceIncorrect`, `falseRejects`, `referenceCorrect`, `agreement`, `falseAcceptRate`, `falseRejectRate`, `perChildFalseAccept` (map of child id to a ratio string or `"n/a"`), `agreementCI`, `falseAcceptCI`.
