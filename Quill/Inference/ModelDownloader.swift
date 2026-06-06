import Foundation
import HuggingFace

/// Downloading the weights — the one and only way the app fetches the model.
/// Kept separate from ModelLocator so the standalone test harness can compile the
/// locator without the HuggingFace SPM package (it never downloads). The app
/// always compiles this file.
extension ModelLocator {
    /// The Hugging Face repo holding the weights.
    static let repoID: Repo.ID = "ggml-org/gemma-4-E2B-it-GGUF"
    /// The main weights GGUF inside the repo. Matched as a download glob so we
    /// fetch ONLY this file — not the other quants or the `mmproj-*` vision
    /// projector (which this text-only app doesn't use).
    static let weightsFile = "gemma-4-E2B-it-Q8_0.gguf"

    /// Downloads the weights GGUF into the standard Hugging Face cache — the same
    /// cache `resolveGGUF()` reads, shared with the Python `huggingface_hub`
    /// client. The cache is content-addressed, so an already-present blob is NOT
    /// re-downloaded (a partial/complete prior download is reused, not discarded).
    /// `progress` is delivered on the main actor as a 0...1 fraction.
    static func download(progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        // The no-`to:` overload writes into the default HF cache and returns the
        // cache snapshot dir; `resolveGGUF()` then finds the file there.
        _ = try await HubClient.default.downloadSnapshot(
            of: repoID,
            matching: [weightsFile],
            progressHandler: { progress($0.fractionCompleted) }
        )
    }
}
