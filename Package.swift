// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "J2KSwift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "J2KCore",
            targets: ["J2KCore"]),
        .library(
            name: "J2KCodec",
            targets: ["J2KCodec"]),
        .library(
            name: "J2KAccelerate",
            targets: ["J2KAccelerate"]),
        .library(
            name: "J2KFileFormat",
            targets: ["J2KFileFormat"]),
        .library(
            name: "JPIP",
            targets: ["JPIP"]),
        .executable(
            name: "j2k",
            targets: ["J2KCLI"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "J2KCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency")
            ]),
        .target(
            name: "J2KCodec",
            dependencies: ["J2KCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency")
            ]),
        .target(
            name: "J2KAccelerate",
            dependencies: ["J2KCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency")
            ]),
        .target(
            name: "J2KFileFormat",
            dependencies: ["J2KCore", "J2KCodec"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency")
            ]),
        .target(
            name: "JPIP",
            dependencies: ["J2KCore", "J2KFileFormat"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency")
            ]),
        .testTarget(
            name: "J2KCoreTests",
            dependencies: ["J2KCore", "J2KFileFormat"]),
        .testTarget(
            name: "J2KCodecTests",
            dependencies: ["J2KCodec"]),
        .testTarget(
            name: "J2KAccelerateTests",
            dependencies: ["J2KAccelerate"]),
        .testTarget(
            name: "J2KFileFormatTests",
            dependencies: ["J2KFileFormat"]),
        .testTarget(
            name: "JPIPTests",
            dependencies: ["JPIP"]),
        .executableTarget(
            name: "J2KCLI",
            dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat"],
            path: "Sources/J2KCLI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-parse-as-library"])
            ]),
    ]
)
