#!/bin/bash
# Build a no-App-Sandbox macOS release of Fa.
#
# The standard `flutter build macos --release` produces a sandboxed app. This
# script re-signs that build with ReleaseNoSandbox.entitlements so Fa can spawn
# system interpreters and other tools that the App Sandbox would block.
set -euo pipefail

cd "$(dirname "$0")/.."

# Build the Release app first (uses real signing if a cert is available).
./scripts/build_macos.sh --release

app_path="build/macos/Build/Products/Release/demo.app"
entitlements_path="macos/Runner/ReleaseNoSandbox.entitlements"
output_dir="build/macos/release-nosandbox"
output_zip="$output_dir/fa-macos-nosandbox.zip"

if [[ ! -d "$app_path" ]]; then
  echo "error: expected app bundle at $app_path" >&2
  exit 1
fi

# Use the same identity that flutter used. If no real cert is configured,
# flutter signs ad-hoc with identity "-"; codesign accepts "-" for ad-hoc too.
identity="${MACOS_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 -E 'Apple Development|Apple Distribution|Developer ID' \
  | sed -n 's/.*"\(.*\)".*/\1/p' || true)}"
if [[ -z "$identity" ]]; then
  identity="-"
fi

rm -rf "$output_dir"
mkdir -p "$output_dir"

echo "Re-signing $app_path without App Sandbox (identity: $identity)..."
codesign --force --deep --sign "$identity" --options runtime \
  --entitlements "$entitlements_path" "$app_path"

# Produce a zip artifact for GitHub Releases.
ditto -c -k --keepParent "$app_path" "$output_zip"
echo "No-sandbox release artifact: $output_zip"
