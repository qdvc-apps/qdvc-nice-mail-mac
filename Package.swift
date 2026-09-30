// swift-tools-version: 5.10
//
// QDVC Nice Mail for macOS — a native SwiftUI app for writing emails faster:
// an emoji picker with favourites, reusable phrases, an assembled plaintext
// signature and a Note to Self .eml writer. Its data lives in a plain-text
// workspace folder (see docs/FILE_FORMAT.md) that it shares with the
// Python/GTK edition of QDVC Nice Mail, but neither needs the other.
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed .app, no Apple account needed)

import PackageDescription

var products: [Product] = [
    .library(name: "NiceMailCore", targets: ["NiceMailCore"]),
]
var targets: [Target] = [
    // Pure model layer: Foundation only, no AppKit/SwiftUI, unit-testable.
    .target(name: "NiceMailCore"),
    .testTarget(
        name: "NiceMailCoreTests",
        dependencies: ["NiceMailCore"],
        resources: [.copy("Fixtures")]
    ),
]

#if os(macOS)
// The SwiftUI/AppKit front-end. Declared on macOS only, so the core and its
// tests also build with a Linux Swift toolchain (docs/MAINTENANCE.md §5).
products.insert(.executable(name: "QDVCNiceMail", targets: ["QDVCNiceMail"]), at: 0)
targets.insert(.executableTarget(name: "QDVCNiceMail", dependencies: ["NiceMailCore"]), at: 1)
#endif

let package = Package(
    name: "QDVCNiceMail",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
