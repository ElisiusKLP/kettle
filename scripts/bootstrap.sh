#!/usr/bin/env bash
# Checks the toolchain and installs the optional linters via Homebrew if they're missing.
set -euo pipefail

fail() { echo "error: $*" >&2; exit 1; }

developer_dir=$(xcode-select -p 2>/dev/null) || fail "no Xcode or Command Line Tools found. Run: xcode-select --install"
echo "Developer dir: $developer_dir"

command -v swift >/dev/null || fail "swift not found in PATH"
swift_version=$(swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1.\2/p' | head -1)
[[ -n "$swift_version" ]] || fail "could not read the Swift version"
major=${swift_version%%.*}
# Tests use Swift Testing, which ships with the Swift 6 toolchains (Xcode 16 / matching CLT).
if (( major < 6 )); then
    fail "Swift $swift_version found; Kettle needs Swift 6.0 or later (Xcode 16+ or matching Command Line Tools)"
fi
echo "Swift: $swift_version"

clt_frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [[ "$developer_dir" == /Library/Developer/CommandLineTools && ! -d "$clt_frameworks/Testing.framework" ]]; then
    fail "Swift Testing not found in the Command Line Tools. Update them via Software Update or install Xcode 16+"
fi

missing=()
for tool in swiftlint swiftformat; do
    if command -v "$tool" >/dev/null; then
        echo "$tool: $("$tool" --version)"
    else
        missing+=("$tool")
    fi
done

if (( ${#missing[@]} > 0 )); then
    if command -v brew >/dev/null; then
        echo "Installing ${missing[*]} via Homebrew..."
        brew install "${missing[@]}"
    else
        echo "warning: Homebrew not found; install ${missing[*]} yourself to run make lint" >&2
    fi
fi

echo "Bootstrap complete."
