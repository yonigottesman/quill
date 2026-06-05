import AppKit

/// The synthetic-clipboard flow: on hotkey, copy the current selection via a
/// synthetic ⌘C, fix it, paste the result via ⌘V, then restore the original
/// clipboard. Rides the normal copy/paste path so it works in almost any app.
///
/// Two things keep this reliable:
///  - We never call `NSApp.activate` — the app is an accessory (LSUIElement), so
///    the source app keeps focus and receives our synthetic keystrokes.
///  - We poll `NSPasteboard.changeCount` instead of sleeping a fixed time, so we
///    read the copied text only once the source app has actually written it.
@MainActor
final class TextActionService {
    private let inference: InferenceService
    private let history: HistoryStore
    private var isRunning = false

    init(inference: InferenceService, history: HistoryStore) {
        self.inference = inference
        self.history = history
    }

    func run() {
        guard !isRunning else { return }
        guard Accessibility.ensureTrusted(prompt: true) else {
            NSSound.beep() // not trusted yet; system prompt was shown
            return
        }
        guard inference.state == .loaded else {
            NSSound.beep() // model not loaded — open the menu and click "Load model"
            return
        }
        isRunning = true
        Task { await perform() }
    }

    private func perform() async {
        defer { isRunning = false }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let beforeCopy = pasteboard.changeCount

        // 1. Synthetic ⌘C and wait for the source app to write the selection.
        postCommandKey(.c)
        guard await waitForChange(pasteboard, from: beforeCopy, timeoutMs: 500) else {
            restore(pasteboard, items: saved) // nothing selected / app didn't copy
            return
        }
        guard let selection = pasteboard.string(forType: .string),
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            restore(pasteboard, items: saved)
            return
        }

        // 2. Fix it.
        guard let fixed = await inference.fixGrammar(selection) else {
            restore(pasteboard, items: saved)
            return
        }

        history.add(before: selection, after: fixed)

        // 3. Write result, paste over the selection.
        pasteboard.clearContents()
        pasteboard.setString(fixed, forType: .string)
        let afterWrite = pasteboard.changeCount
        try? await Task.sleep(nanoseconds: 30_000_000) // let the write settle
        postCommandKey(.v)

        // 4. Restore the original clipboard once the paste has consumed our value,
        //    but only if the user hasn't copied something new in the meantime.
        try? await Task.sleep(nanoseconds: 450_000_000)
        if pasteboard.changeCount == afterWrite {
            restore(pasteboard, items: saved)
        }
    }

    // MARK: - Synthetic keystrokes

    private enum Key: CGKeyCode {
        case c = 8  // kVK_ANSI_C
        case v = 9  // kVK_ANSI_V
    }

    private func postCommandKey(_ key: Key) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Pasteboard change polling

    private func waitForChange(_ pasteboard: NSPasteboard, from start: Int, timeoutMs: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if pasteboard.changeCount != start { return true }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return pasteboard.changeCount != start
    }

    // MARK: - Snapshot / restore (preserves all types, not just plain text)

    private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restore(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
