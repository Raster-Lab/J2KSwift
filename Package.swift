// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "J2KSwift",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
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
            name: "J2KMetal",
            targets: ["J2KMetal"]),
        .library(
            name: "J2KVulkan",
            targets: ["J2KVulkan"]),
        .library(
            name: "JPIP",
            targets: ["JPIP"]),
        .library(
            name: "J2K3D",
            targets: ["J2K3D"]),
        .executable(
            name: "j2k",
            targets: ["J2KCLI"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "J2KCore"),
        .target(
            name: "J2KCodec",
            dependencies: ["J2KCore"]),
        .target(
            name: "J2KAccelerate",
            dependencies: ["J2KCore", "J2KCodec"]),
        .target(
            name: "J2KFileFormat",
            dependencies: ["J2KCore", "J2KCodec"]),
        .target(
            name: "J2KMetal",
            dependencies: ["J2KCore"]),
        .target(
            name: "J2KVulkan",
            dependencies: ["J2KCore"]),
        .target(
            name: "JPIP",
            dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat", "J2K3D"]),
        .target(
            name: "J2K3D",
            dependencies: ["J2KCore"]),
        .testTarget(
            name: "J2KCoreTests",
            dependencies: ["J2KCore", "J2KFileFormat"]),
        .testTarget(
            name: "J2KCodecTests",
            dependencies: ["J2KCodec", "J2KFileFormat", "J2KAccelerate"]),
        .testTarget(
            name: "J2KAccelerateTests",
            dependencies: ["J2KAccelerate"]),
        .testTarget(
            name: "J2KFileFormatTests",
            dependencies: ["J2KFileFormat"]),
        .testTarget(
            name: "J2KMetalTests",
            dependencies: ["J2KMetal"]),
        .testTarget(
            name: "J2KVulkanTests",
            dependencies: ["J2KVulkan"]),
        .testTarget(
            name: "JPIPTests",
            dependencies: ["JPIP", "J2KCodec"]),
        .testTarget(
            name: "J2KCLITests",
            dependencies: ["J2KCore"]),
        .testTarget(
            name: "JP3DTests",
            dependencies: ["J2K3D", "J2KCore", "JPIP"]),
        .testTarget(
            name: "J2KComplianceTests",
            dependencies: ["J2K3D", "J2KCore"]),
        .executableTarget(
            name: "J2KCLI",
            dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat"],
            path: "Sources/J2KCLI",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]),
    ]
)
