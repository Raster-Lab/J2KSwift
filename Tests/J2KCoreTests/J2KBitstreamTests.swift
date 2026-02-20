//
// J2KBitstreamTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests for the bitstream reader/writer functionality.
final class J2KBitstreamTests: XCTestCase {
    // MARK: - J2KBitReader Tests

    func testBitReaderInitialization() throws {
        let data = Data([0xFF, 0x4F, 0x00, 0x01])
        let reader = J2KBitReader(data: data)

        XCTAssertEqual(reader.count, 4)
        XCTAssertEqual(reader.position, 0)
        XCTAssertEqual(reader.bitOffset, 0)
        XCTAssertTrue(reader.isByteAligned)
        XCTAssertFalse(reader.isAtEnd)
        XCTAssertEqual(reader.bytesRemaining, 4)
        XCTAssertEqual(reader.bitsRemaining, 32)
    }

    func testReadUInt8() throws {
        let data = Data([0x12, 0x34, 0x56])
        var reader = J2KBitReader(data: data)

        let byte1 = try reader.readUInt8()
        XCTAssertEqual(byte1, 0x12)
        XCTAssertEqual(reader.position, 1)

        let byte2 = try reader.readUInt8()
        XCTAssertEqual(byte2, 0x34)
        XCTAssertEqual(reader.position, 2)

        let byte3 = try reader.readUInt8()
        XCTAssertEqual(byte3, 0x56)
        XCTAssertEqual(reader.position, 3)
        XCTAssertTrue(reader.isAtEnd)
    }

    func testReadUInt16() throws {
        let data = Data([0xFF, 0x4F, 0x00, 0x51])
        var reader = J2KBitReader(data: data)

        let value1 = try reader.readUInt16()
        XCTAssertEqual(value1, 0xFF4F) // SOC marker

        let value2 = try reader.readUInt16()
        XCTAssertEqual(value2, 0x0051)

        XCTAssertTrue(reader.isAtEnd)
    }

    func testReadUInt32() throws {
        let data = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
        var reader = J2KBitReader(data: data)

        let value1 = try reader.readUInt32()
        XCTAssertEqual(value1, 0x12345678)

        let value2 = try reader.readUInt32()
        XCTAssertEqual(value2, 0x9ABCDEF0)
    }

    func testReadUInt64() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        var reader = J2KBitReader(data: data)

        let value = try reader.readUInt64()
        XCTAssertEqual(value, 0x0102030405060708)
    }

    func testReadBytes() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        var reader = J2KBitReader(data: data)

        let bytes = try reader.readBytes(3)
        XCTAssertEqual(bytes, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(reader.position, 3)
        XCTAssertEqual(reader.bytesRemaining, 2)
    }

    func testReadBit() throws {
        let data = Data([0b10110100]) // 180 decimal, bits: 1,0,1,1,0,1,0,0
        var reader = J2KBitReader(data: data)

        XCTAssertTrue(try reader.readBit())   // 1
        XCTAssertFalse(try reader.readBit())  // 0
        XCTAssertTrue(try reader.readBit())   // 1
        XCTAssertTrue(try reader.readBit())   // 1
        XCTAssertFalse(try reader.readBit())  // 0
        XCTAssertTrue(try reader.readBit())   // 1
        XCTAssertFalse(try reader.readBit())  // 0
        XCTAssertFalse(try reader.readBit())  // 0

        XCTAssertTrue(reader.isAtEnd)
    }

    func testReadBits() throws {
        let data = Data([0b11001010, 0b10110100])
        var reader = J2KBitReader(data: data)

        // Read 4 bits: 1100 = 12
        let bits1 = try reader.readBits(4)
        XCTAssertEqual(bits1, 12)

        // Read 8 bits: 10101011 = 171
        let bits2 = try reader.readBits(8)
        XCTAssertEqual(bits2, 0b10101011)

        // Read remaining 4 bits: 0100 = 4
        let bits3 = try reader.readBits(4)
        XCTAssertEqual(bits3, 4)
    }

    func testSeekAndSkip() throws {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        var reader = J2KBitReader(data: data)

        try reader.seek(to: 2)
        XCTAssertEqual(reader.position, 2)

        let byte = try reader.readUInt8()
        XCTAssertEqual(byte, 0x03)

        try reader.skip(1)
        let lastByte = try reader.readUInt8()
        XCTAssertEqual(lastByte, 0x05)
    }

    func testSkipBits() throws {
        let data = Data([0b11110000, 0b10101010])
        var reader = J2KBitReader(data: data)

        try reader.skipBits(4)
        let bits = try reader.readBits(8)
        XCTAssertEqual(bits, 0b00001010) // 0000 from first byte + 1010 from second
    }

    func testPeekUInt8() throws {
        let data = Data([0x42, 0x43])
        var reader = J2KBitReader(data: data)

        XCTAssertEqual(reader.peekUInt8(), 0x42)
        XCTAssertEqual(reader.position, 0) // Position unchanged

        _ = try reader.readUInt8()
        XCTAssertEqual(reader.peekUInt8(), 0x43)
    }

    func testPeekUInt16() throws {
        let data = Data([0xFF, 0x4F, 0x00])
        let reader = J2KBitReader(data: data)

        XCTAssertEqual(reader.peekUInt16(), 0xFF4F)
        XCTAssertEqual(reader.position, 0)
    }

    func testReadMarker() throws {
        let data = Data([0xFF, 0x4F, 0xFF, 0x51])
        var reader = J2KBitReader(data: data)

        let marker1 = try reader.readMarker()
        XCTAssertEqual(marker1, 0xFF4F) // SOC

        let marker2 = try reader.readMarker()
        XCTAssertEqual(marker2, 0xFF51) // SIZ
    }

    func testIsNextMarker() throws {
        let data = Data([0xFF, 0x4F, 0x00, 0x01])
        var reader = J2KBitReader(data: data)

        XCTAssertTrue(reader.isNextMarker())

        _ = try reader.readUInt16()
        XCTAssertFalse(reader.isNextMarker())
    }

    func testReadBeyondData() throws {
        let data = Data([0x01])
        var reader = J2KBitReader(data: data)

        _ = try reader.readUInt8()

        XCTAssertThrowsError(try reader.readUInt8()) { error in
            guard case J2KError.invalidData = error else {
                XCTFail("Expected invalidData error")
                return
            }
        }
    }

    func testReadBitsBeyondData() throws {
        let data = Data([0xFF])
        var reader = J2KBitReader(data: data)

        _ = try reader.readBits(8)

        XCTAssertThrowsError(try reader.readBits(1)) { error in
            guard case J2KError.invalidData = error else {
                XCTFail("Expected invalidData error")
                return
            }
        }
    }

    func testInvalidBitCount() throws {
        let data = Data([0xFF])
        var reader = J2KBitReader(data: data)

        XCTAssertThrowsError(try reader.readBits(0)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }

        XCTAssertThrowsError(try reader.readBits(33)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    // MARK: - J2KBitWriter Tests

    func testBitWriterInitialization() throws {
        let writer = J2KBitWriter()

        XCTAssertEqual(writer.count, 0)
        XCTAssertEqual(writer.bitCount, 0)
        XCTAssertTrue(writer.isByteAligned)
    }

    func testWriteUInt8() throws {
        var writer = J2KBitWriter()

        writer.writeUInt8(0x42)
        writer.writeUInt8(0x43)

        XCTAssertEqual(writer.data, Data([0x42, 0x43]))
    }

    func testWriteUInt16() throws {
        var writer = J2KBitWriter()

        writer.writeUInt16(0xFF4F)

        XCTAssertEqual(writer.data, Data([0xFF, 0x4F]))
    }

    func testWriteUInt32() throws {
        var writer = J2KBitWriter()

        writer.writeUInt32(0x12345678)

        XCTAssertEqual(writer.data, Data([0x12, 0x34, 0x56, 0x78]))
    }

    func testWriteUInt64() throws {
        var writer = J2KBitWriter()

        writer.writeUInt64(0x0102030405060708)

        XCTAssertEqual(writer.data, Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
    }

    func testWriteBytes() throws {
        var writer = J2KBitWriter()

        writer.writeBytes(Data([0x01, 0x02, 0x03]))

        XCTAssertEqual(writer.data, Data([0x01, 0x02, 0x03]))
    }

    func testWriteBit() throws {
        var writer = J2KBitWriter()

        writer.writeBit(true)   // 1
        writer.writeBit(false)  // 0
        writer.writeBit(true)   // 1
        writer.writeBit(true)   // 1
        writer.writeBit(false)  // 0
        writer.writeBit(true)   // 1
        writer.writeBit(false)  // 0
        writer.writeBit(false)  // 0

        XCTAssertEqual(writer.data, Data([0b10110100]))
    }

    func testWriteBits() throws {
        var writer = J2KBitWriter()

        try writer.writeBits(0b1100, count: 4)
        try writer.writeBits(0b10101011, count: 8)
        try writer.writeBits(0b0100, count: 4)

        XCTAssertEqual(writer.data, Data([0b11001010, 0b10110100]))
    }

    func testAlignToByte() throws {
        var writer = J2KBitWriter()

        writer.writeBit(true)
        writer.writeBit(true)
        writer.writeBit(false)

        XCTAssertFalse(writer.isByteAligned)

        writer.alignToByte()

        XCTAssertTrue(writer.isByteAligned)
        XCTAssertEqual(writer.data, Data([0b11000000]))
    }

    func testAlignToByteFillingWithOnes() throws {
        var writer = J2KBitWriter()

        writer.writeBit(true)
        writer.writeBit(false)

        writer.alignToByte(filling: true)

        XCTAssertEqual(writer.data, Data([0b10111111]))
    }

    func testWriteMarker() throws {
        var writer = J2KBitWriter()

        writer.writeMarker(0xFF4F) // SOC
        writer.writeMarker(0xFF51) // SIZ

        XCTAssertEqual(writer.data, Data([0xFF, 0x4F, 0xFF, 0x51]))
    }

    func testWriteMarkerSegment() throws {
        var writer = J2KBitWriter()

        let segmentData = Data([0x01, 0x02, 0x03])
        writer.writeMarkerSegment(0xFF64, segmentData: segmentData) // COM marker

        // Marker (2) + Length (2) + Data (3) = 7 bytes
        // Length includes itself: 2 + 3 = 5
        XCTAssertEqual(writer.data, Data([0xFF, 0x64, 0x00, 0x05, 0x01, 0x02, 0x03]))
    }

    func testClear() throws {
        var writer = J2KBitWriter()

        writer.writeUInt16(0x1234)
        writer.writeBit(true)

        writer.clear()

        XCTAssertEqual(writer.count, 0)
        XCTAssertEqual(writer.bitCount, 0)
        XCTAssertTrue(writer.isByteAligned)
    }

    func testInvalidWriteBitCount() throws {
        var writer = J2KBitWriter()

        XCTAssertThrowsError(try writer.writeBits(0, count: 0)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }

        XCTAssertThrowsError(try writer.writeBits(0, count: 33)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    // MARK: - Round-Trip Tests

    func testByteRoundTrip() throws {
        var writer = J2KBitWriter()
        writer.writeUInt8(0x42)
        writer.writeUInt16(0x1234)
        writer.writeUInt32(0xABCDEF01)

        var reader = J2KBitReader(data: writer.data)
        XCTAssertEqual(try reader.readUInt8(), 0x42)
        XCTAssertEqual(try reader.readUInt16(), 0x1234)
        XCTAssertEqual(try reader.readUInt32(), 0xABCDEF01)
    }

    func testBitRoundTrip() throws {
        var writer = J2KBitWriter()
        try writer.writeBits(0b11010, count: 5)
        try writer.writeBits(0b1110001, count: 7)
        try writer.writeBits(0b101, count: 3)
        writer.writeBit(false)

        var reader = J2KBitReader(data: writer.data)
        XCTAssertEqual(try reader.readBits(5), 0b11010)
        XCTAssertEqual(try reader.readBits(7), 0b1110001)
        XCTAssertEqual(try reader.readBits(3), 0b101)
        XCTAssertFalse(try reader.readBit())
    }

    func testMarkerRoundTrip() throws {
        var writer = J2KBitWriter()
        writer.writeMarker(0xFF4F) // SOC
        writer.writeMarker(0xFF51) // SIZ
        writer.writeMarker(0xFFD9) // EOC

        var reader = J2KBitReader(data: writer.data)
        XCTAssertEqual(try reader.readMarker(), 0xFF4F)
        XCTAssertEqual(try reader.readMarker(), 0xFF51)
        XCTAssertEqual(try reader.readMarker(), 0xFFD9)
    }
}
