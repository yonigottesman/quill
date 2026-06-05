<p align="center">
  <img src="docs/icon.png" width="160" alt="Quill icon">
</p>

<h1 align="center">Quill</h1>

<p align="center">
  A minimalist macOS menu-bar grammar &amp; typo fixer powered by a <strong>local</strong> LLM.
</p>

Press a global hotkey → Quill copies the selected text, fixes it with a local Gemma
model running **in-process** via llama.cpp (no server, no network, nothing leaves your
machine), and pastes the result back in place.

## Highlights

- **Fully local & private** — inference runs in-process via the llama.cpp C API; no
  subprocess, no server, no network.
- **Self-contained** — the app embeds llama.cpp; no Homebrew/llama install needed at runtime.
- **Menu-bar only** — `LSUIElement`, no Dock icon. Classic AppKit (`NSStatusItem`); Settings
  and History are SwiftUI in `NSWindow`s.
- **Global hotkey** via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts);
  synthetic-clipboard flow (⌘C → fix → ⌘V → restore) works almost anywhere.
- **Model:** `ggml-org/gemma-4-E2B-it-GGUF`, loaded once on demand and kept resident.

## Develop

Needs full Xcode, plus `cmake`, `xcodegen`, and `llama.cpp` (`brew install cmake xcodegen llama.cpp`).

```bash
# One-time: build the embedded llama framework, and fetch the model into the HF cache
./scripts/build-xcframework.sh
llama-cli -hf ggml-org/gemma-4-E2B-it-GGUF

# Build & run (→ ./Quill.app)
./build.sh && open Quill.app
```

On first hotkey use, grant **Accessibility** when prompted (needed for the synthetic ⌘C/⌘V).
Then: menu-bar item → **Load model** → set a hotkey in **Settings…** → select text → press it.

Iterate on the prompt/inference without a full build: `./scripts/test-prompt.sh`.

## How it fits together

- **`project.yml` → XcodeGen → `Quill.xcodeproj`** (gitignored, disposable — edit `project.yml`).
- **`Frameworks/llama.xcframework`** is embedded (Embed & Sign), so `Quill.app` is self-contained.
  It's a one-time build artifact, gitignored; `build.sh` errors if it's missing. Pinned to llama.cpp
  `b9290` (the C API `LlamaContext.swift` targets).
- See `CLAUDE.md` for the non-obvious gotchas (signing/TCC, the prompt design, build internals).

## Notes

- The exit-time `SIGABRT` from ggml/Metal static teardown is benign (only at quit).
- Password / secure-input fields swallow synthetic keystrokes — expected limitation.
