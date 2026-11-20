#!/bin/bash
# Builds the release executable, wraps it in a proper .app bundle, copies the
# Info.plist/icon and ad-hoc signs the result. The app is placed in dist/.
# This script intentionally does not touch SwiftPM's global caches.
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$PWD"
export TMPDIR="$ROOT/.tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.modulecache"
export SWIFT_MODULECACHE_PATH="$ROOT/.modulecache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" .spm-cache .spm-config dist

SWIFT_FLAGS=(
  --disable-sandbox
  --cache-path .spm-cache
  --config-path .spm-config
  --manifest-cache local
)

# SwiftUI's property-wrapper macros need the macro plugin that ships with
# Xcode. On a Command Line Tools-only machine the newest SDK can declare the
# macros without providing the plugin, so prefer the 26.5 SDK when it exists
# (override with GTRBOARD_SDK=/path/to/MacOSX.sdk).
SDK="${GTRBOARD_SDK:-}"
if [[ -z "$SDK" ]]; then
  # Only use the CLT fallback when Command Line Tools are the selected
  # developer directory. With full Xcode selected (including GitHub's macOS
  # runners) use Xcode's own SDK and toolchain, which ship the macro plugin.
  DEVELOPER_PATH="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$DEVELOPER_PATH" == *"/CommandLineTools"* &&
        -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
    SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
  fi
fi
BUILD_ARGS=(-c release --product GtrBoard)
if [[ -n "$SDK" ]]; then
  BUILD_ARGS+=(--sdk "$SDK")
fi
BUILD_ARGS+=("${SWIFT_FLAGS[@]}")

echo "▸ Building GtrBoard (release)…"
swift build "${BUILD_ARGS[@]}"

APP="$ROOT/dist/GtrBoard.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/GtrBoard" "$APP/Contents/MacOS/GtrBoard"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
chmod +x "$APP/Contents/MacOS/GtrBoard"

# Ad-hoc signing is enough for a locally built, non-sandboxed app and gives
# macOS a stable identity for the microphone permission prompt.
codesign --force --sign - --identifier com.andreyilin.GtrBoard "$APP" >/dev/null
codesign --verify --strict "$APP"

echo "▸ Built: $APP"
