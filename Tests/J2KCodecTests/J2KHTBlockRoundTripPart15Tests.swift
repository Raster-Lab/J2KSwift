// J2KHTBlockRoundTripPart15Tests.swift
// Self round-trip tests for the Part-15 codeblock encoder + decoder.
//
// These tests feed coefficients through the cleanup-pass encoder
// (M5b), assemble the resulting streams with the block layout
// (M5a), then parse and decode them back through the reference
// decoder (M5c). Used to catch logic divergences between encoder
// and decoder before cross-validating against OpenJPH (M7).

import XCTest
@testable import J2KCodec

final class HTBlockRoundTripPart15Tests: XCTestCase {

    /// All-zero block: MagSgn is empty; the decoder must reconstruct
    /// all zeros. Smallest possible case.
    func testAllZeroRoundTrip() throws {
        let coefs = [UInt32](repeating: 0, count: 8)
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: 4, height: 2, missingMSBs: 0)
        let block = try HTBlockLayoutPart15.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderPart15.decode(
            block: block, width: 4, height: 2, missingMSBs: 0)
        XCTAssertEqual(decoded, [UInt32](repeating: 0, count: 8))
    }

    /// 1x1 zero: smallest possible block.
    func testSingleZeroRoundTrip() throws {
        let coefs: [UInt32] = [0]
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: 1, height: 1, missingMSBs: 0)
        let block = try HTBlockLayoutPart15.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let decoded = try HTBlockDecoderPart15.decode(
            block: block, width: 1, height: 1, missingMSBs: 0)
        XCTAssertEqual(decoded, [0])
    }
}
