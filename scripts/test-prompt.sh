#!/usr/bin/env bash
# Compiles the prompt/inference test harness against the SAME llama.cpp the app
# ships — the embedded Frameworks/llama.xcframework (pinned to LLAMA_CPP_REF by
# scripts/build-xcframework.sh) — so the test and the app can never drift onto
# different llama.cpp builds. No Homebrew install required.
set -euo pipefail
cd "$(dirname "$0")/.."

FW_DIR="$PWD/Frameworks/llama.xcframework/macos-arm64_x86_64"

mkdir -p .scratch

swiftc -O \
  -F "$FW_DIR" \
  -framework llama \
  -Xlinker -rpath -Xlinker "$FW_DIR" \
  Quill/Inference/PromptBuilder.swift \
  Quill/Inference/ModelLocator.swift \
  Quill/Inference/LlamaContext.swift \
  scripts/test-prompt.swift \
  -o .scratch/test-prompt

.scratch/test-prompt
