# CLAUDE.md

Non-obvious things only — read the code for the rest.

## Build

`./build.sh` → `xcodegen generate` + `xcodebuild`, copies the bundle to `./Quill.app`.

- **Edit `project.yml`, never the pbxproj** — `Quill.xcodeproj` is XcodeGen-generated and gitignored.
- `xcodebuild` needs `-skipMacroValidation` (KeyboardShortcuts SPM macro). First build on a machine
  also needs `sudo xcodebuild -runFirstLaunch` + `-license accept`.
- **`build.sh` kills any running Quill first, on purpose** — macOS `open` re-activates the running
  app (same bundle id) instead of launching the new binary, so the rebuild would silently not run.
  Don't remove the `pkill`.

## Signing & the Accessibility trap

Signed with **Developer ID Application (team 29HD5Q85D4)** in `project.yml` — load-bearing, **do not
switch to ad-hoc**. macOS ties the Accessibility (TCC) grant to code identity; ad-hoc changes the
cdhash every build, so the grant is silently revoked → endless "control this computer" prompts.
Stable Developer ID keeps the grant across rebuilds. If it gets stuck: `tccutil reset Accessibility
com.yonigo.Quill`, relaunch, re-grant.

Accessibility is needed only to post the synthetic ⌘C/⌘V CGEvents — the Carbon global hotkey works
without it. Requested lazily on first hotkey use.

## llama.cpp

In-process via the C API (`import llama`). The app **embeds `Frameworks/llama.xcframework`** (Embed &
Sign, found at runtime via `@executable_path/../Frameworks`) — no Homebrew dependency at runtime.

- The framework is a build prerequisite, gitignored, **not committed**. `scripts/build-xcframework.sh`
  produces it; `build.sh` errors if missing.
- **There is NO `LLAMA_BUILD_FRAMEWORK` cmake option** (an earlier script assumed one — silently
  ignored, produced loose dylibs). The script delegates to llama.cpp's own `build-xcframework.sh`,
  trimmed at runtime to macOS only (upstream builds 7 Apple platforms incl. visionOS, whose SDK isn't
  always installed).
- **Pinned to llama.cpp `b9290`** (`LLAMA_CPP_REF`) — the C API `LlamaContext.swift` was written
  against. A release with a changed API breaks `LlamaContext.swift`.
- **`scripts/test-prompt.sh` is the exception** — it compiles the inference code standalone against
  Homebrew `libllama` via `Vendor/llama/module.modulemap` (test-harness-only; the app doesn't use it).

## Model

`ModelLocator` resolves the GGUF from the **HF cache** (`gemma-4-E2B-it-*.gguf`, excluding `mmproj*`).
The app does **not** download — missing model → `state = .failed` telling the user to run
`llama-cli -hf ggml-org/gemma-4-E2B-it-GGUF`. Loaded on demand, stays resident; Unload frees it.

## Prompt & inference

`PromptBuilder` is **shared by the app and `test-prompt.sh`** so they can't drift. **Validate every
prompt/guard change with `./scripts/test-prompt.sh`.** Sampling is **greedy** (deterministic — temperature
was tried and was not the fix). The hard-won, non-obvious findings:

- **This `gemma-4-E2B-it` has a real `system` role** (its template supports `system`/`developer`,
  thinking, tools — unlike classic Gemma 2/3). The instruction goes in the system turn, the user turn
  carries only the text. `applyChatTemplate` sends `[system, user]` (C strings via `strdup`; `n_msg`
  is `size_t`/`Int`).
- **The `Text to proofread:` anchor is applied conditionally by length** (`userPrompt`) — it's the
  behavior dial. With it, long/Markdown input is safe but short input is under-corrected; without it,
  short input gets fixed but long input derails (paragraph → `"The model"`). So **≤7 words → no
  anchor**, longer → anchor.
- **`finalize(output:original:)` is a fail-safe** (app + harness): if the output looks like a derail
  (self-reference/chit-chat markers *not in the input*, a short input exploding, a long input
  collapsing, or a multi-line input flattened to one line), it returns the **original unchanged** —
  the app must never paste model chatter. A missed typo is the accepted cost.
- Tried and **worse, do not re-add**: a one-shot example (hallucinates), a `Corrected:` cue (same), an
  imperative anchor like "Correct this text:" (reads as chat → conversational derail).
- `test-prompt.sh` ends with `fflush(stdout); _exit(0)` — `_exit` skips the benign teardown SIGABRT
  but also skips stdio flush, so the `fflush` is required or you get no output.

## App icon

`scripts/make-icon.sh` → `Quill/Quill.icns` (committed; `CFBundleIconFile`). It's the Finder/Spotlight
icon — the app is `LSUIElement`, no Dock icon. Re-run only to change it.

## Architecture gotchas

- **Entry point is classic AppKit** (`main.swift` → `NSApplication` + `AppDelegate`), not SwiftUI
  `@main`. Menu bar is **`NSStatusItem`**, not `MenuBarExtra` — SwiftUI's menu-bar/lifecycle path
  didn't render reliably under `LSUIElement` here. Settings/History are SwiftUI in plain `NSWindow`s.
- A SwiftUI `Form` via `NSWindow(contentViewController:)` **intermittently collapses to the title
  bar**. Use the `makeWindow` helper in `AppDelegate` (explicit `contentRect` + autoresizing
  `NSHostingView`) for any new window.
- KeyboardShortcuts does **not** block system-reserved combos (e.g. ⌘⌃Q hijacks Lock Screen). The
  chosen shortcut lives in `defaults read com.yonigo.Quill`.
- The exit-time `SIGABRT` (ggml/Metal static teardown) is benign — process quit only.
</content>
