// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "Y2GoogleDrive",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Y2GoogleDrive", targets: ["Y2GoogleDrive"])
    ],
    dependencies: [
        .package(path: "../Y2Core")
    ],
    targets: [
        .target(
            name: "Y2GoogleDrive",
            dependencies: ["Y2Core"],
            path: "Sources/Y2GoogleDrive"
        ),
        .testTarget(
            name: "Y2GoogleDriveTests",
            dependencies: ["Y2GoogleDrive"],
            path: "Tests/Y2GoogleDriveTests"
        )
    ]
)
