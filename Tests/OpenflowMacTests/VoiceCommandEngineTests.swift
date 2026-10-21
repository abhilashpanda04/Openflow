import XCTest
@testable import OpenflowMac

final class VoiceCommandEngineTests: XCTestCase {
    private var engine: VoiceCommandEngine!

    override func setUp() {
        super.setUp()
        engine = VoiceCommandEngine(isEnabled: true)
    }

    func testStandaloneActions() {
        XCTAssertEqual(engine.process(rawTranscript: "select all"), .systemAction(.selectAll))
        XCTAssertEqual(engine.process(rawTranscript: "Select Everything"), .systemAction(.selectAll))
        XCTAssertEqual(engine.process(rawTranscript: "Please select all."), .systemAction(.selectAll))
        XCTAssertEqual(engine.process(rawTranscript: "undo"), .systemAction(.undo))
        XCTAssertEqual(engine.process(rawTranscript: "undo that!"), .systemAction(.undo))
        XCTAssertEqual(engine.process(rawTranscript: "Undo."), .systemAction(.undo))
        XCTAssertEqual(engine.process(rawTranscript: "redo that"), .systemAction(.redo))
        XCTAssertEqual(engine.process(rawTranscript: "paste that"), .systemAction(.paste))
        XCTAssertEqual(engine.process(rawTranscript: "save file"), .systemAction(.save))
        XCTAssertEqual(engine.process(rawTranscript: "delete line"), .systemAction(.deleteLine))
        XCTAssertEqual(engine.process(rawTranscript: "delete that"), .systemAction(.delete))
        XCTAssertEqual(engine.process(rawTranscript: "copy that"), .systemAction(.copy))
        XCTAssertEqual(engine.process(rawTranscript: "cut that"), .systemAction(.cut))
        XCTAssertEqual(engine.process(rawTranscript: "new line"), .systemAction(.newLine))
        XCTAssertEqual(engine.process(rawTranscript: "new paragraph"), .systemAction(.newParagraph))
    }

    func testSelectionEditWithoutSelection() {
        XCTAssertEqual(
            engine.process(rawTranscript: "make this shorter"),
            .selectionEditRequestedWithoutSelection(description: "Make Shorter")
        )
    }

    func testScratchThatDiscardsDictation() {
        XCTAssertEqual(engine.process(rawTranscript: "scratch that"), .discarded)
        XCTAssertEqual(engine.process(rawTranscript: "never mind"), .discarded)
        XCTAssertEqual(engine.process(rawTranscript: "cancel that"), .discarded)
    }

    func testInlineScratchThatDropsPriorText() {
        let input = "Hey Alice I have an email. Scratch that, this email is for Jordan."
        let result = engine.process(rawTranscript: input)
        guard case .processedText(let text) = result else {
            return XCTFail("Expected processedText")
        }
        XCTAssertEqual(text, "this email is for Jordan.")
    }

    func testInlineSelfCorrectionReplacesMistake() {
        let input = "send it to John, no, Mary"
        let result = engine.process(rawTranscript: input)
        guard case .processedText(let text) = result else {
            return XCTFail("Expected processedText")
        }
        XCTAssertEqual(text, "send it to Mary")

        let input2 = "let's meet at six, actually seven pm"
        let result2 = engine.process(rawTranscript: input2)
        guard case .processedText(let text2) = result2 else {
            return XCTFail("Expected processedText")
        }
        XCTAssertEqual(text2, "let's meet at seven pm")
    }

    func testInlineNavigationCommands() {
        let input = "first point new line second point new paragraph next section"
        let result = engine.process(rawTranscript: input)
        guard case .processedText(let text) = result else {
            return XCTFail("Expected processedText")
        }
        XCTAssertEqual(text, "first point\nsecond point\n\nnext section")
    }

    func testInlineCaseCommands() {
        let input = "make this urgent uppercase that please"
        let result = engine.process(rawTranscript: input)
        guard case .processedText(let text) = result else {
            return XCTFail("Expected processedText")
        }
        XCTAssertEqual(text, "make this URGENT please")
    }

    func testSelectionEdits() {
        let selected = "hello world"
        XCTAssertEqual(
            engine.process(rawTranscript: "all caps", selectedText: selected),
            .selectionEdit(transformed: "HELLO WORLD", description: "All Caps / Uppercase")
        )

        let bulletInput = "Apple\nBanana\nOrange"
        XCTAssertEqual(
            engine.process(rawTranscript: "bullet points", selectedText: bulletInput),
            .selectionEdit(transformed: "• Apple\n• Banana\n• Orange", description: "Turn into Bullet Points")
        )
    }

    func testDisabledEnginePassesThrough() {
        let disabled = VoiceCommandEngine(isEnabled: false)
        XCTAssertEqual(disabled.process(rawTranscript: "select all"), .processedText("select all"))
    }

    func testAppleIntelligenceCommandRecognition() {
        let selected = "We is ready to start."

        // Writing Tools launcher
        let wtResult = engine.process(rawTranscript: "show writing tools", selectedText: selected)
        guard case .appleIntelligence(let cmd1) = wtResult else {
            return XCTFail("Expected appleIntelligence result")
        }
        XCTAssertEqual(cmd1.style, .showWritingTools)

        // Proofread
        let proofResult = engine.process(rawTranscript: "apple intelligence proofread", selectedText: selected)
        guard case .appleIntelligence(let cmd2) = proofResult else {
            return XCTFail("Expected appleIntelligence proofread")
        }
        XCTAssertEqual(cmd2.style, .proofread)
        XCTAssertEqual(cmd2.targetText, selected)

        // Rewrite Professional
        let profResult = engine.process(rawTranscript: "rewrite this professionally", selectedText: selected)
        guard case .appleIntelligence(let cmd3) = profResult else {
            return XCTFail("Expected appleIntelligence rewriteProfessional")
        }
        XCTAssertEqual(cmd3.style, .rewriteProfessional)

        // Rewrite Friendly
        let friendResult = engine.process(rawTranscript: "apple intelligence rewrite friendly", selectedText: selected)
        guard case .appleIntelligence(let cmd4) = friendResult else {
            return XCTFail("Expected appleIntelligence rewriteFriendly")
        }
        XCTAssertEqual(cmd4.style, .rewriteFriendly)

        // Rewrite Concise
        let conciseResult = engine.process(rawTranscript: "make this concise", selectedText: selected)
        guard case .appleIntelligence(let cmd5) = conciseResult else {
            return XCTFail("Expected appleIntelligence rewriteConcise")
        }
        XCTAssertEqual(cmd5.style, .rewriteConcise)

        // Summarize Key Points
        let kpResult = engine.process(rawTranscript: "summarize into key points", selectedText: selected)
        guard case .appleIntelligence(let cmd6) = kpResult else {
            return XCTFail("Expected appleIntelligence summarizeKeyPoints")
        }
        XCTAssertEqual(cmd6.style, .summarizeKeyPoints)

        // Summarize Table
        let tableResult = engine.process(rawTranscript: "create a table", selectedText: selected)
        guard case .appleIntelligence(let cmd7) = tableResult else {
            return XCTFail("Expected appleIntelligence summarizeTable")
        }
        XCTAssertEqual(cmd7.style, .summarizeTable)

        // Explain
        let expResult = engine.process(rawTranscript: "explain this with apple intelligence", selectedText: selected)
        guard case .appleIntelligence(let cmd8) = expResult else {
            return XCTFail("Expected appleIntelligence explain")
        }
        XCTAssertEqual(cmd8.style, .explain)

        // Custom Prompt
        let customResult = engine.process(rawTranscript: "apple intelligence write a thank you note to Sarah", selectedText: nil)
        guard case .appleIntelligence(let cmd9) = customResult else {
            return XCTFail("Expected appleIntelligence customPrompt")
        }
        XCTAssertEqual(cmd9.style, .customPrompt)
        XCTAssertEqual(cmd9.prompt, "write a thank you note to Sarah")
    }

    func testAppleIntelligenceWithoutSelectionDemandsSelection() {
        let result = engine.process(rawTranscript: "apple intelligence proofread", selectedText: nil)
        XCTAssertEqual(result, .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Proofread)"))

        let result2 = engine.process(rawTranscript: "rewrite this professionally", selectedText: nil)
        XCTAssertEqual(result2, .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Rewrite Professional)"))
    }
}
