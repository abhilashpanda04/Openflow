// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Openflow",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Openflow", targets: ["QuickASRMac"]),
    ],
    targets: [
        .executableTarget(
            name: "QuickASRMac",
            path: "Sources/QuickASRMac"
        ),
    ]
)
