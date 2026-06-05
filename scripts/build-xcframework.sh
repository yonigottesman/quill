#!/usr/bin/env bash
# Builds a self-contained macOS (arm64) llama.xcframework and drops it at
# Frameworks/llama.xcframework. This is what makes the app independent of a local
# Homebrew llama.cpp install — the framework is embedded in Quill.app. Run this
# ONCE before the first build (and again to bump the llama.cpp version). Requires
# full Xcode + cmake.
#
# The project (project.yml) already embeds Frameworks/llama.xcframework, so no
# further edits are needed after running this — just ./build.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA_DIR="${LLAMA_CPP_DIR:-$REPO_ROOT/../llama.cpp}"
OUT="$REPO_ROOT/Frameworks/llama.xcframework"

# Pin to the llama.cpp release the Swift C API in LlamaContext.swift was written
# against (matches Homebrew's `llama.cpp 9290`). Building HEAD instead risks C API
# drift that breaks LlamaContext.swift. Override with LLAMA_CPP_REF=master to track HEAD.
LLAMA_CPP_REF="${LLAMA_CPP_REF:-b9290}"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: full Xcode required. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [ ! -d "$LLAMA_DIR" ]; then
  echo "Cloning llama.cpp into $LLAMA_DIR ..."
  git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
fi

cd "$LLAMA_DIR"
echo "Checking out llama.cpp $LLAMA_CPP_REF ..."
git fetch --tags --quiet origin
git checkout --quiet "$LLAMA_CPP_REF"
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
