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
        .target(name: "DeskewImageIO", dependencies: ["DeskewCore"]),
        .executableTarget(name: "DeskewCLI", dependencies: ["DeskewCore", "DeskewImageIO"]),
        .testTarget(name: "DeskewCoreTests", dependencies: ["DeskewCore", "DeskewImageIO"])
    ]
)
