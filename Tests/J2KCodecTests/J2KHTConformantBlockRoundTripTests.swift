// J2KHTBlockRoundTripConformantTests.swift
// Self round-trip tests for the Part-15 codeblock encoder + decoder.
//
// These tests feed coefficients through the cleanup-pass encoder
// (M5b), assemble the resulting streams with the block layout
// (M5a), then parse and decode them back through the reference
// decoder (M5c). Used to catch logic divergences between encoder
// and decoder before cross-validating against OpenJPH (M7).

import XCTest
@testable import J2KCodec

final class HTBlockRoundTripConformantTests: XCTestCase {

    /// All-zero block: MagSgn is empty; the decoder must reconstruct
    /// all zeros. Smallest possible case.
    func testAllZeroRoundTrip() throws {
        let coefs = [UInt32](repeating: 0, count: 8)
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 4, height: 2, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 4, height: 2, missingMSBs: 0)
        XCTAssertEqual(decoded, [UInt32](repeating: 0, count: 8))
    }

    /// 1x1 zero: smallest possible block.
    func testSingleZeroRoundTrip() throws {
        let coefs: [UInt32] = [0]
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 1, height: 1, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 1, height: 1, missingMSBs: 0)
        XCTAssertEqual(decoded, [0])
    }

    /// Bin-centered positive coefficient: input aligned to the
    /// `(2μ_p + 1) << (p - 1)` quantization-bin center at p=30
    /// should round-trip exactly. μ_p=1 → input 0x6000_0000.
    func testSingleBinCenteredPositiveRoundTrip() throws {
        let coefs: [UInt32] = [0x6000_0000]
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 1, height: 1, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 1, height: 1, missingMSBs: 0)
        XCTAssertEqual(decoded, coefs)
    }

    /// Bin-centered negative coefficient: sign bit set at bit 31.
    /// μ_p=1, negative → input = 0xE000_0000.
    func testSingleBinCenteredNegativeRoundTrip() throws {
        let coefs: [UInt32] = [0xE000_0000]
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 1, height: 1, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 1, height: 1, missingMSBs: 0)
        XCTAssertEqual(decoded, coefs)
    }

    /// 4x2 block with scattered bin-centered samples: exercises the
    /// quad-pair iterator, c_q propagation, per-sample sign handling.
    func testScattered4x2BinCenteredRoundTrip() throws {
        var coefs = [UInt32](repeating: 0, count: 8)
        // Two quads, each with one active sample at bin center.
        coefs[0] = 0x6000_0000    // quad 0, sample (0,0): +μ_p=1
        coefs[6] = 0xE000_0000    // quad 1, sample (0,1): -μ_p=1
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 4, height: 2, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 4, height: 2, missingMSBs: 0)
        XCTAssertEqual(decoded, coefs)
    }

    /// 8x2 block: two full quad-pairs, exercises c_q propagation
    /// across pair boundaries.
    func testWidth8TwoQuadPairsRoundTrip() throws {
        var coefs = [UInt32](repeating: 0, count: 16)
        coefs[0] = 0x6000_0000
        coefs[8] = 0x6000_0000
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 8, height: 2, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 8, height: 2, missingMSBs: 0)
        XCTAssertEqual(decoded, coefs)
    }

    /// 4x4 all-zero block: tests the subsequent-row (y >= 2) decoder
    /// path against an encoder with empty eVal/cxVal carryover.
    func testAllZero4x4RoundTrip() throws {
        let coefs = [UInt32](repeating: 0, count: 16)
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 4, height: 4, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 4, height: 4, missingMSBs: 0)
        XCTAssertEqual(decoded, coefs)
    }

    /// 4x4 block with samples in both the initial row (y=0,1) and
    /// subsequent row (y=2,3) — exercises the max_e + kappa context
    /// flow between rows.
    func testTwoRowSamples4x4RoundTrip() throws {
        var coefs = [UInt32](repeating: 0, count: 16)
        coefs[0]  = 0x6000_0000  // (0, 0) in initial quad row
        coefs[9]  = 0xE000_0000  // (1, 2) in subsequent quad row
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 4, height: 4, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 4, height: 4, missingMSBs: 0)
        XCTAssertEqual(decoded, coefs)
    }

    /// 8x4 block: two quad-pairs by two quad-rows. Validates the
    /// full context cascade (c_q across pairs AND max_e across rows).
    func testDense8x4RoundTrip() throws {
        var coefs = [UInt32](repeating: 0, count: 32)
        // Plant a diagonal of bin-centered samples.
        coefs[0]  = 0x6000_0000
        coefs[9]  = 0x6000_0000
        coefs[18] = 0xE000_0000
        coefs[27] = 0xE000_0000
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: 8, height: 4, missingMSBs: 0)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderConformant.decode(
            block: block, width: 8, height: 4, missingMSBs: 0)
        XCTAssertEqual(decoded, coefs)
    }
}
