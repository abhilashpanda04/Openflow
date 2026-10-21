import SwiftUI
import AppKit

private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

public struct ReaderMiniPlayerView: View {
    @ObservedObject public var manager: ReaderManager = .shared
    public var onClose: () -> Void = {}

    public init(manager: ReaderManager = .shared, onClose: @escaping () -> Void = {}) {
        self.manager = manager
        self.onClose = onClose
    }

    private let speedOptions: [Float] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0]

    public var body: some View {
        VStack(spacing: 8) {
            // Header Bar: Status & Controls
            HStack(spacing: 10) {
                // Animated Speaker / Sound icon
                ZStack {
                    Circle()
                        .fill(manager.state == .playing ? Color(hex: "0284c7").opacity(0.2) : Color.white.opacity(0.08))
                        .frame(width: 28, height: 28)

                    Image(systemName: manager.state == .playing ? "speaker.wave.3.fill" : (manager.state == .paused ? "pause.fill" : "book.fill"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(manager.state == .playing ? Color(hex: "38bdf8") : Color.secondary)
                }

                // Progress & Sentence Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(manager.documentTitle ?? (manager.state == .playing ? "Reading Aloud" : (manager.state == .paused ? "Paused" : "Book Reader")))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        Text(manager.engineKind == .kokoro ? "Kokoro AI" : "Apple")
                            .font(.system(size: 8.5, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: "0284c7").opacity(0.18))
                            .foregroundStyle(Color(hex: "38bdf8"))
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                        if !manager.sentences.isEmpty {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)

                            Text("\(manager.currentSentenceIndex + 1)/\(manager.sentences.count)")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                        }
                    }

                    if let current = manager.currentSentence {
                        Text(current.text)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("Ready to read books, articles, or clipboard text")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                // Speed Menu
                Menu {
                    ForEach(speedOptions, id: \.self) { speed in
                        let title = speed == manager.playbackRate ? String(format: "%.2fx ✓", speed) : String(format: "%.2fx", speed)
                        Button(title) {
                            manager.playbackRate = speed
                        }
                    }
                } label: {
                    Text(String(format: "%.1fx", manager.playbackRate))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Voice Menu
                Menu {
                    ForEach(Array(manager.availableVoices.prefix(15)), id: \.id) { voice in
                        let isSelected = voice.id == manager.currentVoice?.id
                        let title = isSelected ? "\(voice.displayName) ✓" : voice.displayName
                        Button(title) {
                            manager.setVoice(voice)
                        }
                    }
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .medium))
                        .padding(6)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Play / Pause Button
                Button {
                    manager.togglePlayPause()
                } label: {
                    Image(systemName: manager.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(Color(hex: "0284c7"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Close Button
                Button {
                    manager.stop()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .padding(5)
                }
                .buttonStyle(.plain)
            }

            // Progress Bar
            if !manager.sentences.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 3)

                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: "0284c7"), Color(hex: "38bdf8")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: max(0, min(geo.size.width * CGFloat(manager.progress), geo.size.width)), height: 3)
                    }
                }
                .frame(height: 3)
            }

            // Quick Nav Controls
            HStack(spacing: 12) {
                Button {
                    manager.skipBackward()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 9))
                        Text("Prev Sentence")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(manager.sentences.isEmpty || manager.currentSentenceIndex == 0)

                Spacer()

                Button {
                    manager.readClipboard()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 9))
                        Text("Clipboard")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color(hex: "38bdf8"))
                }
                .buttonStyle(.plain)

                Button {
                    manager.openFilePicker()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text("Open File...")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color(hex: "38bdf8"))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    manager.skipForward()
                } label: {
                    HStack(spacing: 3) {
                        Text("Next Sentence")
                            .font(.system(size: 10))
                        Image(systemName: "forward.fill")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(manager.sentences.isEmpty || manager.currentSentenceIndex >= manager.sentences.count - 1)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
    }
}
