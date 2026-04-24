// J2KHTBlockLayoutConformantTests.swift
// Unit tests for the ISO/IEC 15444-15 codeblock layout assembler
// and parser. Validates Scup round-trip, stream region offsets, and
// boundary/error conditions.

import XCTest
@testable import J2KCodec

final class HTBlockLayoutConformantTests: XCTestCase {

    // MARK: - Assembly + parse round-trip

    func testAssembleParseRoundTrip() throws {
        let magsgn: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let mel:    [UInt8] = [0x10, 0x20, 0x30]
        let vlc:    [UInt8] = [0xAA, 0xBB, 0xCC, 0xFF]   // last = sentinel

        let block = try HTBlockLayoutConformant.assemble(
            magsgn: magsgn, mel: mel, vlc: vlc)
        XCTAssertEqual(block.count, magsgn.count + mel.count + vlc.count)

        guard let parsed = HTBlockLayoutConformant.parse(block: block) else {
            XCTFail("parse returned nil for valid block")
            return
        }
        XCTAssertEqual(parsed.scup, mel.count + vlc.count)
        XCTAssertEqual(Array(parsed.magsgn), magsgn)
        XCTAssertEqual(parsed.magsgn.count, magsgn.count)
        XCTAssertEqual(parsed.melVlc.count, mel.count + vlc.count)
    }

    /// Scup writes into the block: high 8 bits go to last byte, low
    /// 4 bits into low nibble of second-to-last byte.
    func testScupBitsLandInLastTwoBytes() throws {
        let magsgn: [UInt8] = [0x00]
        let mel:    [UInt8] = Array(repeating: 0x00, count: 3)
        // VLC with known last-two bytes pattern so we can verify the
        // scup low-nibble merge + high-byte clobber.
        let vlc:    [UInt8] = [0xAA, 0x50, 0xFF] // high nibble of 0x50 = 0x5
        let scup = mel.count + vlc.count             // 6
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: magsgn, mel: mel, vlc: vlc)
        let lcup = block.count

        // block[lcup-1] = scup >> 4 = 6 >> 4 = 0
        XCTAssertEqual(block[lcup - 1], UInt8(scup >> 4))
        // block[lcup-2] low nibble = scup & 0xF = 6; high nibble kept
        XCTAssertEqual(block[lcup - 2] & 0x0F, UInt8(scup & 0x0F))
        XCTAssertEqual(block[lcup - 2] & 0xF0, 0x50,
                       "high nibble of block[lcup-2] must preserve VLC data")
    }

    /// Large Scup: 4079 is the documented maximum. 4080+ must raise
    /// the scupOutOfRange error.
    func testScupOutOfRangeAtUpperBoundary() {
        // Need scup = 4080 = mel + vlc. Any split works.
        let mel = [UInt8](repeating: 0x00, count: 2000)
        let vlc = [UInt8](repeating: 0x00, count: 2080)
        XCTAssertThrowsError(try HTBlockLayoutConformant.assemble(
            magsgn: [], mel: mel, vlc: vlc)) { err in
            XCTAssertEqual(err as? HTBlockLayoutConformantError,
                           .scupOutOfRange(4080))
        }
    }

    /// Scup at exact upper boundary (4079) should succeed and
    /// round-trip.
    func testScupAtUpperBoundarySucceeds() throws {
        let mel = [UInt8](repeating: 0x00, count: 2000)
        let vlc = [UInt8](repeating: 0x55, count: 2079)
        let block = try HTBlockLayoutConformant.assemble(
            magsgn: [], mel: mel, vlc: vlc)
        guard let parsed = HTBlockLayoutConformant.parse(block: block) else {
            XCTFail("parse returned nil for valid block"); return
        }
        XCTAssertEqual(parsed.scup, 4079)
    }

    // MARK: - Edge cases

    /// Parse must reject blocks that are too short to contain Scup.
    func testParseRejectsEmptyBlock() {
        XCTAssertNil(HTBlockLayoutConformant.parse(block: []))
        XCTAssertNil(HTBlockLayoutConformant.parse(block: [0x00]))
    }

    /// Parse must reject blocks whose Scup value is > block length.
    func testParseRejectsOversizeScup() {
        // Manually craft a block with Scup = 255 but only 10 bytes.
        // high 8 bits of scup = 255 >> 4 = 0x0F; low 4 = 0x0F.
        var block = [UInt8](repeating: 0x00, count: 10)
        block[9] = 0x0F
        block[8] = 0x0F // low nibble = 0xF
        XCTAssertNil(HTBlockLayoutConformant.parse(block: block))
    }

    /// Assembly must reject too-small streams where Scup would
    /// collapse below 2 bytes.
    func testAssembleRejectsTinyStreams() {
        XCTAssertThrowsError(try HTBlockLayoutConformant.assemble(
            magsgn: [], mel: [0x01], vlc: [])) { err in
            XCTAssertEqual(err as? HTBlockLayoutConformantError,
                           .scupOutOfRange(1))
        }
    }
}
