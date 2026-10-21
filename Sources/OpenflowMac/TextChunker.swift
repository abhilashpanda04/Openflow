import Foundation
import NaturalLanguage

public struct TextSentence: Identifiable, Equatable {
    public let id: Int
    public let text: String
    public let range: NSRange

    public init(id: Int, text: String, range: NSRange) {
        self.id = id
        self.text = text
        self.range = range
    }
}

public struct TextChunker {
    /// Splits long text into structured sentences using Apple's NaturalLanguage tokenizer.
    public static func splitIntoSentences(_ text: String) -> [TextSentence] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [TextSentence] = []
        var index = 0

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let rawSentence = String(text[tokenRange])
            let cleanSentence = rawSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanSentence.isEmpty {
                let nsRange = NSRange(tokenRange, in: text)
                sentences.append(TextSentence(id: index, text: cleanSentence, range: nsRange))
                index += 1
            }
            return true
        }

        // Fallback in case tokenizer found nothing (e.g. single word or unpunctuated text)
        if sentences.isEmpty && !trimmed.isEmpty {
            let nsRange = NSRange(location: 0, length: (text as NSString).length)
            sentences.append(TextSentence(id: 0, text: trimmed, range: nsRange))
        }

        return sentences
    }
}
