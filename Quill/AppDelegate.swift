import AppKit
import Combine
import SwiftUI

/// Builds the menu-bar item with a classic NSStatusItem (more reliable than
/// SwiftUI's MenuBarExtra under LSUIElement / notch displays) and owns the app's
/// services. The Settings window is still a SwiftUI `Settings` scene.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let appState = AppState()

    private var statusItem: NSStatusItem!
    private var stateObserver: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "Quill")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        rebuildMenu()

        // Keep the menu in sync with model load state.
        stateObserver = appState.inference.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
    }

    /// Re-opening the app (Spotlight/Finder/`open`) re-shows the control window —
    /// the safety net for when the menu-bar item is hidden under a full menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: - Menu

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        switch appState.inference.state {
        case .notLoaded:
            add(menu, "Load model", #selector(loadModel))
        case .loading:
            add(menu, "Loading model…", nil)
        case .loaded:
            add(menu, "Model loaded ✓", nil)
            add(menu, "Unload model", #selector(unloadModel))
        case .failed(let message):
            add(menu, "Load failed — retry", #selector(loadModel))
            add(menu, message, nil)
        }

        menu.addItem(.separator())
        add(menu, "History…", #selector(openHistory))
        add(menu, "Settings…", #selector(openSettings), key: ",")
        add(menu, "Quit Quill", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == nil ? nil : self
        item.isEnabled = action != nil
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func loadModel() { appState.inference.loadModel() }
    @objc private func unloadModel() { appState.inference.unloadModel() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "Quill",
                size: NSSize(width: 420, height: 300),
                content: SettingsView(inference: appState.inference))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Creates a fixed-size window whose SwiftUI content fills the content area.
    /// Using an explicit contentRect + NSHostingView (not contentViewController +
    /// setContentSize) avoids the Form-collapses-to-a-bar sizing bug.
    private func makeWindow(title: String, size: NSSize, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: content)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.center()
        return window
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            let hosting = NSHostingController(rootView: HistoryView(store: appState.history))
            let window = NSWindow(contentViewController: hosting)
            window.title = "History"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 460, height: 420))
            window.center()
            historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }
}
