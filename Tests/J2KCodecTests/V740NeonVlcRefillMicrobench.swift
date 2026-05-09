// V740NeonVlcRefillMicrobench.swift
//
// v7.4 Phase 3 — VLC reverse-reader refill microbench.
// `VLCReverseReader` is fileprivate, so we cannot bench `refill`
// directly. Instead, we drive the public block-decode entry point
// `HTBlockDecoderConformant.decode` and toggle
// `VLCReverseReaderTesting.batchedRefillEnabled` between runs. The
// resulting per-block delta isolates the refill path under realistic
// VLC-stream byte distributions (which differ from MagSgn — bytes
// `> 0x8F` are 7/16 of the value space, so the SWAR fast-path hit-
// rate is much lower than Phase 2's MagSgn 0xFF-detect).

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V740NeonVlcRefillMicrobench: XCTestCase {

    private func makeBlock(
        width: Int, height: Int,
        sigDensity: Double, missingMSBs: Int,
        seed: UInt64
    ) throws -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        let n = width * height
        var coeffs = [UInt32](repeating: 0, count: n)
        let sigThreshold = UInt64(sigDensity * Double(UInt64.max))
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

    private func benchDecode(
        block: [UInt8], width: Int, height: Int, missingMSBs: Int,
        iterations: Int
    ) throws -> Double {
        var sink: UInt32 = 0
        let t0 = DispatchTime.now()
        for _ in 0..<iterations {
            let coefs = try HTBlockDecoderConformant.decode(
                block: block, width: width, height: height,
                missingMSBs: missingMSBs)
            sink &+= coefs[0] &+ coefs[coefs.count - 1]
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt32.max - 1)
        return Double(dt) / Double(iterations)
    }

    func testRefill_ScalarVsBatched_PerDensity() throws {
        let runs = 5
        let iterations = 2_000

        let cells: [(label: String, density: Double, missingMSBs: Int)] = [
            ("sparse  (5%, 14 missing)",   0.05, 14),
            ("typical (30%, 14 missing)",  0.30, 14),
            ("dense   (60%, 14 missing)",  0.60, 14),
            ("very-dense (90%, 14 missing)", 0.90, 14),
        ]

        let prev = VLCReverseReaderTesting.batchedRefillEnabled
        defer { VLCReverseReaderTesting.batchedRefillEnabled = prev }

        print("=== v7.4 Phase 3 VLC refill microbench (median of \(runs)) ===")
        print("Block 32×32, iterations: \(iterations) per cell")
        print()
        print("| cell | scalar µs/block | batched µs/block | batched Δ | speedup |")
        print("|---|---:|---:|---:|---:|")

        for cell in cells {
            let block = try makeBlock(
                width: 32, height: 32,
                sigDensity: cell.density, missingMSBs: cell.missingMSBs,
                seed: 0xC0FFEE_C0FFEE)

            VLCReverseReaderTesting.batchedRefillEnabled = false
            var scalarSamples: [Double] = []
            for _ in 0..<runs {
                scalarSamples.append(try benchDecode(
                    block: block, width: 32, height: 32,
                    missingMSBs: cell.missingMSBs,
                    iterations: iterations))
            }
            scalarSamples.sort()
            let scalar = scalarSamples[runs / 2]

            VLCReverseReaderTesting.batchedRefillEnabled = true
            var batchedSamples: [Double] = []
            for _ in 0..<runs {
                batchedSamples.append(try benchDecode(
                    block: block, width: 32, height: 32,
                    missingMSBs: cell.missingMSBs,
                    iterations: iterations))
            }
            batchedSamples.sort()
            let batched = batchedSamples[runs / 2]

            let scalarUs = scalar / 1000.0
            let batchedUs = batched / 1000.0
            let delta = (batched - scalar) / scalar * 100.0
            let speedup = scalar / batched
            print(String(format: "| %@ | %.2f | %.2f | %+.1f %% | %.2f× |",
                cell.label, scalarUs, batchedUs, delta, speedup))
        }
    }

    func testRefill_ScalarVsBatched_PerBlockSize() throws {
        let runs = 5
        let iterations = 2_000

        let sizes: [(Int, Int)] = [(16, 16), (32, 32), (64, 64), (32, 64)]

        let prev = VLCReverseReaderTesting.batchedRefillEnabled
        defer { VLCReverseReaderTesting.batchedRefillEnabled = prev }

        print("=== v7.4 Phase 3 VLC refill microbench by block size ===")
        print("Density 30%, missingMSBs 14, iterations: \(iterations)")
        print()
        print("| block | scalar µs/block | batched µs/block | batched Δ | speedup |")
        print("|---|---:|---:|---:|---:|")

        for (w, h) in sizes {
            let block = try makeBlock(
                width: w, height: h,
                sigDensity: 0.30, missingMSBs: 14,
                seed: 0x1234_5678_9ABC_DEF0)

            VLCReverseReaderTesting.batchedRefillEnabled = false
            var scalarSamples: [Double] = []
            for _ in 0..<runs {
                scalarSamples.append(try benchDecode(
                    block: block, width: w, height: h,
                    missingMSBs: 14, iterations: iterations))
            }
            scalarSamples.sort()
            let scalar = scalarSamples[runs / 2]

            VLCReverseReaderTesting.batchedRefillEnabled = true
            var batchedSamples: [Double] = []
            for _ in 0..<runs {
                batchedSamples.append(try benchDecode(
                    block: block, width: w, height: h,
                    missingMSBs: 14, iterations: iterations))
            }
            batchedSamples.sort()
            let batched = batchedSamples[runs / 2]

            let scalarUs = scalar / 1000.0
            let batchedUs = batched / 1000.0
            let delta = (batched - scalar) / scalar * 100.0
            let speedup = scalar / batched
            print(String(format: "| %d×%d | %.2f | %.2f | %+.1f %% | %.2f× |",
                w, h, scalarUs, batchedUs, delta, speedup))
        }
    }
}

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
