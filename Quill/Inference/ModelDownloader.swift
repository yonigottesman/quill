import Foundation
import HuggingFace

/// Downloading the weights — the one and only way the app fetches the model.
/// Kept separate from ModelLocator so the standalone test harness can compile the
/// locator without the HuggingFace SPM package (it never downloads). The app
/// always compiles this file.
extension ModelLocator {
    /// The Hugging Face repo holding the weights. Unsloth's QAT (quantization-aware
    /// trained) build matches Q8 quality on proofreading while being ~42% faster and
    /// ~2.2 GB smaller in GPU memory — see scripts/grammar-eval.sh.
    static let repoID: Repo.ID = "unsloth/gemma-4-E2B-it-qat-GGUF"
    // The weights filename (`weightsFile`) lives in ModelLocator.swift — single
    // source of truth shared with the resolver. It's matched as a download glob
    // below so we fetch ONLY that file, not the other quants or the `mmproj-*`
    // vision projector (which this text-only app doesn't use).

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
