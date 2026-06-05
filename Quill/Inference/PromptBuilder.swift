import Foundation

/// Builds the user-turn prompt. Shared by the app and the test harness so they
/// never drift. The Gemma chat template is applied later in LlamaContext.
enum PromptBuilder {
    static let baseInstruction = """
        Proofread the text below. Fix every spelling mistake, typo, and grammar error. Reply with \
        only the single corrected version of the text — do not repeat the original, do not explain, \
        do not add anything. Keep the original meaning, tone, and wording where possible.
        """

    static func build(text: String, additionalInstructions: String) -> String {
        var prompt = baseInstruction
        let extra = additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            prompt += "\nAdditional instructions: \(extra)"
        }
        prompt += "\n\n" + text
        return prompt
    }
}
