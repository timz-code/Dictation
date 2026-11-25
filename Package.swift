// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dictation",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Dictation", targets: ["Dictation"])],
    targets: [
        .target(name: "DictationCore", resources: [.process("Resources")]),
        .executableTarget(name: "Dictation", dependencies: ["DictationCore"]),
        .testTarget(name: "DictationCoreTests", dependencies: ["DictationCore"]),
        .testTarget(name: "DictationTests", dependencies: ["Dictation"])
    ]
)
