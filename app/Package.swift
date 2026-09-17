// swift-tools-version: 6.0
import PackageDescription

// Tests use Swift Testing. With full Xcode, `swift test` works as is. With Command Line
// Tools only, Testing.framework sits outside SwiftPM's default search paths: run
// `scripts/test.sh`, which adds the needed -F / rpath flags.
let package = Package(
    name: "ZeroCortisol",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZeroCortisolCore", targets: ["ZeroCortisolCore"]),
        .executable(name: "ZeroCortisol", targets: ["ZeroCortisol"]),
    ],
    targets: [
        .target(
            name: "ZeroCortisolCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "ZeroCortisol",
            dependencies: ["ZeroCortisolCore"]
        ),
        .testTarget(
            name: "ZeroCortisolCoreTests",
            dependencies: ["ZeroCortisolCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
