// V10_31_PixelDataEncapsulationTests.swift
//
// v10.19.0 — J2KDICOMHelpers Phase 2 parity gate.
//
// Verifies J2KDICOMPixelDataEncapsulator + J2KDICOMPixelDataDecapsulator
// produce byte-correct DICOM Pixel Data Item sequences per PS3.5 §A.4
// and that the round-trip (encapsulate → decapsulate) preserves the
// J2K codestream bit-exactly.

import XCTest
import Foundation
@testable import J2KDICOMHelpers

final class V10_31_PixelDataEncapsulationTests: XCTestCase {

    // MARK: - Test fixtures

    /// Synthetic J2K codestream-like bytes (not a real J2K codestream —
    /// these tests verify the DICOM byte layout, not codec behaviour;
    /// the encapsulator + decapsulator are codec-agnostic).
    private func makeFakeCodestream(byteCount: Int, signature: UInt8) -> Data {
        // Start with SOC marker (0xFF 0x4F), end with EOC (0xFF 0xD9) to
        // exercise the EOC-then-pad detection in the decapsulator.
        var bytes = Data(count: byteCount)
        bytes[0] = 0xFF
        bytes[1] = 0x4F
        for i in 2..<(byteCount - 2) {
            bytes[i] = signature &+ UInt8(i % 256)
        }
        bytes[byteCount - 2] = 0xFF
        bytes[byteCount - 1] = 0xD9
        return bytes
    }

    // MARK: - encapsulateItem

    func testEncapsulateItemEvenLengthCodestream() {
        let codestream = makeFakeCodestream(byteCount: 64, signature: 0xAA)
        let item = J2KDICOMPixelDataEncapsulator.encapsulateItem(codestream)

        // 4-byte tag + 4-byte length + 64-byte payload (no pad)
        XCTAssertEqual(item.count, 8 + 64)

        // Item tag FFFE,E000 written little-endian
        XCTAssertEqual(item[0], 0xFE)
        XCTAssertEqual(item[1], 0xFF)
        XCTAssertEqual(item[2], 0x00)
        XCTAssertEqual(item[3], 0xE0)

        // Length = 64 (LE)
        XCTAssertEqual(item[4], 0x40)
        XCTAssertEqual(item[5], 0x00)
        XCTAssertEqual(item[6], 0x00)
        XCTAssertEqual(item[7], 0x00)

        // Payload bytes match
        XCTAssertEqual(item.subdata(in: 8..<(8 + 64)), codestream)
    }

    func testEncapsulateItemOddLengthAddsPadByte() {
        let codestream = makeFakeCodestream(byteCount: 65, signature: 0xBB)
        let item = J2KDICOMPixelDataEncapsulator.encapsulateItem(codestream)

        // 4-byte tag + 4-byte length + 65-byte payload + 1-byte pad
        XCTAssertEqual(item.count, 8 + 66)

        // Length = 66 (LE) — includes the pad
        XCTAssertEqual(item[4], 0x42)
        XCTAssertEqual(item[5], 0x00)

        // Last byte is the 0x00 pad
        XCTAssertEqual(item.last, 0x00)

        // First 65 payload bytes match the codestream
        XCTAssertEqual(item.subdata(in: 8..<(8 + 65)), codestream)
    }

    // MARK: - encapsulateFrames

    func testEncapsulateSingleFrameWithEmptyBOT() {
        let frame = makeFakeCodestream(byteCount: 64, signature: 0xCC)
        let seq = J2KDICOMPixelDataEncapsulator.encapsulateFrames([frame], includeBOT: false)

        // Layout: BOT(8) + frame(8+64) + delim(8) = 88
        XCTAssertEqual(seq.count, 8 + (8 + 64) + 8)

        // BOT item tag at offset 0, length 0
        XCTAssertEqual(seq[0], 0xFE); XCTAssertEqual(seq[1], 0xFF)
        XCTAssertEqual(seq[2], 0x00); XCTAssertEqual(seq[3], 0xE0)
        XCTAssertEqual(seq[4], 0x00); XCTAssertEqual(seq[5], 0x00)
        XCTAssertEqual(seq[6], 0x00); XCTAssertEqual(seq[7], 0x00)

        // Sequence Delimitation Item at end: FFFE,E0DD, length 0
        let delimStart = 8 + (8 + 64)
        XCTAssertEqual(seq[delimStart], 0xFE)
        XCTAssertEqual(seq[delimStart + 1], 0xFF)
        XCTAssertEqual(seq[delimStart + 2], 0xDD)
        XCTAssertEqual(seq[delimStart + 3], 0xE0)
        XCTAssertEqual(seq[delimStart + 4], 0x00)
        XCTAssertEqual(seq[delimStart + 5], 0x00)
        XCTAssertEqual(seq[delimStart + 6], 0x00)
        XCTAssertEqual(seq[delimStart + 7], 0x00)
    }

    func testEncapsulateMultipleFramesWithPopulatedBOT() {
        let f0 = makeFakeCodestream(byteCount: 64, signature: 0x10)
        let f1 = makeFakeCodestream(byteCount: 80, signature: 0x20)
        let f2 = makeFakeCodestream(byteCount: 32, signature: 0x30)
        let seq = J2KDICOMPixelDataEncapsulator.encapsulateFrames([f0, f1, f2], includeBOT: true)

        // BOT = 8 + (3 × 4) = 20
        // Frame items: (8+64) + (8+80) + (8+32) = 200
        // Delim = 8
        // Total: 228
        XCTAssertEqual(seq.count, 20 + 200 + 8)

        // BOT length = 12 (LE)
        XCTAssertEqual(seq[4], 0x0C); XCTAssertEqual(seq[5], 0x00)

        // BOT entries (LE u32) — offsets relative to start of first frame item:
        //   frame 0 at offset 0
        //   frame 1 at offset 72  (= item0 length: 8-byte hdr + 64-byte payload)
        //   frame 2 at offset 160 (= 72 + 88; item1 length: 8 + 80)
        XCTAssertEqual(UInt32(seq[8])  | (UInt32(seq[9])  << 8) | (UInt32(seq[10]) << 16) | (UInt32(seq[11]) << 24), 0)
        XCTAssertEqual(UInt32(seq[12]) | (UInt32(seq[13]) << 8) | (UInt32(seq[14]) << 16) | (UInt32(seq[15]) << 24), 72)
        XCTAssertEqual(UInt32(seq[16]) | (UInt32(seq[17]) << 8) | (UInt32(seq[18]) << 16) | (UInt32(seq[19]) << 24), 160)
    }

    // MARK: - decapsulateFrames

    func testDecapsulateRoundTripSingleFrame() throws {
        let frame = makeFakeCodestream(byteCount: 100, signature: 0xDD)
        let seq = J2KDICOMPixelDataEncapsulator.encapsulateFrames([frame], includeBOT: false)
        let recovered = try J2KDICOMPixelDataDecapsulator.extractFrames(seq)

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0], frame, "Single-frame round-trip must be byte-exact.")
    }

    func testDecapsulateRoundTripMultipleFrames() throws {
        let frames = [
            makeFakeCodestream(byteCount: 64, signature: 0x10),
            makeFakeCodestream(byteCount: 80, signature: 0x20),
            makeFakeCodestream(byteCount: 32, signature: 0x30),
        ]
        let seq = J2KDICOMPixelDataEncapsulator.encapsulateFrames(frames, includeBOT: true)
        let recovered = try J2KDICOMPixelDataDecapsulator.extractFrames(seq)

        XCTAssertEqual(recovered.count, frames.count)
        for (i, (orig, rec)) in zip(frames, recovered).enumerated() {
            XCTAssertEqual(rec, orig, "Frame \(i) round-trip must be byte-exact.")
        }
    }

    func testDecapsulateStripsPadByteFromOddLengthFrame() throws {
        // 65-byte codestream gets padded to 66 bytes in the Item;
        // decapsulator must detect EOC-then-pad and strip the 0x00.
        let frame = makeFakeCodestream(byteCount: 65, signature: 0xEE)
        let seq = J2KDICOMPixelDataEncapsulator.encapsulateFrames([frame], includeBOT: false)
        let recovered = try J2KDICOMPixelDataDecapsulator.extractFrames(seq)

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].count, 65, "Decapsulator must strip the trailing pad byte.")
        XCTAssertEqual(recovered[0], frame)
    }

    // MARK: - Decapsulator error paths

    func testDecapsulateRejectsTruncatedInput() {
        XCTAssertThrowsError(try J2KDICOMPixelDataDecapsulator.extractFrames(Data())) { error in
            XCTAssertEqual(error as? J2KDICOMPixelDataError,
                           .truncated(needed: 8, got: 0))
        }
        XCTAssertThrowsError(try J2KDICOMPixelDataDecapsulator.extractFrames(Data([0xFE, 0xFF, 0x00]))) { error in
            XCTAssertEqual(error as? J2KDICOMPixelDataError,
                           .truncated(needed: 8, got: 3))
        }
    }

    func testDecapsulateRejectsInvalidBOTTag() {
        // 8 bytes starting with the WRONG tag (0xDEAD instead of FFFE,E000)
        let bad = Data([0xAD, 0xDE, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertThrowsError(try J2KDICOMPixelDataDecapsulator.extractFrames(bad)) { error in
            if case .itemTagExpected(let offset) = error as? J2KDICOMPixelDataError {
                XCTAssertEqual(offset, 0)
            } else {
                XCTFail("Expected itemTagExpected(offset: 0), got \(error)")
            }
        }
    }

    func testDecapsulateRejectsBOTLengthOverrun() {
        // BOT item with declared length > available bytes
        var bad = Data()
        bad.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])  // BOT tag
        bad.append(contentsOf: [0xFF, 0xFF, 0x00, 0x00])  // length 65535 — overruns
        XCTAssertThrowsError(try J2KDICOMPixelDataDecapsulator.extractFrames(bad)) { error in
            if case .itemLengthOverrun = error as? J2KDICOMPixelDataError {
                // expected
            } else {
                XCTFail("Expected itemLengthOverrun, got \(error)")
            }
        }
    }

    func testDecapsulateEmptySequenceReturnsNoFrames() throws {
        // BOT with length 0 + Sequence Delimitation
        var seq = Data()
        seq.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0, 0x00, 0x00, 0x00, 0x00])  // BOT len 0
        seq.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0, 0x00, 0x00, 0x00, 0x00])  // Delim

        let frames = try J2KDICOMPixelDataDecapsulator.extractFrames(seq)
        XCTAssertEqual(frames.count, 0)
    }

    // MARK: - Public-API smoke

    func testJ2KDICOMPixelDataErrorIsEquatable() {
        // Compile-time check that the error type is Equatable + Sendable
        // (since the tests above pattern-match on it).
        XCTAssertEqual(
            J2KDICOMPixelDataError.truncated(needed: 8, got: 0),
            J2KDICOMPixelDataError.truncated(needed: 8, got: 0))
        XCTAssertNotEqual(
            J2KDICOMPixelDataError.truncated(needed: 8, got: 0),
            J2KDICOMPixelDataError.itemTagExpected(offset: 0))
    }
}
