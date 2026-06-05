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

- **The app embeds `Frameworks/llama.xcframework` — it does NOT depend on a local Homebrew
  llama install.** `project.yml` declares the xcframework as an Embed & Sign dependency, and
  `import llama` resolves to the framework's own bundled module map. The built `Quill.app`
  carries `libllama` inside `Contents/Frameworks` (found at runtime via the
  `@executable_path/../Frameworks` rpath).
- **The framework is a build prerequisite, not committed** (it's large; gitignored under
  `Frameworks/`). Produce it once with `scripts/build-xcframework.sh` before the first build —
  `build.sh` hard-errors with that instruction if it's missing. The script clones llama.cpp
  (sibling `../llama.cpp`), checks out a pinned tag, and builds an arm64 `LLAMA_BUILD_FRAMEWORK`
  release with Metal embedded.
- **Pinned to llama.cpp `b9290`** (= Homebrew's `llama.cpp 9290`) via `LLAMA_CPP_REF` in
  `build-xcframework.sh`, because the C API in `LlamaContext.swift` was written against that
  release's symbols (`llama_model_load_from_file`, `llama_init_from_model`,
  `llama_model_chat_template` + `llama_chat_apply_template`, `llama_memory_clear`/
  `llama_get_memory`, etc.). Bumping the ref to a release with a changed API is where
  `LlamaContext.swift` breaks.
- **The test harness still uses Homebrew.** `scripts/test-prompt.sh` compiles the inference
  code directly against `/opt/homebrew` libllama via `Vendor/llama/module.modulemap` for fast
  iteration — that module map is now test-harness-only, the app no longer references it.

## Model

`ModelLocator` resolves the GGUF from the **Hugging Face cache** (`gemma-4-E2B-it-*.gguf`, excluding
`mmproj*`). The app **does not download** — it expects the cache populated by
`llama-cli -hf ggml-org/gemma-4-E2B-it-GGUF`. Missing model → `state = .failed` with a message
telling the user to run that command. Loading is on-demand (menu) and stays resident; Unload frees it.

## Prompt, sampling & the test harness

- The prompt is built by `PromptBuilder` — **shared by the app and the test harness so they can't
  drift**. `InferenceService` appends the Settings "additional instructions" on top (omitted if empty).
- **Sampling is greedy** (`llama_sampler_init_greedy` in `LlamaContext`). Grammar/typo fixing is a
  deterministic task; greedy corrects misspellings more confidently than low-temp sampling and gives
  stable, repeatable output. (Switching temperature was tried — it was *not* the fix.)
- The base prompt is a proofreader instruction that explicitly says **"reply with only the single
  corrected version, do not repeat the original."** This wording is load-bearing: without it the small
  E2B model **echoes the original then the correction on short fragments** (e.g. `sure no promblem` →
  original + fix, or leaves the typo). Full sentences were always fine; short fragments exposed it.
- **Validate any prompt/sampler change with `./scripts/test-prompt.sh`** — it compiles a standalone
  `@main` harness (`scripts/test-prompt.swift`) against Homebrew libllama and runs typo texts +
  additional-instruction cases through the real `PromptBuilder`/`LlamaContext`. It keeps the
  previously-failing fragments as regression cases. Gotcha baked in: it ends with
  `fflush(stdout); _exit(0)` — `_exit` skips the benign teardown SIGABRT but also skips stdio flush,
  so the `fflush` is required or you get no output.

## App icon

`scripts/make-icon.sh` renders the menu-bar `pencil.line` symbol (white on an indigo gradient) →
`Quill/Quill.icns` (committed; bundled via `CFBundleIconFile` in `project.yml`). Re-run only to change
the icon. The app is `LSUIElement`, so this is the Finder/Spotlight icon — there is no Dock icon.

## Architecture notes / gotchas

- **Entry point is classic AppKit** (`main.swift` → `NSApplication` + `AppDelegate`), not a SwiftUI
  `@main App`. The menu bar uses **`NSStatusItem`**, not SwiftUI `MenuBarExtra` — the SwiftUI
  menu-bar/lifecycle path did not render reliably under `LSUIElement` on this macOS. Settings/History
  are SwiftUI views hosted in plain `NSWindow`s.
- A SwiftUI `Form` hosted via `NSWindow(contentViewController:) + setContentSize` **intermittently
  collapses to just the title bar**. The Settings window dodges this with the `makeWindow` helper in
  `AppDelegate` (explicit `contentRect` + an `NSHostingView` with autoresizing) — use it for any new
  window rather than `contentViewController`.
- The exit-time `SIGABRT` from ggml/Metal static teardown is **benign** (only at process quit).
- KeyboardShortcuts does **not** block system-reserved combos — e.g. setting ⌘⌃Q hijacks Lock Screen.
  The chosen shortcut lives in `defaults read com.yonigo.Quill`.
