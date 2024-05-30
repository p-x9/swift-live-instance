// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LiveInstance",
    products: [
        .library(
            name: "LiveInstance",
            targets: ["LiveInstance"]
        ),
    ],
    targets: [
        .target(
            name: "LiveInstance"
        ),
        .testTarget(
            name: "LiveInstanceTests",
            dependencies: ["LiveInstance"]
        ),
    ]
)
