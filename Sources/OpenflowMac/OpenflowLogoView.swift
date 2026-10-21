import AppKit
import SwiftUI

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

// MARK: - Openflow Logo View
/// Pixel-perfect vector implementation of the official Openflow brand logo (`assets/logo.svg`).
public struct OpenflowLogoView: View {
    public let size: CGFloat
    public let cornerRadius: CGFloat?

    public init(size: CGFloat = 32, cornerRadius: CGFloat? = nil) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let s = size / 512.0
        let effectiveRadius = cornerRadius ?? (104.0 * s)

        ZStack {
            // 1. Deep Navy to Cyan Gradient Background
            RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "0A2540"),
                            Color(hex: "0E7490")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: max(0.5, 1.5 * s))
                )

            // 2. Subtle Circular Ambient Glow
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 296.0 * s, height: 296.0 * s)

            // 3. Flowing Audio Sine Wave
            Path { path in
                path.move(to: CGPoint(x: 108 * s, y: 256 * s))
                path.addCurve(
                    to: CGPoint(x: 204 * s, y: 184 * s),
                    control1: CGPoint(x: 140 * s, y: 208 * s),
                    control2: CGPoint(x: 172 * s, y: 184 * s)
                )
                path.addCurve(
                    to: CGPoint(x: 284 * s, y: 328 * s),
                    control1: CGPoint(x: 236 * s, y: 184 * s),
                    control2: CGPoint(x: 252 * s, y: 328 * s)
                )
                path.addCurve(
                    to: CGPoint(x: 404 * s, y: 152 * s),
                    control1: CGPoint(x: 316 * s, y: 328 * s),
                    control2: CGPoint(x: 348 * s, y: 208 * s)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(hex: "F8FAFC"),
                        Color(hex: "BAE6FD")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(
                    lineWidth: max(1.5, 24.0 * s),
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            // 4. Accent Wave Particle Nodes
            Circle()
                .fill(Color(hex: "F8FAFC"))
                .frame(width: max(2.5, 32.0 * s), height: max(2.5, 32.0 * s))
                .position(x: 156.0 * s, y: 256.0 * s)

            Circle()
                .fill(Color(hex: "E0F2FE"))
                .frame(width: max(2.5, 32.0 * s), height: max(2.5, 32.0 * s))
                .position(x: 356.0 * s, y: 208.0 * s)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Openflow Menu Bar Icon Helper
public enum OpenflowLogoHelper {
    /// Creates a crisp, vector template NSImage for the macOS menu bar matching the Openflow wave brand.
    public static func makeMenuBarIcon(isRecording: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()

            if isRecording {
                // Recording mode: distinctive audio wave with active mic dot
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 2.0, y: 9.0))
                path.addCurve(to: CGPoint(x: 6.0, y: 14.5), control1: CGPoint(x: 3.5, y: 11.5), control2: CGPoint(x: 4.8, y: 14.5))
                path.addCurve(to: CGPoint(x: 11.0, y: 3.5), control1: CGPoint(x: 7.8, y: 14.5), control2: CGPoint(x: 9.2, y: 3.5))
                path.addCurve(to: CGPoint(x: 16.0, y: 9.0), control1: CGPoint(x: 12.8, y: 3.5), control2: CGPoint(x: 14.5, y: 6.5))

                context.addPath(path)
                context.setLineWidth(1.8)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setStrokeColor(NSColor.black.cgColor)
                context.strokePath()

                // Pulsing dot
                context.setFillColor(NSColor.black.cgColor)
                context.fillEllipse(in: CGRect(x: 12.5, y: 11.5, width: 4.0, height: 4.0))
            } else {
                // Idle / Normal mode: Openflow smooth wave
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 2.0, y: 9.0))
                path.addCurve(to: CGPoint(x: 6.2, y: 14.0), control1: CGPoint(x: 3.5, y: 11.0), control2: CGPoint(x: 4.8, y: 14.0))
                path.addCurve(to: CGPoint(x: 11.8, y: 4.0), control1: CGPoint(x: 8.0, y: 14.0), control2: CGPoint(x: 9.6, y: 4.0))
                path.addCurve(to: CGPoint(x: 16.0, y: 9.0), control1: CGPoint(x: 13.5, y: 4.0), control2: CGPoint(x: 14.8, y: 7.0))

                context.addPath(path)
                context.setLineWidth(1.8)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setStrokeColor(NSColor.black.cgColor)
                context.strokePath()

                // Two subtle wave nodes
                context.setFillColor(NSColor.black.cgColor)
                context.fillEllipse(in: CGRect(x: 4.5, y: 8.0, width: 2.0, height: 2.0))
                context.fillEllipse(in: CGRect(x: 11.5, y: 8.0, width: 2.0, height: 2.0))
            }

            context.restoreGState()
            return true
        }

        image.isTemplate = true
        return image
    }
}
