#!/usr/bin/env bash
# Runs the tests with coverage and prints a line-coverage summary for KettleCore.
# Fails if KettleCore is below the 85% line-coverage target. Extra arguments go to `swift test`.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

swift test --enable-code-coverage "$@"

bin_dir=$(swift build --show-bin-path)
profdata="$bin_dir/codecov/default.profdata"
binary="$bin_dir/KettlePackageTests.xctest/Contents/MacOS/KettlePackageTests"

# Keep only Sources/KettleCore: drop generated files, tests and the other targets.
report=$(xcrun llvm-cov report "$binary" -instr-profile="$profdata" \
    -ignore-filename-regex='(\.build|Tests|Sources/(KettleApp|KettleIcon|kettle-tools))/')
echo "$report"

# TOTAL row columns: Regions Missed Cover Functions Missed Executed Lines Missed Cover ...
total_lines=$(echo "$report" | awk '/^TOTAL/ { print $8 }')
if [[ -z "$total_lines" || "$total_lines" == 0 ]]; then
    echo
    echo "KettleCore has no executable code yet; nothing to measure."
    exit 0
fi

line_cover=$(echo "$report" | awk '/^TOTAL/ { print $10 }' | tr -d '%')
echo
echo "KettleCore line coverage: ${line_cover}% (target: 85%)"
awk -v cover="$line_cover" 'BEGIN { exit (cover + 0 >= 85) ? 0 : 1 }' || {
    echo "error: KettleCore line coverage is below 85%" >&2
    exit 1
}
