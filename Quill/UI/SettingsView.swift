import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var inference: InferenceService
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Fix grammar hotkey:", name: .fixGrammar)
                Toggle("Launch at login", isOn: $launchAtLogin.isEnabled)
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
