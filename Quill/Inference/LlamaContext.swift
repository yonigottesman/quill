import Foundation
import llama

enum LlamaError: LocalizedError {
    case modelLoad(String)
    case contextInit

    var errorDescription: String? {
        switch self {
        case .modelLoad(let path): return "Failed to load model at \(path)"
        case .contextInit: return "Failed to create llama context"
        }
    }
}

/// In-process wrapper around the llama.cpp C API. One model + context is loaded
/// once and kept resident; `generate` runs a single independent completion (the
/// KV cache is cleared after each call). Modeled on llama.cpp's `llama.swiftui`
/// example, updated to the current C API.
actor LlamaContext {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private var batch: llama_batch
    private let nCtx: Int32

    // MARK: - Lifecycle

    /// Loads the GGUF and initializes a context. Heavy (multi-second) — call off the main actor.
    static func create(modelPath: String, contextLength: UInt32 = 4096) throws -> LlamaContext {
        llama_backend_init()

        let modelParams = llama_model_default_params() // default n_gpu_layers offloads all to Metal
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            llama_backend_free()
            throw LlamaError.modelLoad(modelPath)
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = contextLength
        ctxParams.n_batch = 2048
        let threads = Int32(max(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        ctxParams.n_threads = threads
        ctxParams.n_threads_batch = threads

        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            llama_backend_free()
            throw LlamaError.contextInit
        }

        return LlamaContext(model: model, context: context)
    }

    private init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.nCtx = Int32(llama_n_ctx(context))
        self.batch = llama_batch_init(2048, 0, 1)

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        // Greedy: always take the most likely token. Grammar/typo fixing is a
        // deterministic task — greedy is more confident at correcting misspellings
        // than low-temperature sampling, and gives stable, repeatable output.
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        self.sampler = chain
    }

    deinit {
        llama_sampler_free(sampler)
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        llama_backend_free()
    }

    // MARK: - Generation

    /// Runs one completion for `userContent` (wrapped in the Gemma chat template)
    /// and returns the cleaned model output.
    func generate(prompt userContent: String, maxTokens: Int = 1024) -> String {
        let templated = applyChatTemplate(userContent: userContent)
        let tokens = tokenize(templated, addSpecial: true)
        guard !tokens.isEmpty else { return "" }

        // Decode the prompt; only the last token needs logits.
        batchClear()
        for (i, token) in tokens.enumerated() {
            batchAdd(token, llama_pos(i), seqId: 0, logits: i == tokens.count - 1)
        }
        guard llama_decode(context, batch) == 0 else { resetKV(); return "" }

        var bytes = [UInt8]()
        var position = Int32(tokens.count)

        for _ in 0..<maxTokens {
            let tokenId = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
            if llama_vocab_is_eog(vocab, tokenId) { break }
            bytes.append(contentsOf: pieceBytes(tokenId))

            batchClear()
            batchAdd(tokenId, position, seqId: 0, logits: true)
            position += 1
            if position >= nCtx { break }
            if llama_decode(context, batch) != 0 { break }
        }

        resetKV()
        return clean(String(decoding: bytes, as: UTF8.self))
    }

    private func resetKV() {
        llama_memory_clear(llama_get_memory(context), true)
    }

    // MARK: - Chat template

    private func applyChatTemplate(userContent: String) -> String {
        guard let tmpl = llama_model_chat_template(model, nil) else {
            return hardcodedGemmaTemplate(userContent)
        }
        return userContent.withCString { contentPtr in
            "user".withCString { rolePtr -> String in
                var message = llama_chat_message(role: rolePtr, content: contentPtr)
                var buffer = [CChar](repeating: 0, count: userContent.utf8.count + 256)
                var needed = llama_chat_apply_template(tmpl, &message, 1, true, &buffer, Int32(buffer.count))
                if needed > Int32(buffer.count) {
                    buffer = [CChar](repeating: 0, count: Int(needed))
                    needed = llama_chat_apply_template(tmpl, &message, 1, true, &buffer, Int32(buffer.count))
                }
                guard needed > 0 else { return hardcodedGemmaTemplate(userContent) }
                let utf8 = buffer.prefix(Int(needed)).map { UInt8(bitPattern: $0) }
                return String(decoding: utf8, as: UTF8.self)
            }
        }
    }

    private func hardcodedGemmaTemplate(_ content: String) -> String {
        "<start_of_turn>user\n\(content)<end_of_turn>\n<start_of_turn>model\n"
    }

    /// Drops a leading `<think>…</think>` block and stray turn markers, then trims.
    private func clean(_ text: String) -> String {
        var out = text
        if let end = out.range(of: "</think>") {
            out = String(out[end.upperBound...])
        }
        out = out.replacingOccurrences(of: "<end_of_turn>", with: "")
                 .replacingOccurrences(of: "<start_of_turn>", with: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tokenization helpers

    private func tokenize(_ text: String, addSpecial: Bool) -> [llama_token] {
        let byteCount = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(byteCount) + (addSpecial ? 1 : 0) + 8)
        var n = text.withCString {
            llama_tokenize(vocab, $0, byteCount, &tokens, Int32(tokens.count), addSpecial, true)
        }
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = text.withCString {
                llama_tokenize(vocab, $0, byteCount, &tokens, Int32(tokens.count), addSpecial, true)
            }
        }
        return Array(tokens.prefix(Int(max(0, n))))
    }

    private func pieceBytes(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 16)
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(0, n))).map { UInt8(bitPattern: $0) }
    }

    // MARK: - Batch helpers (not part of the C API)

    private func batchClear() {
        batch.n_tokens = 0
    }

    private func batchAdd(_ token: llama_token, _ position: llama_pos, seqId: llama_seq_id, logits: Bool) {
        let i = Int(batch.n_tokens)
        batch.token[i] = token
        batch.pos[i] = position
        batch.n_seq_id[i] = 1
        batch.seq_id[i]![0] = seqId
        batch.logits[i] = logits ? 1 : 0
        batch.n_tokens += 1
    }
}
