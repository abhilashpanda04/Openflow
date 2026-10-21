import Foundation
import AppKit
import PDFKit

public struct FileTextExtractor {
    public enum ExtractorError: LocalizedError {
        case unsupportedFormat(String)
        case emptyContent
        case readFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported file extension: .\(ext). Please select a .txt, .pdf, .md, or .rtf file."
            case .emptyContent:
                return "The selected document contains no readable text."
            case .readFailed(let reason):
                return "Failed to read document: \(reason)"
            }
        }
    }

    /// Extracts plain text content from a .txt, .md, .pdf, or .rtf file.
    public static func extractText(from url: URL) throws -> (title: String, text: String) {
        let ext = url.pathExtension.lowercased()
        let filename = url.deletingPathExtension().lastPathComponent
        var extractedText = ""

        switch ext {
        case "pdf":
            guard let pdf = PDFDocument(url: url) else {
                throw ExtractorError.readFailed("Could not open PDF document.")
            }
            var pageStrings: [String] = []
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i), let text = page.string {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        pageStrings.append(trimmed)
                    }
                }
            }
            extractedText = pageStrings.joined(separator: "\n\n")

        case "txt", "md", "markdown", "text":
            do {
                extractedText = try String(contentsOf: url, encoding: .utf8)
            } catch {
                // Fallback to ASCII or ISO-Latin-1 if UTF-8 fails
                if let fallback = try? String(contentsOf: url, encoding: .ascii) {
                    extractedText = fallback
                } else if let fallback = try? String(contentsOf: url, encoding: .isoLatin1) {
                    extractedText = fallback
                } else {
                    throw ExtractorError.readFailed(error.localizedDescription)
                }
            }

        case "rtf":
            do {
                let attrStr = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
                extractedText = attrStr.string
            } catch {
                throw ExtractorError.readFailed(error.localizedDescription)
            }

        default:
            throw ExtractorError.unsupportedFormat(ext)
        }

        let cleanText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            throw ExtractorError.emptyContent
        }

        return (title: filename, text: cleanText)
    }
}
