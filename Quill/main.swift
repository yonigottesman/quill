import AppKit

// Classic AppKit entry point (no SwiftUI App lifecycle). This reliably starts
// the AppKit run loop for an LSUIElement menu-bar app, which the SwiftUI
// `App` + MenuBarExtra/Settings lifecycle failed to do on this macOS.
//
// Program start runs on the main thread, so we can safely assume MainActor
// isolation to construct the @MainActor AppDelegate / AppState.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
