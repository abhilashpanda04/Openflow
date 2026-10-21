import XCTest
@testable import OpenflowMac

final class AppleIntelligenceTests: XCTestCase {
    private var engine: AppleIntelligenceEngine!

    override func setUp() {
        super.setUp()
        engine = AppleIntelligenceEngine.shared
    }

    func testProofreadFixesApostrophesAndGrammar() {
        let input = "we is happy and they dont want to wait . he have a car ."
        let output = engine.proofread(text: input)

        // Grammar corrections
        XCTAssertTrue(output.lowercased().contains("we are"), "Expected 'we are' replacement")
        XCTAssertTrue(output.contains("don't"), "Expected 'don't' with apostrophe")
        XCTAssertTrue(output.lowercased().contains("he has"), "Expected 'he has' replacement")
        XCTAssertFalse(output.contains("wait ."), "Expected trailing punctuation space cleaned")
    }

    func testProofreadSentenceCapitalizationAndPunctuation() {
        let input = "hello world"
        let output = engine.proofread(text: input)
        XCTAssertEqual(output, "Hello world.")
    }

    func testRewriteProfessionalExpandsContractionsAndElevatesVocab() {
        let input = "we can't fix this huge problem gonna help them"
        let output = engine.rewriteProfessional(text: input)

        XCTAssertTrue(output.contains("cannot"), "Expected contraction expansion to cannot")
        XCTAssertTrue(output.contains("resolve"), "Expected fix -> resolve")
        XCTAssertTrue(output.contains("significant"), "Expected huge -> significant")
        XCTAssertTrue(output.contains("assist"), "Expected help -> assist")
    }

    func testRewriteFriendlyAddsWarmth() {
        let input = "Dear Sir or Madam, I am writing to inform you that we cannot attend. Sincerely"
        let output = engine.rewriteFriendly(text: input)

        XCTAssertTrue(output.contains("Hello,") || output.contains("Hi"), "Expected warm greeting")
        XCTAssertTrue(output.contains("can't"), "Expected natural contraction can't")
        XCTAssertTrue(output.contains("Warmly,") || output.contains("Best,"), "Expected warm sign-off")
    }

    func testRewriteConciseStripsFluff() {
        let input = "In order to succeed at the present time, basically we need to literally take into consideration the results."
        let output = engine.rewriteConcise(text: input)

        XCTAssertFalse(output.lowercased().contains("in order to"))
        XCTAssertFalse(output.lowercased().contains("at the present time"))
        XCTAssertFalse(output.lowercased().contains("basically"))
        XCTAssertFalse(output.lowercased().contains("literally"))
        XCTAssertTrue(output.lowercased().contains("consider"))
    }

    func testSummarizeKeyPointsFormatsBullets() {
        let input = "First of all Openflow is fast. Additionally it runs on-device. Furthermore it supports voice commands."
        let output = engine.summarizeKeyPoints(text: input)

        let lines = output.components(separatedBy: .newlines)
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("• ") })
    }

    func testSummarizeTableFormatsMarkdown() {
        let input = "Latency: 25ms\nAccuracy: 99.4%\nFootprint: 40MB"
        let output = engine.summarizeTable(text: input)

        XCTAssertTrue(output.contains("| Item | Details |"))
        XCTAssertTrue(output.contains("| Latency | 25ms |"))
        XCTAssertTrue(output.contains("| Accuracy | 99.4% |"))
        XCTAssertTrue(output.contains("| Footprint | 40MB |"))
    }

    func testExplainGeneratesOverviewAndDetails() {
        let input = "Voice activity detection measures audio power to stop recording automatically."
        let output = engine.explain(text: input)

        XCTAssertTrue(output.contains("**Overview:**"))
        XCTAssertTrue(output.contains("**Key Details:**"))
    }

    func testCustomPromptEmailDrafting() {
        let prompt = "draft an email thanking the design team for the mockups"
        let output = engine.handleCustomPrompt(prompt: prompt, text: nil)

        XCTAssertTrue(output.contains("Hi,"))
        XCTAssertTrue(output.contains("Best regards,"))
    }

    func testAsyncExecutionReturnsTextReplaced() async {
        let cmd = AppleIntelligenceCommand(style: .rewriteConcise, targetText: "In order to test this system")
        let result = await engine.execute(command: cmd)

        guard case .textReplaced(let transformed, let style) = result else {
            return XCTFail("Expected textReplaced result")
        }
        XCTAssertEqual(style, .rewriteConcise)
        XCTAssertFalse(transformed.lowercased().contains("in order to"))
    }

    func testAsyncExecutionWithoutTextReturnsError() async {
        let cmd = AppleIntelligenceCommand(style: .rewriteConcise, targetText: nil)
        let result = await engine.execute(command: cmd)

        guard case .error(let msg) = result else {
            return XCTFail("Expected error result")
        }
        XCTAssertTrue(msg.contains("No text provided"))
    }
}
