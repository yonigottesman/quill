# CLAUDE.md

Guidance for working on Quill. Only the non-obvious things are here — read the code for the rest.

## Build & run

```bash
./build.sh        # → ./Quill.app  (signed, ready to run)
open Quill.app
```

`build.sh` runs `xcodegen generate` then `xcodebuild`, and copies the bundle out of the deep
DerivedData path to `./Quill.app`.

- **The Xcode project is generated** from `project.yml` by XcodeGen. `Quill.xcodeproj` is
  gitignored and disposable — **edit `project.yml`, never the pbxproj**.
- `xcodebuild` here needs `-skipMacroValidation` (KeyboardShortcuts SPM macro). First-ever build
  on a machine also needs `sudo xcodebuild -runFirstLaunch` and `sudo xcodebuild -license accept`.
- **`build.sh` kills any running Quill first, on purpose.** macOS `open` re-activates an
  already-running app with the same bundle id instead of launching the new binary — so without the
  kill, your rebuild silently doesn't run and nothing appears to change. This wasted a lot of time
  once; don't remove the `pkill`.

## Signing & the Accessibility-permission trap

The app is signed with **Developer ID Application (team 29HD5Q85D4)**, set in `project.yml`
(`CODE_SIGN_IDENTITY` / `DEVELOPMENT_TEAM`). This is deliberate and load-bearing:

- macOS ties the Accessibility (TCC) grant to the app's code identity. **Ad-hoc signing changes the
  cdhash on every build**, so each rebuild looks like a brand-new untrusted app and the grant is
  silently revoked → endless "Quill would like to control this computer" prompts even though the
  toggle looks ON. A stable Developer ID identity keeps the designated requirement constant, so the
  grant survives rebuilds. **Do not switch back to ad-hoc (`-`).**
- If the permission ever gets stuck/stale: `tccutil reset Accessibility com.yonigo.Quill`, relaunch,
  grant once.
- Accessibility is needed to **post the synthetic ⌘C/⌘V CGEvents**, not for the hotkey. The Carbon
  global hotkey (KeyboardShortcuts) works without it. The app requests it lazily on first hotkey use.

## llama.cpp linkage

Inference is **in-process** via the llama.cpp C API (`import llama`), not a server/subprocess.

- Currently linked against **Homebrew's libllama** (`/opt/homebrew`) through
  `Vendor/llama/module.modulemap` — see the `SWIFT_INCLUDE_PATHS` / `-lllama` settings in
  `project.yml`. This is a **dev bootstrap and is not distributable** (absolute paths to
  `/opt/homebrew`).
- To ship a self-contained app: run `scripts/build-xcframework.sh` to produce
  `Frameworks/llama.xcframework`, then drop the Homebrew search-path/`-lllama` settings and embed the
  xcframework. The Swift code doesn't change.
- The C API was pinned against the symbols in the Homebrew `llama.h` at build time
  (`llama_model_load_from_file`, `llama_init_from_model`, `llama_model_chat_template` +
  `llama_chat_apply_template`, `llama_memory_clear`/`llama_get_memory`, etc.). If a Homebrew upgrade
  changes the API, `LlamaContext.swift` is where it breaks.

## Model

`ModelLocator` resolves the GGUF from the **Hugging Face cache** (`gemma-4-E2B-it-*.gguf`, excluding
`mmproj*`). The app **does not download** — it expects the cache populated by
`llama-cli -hf ggml-org/gemma-4-E2B-it-GGUF`. Missing model → `state = .failed` with a message
telling the user to run that command. Loading is on-demand (menu) and stays resident; Unload frees it.

## Architecture notes / gotchas

- **Entry point is classic AppKit** (`main.swift` → `NSApplication` + `AppDelegate`), not a SwiftUI
  `@main App`. The menu bar uses **`NSStatusItem`**, not SwiftUI `MenuBarExtra` — the SwiftUI
  menu-bar/lifecycle path did not render reliably under `LSUIElement` on this macOS. Settings/History
  are SwiftUI views hosted in plain `NSWindow`s via `NSHostingController`.
- A SwiftUI `Form` in a bare `NSWindow` **collapses to ~zero height** unless given an explicit
  `.frame(height:)` — that's why window content sizes are set explicitly.
- The exit-time `SIGABRT` from ggml/Metal static teardown is **benign** (only at process quit).
- KeyboardShortcuts does **not** block system-reserved combos — e.g. setting ⌘⌃Q hijacks Lock Screen.
  The chosen shortcut lives in `defaults read com.yonigo.Quill`.
