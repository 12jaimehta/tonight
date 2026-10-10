#!/usr/bin/env python3
"""QA gate goldens, written from PM 'M0 gate: exact computation rules' (pm/v1-build-plan.md,
rules 1-7) and M0_SPEECH_QA.md §5.3/§5.4. Not derived from #10 or #11 code.

Builds cases/<id>.json (fixture schema 1, the shared #10/#11 results-file format) and
expected/<id>.json. The oracle below is a direct reading of the rules:
  agreement = matching judged words / judged words (unjudged excluded)          rule 6
  FA = ref-incorrect accepted / ref-incorrect;  FR = ref-correct rejected / ref-correct
  pass = agreement >= 9/10, pooled FA <= 1/20, pooled FR <= 1/10, every child with
         ref-incorrect words FA <= 1/10 (children without are skipped)         rules 2, 3
  pooled FA or FR denominator 0 -> INVALID_STUDY                                rule 3
  age not in 6-8 / class not in 1-3 / missing -> OUT_OF_COHORT                  rule 4
  warn only class 1 & age 8, class 3 & age 6; never reject                      rule 7
  a word lacking either engine's result -> UNPAIRED_RECORDING (M0 MET-28: never drop silently)
  decision: only Sarvam passes -> SARVAM; only Apple -> APPLE; neither -> NO_GO; both ->
  SARVAM iff delta >= 5/100 and CI low > 0 and FA(S) <= FA(A) (tie not worse), else APPLE.
CI: cases are built so the 95% child-cluster percentile CI is known without a particular RNG:
  'uniform' cases (every child has the same delta) give CI = [delta, delta]; two-child cases
  put 25% of draws on the low child, so the 2.5th percentile equals that child's delta.
  expected.ci is exact for uniform cases, and {"low": x} for two-child cases.
Run: python3 build_goldens.py   (rewrites cases/ and expected/)
"""
import json, pathlib
from fractions import Fraction as F

ROOT = pathlib.Path(__file__).parent
CASES, EXP = ROOT / "cases", ROOT / "expected"

def cells(C, I, aFR, aFA, sFR, sFA, unjudged=0):
    """C ref-correct and I ref-incorrect words; aFR/sFR ref-correct words each engine rejects,
    aFA/sFA ref-incorrect words each engine accepts. Overlap is maximised."""
    out = []
    def add(r, a, s, n):
        if n > 0: out.append({"reference_correct": r, "apple_correct": a, "sarvam_correct": s, "n": n})
    o = min(aFR, sFR)
    add(True, False, False, o); add(True, False, True, aFR - o); add(True, True, False, sFR - o)
    add(True, True, True, C - aFR - sFR + o)
    o = min(aFA, sFA)
    add(False, True, True, o); add(False, True, False, aFA - o); add(False, False, True, sFA - o)
    add(False, False, False, I - aFA - sFA + o)
    if unjudged: out.append({"reference_correct": None, "apple_correct": True, "sarvam_correct": True, "n": unjudged})
    return out

def child(cid, recs, age=7, cls=2):
    c = {"child_id": cid, "recordings": [{"recording_id": f"{cid}-r{i}", "cells": r} for i, r in enumerate(recs)]}
    if age != "omit": c["age"] = age
    if cls != "omit": c["school_class"] = cls
    return c

def doc(children): return {"schema_version": 1, "children": children}

# ---------------- oracle (spec only) ----------------
def oracle(d):
    kids = d["children"]
    bad = []
    warns = []
    for k in kids:
        age, cls = k.get("age"), k.get("school_class")
        if not isinstance(age, int) or isinstance(age, bool) or age not in (6, 7, 8): bad.append(k["child_id"])
        elif not isinstance(cls, int) or isinstance(cls, bool) or cls not in (1, 2, 3): bad.append(k["child_id"])
        elif (cls == 1 and age == 8) or (cls == 3 and age == 6): warns.append(k["child_id"])
    if bad: return {"outcome": "OUT_OF_COHORT", "children": bad}
    for k in kids:
        for r in k["recordings"]:
            for c in r["cells"]:
                if c.get("apple_correct") is None or c.get("sarvam_correct") is None:
                    return {"outcome": "UNPAIRED_RECORDING", "recording": r["recording_id"]}
    def tally(eng, ks):
        t = dict(words=0, match=0, C=0, I=0, fr=0, fa=0)
        for k in ks:
            for r in k["recordings"]:
                for c in r["cells"]:
                    ref, n = c["reference_correct"], c["n"]
                    if ref is None: continue
                    e = c[eng + "_correct"]
                    t["words"] += n; t["match"] += n if e == ref else 0
                    if ref: t["C"] += n; t["fr"] += n if not e else 0
                    else: t["I"] += n; t["fa"] += n if e else 0
        return t
    A, S = tally("apple", kids), tally("sarvam", kids)
    if A["I"] == 0: return {"outcome": "INVALID_STUDY", "denominator": "false_accept"}
    if A["C"] == 0: return {"outcome": "INVALID_STUDY", "denominator": "false_reject"}
    def score(eng, t):
        agr, fa, fr = F(t["match"], t["words"]), F(t["fa"], t["I"]), F(t["fr"], t["C"])
        child_ok = all(F(c["fa"], c["I"]) <= F(1, 10) for c in (tally(eng, [k]) for k in kids) if c["I"] > 0)
        bars = {"agreement_at_least_90": agr >= F(9, 10), "pooled_false_accept_at_most_5": fa <= F(1, 20),
                "per_child_false_accept_at_most_10": child_ok, "false_reject_at_most_10": fr <= F(1, 10)}
        return {"agreement": str(agr), "false_accept_rate": str(fa), "false_reject_rate": str(fr),
                "bars": bars, "passes": all(bars.values())}, fa
    a, faA = score("apple", A); s, faS = score("sarvam", S)
    delta = F(S["match"], S["words"]) - F(A["match"], A["words"])
    return {"outcome": None, "warnings": warns, "apple": a, "sarvam": s, "delta": str(delta), "_faA": faA, "_faS": faS}

def decide(o, ci_low):
    a, s = o["apple"]["passes"], o["sarvam"]["passes"]
    if a and s:
        beats = F(o["delta"]) >= F(5, 100) and ci_low > 0 and o["_faS"] <= o["_faA"]
        return "SARVAM" if beats else "APPLE"
    return "SARVAM" if s else "APPLE" if a else "NO_GO"

# ---------------- cases ----------------
K = lambda n, *a, **kw: [child(f"c{i:02d}", [cells(*a)], **kw) for i in range(n)]
cases = {}
def case(cid, why, d, ci="uniform", ci_low=None):
    cases[cid] = (why, d, ci, ci_low)

# agreement
case("G01_apple_only_passes", "Apple passes all bars; Sarvam agreement 0.85 -> APPLE (no tie-break).",
     doc(K(10, 95, 5, 5, 0, 15, 0)))
case("G02_agreement_exactly_090_bar", "Agreement exactly 9/10 (bar passes, inclusive) but FA 1/5 fails -> NO_GO. Full pass at exactly 0.90 is impossible with FA words (see README).",
     doc(K(10, 95, 5, 9, 1, 9, 1)))
case("G03_agreement_899_of_1000", "Agreement 899/1000: bar fails before rounding even though it displays 90.0%. FA 0, FR 101/1000 also fails.",
     doc([child("c00", [cells(950, 50, 101, 0, 101, 0)])]))
# FA pooled
case("G04_FA_pooled_exactly_5pct", "Pooled FA exactly 1/20 passes (<=); every child 1/10 at cap; both engines same -> APPLE.",
     doc(K(10, 90, 10, 0, 1, 0, 1)[:5] + [child(f"d{i}", [cells(90, 10, 0, 0, 0, 0)]) for i in range(5)]))
case("G05_FA_pooled_51_of_1000", "Pooled FA 51/1000 fails even though every child is under the 10% cap -> NO_GO.",
     doc([child(f"c{i:02d}", [cells(900, 100, 0, 6 if i == 0 else 5, 0, 6 if i == 0 else 5)]) for i in range(10)]))
# FA per child
case("G06_child_FA_exactly_10pct", "One child at FA 10/100 (cap boundary, passes); pooled FA 10/1000 -> APPLE.",
     doc([child("c00", [cells(900, 100, 0, 10, 0, 10)])] + [child(f"c{i:02d}", [cells(900, 100, 0, 0, 0, 0)]) for i in range(1, 10)]))
case("G07_child_FA_11_of_109", "Child FA 11/109 = 0.1009 fails the cap though pooled FA is ~1.2% -> NO_GO.",
     doc([child("c00", [cells(891, 109, 0, 11, 0, 11)])] + [child(f"c{i:02d}", [cells(900, 100, 0, 0, 0, 0)]) for i in range(1, 10)]))
case("G08_child_FA_1_of_1", "Child X with one misread word accepted (100%); 40 others at 2% -> NO_GO (MET-06).",
     doc([child(f"c{i:02d}", [cells(900, 100, 0, 2, 0, 2)]) for i in range(40)] + [child("X", [cells(50, 1, 0, 1, 0, 1)])]))
case("G09_child_without_misreads_skipped", "Child with 0 ref-incorrect words is skipped by the cap and adds 0/0 to pooled FA -> APPLE.",
     doc([child("c00", [cells(100, 0, 0, 0, 0, 0)])] + [child(f"c{i:02d}", [cells(95, 5, 1, 0, 1, 0)]) for i in range(1, 6)]))
# FR
case("G10_FR_exactly_10pct", "Pooled FR exactly 1/10 passes; no FA -> APPLE (agreement 0.905).",
     doc(K(10, 95, 5, 9, 0, 9, 0)[:5] + [child(f"d{i}", [cells(95, 5, 10, 0, 10, 0)]) for i in range(5)]))
case("G11_FR_101_of_1000", "Pooled FR 101/1000 fails with agreement and FA passing -> NO_GO.",
     doc([child(f"c{i:02d}", [cells(100, 10, 11 if i == 0 else 10, 0, 11 if i == 0 else 10, 0)]) for i in range(10)]))
case("G12_child_FR_100pct_no_child_cap", "One child FR 5/5 = 100%; pooled FR 5/905 -> passes (no per-child FR cap) -> APPLE.",
     doc([child("c00", [cells(5, 5, 5, 0, 5, 0)])] + [child(f"c{i:02d}", [cells(100, 10, 0, 0, 0, 0)]) for i in range(1, 10)]))
# CI and margin
case("G13_delta_exactly_5pp_FA_tie", "Both pass; uniform delta exactly +5pp; CI [1/20,1/20]; FA equal (tie not worse) -> SARVAM.",
     doc(K(10, 80, 20, 8, 1, 3, 1)))
case("G14_delta_49_of_1000", "Both pass; uniform delta 49/1000 < 5pp -> APPLE.",
     doc([child(f"c{i:02d}", [cells(950, 50, 95, 0, 46, 0)]) for i in range(10)]))
case("G15_CI_low_exactly_0", "Two equal-size children: +12pp and 0pp; pooled +6pp, FA tie; 25% of draws pick the 0pp child twice, so CI low = 0 exactly (touches 0) -> APPLE.",
     doc([child("c00", [cells(90, 10, 12, 0, 0, 0)]), child("c01", [cells(90, 10, 0, 0, 0, 0)])]),
     ci="two", ci_low="0")
case("G16_CI_overlaps_0", "Two children: +16pp and -4pp; pooled +6pp; CI low = -4pp -> APPLE.",
     doc([child("c00", [cells(100, 0, 16, 0, 0, 0)]), child("c01", [cells(90, 10, 0, 0, 4, 0)])]),
     ci="two", ci_low="-1/25")
case("G17_FA_worse_by_one_word", "Both pass; uniform +6pp, CI > 0; Sarvam FA 1/20 vs Apple 0 (one accepted misread per child) -> APPLE (MET-34).",
     doc(K(10, 80, 20, 8, 0, 1, 1)))
case("G18_clear_win", "Both pass; uniform +6pp; Sarvam FA better -> SARVAM.",
     doc(K(10, 80, 20, 7, 1, 1, 0)))
# pass/fail combinations
case("G19_apple_fails_sarvam_passes_small_delta", "Apple FR 11% fails; Sarvam passes; delta only +3pp -> SARVAM (MET-36).",
     doc(K(10, 100, 10, 11, 0, 8, 0)))
case("G20_apple_fails_sarvam_passes_negative_delta", "Apple higher agreement but fails the child cap; Sarvam passes with lower agreement -> SARVAM (MET-36c).",
     doc([child("c00", [cells(90, 10, 0, 2, 9, 0)])] + [child(f"c{i:02d}", [cells(90, 10, 0, 0, 2, 0)]) for i in range(1, 10)]),
     ci="skip")
case("G21_both_fail", "Both engines: agreement 19/22, FA 1/2 -> NO_GO (MET-36d).", doc(K(10, 100, 10, 10, 5, 10, 5)))
# undefined rates
case("G22_recordings_with_empty_sides", "Each child has one all-correct-reference recording and one all-misread recording; neither fails the engine -> APPLE.",
     doc([child(f"c{i:02d}", [cells(95, 0, 2, 0, 2, 0), cells(0, 20, 0, 0, 0, 0)]) for i in range(5)]))
case("G23_unjudged_excluded", "10 unjudged words per child are excluded: agreement 909/990 (not 909/1090) -> APPLE.",
     doc([child("c00", [cells(81, 9, 0, 0, 0, 0, unjudged=10)])] + [child(f"c{i:02d}", [cells(90, 10, 9, 0, 9, 0, unjudged=10)]) for i in range(1, 10)]))
case("G24_invalid_no_misreads", "No ref-incorrect word anywhere -> INVALID_STUDY (pooled FA denominator 0).",
     doc(K(5, 100, 0, 5, 0, 5, 0)))
case("G25_invalid_no_correct_reference", "No ref-correct word anywhere -> INVALID_STUDY (pooled FR denominator 0).",
     doc(K(5, 0, 20, 0, 0, 0, 0)))
# cohort
case("G26_age_5", "Age 5 -> OUT_OF_COHORT.", doc([child("c00", [cells(95, 5, 1, 0, 1, 0)], age=5)] + K(3, 95, 5, 1, 0, 1, 0)[1:]))
case("G27_age_missing", "Age key absent -> OUT_OF_COHORT.", doc([child("c00", [cells(95, 5, 1, 0, 1, 0)], age="omit")] + K(3, 95, 5, 1, 0, 1, 0)[1:]))
case("G28_class_null", "school_class null -> OUT_OF_COHORT.", doc([child("c00", [cells(95, 5, 1, 0, 1, 0)], cls=None)] + K(3, 95, 5, 1, 0, 1, 0)[1:]))
case("G29_class_4_age_9", "Class 4 and a separate age 9 -> OUT_OF_COHORT naming both.",
     doc([child("c00", [cells(95, 5, 1, 0, 1, 0)], cls=4), child("c01", [cells(95, 5, 1, 0, 1, 0)], age=9)] + K(4, 95, 5, 1, 0, 1, 0)[2:]))
# rule 7
case("G30_rule7_warnings", "Class 1 age 8 and class 3 age 6 warn; still scored -> APPLE with exactly those two warnings.",
     doc([child("w1", [cells(95, 5, 1, 0, 1, 0)], age=8, cls=1), child("w2", [cells(95, 5, 1, 0, 1, 0)], age=6, cls=3)] + K(2, 95, 5, 1, 0, 1, 0)))
case("G31_rule7_no_warnings", "All seven acceptable pairs (1/6,1/7,2/6,2/7,2/8,3/7,3/8) -> no warnings.",
     doc([child(f"p{c}{a}", [cells(95, 5, 1, 0, 1, 0)], age=a, cls=c) for c, a in [(1, 6), (1, 7), (2, 6), (2, 7), (2, 8), (3, 7), (3, 8)]]))
# pairing
_unp = cells(95, 5, 1, 0, 1, 0)
for c in _unp: c.pop("sarvam_correct")
case("G32_unpaired_whole_recording", "A recording with no Sarvam results -> UNPAIRED_RECORDING (MET-28).",
     doc([child("c00", [_unp])] + K(3, 95, 5, 1, 0, 1, 0)[1:]))
_part = cells(95, 5, 1, 0, 1, 0) + [{"reference_correct": True, "apple_correct": True, "n": 3}]
case("G33_unpaired_some_words", "A recording where 3 words have no Sarvam result -> UNPAIRED_RECORDING (M0 §5.3: never drop silently).",
     doc([child("c00", [_part])] + K(3, 95, 5, 1, 0, 1, 0)[1:]))

def main():
    CASES.mkdir(exist_ok=True); EXP.mkdir(exist_ok=True)
    for p in list(CASES.glob("*.json")) + list(EXP.glob("*.json")): p.unlink()
    for cid, (why, d, ci, ci_low) in cases.items():
        o = oracle(d)
        if o["outcome"] is None:
            if ci == "skip":  # CI is not part of the rule when only one engine passes
                low = F(-1)
            elif ci == "uniform":
                low = F(o["delta"]); o["ci"] = {"low": o["delta"], "high": o["delta"]}
            else:
                low = F(ci_low); o["ci"] = {"low": ci_low}
            o["outcome"] = decide(o, low)
        o.pop("_faA", None); o.pop("_faS", None)
        o = {"case": cid, "why": why, **o}
        (CASES / f"{cid}.json").write_text(json.dumps(d, indent=1) + "\n")
        (EXP / f"{cid}.json").write_text(json.dumps(o, indent=1) + "\n")
        print(f"{cid:45s} {o['outcome']}")

if __name__ == "__main__":
    main()
