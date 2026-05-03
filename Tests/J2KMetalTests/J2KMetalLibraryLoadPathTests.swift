// J2KMetalLibraryLoadPathTests.swift
//
// v5.15: regression gate that the bundled `default.metallib` is
// the path actually taken at runtime. If `Sources/J2KMetal/
// default.metallib` is missing or `Package.swift` stops shipping
// it as a `.copy()` resource, this test fails — surfaces the
// silent fallback to source-compile (which costs ~50 ms per
// process startup) before it ships.

import XCTest
@testable import J2KMetal

final class J2KMetalLibraryLoadPathTests: XCTestCase {

    func testBundledMetallibIsLoaded() async throws {
        try XCTSkipUnless(J2KMetalDevice.isAvailable, "Metal not available")

        let device = J2KMetalDevice()
        try await device.initialize()
        let queue = try await device.commandQueue()
        let lib = J2KMetalShaderLibrary()
        try await lib.loadShaders(device: queue.device)

        let path = await lib.loadPath
        XCTAssertEqual(
            path, .metallib,
            "Expected the bundled default.metallib to be loaded; got \(path?.rawValue ?? "nil"). " +
            "Either Sources/J2KMetal/default.metallib is missing or Package.swift " +
            "stopped declaring it as a .copy() resource. Regenerate via " +
            "Scripts/build_metallib.sh.")
    }
}
