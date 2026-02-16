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

    let inset = CGFloat(size) * 0.08
    let baseRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(size) * 0.23

    let gradientColors = [
        CGColor(red: 0.07, green: 0.20, blue: 0.42, alpha: 1.0),
        CGColor(red: 0.04, green: 0.12, blue: 0.26, alpha: 1.0),
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
        start: CGPoint(x: baseRect.midX, y: baseRect.maxY),
        end: CGPoint(x: baseRect.midX, y: baseRect.minY),
        options: []
    )
    context.restoreGState()

    context.addPath(basePath)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    context.setLineWidth(max(1.0, CGFloat(size) * 0.015))
    context.strokePath()

    let left = baseRect.minX + baseRect.width * 0.17
    let right = baseRect.maxX - baseRect.width * 0.17
    let centerY = baseRect.midY
    let amp = baseRect.height * 0.20
    let segments = 6

    context.beginPath()
    context.move(to: CGPoint(x: left, y: centerY))
    for step in 1...segments {
        let t = CGFloat(step) / CGFloat(segments)
        let x = left + (right - left) * t
        let y = centerY + sin(t * .pi * 2.0) * amp * 0.75
        context.addLine(to: CGPoint(x: x, y: y))
    }
    context.setLineWidth(max(2.0, CGFloat(size) * 0.075))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    context.strokePath()

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
