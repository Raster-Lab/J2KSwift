// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// CompressionFamily — shared protocol surface for the Swift
// compression-library family. For local co-development a sibling
// `../CompressionFamily` checkout is used directly; otherwise (CI, and
// any consumer that resolves J2KSwift via `.package(url:)`) it is
// fetched from its public Git repository. The URL form is what makes
// J2KSwift itself URL-consumable as a SwiftPM dependency — see #438.
let compressionFamilyDependency: Package.Dependency = {
    if FileManager.default.fileExists(atPath: "../CompressionFamily/Package.swift") {
        return .package(path: "../CompressionFamily")
    }
    return .package(
        url: "https://github.com/Raster-Lab/CompressionFamily.git",
        from: "1.0.0")
}()

let package = Package(
    name: "J2KSwift",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
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
        .library(
            name: "J2KXS",
            targets: ["J2KXS"]),
        .executable(
            name: "j2k",
            targets: ["J2KCLI"]),
        .executable(
            name: "J2KTestApp",
            targets: ["J2KTestApp"]),
        // v8 Phase 6.3 — XPC daemon (macOS-only). Long-lived
        // process that holds J2KMetalSession warm across CLI
        // invocations, listening on a Mach service registered
        // via launchd. Skeleton scope: ping/pong only; decode
        // RPC + shared-memory marshalling land in Phase 6.4-6.6.
        .executable(
            name: "j2kd",
            targets: ["J2KDaemon"]),
        .library(
            name: "J2KDaemonProtocol",
            targets: ["J2KDaemonProtocol"]),
        .library(
            name: "J2KDaemonCore",
            targets: ["J2KDaemonCore"]),
        .library(
            name: "J2KDaemonClient",
            targets: ["J2KDaemonClient"]),
    ],
    dependencies: [
        compressionFamilyDependency,
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "J2KCore",
            dependencies: [
                .product(name: "CompressionFamily", package: "CompressionFamily"),
            ],
            swiftSettings: [
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release)),
            ]),
        // v9.4-research — custom C+NEON tier-1 HT block encoder. Plain C
        // target with caller-owned-buffer entry point. No global statics,
        // no allocator hits. Default-off behind J2K_NEON_HOT_PATH env var
        // until the in-proc warm A/B clears the v9.3 baseline (see
        // V9_4_NEON_HOT_PATH_RESEARCH.md decision matrix).
        .target(
            name: "J2KCodecNEON",
            path: "Sources/J2KCodecNEON",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(
                    ["-O3", "-fno-exceptions", "-fno-stack-protector",
                     "-fno-math-errno", "-fstrict-aliasing"],
                    .when(configuration: .release)),
            ]),
        .target(
            name: "J2KCodec",
            dependencies: [
                "J2KCore",
                "J2KMetal",
                "J2KCodecNEON",
                .product(name: "CompressionFamily", package: "CompressionFamily"),
            ],
            swiftSettings: [
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release)),
            ]),
        .target(
            name: "J2KAccelerate",
            dependencies: ["J2KCore", "J2KCodec"]),
        .target(
            name: "J2KFileFormat",
            dependencies: ["J2KCore", "J2KCodec"]),
        .target(
            name: "J2KMetal",
            dependencies: ["J2KCore"],
            // The .metal source file is documentation/reference
            // material — regenerated via Scripts/build_metallib.sh
            // and committed as `default.metallib`. Excluded from
            // the build to avoid Xcode auto-discovering it as a
            // Metal source target (which would compile a second
            // metallib and collide with the pre-copied one in iOS
            // Simulator builds).
            //
            // **v8 Phase 6.2 (iOS support)**: dropping
            // `.process("J2KShaders.metal")` from resources +
            // adding it to `exclude:` aligns macOS and iOS Xcode
            // builds with the SwiftPM `swift build` behaviour
            // (both rely on the pre-compiled metallib).
            exclude: ["J2KShaders.metal"],
            resources: [
                // v5.15: ship a pre-compiled `default.metallib`
                // alongside the .metal source. SwiftPM's
                // `.process()` does NOT compile .metal files under
                // `swift build` (only Xcode handles that); checking
                // in a pre-built metallib is the only way to make
                // the runtime metallib path live for SPM consumers.
                // Regenerate via `Scripts/build_metallib.sh` when
                // J2KShaders.metal changes (script verifies parity
                // with the source). The runtime path falls back to
                // source-compiling J2KMetalShaderSource.kernelSource
                // if the metallib is missing or corrupt.
                .copy("default.metallib")
            ]),
        .target(
            name: "J2KVulkan",
            dependencies: ["J2KCore"]),
        .target(
            name: "JPIP",
            dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat", "J2K3D"]),
        .target(
            name: "J2K3D",
            dependencies: ["J2KCore", "J2KCodec"]),
        .target(
            name: "J2KXS",
            dependencies: ["J2KCore"]),
        .testTarget(
            name: "J2KCoreTests",
            dependencies: ["J2KCore", "J2KFileFormat"]),
        .testTarget(
            name: "J2KCodecTests",
            dependencies: [
                "J2KCodec", "J2KFileFormat", "J2KAccelerate", "J2KMetal",
                "J2KCodecNEON",
                .product(name: "CompressionFamily", package: "CompressionFamily"),
            ]),
        .testTarget(
            name: "J2KAccelerateTests",
            dependencies: ["J2KAccelerate"]),
        .testTarget(
            name: "J2KFileFormatTests",
            dependencies: ["J2KFileFormat"]),
        .testTarget(
            name: "J2KMetalTests",
            dependencies: ["J2KMetal", "J2KCodec"]),
        .testTarget(
            name: "J2KVulkanTests",
            dependencies: ["J2KVulkan"]),
        .testTarget(
            name: "JPIPTests",
            dependencies: ["JPIP", "J2KCodec"]),
        .testTarget(
            name: "J2KCLITests",
            dependencies: ["J2KCore", "J2KCLI"]),
        .testTarget(
            name: "JP3DTests",
            dependencies: ["J2K3D", "J2KCore", "JPIP"]),
        .testTarget(
            name: "J2KXSTests",
            dependencies: ["J2KXS", "J2KCore"]),
        .testTarget(
            name: "J2KComplianceTests",
            dependencies: ["J2K3D", "J2KCore"]),
        .testTarget(
            name: "J2KInteroperabilityTests",
            dependencies: ["J2KCore"]),
        .testTarget(
            name: "PerformanceTests",
            dependencies: ["J2KCore", "J2KCodec"]),
        .testTarget(
            name: "J2KTestAppTests",
            dependencies: ["J2KCore"]),
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib"),
        .executableTarget(
            name: "J2KCLI",
            dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat", "J2K3D", "JPIP", "CZlib", "J2KDaemonClient"],
            path: "Sources/J2KCLI",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]),
        // v8 Phase 6.3 — XPC daemon protocol (macOS-only at the
        // type level via #if os(macOS)). Shared between the
        // daemon executable, the daemon-side service, and the
        // CLI client.
        .target(
            name: "J2KDaemonProtocol",
            path: "Sources/J2KDaemonProtocol"),
        // v8 Phase 6.4 — daemon-side service implementation
        // (J2KDaemonService, J2KDaemonListenerDelegate). Shared
        // between the daemon executable and the test suite so
        // the in-process round-trip tests use the real
        // implementation rather than a duplicate.
        .target(
            name: "J2KDaemonCore",
            dependencies: ["J2KDaemonProtocol", "J2KCore", "J2KCodec"],
            path: "Sources/J2KDaemonCore"),
        // v8 Phase 6.4 — client-side wrapper around
        // NSXPCConnection. Auto-discovers the Mach service,
        // exposes a type-safe async ping API, surfaces
        // "daemon unavailable" cleanly so callers can fall
        // back to in-process decode.
        .target(
            name: "J2KDaemonClient",
            dependencies: ["J2KDaemonProtocol", "J2KCore"],
            path: "Sources/J2KDaemonClient"),
        // v8 Phase 6.3 — XPC daemon executable. macOS-only.
        .executableTarget(
            name: "J2KDaemon",
            dependencies: ["J2KDaemonProtocol", "J2KDaemonCore"],
            path: "Sources/J2KDaemon",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]),
        .testTarget(
            name: "J2KDaemonTests",
            dependencies: ["J2KDaemonProtocol", "J2KDaemonCore"],
            path: "Tests/J2KDaemonTests"),
        .testTarget(
            name: "J2KDaemonClientTests",
            dependencies: ["J2KDaemonProtocol", "J2KDaemonCore", "J2KDaemonClient", "J2KCore", "J2KCodec"],
            path: "Tests/J2KDaemonClientTests"),
        .executableTarget(
            name: "J2KTestApp",
            dependencies: ["J2KCore", "J2KCodec", "J2K3D"],
            path: "Sources/J2KTestApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]),
    ]
)
