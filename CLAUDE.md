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
- **`scripts/test-prompt.sh`** compiles the inference code standalone with `swiftc`, but links the
  **same `Frameworks/llama.xcframework`** the app embeds (via `-F`/`-framework llama`) — so the harness
  and the app can never drift onto different llama.cpp builds. The framework is the build prerequisite;
  no Homebrew install needed. The harness compiles `ModelLocator.swift` (pure Foundation — resolves an
  already-present GGUF) but **not** `ModelDownloader.swift` (the `import HuggingFace` half — the only
  download path), so it builds without the SPM package. Keep that split: no HuggingFace symbols in
  `ModelLocator.swift`.

## Model

The app **auto-downloads** the weights on first load: `ModelDownloader` (swift-huggingface) fetches
them into the standard **HF cache**, then `ModelLocator` resolves the GGUF from that cache
(`gemma-4-E2B-it-*.gguf`, excluding `mmproj*`). State walks `.notLoaded → .downloading(progress) →
.loading → .loaded`. The cache is content-addressed, so a blob already there (e.g. from a prior
`llama-cli -hf …`) is reused, not re-fetched. Loaded on demand, stays resident; Unload frees it.

## Prompt & inference

`PromptBuilder` is **shared by the app and `test-prompt.sh`** so they can't drift. **After ANY change
to the prompt, template, sampling, or inference path, always run BOTH harnesses:
`./scripts/test-prompt.sh` (qualitative — eyeball the corrections) and `./scripts/compare-cli.sh`
(asserts byte-identical output vs. the `llama cli` oracle, PASS/FAIL).** Sampling is **greedy**
(deterministic — temperature was tried and was not the fix). The hard-won, non-obvious findings:

- **This `gemma-4-E2B-it` has a real `system` role** (its template supports `system`/`developer`,
  thinking, tools — unlike classic Gemma 2/3). The instruction goes in the system turn, the user turn
  carries only the text.
- **`applyChatTemplate` builds the gemma-4 template by hand — do NOT route it through
  `llama_chat_apply_template`.** That legacy C API only knows a fixed set of built-in templates and
  **returns -1 for gemma-4's jinja template** (its `<|turn>`/`<turn|>` markers + macros aren't
  recognized); the jinja engine that handles it lives in llama.cpp's `common` lib, which the app
  doesn't link. The old code's "fallback" then emitted the **classic Gemma `<start_of_turn>` format** —
  which isn't even in this vocab, so it **shredded into raw subword tokens** (7 garbage tokens per
  marker) with the system folded into the user turn. The model never saw a real system turn. The
  correct format is `<|turn>system\n{sys}<turn|>\n<|turn>user\n{usr}<turn|>\n<|turn>model\n`
  (`<|turn>`=105, `<turn|>`=106 are real special tokens; BOS via the tokenizer's `addSpecial`,
  not emitted in the string). System and user content are `trim`med to match the jinja template.
- **Ground-truth alignment is checked by `./scripts/compare-cli.sh`** — runs ~40 prompts through the
  Swift path AND `llama cli` (greedy `--temp 0`, `--reasoning off`) and asserts byte-identical raw
  output. Run it after any template/sampling change. (`llama cli` uses jinja, so it's the oracle; the
  app can't.)
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

## Auto-update (Sparkle)

In-app updates via **Sparkle 2** (SPM dep in `project.yml`). `UpdaterManager` wraps
`SPUStandardUpdaterController`; `AppState` owns it. The UX is deliberately **quiet** ("gentle
reminders"): scheduled checks + (when enabled) downloads happen in the background with Sparkle's
pop-ups suppressed, and the AppDelegate surfaces a **"Restart to update"** menu item once a download
is staged (`UpdaterManager.updateReadyToInstall`). The Settings toggle "Automatically download
updates" binds to Sparkle's `automaticallyDownloadsUpdates` (default ON on first run). A
"Check for updates…" menu item does a user-initiated check (this one *does* show Sparkle's UI — that's
correct for an explicit check).

- **`Quill/Info.plist` is GENERATED by XcodeGen** from `project.yml`'s `info.properties` and is
  **gitignored** — editing the plist directly is futile (it's overwritten every `xcodegen generate`,
  like the pbxproj). The feed URL, `SUPublicEDKey`, and the `CFBundleShortVersionString`/`CFBundleVersion`
  → `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` wiring all live in `project.yml`.
- **The build number must be real and monotonic** — Sparkle compares `CFBundleVersion`. `project.yml`
  pins `CURRENT_PROJECT_VERSION: "1"` as a **local placeholder only**; CI injects
  `git rev-list --count HEAD` (needs `fetch-depth: 0`). If it were stuck at 1, updates would never trigger.
- **EdDSA signing keys** (separate from Developer ID): public key in `project.yml` `SUPublicEDKey`,
  private key in the **login keychain** (from Sparkle's `generate_keys`) + a GitHub secret
  **`SPARKLE_ED_PRIVATE_KEY`** (`generate_keys -x`, base64). Every released DMG is signed with
  `sign_update` (use `bin/sign_update`, NOT `old_dsa_scripts/`) and the appcast carries the
  `sparkle:edSignature`. Sparkle refuses any update whose signature doesn't verify against the public key.
- **The appcast is `appcast.xml` committed in this repo**, served via
  `https://raw.githubusercontent.com/yonigottesman/quill/main/appcast.xml` (= `SUFeedURL`). **CI owns
  it** — the release job prepends an `<item>` (pointing at the GitHub release-asset DMG, with the
  EdDSA sig) and pushes it back to `main` with a `[skip ci]` commit. Never hand-edit it. The push can't
  loop: the `gate` job skips the build once `v<version>` exists.
- **Sparkle's embedded helpers must be re-signed for notarization** — this broke the first 0.1.3 build.
  Sparkle.framework bundles `Autoupdate`, `Updater.app`, and `Downloader.xpc`/`Installer.xpc`; xcodebuild's
  embedded signing gives them hardened runtime but **not a secure timestamp**, which the notary requires on
  every nested executable (status `Invalid`). The **"Harden Sparkle helpers"** step in `release.yml` re-signs
  them inside-out (`Versions/B/...`) with `--options runtime --timestamp` before the DMG is built. The
  notarize step dumps `notarytool log` on any non-`Accepted` status — read it first if this recurs. (Library
  validation was *not* the problem; SPM re-signs the framework with our Team ID, so no entitlements file is
  needed. If a future failure is genuinely library-validation, the fallback is `Quill.entitlements` with
  `com.apple.security.cs.disable-library-validation`.)
- **Sparkle requires HTTPS** feeds/downloads (ATS also blocks plain `http://localhost`), so there's no
  clean local live-update test — the production path is all HTTPS. Validate end-to-end via a
  `workflow_dispatch` CI dry-run (real notarized + EdDSA-signed DMG + committed appcast).

## Release / CI

`.github/workflows/release.yml` builds, signs, **notarizes & staples** the DMG on every push to
`main` and publishes it as a GitHub Release.

- **A release ships ONLY when you bump `MARKETING_VERSION` in `project.yml`.** A fast `gate` job reads
  the version and the macOS `build` job runs **only if no `v<MARKETING_VERSION>` release exists yet** —
  if the tag already exists the build is **skipped entirely** (no macOS build runs; the run is green).
  So **when you make a change you want released, bump `MARKETING_VERSION` before pushing** — otherwise
  nothing builds. (`workflow_dispatch` forces a build regardless, re-uploading the DMG onto the tag.)
- **ALWAYS ask the user whether to bump `MARKETING_VERSION` before every commit.** It's easy to forget
  and then the push builds nothing. So before committing any change, ask "bump the version?" and bump
  it (patch unless told otherwise) if they say yes.
- CI builds **Release config with `ENABLE_HARDENED_RUNTIME=YES`** (notarization requires it) — unlike
  the local `build.sh`, which is Debug + hardened-runtime off. If a change works locally but breaks
  the notarized build, suspect hardened runtime.
- The embedded `llama.xcframework` is **rebuilt from source in CI and cached**, keyed on
  `scripts/build-xcframework.sh` (which pins `LLAMA_CPP_REF`). Editing that script busts the cache.
- **Secrets** (five from the ezdash repo: `CSC_LINK`, `CSC_KEY_PASSWORD`, `APPLE_API_KEY_P8`,
  `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`) can't be copied between repos — GitHub never reveals secret
  values; set them from the Developer ID identity in the keychain + the App Store Connect `.p8`. A sixth,
  **`SPARKLE_ED_PRIVATE_KEY`** (base64 of the Sparkle EdDSA private key), is unique to this repo — see
  the Auto-update section. The EdDSA sign step fails the build if it's missing.

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
