// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "Y2Components",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Y2Components", targets: ["Y2Components"])
    ],
    dependencies: [
        .package(path: "../Y2Core"),
        .package(path: "../Y2Engine")
    ],
    targets: [
        .target(
            name: "Y2Components",
            dependencies: ["Y2Core", "Y2Engine"],
            path: "Sources/Y2Components"
        ),
        .testTarget(
            name: "Y2ComponentsTests",
            dependencies: ["Y2Components"],
            path: "Tests/Y2ComponentsTests"
        )
    ]
)
