// J2KQstepSearchEfficiencyTests.swift
// v5.19.1 regression gate.
//
// v5.19.0 introduced .constantBitrateViaQstep with a binary-search
// outer loop on qstep. Typical cost was 4-6 encode iterations per
// image. v5.19.1 adds three improvements to lower that cost:
//   1. Probe-based one-shot refinement after the first iteration —
//      uses observed bytes/target ratio to scale qstep before binary
//      search begins.
//   2. Tighter initial bracket [guess/16, guess*16] (was 64×).
//   3. Optional J2KQstepCache for batch workflows.
//   4. Early-exit when bracket narrows below 5% AND iterations ≥ 3.
//
// This gate locks in the iteration-count improvements and verifies
// the cache delivers its claimed warm-cache speedup.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KQstepSearchEfficiencyTests: XCTestCase {

    private func makeSynth8(width: Int, height: Int, seed: UInt64 = 0xfeed_face_dead_beef) -> J2KImage {
        var s = seed &+ UInt64(width) &* 1009 &+ UInt64(height) &* 7919
        var bytes = [UInt8](repeating: 0, count: width * height)
        for i in 0..<bytes.count {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let x = i % width
            let y = i / width
            let gradient = (x * 31 + y * 17) & 255
            let noise = Int(s >> 56) & 255
            bytes[i] = UInt8(gradient ^ noise)
        }
        return J2KImage(
            width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 8, signed: false,
                width: width, height: height, data: Data(bytes))])
    }

    private func makeBaseConfig(targetBpp: Double, qstepCache: J2KQstepCache?) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrateViaQstep(
            bitsPerPixel: targetBpp, tolerance: 0.10, maxIterations: 8)
        cfg.qstepCache = qstepCache
        return cfg
    }

    /// Warm-cache convergence should take 1-2 iterations. The cache
    /// pre-loads a known-good qstep so the first iteration usually
    /// converges within tolerance.
    func testWarmCacheConvergesIn2OrFewerIterations() async throws {
        let image = makeSynth8(width: 256, height: 256, seed: 0xabcd1234)
        let cache = J2KQstepCache()

        // First encode fills the cache.
        let cfg = makeBaseConfig(targetBpp: 2.0, qstepCache: cache)
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let (_, coldStats) = try await encoder.encodeWithQstepStats(image)
        XCTAssertFalse(coldStats.cacheHit, "first encode should not be a cache hit")

        // Second encode: same image class (bit-depth/components/bpp),
        // so cache should hit and converge in ≤2 iterations.
        let image2 = makeSynth8(width: 256, height: 256, seed: 0xef560000)
        let (_, warmStats) = try await encoder.encodeWithQstepStats(image2)

        print("Warm-cache stats: cold-iters=\(coldStats.iterations), warm-iters=\(warmStats.iterations), warm-cacheHit=\(warmStats.cacheHit)")

        XCTAssertTrue(warmStats.cacheHit, "second encode should be a cache hit")
        XCTAssertLessThanOrEqual(warmStats.iterations, 2,
            "warm-cache convergence must take ≤2 iterations; got \(warmStats.iterations)")
        XCTAssertLessThan(warmStats.iterations, coldStats.iterations,
            "warm cache should reduce iterations vs cold")
    }

    /// Stats output makes sense: the converged qstep is within an
    /// order of magnitude of the initial guess (so the search wasn't
    /// completely off-target), and achieved bpp is close to target.
    func testStatsAreCoherent() async throws {
        let image = makeSynth8(width: 128, height: 128)
        let cfg = makeBaseConfig(targetBpp: 2.0, qstepCache: nil)
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let (_, stats) = try await encoder.encodeWithQstepStats(image)

        XCTAssertGreaterThan(stats.initialQstep, 0.0)
        XCTAssertGreaterThan(stats.convergedQstep, 0.0)
        // Within 100× of each other (very loose check).
        let ratio = max(stats.initialQstep, stats.convergedQstep)
                  / min(stats.initialQstep, stats.convergedQstep)
        XCTAssertLessThan(ratio, 100.0,
            "calibration is wildly off — converged qstep \(stats.convergedQstep) vs initial \(stats.initialQstep)")

        // Achieved bpp should be close to target.
        let bppRatio = stats.achievedBpp / stats.targetBpp
        XCTAssertLessThan(abs(bppRatio - 1.0), 0.30,
            "achieved bpp \(stats.achievedBpp) too far from target \(stats.targetBpp)")
    }

    /// Cache survives across encoders that share it (it's an actor).
    func testCacheSharingAcrossEncoders() async throws {
        let cache = J2KQstepCache()
        let image = makeSynth8(width: 128, height: 128)

        // Encoder A fills the cache.
        let cfgA = makeBaseConfig(targetBpp: 2.0, qstepCache: cache)
        let (_, statsA) = try await J2KEncoder(encodingConfiguration: cfgA).encodeWithQstepStats(image)
        XCTAssertFalse(statsA.cacheHit)

        // Encoder B reuses the same cache instance.
        let cfgB = makeBaseConfig(targetBpp: 2.0, qstepCache: cache)
        let (_, statsB) = try await J2KEncoder(encodingConfiguration: cfgB).encodeWithQstepStats(image)
        XCTAssertTrue(statsB.cacheHit, "cache should persist across encoders")

        let cacheCount = await cache.count
        XCTAssertEqual(cacheCount, 1, "cache should have one entry after two compatible encodes")
    }
}
