// V730Phase3aBlockDecodeMicrobench.swift
//
// v7.3.0 Phase 3a — block-level HT decode microbench.
//
// Phase 1b's negative finding: scalar `HTMagSgnDecoderConformant.read`
// is at the Apple M2 ceiling — bounds-check elimination saves ~1 % on
// the hot 14-bit case. Phase 3 redirects to `readQuadSamples`, the
// per-quad reconstruction loop that the Phase 0 probe showed runs
// 615 K times per DX 4x4 decode (each call doing 4 sample positions ×
// payload unpack).
//
// This microbench measures the WHOLE `HTBlockDecoderConformant.decode`
// on synthetic codeblocks of representative sizes + densities. Gives
// a per-block ns baseline that Phase 3b's optimisation has to beat.
//
// Synthetic blocks are built by encoding a known coefficient pattern
// and then decoding the resulting bytes. Coefficient pattern uses a
// deterministic SplitMix64 RNG with realistic significant-sample
// density (~30 %, matching DX corpus).

import XCTest
@testable import J2KCodec

final class V730Phase3aBlockDecodeMicrobench: XCTestCase {

    /// Build a synthetic codeblock by encoding a random-coefficient
    /// pattern of the requested size + density.
    private func makeBlock(
        width: Int, height: Int,
        sigDensity: Double,    // fraction of samples that are significant
        missingMSBs: Int,
        seed: UInt64
    ) throws -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        let n = width * height
        var coeffs = [UInt32](repeating: 0, count: n)
        let sigThreshold = UInt64(sigDensity * Double(UInt64.max))
        // For a coefficient to be significant in the HT cleanup pass
        // at bit-plane (p-1) where p = 30 - missingMSBs, its magnitude
        // must be ≥ 2^(p-1). We force the top bit on for "significant"
        // samples and randomise the lower (p-1) bits to give realistic
        // bit-pattern variety.
        // Cleanup-pass significance threshold is `2^p` (per existing
        // J2KMetalHTCleanupTests.makeCoefficients reference). For
        // missingMSBs=14, p=16, so the minimum significant magnitude
        // is 2^16 = 65536. We add up to 3 bits of variety so coefs
        // span a few `eQ` values without flipping into the sign bit.
        let p = 30 - missingMSBs
        let minMag: UInt32 = UInt32(1) << p
        let extraBits = min(3, 30 - p)
        let extraMask: UInt32 = extraBits >= 31 ? 0 : ((UInt32(1) << extraBits) - 1)
        for i in 0..<n {
            if rng.next() < sigThreshold {
                let extra = UInt32(rng.next() & UInt64(extraMask))
                let sign: UInt32 = (rng.next() & 1 != 0) ? 0x8000_0000 : 0
                coeffs[i] = sign | (minMag &+ extra)
            }
        }
        let (magsgn, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coeffs, width: width, height: height,
            missingMSBs: missingMSBs)
        return try HTBlockLayoutConformant.assemble(
            magsgn: magsgn, mel: mel, vlc: vlc)
    }

    /// Time `HTBlockDecoderConformant.decode` over `iterations`
    /// invocations. Returns ns per call.
    private func benchDecode(
        block: [UInt8],
        width: Int, height: Int,
        missingMSBs: Int,
        iterations: Int
    ) throws -> Double {
        // Warmup
        for _ in 0..<10 {
            _ = try HTBlockDecoderConformant.decode(
                block: block, width: width, height: height,
                missingMSBs: missingMSBs)
        }
        var sink: UInt32 = 0
        let t0 = DispatchTime.now()
        for _ in 0..<iterations {
            let coefs = try HTBlockDecoderConformant.decode(
                block: block, width: width, height: height,
                missingMSBs: missingMSBs)
            sink &+= coefs.first ?? 0
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt32.max - 1)
        return Double(dt) / Double(iterations)
    }

    func testBlockDecodeThroughput_PerSizeAndDensity() throws {
        let runs = 5
        let iterations = 5000
        let missingMSBs = 14  // typical for 16-bit medical DWT

        struct Cell {
            let label: String
            let width: Int
            let height: Int
            let sigDensity: Double
        }
        let cells: [Cell] = [
            Cell(label: "32×32  density 0.30 (typical)", width: 32, height: 32, sigDensity: 0.30),
            Cell(label: "64×64  density 0.30 (typical)", width: 64, height: 64, sigDensity: 0.30),
            Cell(label: "64×64  density 0.10 (sparse)",  width: 64, height: 64, sigDensity: 0.10),
            Cell(label: "64×64  density 0.50 (dense)",   width: 64, height: 64, sigDensity: 0.50),
            Cell(label: "64×64  density 0.90 (very dense)", width: 64, height: 64, sigDensity: 0.90),
        ]

        print("=== v7.3.0 Phase 3a — HTBlockDecoderConformant.decode microbench ===")
        print("missingMSBs = \(missingMSBs); iterations = \(iterations) per cell, n = \(runs)")
        print()
        print("| block | bytes | ns/call (median) | ns/sample |")
        print("|---|---:|---:|---:|")

        for c in cells {
            let block = try makeBlock(
                width: c.width, height: c.height,
                sigDensity: c.sigDensity,
                missingMSBs: missingMSBs,
                seed: 0xC0FFEE_C0FFEE)

            // Sanity: decode once and verify round-trip is non-trivial.
            let decoded = try HTBlockDecoderConformant.decode(
                block: block, width: c.width, height: c.height,
                missingMSBs: missingMSBs)
            let nonZeroOut = decoded.lazy.filter { $0 != 0 }.count

            var samples: [Double] = []
            for _ in 0..<runs {
                samples.append(try benchDecode(
                    block: block, width: c.width, height: c.height,
                    missingMSBs: missingMSBs, iterations: iterations))
            }
            samples.sort()
            let median = samples[runs / 2]
            let nsPerSample = median / Double(c.width * c.height)
            print("| \(c.label) | block=\(block.count) B nonZero=\(nonZeroOut) | "
                  + String(format: "%.0f ns/call | %.2f ns/sample |",
                           median, nsPerSample))
        }

        // Cross-reference: the 64×64 0.30-density cell is the most
        // representative single block for the medical corpus. DX 4x4
        // tile has ~700×572 / 64² ≈ 100 codeblocks per band per tile;
        // total codeblocks per DX decode = ~6.4 M / 4096 ≈ 1500-2000
        // codeblocks (across 16 tiles × ~100 blocks). At
        // (ns/call median for the 64×64 0.30 cell) × ~1750 blocks =
        // total HT decode wall on DX (estimate).
    }
}

// MARK: - Deterministic RNG (matches Phase 1a)

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
