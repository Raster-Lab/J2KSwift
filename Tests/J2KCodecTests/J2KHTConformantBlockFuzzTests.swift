// J2KHTBlockFuzzConformantTests.swift
// Randomized self-round-trip tests for the Part-15 cleanup-pass
// codeblock encoder + decoder. Feeds randomly-placed bin-centered
// samples at various magnitudes through the encode/assemble/parse/
// decode pipeline and asserts exact reconstruction.
//
// Bin-centered inputs are necessary for lossless round-trip because
// OpenJPH's decoder reconstructs to the bin center — inputs aligned
// to `(2μ_p + 1) << (p - 1)` land exactly on a decodable value.

import XCTest
@testable import J2KCodec

final class HTBlockFuzzConformantTests: XCTestCase {

    /// Deterministic LCG for reproducible fuzz runs.
    private struct SeededRNG {
        var state: UInt64
        init(seed: UInt64) { state = seed | 1 }
        mutating func next() -> UInt64 {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            return state
        }
        mutating func nextInt(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }
    }

    /// Build a bin-centered sign-magnitude coefficient for μ_p value
    /// and sign. `(2μ_p + 1) << (p - 1)` places the sample at the
    /// center of the [μ_p, μ_p + 1] quantization bin.
    private static func binCenter(mu: UInt32, sign: Bool, p: UInt32)
        -> UInt32
    {
        let mag = (2 * mu + 1) << (p - 1)
        return sign ? (mag | 0x8000_0000) : mag
    }

    /// One fuzz trial: pick width/height + a density of significant
    /// samples; plant μ_p=1 bin centers at those positions; round-trip.
    private func runTrial(seed: UInt64) throws {
        var rng = SeededRNG(seed: seed)
        let width = [1, 2, 3, 4, 6, 8, 16][rng.nextInt(7)]
        let height = [1, 2, 3, 4, 6, 8][rng.nextInt(6)]
        let missingMSBs = 0
        let p: UInt32 = 30

        var coefs = [UInt32](repeating: 0, count: width * height)
        // Sparse placement: about 25% density.
        for i in 0..<coefs.count {
            if (rng.next() & 3) == 0 {
                let mu: UInt32 = 1  // Keep μ_p=1 to keep Uq small.
                let sign = (rng.next() & 1) == 1
                coefs[i] = Self.binCenter(mu: mu, sign: sign, p: p)
            }
        }

        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: missingMSBs)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: width, height: height,
            missingMSBs: missingMSBs)
        XCTAssertEqual(decoded, coefs,
            "seed=\(seed) width=\(width) height=\(height) coefs=\(coefs)")
    }

    /// Run 50 deterministic fuzz trials over varied dimensions and
    /// sample placements.
    func testFifty25PercentDensityTrials() throws {
        for seed in UInt64(1)...UInt64(50) {
            try runTrial(seed: seed)
        }
    }

    /// Dense-fill variant: every sample is significant at μ_p=1,
    /// exercising rho patterns with multiple bits set in every quad.
    func testDenseFilledBlocks() throws {
        let p: UInt32 = 30
        for (width, height) in [(4, 4), (8, 4), (4, 8), (8, 8)] {
            var coefs = [UInt32](repeating: 0, count: width * height)
            for i in 0..<coefs.count {
                coefs[i] = Self.binCenter(
                    mu: 1, sign: (i & 1) == 1, p: p)
            }
            let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
                coefficients: coefs, width: width, height: height,
                missingMSBs: 0)
            let block = try HTBlockLayoutConformant.assemble(
                magsgn: ms, mel: mel, vlc: vlc)
            let decoded = try HTBlockDecoderConformant.decode(
                block: block, width: width, height: height, missingMSBs: 0)
            XCTAssertEqual(decoded, coefs,
                "dense \(width)x\(height) round-trip failed")
        }
    }

    /// Varied μ_p magnitudes exercise the UVLC (u-value) path. To
    /// accommodate higher μ_p values, `missingMSBs` is increased so
    /// that `p = 30 - missingMSBs` leaves enough headroom for
    /// `(2μ_p + 1) << (p - 1)` to fit in bits 0..30 without
    /// colliding with the sign bit (bit 31). Each pair in the sweep
    /// hits a different UVLC sub-branch (both ≤ 2, asymmetric,
    /// both > 2).
    func testVariedMagnitudes() throws {
        struct Case { let muPair: (UInt32, UInt32); let missingMSBs: Int }
        let cases: [Case] = [
            Case(muPair: (1, 1), missingMSBs: 0),   // p=30, μ_p=1 fits
            Case(muPair: (2, 1), missingMSBs: 1),   // p=29, μ_p=2 fits
            Case(muPair: (3, 3), missingMSBs: 2),   // p=28, μ_p=3 fits
            Case(muPair: (4, 2), missingMSBs: 3)    // p=27, μ_p=4 fits
        ]
        for c in cases {
            let p = UInt32(30 - c.missingMSBs)
            var coefs = [UInt32](repeating: 0, count: 8)
            coefs[0] = Self.binCenter(mu: c.muPair.0, sign: false, p: p)
            coefs[4] = Self.binCenter(mu: c.muPair.1, sign: true,  p: p)
            let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
                coefficients: coefs, width: 4, height: 2,
                missingMSBs: c.missingMSBs)
            let block = try HTBlockLayoutConformant.assemble(
                magsgn: ms, mel: mel, vlc: vlc)
            let decoded = try HTBlockDecoderConformant.decode(
                block: block, width: 4, height: 2,
                missingMSBs: c.missingMSBs)
            XCTAssertEqual(decoded, coefs,
                "mu=\(c.muPair) missingMSBs=\(c.missingMSBs) failed")
        }
    }
}
