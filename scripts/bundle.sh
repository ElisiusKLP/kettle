#!/usr/bin/env bash
# Builds the Kettle executable and wraps it into an ad-hoc signed .app bundle.
#
#   scripts/bundle.sh <debug|release> <dev|prod>
#
#   dev  -> build/Kettle Dev.app  (io.github.kettle.dev, unsandboxed, own data folder)
#   prod -> build/Kettle.app      (io.github.kettle, App Sandbox)
set -euo pipefail

config=${1:?usage: bundle.sh <debug|release> <dev|prod>}
variant=${2:?usage: bundle.sh <debug|release> <dev|prod>}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

case "$config" in
    debug) build_flags=(-c debug) ;;
    release) build_flags=(-c release -Xswiftc -Osize) ;;
    *) echo "unknown config: $config" >&2; exit 64 ;;
esac

case "$variant" in
    dev) app_name="Kettle Dev"; plist=Resources/Info.dev.plist; entitlements=() ;;
    prod) app_name="Kettle"; plist=Resources/Info.plist; entitlements=(--entitlements Resources/Kettle.entitlements) ;;
    *) echo "unknown variant: $variant" >&2; exit 64 ;;
esac

swift build "${build_flags[@]}" --product Kettle
bin_dir=$(swift build "${build_flags[@]}" --show-bin-path)

app="build/$app_name.app"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Kettle" "$app/Contents/MacOS/$executable"
cp "$plist" "$app/Contents/Info.plist"
for resource in AppIcon.icns Whistle.wav; do
    if [[ -f "Resources/$resource" ]]; then
        cp "Resources/$resource" "$app/Contents/Resources/$resource"
    fi
done

if [[ "$config" == release ]]; then
    strip -x "$app/Contents/MacOS/$executable"
fi

codesign --force --sign - --options runtime ${entitlements[@]+"${entitlements[@]}"} "$app"
echo "Bundled $app"
