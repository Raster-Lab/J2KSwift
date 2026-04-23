// J2KHTMagSgnCoderPart15Tests.swift
// Unit tests for the ISO/IEC 15444-15 MagSgn forward bit coder.
//
// Validates LSB-first bit packing, FF-stuffing at byte boundaries,
// the terminate-with-1-pad / drop-if-0xFF rule, and round-trip
// equivalence between encoder and decoder on a variety of inputs
// including ones engineered to hit the 0xFF stuff boundary.

import XCTest
@testable import J2KCodec

final class HTMagSgnCoderPart15Tests: XCTestCase {

    // MARK: - Round-trip

    func testRoundTripSingleByte() {
        let items: [(UInt32, Int)] = [
            (0b1010_0110, 8)
        ]
        let bytes = HTMagSgnCoderPart15.encodeBits(items)
        let decoded = HTMagSgnCoderPart15.decodeBits(bytes, widths: [8])
        XCTAssertEqual(decoded, [0b1010_0110])
    }

    func testRoundTripSubByteBits() {
        let items: [(UInt32, Int)] = [
            (0b101, 3), (0b1, 1), (0b11, 2)
        ]
        let bytes = HTMagSgnCoderPart15.encodeBits(items)
        let decoded = HTMagSgnCoderPart15.decodeBits(bytes, widths: [3, 1, 2])
        XCTAssertEqual(decoded, [0b101, 0b1, 0b11])
    }

    func testRoundTripMultiByteSpanning() {
        // Write 7 + 7 + 7 = 21 bits; spans across byte boundaries,
        // bit positions not aligned with 8-bit boundaries.
        let items: [(UInt32, Int)] = [
            (0b1010101, 7),
            (0b0110011, 7),
            (0b1111000, 7)
        ]
        let bytes = HTMagSgnCoderPart15.encodeBits(items)
        let decoded = HTMagSgnCoderPart15.decodeBits(bytes, widths: [7, 7, 7])
        XCTAssertEqual(decoded, [0b1010101, 0b0110011, 0b1111000])
    }

    func testRoundTripWide32BitValue() {
        let items: [(UInt32, Int)] = [
            (0xDEADBEEF, 32)
        ]
        let bytes = HTMagSgnCoderPart15.encodeBits(items)
        let decoded = HTMagSgnCoderPart15.decodeBits(bytes, widths: [32])
        XCTAssertEqual(decoded, [0xDEADBEEF])
    }

    // MARK: - FF-stuffing

    /// Writing exactly 8 one-bits produces byte `0xFF`; after that
    /// the encoder must reserve the high bit of the next byte.
    /// Encoding another 8 one-bits must therefore span 2 bytes: the
    /// first contributes 7 real bits (plus the reserved high bit as
    /// 0), the second contributes the final bit in its low slot.
    func testFFStuffingReservesHighBit() {
        let items: [(UInt32, Int)] = [
            (0xFF, 8),   // emits 0xFF
            (0xFF, 8)    // second run of ones
        ]
        let bytes = HTMagSgnCoderPart15.encodeBits(items)
        // First byte must be 0xFF.
        XCTAssertEqual(bytes[0], 0xFF)
        // Second byte's high bit must be 0 (reserved stuff bit).
        XCTAssertEqual(bytes[1] & 0x80, 0,
                       "byte after 0xFF must reserve high bit as 0")
        // Round-trip equivalence confirms the decoder unstuffs
        // correctly.
        let decoded = HTMagSgnCoderPart15.decodeBits(bytes, widths: [8, 8])
        XCTAssertEqual(decoded, [0xFF, 0xFF])
    }

    // MARK: - Terminate semantics

    /// `ms_terminate`: pad the final byte with 1-bits. If that byte
    /// becomes 0xFF it is dropped (the decoder substitutes 0xFF on
    /// exhaustion). Emitting 4 zero bits and terminating therefore
    /// produces one byte of `0b1111_0000 = 0xF0` — the high 4 bits
    /// are the 1-pad, low 4 are the real data.
    func testTerminatePadsWithOnes() {
        let items: [(UInt32, Int)] = [(0x0, 4)]
        let bytes = HTMagSgnCoderPart15.encodeBits(items)
        XCTAssertEqual(bytes.count, 1)
        XCTAssertEqual(bytes[0], 0xF0)
    }

    /// Emitting exactly 4 one-bits and terminating produces
    /// `0b1111_1111 = 0xFF` which is dropped.
    func testTerminateDropsTrailingFF() {
        let items: [(UInt32, Int)] = [(0xF, 4)]
        let bytes = HTMagSgnCoderPart15.encodeBits(items)
        XCTAssertEqual(bytes.count, 0,
                       "trailing 0xFF after 1-pad must be dropped")
        // Decoder still round-trips because it feeds 0xFF when the
        // stream is exhausted.
        let decoded = HTMagSgnCoderPart15.decodeBits(bytes, widths: [4])
        XCTAssertEqual(decoded, [0xF])
    }

    // MARK: - Randomized stress

    func testRandomizedRoundTrip() {
        var rng = SeededRNGMagSgn(seed: 0x5152_5354)
        for trial in 0..<50 {
            let itemCount = Int(rng.next() % 64) + 1
            var items: [(UInt32, Int)] = []
            var widths: [Int] = []
            for _ in 0..<itemCount {
                let w = Int(rng.next() % 16) + 1
                let mask: UInt32 = (w >= 32) ? ~UInt32(0)
                                             : ((UInt32(1) << w) - 1)
                let v = UInt32(rng.next() & UInt64(mask))
                items.append((v, w))
                widths.append(w)
            }
            let bytes = HTMagSgnCoderPart15.encodeBits(items)
            let decoded = HTMagSgnCoderPart15.decodeBits(bytes, widths: widths)
            let expected = items.map { $0.0 }
            XCTAssertEqual(decoded, expected,
                           "trial \(trial) round-trip failed")
        }
    }
}

/// LCG RNG for deterministic randomized tests.
private struct SeededRNGMagSgn {
    var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> UInt64 {
        state &*= 6364136223846793005
        state &+= 1442695040888963407
        return state
    }
}
