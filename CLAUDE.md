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
  drift**. `InferenceService` appends the Settings "additional instructions" to the system turn
  (omitted if empty).
- **This `gemma-4-E2B-it` model HAS a real `system` role** (its chat template supports `system`/
  `developer` roles, plus thinking and tool-calling — unlike the classic Gemma 2/3 template that has
  only `user`/`model`). So the instruction goes in a dedicated **system turn** and the **user turn
  carries only the text to fix**. `LlamaContext.applyChatTemplate` sends a `[system, user]` message
  pair through `llama_chat_apply_template` (C strings via `strdup`; `n_msg` is `size_t`/Swift `Int`,
  not `Int32`).
- The system instruction is a proofreader: fixes spelling/grammar **and capitalization** (sentence
  starts, `i`/`i'll`/`i'm` → `I`/`I'll`/`I'm`) with **minimal changes / no rephrasing**, and preserves
  Markdown, code, code comments, URLs, paths, @-mentions, emails, symbols, and emoji. It must say
  **"reply with only the corrected text, do not repeat the original"** — load-bearing wording.
- **The user turn wraps the text in a passive `Text to proofread:` label** (`PromptBuilder.userPrompt`).
  This is the real behavior dial and is load-bearing/non-obvious: **with** it, long text and Markdown
  are handled safely but the model under-corrects rare ultra-short fragments; **without** it, short
  fragments get fixed but long/Markdown inputs derail (e.g. a paragraph → `"The model"`). The anchor is
  kept because the app proofreads *selected prose* (the paragraph case dominates). Tried and *worse*,
  do not re-add: a one-shot example, a `Corrected:` cue, or an **imperative** anchor ("Correct this
  text:" reads as a chat request → conversational derail).
- **`PromptBuilder.finalize(output:original:)` is a fail-safe, applied by both the app and the harness.**
  The small greedy model can still derail on *degenerate* inputs; `finalize` discards such output and
  returns the user's original text unchanged — the app must **never paste model chatter** in place of a
  selection. Four signatures: assistant self-reference markers; a ≤3-word input that explodes into a
  much longer output; a substantial input that collapses to a tiny output; and a multi-line input
  flattened to one line. A missed typo on a fragment is the accepted cost.
- **Sampling is greedy** (`llama_sampler_init_greedy` in `LlamaContext`) for stable, repeatable output —
  also what makes the harness a reliable pass/fail check. (Temperature was tried for the echo issue and
  was *not* the fix; derails are handled by the system turn + anchor + `finalize`, not sampling.)
- **Validate any prompt/guard change with `./scripts/test-prompt.sh`** — it compiles a standalone
  `@main` harness (`scripts/test-prompt.swift`) against Homebrew libllama and runs ~45 cases (short
  fragments, paragraphs that must not drop content, capitalization, Markdown/code/comment/special-char
  preservation, additional-instruction cases, and derail-bait) through the real
  `PromptBuilder`/`LlamaContext`, applying `finalize` exactly like the app. Gotcha baked in: it ends
  with `fflush(stdout); _exit(0)` — `_exit` skips the benign teardown SIGABRT but also skips stdio
  flush, so the `fflush` is required or you get no output.

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
