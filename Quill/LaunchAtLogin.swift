import SwiftUI
import ServiceManagement

/// Wraps `SMAppService.mainApp` so Settings can show a "Launch at login" toggle.
/// Registering the main app as a login item makes macOS relaunch Quill after a
/// reboot/login. The toggle reflects (and writes) the live system state.
@MainActor
final class LaunchAtLogin: ObservableObject {
    /// `true` when Quill is registered to start at login. Setting it
    /// registers/unregisters the login item; on failure it reverts.
    @Published var isEnabled: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard isEnabled != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("LaunchAtLogin: failed to \(isEnabled ? "register" : "unregister"): \(error)")
                isEnabled = !isEnabled   // revert the toggle to the real state
            }
        }
    }
}
