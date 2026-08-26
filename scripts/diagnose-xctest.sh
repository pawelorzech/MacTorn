#!/usr/bin/env bash
#
# Read-only XCTest runner diagnostics. This intentionally does not restart, kill, or
# mutate testmanagerd/Xcode services. Optionally pass an xcresult path to summarize it.

set -u
set -o pipefail

RESULT_BUNDLE="${1:-}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section() {
  printf '\n== %s ==\n' "$1"
}

section "Timestamp"
date -u '+%Y-%m-%dT%H:%M:%SZ'

section "macOS"
sw_vers

section "Selected developer directory"
xcode-select -p
xcodebuild -version

section "Available macOS test destinations"
xcodebuild \
  -project "$PROJECT_ROOT/MacTorn/MacTorn.xcodeproj" \
  -scheme MacTorn \
  -showdestinations 2>&1

section "XCTest-related processes"
# Use executable names rather than full command lines so diagnostics cannot leak
# arguments supplied to an unrelated local test process.
ps -axo pid,ppid,etime,state,comm \
  | awk 'NR == 1 { print; next }
         {
           name = $5
           sub(/^.*\//, "", name)
           if (name == "xcodebuild" || name == "xctest" || name == "testmanagerd") print
         }'

section "Built app bundles still running"
# A build hanging at `RegisterWithLaunchServices` is almost always this: `lsregister`
# blocks while an instance of the bundle it is registering is alive, and an interrupted
# test run leaves its host app behind to do exactly that. The symptom looks like a wedged
# compiler (xcodebuild at 0% CPU, log frozen mid-phase) rather than a stuck daemon.
#
# The recovery, once you have confirmed it here, is: quit those instances, `lsregister -u`
# the bundle, delete `Build/Products/Debug/*.app`, and split the run into
# `build-for-testing` + `test-without-building`. This script does not do any of that.
found=0
while read -r pid comm; do
  [[ -z "$pid" ]] && continue
  printf 'running   pid %s  %s\n' "$pid" "$comm"
  found=1
done < <(ps -axo pid,comm | awk '$2 ~ /DerivedData\/.*\.app\/Contents\/MacOS\// { print $1, $2 }')
if [[ "$found" -eq 0 ]]; then
  printf 'none      no built app bundle is currently running\n'
fi

section "Writable runner paths"
for path in "${TMPDIR:-/tmp}" \
            "$PROJECT_ROOT/DerivedData" \
            "$PROJECT_ROOT/TestResults"; do
  parent="$path"
  if [[ ! -e "$parent" ]]; then
    parent="$(dirname "$parent")"
  fi
  if [[ -w "$parent" ]]; then
    printf 'writable  %s\n' "$path"
  else
    printf 'BLOCKED   %s (nearest existing parent: %s)\n' "$path" "$parent"
  fi
done

if [[ -n "$RESULT_BUNDLE" ]]; then
  section "xcresult summary"
  if [[ -e "$RESULT_BUNDLE" ]]; then
    xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>&1
  else
    printf 'Result bundle not found: %s\n' "$RESULT_BUNDLE"
  fi
fi

section "Safety"
printf '%s\n' "No service was restarted or terminated and no cache was deleted."
