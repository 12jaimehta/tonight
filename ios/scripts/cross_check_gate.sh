#!/bin/sh
# Fetch PR #10 and compare its decision tokens with the Swift harness.
# The checker tree is not committed. Warning text is ignored (PM rule 7).
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

git fetch origin gate-check-independent
git checkout origin/gate-check-independent -- tools/gate_check_independent

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
