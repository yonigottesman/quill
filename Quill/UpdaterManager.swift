import Foundation
import Combine
import Sparkle

/// Wraps Sparkle's auto-updater. Mirrors the `LaunchAtLogin` pattern: a small
/// `@MainActor ObservableObject` that exposes exactly what the UI binds to.
///
/// UX is deliberately quiet ("gentle reminders"): Sparkle checks and — when the
/// toggle is on — downloads in the background, but we suppress its pop-up windows
/// and instead surface a "Restart to update" item in the menu-bar dropdown once an
/// update is staged. Clicking it re-enters the update flow, which resumes the
/// already-downloaded session and lets Sparkle install + relaunch.
@MainActor
final class UpdaterManager: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {

    private var controller: SPUStandardUpdaterController!

    /// Drives the Settings checkbox. Mirrors Sparkle's own persisted preference,
    /// writing changes straight back to the updater (Sparkle persists it for us).
    @Published var automaticallyDownloadsUpdates: Bool = false {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }

    /// `true` once an update has been downloaded and staged — the AppDelegate shows
    /// the "Restart to update" menu item while this is set.
    @Published private(set) var updateReadyToInstall = false

    override init() {
        super.init()
        // self is the delegate for both the updater and the standard user driver.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        // Default automatic downloads ON for first-run users (so "Restart to update"
        // can appear without any setup); once the user touches the toggle, Sparkle's
        // persisted choice wins.
        if UserDefaults.standard.object(forKey: "SUAutomaticallyUpdate") == nil {
            updater.automaticallyDownloadsUpdates = true
        }
        // Reflect Sparkle's persisted auto-download setting in the toggle. Assigning
        // here fires didSet, which writes the same value straight back — harmless.
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }

    /// The single "advance the update flow" action, behind both menu items. Sparkle
    /// is stateful, so one call does the right thing in either context: with nothing
    /// staged it checks for updates ("Check for updates…"); with a download already
    /// staged it presents the install-and-relaunch step ("Restart to update").
    func checkForUpdates() { controller.updater.checkForUpdates() }

    // MARK: - SPUStandardUserDriverDelegate (gentle reminders → menu-only UX)

    /// Opt into gentle reminders: we present updates in our own UI (the menu bar).
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Don't let Sparkle pop its own window for a background-found update — we show
    /// "Restart to update" in the dropdown instead.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    /// Sparkle has an update to show. Once it's downloaded/staged, light the menu item.
    nonisolated func standardUserDriver(
        willHandleShowingUpdate handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let staged = state.stage == .downloaded || state.stage == .installing
        Task { @MainActor in self.updateReadyToInstall = staged }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Task { @MainActor in self.updateReadyToInstall = false }
    }
}
