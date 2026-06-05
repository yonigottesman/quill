import Foundation

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
    /// `~/.cache/huggingface/hub/models--ggml-org--gemma-4-E2B-it-GGUF`
    static let repoDir = ("~/.cache/huggingface/hub/models--ggml-org--gemma-4-E2B-it-GGUF"
                          as NSString).expandingTildeInPath

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
