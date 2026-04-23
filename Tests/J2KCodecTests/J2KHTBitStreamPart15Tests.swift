// J2KHTBitStreamPart15Tests.swift
// Unit tests for the ISO/IEC 15444-15 (HTJ2K) bit-stream emitters.
//
// Validates byte-level equivalence with OpenJPH 0.26's `mel_struct` and
// `vlc_struct` encoders using hand-computed expected outputs on trivial
// inputs.

import XCTest
@testable import J2KCodec

final class HTBitStreamPart15Tests: XCTestCase {

    // MARK: - Forward bit emitter

    /// Emitting `0b10101010` one bit at a time produces a single
    /// 0xAA byte.
    func testForwardEmitterPacksBitsMSBFirst() {
        var emitter = HTForwardBitEmitterPart15()
        for b in [1, 0, 1, 0, 1, 0, 1, 0] {
            emitter.emit(bit: b)
        }
        XCTAssertEqual(emitter.finish(), [0xAA])
    }

    /// Eight `1` bits produce `0xFF`; the next byte has its high bit
    /// reserved (FF-stuff). After FF-stuff, emitting seven `1` bits
    /// produces `0x7F` (not 0xFE), because the high bit of that byte
    /// is the stuff bit (always 0).
    func testForwardEmitterFFStuffs() {
        var emitter = HTForwardBitEmitterPart15()
        for _ in 0..<8 {
            emitter.emit(bit: 1)
        }
        // Now the byte 0xFF has been emitted; FF-stuff reserves the
        // high bit of the next byte. Emitting 7 more `1` bits fills
        // positions bit6..bit0 with 1; bit7 stays 0.
        for _ in 0..<7 {
            emitter.emit(bit: 1)
        }
        XCTAssertEqual(emitter.finish(), [0xFF, 0x7F])
    }

    /// Emitting fewer than 8 bits and finishing pads with zeros on
    /// the LSB side (bits shifted left fill the MSB positions).
    func testForwardEmitterPadsPartialByte() {
        var emitter = HTForwardBitEmitterPart15()
        emitter.emit(bit: 1)
        emitter.emit(bit: 1)
        emitter.emit(bit: 0)
        // tmp = 0b110, remainingBits = 5
        // finish: shift left 5 → 0b11000000 = 0xC0
        XCTAssertEqual(emitter.finish(), [0xC0])
    }

    /// `emit(bits:count:)` emits MSB-first within the value.
    func testForwardEmitterBitsHelper() {
        var emitter = HTForwardBitEmitterPart15()
        emitter.emit(bits: 0b101, count: 3)  // emits 1, 0, 1
        emitter.emit(bits: 0b11001, count: 5) // emits 1, 1, 0, 0, 1
        // Together: 1 0 1 1 1 0 0 1 = 0b10111001 = 0xB9
        XCTAssertEqual(emitter.finish(), [0xB9])
    }

    // MARK: - Reverse bit emitter

    /// Empty stream (no bits emitted) returns just the 0xFF sentinel.
    /// Part-15 requires the terminating byte of any block's reverse
    /// stream to be 0xFF (conceptually adjacent to Scup).
    func testReverseEmitterEmptyIsJustSentinel() {
        var emitter = HTReverseBitEmitterPart15()
        // After init, usedBits=4 (because sentinel already consumed
        // 4 bits of downstream adjacency), tmp=0x0F, nothing encoded.
        // Finishing flushes the 0x0F prefix byte.
        // On-wire forward order: [0x0F, 0xFF].
        XCTAssertEqual(emitter.finish(), [0x0F, 0xFF])
    }

    /// Encoding a single-bit codeword 0 puts 0x0F before the sentinel
    /// (the low nibble of the partial byte already contains 0xF from
    /// the init).
    func testReverseEmitterSingleBit() {
        var emitter = HTReverseBitEmitterPart15()
        emitter.encode(codeword: 0, count: 1)
        // tmp = 0x0F | (0 << 4) = 0x0F, usedBits = 5
        // finish → emits 0x0F; forward: [0x0F, 0xFF].
        XCTAssertEqual(emitter.finish(), [0x0F, 0xFF])
    }

    /// Encoding a 4-bit codeword 0b1010 into the partial byte:
    /// tmp = 0x0F | (0b1010 << 4) = 0xAF, usedBits = 8.
    /// Since lastGreaterThan8F is true from init (the sentinel 0xFF
    /// is > 0x8F) and tmp != 0x7F, we need a stuff iteration.
    /// After stuff: lastGreaterThan8F=false, loop continues, but no
    /// more bits to consume so we exit.
    /// Then finish() emits tmp=0xAF.
    /// Forward order: [0xAF, 0xFF].
    func testReverseEmitter4BitCodeword() {
        var emitter = HTReverseBitEmitterPart15()
        emitter.encode(codeword: 0b1010, count: 4)
        XCTAssertEqual(emitter.finish(), [0xAF, 0xFF])
    }

    /// A codeword that spans multiple bytes with the stuff rule
    /// triggering. Encoding 12 bits of all-ones first fills tmp to
    /// 0xFF (needs stuff check). After stuff, continues with 4 more
    /// `1`s into the next byte.
    func testReverseEmitterSpansBytesWithStuff() {
        var emitter = HTReverseBitEmitterPart15()
        // 12 ones:
        //   iter 1: availBits = 8 - 1(stuff) - 4(used) = 3
        //     tmp |= 0b111 << 4 = 0x7F, used=7, cwd = (0xFFF >> 3) = 0x1FF, len=9
        //     remainingAfter = availBits - take = 0 → flush check
        //     lastGreaterThan8F=true, tmp(0x7F) == 0x7F → emit
        //     emittedReversed += [0x7F]. lastGreaterThan8F = 0x7F > 0x8F → false.
        //     tmp=0, used=0.
        //   iter 2: availBits = 8 - 0(stuff) - 0(used) = 8
        //     tmp |= 0xFF << 0 = 0xFF (mask 0xFF of 0x1FF), used=8, cwd=(0x1FF >> 8) = 0x1, len=1
        //     remainingAfter = 0 → flush
        //     lastGreaterThan8F=false, so no stuff. emit 0xFF.
        //     emittedReversed += [0xFF]. lastGreaterThan8F = true.
        //     tmp=0, used=0.
        //   iter 3: availBits = 8 - 1 - 0 = 7
        //     tmp |= 0x1 << 0 = 0x01, used=1, cwd=0, len=0 → loop exits.
        // finish: tmp=0x01, used=1 → emit 0x01. emittedReversed=[0xFF, 0x7F, 0xFF, 0x01].
        // Forward reversed: [0x01, 0xFF, 0x7F, 0xFF].
        var emitter2 = emitter
        emitter2.encode(codeword: 0xFFF, count: 12)
        XCTAssertEqual(emitter2.finish(), [0x01, 0xFF, 0x7F, 0xFF])
    }
}
