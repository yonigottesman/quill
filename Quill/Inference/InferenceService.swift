import Foundation

/// Owns the resident model. Loads on demand (menu click) and stays in memory so
/// every hotkey press reuses it. UI binds to `state`.
@MainActor
final class InferenceService: ObservableObject {
    enum State: Equatable {
        case notLoaded
        case downloading(Double)   // 0...1 fraction
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

    /// Downloads the model if needed, then loads it. The state walks
    /// `.downloading(progress)` → `.loading` → `.loaded` so the menu reflects
    /// each phase. Re-entrant calls while already busy are ignored.
    func loadModel() {
        switch state {
        case .downloading, .loading, .loaded: return
        case .notLoaded, .failed: break
        }
        Task {
            do {
                // Fetch into the HF cache first if the weights aren't there yet.
                // Already-present blobs are reused, not re-downloaded.
                if !ModelLocator.isDownloaded {
                    state = .downloading(0)
                    try await ModelLocator.download { [weak self] fraction in
                        self?.state = .downloading(fraction)
                    }
                }

                state = .loading
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
        let system = PromptBuilder.systemPrompt(additionalInstructions: additionalInstructions)
        let raw = await llama.generate(system: system, user: PromptBuilder.userPrompt(text: text))
        let result = PromptBuilder.finalize(output: raw, original: text, additionalInstructions: additionalInstructions)
        return result.isEmpty ? nil : result
    }
}
