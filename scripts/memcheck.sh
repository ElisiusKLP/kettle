#!/usr/bin/env bash
# Measures Kettle Dev (release build) idle in the menubar with a task brewing, and fails if
# it's over the SPEC section 8 budget. Uses a throwaway data folder, never your dev data.
#
# The CPU and wake-up budget applies to smart precision (minutes, seconds in the final
# minute), the energy-saving choice, which outside the final minute behaves exactly like
# minutes mode. The default is seconds precision (see docs/DECISIONS.md). It's measured in four
# 60 s slices and judged on the median slice: macOS sometimes does a burst of work on a
# newly launched status item 1-3 minutes after launch, which isn't Kettle's steady state.
# Every slice is printed, so such a burst stays visible. For seconds precision, CPU use is
# reported for information, and the footprint and wake-ups are checked.
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
smart_slices=4
smart_slice_seconds=60
# SPEC section 10 says 30 s.
seconds_window_seconds=30

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

# Launches Kettle Dev with the given timer precision and measures it in consecutive slices.
# Prints one line per slice: precision slice footprint_bytes cpu_seconds idle_wakeups elapsed_seconds.
measure() {
    local precision=$1 slices=$2 window=$3
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
    echo "$precision: pid $pid, settling ${settle_seconds}s, then ${slices} x ${window}s" >&2
    sleep "$settle_seconds"
    local slice cpu_start wakeups_start started
    for slice in $(seq "$slices"); do
        cpu_start=$(cpu_seconds "$pid")
        wakeups_start=$(idle_wakeups "$pid")
        started=$(date +%s)
        sleep "$window"
        kill -0 "$pid" 2>/dev/null || { echo "error: Kettle Dev quit during the measurement" >&2; exit 1; }
        echo "$precision $slice $(footprint_bytes "$pid") \
$(awk -v a="$cpu_start" -v b="$(cpu_seconds "$pid")" 'BEGIN { print b - a }') \
$(( $(idle_wakeups "$pid") - wakeups_start )) $(( $(date +%s) - started ))"
    done
    kill "$pid" 2>/dev/null || true
}

step "Measuring with the popover closed and a task brewing"
results=$(measure smart "$smart_slices" "$smart_slice_seconds"; measure seconds 1 "$seconds_window_seconds")

report=$(echo "$results" | awk -v mb="$budget_footprint_mb" -v cpu="$budget_cpu_percent" '
    function row(name, value, unit, op, limit, ok) {
        printf "%-40s %9.3f %-5s budget %s %-7s %s\n", name, value, unit, op, limit, ok ? "ok" : "OVER"
        if (!ok) failed = 1
    }
    function median(values, n,    i, j, t) {
        for (i = 2; i <= n; i++) for (j = i; j > 1 && values[j - 1] > values[j]; j--) {
            t = values[j]; values[j] = values[j - 1]; values[j - 1] = t
        }
        return n % 2 ? values[(n + 1) / 2] : (values[n / 2] + values[n / 2 + 1]) / 2
    }
    {
        footprint = $3 / 1048576; cpu_percent = $4 / $6 * 100
        if ($1 == "smart") {
            n++; smart_cpu[n] = cpu_percent; smart_wake[n] = $5 / $6 * 60
            if (footprint > smart_footprint) smart_footprint = footprint
            printf "  smart slice %d: footprint %.1f MB, CPU %.3f%%, %d idle wake-ups\n", $2, footprint, cpu_percent, $5
        } else {
            seconds_footprint = footprint; seconds_cpu = cpu_percent; seconds_wake = $5 / $6
        }
    }
    END {
        print ""
        row("Idle footprint (smart, largest slice)", smart_footprint, "MB", "<=", mb, smart_footprint <= mb)
        cpu_median = median(smart_cpu, n); wake_median = median(smart_wake, n)
        row("Average CPU (smart, median slice)", cpu_median, "%", "<", cpu, cpu_median < cpu)
        row("Idle wake-ups (smart, median slice)", wake_median, "/min", "<=", 1, wake_median <= 1)
        row("Idle footprint (seconds)", seconds_footprint, "MB", "<=", mb, seconds_footprint <= mb)
        # Opt-in: redrawing the menubar every second costs ~0.4% CPU (SPEC section 8).
        printf "%-40s %9.3f %-5s (default; not budgeted)\n", "Average CPU (seconds)", seconds_cpu, "%"
        row("Idle wake-ups (seconds)", seconds_wake, "/s", "<=", 1, seconds_wake <= 1)
        exit failed
    }') && status=0 || status=$?

step "Results (release build)"
echo "$report"
echo "$report" > "$work/report.txt"
if (( status != 0 )); then
    echo
    echo "memcheck FAILED: over budget (SPEC section 8)." >&2
    exit 1
fi
echo
echo "memcheck passed."
