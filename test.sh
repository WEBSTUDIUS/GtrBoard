#!/bin/bash
# Runs the standalone DSP/preset self-test. Release optimisation is used so
# the throughput assertions reflect the shipped binary.
set -euo pipefail
cd "$(dirname "$0")"

ROOT="$PWD"
export TMPDIR="$ROOT/.tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.modulecache"
export SWIFT_MODULECACHE_PATH="$ROOT/.modulecache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" .spm-cache .spm-config

echo "▸ Running GtrBoard self-tests…"
swift run -c release \
  --disable-sandbox \
  --cache-path .spm-cache \
  --config-path .spm-config \
  --manifest-cache local \
  GtrBoardSelfTest
