#!/usr/bin/env bash
#
# coverage-gate.sh — fail if any critical module's line coverage drops below a threshold.
#
# Etap G / ISC-20: the reliability-critical, pure modules must stay well-tested. This gate
# is deliberately scoped to those modules — NOT to SwiftUI views (which are validated by the
# UI-test suite, not line coverage) — so it protects correctness without penalising view code.
#
# Usage: scripts/coverage-gate.sh <path-to-.xcresult> [threshold]
#   threshold defaults to 80 (percent).
#
# Requires: xcrun xccov (Xcode). No external dependencies (no jq).

set -euo pipefail

RESULT_BUNDLE="${1:?usage: coverage-gate.sh <path-to-.xcresult> [threshold]}"
THRESHOLD="${2:-80}"
TARGET="MacTorn.app"

# Reliability-critical modules gated at >= THRESHOLD. Matched by basename so the check is
# path-agnostic. Add the key-validation module here when Etap C (ISC-16) lands.
CRITICAL_FILES=(
  "TornAPIError.swift"
  "TornEndpoint.swift"
  "PollingCoordinator.swift"
  "NotificationCoordinator.swift"
  "NextAction.swift"
)

if [[ ! -e "$RESULT_BUNDLE" ]]; then
  echo "coverage-gate: result bundle not found: $RESULT_BUNDLE" >&2
  exit 2
fi

REPORT="$(xcrun xccov view --report --files-for-target "$TARGET" "$RESULT_BUNDLE" 2>/dev/null)"
if [[ -z "$REPORT" ]]; then
  echo "coverage-gate: no coverage report for target $TARGET (was -enableCodeCoverage YES set?)" >&2
  exit 2
fi

echo "Coverage gate: requiring >= ${THRESHOLD}% line coverage on critical modules"
echo "-------------------------------------------------------------------------"

failed=0
for file in "${CRITICAL_FILES[@]}"; do
  # Grab the report line for this file and pull the first "NN.NN%" token from it.
  line="$(grep -F "/$file " <<<"$REPORT" | head -1 || true)"
  if [[ -z "$line" ]]; then
    echo "MISSING  $file — not present in coverage report" >&2
    failed=1
    continue
  fi

  pct="$(grep -oE '[0-9]+\.[0-9]+%' <<<"$line" | head -1 | tr -d '%')"
  if [[ -z "$pct" ]]; then
    echo "MISSING  $file — could not parse coverage from: $line" >&2
    failed=1
    continue
  fi

  # Compare as floats via awk (bash can't do decimals).
  if awk "BEGIN { exit !($pct < $THRESHOLD) }"; then
    printf 'FAIL     %-32s %6s%% (< %s%%)\n' "$file" "$pct" "$THRESHOLD"
    failed=1
  else
    printf 'ok       %-32s %6s%%\n' "$file" "$pct"
  fi
done

echo "-------------------------------------------------------------------------"
if [[ "$failed" -ne 0 ]]; then
  echo "coverage-gate: FAILED — a critical module is below ${THRESHOLD}% coverage." >&2
  exit 1
fi
echo "coverage-gate: PASSED"
