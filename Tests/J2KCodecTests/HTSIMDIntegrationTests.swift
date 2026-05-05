// HTSIMDIntegrationTests.swift
// v5.39 M1 — block-level byte-identical correctness gates for the
// SIMD per-quad classification path inside `HTBlockEncoderConformant`.
//
// Hard rule for v5.39 M1: the SIMD path must produce **bit-identical
// (magsgn, mel, vlc) byte tuples** to the scalar path on every input.
// The prototype tests (`HTSampleInfoSIMDPrototypeTests`) already
// proved per-sample (sig, eQ, payload) lane-identity; this file
// proves end-to-end block byte identity, which is the contract the
// caller (encoder pipeline) actually depends on.
//
// What this test does NOT do:
//   - benchmark performance (separate full-image perf test)
//   - touch lossy paths
//   - integrate the SIMD switch into production defaults
//
// SCOPE: lossless HT conformant block encoder only.

import XCTest
@testable import J2KCodec

final class HTSIMDIntegrationTests: XCTestCase {

    /// Encode `coefficients` once via scalar, once via SIMD, return
    /// both byte tuples for comparison.
    private func encodeBoth(
        _ coefficients: [UInt32],
        width: Int,
        height: Int,
        missingMSBs: Int
    ) -> (scalar: ([UInt8], [UInt8], [UInt8]),
          simd:   ([UInt8], [UInt8], [UInt8])) {
        var ms1 = HTMagSgnEncoderConformant()
        var ml1 = HTMELEncoderConformant()
        var vl1 = HTReverseBitEmitterConformant()
        let scalar = coefficients.withUnsafeBufferPointer { buf in
            HTBlockEncoderConformant.encode(
                coefficients: buf,
                width: width, height: height, missingMSBs: missingMSBs,
                magsgnEnc: &ms1, melEnc: &ml1, vlcEnc: &vl1,
                useSIMDClassification: false)
        }

        var ms2 = HTMagSgnEncoderConformant()
        var ml2 = HTMELEncoderConformant()
        var vl2 = HTReverseBitEmitterConformant()
        let simd = coefficients.withUnsafeBufferPointer { buf in
            HTBlockEncoderConformant.encode(
                coefficients: buf,
                width: width, height: height, missingMSBs: missingMSBs,
                magsgnEnc: &ms2, melEnc: &ml2, vlcEnc: &vl2,
                useSIMDClassification: true)
        }
        return (scalar, simd)
    }

    private func assertBytesIdentical(
        _ pair: (scalar: ([UInt8], [UInt8], [UInt8]),
                 simd:   ([UInt8], [UInt8], [UInt8])),
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(pair.scalar.0, pair.simd.0,
            "\(label): magsgn bytes differ", file: file, line: line)
        XCTAssertEqual(pair.scalar.1, pair.simd.1,
            "\(label): mel bytes differ",    file: file, line: line)
        XCTAssertEqual(pair.scalar.2, pair.simd.2,
            "\(label): vlc bytes differ",    file: file, line: line)
    }

    // MARK: - Edge-case blocks

    /// All-zero block — should produce empty/minimal streams in
    /// both paths. The SIMD path's "non-significant lane" handling
    /// is exercised here on every quad.
    func testSIMDvsScalarBlock_AllZero_64x64() {
        let coeffs = [UInt32](repeating: 0, count: 64 * 64)
        let pair = encodeBoth(coeffs, width: 64, height: 64, missingMSBs: 0)
        assertBytesIdentical(pair, label: "all-zero 64x64")
    }

    /// All-max block — every sample is 0xFFFFFFFF (sign bit set,
    /// magnitude all-ones). Hits the high end of `eQ`.
    func testSIMDvsScalarBlock_AllMax_64x64() {
        let coeffs = [UInt32](repeating: 0xFFFF_FFFF, count: 64 * 64)
        let pair = encodeBoth(coeffs, width: 64, height: 64, missingMSBs: 0)
        assertBytesIdentical(pair, label: "all-max 64x64")
    }

    /// Alternating-sign checkerboard — exercises rho variation
    /// across the four positions of every quad.
    func testSIMDvsScalarBlock_AlternatingSign_64x64() {
        var coeffs = [UInt32]()
        coeffs.reserveCapacity(64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let v: UInt32 = ((x + y) & 1) == 0 ? 0x4000_0000 : 0xC000_0000
                coeffs.append(v)
            }
        }
        let pair = encodeBoth(coeffs, width: 64, height: 64, missingMSBs: 0)
        assertBytesIdentical(pair, label: "alternating sign 64x64")
    }

    /// Sparse block (medical-like) — most samples zero with rare
    /// significant samples. Exercises the "mostly non-significant
    /// lanes" code path which is the common case in MR/sparse content.
    func testSIMDvsScalarBlock_Sparse_64x64() {
        var coeffs = [UInt32](repeating: 0, count: 64 * 64)
        // ~5% sparse pattern at varying magnitudes / signs.
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let idx = Int.random(in: 0..<coeffs.count, using: &rng)
            let mag = UInt32.random(in: 1...0x0FFF_FFFF, using: &rng)
            let sign: UInt32 = Bool.random(using: &rng) ? 0x8000_0000 : 0
            coeffs[idx] = sign | mag
        }
        let pair = encodeBoth(coeffs, width: 64, height: 64, missingMSBs: 0)
        assertBytesIdentical(pair, label: "sparse 64x64")
    }

    /// Dense random block.
    func testSIMDvsScalarBlock_DenseRandom_64x64() {
        var rng = SystemRandomNumberGenerator()
        var coeffs = [UInt32](repeating: 0, count: 64 * 64)
        for i in 0..<coeffs.count {
            coeffs[i] = UInt32.random(in: 0...UInt32.max, using: &rng)
        }
        let pair = encodeBoth(coeffs, width: 64, height: 64, missingMSBs: 0)
        assertBytesIdentical(pair, label: "dense random 64x64")
    }

    /// Boundary / partial-size blocks — non-multiple-of-4 widths
    /// and non-multiple-of-2 heights exercise the `fetch()` zero-
    /// fill branch, which the SIMD path also goes through (it
    /// loads via `fetch`, then SIMDs the four resulting UInt32s).
    func testSIMDvsScalarBlock_BoundarySizes() {
        var rng = SystemRandomNumberGenerator()
        let cases: [(Int, Int)] = [
            (1, 1), (1, 64), (64, 1), (3, 5), (7, 13), (13, 7),
            (31, 31), (31, 32), (32, 31), (33, 17), (61, 63),
            (63, 1), (1, 63), (5, 64), (64, 5),
        ]
        for (w, h) in cases {
            var coeffs = [UInt32](repeating: 0, count: w * h)
            for i in 0..<coeffs.count {
                coeffs[i] = UInt32.random(in: 0...UInt32.max, using: &rng)
            }
            let pair = encodeBoth(coeffs, width: w, height: h, missingMSBs: 0)
            assertBytesIdentical(pair, label: "boundary \(w)x\(h)")
        }
    }

    /// Vary missingMSBs across the realistic range — for HT
    /// cleanup-only lossless on 16-bit medical content the value
    /// is K_max - 1 where K_max is bitDepth + guardBits, so the
    /// realistic range here is ~14-22.
    func testSIMDvsScalarBlock_VaryingMissingMSBs() {
        var rng = SystemRandomNumberGenerator()
        var coeffs = [UInt32](repeating: 0, count: 32 * 32)
        for i in 0..<coeffs.count {
            coeffs[i] = UInt32.random(in: 0...UInt32.max, using: &rng)
        }
        for kmsbs in [3, 5, 10, 14, 18, 22, 25, 28, 29] {
            let pair = encodeBoth(coeffs, width: 32, height: 32, missingMSBs: kmsbs)
            assertBytesIdentical(pair, label: "missingMSBs=\(kmsbs) 32x32")
        }
    }

    // MARK: - Randomised sweep

    /// Encode the same random block via scalar and SIMD; assert
    /// byte-identical output. Repeats over many random blocks across
    /// multiple block sizes and missingMSBs values to give the
    /// classifier full coverage that the prototype's per-sample
    /// sweep didn't reach (which only checked classification math,
    /// not block-level bookkeeping interactions).
    func testSIMDvsScalarBlock_RandomSweep() {
        var rng = SystemRandomNumberGenerator()
        let sizes: [(Int, Int)] = [(64, 64), (32, 32), (32, 64), (64, 32), (16, 16)]
        let kmsbsList = [3, 10, 18, 25, 28]

        for (w, h) in sizes {
            for kmsbs in kmsbsList {
                // 200 random blocks per (size, kmsbs) cell — at the
                // smallest size = 16² that's 200 × 256 = 51,200
                // samples through the path; total across all cells
                // is ~6M samples per random run, far exceeding the
                // prototype's 180K.
                for _ in 0..<200 {
                    var coeffs = [UInt32](repeating: 0, count: w * h)
                    for i in 0..<coeffs.count {
                        coeffs[i] = UInt32.random(in: 0...UInt32.max, using: &rng)
                    }
                    let pair = encodeBoth(coeffs, width: w, height: h, missingMSBs: kmsbs)
                    if pair.scalar != pair.simd {
                        // Fail on first divergence with full context.
                        XCTFail("SIMD vs scalar diverged at (w=\(w), h=\(h), kmsbs=\(kmsbs)). Coefficient sample[0..min(8,n)]: \(coeffs.prefix(min(8, coeffs.count)).map { String($0, radix: 16) })")
                        return
                    }
                }
            }
        }
    }
}
