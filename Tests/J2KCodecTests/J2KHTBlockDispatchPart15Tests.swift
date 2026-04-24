// J2KHTBlockDispatchPart15Tests.swift
// End-to-end tests for the Part-15 dispatch layer that adapts
// pipeline-level Int32 coefficients to HTBlockEncoderPart15 /
// HTBlockDecoderPart15 and wraps the result in HTEncodedBlock.

import XCTest
@testable import J2KCodec

final class HTBlockDispatchPart15Tests: XCTestCase {

    /// Default `HTEncodedBlock.format` must be `.custom` so
    /// existing v4.x call sites are source-compatible.
    func testDefaultFormatIsCustom() {
        let block = HTEncodedBlock(
            codedData: Data(),
            passType: .htCleanup,
            melLength: 0, vlcLength: 0, magsgnLength: 0,
            bitPlane: 0, width: 32, height: 32)
        XCTAssertEqual(block.format, .custom)
    }

    /// Encoder → decoder round-trip via the dispatch layer with a
    /// bin-centered positive sample.
    func testEncodeDecodePart15SingleSample() throws {
        let encoder = HTBlockEncoder(width: 4, height: 2, subband: .hh)
        // μ_p = 1 at bit-plane 30, positive → coefficient 0x6000_0000.
        // Interpreted as Int32 that's 0x6000_0000 as well (positive).
        var coefs = [Int32](repeating: 0, count: 8)
        coefs[0] = Int32(bitPattern: 0x6000_0000)

        let block = try encoder.encodeCleanupPart15(coefficients: coefs)
        XCTAssertEqual(block.format, .part15)
        XCTAssertEqual(block.passType, .htCleanup)
        XCTAssertEqual(block.width, 4)
        XCTAssertEqual(block.height, 2)

        let decoder = HTBlockDecoder(width: 4, height: 2, subband: .hh)
        let decoded = try decoder.decodeCleanupPart15(from: block)
        XCTAssertEqual(decoded, coefs)
    }

    /// Negative sign pattern: μ_p = 1, negative → Int32
    /// `Int32(bitPattern: 0xE000_0000)`.
    func testEncodeDecodePart15NegativeSample() throws {
        let encoder = HTBlockEncoder(width: 4, height: 2, subband: .hh)
        var coefs = [Int32](repeating: 0, count: 8)
        coefs[0] = Int32(bitPattern: 0xE000_0000)

        let block = try encoder.encodeCleanupPart15(coefficients: coefs)
        let decoder = HTBlockDecoder(width: 4, height: 2, subband: .hh)
        let decoded = try decoder.decodeCleanupPart15(from: block)
        XCTAssertEqual(decoded, coefs)
    }

    /// All-zero round-trip via dispatch.
    func testEncodeDecodePart15AllZeros() throws {
        let encoder = HTBlockEncoder(width: 4, height: 2, subband: .hh)
        let coefs = [Int32](repeating: 0, count: 8)

        let block = try encoder.encodeCleanupPart15(coefficients: coefs)
        let decoder = HTBlockDecoder(width: 4, height: 2, subband: .hh)
        let decoded = try decoder.decodeCleanupPart15(from: block)
        XCTAssertEqual(decoded, coefs)
    }

    /// Decoder refuses Part-15 handling of a `.custom` block.
    func testDecoderRejectsWrongFormat() throws {
        let block = HTEncodedBlock(
            codedData: Data([0x00, 0x00]),
            passType: .htCleanup,
            melLength: 0, vlcLength: 0, magsgnLength: 0,
            bitPlane: 0, width: 4, height: 2,
            format: .custom)
        let decoder = HTBlockDecoder(width: 4, height: 2, subband: .hh)
        XCTAssertThrowsError(try decoder.decodeCleanupPart15(from: block))
    }
}
