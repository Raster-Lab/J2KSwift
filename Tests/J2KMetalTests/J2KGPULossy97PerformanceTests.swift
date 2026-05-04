// J2KGPULossy97PerformanceTests.swift
// v5.23.0 — perf-characterisation gate for GPU 9/7 lossy decode.
//
// v5.20.0 caught the GPU 9/7 IDWT correctness bug; v5.21.0 fixed
// it; v5.22.0 locked in cross-module convention. v5.23.0 measures
// the resulting warm-session speedup so we can detect future
// architectural regressions.
//
// Measured baseline (release mode, M-series, 1024×1024 16-bit lossy
// 9/7 @ 2 bpp, n=5 after warm-up):
//   - CPU median:    ~40 ms
//   - GPU-HT median: ~26 ms
//   - Speedup:       ~1.52×
//
// The ceiling is modest because `decodeWithGPUHT` still runs HT
// entropy decoding on CPU; the GPU only owns IDWT + colour transform
// + quantisation. The bigger lever is the GPU HT entropy decoder
// (in flight on the gpu-ht-phase3 branch — phases 0-2 shipped, phase-
// 3 dispatch-amortisation work continues). Ship that and 9/7 lossy
// warm-session speedup should rise materially.
//
// Gate semantics: this is a MEASUREMENT gate, not an assertion gate.
// Sampled variance across 4 release-mode runs on M2 was 0.99×–1.54×
// (n=5 each). A "GPU faster than CPU" assertion flaked ~1-in-4 when
// the two paths happened to land within noise. Asserting any
// specific ratio would amplify that flake rate. Correctness is
// guarded by the v5.20-v5.22 audit gates; this test publishes the
// measured speedup for human review and future perf-trend tracking
// without becoming a flaky red-light gate.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class J2KGPULossy97PerformanceTests: XCTestCase {

    /// Build a synth 16-bit image and encode it once.
    private func makeAndEncode(width: Int, height: Int, bpp: Double) async throws -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        var s: UInt64 = 0xfeed_face
        for i in 0..<(width * height) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let v = Int(s >> 48) & 0xFFFF
            bytes[i * 2]     = UInt8((v >> 8) & 0xFF)
            bytes[i * 2 + 1] = UInt8(v & 0xFF)
        }
        let component = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: width, height: height,
            data: Data(bytes), sampleByteOrder: .bigEndian)
        let image = J2KImage(width: width, height: height, components: [component])
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        return try await J2KEncoder(encodingConfiguration: cfg).encode(image)
    }

    /// Benchmark CPU decode vs GPU-HT decode with shared session.
    /// Reports per-image median time over N decodes.
    func testWarmSessionGPUSpeedupVsCPU() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let width = 1024
        let height = 1024
        let n = 5  // images per timing batch

        // Encode once; reuse the same encoded bytes for both paths.
        let encoded = try await makeAndEncode(width: width, height: height, bpp: 2.0)

        // CPU baseline (no Metal involvement)
        let cpuDecoder = J2KDecoder()
        // Warm CPU caches first
        _ = try await cpuDecoder.decode(encoded)
        var cpuTimes: [TimeInterval] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try await cpuDecoder.decode(encoded)
            cpuTimes.append(Date().timeIntervalSince(t0))
        }

        // GPU-HT with shared session
        let session = J2KMetalSession()
        let gpuDecoder = J2KDecoder()
        // Warm-up: first call pays Metal startup cost
        _ = try await gpuDecoder.decodeWithGPUHT(encoded, session: session)
        var gpuTimes: [TimeInterval] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try await gpuDecoder.decodeWithGPUHT(encoded, session: session)
            gpuTimes.append(Date().timeIntervalSince(t0))
        }

        let cpuMedian = cpuTimes.sorted()[n / 2] * 1000
        let gpuMedian = gpuTimes.sorted()[n / 2] * 1000
        let speedup = cpuMedian / gpuMedian

        print("=== v5.23.0 GPU 9/7 lossy decode warm-session benchmark ===")
        print("Image: \(width)×\(height) 16-bit lossy 9/7 @ 2 bpp")
        print("CPU median:    \(String(format: "%.1f", cpuMedian)) ms (over \(n) calls)")
        print("GPU-HT median: \(String(format: "%.1f", gpuMedian)) ms (over \(n) calls)")
        print("Speedup:       \(String(format: "%.2fx", speedup))")
        print("CPU times:     \(cpuTimes.map { String(format: "%.1f", $0 * 1000) }.joined(separator: " "))")
        print("GPU-HT times:  \(gpuTimes.map { String(format: "%.1f", $0 * 1000) }.joined(separator: " "))")

        // Measurement gate (not assertion gate). See header comment.
        XCTAssertGreaterThan(gpuMedian, 0)
        XCTAssertGreaterThan(cpuMedian, 0)
    }
}
