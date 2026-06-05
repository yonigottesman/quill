import Foundation

/// Owns the resident model. Loads on demand (menu click) and stays in memory so
/// every hotkey press reuses it. UI binds to `state`.
@MainActor
final class InferenceService: ObservableObject {
    enum State: Equatable {
        case notLoaded
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: State = .notLoaded
    private(set) var modelPath: String?

    /// Free-form instructions appended to the prompt, edited in Settings. Persisted.
    @Published var additionalInstructions: String = UserDefaults.standard
        .string(forKey: "additionalInstructions") ?? "" {
        didSet { UserDefaults.standard.set(additionalInstructions, forKey: "additionalInstructions") }
    }

    private var llama: LlamaContext?

    func loadModel() {
        switch state {
        case .loading, .loaded: return
        case .notLoaded, .failed: break
        }
        state = .loading
        Task {
            do {
                let path = try ModelLocator.resolveGGUF()
                modelPath = path
                // Heavy multi-second load — keep it off the main actor.
                let context = try await Task.detached(priority: .userInitiated) {
                    try LlamaContext.create(modelPath: path)
                }.value
                llama = context
                state = .loaded
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Frees the resident model from memory. The LlamaContext's deinit releases
    /// the llama.cpp model/context (~5 GB) once the last reference drops.
    func unloadModel() {
        guard state == .loaded else { return }
        llama = nil
        modelPath = nil
        state = .notLoaded
    }

    /// Returns the corrected text, or nil if the model isn't loaded / produced nothing.
    func fixGrammar(_ text: String) async -> String? {
        guard let llama, state == .loaded else { return nil }
        let prompt = PromptBuilder.build(text: text, additionalInstructions: additionalInstructions)
        let raw = await llama.generate(prompt: prompt)
        let result = PromptBuilder.finalize(output: raw, original: text)
        return result.isEmpty ? nil : result
    }
}
