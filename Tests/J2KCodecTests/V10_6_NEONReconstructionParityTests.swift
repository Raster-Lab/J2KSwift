// V10_6_NEONReconstructionParityTests.swift
//
// v10.6-research — bit-exact parity oracle for the C+NEON SIMD
// reconstruction path (`read_quad_samples_simd`) vs the scalar
// reference (`read_quad_samples_scalar`) inside
// `j2knhd_decode_block_ht32`.
//
// Strategy: round-trip a set of synthetic coefficient blocks through
// the Swift encoder, then decode each twice via the C entry point —
// once with `reconstruct_use_simd = false` (scalar reference), once
// with `reconstruct_use_simd = true` (v10.6 SIMD port). Every output
// byte must match across the two paths.
//
// Bit-exactness is required by construction: the SIMD path mirrors
// the scalar arithmetic lane-parallel and uses `vshlq_u32` with shift
// counts that produce 0 at ≥ 32 — matching Swift's `1 &<< 32 = 0`
// wraparound that drives the `(1 << m) - 1` mask through to ~0u on
// the m == 32 edge case.
//
// Run with:
//   swift test -c release --filter V10_6_NEONReconstructionParityTests

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_6_NEONReconstructionParityTests: XCTestCase {

    // MARK: - Synthetic block generator

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

    // MARK: - C decoder dispatch helper

    private func decodeC(
        block: [UInt8], width: Int, height: Int, missingMSBs: Int,
        useSimd: Bool
    ) -> [UInt32]? {
        var coefs = [UInt32](repeating: 0, count: width * height)
        let rc: Int32 = block.withUnsafeBufferPointer { bp -> Int32 in
            return vlcDecoderTable0Conformant.withUnsafeBufferPointer { t0 in
                return vlcDecoderTable1Conformant.withUnsafeBufferPointer { t1 in
                    return coefs.withUnsafeMutableBufferPointer { co in
                        return j2knhd_decode_block_ht32(
                            bp.baseAddress, bp.count,
                            UInt32(width), UInt32(height), UInt32(missingMSBs),
                            t0.baseAddress, t1.baseAddress,
                            /* useSwar */ true,
                            /* reconstruct_use_simd */ useSimd,
                            co.baseAddress)
                    }
                }
            }
        }
        return rc == 0 ? coefs : nil
    }

    private func assertParity(
        coefs: [UInt32], width: Int, height: Int, missingMSBs: Int,
        label: String
    ) {
        // Encode via Swift reference.
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: missingMSBs)
        let block = (try? HTBlockLayoutConformant.assemble(magsgn: ms, mel: mel, vlc: vlc)) ?? []
        XCTAssertFalse(block.isEmpty, "[\(label)] empty block")

        // Decode twice — scalar then SIMD.
        guard let scalarOut = decodeC(
            block: block, width: width, height: height,
            missingMSBs: missingMSBs, useSimd: false) else {
            XCTFail("[\(label)] C scalar decode returned non-zero"); return
        }
        guard let simdOut = decodeC(
            block: block, width: width, height: height,
            missingMSBs: missingMSBs, useSimd: true) else {
            XCTFail("[\(label)] C SIMD decode returned non-zero"); return
        }

        XCTAssertEqual(scalarOut.count, simdOut.count, "[\(label)] output count")
        if scalarOut != simdOut {
            // Find first divergence + report context.
            var first = -1
            for i in 0..<min(scalarOut.count, simdOut.count) where scalarOut[i] != simdOut[i] {
                first = i; break
            }
            let lo = max(0, first - 2)
            let hi = min(scalarOut.count, first + 3)
            var ctx = ""
            for i in lo..<hi {
                let mark = (i == first) ? "*" : " "
                ctx += "[\(i)\(mark)] s=0x\(String(scalarOut[i], radix: 16)) v=0x\(String(simdOut[i], radix: 16))  "
            }
            XCTFail("[\(label)] SIMD diverges from scalar at idx \(first); \(ctx)")
        }

        // Also confirm both round-trip cleanly.
        XCTAssertEqual(scalarOut, coefs, "[\(label)] scalar round-trip self-mismatch")
        XCTAssertEqual(simdOut, coefs, "[\(label)] SIMD round-trip self-mismatch")
    }

    // MARK: - Tests

    func testSimdParity_smallSizes() {
        let cases: [(Int, Int, Double, UInt64, String)] = [
            (4, 4, 0.5, 0xA001, "4x4 50%"),
            (8, 8, 0.3, 0xA002, "8x8 30%"),
            (16, 16, 0.3, 0xA003, "16x16 30%"),
            (32, 32, 0.3, 0xA004, "32x32 30%"),
            (64, 64, 0.3, 0xA005, "64x64 30%")
        ]
        for (w, h, d, seed, label) in cases {
            let coefs = Self.makeCoefficients(width: w, height: h, density: d, seed: seed)
            assertParity(coefs: coefs, width: w, height: h, missingMSBs: 0, label: label)
        }
    }

    func testSimdParity_densitySweep_64x64() {
        for (i, density) in [0.05, 0.10, 0.25, 0.50, 0.75, 0.95].enumerated() {
            let coefs = Self.makeCoefficients(
                width: 64, height: 64, density: density,
                seed: UInt64(i + 1) &* 0xCAFE_BABE)
            assertParity(coefs: coefs, width: 64, height: 64, missingMSBs: 0,
                         label: "64x64 density \(density)")
        }
    }

    func testSimdParity_randomSweep_32Trials() {
        // Use missingMSBs = 0 throughout (mirrors V10_2_DecodeBlockParityTests).
        // The synthetic `binCenter(mu:1, p:30)` is calibrated to p=30 which
        // corresponds to missingMSBs=0 — varying missingMSBs would require
        // a matching scale change in `makeCoefficients`, out of scope for
        // this oracle.
        var state: UInt64 = 0xA1B2_C3D4_E5F6_0718
        for trial in 0..<32 {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            let widthChoices = [8, 16, 32, 64]
            let densityChoices = [0.05, 0.20, 0.40, 0.70]
            let w = widthChoices[Int(state >> 56) % widthChoices.count]
            let h = widthChoices[Int((state >> 48) & 0xFF) % widthChoices.count]
            let d = densityChoices[Int((state >> 40) & 0xFF) % densityChoices.count]
            let coefs = Self.makeCoefficients(width: w, height: h, density: d, seed: state)
            assertParity(coefs: coefs, width: w, height: h, missingMSBs: 0,
                         label: "rnd trial \(trial) w=\(w) h=\(h) d=\(d)")
        }
    }
}
#endif
