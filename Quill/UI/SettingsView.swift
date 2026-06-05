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
                TextField("Additional instructions",
                          text: $inference.additionalInstructions,
                          prompt: Text("e.g. start all fixes with FIX"),
                          axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .labelsHidden()
            }
        }
        .formStyle(.grouped)
    }
}
