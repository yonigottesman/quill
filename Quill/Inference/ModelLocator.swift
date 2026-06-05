import Foundation
import HuggingFace

enum ModelLocatorError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Couldn't find the Gemma GGUF under \(path).\n" +
                   "Run `llama-cli -hf ggml-org/gemma-4-E2B-it-GGUF` once to download it."
        }
    }
}

/// Locates the gemma-4-E2B-it GGUF inside the standard Hugging Face cache.
/// The cache is populated by `llama-cli/llama-server -hf ggml-org/gemma-4-E2B-it-GGUF`.
enum ModelLocator {
    /// The Hugging Face repo holding the weights.
    static let repoID: Repo.ID = "ggml-org/gemma-4-E2B-it-GGUF"
    /// The main weights GGUF inside the repo. Matched as a download glob so we
    /// fetch ONLY this file — not the other quants or the `mmproj-*` vision
    /// projector (which this text-only app doesn't use).
    static let weightsFile = "gemma-4-E2B-it-Q8_0.gguf"

    /// `~/.cache/huggingface/hub/models--ggml-org--gemma-4-E2B-it-GGUF`
    static let repoDir = ("~/.cache/huggingface/hub/models--ggml-org--gemma-4-E2B-it-GGUF"
                          as NSString).expandingTildeInPath

    /// True when the weights are already present in the HF cache (so we can skip
    /// straight to loading without going through the download step).
    static var isDownloaded: Bool { (try? resolveGGUF()) != nil }

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

    /// Returns the path to the main weights GGUF (excludes the `mmproj-*` vision projector).
    static func resolveGGUF() throws -> String {
        let fm = FileManager.default
        let snapshotsDir = (repoDir as NSString).appendingPathComponent("snapshots")

        guard let snapshots = try? fm.contentsOfDirectory(atPath: snapshotsDir),
              !snapshots.isEmpty else {
            throw ModelLocatorError.notFound(snapshotsDir)
        }

        for snapshot in snapshots.sorted() {
            let dir = (snapshotsDir as NSString).appendingPathComponent(snapshot)
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            if let gguf = files.first(where: { $0.hasSuffix(".gguf") && !$0.hasPrefix("mmproj") }) {
                let full = (dir as NSString).appendingPathComponent(gguf)
                // HF snapshot entries are symlinks into ../blobs — resolve so llama.cpp opens the real file.
                return (try? fm.destinationOfSymbolicLink(atPath: full))
                    .map { resolved in
                        resolved.hasPrefix("/") ? resolved
                            : (dir as NSString).appendingPathComponent(resolved)
                    } ?? full
            }
        }
        throw ModelLocatorError.notFound(snapshotsDir)
    }
}
