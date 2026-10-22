import Foundation
import AppKit
import PDFKit

public struct FileTextExtractor {
    public static let maxFileSizeBytes: Int64 = 50 * 1024 * 1024 // 50 MB
    public static let maxPdfPages: Int = 1000

    public enum ExtractorError: LocalizedError {
        case unsupportedFormat(String)
        case emptyContent
        case fileTooLarge(Int64, Int64)
        case tooManyPages(Int, Int)
        case readFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported file extension: .\(ext). Please select a .txt, .pdf, .md, or .rtf file."
            case .emptyContent:
                return "The selected document contains no readable text."
            case .fileTooLarge(let size, let max):
                let sizeMB = Double(size) / (1024 * 1024)
                let maxMB = Double(max) / (1024 * 1024)
                return String(format: "File is too large (%.1f MB). Maximum allowed is %.0f MB.", sizeMB, maxMB)
            case .tooManyPages(let pages, let max):
                return "PDF has too many pages (\(pages)). Maximum allowed is \(max) pages."
            case .readFailed(let reason):
                return "Failed to read document: \(reason)"
            }
        }
    }

    /// Extracts plain text content from a .txt, .md, .pdf, or .rtf file with defensive size bounds.
    public static func extractText(from url: URL) throws -> (title: String, text: String) {
        // Check file size defensively
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? Int64, fileSize > maxFileSizeBytes {
            throw ExtractorError.fileTooLarge(fileSize, maxFileSizeBytes)
        }

        let ext = url.pathExtension.lowercased()
        let filename = url.deletingPathExtension().lastPathComponent
        var extractedText = ""

        switch ext {
        case "pdf":
            guard let pdf = PDFDocument(url: url) else {
                throw ExtractorError.readFailed("Could not open PDF document.")
            }
            if pdf.pageCount > maxPdfPages {
                throw ExtractorError.tooManyPages(pdf.pageCount, maxPdfPages)
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
