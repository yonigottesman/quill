import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var inference: InferenceService

    var body: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Fix grammar:", name: .fixGrammar)
            }

            Section("Additional instructions") {
                TextField("e.g. use British spelling, keep it casual",
                          text: $inference.additionalInstructions, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }
}
