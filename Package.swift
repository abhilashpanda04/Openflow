// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Openflow",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Openflow", targets: ["OpenflowMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        .executableTarget(
            name: "OpenflowMac",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/OpenflowMac"
        ),
        .testTarget(
            name: "OpenflowMacTests",
            dependencies: ["OpenflowMac"],
            path: "Tests/OpenflowMacTests"
        ),
    ]
)
