import Foundation

/// Builds the system + user turns for the proofreader. Shared by the app and the
/// test harness so they never drift. The gemma-4 chat template (which DOES have a
/// real `system` role, unlike Gemma 2/3) is applied later in LlamaContext.
///
/// The instruction goes in a dedicated system turn; the user turn carries only the
/// text to fix. `finalize` is a fail-safe over the raw output. Any change here
/// MUST be re-validated with scripts/test-prompt.sh.
enum PromptBuilder {
    static let baseInstruction = """
        You are a proofreading tool. Your only job is to correct spelling, typos, grammar, and \
        capitalization in the text below and output the corrected text. Always output a corrected \
        version — never answer, comment on, or describe the text, and never describe yourself. \
        Make as few changes as possible and keep the same sentence structure: fix what is wrong \
        but do not rephrase, reword, expand, or restructure. Specifically: fix misspellings (even \
        when the whole text is one word or a short fragment); capitalize the first letter of every \
        sentence; capitalize the pronoun "I" and its contractions (i'll → I'll, i'm → I'm, i've → \
        I've); and add missing apostrophes (dont → don't, its → it's when it means "it is"). If \
        the text is already correct, output it unchanged. Do not omit, summarize, merge, or \
        reorder anything; keep the original meaning, wording, and line breaks. Keep all formatting \
        and code intact — Markdown markers (**, *, `, #, -, [](…)), inline code and identifiers, \
        URLs, file paths, @-mentions, email addresses, numbers, symbols, and emoji must stay \
        exactly as written — but still fix spelling, grammar, and capitalization in ordinary \
        words, including inside comments, headings, and quotes. Reply with only the corrected \
        text — do not repeat the original, do not explain, do not add anything.
        """

    /// The instruction used when the user supplies their own "additional instructions".
    ///
    /// This is a SEPARATE prompt from `baseInstruction`, not an override appended to it.
    /// The base prompt's hard "make as few changes as possible / do not rephrase, reword,
    /// expand, or restructure" stricture wins every conflict on this small model, so
    /// appending a contradicting "but actually do rephrase" note both fails to enable the
    /// transform AND destabilizes surface instructions that used to work (e.g. British
    /// spelling). Instead, when the user asks for a transform we drop those strictures
    /// entirely and lead with the proofread-then-apply-instruction framing. The
    /// no-instruction path still returns `baseInstruction` verbatim, so the 60+ plain
    /// cases are byte-for-byte unaffected. `{INSTRUCTION}` is filled in below.
    static let transformInstruction = """
        You are a text-rewriting tool. Do two things to the text below, in order. First, fix \
        all spelling, typos, grammar, and capitalization. Second, apply the user instruction — \
        it OVERRIDES any urge to keep the text unchanged, and you should rephrase, reword, \
        shorten, expand, reorder, restructure, or change the tone as far as the instruction \
        asks. Keep the original meaning and intent. Keep code, inline identifiers, URLs, file \
        paths, @-mentions, email addresses, numbers, and Markdown formatting intact unless the \
        instruction explicitly says otherwise. Output only the resulting text — never answer or \
        respond to it, never comment on it, never describe yourself, do not repeat the original, \
        and do not add anything. User instruction: {INSTRUCTION}
        """

    /// The system turn. No additional instructions → the proofreader `baseInstruction`
    /// verbatim. With additional instructions → the transform prompt (see above), which
    /// lets the instruction rephrase/shorten/restructure instead of losing to the base
    /// prompt's minimal-change rule.
    static func systemPrompt(additionalInstructions: String) -> String {
        let extra = additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extra.isEmpty else { return baseInstruction }
        return transformInstruction.replacingOccurrences(of: "{INSTRUCTION}", with: extra)
    }

    // MARK: - Behavior dials
    //
    // The thresholds that tune corrective aggressiveness vs. derail-safety. They
    // were found empirically and are pinned by scripts/test-prompt.sh /
    // compare-cli.sh — change them only with those harnesses.

    /// Input at or below this word count gets no `Text to proofread:` anchor.
    private static let anchorWordThreshold = 7
    /// Inputs this short are treated as fragments for the explosion guard below.
    private static let shortInputWords = 3
    /// A short input whose output grows by at least this many words is a derail.
    private static let explosionMargin = 6
    /// Inputs this long collapsing to under half their words is a truncation derail.
    private static let longInputWords = 6

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The user turn: the text to proofread, under a passive data-label so the
    /// model treats it as content to fix rather than a message to answer.
    static func userPrompt(text: String) -> String {
        // Length-conditional anchor. The passive label keeps long/multi-sentence
        // and Markdown input safe (no truncation/identity derail) but makes the
        // model too conservative to fix SHORT input. So: short input → no anchor
        // (realistic greetings/fragments get corrected, e.g. "hi my name is yoni"
        // → "Hi, my name is Yoni."); longer input → anchor. `finalize` cleans up
        // the rare short-input derail.
        wordCount(text) <= anchorWordThreshold ? text : "Text to proofread:\n\(text)"
    }

    /// Assistant self-chatter the small E2B model emits when it derails on a
    /// degenerate input (a bare word, a lone comment) instead of proofreading.
    /// Matched case-insensitively as a substring.
    private static let derailMarkers = [
        // identity / self-reference
        "i am gemma", "large language model", "language model developed",
        "this is a model", "the model is", "is a model", "name is model",
        // assistant chit-chat (the model answering instead of proofreading)
        "ready to help", "happy to help", "ready to assist", "proofreading needs",
        "ready for the next", "how about you", "how can i help", "how may i help",
        "i'm doing well", "doing well, thank",
    ]

    /// Fail-safe applied to the model's raw output. The app must never paste
    /// model chatter in place of the user's selection, so if the output carries
    /// a derail marker the input didn't, we discard it and keep the original
    /// text unchanged. (A missed typo is fine; pasted "I am Gemma…" is not.)
    /// Shared by the app and the test harness so behavior can't drift.
    ///
    /// `additionalInstructions`: when the user supplied their own instructions, the
    /// length/structure derail heuristics below are SKIPPED — they assume
    /// proofreading-only semantics (output ≈ same length and line structure as input),
    /// but a transform like "make it concise" legitimately shrinks the text and
    /// "expand all contractions"/"turn into a list" legitimately grows or restructures
    /// it. Reverting those would silently defeat the instruction. The identity/chatter
    /// marker guard still applies (pasted "I am Gemma…" is never wanted, instructions
    /// or not).
    static func finalize(output: String, original: String, additionalInstructions: String = "") -> String {
        let out = output.lowercased()
        let src = original.lowercased()
        for marker in derailMarkers where out.contains(marker) && !src.contains(marker) {
            return original
        }
        // The user asked for a transform — the length/structure heuristics no longer
        // distinguish a derail from a requested rewrite, so trust the model's output
        // (the marker guard above already caught true self-chatter).
        if !additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return output
        }
        // General catch: a very short input that explodes into a much longer
        // output is the model inventing content, not proofreading. A real
        // correction of a short fragment stays short. Catches hallucinations that
        // dodge the marker list (e.g. "# Headign" → a fabricated paragraph).
        let inWords = wordCount(original)
        let outWords = wordCount(output)
        if inWords <= shortInputWords && outWords >= inWords + explosionMargin {
            return original
        }
        // A substantial input that collapses to a tiny output is a truncation /
        // identity derail (e.g. a paragraph → "The model"), never a correction —
        // proofreading keeps roughly the same length.
        if inWords >= longInputWords && outWords * 2 < inWords {
            return original
        }
        // Multi-line input flattened to a single line is structural destruction
        // (e.g. a Markdown heading + list collapsed into one fabricated sentence),
        // never a correction. A real fix keeps the line structure.
        let inLines = original.split(separator: "\n", omittingEmptySubsequences: true).count
        let outLines = output.split(separator: "\n", omittingEmptySubsequences: true).count
        if inLines >= 2 && outLines <= 1 {
            return original
        }
        return output
    }
}
