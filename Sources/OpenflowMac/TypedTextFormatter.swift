import Foundation

public struct TypedTextConfig: Equatable {
    public var addTrailingSpace: Bool
    public var capitalizeSentences: Bool
    public var writeNumbersAsDigits: Bool
    public var useSymbolsAndOrdinals: Bool
    public var spokenEmoji: Bool
    public var paragraphBreaks: Bool
    public var spokenPunctuation: Bool

    public init(
        addTrailingSpace: Bool = true,
        capitalizeSentences: Bool = true,
        writeNumbersAsDigits: Bool = false,
        useSymbolsAndOrdinals: Bool = false,
        spokenEmoji: Bool = false,
        paragraphBreaks: Bool = true,
        spokenPunctuation: Bool = true
    ) {
        self.addTrailingSpace = addTrailingSpace
        self.capitalizeSentences = capitalizeSentences
        self.writeNumbersAsDigits = writeNumbersAsDigits
        self.useSymbolsAndOrdinals = useSymbolsAndOrdinals
        self.spokenEmoji = spokenEmoji
        self.paragraphBreaks = paragraphBreaks
        self.spokenPunctuation = spokenPunctuation
    }
}

public struct TypedTextFormatter {
    public let config: TypedTextConfig

    public init(config: TypedTextConfig = TypedTextConfig()) {
        self.config = config
    }

    public func format(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if config.spokenEmoji {
            text = replaceSpokenEmojis(in: text)
        }

        if config.spokenPunctuation {
            text = replaceSpokenPunctuation(in: text)
        }

        if config.paragraphBreaks {
            text = formatParagraphBreaks(in: text)
        }

        if config.writeNumbersAsDigits {
            text = replaceNumbersAsDigits(in: text)

            if config.useSymbolsAndOrdinals {
                text = replaceSymbolsAndOrdinals(in: text)
            }
        }

        if config.spokenPunctuation {
            text = cleanPunctuationSpacing(in: text)
        }

        if config.capitalizeSentences {
            text = capitalizeSentences(in: text)
        }

        if config.addTrailingSpace {
            if !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("\n") {
                text += " "
            }
        }

        return text
    }

    // MARK: - Spoken Emoji

    private static let emojiMap: [(phrase: String, emoji: String)] = [
        ("party", "🎉"),
        ("celebration", "🎉"),
        ("party popper", "🎉"),
        ("fire", "🔥"),
        ("red heart", "❤️"),
        ("heart", "❤️"),
        ("thumbs up", "👍"),
        ("thumbs down", "👎"),
        ("smiling face", "😊"),
        ("smiley face", "😊"),
        ("smiley", "😊"),
        ("smile", "😊"),
        ("laughing", "😂"),
        ("crying laughing", "😂"),
        ("joy", "😂"),
        ("crying", "😭"),
        ("loudly crying", "😭"),
        ("sob", "😭"),
        ("rocket", "🚀"),
        ("checkmark", "✅"),
        ("check mark", "✅"),
        ("check", "✅"),
        ("cross", "❌"),
        ("x", "❌"),
        ("sparkles", "✨"),
        ("sparkle", "✨"),
        ("star", "⭐"),
        ("coffee", "☕"),
        ("waving hand", "👋"),
        ("waving", "👋"),
        ("wave", "👋"),
        ("clapping hands", "👏"),
        ("clapping", "👏"),
        ("clap", "👏"),
        ("eyes", "👀"),
        ("hundred points", "💯"),
        ("hundred", "💯"),
        ("100", "💯"),
        ("skull", "💀"),
        ("sunglasses", "😎"),
        ("cool", "😎"),
        ("thinking face", "🤔"),
        ("thinking", "🤔"),
        ("folded hands", "🙏"),
        ("praying", "🙏"),
        ("pray", "🙏"),
        ("mind blown", "🤯"),
        ("exploding head", "🤯"),
        ("facepalm", "🤦"),
        ("shrug", "🤷"),
        ("poop", "💩"),
        ("birthday cake", "🎂"),
        ("cake", "🎂"),
        ("cheers", "🍻"),
        ("beer", "🍻"),
        ("wine", "🍷"),
        ("pizza", "🍕"),
        ("muscle", "💪"),
        ("flex", "💪"),
        ("money bag", "💰"),
        ("money", "💰"),
        ("warning", "⚠️"),
        ("lightning", "⚡"),
        ("bolt", "⚡"),
        ("sun", "☀️"),
        ("moon", "🌙")
    ]

    private func replaceSpokenEmojis(in input: String) -> String {
        var text = input
        for item in Self.emojiMap {
            // Replace pattern: [word] emoji OR [word] emojis
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: item.phrase))\\s+emojis?\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: item.emoji)
            }
        }
        return text
    }

    // MARK: - Spoken Punctuation

    private static let spokenPunctuationMap: [(pattern: String, replacement: String)] = [
        // Multi-word punctuation phrases first (consume adjoining whitespace)
        ("(?i)\\s*\\bquestion\\s+mark\\b", "?"),
        ("(?i)\\s*\\bexclamation\\s+(?:mark|point)\\b", "!"),
        ("(?i)\\s*\\bfull\\s+stop\\b", "."),
        ("(?i)\\s*\\b(?:dot\\s+dot\\s+dot|ellipsis)\\b", "..."),
        ("(?i)\\s*\\b(?:semi\\s+colon|semicolon)\\b", ";"),
        ("(?i)\\b(?:em\\s+dash)\\b", "—"),
        ("(?i)\\b(?:open\\s+(?:quote|quotation)|start\\s+quote)\\s*", "\""),
        ("(?i)\\s*\\b(?:close\\s+(?:quote|quotation)|end\\s+quote)\\b", "\""),
        ("(?i)\\b(?:open\\s+(?:parenthesis|paren))\\s*", "("),
        ("(?i)\\s*\\b(?:close\\s+(?:parenthesis|paren))\\b", ")"),
        ("(?i)\\b(?:open\\s+bracket)\\s*", "["),
        ("(?i)\\s*\\b(?:close\\s+bracket)\\b", "]"),
        // Single-word punctuation (with smart negative lookaheads to protect natural language)
        ("(?i)\\s*\\bperiod\\b(?!\\s+of\\b)", "."),
        ("(?i)\\s*\\bcomma\\b", ","),
        ("(?i)\\s*\\bcolon\\b(?!\\s+(?:cancer|polyps|screening))", ":"),
        ("(?i)\\b(?:hyphen)\\b", "-"),
        ("(?i)\\bdash\\b(?!\\s+(?:of|cam))", "-")
    ]

    private func replaceSpokenPunctuation(in input: String) -> String {
        var text = input
        for item in Self.spokenPunctuationMap {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: []) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: item.replacement)
            }
        }
        return text
    }

    private func cleanPunctuationSpacing(in input: String) -> String {
        var text = input

        // 1. Remove space before punctuation marks: "word ," -> "word,"
        if let regex = try? NSRegularExpression(pattern: "\\s+([,.:;?!—])", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
        }

        // 2. Remove space inside opening brackets/parentheses: "( word" -> "(word"
        if let regex = try? NSRegularExpression(pattern: "([(<\\[])\\s+", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
        }

        // 3. Remove space before closing brackets/parentheses: "word )" -> "word)"
        if let regex = try? NSRegularExpression(pattern: "\\s+([)>\\]])", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
        }

        // 4. Ensure space after punctuation when followed by a letter: "hello,world" -> "hello, world"
        if let regex = try? NSRegularExpression(pattern: "([,.:;?!])([A-Za-z])", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1 $2")
        }

        // 5. Clean up multiple consecutive spaces
        if let regex = try? NSRegularExpression(pattern: "[ \\t]{2,}", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }

        return text
    }

    // MARK: - Paragraph Breaks

    private func formatParagraphBreaks(in input: String) -> String {
        var text = input

        // Spoken "new paragraph" / "next paragraph"
        if let regex = try? NSRegularExpression(pattern: "\\s*\\b(?:new|next)\\s+paragraph\\b\\s*", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\n\n")
        }

        // Spoken "new line"
        if let regex = try? NSRegularExpression(pattern: "\\s*\\bnew\\s+line\\b\\s*", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\n")
        }

        // Email greetings on their own line (e.g. "Hi John, hope you are well" -> "Hi John,\n\nHope you are well")
        let greetingPattern = "^(Hi|Hello|Dear|Hey)\\s+([A-Z][a-z]+),?\\s+([A-Za-z])"
        if let regex = try? NSRegularExpression(pattern: greetingPattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1 $2,\n\n$3")
        }

        return text
    }

    // MARK: - Numbers as Digits

    private static let timeWordMap: [String: String] = [
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12"
    ]

    private static let numberMap: [(word: String, digit: String)] = [
        ("ninety-nine", "99"), ("ninety nine", "99"),
        ("ninety-eight", "98"), ("ninety eight", "98"),
        ("ninety-seven", "97"), ("ninety seven", "97"),
        ("ninety-six", "96"), ("ninety six", "96"),
        ("ninety-five", "95"), ("ninety five", "95"),
        ("ninety-four", "94"), ("ninety four", "94"),
        ("ninety-three", "93"), ("ninety three", "93"),
        ("ninety-two", "92"), ("ninety two", "92"),
        ("ninety-one", "91"), ("ninety one", "91"),
        ("eighty-nine", "89"), ("eighty nine", "89"),
        ("eighty-eight", "88"), ("eighty eight", "88"),
        ("eighty-seven", "87"), ("eighty seven", "87"),
        ("eighty-six", "86"), ("eighty six", "86"),
        ("eighty-five", "85"), ("eighty five", "85"),
        ("eighty-four", "84"), ("eighty four", "84"),
        ("eighty-three", "83"), ("eighty three", "83"),
        ("eighty-two", "82"), ("eighty two", "82"),
        ("eighty-one", "81"), ("eighty one", "81"),
        ("seventy-nine", "79"), ("seventy nine", "79"),
        ("seventy-eight", "78"), ("seventy eight", "78"),
        ("seventy-seven", "77"), ("seventy seven", "77"),
        ("seventy-six", "76"), ("seventy six", "76"),
        ("seventy-five", "75"), ("seventy five", "75"),
        ("seventy-four", "74"), ("seventy four", "74"),
        ("seventy-three", "73"), ("seventy three", "73"),
        ("seventy-two", "72"), ("seventy two", "72"),
        ("seventy-one", "71"), ("seventy one", "71"),
        ("sixty-nine", "69"), ("sixty nine", "69"),
        ("sixty-eight", "68"), ("sixty eight", "68"),
        ("sixty-seven", "67"), ("sixty seven", "67"),
        ("sixty-six", "66"), ("sixty six", "66"),
        ("sixty-five", "65"), ("sixty five", "65"),
        ("sixty-four", "64"), ("sixty four", "64"),
        ("sixty-three", "63"), ("sixty three", "63"),
        ("sixty-two", "62"), ("sixty two", "62"),
        ("sixty-one", "61"), ("sixty one", "61"),
        ("fifty-nine", "59"), ("fifty nine", "59"),
        ("fifty-eight", "58"), ("fifty eight", "58"),
        ("fifty-seven", "57"), ("fifty seven", "57"),
        ("fifty-six", "56"), ("fifty six", "56"),
        ("fifty-five", "55"), ("fifty five", "55"),
        ("fifty-four", "54"), ("fifty four", "54"),
        ("fifty-three", "53"), ("fifty three", "53"),
        ("fifty-two", "52"), ("fifty two", "52"),
        ("fifty-one", "51"), ("fifty one", "51"),
        ("forty-nine", "49"), ("forty nine", "49"),
        ("forty-eight", "48"), ("forty eight", "48"),
        ("forty-seven", "47"), ("forty seven", "47"),
        ("forty-six", "46"), ("forty six", "46"),
        ("forty-five", "45"), ("forty five", "45"),
        ("forty-four", "44"), ("forty four", "44"),
        ("forty-three", "43"), ("forty three", "43"),
        ("forty-two", "42"), ("forty two", "42"),
        ("forty-one", "41"), ("forty one", "41"),
        ("thirty-nine", "39"), ("thirty nine", "39"),
        ("thirty-eight", "38"), ("thirty eight", "38"),
        ("thirty-seven", "37"), ("thirty seven", "37"),
        ("thirty-six", "36"), ("thirty six", "36"),
        ("thirty-five", "35"), ("thirty five", "35"),
        ("thirty-four", "34"), ("thirty four", "34"),
        ("thirty-three", "33"), ("thirty three", "33"),
        ("thirty-two", "32"), ("thirty two", "32"),
        ("thirty-one", "31"), ("thirty one", "31"),
        ("twenty-nine", "29"), ("twenty nine", "29"),
        ("twenty-eight", "28"), ("twenty eight", "28"),
        ("twenty-seven", "27"), ("twenty seven", "27"),
        ("twenty-six", "26"), ("twenty six", "26"),
        ("twenty-five", "25"), ("twenty five", "25"),
        ("twenty-four", "24"), ("twenty four", "24"),
        ("twenty-three", "23"), ("twenty three", "23"),
        ("twenty-two", "22"), ("twenty two", "22"),
        ("twenty-one", "21"), ("twenty one", "21"),
        ("one hundred", "100"), ("a hundred", "100"),
        ("one thousand", "1000"), ("a thousand", "1000"),
        ("one million", "1000000"), ("a million", "1000000"),
        ("ninety", "90"), ("eighty", "80"), ("seventy", "70"),
        ("sixty", "60"), ("fifty", "50"), ("forty", "40"),
        ("thirty", "30"), ("twenty", "20"),
        ("nineteen", "19"), ("eighteen", "18"), ("seventeen", "17"),
        ("sixteen", "16"), ("fifteen", "15"), ("fourteen", "14"),
        ("thirteen", "13"), ("twelve", "12"), ("eleven", "11"),
        ("ten", "10"), ("nine", "9"), ("eight", "8"), ("seven", "7"),
        ("six", "6"), ("five", "5"), ("four", "4"), ("three", "3"),
        ("two", "2"), ("zero", "0")
    ]

    private func replaceNumbersAsDigits(in input: String) -> String {
        var text = input

        // 1. Specific time pattern: "six pm" -> "6 pm", "six am" -> "6 am"
        for (word, digit) in Self.timeWordMap {
            let pattern = "\\b\(word)\\s*(pm|am|p\\.m\\.|a\\.m\\.)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\(digit) $1")
            }
        }

        // 2. Multi-word and single-word numbers
        for item in Self.numberMap {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: item.word))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: item.digit)
            }
        }

        return text
    }

    // MARK: - Symbols and Ordinals

    private static let ordinalsMap: [(word: String, ordinal: String)] = [
        ("first", "1st"), ("second", "2nd"), ("third", "3rd"),
        ("fourth", "4th"), ("fifth", "5th"), ("sixth", "6th"),
        ("seventh", "7th"), ("eighth", "8th"), ("ninth", "9th"),
        ("tenth", "10th"), ("eleventh", "11th"), ("twelfth", "12th"),
        ("thirteenth", "13th"), ("fourteenth", "14th"), ("fifteenth", "15th"),
        ("sixteenth", "16th"), ("seventeenth", "17th"), ("eighteenth", "18th"),
        ("nineteenth", "19th"), ("twentieth", "20th"),
        ("twenty-first", "21st"), ("twenty first", "21st"),
        ("twenty-second", "22nd"), ("twenty second", "22nd"),
        ("twenty-third", "23rd"), ("twenty third", "23rd"),
        ("thirtieth", "30th"), ("thirty-first", "31st"), ("thirty first", "31st"),
        ("fiftieth", "50th"), ("hundredth", "100th")
    ]

    private func replaceSymbolsAndOrdinals(in input: String) -> String {
        var text = input

        // Ordinals
        for item in Self.ordinalsMap {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: item.word))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: item.ordinal)
            }
        }

        // Percent: "50 percent" -> "50%"
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:percent|percentage)\\b", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1%")
        }

        // Dollars: "50 dollars" -> "$50", "5 bucks" -> "$5"
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:dollars?|bucks?)\\b", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\\$$1")
        }

        // Cents: "50 cents" -> "50¢"
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:cents?)\\b", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1¢")
        }

        // Degrees: "72 degrees" -> "72°"
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:degrees?)\\b", options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1°")
        }

        return text
    }

    // MARK: - Sentence Capitalization

    private func capitalizeSentences(in input: String) -> String {
        guard !input.isEmpty else { return "" }

        var chars = Array(input)
        var shouldCapitalize = true

        for i in 0..<chars.count {
            let char = chars[i]

            if shouldCapitalize && char.isLetter {
                chars[i] = Character(char.uppercased())
                shouldCapitalize = false
            } else if char == "." || char == "!" || char == "?" || char == "\n" {
                shouldCapitalize = true
            }
        }

        return String(chars)
    }
}
