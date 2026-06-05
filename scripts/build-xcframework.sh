#!/usr/bin/env bash
# Builds a self-contained macOS (arm64) llama.xcframework for distribution and
# drops it at Frameworks/llama.xcframework. Run this when you want to stop using
# the Homebrew bootstrap linkage. Requires full Xcode + cmake.
#
# After running, edit project.yml: remove SWIFT_INCLUDE_PATHS / HEADER_SEARCH_PATHS /
# LIBRARY_SEARCH_PATHS / OTHER_LDFLAGS / LD_RUNPATH_SEARCH_PATHS from the Quill target,
# add the xcframework as an Embed & Sign dependency, then `xcodegen generate`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/../llama.cpp}"
OUT="$REPO_ROOT/Frameworks/llama.xcframework"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: full Xcode required. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [ ! -d "$LLAMA_DIR" ]; then
  echo "Cloning llama.cpp into $LLAMA_DIR ..."
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
fi

cd "$LLAMA_DIR"
cmake -B build-macos -G Xcode \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
  -DLLAMA_BUILD_FRAMEWORK=ON
cmake --build build-macos --config Release -j

FRAMEWORK="$(find "$LLAMA_DIR/build-macos" -name llama.framework -type d | head -1)"
if [ -z "$FRAMEWORK" ]; then
  echo "error: llama.framework not found under build-macos (LLAMA_BUILD_FRAMEWORK may have changed)." >&2
  echo "Fallback: build static libs + a hand-written module map (see plan)." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$REPO_ROOT/Frameworks"
xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$OUT"
echo "Created $OUT"
