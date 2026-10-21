import XCTest
@testable import OpenflowMac

final class TypedTextFormatterTests: XCTestCase {

    func testDefaultConfigBehavior() {
        let formatter = TypedTextFormatter() // default: trailing space ON, capitalize ON, paragraph breaks ON
        let result = formatter.format("hello world. how are you?")
        XCTAssertEqual(result, "Hello world. How are you? ")
    }

    func testSpokenEmoji() {
        let config = TypedTextConfig(
            addTrailingSpace: false,
            capitalizeSentences: false,
            spokenEmoji: true
        )
        let formatter = TypedTextFormatter(config: config)

        let input = "Let's celebrate party emoji and fire emoji"
        let output = formatter.format(input)
        XCTAssertEqual(output, "Let's celebrate 🎉 and 🔥")

        let input2 = "Great job thumbs up emoji and heart emoji"
        let output2 = formatter.format(input2)
        XCTAssertEqual(output2, "Great job 👍 and ❤️")

        let input3 = "That's funny laughing emoji"
        let output3 = formatter.format(input3)
        XCTAssertEqual(output3, "That's funny 😂")
    }

    func testWriteNumbersAsDigits() {
        let config = TypedTextConfig(
            addTrailingSpace: false,
            capitalizeSentences: false,
            writeNumbersAsDigits: true
        )
        let formatter = TypedTextFormatter(config: config)

        XCTAssertEqual(formatter.format("the meeting is at six pm"), "the meeting is at 6 pm")
        XCTAssertEqual(formatter.format("call me at ten am"), "call me at 10 am")
        XCTAssertEqual(formatter.format("twenty-five people attended"), "25 people attended")
        XCTAssertEqual(formatter.format("twenty five people attended"), "25 people attended")
        XCTAssertEqual(formatter.format("there are one hundred items"), "there are 100 items")
    }

    func testSymbolsAndOrdinals() {
        let config = TypedTextConfig(
            addTrailingSpace: false,
            capitalizeSentences: false,
            writeNumbersAsDigits: true,
            useSymbolsAndOrdinals: true
        )
        let formatter = TypedTextFormatter(config: config)

        XCTAssertEqual(formatter.format("he finished in first place"), "he finished in 1st place")
        XCTAssertEqual(formatter.format("this is the second time"), "this is the 2nd time")
        XCTAssertEqual(formatter.format("the third option"), "the 3rd option")
        XCTAssertEqual(formatter.format("interest rate is fifty percent"), "interest rate is 50%")
        XCTAssertEqual(formatter.format("it costs twenty-five dollars"), "it costs $25")
        XCTAssertEqual(formatter.format("it is seventy-two degrees outside"), "it is 72° outside")
    }

    func testSymbolsAndOrdinalsIgnoredWhenWriteNumbersDisabled() {
        let config = TypedTextConfig(
            addTrailingSpace: false,
            capitalizeSentences: false,
            writeNumbersAsDigits: false,
            useSymbolsAndOrdinals: true
        )
        let formatter = TypedTextFormatter(config: config)

        // When writeNumbersAsDigits is false, useSymbolsAndOrdinals should not run
        XCTAssertEqual(formatter.format("he finished in first place"), "he finished in first place")
        XCTAssertEqual(formatter.format("fifty percent"), "fifty percent")
    }

    func testParagraphBreaks() {
        let config = TypedTextConfig(
            addTrailingSpace: false,
            capitalizeSentences: true,
            paragraphBreaks: true
        )
        let formatter = TypedTextFormatter(config: config)

        let input = "First section. New paragraph Second section. New line Next line."
        let output = formatter.format(input)
        XCTAssertEqual(output, "First section.\n\nSecond section.\nNext line.")

        let emailGreeting = "Hi Sarah, hope you are doing well."
        let emailOutput = formatter.format(emailGreeting)
        XCTAssertEqual(emailOutput, "Hi Sarah,\n\nHope you are doing well.")
    }

    func testCapitalizeSentences() {
        let config = TypedTextConfig(
            addTrailingSpace: false,
            capitalizeSentences: true
        )
        let formatter = TypedTextFormatter(config: config)

        XCTAssertEqual(
            formatter.format("first sentence. second sentence! third sentence? fourth."),
            "First sentence. Second sentence! Third sentence? Fourth."
        )
    }

    func testTrailingSpaceBehavior() {
        let withTrailing = TypedTextFormatter(config: TypedTextConfig(addTrailingSpace: true, capitalizeSentences: false))
        XCTAssertEqual(withTrailing.format("hello"), "hello ")
        XCTAssertEqual(withTrailing.format("hello "), "hello ")

        let withoutTrailing = TypedTextFormatter(config: TypedTextConfig(addTrailingSpace: false, capitalizeSentences: false))
        XCTAssertEqual(withoutTrailing.format("hello"), "hello")
    }

    func testAppDelegateFormattingIntegration() {
        let delegate = AppDelegate()
        let formatted = delegate._test_formatTranscriptText("hello world")
        // Default has capitalizeSentences = true, addTrailingSpace = true
        XCTAssertEqual(formatted, "Hello world ")
    }

    func testAppConfigDefaultsIncludeTypedText() {
        let config = AppConfig.default
        XCTAssertTrue(config.typedText.addTrailingSpace)
        XCTAssertTrue(config.typedText.capitalizeSentences)
        XCTAssertFalse(config.typedText.writeNumbersAsDigits)
        XCTAssertFalse(config.typedText.useSymbolsAndOrdinals)
        XCTAssertFalse(config.typedText.spokenEmoji)
        XCTAssertTrue(config.typedText.paragraphBreaks)
        XCTAssertTrue(config.typedText.spokenPunctuation)
    }

    func testSpokenPunctuation() {
        let config = TypedTextConfig(
            addTrailingSpace: false,
            capitalizeSentences: true,
            spokenPunctuation: true
        )
        let formatter = TypedTextFormatter(config: config)

        XCTAssertEqual(
            formatter.format("hello comma how are you question mark"),
            "Hello, how are you?"
        )
        XCTAssertEqual(
            formatter.format("this is amazing exclamation point"),
            "This is amazing!"
        )
        XCTAssertEqual(
            formatter.format("first item comma second item semicolon third item period"),
            "First item, second item; third item."
        )
        XCTAssertEqual(
            formatter.format("wait ellipsis really question mark"),
            "Wait... Really?"
        )
        XCTAssertEqual(
            formatter.format("she said open quote welcome close quote period"),
            "She said \"welcome\"."
        )
        XCTAssertEqual(
            formatter.format("note open paren see details close paren period"),
            "Note (see details)."
        )
        // Verify natural phrasing "period of time" is protected
        XCTAssertEqual(
            formatter.format("during a period of time period"),
            "During a period of time."
        )
    }
}
