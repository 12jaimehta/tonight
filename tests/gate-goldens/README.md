# QA gate goldens (M0 speech-engine gate)

**Owner:** QA. **Written:** 10 Oct 2026.

**Sources:** PM `pm/v1-build-plan.md` "M0 gate: exact computation rules" 1–7, and `qa/M0_SPEECH_QA.md` v0.6 §5.3/§5.4. Nothing here is derived from PR #10 (`tools/gate_check_independent`) or PR #11 (`GateHarness.swift`). I didn't read their decision code while writing the oracle. The only thing shared is the results-file **input schema** (schema 1), so both can read the cases.

## Files

| Path | What it is |
|---|---|
| `build_goldens.py` | Builds every case and computes the expected result with a ~60-line oracle read straight from the rules (docstring at the top). Re-run it to regenerate `cases/` and `expected/`. |
| `cases/Gnn_*.json` | Input, in fixture schema 1 (`children[] → recordings[] → cells[]`, with `reference_correct` null meaning unjudged) |
| `expected/Gnn_*.json` | `outcome`, plus `why`. For scored cases it also has per-engine `agreement`, `false_accept_rate`, `false_reject_rate` (exact fractions), the four `bars`, `passes`, `delta`, `ci` and `warnings` (child IDs). For errors it names the children, the recording or the empty denominator. |
| `compare.py` | Runs an implementation on every case and diffs against expected |

Usage:

```
python3 build_goldens.py
python3 compare.py swift  /path/to/gate-harness-cli {}
(cd tools/gate_check_independent && python3 /path/to/compare.py python python3 -m gate_check_independent {} --format json)
```

## How the CI is pinned without depending on a particular random generator

- **Uniform cases:** every child has the same Δ, so every child-cluster resample has that Δ. The 95% CI is exactly `[Δ, Δ]`.
- **Two-child cases (G15, G16):** equal-size children, so each bootstrap draw picks the low child twice with probability 1/4. That puts ~2,500 of the 10,000 draws at the low child's Δ, so the 2.5th percentile is exactly that value under any sound RNG and any standard percentile type. Only `ci.low` is asserted.
- **G20:** only one engine passes, so the CI isn't part of the rule and isn't asserted.

## Coverage (33 cases)

| Area | Cases |
|---|---|
| Agreement bar (≥ 9/10, unrounded) | G01, G02 (exactly 9/10), G03 (899/1000) |
| Pooled FA (≤ 1/20) | G04 (exactly 1/20), G05 (51/1000) |
| Per-child FA cap (≤ 1/10) | G06 (exactly 10/100), G07 (11/109), G08 (1/1, MET-06), G09 (child with no misreads skipped) |
| FR (pooled only, ≤ 1/10) | G10 (exactly 1/10), G11 (101/1000), G12 (one child at 100% FR still passes) |
| "Clearly beats" (both pass) | G13 (Δ exactly +5pp, FA tie → SARVAM), G14 (Δ 4.9pp), G15 (CI low exactly 0), G16 (CI overlaps 0), G17 (FA worse), G18 (clear win) |
| Pass/fail matrix | G01 (Apple only), G19 (Apple fails, Sarvam passes, +3pp), G20 (same with negative Δ), G21 (both fail) |
| Undefined rates (rule 3) | G22 (recordings with an empty side), G09 |
| Agreement formula (rule 6) | G23 (unjudged excluded: 909/990) |
| INVALID_STUDY | G24 (FA denominator 0), G25 (FR denominator 0) |
| OUT_OF_COHORT (rule 4) | G26 (age 5), G27 (age missing), G28 (class null), G29 (class 4 plus age 9, both named) |
| Rule 7 warnings | G30 (class 1 age 8, class 3 age 6: warn and still score), G31 (all 7 acceptable pairs: no warning) |
| UNPAIRED_RECORDING | G32 (whole recording without Sarvam), G33 (3 words in a recording without Sarvam) |

## Notes

- **Exactly 0.90 can't pass the whole gate when any FA word exists.** With FR ≤ 10% and FA ≤ 5%, the maximum error share is 10% only when there are no ref-incorrect words, and that is INVALID_STUDY. So G02 asserts the agreement **bar** flag, not a full pass (M0 MET-02 note).
- **G33 is stricter than both implementations.** M0 §5.3 says the harness "errors if either engine is missing a recording; it never drops one silently". QA reads a word with no Sarvam result as an unpaired recording. If PM rules that words may be dropped, change G33's expected outcome to the scored result and record the ruling here.
- **Warnings are compared by child ID, not text.**

## Results, 10 Oct 2026

| Implementation | Head | Mismatches |
|---|---|---|
| #11 `GateHarness` (built with `swiftc` from `ios/scripts/GateHarnessCLI.swift` on Linux) | `d240a87` | 1/33: G33 → APPLE (expected UNPAIRED_RECORDING) |
| #10 `gate_check_independent` | `f54bc0d` | 1/33: G33 → APPLE (expected UNPAIRED_RECORDING) |

All metrics, bars, Δ, CI bounds and warnings match on the other 32. #10 and #11 agree with each other on all 33.
