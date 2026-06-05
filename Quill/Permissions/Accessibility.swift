import AppKit
import ApplicationServices

/// Accessibility (AXIsProcessTrusted) is required to POST synthetic CGEvents
/// (the ⌘C / ⌘V we use to copy & paste). The Carbon global hotkey itself does
/// NOT need it — only the event posting does, so without trust the hotkey fires
/// but nothing gets copied/pasted.
enum Accessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Returns current trust; when `prompt` is true and not yet trusted, macOS
    /// shows the system "grant accessibility" prompt.
    @discardableResult
    static func ensureTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
