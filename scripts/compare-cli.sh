#!/usr/bin/env bash
# Validates that the Swift inference path (PromptBuilder + LlamaContext, fixed
# gemma-4 template) returns the SAME raw output as `llama cli` (the ground truth)
# for many prompts. Both run greedy + reasoning off so they're deterministic and
# comparable. Exits non-zero if any case diverges.
set -euo pipefail
cd "$(dirname "$0")/.."

FW_DIR="$PWD/Frameworks/llama.xcframework/macos-arm64_x86_64"
GGUF=$(find "$HOME/.cache/huggingface" -name "gemma-4-E2B-it-Q8_0.gguf" | head -1)
OUT=.scratch/compare
rm -rf "$OUT"; mkdir -p "$OUT"

echo "==> Building Swift harness against embedded llama.xcframework"
swiftc -O -F "$FW_DIR" -framework llama -Xlinker -rpath -Xlinker "$FW_DIR" -parse-as-library \
  Quill/Inference/PromptBuilder.swift \
  Quill/Inference/ModelLocator.swift \
  Quill/Inference/LlamaContext.swift \
  scripts/compare-harness.swift \
  -o .scratch/compare-harness

echo "==> Running Swift path (writes case_*.{sys,user,raw})"
.scratch/compare-harness "$OUT" 2>/dev/null

n=$(ls "$OUT"/case_*.raw | wc -l | tr -d ' ')
echo "==> Comparing $n cases against 'llama cli' (greedy, reasoning off)"
pass=0; fail=0
for raw in "$OUT"/case_*.raw; do
  i=$(basename "$raw" .raw | sed 's/case_//')
  sys="$OUT/case_$i.sys"; user="$OUT/case_$i.user"
  # llama cli, single-turn conversation: applies the gemma-4 jinja template to
  # system+user, greedy (--temp 0), thinking off. stdout carries a banner + the
  # echoed prompt + stats; the Python extractor anchors on the echoed user text
  # and returns just the model generation (matching LlamaContext.clean()'s trim).
  cli=$(llama cli -m "$GGUF" -sysf "$sys" -p "$(cat "$user")" \
        --temp 0 --reasoning off -st --no-warmup 2>/dev/null \
        | python3 scripts/extract-cli-output.py "$user")
  swift=$(cat "$raw")
  if [[ "$cli" == "$swift" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "──────── MISMATCH case $i ────────"
    echo "INPUT(user): $(cat "$user")"
    echo "SWIFT: >>>$swift<<<"
    echo "CLI:   >>>$cli<<<"
  fi
done
echo "════════════════════════════════════"
echo "PASS=$pass FAIL=$fail / $n"
[[ "$fail" -eq 0 ]]
