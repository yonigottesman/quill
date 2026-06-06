// Comparison harness: for each test input, runs the REAL Swift inference path
// (PromptBuilder + LlamaContext, same as the app) and writes two files per case
// into the output dir given as argv[1]:
//   case_<n>.user  — the exact user-turn content the app feeds the model
//   case_<n>.raw   — the RAW model output (pre-finalize)
//   case_<n>.sys   — the exact system-turn content
// scripts/compare-cli.sh then feeds the SAME system+user to `llama cli` (greedy,
// reasoning off) and diffs the outputs. Raw (pre-finalize) is compared so we test
// template/sampling alignment, not the app-only finalize fail-safe.
import Foundation

struct Case { let text: String; let additional: String
    init(_ t: String, additional a: String = "") { text = t; additional = a } }

@main
struct CompareHarness {
    static let plain: [String] = [
        "sure no promblem",
        "thanks alot for the help",
        "i recieved your mesage",
        "see you tommorow",
        "definately",
        "acommodate",
        "i has went too the stor yesterday and buyed sum apples.",
        "she dont know what she want for her birhtday.",
        "their going too the park but its to cold outsid today.",
        "we was hopping you could join us for diner on thursday.",
        "the quaterly reprot is due monday and the metrics looks wrong.",
        "can you reveiw my PR befor the standup tommorrow pls.",
        "hi my name is yoni",
        "whats up how are you",
        "i think i'll go home now becuase i'm tired.",
        "we shipped it. i'll monitor the erors and let you know.",
        "hello there. how are you doing today.",
        "The meeting is scheduled for 3 PM on Tuesday.",
        "I think we should ship the feature behind a flag and monitor errors.",
        "we deployed teh new versoin too AWS and the latancy droped.",
        "im learnig SwiftUI and i keep confusin @State and @Binding.",
        "the api retuns a 401 wen the jwt is expird.",
        "first we need to fix the login bug, then refactor the netwoking layer, and finaly write tests for the parser. dont forget to update the docs aswell.",
        "i went to the store. i bought milk, egss, and bred. then i drove home and relized i forgot the coffe.",
        "this is **bold** and *italic* text with a tpyo in it.",
        "use the `fetchData()` functon to get the curent user.",
        "see [the docs](https://example.com/guide) for moar info.",
        "// this functoin retuns the user id from the databse",
        "cost is $50 (50% off!) — limited time, e.g. today & tommorow.",
        "email me at jon@example.com — i'll reespond asap.",
        // multi-line / Markdown (riskiest for template + line-break alignment)
        "# Headign\n- frist item\n- secnd item with a typo",
        "first we need to fix the login bug, then refactor the netwoking layer, and finaly write tests for the parser. dont forget to update the docs aswell.",
        "i went to the store. i bought milk, egss, and bred. then i drove home and relized i forgot the coffe.",
        "/* TODO: fix the of-by-one eror in the loop bellow */",
        "she said \"its fine\" but its not realy fine.",
    ]

    // Cases that also exercise the Settings "additional instructions" (changes the system turn).
    static let withAdditional: [Case] = [
        Case("I love the color gray and my favorite flavor is vanilla.", additional: "use British spelling"),
        Case("This Sentence Has Wierd Capitalizaton and a typo.", additional: "make the whole output lowercase"),
        Case("hey, can u send me teh report when your free?", additional: "make it formal"),
        Case("the meetign is at 2pm. bring the laptop. we will demo the prototype.", additional: "start every fix with the word FIX"),
    ]

    static var cases: [Case] { plain.map { Case($0) } + withAdditional }

    static func main() async throws {
        let outDir = CommandLine.arguments[1]
        let path = try ModelLocator.resolveGGUF()
        FileHandle.standardError.write("Model: \(path)\n".data(using: .utf8)!)
        let ctx = try LlamaContext.create(modelPath: path)
        for (i, c) in cases.enumerated() {
            let system = PromptBuilder.systemPrompt(additionalInstructions: c.additional)
            let user = PromptBuilder.userPrompt(text: c.text)
            let raw = await ctx.generate(system: system, user: user)
            try system.write(toFile: "\(outDir)/case_\(i).sys", atomically: true, encoding: .utf8)
            try user.write(toFile: "\(outDir)/case_\(i).user", atomically: true, encoding: .utf8)
            try raw.write(toFile: "\(outDir)/case_\(i).raw", atomically: true, encoding: .utf8)
            FileHandle.standardError.write("case \(i) done\n".data(using: .utf8)!)
        }
        print("WROTE \(cases.count) cases to \(outDir)")
        fflush(stdout)
        _exit(0)
    }
}
