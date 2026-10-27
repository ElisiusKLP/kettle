#!/usr/bin/env bash
# Records an Instruments Allocations trace of the release Kettle Dev into build/traces/.
# Uses throwaway seeded data with a task brewing, never your dev data.
#
#   scripts/profile.sh            (normally via make profile; PROFILE_SECONDS=120 to record longer)
#
# Needs full Xcode (Instruments' xctrace); the Command Line Tools alone don't include it.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

seconds=${PROFILE_SECONDS:-60}

if ! xcrun --find xctrace >/dev/null 2>&1; then
    echo "error: make profile needs Instruments (xctrace), which comes with full Xcode." >&2
    echo "Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

scripts/bundle.sh release dev

data="$root/build/traces/data"
rm -rf "$data"
mkdir -p "$data"
KETTLE_DATA_DIR="$data" swift run --quiet kettle-tools seed --brewing

pkill -x "Kettle Dev" 2>/dev/null || true
trace="build/traces/kettle-$(date +%Y%m%d-%H%M%S).trace"
echo "Recording ${seconds}s into $trace (open and close the popover and Stats window while it runs)"
xcrun xctrace record --template 'Allocations' --time-limit "${seconds}s" --output "$trace" \
    --env KETTLE_DATA_DIR="$data" --launch -- "$root/build/Kettle Dev.app"
echo "Open it with: open $trace"
