#!/usr/bin/env bash
# Builds a self-contained macOS (arm64) llama.xcframework and drops it at
# Frameworks/llama.xcframework. This is what makes the app independent of a local
# Homebrew llama.cpp install — the framework is embedded in Quill.app. Run this
# ONCE before the first build (and again to bump the llama.cpp version). Requires
# full Xcode + cmake.
#
# Implementation note: there is NO `LLAMA_BUILD_FRAMEWORK` cmake option (a previous
# version of this script assumed one — it was silently ignored and produced loose
# dylibs, not a framework). Instead we delegate to llama.cpp's OWN, maintained
# `build-xcframework.sh`, which statically links ggml + llama into a single
# framework binary per platform. That script targets seven Apple platforms
# (incl. visionOS, whose SDK isn't always installed), so we trim it to macOS/arm64
# before running. The project (project.yml) embeds the result; just ./build.sh after.
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

# Clean stale build dirs (a prior run may have configured them with conflicting
# cmake caches), then trim the upstream script to macOS/arm64 only.
rm -rf build-macos build-apple build-macos-static

echo "Generating macOS-only build-xcframework script ..."
python3 - <<'PY'
import re
src = open("build-xcframework.sh").read().splitlines(keepends=True)
out, i, n = [], 0, len(src)

def is_build_header(l):
    return l.lstrip().startswith('echo "Building for')

def is_terminator(l):
    s = l.lstrip()
    return (is_build_header(l)
            or s.startswith('setup_framework_structure')
            or s.startswith('combine_static_libraries')
            or 'create-xcframework' in l
            or 'Creating XCFramework' in l
            or s.startswith('# Create'))

while i < n:
    l = src[i]
    # Drop every `echo "Building for <X>..."` cmake block except macOS.
    if is_build_header(l):
        block = [l]; i += 1
        while i < n and not is_terminator(src[i]):
            block.append(src[i]); i += 1
        if 'macOS' in l:
            out.extend(block)
        continue
    # Keep only the macОS framework assembly CALLS (quoted arg follows the name —
    # this must NOT match the function *definitions* `name() {`).
    if l.lstrip().startswith(('setup_framework_structure "', 'combine_static_libraries "')):
        if 'build-macos' in l:
            out.append(l)
        i += 1; continue
    # In the create-xcframework call, drop non-macОS slice args.
    if ('-framework ' in l or '-debug-symbols ' in l) and any(p in l for p in ('build-ios', 'build-visionos', 'build-tvos')):
        i += 1; continue
    out.append(l); i += 1

text = ''.join(out)
# macOS arm64 only (drop the universal x86_64 slice — Quill is Apple Silicon).
text = text.replace('arm64;x86_64', 'arm64')
open("build-xcframework-macos.sh", "w").write(text)
PY
chmod +x build-xcframework-macos.sh

echo "Building macОS llama.xcframework (static ggml+llama, Metal embedded) ..."
./build-xcframework-macos.sh

SRC_XCF="$LLAMA_DIR/build-apple/llama.xcframework"
if [ ! -d "$SRC_XCF" ]; then
  echo "error: $SRC_XCF was not produced — upstream build-xcframework.sh layout may have changed." >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$REPO_ROOT/Frameworks"
cp -R "$SRC_XCF" "$OUT"
echo "Created $OUT"
