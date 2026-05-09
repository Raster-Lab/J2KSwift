// V740NeonReconstructionMicrobench.swift
//
// v7.4 NEON reconstruction microbench — scalar vs NEON A/B at the
// block-decode level. We can't isolate `readQuadSamples*` standalone
// (it requires a fully-set-up DecodeState with bit-stream readers
// pre-loaded), so we time the full `HTBlockDecoderConformant.decode`
// once per branch on the same synthetic block. The delta between
// the two timings is the reconstruction-only cost difference, since
// every other pipeline stage is identical between the two paths.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V740NeonReconstructionMicrobench: XCTestCase {

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
        block: [UInt8], width: Int, height: Int,
        missingMSBs: Int, iterations: Int
    ) throws -> Double {
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

    func testReconstruction_ScalarVsNEON_PerSizeAndDensity() throws {
        let runs = 5
        let iterations = 5000
        let missingMSBs = 14

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

        let prev = HTBlockDecoderConformant.neonReconstructionEnabled
        defer { HTBlockDecoderConformant.neonReconstructionEnabled = prev }

        print("=== v7.4 NEON reconstruction microbench (median of \(runs)) ===")
        print("missingMSBs = \(missingMSBs); iterations = \(iterations) per cell")
        print()
        print("| block | scalar ns/call | NEON ns/call | NEON Δ | ns/sample (scalar/NEON) |")
        print("|---|---:|---:|---:|---:|")

        for c in cells {
            let block = try makeBlock(
                width: c.width, height: c.height,
                sigDensity: c.sigDensity,
                missingMSBs: missingMSBs,
                seed: 0xC0FFEE_C0FFEE)

            // Scalar measurements
            HTBlockDecoderConformant.neonReconstructionEnabled = false
            var scalarSamples: [Double] = []
            for _ in 0..<runs {
                scalarSamples.append(try benchDecode(
                    block: block, width: c.width, height: c.height,
                    missingMSBs: missingMSBs, iterations: iterations))
            }
            scalarSamples.sort()
            let scalar = scalarSamples[runs / 2]

            // NEON measurements
            HTBlockDecoderConformant.neonReconstructionEnabled = true
            var neonSamples: [Double] = []
            for _ in 0..<runs {
                neonSamples.append(try benchDecode(
                    block: block, width: c.width, height: c.height,
                    missingMSBs: missingMSBs, iterations: iterations))
            }
            neonSamples.sort()
            let neon = neonSamples[runs / 2]

            let neonDelta = (neon - scalar) / scalar * 100.0
            let scalarPerSample = scalar / Double(c.width * c.height)
            let neonPerSample = neon / Double(c.width * c.height)
            print(String(format: "| %@ | %.0f | %.0f | %+.1f %% | %.2f / %.2f |",
                c.label, scalar, neon, neonDelta,
                scalarPerSample, neonPerSample))
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
