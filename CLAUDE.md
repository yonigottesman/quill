# CLAUDE.md

Non-obvious things only — read the code (it's heavily commented) for the rest.

## Build & run

- `./build.sh` → `xcodegen generate` + `xcodebuild`, drops a ready-to-run `./Quill.app`.
- **Edit `project.yml`, never `Quill.xcodeproj` or `Quill/Info.plist`** — both are XcodeGen-generated
  and gitignored, overwritten every `xcodegen generate`.
- The app embeds `Frameworks/llama.xcframework` (gitignored, **not committed**). `build.sh` errors if
  it's missing — build it once with `scripts/build-xcframework.sh`. llama.cpp is pinned to a ref in
  that script; a different ref can break `LlamaContext.swift` (written against the C API).
- See `build.sh` header for one-time fresh-machine setup.

## Prompt / inference / model changes — always test

`PromptBuilder` and `LlamaContext` are shared by the app and the test harnesses so they can't drift.
**After ANY change to the prompt, template, sampling, inference path, or the model, run BOTH:**

- `./scripts/test-prompt.sh` — qualitative, eyeball the corrections.
- `./scripts/compare-cli.sh` — asserts the Swift path is byte-identical to the `llama cli` oracle.

Sampling is greedy/deterministic (temperature was tried, didn't help). The hard-won details about the
gemma-4 chat template, the length-conditional anchor, and the `finalize` derail guard all live in
comments in `PromptBuilder.swift` and `LlamaContext.swift` — read those before touching them.

## Releasing — ask before every commit

A release ships only when `MARKETING_VERSION` in `project.yml` is bumped (CI skips the build if the
`v<version>` tag already exists). So **before every commit, ask the user "bump the version?"** and bump
it (patch unless told otherwise) if yes — otherwise the push builds nothing.

CI (`.github/workflows/release.yml`) builds, signs, notarizes, and publishes the DMG, then updates the
Sparkle `appcast.xml` itself — **never hand-edit `appcast.xml`**. The workflow + `project.yml` comments
explain the signing/notarization/Sparkle wiring; an agent working on CI can find what it needs there.

## Architecture gotchas

- **Entry point is classic AppKit** (`main.swift` → `NSApplication` + `AppDelegate`), not SwiftUI
  `@main`. Menu bar is `NSStatusItem`, not `MenuBarExtra` (SwiftUI's path didn't render reliably under
  `LSUIElement`). For new SwiftUI windows use the `makeWindow` helper in `AppDelegate` — a `Form` in a
  bare `NSWindow(contentViewController:)` intermittently collapses to the title bar.
- **Signing is Developer ID, not ad-hoc** (`project.yml`) — load-bearing. macOS ties the Accessibility
  (TCC) grant to code identity; ad-hoc changes the cdhash every build and silently revokes the grant.
  If it gets stuck: `tccutil reset Accessibility com.yonigo.Quill`, relaunch, re-grant. Accessibility
  is needed only to post the synthetic ⌘C/⌘V; requested lazily on first hotkey use.
- The exit-time `SIGABRT` (ggml/Metal static teardown) is benign — process quit only.
</content>
