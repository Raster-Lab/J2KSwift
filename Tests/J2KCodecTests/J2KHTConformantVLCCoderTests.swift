// J2KHTVLCCoderConformantTests.swift
// Unit tests for the ISO/IEC 15444-15 VLC + UVLC codebook primitives.
//
// Validates the 2048-entry `vlcTable0Conformant` / `vlcTable1Conformant`
// lookup tables against hand-computed entries derived from OpenJPH's
// `table0.h` / `table1.h`, and verifies the 75-entry UVLC codebook
// against the prefix/suffix/extension structure documented in
// `ojph_block_encoder.cpp::uvlc_init_tables`.

import XCTest
@testable import J2KCodec

final class HTVLCCoderConformantTests: XCTestCase {

    // MARK: - VLC lookup table

    /// Guard: index 0 (c_q = 0, rho = 0, emb = 0) must be 0.
    func testTable0GuardZero() {
        XCTAssertEqual(vlcTable0Conformant[0], 0)
        XCTAssertEqual(vlcTable1Conformant[0], 0)
    }

    /// For indices where `(emb & rho) != emb` the guard clause zeroes
    /// the entry. Spot-check: c_q=0, rho=0x1, emb=0x2 → 2 & 1 = 0 != 2.
    func testTable0InvalidEmb() {
        let idx = (0 << 8) | (0x1 << 4) | 0x2
        XCTAssertEqual(vlcTable0Conformant[idx], 0)
    }

    /// Table0 entry for c_q=0, rho=1, emb=0 corresponds to the source
    /// row `VLCSrc(0, 0x1, 0x0, 0x0, 0x0, 0x06, 4)`, packed as
    /// `(cwd << 8) | (cwd_len << 4) | e_k`.
    func testTable0KnownU0Entry() {
        let idx = (0 << 8) | (0x1 << 4) | 0x0
        let expected: UInt16 = UInt16((0x06 << 8) | (4 << 4) | 0)
        XCTAssertEqual(vlcTable0Conformant[idx], expected)
    }

    /// Table0 entry for c_q=0, rho=1, emb=1: u_off=1 row
    /// `VLCSrc(0, 0x1, 0x1, 0x1, 0x1, 0x3F, 7)`.
    func testTable0KnownU1Entry() {
        let idx = (0 << 8) | (0x1 << 4) | 0x1
        let expected: UInt16 = UInt16((0x3F << 8) | (7 << 4) | 0x1)
        XCTAssertEqual(vlcTable0Conformant[idx], expected)
    }

    /// Table1 entry for c_q=0, rho=1, emb=0 corresponds to the source
    /// row `VLCSrc(0, 0x1, 0x0, 0x0, 0x0, 0x00, 3)`.
    func testTable1KnownU0Entry() {
        let idx = (0 << 8) | (0x1 << 4) | 0x0
        let expected: UInt16 = UInt16((0x00 << 8) | (3 << 4) | 0)
        XCTAssertEqual(vlcTable1Conformant[idx], expected)
    }

    /// Verify `HTVLCCoderConformant.lookupQuad` unpacks entries correctly.
    func testLookupQuadUnpack() {
        let (cwd, len, ek) = HTVLCCoderConformant.lookupQuad(
            initialLine: true, c_q: 0, rho: 0x1, emb: 0x1)
        XCTAssertEqual(cwd, 0x3F)
        XCTAssertEqual(len, 7)
        XCTAssertEqual(ek, 0x1)
    }

    // MARK: - UVLC codebook

    /// Length table per `uvlc_init_tables`: u in 0..4 uses short
    /// prefix+short-suffix, 5..32 uses 3-bit prefix + 5-bit suffix,
    /// 33..74 adds a 4-bit extension.
    func testUVLCLengthsMatchDocumentedPattern() {
        let expectedTotalBits: [Int] = [
            0,                  // u = 0 → no bits
            1,                  // u = 1 → 1-bit prefix
            2,                  // u = 2 → 2-bit prefix
            3 + 1,              // u = 3 → 3-bit prefix + 1 suffix bit
            3 + 1               // u = 4 → same
        ]
            + Array(repeating: 3 + 5, count: 33 - 5)  // u in 5..32
            + Array(repeating: 3 + 5 + 4, count: 75 - 33) // u in 33..74

        for u in 0..<75 {
            let e = uvlcTableConformant[u]
            let actual = Int(e.preLen) + Int(e.sufLen) + Int(e.extLen)
            XCTAssertEqual(actual, expectedTotalBits[u],
                           "u=\(u) total bits")
        }
    }

    /// Specific entries documented in `uvlc_init_tables`.
    func testUVLCEntries0Through4() {
        XCTAssertEqual(uvlcTableConformant[0].pre,    0)
        XCTAssertEqual(uvlcTableConformant[0].preLen, 0)
        XCTAssertEqual(uvlcTableConformant[1].pre,    1)
        XCTAssertEqual(uvlcTableConformant[1].preLen, 1)
        XCTAssertEqual(uvlcTableConformant[2].pre,    2)
        XCTAssertEqual(uvlcTableConformant[2].preLen, 2)
        XCTAssertEqual(uvlcTableConformant[3].pre,    4)
        XCTAssertEqual(uvlcTableConformant[3].preLen, 3)
        XCTAssertEqual(uvlcTableConformant[3].suf,    0)
        XCTAssertEqual(uvlcTableConformant[3].sufLen, 1)
        XCTAssertEqual(uvlcTableConformant[4].suf,    1)
    }

    /// u = 5..32: prefix is always 0 with 3 bits, suffix is `u - 5`.
    func testUVLCMidRange() {
        for u in 5..<33 {
            XCTAssertEqual(uvlcTableConformant[u].pre,    0,  "u=\(u)")
            XCTAssertEqual(uvlcTableConformant[u].preLen, 3,  "u=\(u)")
            XCTAssertEqual(uvlcTableConformant[u].suf,    UInt8(u - 5), "u=\(u)")
            XCTAssertEqual(uvlcTableConformant[u].sufLen, 5,  "u=\(u)")
            XCTAssertEqual(uvlcTableConformant[u].extLen, 0,  "u=\(u)")
        }
    }

    /// u = 33..74: same prefix/suffix layout but with a 4-bit
    /// extension field carrying `(u - 33) / 4`, and suffix bits
    /// reused cyclically in `28..31`.
    func testUVLCHighRange() {
        for u in 33..<75 {
            let e = uvlcTableConformant[u]
            XCTAssertEqual(e.preLen, 3, "u=\(u)")
            XCTAssertEqual(e.sufLen, 5, "u=\(u)")
            XCTAssertEqual(e.extLen, 4, "u=\(u)")
            XCTAssertEqual(e.suf,    UInt8(28 + (u - 33) % 4), "u=\(u)")
            XCTAssertEqual(e.ext,    UInt8((u - 33) / 4),      "u=\(u)")
        }
    }

    // MARK: - Encode smoke test

    /// Sanity: encoding u = 0 through the reverse emitter must not
    /// produce any extra bytes beyond the 0xFF sentinel frame, since
    /// u = 0 carries zero bits.
    func testEncodeUVLCZeroProducesNoPayload() {
        var emitter = HTReverseBitEmitterConformant()
        HTVLCCoderConformant.encodeUVLC(u: 0, into: &emitter)
        let bytes = emitter.finish()
        // The reverse emitter seeds with an initial sentinel byte and
        // a nibble of framing bits; emitting zero VLC bits cannot add
        // a new byte. Assert that the output is the minimum framing.
        XCTAssertLessThanOrEqual(bytes.count, 2,
                                 "u=0 should not expand the stream")
    }

    /// Encoding `u = 4` emits `preLen=3 + sufLen=1 = 4` bits. Those
    /// bits land in the single framing byte; no new byte should be
    /// appended.
    func testEncodeUVLCSmallUFitsInFrame() {
        var emitter = HTReverseBitEmitterConformant()
        HTVLCCoderConformant.encodeUVLC(u: 4, into: &emitter)
        let bytes = emitter.finish()
        XCTAssertLessThanOrEqual(bytes.count, 2)
    }
}
