// v10.2-research Phase D1.5-B — block-level decoder parity oracle.
//
// Round-trips coefficient blocks through:
//   1. Swift HTBlockEncoderConformant.encode  →  on-wire bytes
//   2a. Swift HTBlockDecoderConformant.decode   →  reconstructed coefs (reference)
//   2b. C    j2knhd_decode_block_ht32           →  reconstructed coefs (port)
//
// Asserts (a) == input (round-trip self-check),
//         (b) == (a)    (Swift vs C parity, bit-exact).

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_2_DecodeBlockParityTests: XCTestCase {

    // MARK: - Synthetic coefficient generator

    private static func binCenter(mu: UInt32, sign: Bool, p: UInt32) -> UInt32 {
        let mag = (2 * mu + 1) << (p - 1)
        return sign ? (mag | 0x8000_0000) : mag
    }

    private static func makeCoefficients(
        width: Int, height: Int, density: Double, seed: UInt64
    ) -> [UInt32] {
        let p: UInt32 = 30
        var coefs = [UInt32](repeating: 0, count: width * height)
        var state = seed | 1
        for i in 0..<coefs.count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            let pct = Double(state >> 32) / Double(UInt32.max)
            if pct < density {
                let sign = (state & 1) == 1
                coefs[i] = binCenter(mu: 1, sign: sign, p: p)
            }
        }
        return coefs
    }

    // MARK: - Block round-trip helpers

    /// Encode coefs → block bytes via the existing Swift encoder.
    private func encodeBlock(coefs: [UInt32], width: Int, height: Int, missingMSBs: Int) -> [UInt8] {
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: missingMSBs)
        return (try? HTBlockLayoutConformant.assemble(magsgn: ms, mel: mel, vlc: vlc)) ?? []
    }

    /// Decode block bytes via Swift reference.
    private func decodeSwift(block: [UInt8], width: Int, height: Int, missingMSBs: Int) -> [UInt32]? {
        return try? HTBlockDecoderConformant.decode(
            block: block, width: width, height: height, missingMSBs: missingMSBs)
    }

    /// Decode block bytes via the C port. `useSimd` selects between the
    /// scalar reference reconstruction and the v10.6 NEON SIMD path
    /// (added with `reconstruct_use_simd` parameter to
    /// `j2knhd_decode_block_ht32`).
    private func decodeC(block: [UInt8], width: Int, height: Int, missingMSBs: Int, useSwar: Bool, useSimd: Bool = false) -> [UInt32]? {
        var coefs = [UInt32](repeating: 0, count: width * height)
        let rc: Int32 = block.withUnsafeBufferPointer { bp -> Int32 in
            return vlcDecoderTable0Conformant.withUnsafeBufferPointer { t0 in
                return vlcDecoderTable1Conformant.withUnsafeBufferPointer { t1 in
                    return coefs.withUnsafeMutableBufferPointer { co in
                        return j2knhd_decode_block_ht32(
                            bp.baseAddress, bp.count,
                            UInt32(width), UInt32(height), UInt32(missingMSBs),
                            t0.baseAddress, t1.baseAddress,
                            useSwar,
                            useSimd,
                            co.baseAddress)
                    }
                }
            }
        }
        return rc == 0 ? coefs : nil
    }

    private func assertRoundTripParity(
        coefs: [UInt32], width: Int, height: Int, missingMSBs: Int,
        useSwar: Bool, label: String
    ) {
        let block = encodeBlock(coefs: coefs, width: width, height: height, missingMSBs: missingMSBs)
        XCTAssertFalse(block.isEmpty, "\(label): empty block")
        guard let swiftOut = decodeSwift(block: block, width: width, height: height, missingMSBs: missingMSBs) else {
            XCTFail("\(label): Swift decode failed"); return
        }
        XCTAssertEqual(swiftOut.count, coefs.count, "\(label): Swift output count")
        XCTAssertEqual(swiftOut, coefs, "\(label): Swift round-trip self-mismatch")

        guard let cOut = decodeC(block: block, width: width, height: height, missingMSBs: missingMSBs, useSwar: useSwar) else {
            XCTFail("\(label): C decode failed (returned nil / non-zero rc)"); return
        }
        XCTAssertEqual(cOut.count, coefs.count, "\(label): C output count")
        if cOut != swiftOut {
            // Find first divergence + report compact context.
            var first = -1
            for i in 0..<min(cOut.count, swiftOut.count) where cOut[i] != swiftOut[i] {
                first = i; break
            }
            XCTFail("\(label): C output diverges from Swift at index \(first); Swift=\(String(format: "0x%08X", swiftOut[max(0,first)])) C=\(String(format: "0x%08X", cOut[max(0,first)])); block len=\(block.count)")
        }
    }

    // MARK: - Tests

    func testParity_64x64_5pct_scalar() {
        let coefs = Self.makeCoefficients(width: 64, height: 64, density: 0.05, seed: 0x101)
        assertRoundTripParity(coefs: coefs, width: 64, height: 64, missingMSBs: 0,
                              useSwar: false, label: "64x64 5% scalar")
    }

    func testParity_64x64_5pct_swar() {
        let coefs = Self.makeCoefficients(width: 64, height: 64, density: 0.05, seed: 0x101)
        assertRoundTripParity(coefs: coefs, width: 64, height: 64, missingMSBs: 0,
                              useSwar: true, label: "64x64 5% swar")
    }

    func testParity_64x64_25pct_swar() {
        let coefs = Self.makeCoefficients(width: 64, height: 64, density: 0.25, seed: 0x102)
        assertRoundTripParity(coefs: coefs, width: 64, height: 64, missingMSBs: 0,
                              useSwar: true, label: "64x64 25% swar")
    }

    func testParity_64x64_50pct_swar() {
        let coefs = Self.makeCoefficients(width: 64, height: 64, density: 0.50, seed: 0x103)
        assertRoundTripParity(coefs: coefs, width: 64, height: 64, missingMSBs: 0,
                              useSwar: true, label: "64x64 50% swar")
    }

    /// Smaller block sizes — exercises odd-width / odd-height paths.
    func testParity_smallBlocks() {
        let cases: [(Int, Int)] = [
            (4, 4), (8, 8), (16, 16), (32, 32),
            (4, 16), (16, 4),
            (5, 7), (7, 5),
            (9, 13), (13, 9),
            (15, 17), (17, 15),
            (32, 16), (16, 32),
            (33, 33), (63, 63)
        ]
        for (w, h) in cases {
            for density in [0.05, 0.25, 0.50] {
                let coefs = Self.makeCoefficients(width: w, height: h,
                                                  density: density,
                                                  seed: UInt64(w * 1000 + h) ^ UInt64(bitPattern: Int64(density * 1e7)))
                assertRoundTripParity(coefs: coefs, width: w, height: h, missingMSBs: 0,
                                      useSwar: true, label: "\(w)x\(h) \(Int(density*100))% swar")
            }
        }
    }

    /// missingMSBs sweep — common medical bit-depths.
    func testParity_missingMSBsSweep() {
        let coefs = Self.makeCoefficients(width: 64, height: 64, density: 0.25, seed: 0x501)
        for mm in [0, 1, 4, 8, 12, 16, 20, 25, 29] {
            // Re-derive bin-centered coefs at the right p for each missingMSBs.
            // Quick rebuild: scale magnitudes to p = 30 - missingMSBs.
            let p = UInt32(30 - mm)
            var scaled = [UInt32](repeating: 0, count: coefs.count)
            for i in 0..<coefs.count {
                if coefs[i] != 0 {
                    let sign = (coefs[i] & 0x8000_0000) != 0
                    scaled[i] = Self.binCenter(mu: 1, sign: sign, p: p)
                }
            }
            assertRoundTripParity(coefs: scaled, width: 64, height: 64,
                                  missingMSBs: mm, useSwar: true,
                                  label: "missingMSBs=\(mm)")
        }
    }

    /// All-zero block — degenerate but common case.
    func testParity_allZeroBlock() {
        let coefs = [UInt32](repeating: 0, count: 64 * 64)
        assertRoundTripParity(coefs: coefs, width: 64, height: 64, missingMSBs: 0,
                              useSwar: true, label: "all-zero 64x64 swar")
    }

    /// Larger random sweep at 64×64 to stress the state machine across
    /// many distinct stream patterns.
    func testParity_64x64_randomSweep_32Trials() {
        for trial in 0..<32 {
            let density = 0.05 + Double(trial % 5) * 0.10  // 0.05..0.45
            let coefs = Self.makeCoefficients(
                width: 64, height: 64, density: density,
                seed: UInt64(trial) &* 0xABCDEF0123456789)
            assertRoundTripParity(coefs: coefs, width: 64, height: 64, missingMSBs: 0,
                                  useSwar: true, label: "rand-\(trial)-d\(Int(density*100))%")
        }
    }
}
#endif
