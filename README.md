<p align="center">
  <img src="docs/icon.png" width="160" alt="Quill icon">
</p>

<h1 align="center">Quill</h1>

<p align="center">
  A minimalist macOS menu-bar grammar &amp; typo fixer powered by a <strong>local</strong> LLM.
</p>

Press a global hotkey → Quill copies the selected text, fixes its spelling, grammar, and
capitalization with a local Gemma model, and pastes the result back in place.

**Nothing leaves your machine.** The model runs in-process via llama.cpp — no server, no
subprocess, no network. Your text is never uploaded anywhere.

## Install & use

1. Download the latest `Quill.dmg` from [Releases](../../releases) and drag Quill to Applications.
2. Launch it — a ✏️ icon appears in the menu bar.
3. Click the icon → **Load model**. The Gemma weights download automatically the first time
   (a one-time download); after that the model loads in a few seconds.
4. Open **Settings…** and pick a global hotkey.
5. Select text in any app and press your hotkey — Quill replaces it with the corrected version.

On first use, macOS asks for **Accessibility** permission (needed to simulate ⌘C/⌘V) — grant it,
then press the hotkey again.

Tune the correction style anytime in **Settings → Additional instructions** (e.g. "use British
spelling", "keep it casual"). **History** shows every before/after fix.

> Password and other secure-input fields block simulated keystrokes, so Quill can't fix text there.

## Development

Building from source, the architecture, and the non-obvious gotchas all live in
[`AGENTS.md`](AGENTS.md).
