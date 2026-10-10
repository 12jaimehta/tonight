#!/bin/sh
# PRIV-24. External links and openURL calls go through ParentalGatedLink.
set -eu
root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
gate="$root/Packages/Tonight/Sources/ProfilesKit/ParentalGate.swift"
grep -q "enum ParentalGatedLink" "$gate"
grep -q "func destination" "$gate"

app="$root/TonightApp"
if [ ! -d "$app" ]; then
  echo "TonightApp is not in this tree"
  exit 0
fi

fail=0
for file in $(find "$app" -name '*.swift'); do
  if grep -E -q 'openURL[[:space:]]*\(|[^A-Za-z]Link[[:space:]]*\(' "$file"; then
    if ! grep -q "ParentalGatedLink" "$file"; then
      echo "ungated link or openURL in $file"
      fail=1
    fi
  fi
done
exit "$fail"
