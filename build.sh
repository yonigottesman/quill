#!/usr/bin/env bash
# Build Quill and drop a ready-to-run ./Quill.app in this folder.
# Run it yourself with:  open Quill.app   (or just double-click it in Finder)
set -euo pipefail
cd "$(dirname "$0")"

# First build on a fresh machine also needs (one time):
#   sudo xcodebuild -runFirstLaunch && sudo xcodebuild -license accept
# -skipMacroValidation (below) is required for the KeyboardShortcuts SPM macro.

# Stop any running instance first — macOS's `open` reactivates a running app
# with the same bundle id instead of launching the new build.
pkill -9 -f Quill 2>/dev/null || true

# The app embeds llama.cpp via Frameworks/llama.xcframework (so it needs no local
# Homebrew install). It's a one-time, multi-minute build — produce it first.
if [ ! -d Frameworks/llama.xcframework ]; then
  echo "error: Frameworks/llama.xcframework is missing." >&2
  echo "       Build it once (needs full Xcode + cmake):  ./scripts/build-xcframework.sh" >&2
  exit 1
fi

xcodegen generate >/dev/null

set -o pipefail
xcodebuild -project Quill.xcodeproj -scheme Quill -configuration Debug \
  -derivedDataPath build -skipMacroValidation build 2>&1 \
  | grep -E "BUILD (SUCCEEDED|FAILED)|error:" || true

APP="build/Build/Products/Debug/Quill.app"
if [ ! -d "$APP" ]; then
  echo "Build failed — no app produced." >&2
  exit 1
fi

rm -rf Quill.app
ditto "$APP" Quill.app
echo
echo "✅ Built ./Quill.app"
echo "   Run it:  open Quill.app   (or double-click in Finder)"
