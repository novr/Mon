// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Mon",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "Mon", targets: ["BadgeIcon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "BadgeIcon",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
