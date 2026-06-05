#!/usr/bin/env bash
# Compiles the prompt/inference test harness against Homebrew libllama and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .scratch

swiftc -O \
  -I Vendor/llama \
  -L/opt/homebrew/lib -lllama \
  -Xlinker -rpath -Xlinker /opt/homebrew/lib \
  Quill/Inference/PromptBuilder.swift \
  Quill/Inference/ModelLocator.swift \
  Quill/Inference/LlamaContext.swift \
  scripts/test-prompt.swift \
  -o .scratch/test-prompt

.scratch/test-prompt
