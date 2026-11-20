#!/bin/bash
# Builds and installs GtrBoard into /Applications (~/Applications fallback).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
TARGET="/Applications"
if [[ ! -w "$TARGET" ]]; then
  TARGET="$HOME/Applications"
  mkdir -p "$TARGET"
fi
rm -rf "$TARGET/GtrBoard.app"
cp -R "dist/GtrBoard.app" "$TARGET/"
echo "▸ Installed: $TARGET/GtrBoard.app"
