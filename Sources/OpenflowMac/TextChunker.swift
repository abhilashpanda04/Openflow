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

    /// Splits long text into structured paragraphs for continuous audiobook-style reading.
    public static func splitIntoParagraphs(_ text: String) -> [TextSentence] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var paragraphs: [TextSentence] = []
        var index = 0

        // Regex that matches paragraphs separated by double or single newlines
        let pattern = #"(?:[^\r\n]+(?:\r?\n(?![ \t]*\r?\n)[^\r\n]+)*)"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let raw = nsText.substring(with: match.range)
                let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    // Normalize internal single newlines to spaces for natural speech prosody
                    let normalized = clean.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    // If paragraph is extraordinarily long (> 1200 chars), split at sentence boundaries to protect token context
                    if normalized.count > 1200 {
                        let subSentences = splitIntoSentences(normalized)
                        for sub in subSentences {
                            paragraphs.append(TextSentence(id: index, text: sub.text, range: match.range))
                            index += 1
                        }
                    } else {
                        paragraphs.append(TextSentence(id: index, text: normalized, range: match.range))
                        index += 1
                    }
                }
            }
        }

        if paragraphs.isEmpty && !trimmed.isEmpty {
            let nsRange = NSRange(location: 0, length: (text as NSString).length)
            paragraphs.append(TextSentence(id: 0, text: trimmed, range: nsRange))
        }

        return paragraphs
    }
}
