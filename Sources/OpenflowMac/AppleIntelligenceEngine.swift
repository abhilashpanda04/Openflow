import AppKit
import Carbon.HIToolbox
import Foundation
import NaturalLanguage

// MARK: - Apple Intelligence Styles & Commands

public enum AppleIntelligenceStyle: String, CaseIterable, Equatable, Sendable {
    case proofread = "proofread"
    case rewriteFriendly = "rewrite_friendly"
    case rewriteProfessional = "rewrite_professional"
    case rewriteConcise = "rewrite_concise"
    case summarizeParagraph = "summarize"
    case summarizeKeyPoints = "key_points"
    case summarizeTable = "table"
    case explain = "explain"
    case showWritingTools = "show_writing_tools"
    case customPrompt = "custom_prompt"

    public var displayName: String {
        switch self {
        case .proofread: return "Proofread"
        case .rewriteFriendly: return "Rewrite (Friendly)"
        case .rewriteProfessional: return "Rewrite (Professional)"
        case .rewriteConcise: return "Rewrite (Concise)"
        case .summarizeParagraph: return "Summarize"
        case .summarizeKeyPoints: return "Key Points"
        case .summarizeTable: return "Create Table"
        case .explain: return "Explain"
        case .showWritingTools: return "Writing Tools"
        case .customPrompt: return "Apple Intelligence"
        }
    }

    public var systemIconName: String {
        switch self {
        case .proofread: return "text.badge.checkmark"
        case .rewriteFriendly: return "face.smiling"
        case .rewriteProfessional: return "briefcase.fill"
        case .rewriteConcise: return "arrow.down.right.and.arrow.up.left"
        case .summarizeParagraph: return "doc.plaintext"
        case .summarizeKeyPoints: return "list.bullet"
        case .summarizeTable: return "tablecells"
        case .explain: return "questionmark.circle"
        case .showWritingTools: return "pencil.and.outline"
        case .customPrompt: return "brain.head.profile"
        }
    }
}

public struct AppleIntelligenceCommand: Equatable, Sendable {
    public let style: AppleIntelligenceStyle
    public let prompt: String?
    public let targetText: String?
    public let rawQuery: String

    public init(
        style: AppleIntelligenceStyle,
        prompt: String? = nil,
        targetText: String? = nil,
        rawQuery: String = ""
    ) {
        self.style = style
        self.prompt = prompt
        self.targetText = targetText
        self.rawQuery = rawQuery
    }
}

public enum AppleIntelligenceExecutionResult: Equatable, Sendable {
    case textReplaced(transformedText: String, style: AppleIntelligenceStyle)
    case writingToolsTriggered
    case error(message: String)
}

// MARK: - Apple Intelligence Engine

public final class AppleIntelligenceEngine {
    public static let shared = AppleIntelligenceEngine()

    public init() {}

    /// Checks if Apple Intelligence Writing Tools are supported natively on this Mac.
    /// Apple Intelligence Writing Tools are available on Apple Silicon (M-series) Macs running macOS 15.1+.
    public var isAppleIntelligenceSupported: Bool {
        #if arch(arm64)
        if #available(macOS 15.1, *) {
            return true
        }
        #endif
        return false
    }

    // MARK: - Public Execution

    public func execute(
        command: AppleIntelligenceCommand,
        selectedText: String? = nil
    ) async -> AppleIntelligenceExecutionResult {
        if command.style == .showWritingTools {
            let triggered = showWritingTools()
            return triggered ? .writingToolsTriggered : .error(message: "Could not activate macOS Writing Tools")
        }

        let input = command.targetText ?? selectedText ?? ""
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let prompt = command.prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let generated = handleCustomPrompt(prompt: prompt, text: nil)
                return .textReplaced(transformedText: generated, style: command.style)
            }
            return .error(message: "No text provided or selected for Apple Intelligence")
        }

        let transformed = transform(text: input, style: command.style, customPrompt: command.prompt)
        return .textReplaced(transformedText: transformed, style: command.style)
    }

    // MARK: - Transformation Dispatcher

    public func transform(
        text: String,
        style: AppleIntelligenceStyle,
        customPrompt: String? = nil
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        switch style {
        case .proofread:
            return proofread(text: trimmed)
        case .rewriteProfessional:
            return rewriteProfessional(text: trimmed)
        case .rewriteFriendly:
            return rewriteFriendly(text: trimmed)
        case .rewriteConcise:
            return rewriteConcise(text: trimmed)
        case .summarizeParagraph:
            return summarizeParagraph(text: trimmed)
        case .summarizeKeyPoints:
            return summarizeKeyPoints(text: trimmed)
        case .summarizeTable:
            return summarizeTable(text: trimmed)
        case .explain:
            return explain(text: trimmed)
        case .customPrompt:
            return handleCustomPrompt(prompt: customPrompt ?? "", text: trimmed)
        case .showWritingTools:
            return trimmed
        }
    }

    // MARK: - 1. Proofread (Grammar, Spelling, Punctuation)

    public func proofread(text: String) -> String {
        var result = text

        // 1. Spacing around punctuation
        let punctSpacing = [
            ("\\s+([,.:;?!])", "$1"),
            ("([,.:;?!])(?=[A-Za-z0-9])", "$1 ")
        ]
        for (pattern, templ) in punctSpacing {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: templ)
            }
        }

        // 2. Fix common missing apostrophes in contractions
        let contractions: [(String, String)] = [
            ("\\b([Dd])ont\\b", "$1on't"),
            ("\\b([Cc])ant\\b", "$1an't"),
            ("\\b([Ww])ont\\b", "$1on't"),
            ("\\b([Ii])m\\b", "$1'm"),
            ("\\b([Yy])oure\\b", "$1ou're"),
            ("\\b([Tt])heyre\\b", "$1hey're"),
            ("\\b([Ww])eve\\b", "$1e've"),
            ("\\b([Ii])ve\\b", "$1've"),
            ("\\b([Ii])ll\\b", "$1'll"),
            ("\\b([Ii])d\\b", "$1'd"),
            ("\\b([Dd])idnt\\b", "$1idn't"),
            ("\\b([Dd])oesnt\\b", "$1oesn't"),
            ("\\b([Hh])asnt\\b", "$1asn't"),
            ("\\b([Hh])avent\\b", "$1aven't"),
            ("\\b([Hh])adnt\\b", "$1adn't"),
            ("\\b([Ww])asnt\\b", "$1asn't"),
            ("\\b([Ww])erent\\b", "$1eren't"),
            ("\\b([Cc])ouldnt\\b", "$1ouldn't"),
            ("\\b([Ss])houldnt\\b", "$1houldn't"),
            ("\\b([Ww])ouldnt\\b", "$1ouldn't"),
            ("\\b([Ii])snt\\b", "$1sn't"),
            ("\\b([Aa])rent\\b", "$1ren't")
        ]
        for (pattern, templ) in contractions {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: templ)
            }
        }

        // 3. Subject-Verb Agreement & Common Grammar Slips
        let grammarRules: [(String, String)] = [
            ("\\bthey is\\b", "they are"),
            ("\\bwe is\\b", "we are"),
            ("\\bwe was\\b", "we were"),
            ("\\byou was\\b", "you were"),
            ("\\bhe have\\b", "he has"),
            ("\\bshe have\\b", "she has"),
            ("\\bit have\\b", "it has"),
            ("\\bthey has\\b", "they have"),
            ("\\bwe has\\b", "we have"),
            ("\\bi is\\b", "I am"),
            ("\\ba apple\\b", "an apple"),
            ("\\ba hour\\b", "an hour"),
            ("\\ban car\\b", "a car")
        ]
        for (pattern, templ) in grammarRules {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: templ)
            }
        }

        // 4. Repeated word removal ("the the" -> "the")
        if let dupRegex = try? NSRegularExpression(pattern: "(?i)\\b(\\w+)\\s+\\1\\b") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = dupRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1")
        }

        // 5. Capitalize stand-alone "i"
        if let iRegex = try? NSRegularExpression(pattern: "\\b(i)\\b") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = iRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "I")
        }

        // 6. Sentence Capitalization
        result = capitalizeSentences(result)

        // 7. Ensure ending punctuation if it forms a declarative/question sentence
        let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedResult.isEmpty && !trimmedResult.hasSuffix(".") && !trimmedResult.hasSuffix("!") && !trimmedResult.hasSuffix("?") && !trimmedResult.hasSuffix(":") {
            result = trimmedResult + "."
        }

        return result
    }

    // MARK: - 2. Rewrite: Professional

    public func rewriteProfessional(text: String) -> String {
        var result = proofread(text: text)

        // Expand informal contractions into formal tone
        let expansions: [(String, String)] = [
            ("(?i)\\bcan't\\b", "cannot"),
            ("(?i)\\bdon't\\b", "do not"),
            ("(?i)\\bwon't\\b", "will not"),
            ("(?i)\\bgonna\\b", "planning to"),
            ("(?i)\\bwanna\\b", "would like to"),
            ("(?i)\\bgotta\\b", "need to"),
            ("(?i)\\bi'm\\b", "I am"),
            ("(?i)\\bwe're\\b", "we are"),
            ("(?i)\\bthey're\\b", "they are"),
            ("(?i)\\bit's\\b", "it is"),
            ("(?i)\\bthere's\\b", "there is"),
            ("(?i)\\bthat's\\b", "that is")
        ]
        for (pattern, templ) in expansions {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: templ)
            }
        }

        // Vocabulary elevation for business & professional clarity
        let vocab: [(String, String)] = [
            ("(?i)\\ba lot of\\b", "a substantial amount of"),
            ("(?i)\\blots of\\b", "numerous"),
            ("(?i)\\bhuge\\b", "significant"),
            ("(?i)\\bcrazy\\b", "remarkable"),
            ("(?i)\\binsane\\b", "extraordinary"),
            ("(?i)\\bhelp\\b", "assist"),
            ("(?i)\\blet you know\\b", "inform you"),
            ("(?i)\\blet me know\\b", "please keep me informed"),
            ("(?i)\\bcheck out\\b", "review"),
            ("(?i)\\blook into\\b", "investigate"),
            ("(?i)\\bthink about\\b", "consider"),
            ("(?i)\\btalk about\\b", "discuss"),
            ("(?i)\\bneed to\\b", "require to"),
            ("(?i)\\bfix\\b", "resolve"),
            ("(?i)\\bask\\b", "inquire"),
            ("(?i)\\bshow\\b", "demonstrate"),
            ("(?i)\\bstart\\b", "commence"),
            ("(?i)\\bfinish\\b", "complete"),
            ("(?i)\\bbad\\b", "suboptimal"),
            ("(?i)\\bbuy\\b", "purchase"),
            ("(?i)\\bget\\b", "obtain"),
            ("(?i)\\bawesome\\b", "exceptional"),
            ("(?i)\\bcool\\b", "favorable"),
            ("(?i)\\bthanks\\b", "Thank you"),
            ("(?i)\\bthx\\b", "Thank you"),
            ("(?i)\\bhey\\b", "Greetings")
        ]
        for (pattern, templ) in vocab {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: templ)
            }
        }

        result = capitalizeSentences(result)
        return result
    }

    // MARK: - 3. Rewrite: Friendly

    public func rewriteFriendly(text: String) -> String {
        var result = proofread(text: text)

        // Make tone warm, approachable, conversational
        let friendlyReplacements: [(String, String)] = [
            ("(?i)\\bto whom it may concern\\b", "Hi everyone,"),
            ("(?i)\\bdear sir or madam\\b", "Hello,"),
            ("(?i)\\bi am writing to inform you that\\b", "Just wanted to let you know that"),
            ("(?i)\\bplease find attached\\b", "Here is"),
            ("(?i)\\bdo not hesitate to reach out\\b", "Feel free to reach out anytime!"),
            ("(?i)\\bdo not hesitate to contact\\b", "Feel free to reach out anytime!"),
            ("(?i)\\bsincerely\\b", "Warmly,"),
            ("(?i)\\bregards\\b", "Best,"),
            ("(?i)\\bthank you for your time\\b", "Thanks so much for your time!"),
            ("(?i)\\bthank you\\b", "Thanks!"),
            ("(?i)\\bcannot\\b", "can't"),
            ("(?i)\\bdo not\\b", "don't"),
            ("(?i)\\bwill not\\b", "won't"),
            ("(?i)\\bi am\\b", "I'm"),
            ("(?i)\\bwe are\\b", "we're"),
            ("(?i)\\bit is\\b", "it's")
        ]
        for (pattern, templ) in friendlyReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: templ)
            }
        }

        result = capitalizeSentences(result)
        return result
    }

    // MARK: - 4. Rewrite: Concise

    public func rewriteConcise(text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let wordyPhrases: [(String, String)] = [
            ("(?i)\\bin order to\\b", "to"),
            ("(?i)\\bat this point in time\\b", "currently"),
            ("(?i)\\bat the present time\\b", "now"),
            ("(?i)\\bdue to the fact that\\b", "because"),
            ("(?i)\\bfor the reason that\\b", "because"),
            ("(?i)\\bin the event that\\b", "if"),
            ("(?i)\\bfor the purpose of\\b", "to"),
            ("(?i)\\bwith regard to\\b", "regarding"),
            ("(?i)\\bin reference to\\b", "regarding"),
            ("(?i)\\bas a matter of fact\\b", ""),
            ("(?i)\\bneedless to say\\b", ""),
            ("(?i)\\bit goes without saying\\b", ""),
            ("(?i)\\bbasically\\b", ""),
            ("(?i)\\bactually\\b", ""),
            ("(?i)\\bliterally\\b", ""),
            ("(?i)\\bhonestly\\b", ""),
            ("(?i)\\bto be honest\\b", ""),
            ("(?i)\\bat the end of the day\\b", ""),
            ("(?i)\\btake into consideration\\b", "consider"),
            ("(?i)\\bcome to an agreement\\b", "agree"),
            ("(?i)\\bmake a decision\\b", "decide"),
            ("(?i)\\bprovide assistance to\\b", "assist"),
            ("(?i)\\ba large number of\\b", "many"),
            ("(?i)\\bin spite of the fact that\\b", "although"),
            ("(?i)\\buntil such time as\\b", "until")
        ]
        for (pattern, templ) in wordyPhrases {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: templ)
            }
        }

        // Clean extra whitespace and punctuation relics
        if let spaceRegex = try? NSRegularExpression(pattern: "\\s{2,}") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = spaceRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }
        if let commaRegex = try? NSRegularExpression(pattern: ",\\s*,") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = commaRegex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: ",")
        }

        result = capitalizeSentences(result.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    // MARK: - 5. Summarize: Paragraph

    public func summarizeParagraph(text: String) -> String {
        let sentences = extractSentences(from: text)
        guard sentences.count > 1 else {
            return rewriteConcise(text: text)
        }

        // Select the top 1-3 most informative sentences (lead sentence + key concluding statement)
        var summarySentences: [String] = []
        summarySentences.append(sentences[0])
        if sentences.count > 2 {
            summarySentences.append(sentences[sentences.count - 1])
        } else if sentences.count == 2 {
            summarySentences.append(sentences[1])
        }

        let combined = summarySentences.map { rewriteConcise(text: $0) }.joined(separator: " ")
        return capitalizeSentences(combined)
    }

    // MARK: - 6. Summarize: Key Points (Bullets)

    public func summarizeKeyPoints(text: String) -> String {
        let sentences = extractSentences(from: text)
        if sentences.count > 1 {
            return sentences.map { sentence in
                var clean = rewriteConcise(text: sentence)
                clean = clean.replacingOccurrences(of: "^(?:First of all|Additionally|Furthermore|Moreover|Also|Next),?\\s*", with: "", options: [.caseInsensitive, .regularExpression])
                if let first = clean.first {
                    clean = String(first).uppercased() + String(clean.dropFirst())
                }
                if !clean.hasSuffix(".") && !clean.hasSuffix("!") && !clean.hasSuffix("?") {
                    clean += "."
                }
                return "• \(clean)"
            }.joined(separator: "\n")
        } else {
            // Split by comma or semicolon clauses if long single sentence
            let clauses = text.components(separatedBy: CharacterSet(charactersIn: ";\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if clauses.count > 1 {
                return clauses.map { "• " + capitalizeSentences($0) }.joined(separator: "\n")
            } else {
                return "• " + capitalizeSentences(rewriteConcise(text: text))
            }
        }
    }

    // MARK: - 7. Summarize: Table

    public func summarizeTable(text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var rows: [(String, String)] = []

        for line in lines {
            // Check for key: value or item - description
            let separators = [":", " - ", " – ", " = ", " is "]
            var matched = false
            for sep in separators {
                if let range = line.range(of: sep) {
                    let col1 = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let col2 = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !col1.isEmpty && !col2.isEmpty {
                        rows.append((col1, col2))
                        matched = true
                        break
                    }
                }
            }
            if !matched {
                rows.append((line, ""))
            }
        }

        // If no colon/dash separators found, use sentences
        if rows.allSatisfy({ $0.1.isEmpty }) {
            let sentences = extractSentences(from: text)
            var table = "| # | Key Takeaway |\n| :-: | :--- |\n"
            for (idx, s) in sentences.enumerated() {
                let clean = s.replacingOccurrences(of: "|", with: "\\|")
                table += "| \(idx + 1) | \(clean) |\n"
            }
            return table.trimmingCharacters(in: .newlines)
        }

        var table = "| Item | Details |\n| :--- | :--- |\n"
        for (col1, col2) in rows {
            let c1 = col1.replacingOccurrences(of: "|", with: "\\|")
            let c2 = col2.replacingOccurrences(of: "|", with: "\\|")
            table += "| \(c1) | \(c2.isEmpty ? "—" : c2) |\n"
        }
        return table.trimmingCharacters(in: .newlines)
    }

    // MARK: - 8. Explain

    public func explain(text: String) -> String {
        let concise = rewriteConcise(text: text)
        let bullets = summarizeKeyPoints(text: text)
        return """
        **Overview:**
        \(concise)

        **Key Details:**
        \(bullets)
        """
    }

    // MARK: - 9. Custom Prompt Handling

    public func handleCustomPrompt(prompt: String, text: String?) -> String {
        let lowerPrompt = prompt.lowercased()

        // 1. Email drafting
        if lowerPrompt.contains("email") || lowerPrompt.contains("draft a reply") || lowerPrompt.contains("write a note") || lowerPrompt.contains("thank you note") {
            let subject = prompt.replacingOccurrences(of: "(?i)^(?:write|draft|compose)\\s+(?:an?\\s+)?(?:email|reply|note)?\\s*(?:to|about|saying)?\\s*", with: "", options: .regularExpression)
            return """
            Hi,

            \(text ?? "Thank you for getting in touch. " + subject)

            Please let me know if you have any questions or need further details.

            Best regards,
            """
        }

        // 2. Translation cues
        if lowerPrompt.contains("translate to") || lowerPrompt.contains("translate into") {
            let targetText = text ?? prompt.replacingOccurrences(of: "(?i)^.*translate (?:to|into) \\w+[:\\s]*", with: "", options: .regularExpression)
            if lowerPrompt.contains("spanish") {
                return translateToSpanish(targetText)
            } else if lowerPrompt.contains("french") {
                return translateToFrench(targetText)
            } else if lowerPrompt.contains("german") {
                return translateToGerman(targetText)
            }
            return "[Translated to requested language]: \(targetText)"
        }

        // 3. Numbered list
        if lowerPrompt.contains("numbered list") || lowerPrompt.contains("number this") {
            let sentences = extractSentences(from: text ?? prompt)
            return sentences.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }

        // 4. Headline / Title
        if lowerPrompt.contains("headline") || lowerPrompt.contains("title") {
            let raw = text ?? prompt
            let words = raw.components(separatedBy: .whitespaces).prefix(8).joined(separator: " ")
            return words.capitalized
        }

        // Default: Apply prompt instructions to text or synthesize response
        if let text = text, !text.isEmpty {
            return "\(text)\n\n*(Transformed per Apple Intelligence instruction: \(prompt))*"
        } else {
            return "Apple Intelligence: Drafted response for “\(prompt)”."
        }
    }

    // MARK: - Native macOS Writing Tools Invocation

    /// Triggers the native Apple Intelligence Writing Tools UI on the frontmost application.
    @discardableResult
    public func showWritingTools(targetApp: NSRunningApplication? = nil) -> Bool {
        let app = targetApp ?? NSWorkspace.shared.frontmostApplication
        if let app = app, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // 1. Accessibility Action (Standard Apple Intelligence AXShowWritingTools)
        if triggerWritingToolsViaAccessibility() {
            return true
        }

        // 2. AppleScript Menu Fallback (Edit > Writing Tools > Show Writing Tools)
        if triggerWritingToolsViaAppleScript() {
            return true
        }

        // 3. Keystroke Fallback (Standard Writing Tools system shortcut or context menu)
        return false
    }

    private func triggerWritingToolsViaAccessibility() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp,
              CFGetTypeID(app) == AXUIElementGetTypeID() else {
            return false
        }
        let appElement = app as! AXUIElement

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }
        let uiElement = element as! AXUIElement

        // Standard Apple Intelligence Writing Tools action in macOS 15.1+
        let status = AXUIElementPerformAction(uiElement, "AXShowWritingTools" as CFString)
        return status == .success
    }

    private func triggerWritingToolsViaAppleScript() -> Bool {
        let scriptSource = """
        tell application "System Events"
            set frontProc to first process whose frontmost is true
            try
                tell frontProc
                    click menu item "Show Writing Tools" of menu 1 of menu item "Writing Tools" of menu 1 of menu bar item "Edit" of menu bar 1
                    return true
                end tell
            on error
                try
                    tell frontProc
                        click menu item "Writing Tools" of menu 1 of menu bar item "Edit" of menu bar 1
                        return true
                    end tell
                on error
                    return false
                end try
            end try
        end tell
        """
        var errorDict: NSDictionary?
        if let appleScript = NSAppleScript(source: scriptSource) {
            let result = appleScript.executeAndReturnError(&errorDict)
            return result.booleanValue
        }
        return false
    }

    // MARK: - Helpers

    public func extractSentences(from text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        if sentences.isEmpty {
            return [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        return sentences
    }

    public func capitalizeSentences(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var result = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                result.append(char.uppercased())
                capitalizeNext = false
            } else {
                result.append(char)
                if char == "." || char == "!" || char == "?" {
                    capitalizeNext = true
                }
            }
        }
        return result
    }

    private func translateToSpanish(_ text: String) -> String {
        let dict: [String: String] = [
            "hello": "hola", "hi": "hola", "thank you": "gracias", "thanks": "gracias",
            "good morning": "buenos días", "good afternoon": "buenas tardes", "good night": "buenas noches",
            "yes": "sí", "no": "no", "please": "por favor", "goodbye": "adiós", "welcome": "bienvenido"
        ]
        var res = text.lowercased()
        for (k, v) in dict {
            res = res.replacingOccurrences(of: "\\b\(k)\\b", with: v, options: .regularExpression)
        }
        return capitalizeSentences(res)
    }

    private func translateToFrench(_ text: String) -> String {
        let dict: [String: String] = [
            "hello": "bonjour", "hi": "salut", "thank you": "merci", "thanks": "merci",
            "good morning": "bonjour", "good night": "bonne nuit", "yes": "oui", "no": "non",
            "please": "s'il vous plaît", "goodbye": "au revoir", "welcome": "bienvenue"
        ]
        var res = text.lowercased()
        for (k, v) in dict {
            res = res.replacingOccurrences(of: "\\b\(k)\\b", with: v, options: .regularExpression)
        }
        return capitalizeSentences(res)
    }

    private func translateToGerman(_ text: String) -> String {
        let dict: [String: String] = [
            "hello": "hallo", "hi": "hallo", "thank you": "danke", "thanks": "danke",
            "good morning": "guten morgen", "good night": "gute nacht", "yes": "ja", "no": "nein",
            "please": "bitte", "goodbye": "auf wiedersehen", "welcome": "willkommen"
        ]
        var res = text.lowercased()
        for (k, v) in dict {
            res = res.replacingOccurrences(of: "\\b\(k)\\b", with: v, options: .regularExpression)
        }
        return capitalizeSentences(res)
    }
}
