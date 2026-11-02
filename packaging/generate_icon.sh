#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_DIR="$ROOT_DIR/packaging/icon"
ICONSET_DIR="$ICON_DIR/Openflow.iconset"
ICNS_PATH="$ICON_DIR/Openflow.icns"

mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func makeRoundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
    return path
}

func saveIcon(size: Int, name: String) throws {
    let width = size
    let height = size
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "OpenflowIcon", code: 1)
    }

    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)

    let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    context.fill(rect)

    let s = CGFloat(size) / 512.0
    let baseRect = CGRect(x: 32.0 * s, y: 32.0 * s, width: 448.0 * s, height: 448.0 * s)
    let radius = 104.0 * s

    // 1. Official Openflow Gradient: #0A2540 to #0E7490
    let gradientColors = [
        CGColor(red: 10.0 / 255.0, green: 37.0 / 255.0, blue: 64.0 / 255.0, alpha: 1.0),
        CGColor(red: 14.0 / 255.0, green: 116.0 / 255.0, blue: 144.0 / 255.0, alpha: 1.0),
    ] as CFArray
    let gradientLocations: [CGFloat] = [0, 1]
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations) else {
        throw NSError(domain: "OpenflowIcon", code: 2)
    }

    let basePath = makeRoundedRectPath(baseRect, radius: radius)
    context.saveGState()
    context.addPath(basePath)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 64.0 * s, y: 448.0 * s),
        end: CGPoint(x: 448.0 * s, y: 64.0 * s),
        options: []
    )

    // 2. Ambient Circular Halo
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    context.fillEllipse(in: CGRect(x: (256.0 - 148.0) * s, y: (256.0 - 148.0) * s, width: 296.0 * s, height: 296.0 * s))
    context.restoreGState()

    // 3. Subtle Squircle Edge Highlight
    context.addPath(basePath)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
    context.setLineWidth(max(0.5, 1.5 * s))
    context.strokePath()

    // 4. Flowing Audio Sine Wave Path (Exact logo.svg vector)
    let waveColors = [
        CGColor(red: 248.0 / 255.0, green: 250.0 / 255.0, blue: 252.0 / 255.0, alpha: 1.0), // #F8FAFC
        CGColor(red: 186.0 / 255.0, green: 230.0 / 255.0, blue: 253.0 / 255.0, alpha: 1.0), // #BAE6FD
    ] as CFArray
    guard let waveGrad = CGGradient(colorsSpace: colorSpace, colors: waveColors, locations: gradientLocations) else {
        throw NSError(domain: "OpenflowIcon", code: 2)
    }

    let wavePath = CGMutablePath()
    wavePath.move(to: CGPoint(x: 108.0 * s, y: 256.0 * s))
    wavePath.addCurve(
        to: CGPoint(x: 204.0 * s, y: 184.0 * s),
        control1: CGPoint(x: 140.0 * s, y: 208.0 * s),
        control2: CGPoint(x: 172.0 * s, y: 184.0 * s)
    )
    wavePath.addCurve(
        to: CGPoint(x: 284.0 * s, y: 328.0 * s),
        control1: CGPoint(x: 236.0 * s, y: 184.0 * s),
        control2: CGPoint(x: 252.0 * s, y: 328.0 * s)
    )
    wavePath.addCurve(
        to: CGPoint(x: 404.0 * s, y: 152.0 * s),
        control1: CGPoint(x: 316.0 * s, y: 328.0 * s),
        control2: CGPoint(x: 348.0 * s, y: 208.0 * s)
    )

    context.saveGState()
    context.addPath(wavePath)
    context.setLineWidth(max(1.5, 24.0 * s))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        waveGrad,
        start: CGPoint(x: 108.0 * s, y: 256.0 * s),
        end: CGPoint(x: 404.0 * s, y: 256.0 * s),
        options: []
    )
    context.restoreGState()

    // 5. Sound Node Particles (cx=156, cx=356 from logo.svg)
    context.setFillColor(CGColor(red: 248.0 / 255.0, green: 250.0 / 255.0, blue: 252.0 / 255.0, alpha: 1.0))
    context.fillEllipse(in: CGRect(x: (156.0 - 16.0) * s, y: (256.0 - 16.0) * s, width: 32.0 * s, height: 32.0 * s))

    context.setFillColor(CGColor(red: 224.0 / 255.0, green: 242.0 / 255.0, blue: 254.0 / 255.0, alpha: 1.0))
    context.fillEllipse(in: CGRect(x: (356.0 - 16.0) * s, y: (208.0 - 16.0) * s, width: 32.0 * s, height: 32.0 * s))

    guard let image = context.makeImage() else {
        throw NSError(domain: "OpenflowIcon", code: 3)
    }

    let destinationURL = outputDirectory.appendingPathComponent(name) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(destinationURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "OpenflowIcon", code: 4)
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "OpenflowIcon", code: 5)
    }
}

let outputs: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, fileName) in outputs {
    try saveIcon(size: size, name: fileName)
}
SWIFT

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Generated icon: $ICNS_PATH"
