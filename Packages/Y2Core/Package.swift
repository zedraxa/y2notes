// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "Y2Core",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Y2Core", targets: ["Y2Core"])
    ],
    targets: [
        .target(
            name: "Y2Core",
            path: "Sources/Y2Core"
        ),
        .testTarget(
            name: "Y2CoreTests",
            dependencies: ["Y2Core"],
            path: "Tests/Y2CoreTests"
        )
    ]
)
