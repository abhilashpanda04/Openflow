import AppKit
import Carbon.HIToolbox
import Foundation

// MARK: - Voice Command Types

public enum VoiceSystemAction: String, CaseIterable {
    case selectAll = "select_all"
    case undo = "undo"
    case redo = "redo"
    case copy = "copy"
    case paste = "paste"
    case cut = "cut"
    case deleteLine = "delete_line"
    case delete = "delete"
    case newLine = "new_line"
    case newParagraph = "new_paragraph"
    case save = "save"
    case scratchThat = "scratch_that"

    public var displayName: String {
        switch self {
        case .selectAll: return "Select All (⌘A)"
        case .undo: return "Undo (⌘Z)"
        case .redo: return "Redo (⌘⇧Z)"
        case .copy: return "Copy (⌘C)"
        case .paste: return "Paste (⌘V)"
        case .cut: return "Cut (⌘X)"
        case .deleteLine: return "Delete Line (⌘⌫)"
        case .delete: return "Delete (⌫)"
        case .newLine: return "New Line (↵)"
        case .newParagraph: return "New Paragraph (↵↵)"
        case .save: return "Save (⌘S)"
        case .scratchThat: return "Scratch That (Cancel)"
        }
    }
}

public enum VoiceSelectionEdit: String, CaseIterable {
    case shorter = "shorter"
    case bulletPoints = "bullet_points"
    case uppercase = "uppercase"
    case lowercase = "lowercase"
    case titleCase = "title_case"
    case fixGrammar = "fix_grammar"

    public var displayName: String {
        switch self {
        case .shorter: return "Make Shorter"
        case .bulletPoints: return "Turn into Bullet Points"
        case .uppercase: return "All Caps / Uppercase"
        case .lowercase: return "Lowercase"
        case .titleCase: return "Title Case"
        case .fixGrammar: return "Fix Grammar & Punctuation"
        }
    }
}

public enum VoiceCommandResult: Equatable {
    /// Standalone action that executes directly on the active app without typing text
    case systemAction(VoiceSystemAction)
    /// Transformed text applied to currently selected text
    case selectionEdit(transformed: String, description: String)
    /// Selection edit requested but no text was selected
    case selectionEditRequestedWithoutSelection(description: String)
    /// Apple Intelligence command (Writing Tools, proofreading, tone rewriting, summarizing, custom prompt)
    case appleIntelligence(AppleIntelligenceCommand)
    /// Regular dictated text after in-line self-corrections and navigation replacements
    case processedText(String)
    /// Dictation cancelled (e.g. user said "scratch that")
    case discarded
}

// MARK: - Voice Command Engine

public struct VoiceCommandEngine {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    /// Evaluates transcript against in-line commands, self-corrections, or selection edits.
    public func process(
        rawTranscript: String,
        selectedText: String? = nil
    ) -> VoiceCommandResult {
        guard isEnabled else {
            return .processedText(rawTranscript)
        }

        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .processedText("")
        }

        let cleaned = Self.cleanCommandText(trimmed)

        // 1. Check for standalone system action commands
        if let systemAction = matchStandaloneAction(cleaned) {
            if systemAction == .scratchThat {
                return .discarded
            }
            return .systemAction(systemAction)
        }

        // 2. Check for Apple Intelligence voice commands
        if let aiResult = matchAppleIntelligenceCommand(cleaned: cleaned, raw: trimmed, selectedText: selectedText) {
            return aiResult
        }

        // 3. Check for selection editing commands
        if let edit = matchSelectionEdit(cleaned) {
            if let selection = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !selection.isEmpty {
                let transformed = applySelectionEdit(edit, to: selection)
                return .selectionEdit(transformed: transformed, description: edit.displayName)
            } else {
                return .selectionEditRequestedWithoutSelection(description: edit.displayName)
            }
        }

        // 3. Check for in-line self-corrections (e.g., "scratch that" mid-sentence, "actually", "no, ...")
        var processed = processInlineSelfCorrections(trimmed)
        if processed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .discarded
        }

        // 4. Check for in-line navigation commands (e.g., "new line", "new paragraph")
        processed = processInlineNavigationCommands(processed)

        // 5. Check for in-line casing commands (e.g., "uppercase that", "lowercase that")
        processed = processInlineCaseCommands(processed)

        return .processedText(processed)
    }

    // MARK: - Text Cleaning & Normalization for Commands

    public static func cleanCommandText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Strip surrounding quotes
        let quoteChars = CharacterSet(charactersIn: "\"'“”‘’`")
        text = text.trimmingCharacters(in: quoteChars)

        // Strip punctuation at edges (. , ! ? ; :)
        let punctChars = CharacterSet(charactersIn: ".,!?;:")
        text = text.trimmingCharacters(in: punctChars).trimmingCharacters(in: .whitespaces)

        // Strip polite conversational prefixes
        let prefixes = [
            "please ", "can you ", "could you ", "hey openflow ", "openflow ", "hey ", "command "
        ]
        for p in prefixes {
            if text.hasPrefix(p) {
                text = String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Strip trailing polite suffixes
        let suffixes = [" please", " now"]
        for s in suffixes {
            if text.hasSuffix(s) {
                text = String(text.dropLast(s.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        text = text.trimmingCharacters(in: punctChars).trimmingCharacters(in: .whitespaces)
        return text
    }

    // MARK: - Standalone Action Matching

    private func matchStandaloneAction(_ text: String) -> VoiceSystemAction? {
        switch text {
        case "select all", "select everything", "highlight all", "highlight everything", "select all text":
            return .selectAll

        case "undo", "undo that", "revert that", "revert", "undo this", "undo last":
            return .undo

        case "redo", "redo that", "redo this":
            return .redo

        case "scratch that", "never mind", "nevermind", "cancel dictation", "cancel that", "forget that", "drop that", "scratch", "cancel", "stop dictation":
            return .scratchThat

        case "delete line", "delete this line", "clear line", "remove line":
            return .deleteLine

        case "delete that", "delete this", "delete selection", "delete", "backspace":
            return .delete

        case "copy that", "copy selection", "copy this", "copy", "copy text":
            return .copy

        case "paste that", "paste this", "paste", "paste text", "paste clipboard":
            return .paste

        case "cut that", "cut selection", "cut this", "cut", "cut text":
            return .cut

        case "new line", "next line", "enter", "press enter":
            return .newLine

        case "new paragraph", "next paragraph", "double enter":
            return .newParagraph

        case "save that", "save file", "save document", "save":
            return .save

        default:
            return nil
        }
    }

    // MARK: - Apple Intelligence Command Matching

    public func matchAppleIntelligenceCommand(
        cleaned: String,
        raw: String,
        selectedText: String?
    ) -> VoiceCommandResult? {
        let lower = cleaned.lowercased()
        let selection = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Native Writing Tools launcher command
        if lower == "apple intelligence" ||
           lower == "show writing tools" ||
           lower == "open writing tools" ||
           lower == "writing tools" ||
           lower == "apple intelligence writing tools" ||
           lower == "apple intelligence show writing tools" ||
           lower == "launch writing tools" {
            return .appleIntelligence(
                AppleIntelligenceCommand(style: .showWritingTools, targetText: selection, rawQuery: raw)
            )
        }

        // 2. Proofread
        let proofreadCues = [
            "apple intelligence proofread",
            "proofread this with apple intelligence",
            "proofread with apple intelligence",
            "proofread this",
            "proofread selection",
            "proofread",
            "apple intelligence fix grammar and spelling",
            "apple intelligence check grammar"
        ]
        for cue in proofreadCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .proofread, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Proofread)")
                }
            }
        }

        // 3. Rewrite: Professional
        let profCues = [
            "apple intelligence rewrite professionally",
            "apple intelligence rewrite professional",
            "apple intelligence make this professional",
            "apple intelligence make this formal",
            "apple intelligence rewrite this professionally",
            "rewrite this professionally",
            "rewrite professionally",
            "make this professional",
            "make it professional",
            "make this formal",
            "make it formal",
            "professional rewrite"
        ]
        for cue in profCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .rewriteProfessional, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Rewrite Professional)")
                }
            }
        }

        // 4. Rewrite: Friendly
        let friendlyCues = [
            "apple intelligence rewrite friendly",
            "apple intelligence make this friendly",
            "apple intelligence make it friendly",
            "apple intelligence rewrite this friendly",
            "rewrite this friendly",
            "rewrite friendly",
            "make this friendly",
            "make it friendly",
            "make this sound friendly",
            "make it sound friendly",
            "friendly rewrite"
        ]
        for cue in friendlyCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .rewriteFriendly, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Rewrite Friendly)")
                }
            }
        }

        // 5. Rewrite: Concise
        let conciseCues = [
            "apple intelligence rewrite concise",
            "apple intelligence rewrite concisely",
            "apple intelligence make this concise",
            "apple intelligence make it concise",
            "apple intelligence rewrite this concise",
            "rewrite this concisely",
            "rewrite concise",
            "make this concise",
            "make it concise",
            "concise rewrite"
        ]
        for cue in conciseCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .rewriteConcise, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Rewrite Concise)")
                }
            }
        }

        // 6. Summarize: Paragraph
        let summarizeCues = [
            "apple intelligence summarize this",
            "apple intelligence summarize",
            "summarize this with apple intelligence",
            "summarize with apple intelligence",
            "summarize into a paragraph",
            "apple intelligence summary"
        ]
        for cue in summarizeCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .summarizeParagraph, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Summarize)")
                }
            }
        }

        // 7. Summarize: Key Points
        let keyPointsCues = [
            "apple intelligence key points",
            "apple intelligence summarize into key points",
            "apple intelligence bullet points",
            "summarize into key points",
            "give me key points",
            "extract key points",
            "key points summary"
        ]
        for cue in keyPointsCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .summarizeKeyPoints, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Key Points)")
                }
            }
        }

        // 8. Summarize: Table
        let tableCues = [
            "apple intelligence make a table",
            "apple intelligence table",
            "apple intelligence format as table",
            "format as table",
            "create a table",
            "create table from this",
            "turn this into a table",
            "summarize into a table"
        ]
        for cue in tableCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .summarizeTable, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Create Table)")
                }
            }
        }

        // 9. Explain
        let explainCues = [
            "apple intelligence explain this",
            "apple intelligence explain",
            "explain this with apple intelligence",
            "explain what this means",
            "explain this"
        ]
        for cue in explainCues {
            if lower == cue || lower.hasPrefix(cue + " ") || lower.hasPrefix(cue + ":") {
                let inlineText = extractInlineContent(from: raw, afterCue: cue)
                let target = !inlineText.isEmpty ? inlineText : selection
                if let target = target, !target.isEmpty {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .explain, targetText: target, rawQuery: raw)
                    )
                } else {
                    return .selectionEditRequestedWithoutSelection(description: "Apple Intelligence (Explain)")
                }
            }
        }

        // 10. General / Custom Prompt prefixed by "apple intelligence"
        let generalPrefixes = [
            "apple intelligence ",
            "use apple intelligence to ",
            "ask apple intelligence to ",
            "hey apple intelligence "
        ]
        for prefix in generalPrefixes {
            if lower.hasPrefix(prefix) {
                let prompt = String(raw.dropFirst(raw.index(raw.startIndex, offsetBy: min(prefix.count, raw.count)).utf16Offset(in: raw)))
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":, ").union(.whitespacesAndNewlines))
                guard !prompt.isEmpty else {
                    return .appleIntelligence(
                        AppleIntelligenceCommand(style: .showWritingTools, targetText: selection, rawQuery: raw)
                    )
                }
                return .appleIntelligence(
                    AppleIntelligenceCommand(
                        style: .customPrompt,
                        prompt: prompt,
                        targetText: selection,
                        rawQuery: raw
                    )
                )
            }
        }

        return nil
    }

    private func extractInlineContent(from raw: String, afterCue cue: String) -> String {
        let lower = raw.lowercased()
        guard let range = lower.range(of: cue) else { return "" }
        let after = String(raw[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: ":, ").union(.whitespacesAndNewlines))
        return after
    }

    // MARK: - Selection Edit Matching & Transformation

    private func matchSelectionEdit(_ text: String) -> VoiceSelectionEdit? {
        switch text {
        case "make this shorter", "make it shorter", "make shorter", "shorter", "shorten this", "shorten", "condense this", "condense", "summarize this", "summarize":
            return .shorter

        case "bullet points", "turn into bullet points", "make bullet points", "list this", "format as list", "bullet this", "bullets":
            return .bulletPoints

        case "all caps", "uppercase", "uppercase that", "make it uppercase", "make uppercase", "all capitals", "capitalize all":
            return .uppercase

        case "lowercase", "lowercase that", "make it lowercase", "make lowercase", "all lowercase":
            return .lowercase

        case "title case", "capitalize words", "titlecase", "capitalize":
            return .titleCase

        case "fix grammar", "fix spelling", "clean up", "grammar check", "fix grammar and spelling", "correct grammar", "fix the grammar":
            return .fixGrammar

        default:
            return nil
        }
    }

    public func applySelectionEdit(_ edit: VoiceSelectionEdit, to text: String) -> String {
        switch edit {
        case .uppercase:
            return text.uppercased()

        case .lowercase:
            return text.lowercased()

        case .titleCase:
            return text.capitalized

        case .bulletPoints:
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if lines.count > 1 {
                return lines.map { "• " + $0.replacingOccurrences(of: "^[•\\-*\\d.]+\\s*", with: "", options: .regularExpression) }.joined(separator: "\n")
            } else {
                let sentences = text.components(separatedBy: ". ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return sentences.map { "• " + $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.joined(separator: "\n")
            }

        case .shorter:
            var trimmed = text
            let fillers = [
                "\\b(basically|literally|actually|honestly|in order to|as a matter of fact|needless to say)\\b\\s*",
                "\\b(at the end of the day|to be honest|for the most part)\\b\\s*"
            ]
            for pattern in fillers {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    trimmed = regex.stringByReplacingMatches(in: trimmed, options: [], range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed), withTemplate: "")
                }
            }
            return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)

        case .fixGrammar:
            var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = result.first {
                result = String(first).uppercased() + String(result.dropFirst())
            }
            if !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") {
                result += "."
            }
            return result
        }
    }

    // MARK: - In-line Self-Corrections ("scratch that", "actually", "no, ...")

    public func processInlineSelfCorrections(_ input: String) -> String {
        var text = input

        // 1. "scratch that" / "never mind" drop pattern
        let dropCues = [
            "(?i)\\b.+?\\b(?:,\\s*)?(?:scratch that|never mind|nevermind|forget that)\\b[,:]?\\s*"
        ]
        for pattern in dropCues {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            }
        }

        // 2. Direct word corrections: "X, no, Y", "X, actually Y", "X, rather Y"
        let correctionPatterns = [
            "(?i)\\b(\\w+)(?:\\s*,?\\s*)(?:no(?: wait)?|actually|rather|i mean)[,:]?\\s+(\\w+)"
        ]
        for pattern in correctionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$2")
            }
        }

        return text
    }

    // MARK: - In-line Navigation Commands ("new line", "new paragraph")

    public func processInlineNavigationCommands(_ input: String) -> String {
        var text = input

        // Spoken "new paragraph" -> two newlines
        if let regex = try? NSRegularExpression(pattern: "(?i)\\s*\\b(?:new|next)\\s+paragraph\\b\\s*", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\n\n")
        }

        // Spoken "new line" / "next line" -> one newline
        if let regex = try? NSRegularExpression(pattern: "(?i)\\s*\\b(?:new|next)\\s+line\\b\\s*", options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "\n")
        }

        return text
    }

    // MARK: - In-line Case Cues ("uppercase that", "all caps that")

    public func processInlineCaseCommands(_ input: String) -> String {
        var text = input

        // Patterns like "urgent uppercase that" -> "URGENT"
        let upperPattern = "(?i)\\b(\\w+)\\s+(?:uppercase that|all caps that|make that uppercase)\\b"
        if let regex = try? NSRegularExpression(pattern: upperPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
            for match in matches.reversed() {
                if let phraseRange = Range(match.range(at: 1), in: text),
                   let fullRange = Range(match.range(at: 0), in: text) {
                    let phrase = String(text[phraseRange]).uppercased()
                    text.replaceSubrange(fullRange, with: phrase)
                }
            }
        }

        return text
    }
}

// MARK: - System Action Performer (Dispatches shortcuts to active application)

public final class VoiceActionPerformer {
    public static func performAction(
        _ action: VoiceSystemAction,
        on targetApp: NSRunningApplication?,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            completion?(false)
            return
        }

        if action == .scratchThat {
            completion?(true)
            return
        }

        // Activate target application first
        if let app = targetApp {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }

        // Give macOS WindowServer 110ms to switch focus to the target app before posting keystrokes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            DispatchQueue.global(qos: .userInteractive).async {
                let pid = targetApp?.processIdentifier
                let success: Bool

                switch action {
                case .selectAll:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand, source: source, pid: pid)
                case .undo:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_ANSI_Z), flags: .maskCommand, source: source, pid: pid)
                case .redo:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_ANSI_Z), flags: [.maskCommand, .maskShift], source: source, pid: pid)
                case .copy:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand, source: source, pid: pid)
                case .paste:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand, source: source, pid: pid)
                case .cut:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_ANSI_X), flags: .maskCommand, source: source, pid: pid)
                case .deleteLine:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_Delete), flags: .maskCommand, source: source, pid: pid)
                case .delete:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_Delete), flags: [], source: source, pid: pid)
                case .newLine:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_Return), flags: [], source: source, pid: pid)
                case .newParagraph:
                    _ = sendShortcutWithHold(keyCode: CGKeyCode(kVK_Return), flags: [], source: source, pid: pid)
                    usleep(40_000)
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_Return), flags: [], source: source, pid: pid)
                case .save:
                    success = sendShortcutWithHold(keyCode: CGKeyCode(kVK_ANSI_S), flags: .maskCommand, source: source, pid: pid)
                case .scratchThat:
                    success = true
                }

                DispatchQueue.main.async {
                    completion?(success)
                }
            }
        }
    }

    public static func sendShortcutWithHold(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        source: CGEventSource,
        pid: pid_t?
    ) -> Bool {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags

        // Post to target process if known
        if let pid = pid {
            down.postToPid(pid)
        }
        down.post(tap: .cghidEventTap)

        // Brief hold (25ms) so application run loops receive the key press
        usleep(25_000)

        if let pid = pid {
            up.postToPid(pid)
        }
        up.post(tap: .cghidEventTap)

        return true
    }
}

// MARK: - Accessibility Helper with Clipboard Fallback

public enum AccessibilitySelectionHelper {
    public static func getSelectedText(targetApp: NSRunningApplication? = nil) -> String? {
        // 1. First attempt native macOS Accessibility API
        if let text = getSelectedTextViaAccessibility(), !text.isEmpty {
            return text
        }

        // 2. Clipboard Fallback (Universal for Electron, Chrome, Cursor, Slack)
        guard let app = targetApp ?? NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        return getSelectedTextViaClipboardFallback(targetApp: app)
    }

    private static func getSelectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp,
              CFGetTypeID(app) == AXUIElementGetTypeID() else {
            return nil
        }
        let appElement = app as! AXUIElement

        var focusedUIElement: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement) == .success,
              let element = focusedUIElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return nil
        }
        let uiElement = element as! AXUIElement

        var selectedTextValue: AnyObject?
        if AXUIElementCopyAttributeValue(uiElement, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
           let text = selectedTextValue as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    private static func getSelectedTextViaClipboardFallback(targetApp: NSRunningApplication) -> String? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount

        // Send ⌘C to target app
        _ = VoiceActionPerformer.sendShortcutWithHold(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            source: source,
            pid: targetApp.processIdentifier
        )

        // Wait up to 80ms for pasteboard changeCount to update
        for _ in 0..<8 {
            usleep(10_000) // 10ms
            if pasteboard.changeCount != previousChangeCount {
                if let copied = pasteboard.string(forType: .string), !copied.isEmpty {
                    return copied
                }
                break
            }
        }

        return nil
    }
}
