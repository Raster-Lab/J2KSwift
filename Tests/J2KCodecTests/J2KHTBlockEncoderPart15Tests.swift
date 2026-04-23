// J2KHTBlockEncoderPart15Tests.swift
// Structural tests for the cleanup-pass codeblock encoder.
//
// A full self round-trip needs the decoder (M5c / M7); for now we
// verify the encoder produces non-empty, structurally well-formed
// streams that the block-layout assembler can accept, and that
// trivial input patterns (all zeros) produce the expected minimal
// encoding.

import XCTest
@testable import J2KCodec

final class HTBlockEncoderPart15Tests: XCTestCase {

    /// Encoding an all-zero 4x4 block must produce no significant
    /// MagSgn data: all samples are zero so rho=0 for every quad
    /// and no magnitude bits are emitted.
    func testAllZeroBlockProducesEmptyMagSgn() {
        let coefs = [UInt32](repeating: 0, count: 16)
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: 4, height: 4, missingMSBs: 0)
        XCTAssertEqual(ms.count, 0, "no magnitude bits for zero block")
        // MEL + VLC are non-empty because we still emit signalling
        // bits (rho=0 events for c_q=0 quads, UVLC prefixes).
        XCTAssertGreaterThan(mel.count + vlc.count, 0)
        // VLC's last element is the 0xFF sentinel (reverse emitter
        // seeds the stream with this byte).
        XCTAssertEqual(vlc.last, 0xFF)
    }

    /// Assembly over the encoder output must produce a block with a
    /// valid Scup trailer that parses back to the same MagSgn region.
    func testEncodeAssembleParse() throws {
        var coefs = [UInt32](repeating: 0, count: 16)
        // Plant a few non-zero samples with known magnitudes.
        // Sign bit in MSB; low-bit magnitude encoded per OpenJPH's
        // sign-magnitude convention.
        coefs[0] = 0x0000_0004    // +4
        coefs[5] = 0x0000_0002    // +2
        coefs[10] = 0x8000_0008   // -8
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: 4, height: 4, missingMSBs: 0)
        let block = try HTBlockLayoutPart15.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        guard let parsed = HTBlockLayoutPart15.parse(block: block) else {
            XCTFail("assembled block failed to parse"); return
        }
        XCTAssertEqual(parsed.scup, mel.count + vlc.count)
        XCTAssertEqual(Array(parsed.magsgn), ms)
    }

    /// Varying the block dimensions should not crash; smoke-test a
    /// range of small sizes with a uniform high-magnitude input.
    func testEncoderSurvivesDimensionSweep() {
        for width in [1, 2, 3, 4, 7, 8, 16] {
            for height in [1, 2, 3, 4, 7, 8] {
                let coefs = [UInt32](
                    repeating: 0x0000_0010, count: width * height)
                let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
                    coefficients: coefs, width: width, height: height,
                    missingMSBs: 0)
                XCTAssertGreaterThan(vlc.count, 0,
                                     "\(width)x\(height) produced empty VLC")
                XCTAssertEqual(vlc.last, 0xFF,
                               "\(width)x\(height) missing VLC sentinel")
                _ = (ms, mel)
            }
        }
    }

    /// Encode a 1x1 block with a significant sample — must still
    /// produce a valid structure (no crashes in edge-case branches).
    func testSinglePixelBlock() throws {
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: [0x0000_0008], width: 1, height: 1, missingMSBs: 0)
        let block = try HTBlockLayoutPart15.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        XCTAssertNotNil(HTBlockLayoutPart15.parse(block: block))
    }
}
