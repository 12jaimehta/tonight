#!/usr/bin/env python3
"""Compare an implementation's JSON output with expected/*.json.
usage: compare.py <label> <command...>   ({} in the command is replaced by the case path)
e.g.   compare.py swift /tmp/gh11 {}
       compare.py python python3 -m gate_check_independent {} --format json
"""
import json, subprocess, sys, pathlib, re
from fractions import Fraction as F
root = pathlib.Path(__file__).parent
label, cmd = sys.argv[1], sys.argv[2:]
def frac(x):
    if isinstance(x, dict): return F(x["numerator"], x["denominator"])
    return F(x)
mism = 0
for exp_path in sorted((root / "expected").glob("*.json")):
    e = json.loads(exp_path.read_text()); case = root / "cases" / exp_path.name
    p = subprocess.run([c.replace("{}", str(case)) for c in cmd], capture_output=True, text=True)
    try: out = json.loads(p.stdout)
    except Exception: out = {"error": (p.stdout.strip().split() or ["?"])[-1], "stderr": p.stderr.strip()[-200:]}
    got = out.get("decision") or out.get("error") or out.get("code")
    probs = []
    if got != e["outcome"]: probs.append(f"outcome {got} != {e['outcome']} ({out.get('message') or out.get('stderr','')})")
    if "apple" in e and "apple" in out:
        for eng in ("apple", "sarvam"):
            ee, oo = e[eng], out[eng]
            for k in ("agreement", "false_accept_rate", "false_reject_rate"):
                if frac(oo[k]) != F(ee[k]): probs.append(f"{eng}.{k} {frac(oo[k])} != {ee[k]}")
            if oo.get("bars") and oo["bars"] != ee["bars"]: probs.append(f"{eng}.bars {oo['bars']} != {ee['bars']}")
            if oo["passes"] != ee["passes"]: probs.append(f"{eng}.passes")
        if frac(out["agreement_delta"]) != F(e["delta"]): probs.append(f"delta {frac(out['agreement_delta'])} != {e['delta']}")
        iv = out.get("interval", {})
        if "ci" in e and "low" in iv and frac(iv["low"]) != F(e["ci"]["low"]): probs.append(f"ci.low {frac(iv['low'])} != {e['ci']['low']}")
        if "ci" in e and "high" in e["ci"] and "high" in iv and frac(iv["high"]) != F(e["ci"]["high"]): probs.append(f"ci.high {frac(iv['high'])} != {e['ci']['high']}")
        warned = sorted(c for c in re.findall(r"child (\S+)", " ".join(map(str, out.get("warnings", [])))))
        if warned != sorted(e["warnings"]): probs.append(f"warnings {out.get('warnings')} != children {e['warnings']}")
    print(("OK  " if not probs else "MISMATCH ") + f"{label} {exp_path.stem} -> {got}")
    for x in probs: print("     " + x)
    mism += bool(probs)
print(f"{label}: {mism} mismatch(es) of {len(list((root/'expected').glob('*.json')))}")
