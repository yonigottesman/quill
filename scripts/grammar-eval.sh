#!/usr/bin/env bash
# Graded grammar REGRESSION test: scores the app's model on a labeled set of
# grammar/spelling/punctuation fixes and prints a pass/fail number, so you can
# tell if a model swap / template / sampling change made proofreading WORSE.
# (test-prompt.sh shows before/after to eyeball; this one asserts and scores.)
#
# Compiled against the SAME embedded Frameworks/llama.xcframework the app ships,
# and resolves the same GGUF the app uses (ModelLocator) — no Homebrew, no args.
# Exits non-zero if any case fails, so it works as a CI gate too.
set -euo pipefail
cd "$(dirname "$0")/.."

FW_DIR="$PWD/Frameworks/llama.xcframework/macos-arm64_x86_64"
mkdir -p .scratch

swiftc -O \
  -F "$FW_DIR" \
  -framework llama \
  -Xlinker -rpath -Xlinker "$FW_DIR" \
  -parse-as-library \
  Quill/Inference/PromptBuilder.swift \
  Quill/Inference/ModelLocator.swift \
  Quill/Inference/LlamaContext.swift \
  scripts/grammar-eval.swift \
  -o .scratch/grammar-eval

.scratch/grammar-eval
