// J2KHTBlockDispatchConformantTests.swift
// End-to-end tests for the Part-15 dispatch layer that adapts
// pipeline-level Int32 coefficients to HTBlockEncoderConformant /
// HTBlockDecoderConformant and wraps the result in HTEncodedBlock.

import XCTest
@testable import J2KCodec

final class HTBlockDispatchConformantTests: XCTestCase {

    /// `HTEncodedBlock.format` defaults to `.custom` at the struct
    /// level (call sites that don't set it still get the legacy
    /// format). The pipeline-level default is `.conformant` via the
    /// encoding configuration flag.
    func testStructDefaultFormatIsCustom() {
        let block = HTEncodedBlock(
            codedData: Data(),
            passType: .htCleanup,
            melLength: 0, vlcLength: 0, magsgnLength: 0,
            bitPlane: 0, width: 32, height: 32)
        XCTAssertEqual(block.format, .custom)
    }

    /// Block-level dispatch: inputs/outputs are raw OpenJPH
    /// sign-magnitude UInt32 (reinterpreted as Int32 bit patterns).
    /// μ_p = 1 at bit-plane 30 → bin-centered value 0x6000_0000.
    func testEncodeDecodeConformantSingleSample() throws {
        let encoder = HTBlockEncoder(width: 4, height: 2, subband: .hh)
        var coefs = [Int32](repeating: 0, count: 8)
        coefs[0] = Int32(bitPattern: 0x6000_0000)

        let block = try encoder.encodeCleanupConformant(coefficients: coefs)
        XCTAssertEqual(block.format, .conformant)
        XCTAssertEqual(block.passType, .htCleanup)
        XCTAssertEqual(block.width, 4)
        XCTAssertEqual(block.height, 2)

        let decoder = HTBlockDecoder(width: 4, height: 2, subband: .hh)
        let decoded = try decoder.decodeCleanupConformant(from: block)
        XCTAssertEqual(decoded, coefs)
    }

    /// Negative sign pattern: μ_p = 1, negative → bin-centered
    /// value 0xE000_0000 at the block level.
    func testEncodeDecodeConformantNegativeSample() throws {
        let encoder = HTBlockEncoder(width: 4, height: 2, subband: .hh)
        var coefs = [Int32](repeating: 0, count: 8)
        coefs[0] = Int32(bitPattern: 0xE000_0000)

        let block = try encoder.encodeCleanupConformant(coefficients: coefs)
        let decoder = HTBlockDecoder(width: 4, height: 2, subband: .hh)
        let decoded = try decoder.decodeCleanupConformant(from: block)
        XCTAssertEqual(decoded, coefs)
    }

    /// All-zero round-trip via dispatch.
    func testEncodeDecodeConformantAllZeros() throws {
        let encoder = HTBlockEncoder(width: 4, height: 2, subband: .hh)
        let coefs = [Int32](repeating: 0, count: 8)

        let block = try encoder.encodeCleanupConformant(coefficients: coefs)
        let decoder = HTBlockDecoder(width: 4, height: 2, subband: .hh)
        let decoded = try decoder.decodeCleanupConformant(from: block)
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
        XCTAssertThrowsError(try decoder.decodeCleanupConformant(from: block))
    }
}
