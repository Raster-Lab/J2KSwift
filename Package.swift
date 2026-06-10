// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// CompressionFamily — shared protocol surface for the Swift
// compression-library family. Always resolved from its public Git
// repository so J2KSwift stays URL-consumable as a SwiftPM dependency
// (see #438).
//
// The previous `FileManager.fileExists("../CompressionFamily")` probe was
// relative to the *current working directory*. SwiftPM evaluates a
// dependency's manifest with CWD set to the consuming root package, so any
// consumer that happened to have a `CompressionFamily` directory beside its
// own package root caused J2KSwift to fall back to a `.package(path:)`
// dependency — which a stable-versioned consumer is not allowed to depend
// on transitively ("unstable-version package"). Always using the URL form
// removes that footgun. For local co-development of J2KSwift +
// CompressionFamily, use `swift package edit CompressionFamily
// --path ../CompressionFamily`.
let compressionFamilyDependency: Package.Dependency = .package(
    url: "https://github.com/Raster-Lab/CompressionFamily.git",
    from: "1.0.0")

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
            name: "J2KFileFormat",
            targets: ["J2KFileFormat"]),
        .library(
            name: "J2KMetal",
            targets: ["J2KMetal"]),
        .library(
            name: "JPIP",
            targets: ["JPIP"]),
        .library(
            name: "J2K3D",
            targets: ["J2K3D"]),
        // v10.17.0 — DICOM-bridge helpers product. Phase 1 ships the
        // Transfer Syntax UID enum + J2KEncodingConfiguration mapping +
        // codestream sniffer + PhotometricInterpretation enum mirror.
        // ADR-004 compliant: no DICOM library dependency anywhere in
        // J2KSwift; this product depends only on J2KCore + J2KCodec.
        // Consumers who don't need DICOM ergonomics simply don't import
        // J2KDICOMHelpers.
        .library(
            name: "J2KDICOMHelpers",
            targets: ["J2KDICOMHelpers"]),
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
            ]),
        // v9.4-research — custom C+NEON tier-1 HT block encoder. Plain C
        // target with caller-owned-buffer entry point. No global statics,
        // no allocator hits. Default-off behind J2K_NEON_HOT_PATH env var
        // until the in-proc warm A/B clears the v9.3 baseline (see
        // V9_4_NEON_HOT_PATH_RESEARCH.md decision matrix).
        .target(
            name: "J2KCodecNEON",
            path: "Sources/J2KCodecNEON",
            // v11.0.0: the -O3/-fno-* unsafeFlags were removed after an
            // interleaved warm A/B (DX -0.44 ms, MG +1.35 ms, CT +0.06 ms
            // vs SwiftPM's default release C optimization — all inside the
            // 3 ms gate). Any unsafeFlags in the manifest makes the whole
            // package ineligible as a versioned SwiftPM dependency; this
            // was the last one.
            publicHeadersPath: "include"),
        .target(
            name: "J2KCodec",
            dependencies: [
                "J2KCore",
                "J2KMetal",
                "J2KCodecNEON",
                .product(name: "CompressionFamily", package: "CompressionFamily"),
            ]),
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
            name: "JPIP",
            dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat", "J2K3D"]),
        .target(
            name: "J2K3D",
            dependencies: ["J2KCore", "J2KCodec"]),
        // v10.17.0 — DICOM-bridge helpers. Pure additive surface,
        // ADR-004 compliant: depends only on J2KCore + J2KCodec.
        // No DICOM library dependency introduced.
        .target(
            name: "J2KDICOMHelpers",
            dependencies: ["J2KCore", "J2KCodec"]),
        // v11.0.0 — test-app scaffolding models extracted from J2KCore.
        // A library target (not part of the J2KTestApp executable)
        // because J2KCLICore consumes it for `j2k testapp --headless`
        // and J2KTestAppTests must not link an @main executable into
        // the unified test binary (see the J2KCLICore comment below).
        .target(
            name: "J2KTestAppCore",
            dependencies: ["J2KCore"],
            path: "Sources/J2KTestAppCore"),
        .testTarget(
            name: "J2KCoreTests",
            dependencies: ["J2KCore", "J2KFileFormat"]),
        .testTarget(
            name: "J2KCodecTests",
            dependencies: [
                "J2KCodec", "J2KFileFormat", "J2KMetal",
                "J2KCodecNEON",
                .product(name: "CompressionFamily", package: "CompressionFamily"),
            ]),
        .testTarget(
            name: "J2KFileFormatTests",
            dependencies: ["J2KFileFormat"]),
        .testTarget(
            name: "J2KMetalTests",
            dependencies: ["J2KMetal", "J2KCodec"]),
        .testTarget(
            name: "JPIPTests",
            dependencies: ["JPIP", "J2KCodec"]),
        .testTarget(
            name: "J2KCLITests",
            dependencies: ["J2KCore", "J2KCLICore"]),
        .testTarget(
            name: "JP3DTests",
            dependencies: ["J2K3D", "J2KCore", "JPIP"]),
        // v10.17.0 — J2KDICOMHelpers Phase 1 test target.
        .testTarget(
            name: "J2KDICOMHelpersTests",
            dependencies: ["J2KDICOMHelpers", "J2KCore", "J2KCodec"]),
        .testTarget(
            name: "J2KComplianceTests",
            dependencies: ["J2K3D", "J2KCore"]),
        .testTarget(
            name: "J2KTestAppTests",
            dependencies: ["J2KTestAppCore", "J2KCore"]),
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib"),
        // All CLI command logic. A library (not the executable) so that
        // J2KCLITests can depend on it without linking an executable
        // `@main` into the unified test binary — a linked-in CLI entry
        // point hijacks SwiftPM's swift-testing pass (which executes the
        // test binary directly), printing CLI usage and exiting 1 even
        // when every XCTest suite passes.
        .target(
            name: "J2KCLICore",
            dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat", "J2K3D", "JPIP", "CZlib", "J2KDaemonClient", "J2KTestAppCore"],
            path: "Sources/J2KCLICore"),
        // Thin `@main` wrapper producing the `j2k` executable.
        .executableTarget(
            name: "J2KCLI",
            dependencies: ["J2KCLICore"],
            path: "Sources/J2KCLI"),
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
            dependencies: ["J2KDaemonProtocol", "J2KDaemonCore", "J2KCodec"],
            path: "Sources/J2KDaemon"),
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
            dependencies: ["J2KCore", "J2KCodec", "J2K3D", "J2KTestAppCore"],
            path: "Sources/J2KTestApp"),
    ]
)
