// J2KMetalLibraryLoadBenchTests.swift
//
// v5.15: isolated bench of `loadShaders` cost. Runs N independent
// shader-library loads on a fresh device each call, reporting
// median time. Surfaces the metallib vs source-compile delta the
// v5.6.0 perf report flagged. Skipped unless run with
//
//     J2K_BENCH_LIBRARY_LOAD=1 swift test --filter J2KMetalLibraryLoadBenchTests

import XCTest
@testable import J2KMetal

final class J2KMetalLibraryLoadBenchTests: XCTestCase {

    private static let stderr = FileHandle.standardError
    private static func say(_ s: String) {
        stderr.write(Data((s + "\n").utf8))
    }

    func testLoadShadersBench() async throws {
        try XCTSkipUnless(J2KMetalDevice.isAvailable, "Metal not available")
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["J2K_BENCH_LIBRARY_LOAD"] != nil,
            "Run with J2K_BENCH_LIBRARY_LOAD=1 to capture timings")

        let device = J2KMetalDevice()
        try await device.initialize()
        let queue = try await device.commandQueue()
        let mtlDevice = queue.device

        // Warm one load (Metal driver caching): each subsequent run
        // measures only the shader-library load itself.
        do {
            let lib = J2KMetalShaderLibrary()
            try await lib.loadShaders(device: mtlDevice)
            _ = await lib.loadPath
        }

        let runs = 10
        var ms: [Double] = []
        for _ in 0..<runs {
            let lib = J2KMetalShaderLibrary()
            let t0 = DispatchTime.now()
            try await lib.loadShaders(device: mtlDevice)
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            ms.append(dt)
        }
        let sorted = ms.sorted()
        let median = sorted[runs / 2]
        let min = sorted.first!
        let max = sorted.last!

        let lib = J2KMetalShaderLibrary()
        try await lib.loadShaders(device: mtlDevice)
        let path = await lib.loadPath?.rawValue ?? "unknown"

        Self.say(String(format:
            "[bench] loadShaders path=%@  median=%.2f ms  min=%.2f  max=%.2f  (N=%d)",
            path, median, min, max, runs))
    }
}
