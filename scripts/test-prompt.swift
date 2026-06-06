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
            // --- short fragments (echo regression: must fix, not repeat original) ---
            TestCase("sure no promblem"),
            TestCase("sure, no promblem."),
            TestCase("That is not a promblem at all."),
            TestCase("thanks alot for the help"),
            TestCase("i recieved your mesage"),
            TestCase("see you tommorow"),
            TestCase("ok"),
            TestCase("definately"),
            TestCase(" palta"),                       // not a typo (Spanish): should pass through unchanged
            TestCase("acommodate"),

            // --- plain grammar/typo fixes (no additional instructions) ---
            TestCase("i has went too the stor yesterday and buyed sum apples."),
            TestCase("she dont know what she want for her birhtday."),
            TestCase("their going too the park but its to cold outsid today."),
            TestCase("we was hopping you could join us for diner on thursday."),
            TestCase("the quaterly reprot is due monday and the metrics looks wrong."),
            TestCase("can you reveiw my PR befor the standup tommorrow pls."),

            // --- merged words / names / greetings ---
            TestCase("himy name is yoni"),
            TestCase("hi my name is yoni"),
            TestCase("helloworld this is a testfor you"),
            TestCase("whats up how are you"),

            // --- capitalization (sentence start, "I" and its contractions) ---
            TestCase("i think i'll go home now becuase i'm tired."),
            TestCase("we shipped it. i'll monitor the erors and let you know."),
            TestCase("i've been testing this for hours. i dont know whats wrong."),
            TestCase("hello there. how are you doing today."),

            // --- already-correct text (must come back UNCHANGED, not "improved"/reworded) ---
            TestCase("The meeting is scheduled for 3 PM on Tuesday."),
            TestCase("Please review the attached document and let me know your thoughts."),
            TestCase("I think we should ship the feature behind a flag and monitor errors."),

            // --- proper nouns / technical terms (must be preserved, not normalized away) ---
            TestCase("we deployed teh new versoin too AWS and the latancy droped."),
            TestCase("im learnig SwiftUI and i keep confusin @State and @Binding."),
            TestCase("the api retuns a 401 wen the jwt is expird."),

            // --- CONTENT-PRESERVATION (the reported bug): every sentence/clause must survive,
            //     nothing summarized, merged, or dropped ---
            TestCase("go over this app and evalu how good its built the architecture and the abstractions. I want something really simple and robust. should have swift best practices while being simple and minimalist."),
            TestCase("first we need to fix the login bug, then refactor the netwoking layer, and finaly write tests for the parser. dont forget to update the docs aswell."),
            TestCase("i went to the store. i bought milk, egss, and bred. then i drove home and relized i forgot the coffe."),
            TestCase("the app is slow on launch becuase it loads the modle synchronously. we should load it lazily. also the menu bar icon flickres sometimes which is anoying."),
            TestCase("hey just checking in — did you get a chance to look at the design? i left some comments on figma. lmk if anythng is unclear and we can hop on a call."),

            // --- mixed: long, messy, informal but every point must remain ---
            TestCase("so the plan is: ship the mvp by friday, get feedbak from 5 users over the weekend, and itterate next week. if the feedbak is bad we pivot. sound good?"),

            // --- Markdown must be preserved (fix typos, keep **/*/`/#/-/[](…) intact) ---
            TestCase("this is **bold** and *italic* text with a tpyo in it."),
            TestCase("use the `fetchData()` functon to get the curent user."),
            TestCase("# Headign\n- frist item\n- secnd item with a typo"),
            TestCase("see [the docs](https://example.com/guide) for moar info."),
            TestCase("> quoted advise: allways backup you're databse first."),

            // --- code & comments must be preserved verbatim (fix prose typos only) ---
            TestCase("// this functoin retuns the user id from the databse"),
            TestCase("/* TODO: fix the of-by-one eror in the loop bellow */"),
            TestCase("let x = computeValue(a, b)  // calcualtes the totl"),

            // --- special characters / punctuation / emoji preserved ---
            TestCase("cost is $50 (50% off!) — limited time, e.g. today & tommorow."),
            TestCase("great work on the launch 🎉 see you tommorow!"),
            TestCase("she said \"its fine\" but its not realy fine."),
            TestCase("the file lives at /usr/local/bin/quill and teh script faild."),
            TestCase("email me at jon@example.com — i'll reespond asap."),

            // --- short slack/chat: speed-typing typos, missing apostrophes, common grammar ---
            //     (Quill's bread-and-butter: quick messages fired off fast. All single-line so they
            //      stay on the "no anchor" side of the length dial and are safe for CLI alignment.)
            TestCase("dont worry ill take care of it"),
            TestCase("i cant make it today lets reschedule"),
            TestCase("youre right i didnt notice that"),
            TestCase("thats not what i ment but its fine"),
            TestCase("wont be able to join im in a meeting"),
            TestCase("can you snd me teh link adn ill review it"),
            TestCase("i thnik we shoud merge this"),
            TestCase("waht time is the meetign tonight"),
            TestCase("yeah thats fine wiht me lets do it"),
            TestCase("im on my way runing 5 min late"),
            TestCase("did yuo see the mesage i sent you"),
            TestCase("sounds good ill ping yuo wehn its done"),
            TestCase("i should of tested it first"),                 // should of → should have
            TestCase("this dont work on my machine"),                // dont → doesn't (3rd person)
            TestCase("the tests was failing on ci"),                 // was → were; ci → CI
            TestCase("thanks fir the hekp realy apreciate it"),      // fat-finger fir/hekp
            TestCase("wprking on it now will updaet you soon"),      // adjacent-key wprking/updaet
            TestCase("lmk wen your free to chat"),                   // your → you're
            TestCase("hes alredy on it dont worry"),
            TestCase("we shoud probly ship it tomorow"),
            TestCase("i havent finished it yet sory"),
            TestCase("are we still on for lunch tmrw"),              // tmrw → tomorrow
            TestCase("no wories take you'r time"),                   // you'r → your
            TestCase("i'll be their in 5"),                          // their → there
            TestCase("lets sync up after lunch"),
            TestCase("whos handling the deploy today"),
            TestCase("pls reveiw when you get a sec"),
            TestCase("i seen the email but havnt replyed"),          // seen → saw; havnt → haven't
            TestCase("their is a few bugs left"),                    // their → there; is → are
            TestCase("each of the files need review"),               // need → needs
            TestCase("could of been worse"),                         // could of → could have
            TestCase("your the best thanks again"),                 // your → you're
            TestCase("its been a long day hows it going"),
            TestCase("me and tom is working on it"),                 // subject case + agreement

            // --- with additional instructions (should be honored, content still preserved) ---
            TestCase("I love the color gray and my favorite flavor is vanilla.",
                     additional: "use British spelling"),
            TestCase("This Sentence Has Wierd Capitalizaton and a typo.",
                     additional: "make the whole output lowercase"),
            TestCase("hey, can u send me teh report when your free?",
                     additional: "make it formal"),
            TestCase("we shipped the featur but their are still som bugs in the edge cases.",
                     additional: "use American spelling and keep it casual"),
            TestCase("the meetign is at 2pm. bring the laptop. we will demo the prototype.",
                     additional: "start every fix with the word FIX"),

            // --- more additional instructions: tone/format transforms layered on proofreading.
            //     Each input carries real typos so the proofreading core still has work to do,
            //     and the instruction tests that the system turn steers the output. NOTE: the
            //     "shorter/concise" ones deliberately shrink text — watched against finalize's
            //     collapse guard (a correct concise rewrite must not be reverted to the original).
            TestCase("the meetign is at 2pm and i'll bring the laptop",
                     additional: "dont capitalize"),
            TestCase("i just wanted to quickly reach out and let you know the reprot will be a litle late",
                     additional: "make it shorter and more clear and concise"),
            TestCase("send me teh file now its urgrent",
                     additional: "make it more polite"),
            TestCase("hey can u fix this bug its totaly broken and im freaking out",
                     additional: "make it sound more professional"),
            TestCase("i'll be there when im done so dont wait up",
                     additional: "expand all contractions"),
            TestCase("pls reveiw the doc and snd me your feedbak by eod",
                     additional: "make it more concise"),
        ]

        let path = try ModelLocator.resolveGGUF()
        FileHandle.standardError.write("Model: \(path)\n\n".data(using: .utf8)!)

        let ctx = try LlamaContext.create(modelPath: path)
        for c in cases {
            let system = PromptBuilder.systemPrompt(additionalInstructions: c.additional)
            let raw = await ctx.generate(system: system, user: PromptBuilder.userPrompt(text: c.text))
            let out = PromptBuilder.finalize(output: raw, original: c.text, additionalInstructions: c.additional) // same fail-safe as the app
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
