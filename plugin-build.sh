#!/bin/bash
# Builds the GtrBoard AUv3 extension, embeds it in its host app, installs the
# host into /Applications (which registers the plug-in) and validates it with
# Apple's auval. Requires full Xcode and xcodegen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is missing: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
xcodebuild -project GtrBoardPlugin.xcodeproj \
  -scheme GtrBoardPluginHost \
  -configuration Release \
  -derivedDataPath .build-plugin \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  build

APP=".build-plugin/Build/Products/Release/GtrBoard Plugin Host.app"
DEST="/Applications/GtrBoard Plugin Host.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

pkill -f "GtrBoard Plugin Host" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
# Drop the build-product registration so only the installed copy is visible.
pluginkit -r "$PWD/$APP/Contents/PlugIns/GtrBoardAU.appex" 2>/dev/null || true
"$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true

"$LSREGISTER" -f "$DEST"
open "$DEST"
sleep 3

echo "▸ Validating GtrBoard AUv3…"
auval -v aufx GtrB GtrB
echo ""
echo "Ready. Restart Logic/GarageBand, then add the plug-in on a track:"
echo "  Audio FX → Audio Units → Andrey Ilin → GtrBoard"
