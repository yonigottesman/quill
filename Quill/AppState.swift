import SwiftUI
import KeyboardShortcuts

/// Top-level wiring: owns the services and registers the global hotkey handler.
@MainActor
final class AppState: ObservableObject {
    let inference = InferenceService()
    let history = HistoryStore()
    let textAction: TextActionService

    init() {
        textAction = TextActionService(inference: inference, history: history)

        KeyboardShortcuts.onKeyUp(for: .fixGrammar) { [weak textAction] in
            textAction?.run()
        }
        // Note: we do NOT prompt for Accessibility here. It's requested lazily the
        // first time the hotkey fires (TextActionService.run), and surfaced in the
        // control window — avoids nagging on every launch.
    }
}
