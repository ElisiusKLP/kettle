#!/usr/bin/env bash
# Measures Kettle Dev (release build) idle in the menubar with a task brewing, and fails if
# it's over the SPEC section 8 budget. Uses a throwaway data folder, never your dev data.
#
# The budget applies to the default smart precision (minutes, seconds in the final minute),
# which outside the final minute behaves exactly like minutes mode. Seconds precision is
# opt-in: its CPU use is reported for information, and its wake-ups are checked.
#
#   scripts/memcheck.sh            (normally via make memcheck)
#
# Needs a GUI session (it launches the app), so it runs locally rather than in CI.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

budget_footprint_mb=25
budget_cpu_percent=0.1
budget_wakeups_per_second=1
settle_seconds=10
# SPEC section 10 says 30 s. Smart mode ticks once a minute, so its window is longer,
# otherwise a single stray wake-up would read as 2 per minute.
window_seconds=30
minutes_window_seconds=120

app="build/Kettle Dev.app"
work="$root/build/memcheck"
data="$work/data"

step() { printf '\n==> %s\n' "$*"; }

# CPU time used so far, in seconds (ps prints [[hh:]mm:]ss.cc).
cpu_seconds() {
    ps -o time= -p "$1" | awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; print s }'
}

# Idle wake-ups since launch, as counted by top.
idle_wakeups() {
    top -l 1 -pid "$1" -stats idlew | tail -1 | tr -dc '0-9'
}

footprint_bytes() {
    local bytes
    bytes=$(footprint -p "$1" -f bytes --noCategories 2>/dev/null | awk '/phys_footprint:/ { print $2; exit }')
    if [[ -z "$bytes" ]]; then
        # Fallback: resident size (a less precise stand-in for physical footprint).
        bytes=$(( $(ps -o rss= -p "$1") * 1024 ))
        echo "warning: footprint unavailable, using ps rss" >&2
    fi
    echo "$bytes"
}

step "Zero-allocation tick test (optimised build)"
make --no-print-directory test-release

step "Building release Kettle Dev"
scripts/bundle.sh release dev

step "Seeding throwaway data in $data"
rm -rf "$work"
mkdir -p "$data"
KETTLE_DATA_DIR="$data" swift run --quiet kettle-tools seed --brewing

pid=""
trap '[[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true' EXIT

# Launches Kettle Dev with the given timer precision and measures it. Prints one awk-ready
# line: precision footprint_bytes cpu_seconds idle_wakeups elapsed_seconds.
measure() {
    local precision=$1 window=$2
    printf '{"schemaVersion":1,"timerPrecision":"%s"}\n' "$precision" > "$data/settings.json"
    pkill -x "Kettle Dev" 2>/dev/null || true
    for _ in $(seq 50); do pgrep -x "Kettle Dev" >/dev/null || break; sleep 0.1; done
    open -n --env KETTLE_DATA_DIR="$data" "$app"
    pid=""
    for _ in $(seq 100); do
        pid=$(pgrep -nx "Kettle Dev" || true)
        [[ -n "$pid" ]] && break
        sleep 0.1
    done
    [[ -n "$pid" ]] || { echo "error: Kettle Dev didn't start" >&2; exit 1; }
    echo "$precision mode: pid $pid, settling ${settle_seconds}s, measuring ${window}s" >&2
    sleep "$settle_seconds"
    local cpu_start wakeups_start started
    cpu_start=$(cpu_seconds "$pid")
    wakeups_start=$(idle_wakeups "$pid")
    started=$(date +%s)
    sleep "$window"
    kill -0 "$pid" 2>/dev/null || { echo "error: Kettle Dev quit during the measurement" >&2; exit 1; }
    echo "$precision $(footprint_bytes "$pid") $(awk -v a="$cpu_start" -v b="$(cpu_seconds "$pid")" 'BEGIN { print b - a }') \
$(( $(idle_wakeups "$pid") - wakeups_start )) $(( $(date +%s) - started ))"
    kill "$pid" 2>/dev/null || true
}

step "Measuring with the popover closed and a task brewing"
results=$(measure smart "$minutes_window_seconds"; measure seconds "$window_seconds")

report=$(echo "$results" | awk -v mb="$budget_footprint_mb" -v cpu="$budget_cpu_percent" '
    function row(name, value, unit, op, limit, ok) {
        printf "%-40s %9.3f %-5s budget %s %-7s %s\n", name, value, unit, op, limit, ok ? "ok" : "OVER"
        if (!ok) failed = 1
    }
    {
        precision = $1; footprint = $2 / 1048576; cpu_percent = $3 / $5 * 100
        row("Idle footprint (" precision ")", footprint, "MB", "<=", mb, footprint <= mb)
        if (precision == "seconds") {
            # Opt-in: redrawing the menubar every second costs ~0.4% CPU (SPEC section 8).
            printf "%-40s %9.3f %-5s (opt-in, not budgeted)\n", "Average CPU (seconds)", cpu_percent, "%"
            row("Idle wake-ups (seconds)", $4 / $5, "/s", "<=", 1, $4 / $5 <= 1)
        } else {
            row("Average CPU (" precision ", default)", cpu_percent, "%", "<", cpu, cpu_percent < cpu)
            row("Idle wake-ups (" precision ")", $4 / $5 * 60, "/min", "<=", 1, $4 / $5 * 60 <= 1)
        }
    }
    END { exit failed }') && status=0 || status=$?

step "Results (release build; smart ${minutes_window_seconds}s, seconds ${window_seconds}s)"
echo "$report"
echo "$report" > "$work/report.txt"
if (( status != 0 )); then
    echo
    echo "memcheck FAILED: over budget (SPEC section 8)." >&2
    exit 1
fi
echo
echo "memcheck passed."
