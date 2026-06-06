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

    /// The exact weights GGUF this app ships. `ModelDownloader` fetches ONLY this
    /// file, and `resolveGGUF()` matches it by name. Lives here (not in
    /// ModelDownloader.swift) so it's a single source of truth the standalone test
    /// harness can see — it compiles this file but NOT the HuggingFace half.
    ///
    /// Matching by exact name is load-bearing: the HF cache can hold OTHER quants
    /// of the same repo (e.g. a stray `UD-Q2_K_XL` left by `llama-cli -hf`), and
    /// some of those use tensor types (TQ2_0) the pinned llama.cpp's Metal backend
    /// has no kernel for — loading one SIGSEGVs on first decode. The old "first
    /// .gguf that isn't mmproj" heuristic picked whatever the filesystem listed
    /// first, which could be the wrong, crashing model.
    static let weightsFile = "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf"

    /// True when the weights are already present in the HF cache (so we can skip
    /// straight to loading without going through the download step).
    static var isDownloaded: Bool { (try? resolveGGUF()) != nil }

    /// Returns the path to the main weights GGUF.
    ///
    /// Prefers the exact `weightsFile` across snapshots (newest first), so a stray
    /// extra quant in the cache can never be loaded instead. Falls back to the
    /// first non-`mmproj` `.gguf` only when `weightsFile` is absent (e.g. a cache
    /// populated by `-hf` with a differently-named quant).
    static func resolveGGUF() throws -> String {
        let fm = FileManager.default
        let snapshotsDir = (repoDir as NSString).appendingPathComponent("snapshots")

        guard let snapshots = try? fm.contentsOfDirectory(atPath: snapshotsDir),
              !snapshots.isEmpty else {
            throw ModelLocatorError.notFound(snapshotsDir)
        }

        // Newest snapshot first — commit-hash dir names aren't time-ordered, so sort by mtime.
        let snapshotDirs = snapshots
            .map { (snapshotsDir as NSString).appendingPathComponent($0) }
            .sorted { mtime($0, fm) > mtime($1, fm) }

        // Pass 1: the exact model we ship. Pass 2: any non-mmproj gguf (legacy fallback).
        for matches in [{ (f: String) in f == weightsFile },
                        { (f: String) in f.hasSuffix(".gguf") && !f.hasPrefix("mmproj") }] {
            for dir in snapshotDirs {
                guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                if let gguf = files.first(where: matches) {
                    let full = (dir as NSString).appendingPathComponent(gguf)
                    // HF snapshot entries are symlinks into ../blobs — resolve so llama.cpp opens the real file.
                    return URL(fileURLWithPath: full).resolvingSymlinksInPath().path
                }
            }
        }
        throw ModelLocatorError.notFound(snapshotsDir)
    }

    private static func mtime(_ path: String, _ fm: FileManager) -> Date {
        let attrs = try? fm.attributesOfItem(atPath: path)
        return (attrs?[.modificationDate] as? Date) ?? .distantPast
    }
}
