// MetalHTForwardPrefixSumTests.swift
//
// v7.1.0 I1.1 — bit-exact + microbenchmark validation of the
// single-threadgroup inclusive prefix-sum kernel that backs Pass 2
// of approach C (GPU forward HT entropy).
//
// What this gates:
//   - Pass 2 must match a CPU inclusive scan on UInt32 inputs across
//     a sweep of N values (1, 2, 31, 32, 33, 100, 256, 512, 1024 —
//     edges of the simdgroup-size boundary + the dispatch ceiling).
//   - Edge cases: empty input, single element, all zeros, all ones,
//     values that exercise inter-warp carry (totals stored in
//     threadgroup memory).
//   - Dispatch+execution time at N=1024 (the per-tile chunk size
//     called out in `docs/V7_1_0_I1_0_DESIGN.md`) is reported so
//     I1.2 orchestration knows the per-dispatch cost it's paying.
//
// All correctness assertions are exact (XCTAssertEqual) — no
// tolerance. The microbenchmark records wall-time but does not
// gate on it; it's an observability aid for I1.2 orchestration
// decisions.

import XCTest
@testable import J2KCore
@testable import J2KMetal

final class MetalHTForwardPrefixSumTests: XCTestCase {

    // MARK: - CPU reference

    /// Scalar inclusive prefix-sum reference; the GPU output must
    /// match this byte-for-byte for every input.
    private static func cpuInclusiveScan(_ input: [UInt32]) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: input.count)
        var acc: UInt32 = 0
        for (i, v) in input.enumerated() {
            acc = acc &+ v
            out[i] = acc
        }
        return out
    }

    // MARK: - Helpers

    private func runAndCompare(_ input: [UInt32],
                               file: StaticString = #filePath,
                               line: UInt = #line) async throws {
        let scan = J2KMetalPrefixSum()
        let gpu = try await scan.inclusiveScan(input)
        let cpu = Self.cpuInclusiveScan(input)
        XCTAssertEqual(gpu.count, cpu.count,
                       "length mismatch for N=\(input.count)",
                       file: file, line: line)
        if gpu != cpu {
            // Locate the first divergence to make CI logs actionable.
            for i in 0..<min(gpu.count, cpu.count) where gpu[i] != cpu[i] {
                XCTFail("""
                    GPU vs CPU prefix-sum mismatch for N=\(input.count) \
                    at i=\(i): cpu=\(cpu[i]) gpu=\(gpu[i])
                    """, file: file, line: line)
                return
            }
        }
    }

    // MARK: - Edge cases

    func testEmptyInputReturnsEmpty() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        let scan = J2KMetalPrefixSum()
        let gpu = try await scan.inclusiveScan([])
        XCTAssertEqual(gpu, [])
    }

    func testSingleElement() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        try await runAndCompare([42])
    }

    func testAllZeros() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        try await runAndCompare([UInt32](repeating: 0, count: 1024))
    }

    func testAllOnes_ExercisesInterWarpCarry() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        // 1024 ones → every warp's last lane carries to the next warp.
        // Forces the threadgroup-shared sg_totals[] path.
        try await runAndCompare([UInt32](repeating: 1, count: 1024))
    }

    // MARK: - Simdgroup-boundary sweep

    /// Cover one-below / equal / one-above the simd width (32) — the
    /// kernel branches on warp boundaries and sg_id == 0 carry-fixup,
    /// so these N values stress the most error-prone seams.
    func testSimdgroupBoundaryNValues() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        for n in [1, 2, 31, 32, 33, 63, 64, 65, 100, 256, 511, 512, 513, 1023, 1024] {
            var rng = SplitMix64(seed: UInt64(n) &* 0x9E37_79B9_7F4A_7C15)
            let input: [UInt32] = (0..<n).map { _ in
                // Mix small + large values so partial sums exercise
                // the wide arithmetic path without overflowing UInt32.
                UInt32(rng.next() & 0x000F_FFFF)
            }
            try await runAndCompare(input)
        }
    }

    // MARK: - Random sweep

    func testRandomInputs_SeededReproducible() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        // Three independent seeds × three N values typical for
        // approach C Pass 2 (sub-block, warm-tile, max chunk).
        for seed in [0xDEAD_BEEF, 0xCAFE_F00D, 0xFEED_FACE] as [UInt64] {
            for n in [128, 600, 1024] {
                var rng = SplitMix64(seed: seed &+ UInt64(n))
                let input: [UInt32] = (0..<n).map { _ in
                    UInt32(rng.next() & 0x0000_FFFF)
                }
                try await runAndCompare(input)
            }
        }
    }

    // MARK: - Dispatch ceiling guard

    func testInputAboveCeilingThrows() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        let scan = J2KMetalPrefixSum()
        let oversize = [UInt32](repeating: 1,
                                count: J2KMetalPrefixSum.maxElementsPerDispatch + 1)
        do {
            _ = try await scan.inclusiveScan(oversize)
            XCTFail("Expected single-dispatch limit to throw")
        } catch {
            // Pass — error message already validated by Swift typing.
        }
    }

    // MARK: - Microbenchmark (observational, non-gating)

    /// Reports prefix-sum dispatch+execution wall-time at N=1024.
    /// This is the per-dispatch cost I1.2 orchestration will pay
    /// when stitching multiple chunks per tile (~2300 blocks per
    /// DX 2x2 tile → 3 dispatches).
    func testMicrobenchmark_DispatchTimeAtMaxN() async throws {
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")
        let scan = J2KMetalPrefixSum()
        let n = J2KMetalPrefixSum.maxElementsPerDispatch
        var rng = SplitMix64(seed: 0xA5A5_A5A5_A5A5_A5A5)
        let input: [UInt32] = (0..<n).map { _ in
            UInt32(rng.next() & 0x0000_FFFF)
        }

        // Warm-up — first dispatch pays pipeline state cost.
        _ = try await scan.inclusiveScan(input)

        let trials = 20
        var samples: [Double] = []
        samples.reserveCapacity(trials)
        for _ in 0..<trials {
            let t0 = Date()
            _ = try await scan.inclusiveScan(input)
            samples.append(Date().timeIntervalSince(t0) * 1000.0)
        }
        samples.sort()
        let median = samples[trials / 2]
        let p10 = samples[trials / 10]
        let p90 = samples[trials - trials / 10 - 1]
        print(String(
            format: "I1.1 prefix-sum N=%d: median=%.3f ms p10=%.3f ms p90=%.3f ms",
            n, median, p10, p90))
    }
}

// MARK: - Tiny deterministic RNG (avoid SystemRandomNumberGenerator for reproducibility)

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
