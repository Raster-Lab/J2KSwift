// V91Phase2cArrayVsRawParityTests.swift
//
// v9.1 Path B Phase 2c — production parity gate.
//
// Verifies that `HTBlockEncoderConformant.encode` produces byte-
// identical output whether it's called with Array-backed engines
// (HTMagSgnEncoderConformant et al.) or raw-pointer engines
// (HTMagSgnEncoderRawConformant et al.).
//
// Both paths share the same generic `encodeLoopGeneric` helper that
// does the per-quad classification + bit emission; only the
// finalization differs (Array's `.finish() -> [UInt8]` vs Raw's
// `.finishCount() -> Int`). The bit-stream content emitted by both
// must be byte-identical for the production integration to be safe
// to default-on.
//
// Sweeps coefficient patterns across block sizes and significance
// densities that exercise:
//   - All-zero blocks (zero-block short-circuit on the pipeline side,
//     but encode() still produces the same minimal output)
//   - Single-sample significant blocks (initial-row edge case)
//   - Sparse blocks (typical detail subband)
//   - Dense blocks (LL subband / aggressive lossless)
//   - Edge-of-tile non-power-of-2 widths/heights
//   - All useSIMDClassification values

import XCTest
@testable import J2KCodec

final class V91Phase2cArrayVsRawParityTests: XCTestCase {

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Compare Array vs Raw output for a given coefficient buffer.
    /// Verifies (magsgn, mel, vlc) byte-tuples are byte-identical.
    private func compareArrayVsRaw(
        coeffs: [UInt32],
        width: Int,
        height: Int,
        missingMSBs: Int,
        useSIMDClassification: Bool,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // ---- Array path ----
        var arrayMagsgn = HTMagSgnEncoderConformant()
        var arrayMel = HTMELEncoderConformant()
        var arrayVlc = HTReverseBitEmitterConformant()
        let arrayOutput = coeffs.withUnsafeBufferPointer { ptr in
            HTBlockEncoderConformant.encode(
                coefficients: ptr,
                width: width, height: height,
                missingMSBs: missingMSBs,
                magsgnEnc: &arrayMagsgn,
                melEnc: &arrayMel,
                vlcEnc: &arrayVlc,
                useSIMDClassification: useSIMDClassification,
                preClassifiedTuples: nil)
        }

        // ---- Raw path ----
        let bufCap = 32 * 1024  // generous; max block output well under 16 KB
        let magsgnBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
        let melBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
        let vlcBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
        defer {
            magsgnBuf.deallocate()
            melBuf.deallocate()
            vlcBuf.deallocate()
        }
        var rawMagsgn = HTMagSgnEncoderRawConformant(buf: magsgnBuf, capacity: bufCap)
        var rawMel = HTMELEncoderRawConformant(buf: melBuf, capacity: bufCap)
        var rawVlc = HTReverseBitEmitterRawConformant(buf: vlcBuf, capacity: bufCap)
        let rawOutput = coeffs.withUnsafeBufferPointer { ptr in
            HTBlockEncoderConformant.encode(
                coefficients: ptr,
                width: width, height: height,
                missingMSBs: missingMSBs,
                magsgnEnc: &rawMagsgn,
                melEnc: &rawMel,
                vlcEnc: &rawVlc,
                useSIMDClassification: useSIMDClassification,
                preClassifiedTuples: nil)
        }

        // Reconstruct byte arrays from raw buffers. VLC is in
        // emittedReversed order → reverse to match Array's finish().
        let rawMagsgnBytes = Array(UnsafeBufferPointer(start: magsgnBuf, count: rawOutput.magsgnCount))
        let rawMelBytes = Array(UnsafeBufferPointer(start: melBuf, count: rawOutput.melCount))
        let rawVlcBytes = Array(UnsafeBufferPointer(start: vlcBuf, count: rawOutput.vlcCount)).reversed()

        XCTAssertEqual(arrayOutput.magsgn, rawMagsgnBytes, "\(label): magsgn mismatch",
                       file: file, line: line)
        XCTAssertEqual(arrayOutput.mel, rawMelBytes, "\(label): mel mismatch",
                       file: file, line: line)
        XCTAssertEqual(arrayOutput.vlc, Array(rawVlcBytes), "\(label): vlc mismatch",
                       file: file, line: line)
    }

    // MARK: - All-zero blocks

    func testAllZeroBlock_64x64() {
        let coeffs = [UInt32](repeating: 0, count: 64 * 64)
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "all-zero 64x64")
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: true,
                          label: "all-zero 64x64 SIMD")
    }

    func testAllZeroBlock_32x32() {
        let coeffs = [UInt32](repeating: 0, count: 32 * 32)
        compareArrayVsRaw(coeffs: coeffs, width: 32, height: 32,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "all-zero 32x32")
    }

    // MARK: - Single significant sample

    func testSingleSignificantSample_64x64() {
        var coeffs = [UInt32](repeating: 0, count: 64 * 64)
        coeffs[0] = 0x0000_0080
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "single sig at [0,0]")
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: true,
                          label: "single sig at [0,0] SIMD")
    }

    func testSignificantSampleAtMidRow_64x64() {
        var coeffs = [UInt32](repeating: 0, count: 64 * 64)
        coeffs[64 * 31 + 17] = 0x8000_0080  // negative magnitude
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "single negative sig mid-block")
    }

    // MARK: - Sparse patterns (typical detail subband)

    func testSparseSignificance_5pct_64x64() {
        var rng = SplitMix64(state: 0xCAFE_F00D_DEAD_BEEF)
        var coeffs = [UInt32](repeating: 0, count: 64 * 64)
        let sigCount = 200  // ~5% of 4096
        let stride = coeffs.count / sigCount
        for i in 0..<sigCount {
            let idx = i * stride
            if idx < coeffs.count {
                let sign: UInt32 = (rng.next() & 1) != 0 ? 0x8000_0000 : 0
                let mag: UInt32 = UInt32(rng.next() & 0xFF) | 0x80
                coeffs[idx] = sign | mag
            }
        }
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "sparse ~5% sig")
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: true,
                          label: "sparse ~5% sig SIMD")
    }

    func testDenseSignificance_30pct_64x64() {
        var rng = SplitMix64(state: 0x2026_05_11_CAFE)
        var coeffs = [UInt32](repeating: 0, count: 64 * 64)
        for i in 0..<coeffs.count {
            let r = rng.next()
            if (r & 0xFF) < 76 {  // ~30%
                let sign: UInt32 = (r & 0x100) != 0 ? 0x8000_0000 : 0
                let mag: UInt32 = UInt32((r >> 16) & 0xFF) | 0x80
                coeffs[i] = sign | mag
            }
        }
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "dense ~30% sig")
        compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                          missingMSBs: 24, useSIMDClassification: true,
                          label: "dense ~30% sig SIMD")
    }

    // MARK: - Non-power-of-2 block sizes (edge of tile)

    func testNonPow2_47x39() {
        var rng = SplitMix64(state: 0xDEAD_47_39_2026)
        var coeffs = [UInt32](repeating: 0, count: 47 * 39)
        for i in 0..<coeffs.count {
            if (rng.next() & 0xFF) < 51 {  // ~20%
                let sign: UInt32 = (rng.next() & 1) != 0 ? 0x8000_0000 : 0
                let mag: UInt32 = UInt32(rng.next() & 0xFF) | 0x80
                coeffs[i] = sign | mag
            }
        }
        compareArrayVsRaw(coeffs: coeffs, width: 47, height: 39,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "47x39 nonpow2")
    }

    func testNonPow2_3x5() {
        let coeffs: [UInt32] = [
            0x0000_0080, 0,           0x8000_00FF,
            0,           0x0000_0090, 0,
            0x0000_0100, 0x0000_0080, 0,
            0,           0,           0,
            0x8000_0080, 0,           0x0000_0080,
        ]
        compareArrayVsRaw(coeffs: coeffs, width: 3, height: 5,
                          missingMSBs: 24, useSIMDClassification: false,
                          label: "3x5 tiny")
        compareArrayVsRaw(coeffs: coeffs, width: 3, height: 5,
                          missingMSBs: 24, useSIMDClassification: true,
                          label: "3x5 tiny SIMD")
    }

    // MARK: - Sweep across missingMSBs

    func testMissingMSBsSweep_64x64() {
        var rng = SplitMix64(state: 0xBADC_0FFEE_2026)
        var coeffs = [UInt32](repeating: 0, count: 64 * 64)
        for i in 0..<coeffs.count {
            if (rng.next() & 0xFF) < 51 {
                let sign: UInt32 = (rng.next() & 1) != 0 ? 0x8000_0000 : 0
                let mag: UInt32 = (UInt32(rng.next() & 0xFFFFF)) | 0x10000
                coeffs[i] = sign | mag
            }
        }
        for msb in [4, 12, 16, 20, 24, 28] {
            compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                              missingMSBs: msb, useSIMDClassification: false,
                              label: "missingMSBs=\(msb)")
            compareArrayVsRaw(coeffs: coeffs, width: 64, height: 64,
                              missingMSBs: msb, useSIMDClassification: true,
                              label: "missingMSBs=\(msb) SIMD")
        }
    }
}
