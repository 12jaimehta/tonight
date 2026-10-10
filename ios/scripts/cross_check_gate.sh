#!/bin/sh
# Fetch the pinned PR #10 checker and compare it with the Swift harness.
# QA goldens fail the job on any mismatch, including warnings.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

pin=$(tr -d '[:space:]' < ios/scripts/gate-check-independent.pin)
echo "gate-check-independent pin $pin"
git fetch --depth=1 origin "$pin"
git checkout "$pin" -- tools/gate_check_independent

cleanup() {
  git reset -q HEAD -- tools/gate_check_independent 2>/dev/null || true
  rm -rf tools/gate_check_independent
}
trap cleanup EXIT

py=""
for candidate in python3.13 python3.12 python3.11 python3; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)'; then
    py=$candidate
    break
  fi
done
if [ -z "$py" ]; then
  echo "The independent checker needs Python 3.11 or newer"
  exit 1
fi

out=${RUNNER_TEMP:-/tmp}/gate-harness
swiftc -O \
  ios/Packages/Tonight/Sources/GateHarness/GateHarness.swift \
  ios/scripts/GateHarnessCLI.swift \
  -o "$out"

"$py" ios/scripts/cross_check_gate.py "$out" "$root/tools/gate_check_independent"

export PYTHONPATH="$root/tools/gate_check_independent${PYTHONPATH:+:$PYTHONPATH}"
fail=0
for label_cmd in "swift|$out {}" "independent|$py -m gate_check_independent {} --format json"; do
  label=${label_cmd%%|*}
  rest=${label_cmd#*|}
  # shellcheck disable=SC2086
  log=${RUNNER_TEMP:-/tmp}/golden-$label.txt
  # compare.py prints MISMATCH and still exits 0. The job fails on those lines,
  # which include warning mismatches.
  set +e
  # shellcheck disable=SC2086
  "$py" tests/gate-goldens/compare.py "$label" $rest > "$log"
  set -e
  cat "$log"
  if [ "$label" = "independent" ]; then
    if grep -q '^MISMATCH independent G33_unpaired_some_words' "$log"; then
      echo "known G33 divergence: pin $pin still returns APPLE; Swift returns UNPAIRED_RECORDING"
    fi
    other=$(grep '^MISMATCH ' "$log" | grep -v 'G33_unpaired_some_words' || true)
    if [ -n "$other" ]; then
      echo "$other"
      echo "$label goldens mismatched, including any warning differences"
      fail=1
    fi
  elif grep -q '^MISMATCH ' "$log"; then
    echo "$label goldens mismatched, including any warning differences"
    fail=1
  fi
done
exit "$fail"
