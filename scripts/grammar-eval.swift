// Proofreading regression test. A big list of (input → expected corrected output)
// pairs. It runs each input through the real app path (PromptBuilder +
// LlamaContext), compares the model's output to the expected string, counts how
// many match, and prints the ones that DON'T (input / expected / got) so you can
// eyeball whether a mismatch is a real regression or just a different valid
// phrasing. Greedy sampling is deterministic, so the count is exact and repeatable.
//
// Use it to tell if a model swap / template / sampling change made proofreading
// worse: a healthy model scores at/near the baseline; a worse one drops and the
// mismatch list shows exactly what broke.
//
// To add cases: append (input, expected) where `expected` is the correct proofread
// output you want. Build & run via scripts/grammar-eval.sh.
import Foundation

typealias Case = (input: String, expected: String)

let cases: [Case] = [
    // --- agreement ---
    ("this dont work on my machine",            "This doesn't work on my machine."),
    ("the tests was failing on ci",             "The tests were failing on CI."),
    ("their is a few bugs left",                "There are a few bugs left."),
    ("each of the files need review",           "Each of the files needs review."),
    ("me and tom is working on it",             "Tom and I are working on it."),
    ("she dont know what she wants",            "She doesn't know what she wants."),

    // --- tense ---
    ("i buyed sum apples at the stor",          "I bought some apples at the store."),
    ("i seen the email this morning",           "I saw the email this morning."),
    ("i should of tested it first",             "I should have tested it first."),
    ("that could of been worse honestly",       "That could have been worse, honestly."),
    ("i drived home after the party",           "I drove home after the party."),

    // --- homophones / possessives ---
    ("your the best thanks again",              "You're the best, thanks again."),
    ("youre right i missed that",               "You're right, I missed that."),
    ("i'll be their in five minutes",           "I'll be there in five minutes."),
    ("no wories take you'r time",               "No worries, take your time."),
    ("its been a long day today",               "It's been a long day today."),
    ("lmk wen your free to chat",               "Let me know when you're free to chat."),
    ("the dog wagged it's tail",                "The dog wagged its tail."),

    // --- spelling ---
    ("i recieved your mesage",                  "I received your message."),
    ("ill definately be there",                 "I'll definitely be there."),
    ("see you tommorow morning",                "See you tomorrow morning."),
    ("thanks alot for the help",                "Thanks a lot for the help."),
    ("we can acommodate the request",           "We can accommodate the request."),
    ("we deployed teh new versoin",             "We deployed the new version."),
    ("the latancy droped after the fix",        "The latency dropped after the fix."),
    ("can you reveiw the reprot please",        "Can you review the report, please?"),

    // --- capitalization ---
    ("i think we should merge this",            "I think we should merge this."),
    ("hello there. how are you",                "Hello there. How are you?"),
    ("we shipped it. i'll monitor the erors",   "We shipped it. I'll monitor the errors."),

    // --- contractions ---
    ("i cant make it today",                    "I can't make it today."),
    ("wont be able to join sorry",              "Won't be able to join, sorry."),
    ("i havent finished it yet",                "I haven't finished it yet."),
    ("i dont know whats wrong",                 "I don't know what's wrong."),

    // --- short slack/chat ---
    ("dont worry ill take care of it",          "Don't worry, I'll take care of it."),
    ("i cant make it today lets reschedule",    "I can't make it today. Let's reschedule."),
    ("youre right i didnt notice that",         "You're right, I didn't notice that."),
    ("can you snd me teh link adn ill review it","Can you send me the link, and I'll review it?"),
    ("i thnik we shoud merge this",             "I think we should merge this."),
    ("waht time is the meetign tonight",        "What time is the meeting tonight?"),
    ("are we still on for lunch tmrw",          "Are we still on for lunch tomorrow?"),
    ("pls reveiw when you get a sec",           "Please review when you get a sec."),
    ("hes alredy on it dont worry",             "He's already on it, don't worry."),
    ("we shoud probly ship it tomorow",         "We should probably ship it tomorrow."),

    // --- technical / proper nouns preserved ---
    ("im learnig SwiftUI and i keep confusin @State and @Binding.",
     "I'm learning SwiftUI and I keep confusing @State and @Binding."),
    ("the api retuns a 401 wen the jwt is expird.",
     "The API returns a 401 when the JWT is expired."),
    ("we deployed teh new versoin too AWS and the latancy droped.",
     "We deployed the new version to AWS and the latency dropped."),

    // --- markdown preserved ---
    ("this is **bold** and *italic* text with a tpyo in it.",
     "This is **bold** and *italic* text with a typo in it."),
    ("use the `fetchData()` functon to get the curent user.",
     "Use the `fetchData()` function to get the current user."),

    // --- already correct: must come back UNCHANGED ---
    ("The meeting is scheduled for 3 PM on Tuesday.",
     "The meeting is scheduled for 3 PM on Tuesday."),
    ("Please review the attached document and let me know your thoughts.",
     "Please review the attached document and let me know your thoughts."),
    ("I think we should ship the feature behind a flag and monitor errors.",
     "I think we should ship the feature behind a flag and monitor errors."),
]

@main
struct GrammarEval {
    static func main() async throws {
        let path = try ModelLocator.resolveGGUF()
        FileHandle.standardError.write("Model: \(path)\n\n".data(using: .utf8)!)
        let ctx = try LlamaContext.create(modelPath: path)
        let system = PromptBuilder.systemPrompt(additionalInstructions: "")

        var correct = 0
        var mismatches: [(Case, String)] = []
        for c in cases {
            let raw = await ctx.generate(system: system, user: PromptBuilder.userPrompt(text: c.input))
            let got = PromptBuilder.finalize(output: raw, original: c.input, additionalInstructions: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if got == c.expected.trimmingCharacters(in: .whitespacesAndNewlines) { correct += 1 }
            else { mismatches.append((c, got)) }
        }

        if !mismatches.isEmpty {
            print("──────────────── MISMATCHES (\(mismatches.count)) ────────────────")
            for (c, got) in mismatches {
                print("INPUT:    \(c.input)")
                print("EXPECTED: \(c.expected)")
                print("GOT:      \(got)")
                print("")
            }
        }
        print("════════════════════════════════════════════════════════")
        print("CORRECT \(correct)/\(cases.count)  (\(String(format: "%.1f", Double(correct) / Double(cases.count) * 100))%)")
        print("════════════════════════════════════════════════════════")

        fflush(stdout)
        _exit(0) // _exit skips the benign ggml/Metal teardown SIGABRT
    }
}
