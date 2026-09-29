// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "deskew-swift",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DeskewCore", targets: ["DeskewCore"]),
        .executable(name: "deskew", targets: ["DeskewCLI"])
    ],
    targets: [
        .target(name: "DeskewCore"),
        .executableTarget(name: "DeskewCLI", dependencies: ["DeskewCore"]),
        .testTarget(name: "DeskewCoreTests", dependencies: ["DeskewCore"])
    ]
)
