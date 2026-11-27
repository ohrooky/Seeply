// swift-tools-version: 5.9
import PackageDescription

// This package tests the platform-independent core. The native application and
// ImageIO integration tests are still built with Seeply.xcodeproj on macOS.
let package = Package(
    name: "SeeplyCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SeeplyCore", targets: ["SeeplyCore"])],
    targets: [
        .target(name: "SeeplyCore", path: "Seeply/Core"),
        .testTarget(name: "SeeplyCoreTests", dependencies: ["SeeplyCore"], path: "SeeplyTests",
                    exclude: ["Fixtures", "ImageIOTests.swift", "WorkQueueTests.swift", "FileTypeSessionTests.swift"])
    ]
)
