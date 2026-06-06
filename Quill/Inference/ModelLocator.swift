import Foundation

enum ModelLocatorError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Couldn't find the Gemma GGUF under \(path) after downloading. " +
                   "Try unloading and loading again to re-download."
        }
    }
}

/// Locates the gemma-4-E2B-it GGUF inside the standard Hugging Face cache.
/// The cache is populated by `ModelLocator.download()` (see ModelDownloader.swift)
/// or by `llama-cli/llama-server -hf unsloth/gemma-4-E2B-it-qat-GGUF`.
///
/// This file is pure Foundation so the standalone test harness
/// (scripts/test-prompt.sh) can compile it without the HuggingFace SPM package —
/// the harness only resolves an already-present model, it never downloads.
enum ModelLocator {
    /// `~/.cache/huggingface/hub/models--unsloth--gemma-4-E2B-it-qat-GGUF`
    static let repoDir = ("~/.cache/huggingface/hub/models--unsloth--gemma-4-E2B-it-qat-GGUF"
                          as NSString).expandingTildeInPath

    /// True when the weights are already present in the HF cache (so we can skip
    /// straight to loading without going through the download step).
    static var isDownloaded: Bool { (try? resolveGGUF()) != nil }

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
                return URL(fileURLWithPath: full).resolvingSymlinksInPath().path
            }
        }
        throw ModelLocatorError.notFound(snapshotsDir)
    }
}
