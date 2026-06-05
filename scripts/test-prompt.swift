// Standalone harness: runs short typo-filled texts through the real prompt
// (PromptBuilder + LlamaContext) and prints before/after. Also exercises
// additional instructions. Build & run via scripts/test-prompt.sh.
import Foundation

struct TestCase {
    let text: String
    let additional: String
    init(_ text: String, additional: String = "") { self.text = text; self.additional = additional }
}

@main
struct TestPrompt {
    static func main() async throws {
        let cases = [
            // --- short fragments (reported failing) ---
            TestCase("sure no promblem"),
            TestCase("sure, no promblem."),
            TestCase("That is not a promblem at all."),
            TestCase("thanks alot for the help"),
            TestCase("i recieved your mesage"),
            TestCase("see you tommorow"),

            // --- plain grammar/typo fixes (no additional instructions) ---
            TestCase("i has went too the stor yesterday and buyed sum apples."),
            TestCase("she dont know what she want for her birhtday."),
            TestCase("their going too the park but its to cold outsid today."),
            TestCase("we was hopping you could join us for diner on thursday."),

            // --- with additional instructions (should be honored) ---
            TestCase("I love the color gray and my favorite flavor is vanilla.",
                     additional: "use British spelling"),
            TestCase("This Sentence Has Wierd Capitalizaton and a typo.",
                     additional: "make the whole output lowercase"),
            TestCase("hey, can u send me teh report when your free?",
                     additional: "make it formal"),
        ]

        let path = try ModelLocator.resolveGGUF()
        FileHandle.standardError.write("Model: \(path)\n\n".data(using: .utf8)!)

        let ctx = try LlamaContext.create(modelPath: path)
        for c in cases {
            let prompt = PromptBuilder.build(text: c.text, additionalInstructions: c.additional)
            let out = await ctx.generate(prompt: prompt)
            print("────────────────────────────────────────")
            print("INPUT:      \(c.text)")
            if !c.additional.isEmpty { print("ADDITIONAL: \(c.additional)") }
            print("OUTPUT:     \(out)")
        }
        print("────────────────────────────────────────")
        fflush(stdout) // _exit doesn't flush stdio buffers
        _exit(0)       // skip C++ static teardown (avoids the benign ggml/Metal SIGABRT)
    }
}
