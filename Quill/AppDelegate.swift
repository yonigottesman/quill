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
    private var updateObserver: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    // The informational status line (e.g. "Downloading model… 42%"). Held so a
    // download-progress tick can update its title in place instead of tearing
    // down and rebuilding the whole menu — see handleStateChange.
    private var statusMenuItem: NSMenuItem?
    // Whether the currently-rendered menu was built for the `.downloading` case.
    private var renderedDownloading = false
    // Advances on each download tick to animate the status line's ellipsis.
    private var downloadAnimTick = 0

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
            .sink { [weak self] state in self?.handleStateChange(state) }

        // …and with update availability, so "Restart to update" appears once a
        // download is staged.
        updateObserver = appState.updater.$updateReadyToInstall
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

    /// Routes a model-state change to either a cheap in-place title update or a
    /// full structural rebuild. During a download `$state` fires ~10×/sec; doing a
    /// `removeAllItems()` rebuild on every tick made an open menu flicker (and the
    /// percentage unreadable). While we stay inside `.downloading`, only the status
    /// line's title changes, so we mutate it directly — no flicker. Any case
    /// transition still does a full rebuild.
    private func handleStateChange(_ state: InferenceService.State) {
        if case .downloading = state, renderedDownloading {
            downloadAnimTick &+= 1
            statusMenuItem?.title = downloadingTitle()
            return
        }
        rebuildMenu()
    }

    /// Indeterminate label. swift-huggingface 0.9.0 doesn't deliver a usable
    /// download fraction here — its per-task progress callback never fires, so the
    /// value sits at 0 until the transfer finishes. Showing a percent would read as
    /// frozen, so we spin a braille glyph to convey liveness instead. `$state` still
    /// ticks ~10×/sec while downloading, which clocks the animation.
    ///
    /// The glyph is a single fixed-width character, so the title length never
    /// changes — a varying-length label (e.g. cycling dots) makes the menu
    /// re-measure and visibly jitter its width.
    private func downloadingTitle() -> String {
        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        return "Downloading model \(frames[downloadAnimTick % frames.count])"
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        statusMenuItem = nil
        renderedDownloading = false

        switch appState.inference.state {
        case .notLoaded:
            add(menu, "Load model", #selector(loadModel))
        case .downloading:
            downloadAnimTick = 0
            statusMenuItem = add(menu, downloadingTitle(), nil)
            renderedDownloading = true
        case .loading:
            add(menu, "Loading model…", nil)
        case .loaded:
            add(menu, "Model loaded ✓", nil)
            add(menu, "Unload model", #selector(unloadModel))
        case .failed(let message):
            add(menu, "Load failed — retry", #selector(loadModel))
            add(menu, message, nil)
        }

        if appState.updater.updateReadyToInstall {
            menu.addItem(.separator())
            add(menu, "Restart to update", #selector(restartToUpdate))
        }

        menu.addItem(.separator())
        add(menu, "History…", #selector(openHistory))
        add(menu, "Check for updates…", #selector(checkForUpdates))
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
    // Both menu items drive the same stateful Sparkle action (see UpdaterManager):
    // a staged download resumes into install-and-relaunch, otherwise it just checks.
    @objc private func restartToUpdate() { appState.updater.checkForUpdates() }
    @objc private func checkForUpdates() { appState.updater.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "Quill",
                size: NSSize(width: 420, height: 300),
                content: SettingsView(inference: appState.inference, updater: appState.updater))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Creates a fixed-size window whose SwiftUI content fills the content area.
    /// Using an explicit contentRect + NSHostingView (not contentViewController +
    /// setContentSize) avoids the Form-collapses-to-a-bar sizing bug.
    private func makeWindow(title: String, size: NSSize, resizable: Bool = false,
                            content: some View) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .closable]
        if resizable { styleMask.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
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
            historyWindow = makeWindow(
                title: "History",
                size: NSSize(width: 460, height: 420),
                resizable: true,
                content: HistoryView(store: appState.history))
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }
}
