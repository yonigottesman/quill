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
- **Menu-bar only** — `LSUIElement`, no Dock icon. Built on classic AppKit
  (`NSStatusItem`); Settings and History are SwiftUI views hosted in `NSWindow`s.
- **Global hotkey** via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).
- **Works almost anywhere** — synthetic-clipboard flow (⌘C → fix → ⌘V → restore clipboard).
- **Model:** `ggml-org/gemma-4-E2B-it-GGUF`, loaded once on demand and kept resident.

## Build & run (local dev)

Requires full **Xcode** (not just Command Line Tools), Homebrew, and the model in the
Hugging Face cache.

```bash
# 0. One-time setup: point at full Xcode, install tools, download the model once
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
brew install cmake xcodegen llama.cpp
llama-cli -hf ggml-org/gemma-4-E2B-it-GGUF   # populates ~/.cache/huggingface

# 1. Build (xcodegen generate + xcodebuild, signed, → ./Quill.app)
./build.sh
open Quill.app
```

On first run: grant **Accessibility** when prompted (System Settings → Privacy &
Security → Accessibility) — required for the synthetic ⌘C/⌘V. Then open the menu-bar
item, **Load model**, set a hotkey in **Settings…**, select some text anywhere, and
press the hotkey.

> The Xcode project is generated from `project.yml` by XcodeGen — `Quill.xcodeproj` is
> disposable and gitignored. Edit `project.yml`, never the pbxproj.

## llama.cpp linkage

For fast local dev, Quill links Homebrew's `libllama` (`/opt/homebrew`) via a module
map (`Vendor/llama/module.modulemap`). This is **not** distributable (absolute paths).

To produce a self-contained app, run `scripts/build-xcframework.sh` to build a macOS
`llama.xcframework`, embed it, then drop the Homebrew search-path / `-lllama` settings
from `project.yml`. The Swift code doesn't change.

## Notes

- The exit-time `SIGABRT` from ggml/Metal static teardown is benign (only at quit).
- Password / secure-input fields swallow synthetic keystrokes — expected limitation.
</content>
