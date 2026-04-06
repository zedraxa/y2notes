// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "Y2Engine",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Y2Engine", targets: ["Y2Engine"])
    ],
    dependencies: [
        .package(path: "../Y2Core")
    ],
    targets: [
        .target(
            name: "Y2Engine",
            dependencies: ["Y2Core"],
            path: "Sources/Y2Engine"
        ),
        .testTarget(
            name: "Y2EngineTests",
            dependencies: ["Y2Engine"],
            path: "Tests/Y2EngineTests"
        )
    ]
)
