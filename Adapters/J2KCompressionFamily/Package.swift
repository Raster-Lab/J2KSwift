// swift-tools-version: 6.2
//
// J2KCompressionFamily — the CompressionFamily protocol conformances for
// J2KSwift's public types, kept in a package of their own.
//
// Contract 0.8.0 §4 of the Swift Image Compression Suite requires the J2KSwift
// core library to resolve without CompressionFamily in its package graph, so
// that the codec can migrate into SwiftJ2K alone (POL-01, POL-02). The
// conformances themselves stay available to predecessor consumers under
// POL-04; they were not deleted, they moved here.
//
// This package depends on the J2KSwift package at the repository root by
// path. A consumer that needs the conformances by URL needs this directory
// published as its own repository; nothing here assumes that has happened.

import PackageDescription

let package = Package(
    name: "J2KCompressionFamily",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "J2KCompressionFamily",
            targets: ["J2KCompressionFamily"]),
    ],
    dependencies: [
        .package(name: "J2KSwift", path: "../.."),
        .package(
            url: "https://github.com/Raster-Lab/CompressionFamily.git",
            from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "J2KCompressionFamily",
            dependencies: [
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2KCodec", package: "J2KSwift"),
                .product(name: "CompressionFamily", package: "CompressionFamily"),
            ]),
        .testTarget(
            name: "J2KCompressionFamilyTests",
            dependencies: [
                "J2KCompressionFamily",
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2KCodec", package: "J2KSwift"),
                .product(name: "CompressionFamily", package: "CompressionFamily"),
            ]),
    ]
)
