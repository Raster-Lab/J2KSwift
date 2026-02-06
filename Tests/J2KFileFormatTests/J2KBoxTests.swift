import XCTest
@testable import J2KFileFormat
@testable import J2KCore

/// Tests for JP2 box framework.
final class J2KBoxTests: XCTestCase {
    
    // MARK: - Box Type Tests
    
    func testBoxTypeCreation() {
        let type = J2KBoxType(string: "test")
        XCTAssertEqual(type.stringValue, "test")
    }
    
    func testBoxTypeRawValue() {
        let jp = J2KBoxType.jp
        // 'jP  ' = 0x6A, 0x50, 0x20, 0x20
        let expected: UInt32 = 0x6A502020
        XCTAssertEqual(jp.rawValue, expected)
    }
    
    func testBoxTypeEquality() {
        let type1 = J2KBoxType(string: "test")
        let type2 = J2KBoxType(string: "test")
        let type3 = J2KBoxType(string: "demo")
        
        XCTAssertEqual(type1, type2)
        XCTAssertNotEqual(type1, type3)
    }
    
    func testStandardBoxTypes() {
        XCTAssertEqual(J2KBoxType.jp.stringValue, "jP  ")
        XCTAssertEqual(J2KBoxType.ftyp.stringValue, "ftyp")
        XCTAssertEqual(J2KBoxType.jp2h.stringValue, "jp2h")
        XCTAssertEqual(J2KBoxType.ihdr.stringValue, "ihdr")
        XCTAssertEqual(J2KBoxType.colr.stringValue, "colr")
        XCTAssertEqual(J2KBoxType.jp2c.stringValue, "jp2c")
    }
    
    // MARK: - Box Reader Tests
    
    func testBoxReaderStandardLength() throws {
        // Create a simple box: length=12, type='test', content='data'
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // Length = 12
        data.append(contentsOf: [0x74, 0x65, 0x73, 0x74]) // Type = 'test'
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // Content = 'data'
        
        var reader = J2KBoxReader(data: data)
        let boxInfo = try reader.readNextBox()
        
        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type.stringValue, "test")
        XCTAssertEqual(boxInfo?.headerSize, 8)
        XCTAssertEqual(boxInfo?.totalLength, 12)
        XCTAssertEqual(boxInfo?.contentLength, 4)
        
        let content = reader.extractContent(from: boxInfo!)
        XCTAssertEqual(content, Data([0x64, 0x61, 0x74, 0x61]))
    }
    
    func testBoxReaderExtendedLength() throws {
        // Create a box with extended length
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // Length = 1 (extended)
        data.append(contentsOf: [0x74, 0x65, 0x73, 0x74]) // Type = 'test'
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x14]) // Extended length = 20
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // Content = 'data'
        
        var reader = J2KBoxReader(data: data)
        let boxInfo = try reader.readNextBox()
        
        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type.stringValue, "test")
        XCTAssertEqual(boxInfo?.headerSize, 16)
        XCTAssertEqual(boxInfo?.totalLength, 20)
        XCTAssertEqual(boxInfo?.contentLength, 4)
    }
    
    func testBoxReaderMultipleBoxes() throws {
        // Create two boxes
        var data = Data()
        
        // First box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C]) // Length = 12
        data.append(contentsOf: [0x62, 0x6F, 0x78, 0x31]) // Type = 'box1'
        data.append(contentsOf: [0x61, 0x62, 0x63, 0x64]) // Content
        
        // Second box
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D]) // Length = 13
        data.append(contentsOf: [0x62, 0x6F, 0x78, 0x32]) // Type = 'box2'
        data.append(contentsOf: [0x31, 0x32, 0x33, 0x34, 0x35]) // Content
        
        var reader = J2KBoxReader(data: data)
        
        let box1 = try reader.readNextBox()
        XCTAssertNotNil(box1)
        XCTAssertEqual(box1?.type.stringValue, "box1")
        
        let box2 = try reader.readNextBox()
        XCTAssertNotNil(box2)
        XCTAssertEqual(box2?.type.stringValue, "box2")
        
        let box3 = try reader.readNextBox()
        XCTAssertNil(box3)
        XCTAssertTrue(reader.isAtEnd)
    }
    
    func testBoxReaderInvalidLength() throws {
        // Invalid length (< 8)
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x04]) // Length = 4 (too small)
        data.append(contentsOf: [0x74, 0x65, 0x73, 0x74]) // Type
        
        var reader = J2KBoxReader(data: data)
        XCTAssertThrowsError(try reader.readNextBox()) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testBoxReaderTruncatedData() throws {
        // Box extends beyond data
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x10]) // Length = 16
        data.append(contentsOf: [0x74, 0x65, 0x73, 0x74]) // Type
        data.append(contentsOf: [0x64, 0x61]) // Only 2 bytes of 8 expected
        
        var reader = J2KBoxReader(data: data)
        XCTAssertThrowsError(try reader.readNextBox()) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testBoxReaderPeekDoesNotAdvance() throws {
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
        data.append(contentsOf: [0x74, 0x65, 0x73, 0x74])
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        
        let reader = J2KBoxReader(data: data)
        
        let peek1 = try reader.peekNextBox()
        let peek2 = try reader.peekNextBox()
        
        XCTAssertNotNil(peek1)
        XCTAssertNotNil(peek2)
        XCTAssertEqual(peek1?.type, peek2?.type)
        XCTAssertEqual(reader.currentPosition, 0)
    }
    
    func testBoxReaderReadAllBoxes() throws {
        var data = Data()
        
        // Add 3 boxes
        for i in 0..<3 {
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])
            data.append(contentsOf: [0x62, 0x6F, 0x78, UInt8(0x30 + i)])
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }
        
        var reader = J2KBoxReader(data: data)
        let boxes = try reader.readAllBoxes()
        
        XCTAssertEqual(boxes.count, 3)
        XCTAssertEqual(boxes[0].type.stringValue, "box0")
        XCTAssertEqual(boxes[1].type.stringValue, "box1")
        XCTAssertEqual(boxes[2].type.stringValue, "box2")
    }
    
    // MARK: - Box Writer Tests
    
    func testBoxWriterStandardLength() throws {
        var writer = J2KBoxWriter()
        let content = Data([0x64, 0x61, 0x74, 0x61]) // 'data'
        let type = J2KBoxType(string: "test")
        
        try writer.writeRawBox(type: type, content: content)
        
        let data = writer.data
        XCTAssertEqual(data.count, 12) // 8 header + 4 content
        
        // Verify header
        let length = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        XCTAssertEqual(length, 12)
        
        let boxType = String(bytes: data[4..<8], encoding: .ascii)
        XCTAssertEqual(boxType, "test")
        
        // Verify content
        XCTAssertEqual(data[8..<12], content)
    }
    
    func testBoxWriterMultipleBoxes() throws {
        var writer = J2KBoxWriter()
        
        try writer.writeRawBox(type: J2KBoxType(string: "box1"), content: Data([0x01]))
        try writer.writeRawBox(type: J2KBoxType(string: "box2"), content: Data([0x02, 0x03]))
        
        let data = writer.data
        
        // First box: 8 header + 1 content = 9 bytes
        // Second box: 8 header + 2 content = 10 bytes
        XCTAssertEqual(data.count, 19)
        
        // Parse with reader to verify
        var reader = J2KBoxReader(data: data)
        let box1 = try reader.readNextBox()
        let box2 = try reader.readNextBox()
        
        XCTAssertEqual(box1?.type.stringValue, "box1")
        XCTAssertEqual(box2?.type.stringValue, "box2")
    }
    
    // MARK: - Signature Box Tests
    
    func testSignatureBoxWrite() throws {
        let box = J2KSignatureBox()
        let data = try box.write()
        
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data, Data([0x0D, 0x0A, 0x87, 0x0A]))
    }
    
    func testSignatureBoxRead() throws {
        var box = J2KSignatureBox()
        let data = Data([0x0D, 0x0A, 0x87, 0x0A])
        
        XCTAssertNoThrow(try box.read(from: data))
    }
    
    func testSignatureBoxReadInvalid() throws {
        var box = J2KSignatureBox()
        let invalidData = Data([0x00, 0x00, 0x00, 0x00])
        
        XCTAssertThrowsError(try box.read(from: invalidData)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testSignatureBoxRoundTrip() throws {
        let box = J2KSignatureBox()
        let data = try box.write()
        
        var readBox = J2KSignatureBox()
        try readBox.read(from: data)
        
        // If no error is thrown, round-trip is successful
    }
    
    // MARK: - File Type Box Tests
    
    func testFileTypeBoxWrite() throws {
        let box = J2KFileTypeBox(
            brand: .jp2,
            minorVersion: 0,
            compatibleBrands: [.jp2]
        )
        let data = try box.write()
        
        // 4 (brand) + 4 (version) + 4 (1 compatible brand) = 12 bytes
        XCTAssertEqual(data.count, 12)
        
        // Verify brand
        XCTAssertEqual(String(bytes: data[0..<4], encoding: .ascii), "jp2 ")
        
        // Verify version
        let version = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        XCTAssertEqual(version, 0)
        
        // Verify compatible brand
        XCTAssertEqual(String(bytes: data[8..<12], encoding: .ascii), "jp2 ")
    }
    
    func testFileTypeBoxRead() throws {
        var data = Data()
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20]) // 'jp2 '
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Version 0
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20]) // Compatible: 'jp2 '
        
        var box = J2KFileTypeBox(brand: .jp2, minorVersion: 0)
        try box.read(from: data)
        
        XCTAssertEqual(box.brand, .jp2)
        XCTAssertEqual(box.minorVersion, 0)
        XCTAssertEqual(box.compatibleBrands.count, 1)
        XCTAssertEqual(box.compatibleBrands[0], .jp2)
    }
    
    func testFileTypeBoxRoundTrip() throws {
        let original = J2KFileTypeBox(
            brand: .jpx,
            minorVersion: 1,
            compatibleBrands: [.jp2, .jpx]
        )
        
        let data = try original.write()
        
        var read = J2KFileTypeBox(brand: .jp2, minorVersion: 0)
        try read.read(from: data)
        
        XCTAssertEqual(read.brand, original.brand)
        XCTAssertEqual(read.minorVersion, original.minorVersion)
        XCTAssertEqual(read.compatibleBrands.count, original.compatibleBrands.count)
    }
    
    func testFileTypeBoxMultipleCompatibleBrands() throws {
        let box = J2KFileTypeBox(
            brand: .jpx,
            minorVersion: 0,
            compatibleBrands: [.jp2, .jpx, .jpm]
        )
        
        let data = try box.write()
        
        // 4 (brand) + 4 (version) + 12 (3 compatible brands) = 20 bytes
        XCTAssertEqual(data.count, 20)
    }
    
    // MARK: - Image Header Box Tests
    
    func testImageHeaderBoxWrite() throws {
        let box = J2KImageHeaderBox(
            width: 1920,
            height: 1080,
            numComponents: 3,
            bitsPerComponent: 8
        )
        
        let data = try box.write()
        XCTAssertEqual(data.count, 14)
        
        // Verify height (first 4 bytes)
        let height = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        XCTAssertEqual(height, 1080)
        
        // Verify width (next 4 bytes)
        let width = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        XCTAssertEqual(width, 1920)
        
        // Verify num components (next 2 bytes)
        let numComponents = UInt16(data[8]) << 8 | UInt16(data[9])
        XCTAssertEqual(numComponents, 3)
        
        // Verify bits per component
        XCTAssertEqual(data[10], 8)
        
        // Verify compression type
        XCTAssertEqual(data[11], 7)
        
        // Verify flags
        XCTAssertEqual(data[12], 0) // colorSpaceUnknown
        XCTAssertEqual(data[13], 0) // intellectualProperty
    }
    
    func testImageHeaderBoxRead() throws {
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x04, 0x38]) // Height = 1080
        data.append(contentsOf: [0x00, 0x00, 0x07, 0x80]) // Width = 1920
        data.append(contentsOf: [0x00, 0x03]) // 3 components
        data.append(0x08) // 8 bits per component
        data.append(0x07) // Compression type 7
        data.append(0x00) // Color space known
        data.append(0x00) // No IP
        
        var box = J2KImageHeaderBox(width: 0, height: 0, numComponents: 0, bitsPerComponent: 0)
        try box.read(from: data)
        
        XCTAssertEqual(box.width, 1920)
        XCTAssertEqual(box.height, 1080)
        XCTAssertEqual(box.numComponents, 3)
        XCTAssertEqual(box.bitsPerComponent, 8)
        XCTAssertEqual(box.compressionType, 7)
        XCTAssertEqual(box.colorSpaceUnknown, 0)
        XCTAssertEqual(box.intellectualProperty, 0)
    }
    
    func testImageHeaderBoxRoundTrip() throws {
        let original = J2KImageHeaderBox(
            width: 3840,
            height: 2160,
            numComponents: 4,
            bitsPerComponent: 16,
            compressionType: 7,
            colorSpaceUnknown: 1,
            intellectualProperty: 0
        )
        
        let data = try original.write()
        
        var read = J2KImageHeaderBox(width: 0, height: 0, numComponents: 0, bitsPerComponent: 0)
        try read.read(from: data)
        
        XCTAssertEqual(read.width, original.width)
        XCTAssertEqual(read.height, original.height)
        XCTAssertEqual(read.numComponents, original.numComponents)
        XCTAssertEqual(read.bitsPerComponent, original.bitsPerComponent)
        XCTAssertEqual(read.compressionType, original.compressionType)
        XCTAssertEqual(read.colorSpaceUnknown, original.colorSpaceUnknown)
        XCTAssertEqual(read.intellectualProperty, original.intellectualProperty)
    }
    
    func testImageHeaderBoxInvalidCompressionType() throws {
        let box = J2KImageHeaderBox(
            width: 100,
            height: 100,
            numComponents: 1,
            bitsPerComponent: 8,
            compressionType: 99 // Invalid
        )
        
        XCTAssertThrowsError(try box.write()) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testImageHeaderBoxInvalidFlags() throws {
        let box = J2KImageHeaderBox(
            width: 100,
            height: 100,
            numComponents: 1,
            bitsPerComponent: 8,
            compressionType: 7,
            colorSpaceUnknown: 2 // Invalid (must be 0 or 1)
        )
        
        XCTAssertThrowsError(try box.write()) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    // MARK: - JP2 Header Box Tests
    
    func testHeaderBoxWriteWithChildren() throws {
        let ihdr = J2KImageHeaderBox(
            width: 512,
            height: 512,
            numComponents: 3,
            bitsPerComponent: 8
        )
        
        let headerBox = J2KHeaderBox(boxes: [ihdr])
        let data = try headerBox.write()
        
        // Should contain the ihdr box
        XCTAssertGreaterThan(data.count, 0)
        
        // Parse to verify
        var reader = J2KBoxReader(data: data)
        let boxInfo = try reader.readNextBox()
        
        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type, .ihdr)
    }
    
    func testHeaderBoxRoundTrip() throws {
        let ihdr = J2KImageHeaderBox(
            width: 256,
            height: 256,
            numComponents: 1,
            bitsPerComponent: 16
        )
        
        let original = J2KHeaderBox(boxes: [ihdr])
        let data = try original.write()
        
        var read = J2KHeaderBox()
        try read.read(from: data)
        
        XCTAssertEqual(read.boxes.count, 1)
        
        // Verify the parsed ihdr box
        if let parsedIhdr = read.boxes.first as? J2KImageHeaderBox {
            XCTAssertEqual(parsedIhdr.width, 256)
            XCTAssertEqual(parsedIhdr.height, 256)
            XCTAssertEqual(parsedIhdr.numComponents, 1)
            XCTAssertEqual(parsedIhdr.bitsPerComponent, 16)
        } else {
            XCTFail("Failed to parse ihdr box")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteJP2HeaderStructure() throws {
        // Create a complete JP2 header structure
        var writer = J2KBoxWriter()
        
        // 1. Signature box
        let signature = J2KSignatureBox()
        try writer.writeBox(signature)
        
        // 2. File type box
        let ftyp = J2KFileTypeBox(
            brand: .jp2,
            minorVersion: 0,
            compatibleBrands: [.jp2]
        )
        try writer.writeBox(ftyp)
        
        // 3. JP2 header box containing ihdr
        let ihdr = J2KImageHeaderBox(
            width: 1024,
            height: 768,
            numComponents: 3,
            bitsPerComponent: 8
        )
        let jp2h = J2KHeaderBox(boxes: [ihdr])
        try writer.writeBox(jp2h)
        
        let data = writer.data
        
        // Parse and verify
        var reader = J2KBoxReader(data: data)
        
        // Verify signature
        let sigInfo = try reader.readNextBox()
        XCTAssertEqual(sigInfo?.type, .jp)
        
        // Verify ftyp
        let ftypInfo = try reader.readNextBox()
        XCTAssertEqual(ftypInfo?.type, .ftyp)
        
        // Verify jp2h
        let jp2hInfo = try reader.readNextBox()
        XCTAssertEqual(jp2hInfo?.type, .jp2h)
        
        XCTAssertTrue(reader.isAtEnd)
    }
    
    // MARK: - Bits Per Component Box Tests
    
    func testBitsPerComponentBoxCreation() {
        let box = J2KBitsPerComponentBox(bitDepths: [
            .unsigned(8),
            .unsigned(8),
            .unsigned(8)
        ])
        
        XCTAssertEqual(box.boxType, .bpcc)
        XCTAssertEqual(box.bitDepths.count, 3)
        XCTAssertEqual(box.bitDepths[0], .unsigned(8))
    }
    
    func testBitsPerComponentBoxWriteUnsigned() throws {
        let box = J2KBitsPerComponentBox(bitDepths: [
            .unsigned(8),
            .unsigned(16),
            .unsigned(12)
        ])
        
        let data = try box.write()
        
        // 8-bit unsigned = 7 (8-1)
        // 16-bit unsigned = 15 (16-1)
        // 12-bit unsigned = 11 (12-1)
        XCTAssertEqual(data.count, 3)
        XCTAssertEqual(data[0], 7)
        XCTAssertEqual(data[1], 15)
        XCTAssertEqual(data[2], 11)
    }
    
    func testBitsPerComponentBoxWriteSigned() throws {
        let box = J2KBitsPerComponentBox(bitDepths: [
            .signed(8),
            .signed(16)
        ])
        
        let data = try box.write()
        
        // 8-bit signed = 0x87 (7 | 0x80)
        // 16-bit signed = 0x8F (15 | 0x80)
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0], 0x87)
        XCTAssertEqual(data[1], 0x8F)
    }
    
    func testBitsPerComponentBoxWriteMixed() throws {
        let box = J2KBitsPerComponentBox(bitDepths: [
            .unsigned(8),
            .unsigned(8),
            .unsigned(8),
            .signed(16)
        ])
        
        let data = try box.write()
        
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data[0], 7)   // 8-bit unsigned
        XCTAssertEqual(data[1], 7)   // 8-bit unsigned
        XCTAssertEqual(data[2], 7)   // 8-bit unsigned
        XCTAssertEqual(data[3], 0x8F) // 16-bit signed
    }
    
    func testBitsPerComponentBoxReadUnsigned() throws {
        let data = Data([7, 15, 11]) // 8-bit, 16-bit, 12-bit unsigned
        
        var box = J2KBitsPerComponentBox(bitDepths: [])
        try box.read(from: data)
        
        XCTAssertEqual(box.bitDepths.count, 3)
        XCTAssertEqual(box.bitDepths[0], .unsigned(8))
        XCTAssertEqual(box.bitDepths[1], .unsigned(16))
        XCTAssertEqual(box.bitDepths[2], .unsigned(12))
    }
    
    func testBitsPerComponentBoxReadSigned() throws {
        let data = Data([0x87, 0x8F]) // 8-bit, 16-bit signed
        
        var box = J2KBitsPerComponentBox(bitDepths: [])
        try box.read(from: data)
        
        XCTAssertEqual(box.bitDepths.count, 2)
        XCTAssertEqual(box.bitDepths[0], .signed(8))
        XCTAssertEqual(box.bitDepths[1], .signed(16))
    }
    
    func testBitsPerComponentBoxRoundTrip() throws {
        let original = J2KBitsPerComponentBox(bitDepths: [
            .unsigned(8),
            .unsigned(8),
            .unsigned(8),
            .unsigned(16)
        ])
        
        let data = try original.write()
        var decoded = J2KBitsPerComponentBox(bitDepths: [])
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.bitDepths, original.bitDepths)
    }
    
    func testBitsPerComponentBoxInvalidEmpty() {
        let box = J2KBitsPerComponentBox(bitDepths: [])
        
        XCTAssertThrowsError(try box.write()) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testBitsPerComponentBoxInvalidBitDepth() {
        let box = J2KBitsPerComponentBox(bitDepths: [.unsigned(39)])
        
        XCTAssertThrowsError(try box.write()) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }
    
    func testBitsPerComponentBoxEdgeCases() throws {
        // Test minimum (1-bit)
        let box1 = J2KBitsPerComponentBox(bitDepths: [.unsigned(1)])
        let data1 = try box1.write()
        XCTAssertEqual(data1[0], 0)
        
        // Test maximum (38-bit)
        let box2 = J2KBitsPerComponentBox(bitDepths: [.unsigned(38)])
        let data2 = try box2.write()
        XCTAssertEqual(data2[0], 37)
    }
    
    // MARK: - Color Specification Box Tests
    
    func testColorSpecificationBoxCreationEnumerated() {
        let box = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 0,
            approximation: 0
        )
        
        XCTAssertEqual(box.boxType, .colr)
    }
    
    func testColorSpecificationBoxWriteSRGB() throws {
        let box = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 0,
            approximation: 0
        )
        
        let data = try box.write()
        
        XCTAssertEqual(data.count, 7)
        XCTAssertEqual(data[0], 1) // METH = 1 (enumerated)
        XCTAssertEqual(data[1], 0) // PREC = 0
        XCTAssertEqual(data[2], 0) // APPROX = 0
        
        // EnumCS = 16 (sRGB)
        let enumCS = UInt32(data[3]) << 24 | UInt32(data[4]) << 16 |
                     UInt32(data[5]) << 8 | UInt32(data[6])
        XCTAssertEqual(enumCS, 16)
    }
    
    func testColorSpecificationBoxWriteGreyscale() throws {
        let box = J2KColorSpecificationBox(
            method: .enumerated(.greyscale),
            precedence: 0,
            approximation: 0
        )
        
        let data = try box.write()
        
        let enumCS = UInt32(data[3]) << 24 | UInt32(data[4]) << 16 |
                     UInt32(data[5]) << 8 | UInt32(data[6])
        XCTAssertEqual(enumCS, 17)
    }
    
    func testColorSpecificationBoxWriteYCbCr() throws {
        let box = J2KColorSpecificationBox(
            method: .enumerated(.yCbCr),
            precedence: 1,
            approximation: 1
        )
        
        let data = try box.write()
        
        XCTAssertEqual(data[1], 1) // PREC = 1
        XCTAssertEqual(data[2], 1) // APPROX = 1
        
        let enumCS = UInt32(data[3]) << 24 | UInt32(data[4]) << 16 |
                     UInt32(data[5]) << 8 | UInt32(data[6])
        XCTAssertEqual(enumCS, 18)
    }
    
    func testColorSpecificationBoxWriteRestrictedICC() throws {
        let iccProfile = Data([0x01, 0x02, 0x03, 0x04])
        let box = J2KColorSpecificationBox(
            method: .restrictedICC(iccProfile),
            precedence: 0,
            approximation: 0
        )
        
        let data = try box.write()
        
        XCTAssertEqual(data.count, 7)
        XCTAssertEqual(data[0], 2) // METH = 2 (restricted ICC)
        XCTAssertEqual(data[1], 0)
        XCTAssertEqual(data[2], 0)
        XCTAssertEqual(data[3..<7], iccProfile)
    }
    
    func testColorSpecificationBoxReadSRGB() throws {
        var data = Data()
        data.append(1) // METH
        data.append(0) // PREC
        data.append(0) // APPROX
        data.append(contentsOf: [0, 0, 0, 16]) // EnumCS = 16
        
        var box = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 0,
            approximation: 0
        )
        try box.read(from: data)
        
        XCTAssertEqual(box.precedence, 0)
        XCTAssertEqual(box.approximation, 0)
        
        if case .enumerated(let cs) = box.method {
            XCTAssertEqual(cs, .sRGB)
        } else {
            XCTFail("Expected enumerated color space")
        }
    }
    
    func testColorSpecificationBoxReadGreyscale() throws {
        var data = Data()
        data.append(1) // METH
        data.append(0) // PREC
        data.append(0) // APPROX
        data.append(contentsOf: [0, 0, 0, 17]) // EnumCS = 17
        
        var box = J2KColorSpecificationBox(
            method: .enumerated(.greyscale),
            precedence: 0,
            approximation: 0
        )
        try box.read(from: data)
        
        if case .enumerated(let cs) = box.method {
            XCTAssertEqual(cs, .greyscale)
        } else {
            XCTFail("Expected enumerated color space")
        }
    }
    
    func testColorSpecificationBoxReadRestrictedICC() throws {
        let iccProfile = Data([0x01, 0x02, 0x03, 0x04])
        var data = Data()
        data.append(2) // METH = 2
        data.append(0) // PREC
        data.append(0) // APPROX
        data.append(contentsOf: iccProfile)
        
        var box = J2KColorSpecificationBox(
            method: .restrictedICC(Data()),
            precedence: 0,
            approximation: 0
        )
        try box.read(from: data)
        
        if case .restrictedICC(let profile) = box.method {
            XCTAssertEqual(profile, iccProfile)
        } else {
            XCTFail("Expected restricted ICC profile")
        }
    }
    
    func testColorSpecificationBoxRoundTrip() throws {
        let original = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 5,
            approximation: 1
        )
        
        let data = try original.write()
        var decoded = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 0,
            approximation: 0
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.precedence, original.precedence)
        XCTAssertEqual(decoded.approximation, original.approximation)
        XCTAssertEqual(decoded.method, original.method)
    }
    
    func testColorSpecificationBoxInvalidApproximation() {
        let box = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 0,
            approximation: 2
        )
        
        XCTAssertThrowsError(try box.write())
    }
    
    func testColorSpecificationBoxAllEnumeratedTypes() throws {
        let colorSpaces: [J2KColorSpecificationBox.EnumeratedColorSpace] = [
            .sRGB, .greyscale, .yCbCr, .cmyk, .esRGB, .rommRGB
        ]
        
        for cs in colorSpaces {
            let box = J2KColorSpecificationBox(
                method: .enumerated(cs),
                precedence: 0,
                approximation: 0
            )
            
            let data = try box.write()
            var decoded = J2KColorSpecificationBox(
                method: .enumerated(.sRGB),
                precedence: 0,
                approximation: 0
            )
            try decoded.read(from: data)
            
            if case .enumerated(let decodedCS) = decoded.method {
                XCTAssertEqual(decodedCS, cs)
            } else {
                XCTFail("Expected enumerated color space")
            }
        }
    }
    
    // MARK: - Palette Box Tests
    
    func testPaletteBoxCreation() {
        let entries: [[UInt32]] = [
            [255, 0, 0],
            [0, 255, 0],
            [0, 0, 255]
        ]
        
        let box = J2KPaletteBox(
            entries: entries,
            componentBitDepths: [.unsigned(8), .unsigned(8), .unsigned(8)]
        )
        
        XCTAssertEqual(box.boxType, .pclr)
        XCTAssertEqual(box.numEntries, 3)
        XCTAssertEqual(box.numComponents, 3)
    }
    
    func testPaletteBoxWriteSimple() throws {
        let entries: [[UInt32]] = [
            [255, 0, 0],
            [0, 255, 0],
            [0, 0, 255]
        ]
        
        let box = J2KPaletteBox(
            entries: entries,
            componentBitDepths: [.unsigned(8), .unsigned(8), .unsigned(8)]
        )
        
        let data = try box.write()
        
        // NE (2 bytes) = 3
        XCTAssertEqual(data[0], 0)
        XCTAssertEqual(data[1], 3)
        
        // NPC (1 byte) = 3
        XCTAssertEqual(data[2], 3)
        
        // B[0], B[1], B[2] = 7 (8-bit unsigned)
        XCTAssertEqual(data[3], 7)
        XCTAssertEqual(data[4], 7)
        XCTAssertEqual(data[5], 7)
        
        // Palette data (3 entries × 3 components × 1 byte = 9 bytes)
        XCTAssertEqual(data.count, 6 + 9)
        
        // First entry: [255, 0, 0]
        XCTAssertEqual(data[6], 255)
        XCTAssertEqual(data[7], 0)
        XCTAssertEqual(data[8], 0)
        
        // Second entry: [0, 255, 0]
        XCTAssertEqual(data[9], 0)
        XCTAssertEqual(data[10], 255)
        XCTAssertEqual(data[11], 0)
        
        // Third entry: [0, 0, 255]
        XCTAssertEqual(data[12], 0)
        XCTAssertEqual(data[13], 0)
        XCTAssertEqual(data[14], 255)
    }
    
    func testPaletteBoxWrite16Bit() throws {
        let entries: [[UInt32]] = [
            [65535, 0],
            [0, 65535]
        ]
        
        let box = J2KPaletteBox(
            entries: entries,
            componentBitDepths: [.unsigned(16), .unsigned(16)]
        )
        
        let data = try box.write()
        
        // NE = 2
        XCTAssertEqual(UInt16(data[0]) << 8 | UInt16(data[1]), 2)
        
        // NPC = 2
        XCTAssertEqual(data[2], 2)
        
        // B[0], B[1] = 15 (16-bit unsigned)
        XCTAssertEqual(data[3], 15)
        XCTAssertEqual(data[4], 15)
        
        // Palette data (2 entries × 2 components × 2 bytes = 8 bytes)
        XCTAssertEqual(data.count, 5 + 8)
        
        // First entry: [65535, 0] in big-endian 16-bit
        XCTAssertEqual(data[5], 0xFF)
        XCTAssertEqual(data[6], 0xFF)
        XCTAssertEqual(data[7], 0x00)
        XCTAssertEqual(data[8], 0x00)
    }
    
    func testPaletteBoxReadSimple() throws {
        var data = Data()
        
        // NE = 2
        data.append(contentsOf: [0, 2])
        
        // NPC = 3
        data.append(3)
        
        // B[0-2] = 7 (8-bit)
        data.append(contentsOf: [7, 7, 7])
        
        // Entries
        data.append(contentsOf: [255, 0, 0])  // Red
        data.append(contentsOf: [0, 255, 0])  // Green
        
        var box = J2KPaletteBox(entries: [], componentBitDepths: [])
        try box.read(from: data)
        
        XCTAssertEqual(box.numEntries, 2)
        XCTAssertEqual(box.numComponents, 3)
        XCTAssertEqual(box.entries[0], [255, 0, 0])
        XCTAssertEqual(box.entries[1], [0, 255, 0])
    }
    
    func testPaletteBoxRoundTrip() throws {
        let entries: [[UInt32]] = [
            [255, 128, 0],
            [128, 255, 64],
            [0, 64, 255]
        ]
        
        let original = J2KPaletteBox(
            entries: entries,
            componentBitDepths: [.unsigned(8), .unsigned(8), .unsigned(8)]
        )
        
        let data = try original.write()
        var decoded = J2KPaletteBox(entries: [], componentBitDepths: [])
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.entries, original.entries)
        XCTAssertEqual(decoded.componentBitDepths, original.componentBitDepths)
    }
    
    func testPaletteBoxInvalidTooManyEntries() {
        let entries = Array(repeating: [UInt32(0)], count: 1025)
        let box = J2KPaletteBox(
            entries: entries,
            componentBitDepths: [.unsigned(8)]
        )
        
        XCTAssertThrowsError(try box.write())
    }
    
    func testPaletteBoxInvalidValueRange() {
        let entries: [[UInt32]] = [[256]] // Exceeds 8-bit max
        let box = J2KPaletteBox(
            entries: entries,
            componentBitDepths: [.unsigned(8)]
        )
        
        XCTAssertThrowsError(try box.write())
    }
    
    func testPaletteBoxMixedBitDepths() throws {
        let entries: [[UInt32]] = [
            [255, 1023, 15], // 8-bit, 10-bit, 4-bit
            [128, 512, 8]
        ]
        
        let box = J2KPaletteBox(
            entries: entries,
            componentBitDepths: [
                .unsigned(8),
                .unsigned(10),
                .unsigned(4)
            ]
        )
        
        let data = try box.write()
        var decoded = J2KPaletteBox(entries: [], componentBitDepths: [])
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.entries, box.entries)
    }
    
    // MARK: - Component Mapping Box Tests
    
    func testComponentMappingBoxCreation() {
        let box = J2KComponentMappingBox(mappings: [
            .direct(component: 0),
            .direct(component: 1),
            .direct(component: 2)
        ])
        
        XCTAssertEqual(box.boxType, .cmap)
        XCTAssertEqual(box.mappings.count, 3)
    }
    
    func testComponentMappingBoxWriteDirect() throws {
        let box = J2KComponentMappingBox(mappings: [
            .direct(component: 0),
            .direct(component: 1),
            .direct(component: 2)
        ])
        
        let data = try box.write()
        
        XCTAssertEqual(data.count, 12) // 3 mappings × 4 bytes
        
        // First mapping: CMP=0, MTYP=0, PCOL=0
        XCTAssertEqual(data[0], 0)
        XCTAssertEqual(data[1], 0)
        XCTAssertEqual(data[2], 0)
        XCTAssertEqual(data[3], 0)
        
        // Second mapping: CMP=1, MTYP=0, PCOL=0
        XCTAssertEqual(data[4], 0)
        XCTAssertEqual(data[5], 1)
        XCTAssertEqual(data[6], 0)
        XCTAssertEqual(data[7], 0)
        
        // Third mapping: CMP=2, MTYP=0, PCOL=0
        XCTAssertEqual(data[8], 0)
        XCTAssertEqual(data[9], 2)
        XCTAssertEqual(data[10], 0)
        XCTAssertEqual(data[11], 0)
    }
    
    func testComponentMappingBoxWritePalette() throws {
        let box = J2KComponentMappingBox(mappings: [
            .palette(component: 0, paletteColumn: 0),
            .palette(component: 0, paletteColumn: 1),
            .palette(component: 0, paletteColumn: 2)
        ])
        
        let data = try box.write()
        
        XCTAssertEqual(data.count, 12)
        
        // First mapping: CMP=0, MTYP=1, PCOL=0
        XCTAssertEqual(data[0], 0)
        XCTAssertEqual(data[1], 0)
        XCTAssertEqual(data[2], 1) // MTYP = 1
        XCTAssertEqual(data[3], 0)
        
        // Second mapping: CMP=0, MTYP=1, PCOL=1
        XCTAssertEqual(data[4], 0)
        XCTAssertEqual(data[5], 0)
        XCTAssertEqual(data[6], 1)
        XCTAssertEqual(data[7], 1)
        
        // Third mapping: CMP=0, MTYP=1, PCOL=2
        XCTAssertEqual(data[8], 0)
        XCTAssertEqual(data[9], 0)
        XCTAssertEqual(data[10], 1)
        XCTAssertEqual(data[11], 2)
    }
    
    func testComponentMappingBoxReadDirect() throws {
        var data = Data()
        
        // Three direct mappings
        data.append(contentsOf: [0, 0, 0, 0]) // CMP=0, MTYP=0, PCOL=0
        data.append(contentsOf: [0, 1, 0, 0]) // CMP=1, MTYP=0, PCOL=0
        data.append(contentsOf: [0, 2, 0, 0]) // CMP=2, MTYP=0, PCOL=0
        
        var box = J2KComponentMappingBox(mappings: [])
        try box.read(from: data)
        
        XCTAssertEqual(box.mappings.count, 3)
        XCTAssertEqual(box.mappings[0], .direct(component: 0))
        XCTAssertEqual(box.mappings[1], .direct(component: 1))
        XCTAssertEqual(box.mappings[2], .direct(component: 2))
    }
    
    func testComponentMappingBoxReadPalette() throws {
        var data = Data()
        
        // Three palette mappings
        data.append(contentsOf: [0, 0, 1, 0]) // CMP=0, MTYP=1, PCOL=0
        data.append(contentsOf: [0, 0, 1, 1]) // CMP=0, MTYP=1, PCOL=1
        data.append(contentsOf: [0, 0, 1, 2]) // CMP=0, MTYP=1, PCOL=2
        
        var box = J2KComponentMappingBox(mappings: [])
        try box.read(from: data)
        
        XCTAssertEqual(box.mappings.count, 3)
        XCTAssertEqual(box.mappings[0], .palette(component: 0, paletteColumn: 0))
        XCTAssertEqual(box.mappings[1], .palette(component: 0, paletteColumn: 1))
        XCTAssertEqual(box.mappings[2], .palette(component: 0, paletteColumn: 2))
    }
    
    func testComponentMappingBoxRoundTrip() throws {
        let original = J2KComponentMappingBox(mappings: [
            .direct(component: 0),
            .direct(component: 1),
            .palette(component: 0, paletteColumn: 5)
        ])
        
        let data = try original.write()
        var decoded = J2KComponentMappingBox(mappings: [])
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.mappings, original.mappings)
    }
    
    func testComponentMappingBoxInvalidEmpty() {
        let box = J2KComponentMappingBox(mappings: [])
        
        XCTAssertThrowsError(try box.write())
    }
    
    func testComponentMappingBoxInvalidMappingType() throws {
        var data = Data()
        data.append(contentsOf: [0, 0, 2, 0]) // MTYP=2 is invalid
        
        var box = J2KComponentMappingBox(mappings: [])
        
        XCTAssertThrowsError(try box.read(from: data))
    }
    
    // MARK: - Channel Definition Box Tests
    
    func testChannelDefinitionBoxCreation() {
        let box = J2KChannelDefinitionBox(channels: [
            .color(index: 0, association: 1),
            .color(index: 1, association: 2),
            .color(index: 2, association: 3)
        ])
        
        XCTAssertEqual(box.boxType, .cdef)
        XCTAssertEqual(box.channels.count, 3)
    }
    
    func testChannelDefinitionBoxWriteRGB() throws {
        let box = J2KChannelDefinitionBox(channels: [
            .color(index: 0, association: 1),
            .color(index: 1, association: 2),
            .color(index: 2, association: 3)
        ])
        
        let data = try box.write()
        
        // N = 3
        XCTAssertEqual(data.count, 2 + 3 * 6)
        XCTAssertEqual(UInt16(data[0]) << 8 | UInt16(data[1]), 3)
        
        // First channel: Cn=0, Typ=0, Asoc=1
        XCTAssertEqual(UInt16(data[2]) << 8 | UInt16(data[3]), 0)  // Cn
        XCTAssertEqual(UInt16(data[4]) << 8 | UInt16(data[5]), 0)  // Typ
        XCTAssertEqual(UInt16(data[6]) << 8 | UInt16(data[7]), 1)  // Asoc
    }
    
    func testChannelDefinitionBoxWriteRGBA() throws {
        let box = J2KChannelDefinitionBox(channels: [
            .color(index: 0, association: 1),
            .color(index: 1, association: 2),
            .color(index: 2, association: 3),
            .opacity(index: 3, association: 0)
        ])
        
        let data = try box.write()
        
        XCTAssertEqual(data.count, 2 + 4 * 6)
        
        // Fourth channel: Cn=3, Typ=1 (opacity), Asoc=0
        let offset = 2 + 3 * 6
        XCTAssertEqual(UInt16(data[offset]) << 8 | UInt16(data[offset + 1]), 3)    // Cn
        XCTAssertEqual(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]), 1)  // Typ
        XCTAssertEqual(UInt16(data[offset + 4]) << 8 | UInt16(data[offset + 5]), 0)  // Asoc
    }
    
    func testChannelDefinitionBoxWritePremultiplied() throws {
        let box = J2KChannelDefinitionBox(channels: [
            .color(index: 0, association: 1),
            .premultipliedOpacity(index: 1, association: 0)
        ])
        
        let data = try box.write()
        
        // Second channel: Typ=2 (premultiplied opacity)
        let offset = 2 + 6
        XCTAssertEqual(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]), 2)
    }
    
    func testChannelDefinitionBoxReadRGB() throws {
        var data = Data()
        
        // N = 3
        data.append(contentsOf: [0, 3])
        
        // Three color channels
        data.append(contentsOf: [0, 0, 0, 0, 0, 1]) // Cn=0, Typ=0, Asoc=1
        data.append(contentsOf: [0, 1, 0, 0, 0, 2]) // Cn=1, Typ=0, Asoc=2
        data.append(contentsOf: [0, 2, 0, 0, 0, 3]) // Cn=2, Typ=0, Asoc=3
        
        var box = J2KChannelDefinitionBox(channels: [])
        try box.read(from: data)
        
        XCTAssertEqual(box.channels.count, 3)
        XCTAssertEqual(box.channels[0].index, 0)
        XCTAssertEqual(box.channels[0].type, .color)
        XCTAssertEqual(box.channels[0].association, 1)
    }
    
    func testChannelDefinitionBoxReadRGBA() throws {
        var data = Data()
        
        // N = 4
        data.append(contentsOf: [0, 4])
        
        // RGB + Alpha
        data.append(contentsOf: [0, 0, 0, 0, 0, 1]) // R
        data.append(contentsOf: [0, 1, 0, 0, 0, 2]) // G
        data.append(contentsOf: [0, 2, 0, 0, 0, 3]) // B
        data.append(contentsOf: [0, 3, 0, 1, 0, 0]) // Alpha (Typ=1)
        
        var box = J2KChannelDefinitionBox(channels: [])
        try box.read(from: data)
        
        XCTAssertEqual(box.channels.count, 4)
        XCTAssertEqual(box.channels[3].type, .opacity)
    }
    
    func testChannelDefinitionBoxRoundTrip() throws {
        let original = J2KChannelDefinitionBox(channels: [
            .color(index: 0, association: 1),
            .color(index: 1, association: 2),
            .color(index: 2, association: 3),
            .opacity(index: 3, association: 0)
        ])
        
        let data = try original.write()
        var decoded = J2KChannelDefinitionBox(channels: [])
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.channels.count, original.channels.count)
        for i in 0..<decoded.channels.count {
            XCTAssertEqual(decoded.channels[i].index, original.channels[i].index)
            XCTAssertEqual(decoded.channels[i].type, original.channels[i].type)
            XCTAssertEqual(decoded.channels[i].association, original.channels[i].association)
        }
    }
    
    func testChannelDefinitionBoxUnspecified() throws {
        let box = J2KChannelDefinitionBox(channels: [
            .unspecified(index: 0, association: 65535)
        ])
        
        let data = try box.write()
        var decoded = J2KChannelDefinitionBox(channels: [])
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.channels[0].type, .unspecified)
        XCTAssertEqual(decoded.channels[0].association, 65535)
    }
    
    func testChannelDefinitionBoxInvalidEmpty() {
        let box = J2KChannelDefinitionBox(channels: [])
        
        XCTAssertThrowsError(try box.write())
    }
    
    func testChannelDefinitionBoxInvalidType() throws {
        var data = Data()
        data.append(contentsOf: [0, 1])
        data.append(contentsOf: [0, 0, 0, 5, 0, 0]) // Typ=5 is invalid
        
        var box = J2KChannelDefinitionBox(channels: [])
        
        XCTAssertThrowsError(try box.read(from: data))
    }
    
    // MARK: - Integration Tests
    
    func testCompleteJP2HeaderWithAllBoxes() throws {
        var writer = J2KBoxWriter()
        
        // 1. Signature box
        try writer.writeBox(J2KSignatureBox())
        
        // 2. File type box
        try writer.writeBox(J2KFileTypeBox(brand: .jp2, minorVersion: 0, compatibleBrands: [.jp2]))
        
        // 3. JP2 header with all boxes
        let ihdr = J2KImageHeaderBox(
            width: 512,
            height: 512,
            numComponents: 4,
            bitsPerComponent: 8,
            colorSpaceUnknown: 0
        )
        
        let bpcc = J2KBitsPerComponentBox(bitDepths: [
            .unsigned(8),
            .unsigned(8),
            .unsigned(8),
            .unsigned(8)
        ])
        
        let colr = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 0,
            approximation: 0
        )
        
        let cdef = J2KChannelDefinitionBox(channels: [
            .color(index: 0, association: 1),
            .color(index: 1, association: 2),
            .color(index: 2, association: 3),
            .opacity(index: 3, association: 0)
        ])
        
        let jp2h = J2KHeaderBox(boxes: [ihdr, bpcc, colr, cdef])
        try writer.writeBox(jp2h)
        
        let data = writer.data
        
        // Verify structure
        var reader = J2KBoxReader(data: data)
        
        let sigInfo = try reader.readNextBox()
        XCTAssertEqual(sigInfo?.type, .jp)
        
        let ftypInfo = try reader.readNextBox()
        XCTAssertEqual(ftypInfo?.type, .ftyp)
        
        let jp2hInfo = try reader.readNextBox()
        XCTAssertEqual(jp2hInfo?.type, .jp2h)
        
        XCTAssertTrue(reader.isAtEnd)
    }
    
    func testIndexedColorWithPaletteAndMapping() throws {
        // Create indexed color image setup
        let palette = J2KPaletteBox(
            entries: [
                [255, 0, 0],
                [0, 255, 0],
                [0, 0, 255],
                [255, 255, 0]
            ],
            componentBitDepths: [.unsigned(8), .unsigned(8), .unsigned(8)]
        )
        
        let cmap = J2KComponentMappingBox(mappings: [
            .palette(component: 0, paletteColumn: 0),
            .palette(component: 0, paletteColumn: 1),
            .palette(component: 0, paletteColumn: 2)
        ])
        
        let cdef = J2KChannelDefinitionBox(channels: [
            .color(index: 0, association: 1),
            .color(index: 1, association: 2),
            .color(index: 2, association: 3)
        ])
        
        // Write and read back
        let paletteData = try palette.write()
        let cmapData = try cmap.write()
        let cdefData = try cdef.write()
        
        var decodedPalette = J2KPaletteBox(entries: [], componentBitDepths: [])
        try decodedPalette.read(from: paletteData)
        
        var decodedCmap = J2KComponentMappingBox(mappings: [])
        try decodedCmap.read(from: cmapData)
        
        var decodedCdef = J2KChannelDefinitionBox(channels: [])
        try decodedCdef.read(from: cdefData)
        
        XCTAssertEqual(decodedPalette.numEntries, 4)
        XCTAssertEqual(decodedCmap.mappings.count, 3)
        XCTAssertEqual(decodedCdef.channels.count, 3)
    }
    
    // MARK: - Resolution Box Tests
    
    func testCaptureResolutionBox() throws {
        // Create capture resolution box with 72 DPI
        let box = J2KCaptureResolutionBox(
            horizontalResolution: (72, 1, 0),
            verticalResolution: (72, 1, 0),
            unit: .inch
        )
        
        // Write and read
        let data = try box.write()
        XCTAssertEqual(data.count, 19) // Fixed size
        
        var decoded = J2KCaptureResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .unknown
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.horizontalResolution.numerator, 72)
        XCTAssertEqual(decoded.horizontalResolution.denominator, 1)
        XCTAssertEqual(decoded.horizontalResolution.exponent, 0)
        XCTAssertEqual(decoded.verticalResolution.numerator, 72)
        XCTAssertEqual(decoded.verticalResolution.denominator, 1)
        XCTAssertEqual(decoded.verticalResolution.exponent, 0)
        XCTAssertEqual(decoded.unit, .inch)
    }
    
    func testCaptureResolutionBoxHighDPI() throws {
        // Create capture resolution box with 300 DPI
        let box = J2KCaptureResolutionBox(
            horizontalResolution: (300, 1, 0),
            verticalResolution: (300, 1, 0),
            unit: .inch
        )
        
        let data = try box.write()
        
        var decoded = J2KCaptureResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .unknown
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.horizontalResolution.numerator, 300)
        XCTAssertEqual(decoded.verticalResolution.numerator, 300)
        XCTAssertEqual(decoded.unit, .inch)
    }
    
    func testCaptureResolutionBoxWithExponent() throws {
        // Create resolution with exponent: 72 × 10^2 = 7200
        let box = J2KCaptureResolutionBox(
            horizontalResolution: (72, 1, 2),
            verticalResolution: (72, 1, 2),
            unit: .metre
        )
        
        let data = try box.write()
        
        var decoded = J2KCaptureResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .unknown
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.horizontalResolution.exponent, 2)
        XCTAssertEqual(decoded.verticalResolution.exponent, 2)
    }
    
    func testCaptureResolutionBoxWithNegativeExponent() throws {
        // Create resolution with negative exponent: 720 × 10^-1 = 72
        let box = J2KCaptureResolutionBox(
            horizontalResolution: (720, 1, -1),
            verticalResolution: (720, 1, -1),
            unit: .inch
        )
        
        let data = try box.write()
        
        var decoded = J2KCaptureResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .unknown
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.horizontalResolution.exponent, -1)
        XCTAssertEqual(decoded.verticalResolution.exponent, -1)
    }
    
    func testCaptureResolutionBoxWithFraction() throws {
        // Create resolution with fraction: 7200 / 100 = 72
        let box = J2KCaptureResolutionBox(
            horizontalResolution: (7200, 100, 0),
            verticalResolution: (7200, 100, 0),
            unit: .inch
        )
        
        let data = try box.write()
        
        var decoded = J2KCaptureResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .unknown
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.horizontalResolution.numerator, 7200)
        XCTAssertEqual(decoded.horizontalResolution.denominator, 100)
    }
    
    func testCaptureResolutionBoxUnknownUnit() throws {
        let box = J2KCaptureResolutionBox(
            horizontalResolution: (100, 1, 0),
            verticalResolution: (100, 1, 0),
            unit: .unknown
        )
        
        let data = try box.write()
        
        var decoded = J2KCaptureResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .inch
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.unit, .unknown)
    }
    
    func testDisplayResolutionBox() throws {
        // Create display resolution box with 96 DPI
        let box = J2KDisplayResolutionBox(
            horizontalResolution: (96, 1, 0),
            verticalResolution: (96, 1, 0),
            unit: .inch
        )
        
        let data = try box.write()
        XCTAssertEqual(data.count, 19)
        
        var decoded = J2KDisplayResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .unknown
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.horizontalResolution.numerator, 96)
        XCTAssertEqual(decoded.verticalResolution.numerator, 96)
        XCTAssertEqual(decoded.unit, .inch)
    }
    
    func testDisplayResolutionBoxMetres() throws {
        // Create resolution in pixels per metre: 2835 ppm ≈ 72 DPI
        let box = J2KDisplayResolutionBox(
            horizontalResolution: (2835, 1, 0),
            verticalResolution: (2835, 1, 0),
            unit: .metre
        )
        
        let data = try box.write()
        
        var decoded = J2KDisplayResolutionBox(
            horizontalResolution: (0, 0, 0),
            verticalResolution: (0, 0, 0),
            unit: .unknown
        )
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.horizontalResolution.numerator, 2835)
        XCTAssertEqual(decoded.unit, .metre)
    }
    
    func testResolutionBox() throws {
        let captureRes = J2KCaptureResolutionBox(
            horizontalResolution: (300, 1, 0),
            verticalResolution: (300, 1, 0),
            unit: .inch
        )
        
        let displayRes = J2KDisplayResolutionBox(
            horizontalResolution: (72, 1, 0),
            verticalResolution: (72, 1, 0),
            unit: .inch
        )
        
        let box = J2KResolutionBox(
            captureResolution: captureRes,
            displayResolution: displayRes
        )
        
        let data = try box.write()
        
        // Should contain two complete boxes (header + content for each)
        XCTAssertGreaterThan(data.count, 0)
        
        var decoded = J2KResolutionBox()
        try decoded.read(from: data)
        
        XCTAssertNotNil(decoded.captureResolution)
        XCTAssertNotNil(decoded.displayResolution)
        XCTAssertEqual(decoded.captureResolution?.horizontalResolution.numerator, 300)
        XCTAssertEqual(decoded.displayResolution?.horizontalResolution.numerator, 72)
    }
    
    func testResolutionBoxCaptureOnly() throws {
        let captureRes = J2KCaptureResolutionBox(
            horizontalResolution: (150, 1, 0),
            verticalResolution: (150, 1, 0),
            unit: .inch
        )
        
        let box = J2KResolutionBox(captureResolution: captureRes, displayResolution: nil)
        
        let data = try box.write()
        
        var decoded = J2KResolutionBox()
        try decoded.read(from: data)
        
        XCTAssertNotNil(decoded.captureResolution)
        XCTAssertNil(decoded.displayResolution)
        XCTAssertEqual(decoded.captureResolution?.horizontalResolution.numerator, 150)
    }
    
    func testResolutionBoxDisplayOnly() throws {
        let displayRes = J2KDisplayResolutionBox(
            horizontalResolution: (96, 1, 0),
            verticalResolution: (96, 1, 0),
            unit: .inch
        )
        
        let box = J2KResolutionBox(captureResolution: nil, displayResolution: displayRes)
        
        let data = try box.write()
        
        var decoded = J2KResolutionBox()
        try decoded.read(from: data)
        
        XCTAssertNil(decoded.captureResolution)
        XCTAssertNotNil(decoded.displayResolution)
        XCTAssertEqual(decoded.displayResolution?.horizontalResolution.numerator, 96)
    }
    
    func testResolutionBoxEmpty() throws {
        let box = J2KResolutionBox()
        
        let data = try box.write()
        XCTAssertEqual(data.count, 0) // Empty box
        
        var decoded = J2KResolutionBox()
        try decoded.read(from: data)
        
        XCTAssertNil(decoded.captureResolution)
        XCTAssertNil(decoded.displayResolution)
    }
    
    // MARK: - UUID Box Tests
    
    func testUUIDBox() throws {
        let uuid = UUID()
        let customData = "Custom metadata".data(using: .utf8)!
        
        let box = J2KUUIDBox(uuid: uuid, data: customData)
        
        let data = try box.write()
        XCTAssertEqual(data.count, 16 + customData.count)
        
        var decoded = J2KUUIDBox(uuid: UUID(), data: Data())
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.uuid, uuid)
        XCTAssertEqual(decoded.data, customData)
    }
    
    func testUUIDBoxEmptyData() throws {
        let uuid = UUID()
        let box = J2KUUIDBox(uuid: uuid, data: Data())
        
        let data = try box.write()
        XCTAssertEqual(data.count, 16)
        
        var decoded = J2KUUIDBox(uuid: UUID(), data: Data())
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.uuid, uuid)
        XCTAssertEqual(decoded.data.count, 0)
    }
    
    func testUUIDBoxLargeData() throws {
        let uuid = UUID()
        let largeData = Data(repeating: 0x42, count: 10000)
        
        let box = J2KUUIDBox(uuid: uuid, data: largeData)
        
        let data = try box.write()
        XCTAssertEqual(data.count, 16 + 10000)
        
        var decoded = J2KUUIDBox(uuid: UUID(), data: Data())
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.uuid, uuid)
        XCTAssertEqual(decoded.data.count, 10000)
        XCTAssertEqual(decoded.data.first, 0x42)
    }
    
    func testUUIDBoxPreservesUUID() throws {
        // Test that UUID is preserved exactly through write/read
        let uuidString = "550e8400-e29b-41d4-a716-446655440000"
        let uuid = UUID(uuidString: uuidString)!
        
        let box = J2KUUIDBox(uuid: uuid, data: Data([1, 2, 3]))
        
        let data = try box.write()
        
        var decoded = J2KUUIDBox(uuid: UUID(), data: Data())
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.uuid.uuidString.uppercased(), uuidString.uppercased())
    }
    
    func testUUIDBoxBinaryData() throws {
        let uuid = UUID()
        let binaryData = Data([0x00, 0xFF, 0x01, 0xFE, 0x7F, 0x80])
        
        let box = J2KUUIDBox(uuid: uuid, data: binaryData)
        
        let data = try box.write()
        
        var decoded = J2KUUIDBox(uuid: UUID(), data: Data())
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.data, binaryData)
    }
    
    // MARK: - XML Box Tests
    
    func testXMLBox() throws {
        let xmlString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <metadata>
            <title>Sample Image</title>
            <author>John Doe</author>
        </metadata>
        """
        
        let box = try J2KXMLBox(xmlString: xmlString)
        
        let data = try box.write()
        XCTAssertGreaterThan(data.count, 0)
        
        var decoded = try J2KXMLBox(xmlString: "")
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.xmlString, xmlString)
    }
    
    func testXMLBoxMinimal() throws {
        let xmlString = "<root/>"
        
        let box = try J2KXMLBox(xmlString: xmlString)
        
        let data = try box.write()
        
        var decoded = try J2KXMLBox(xmlString: "")
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.xmlString, xmlString)
    }
    
    func testXMLBoxComplex() throws {
        let xmlString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <image xmlns="http://example.com/schema">
            <metadata>
                <title>Test Image</title>
                <description>A test image with metadata</description>
                <keywords>
                    <keyword>test</keyword>
                    <keyword>jpeg2000</keyword>
                </keywords>
            </metadata>
            <technical>
                <width>1920</width>
                <height>1080</height>
                <colorSpace>sRGB</colorSpace>
            </technical>
        </image>
        """
        
        let box = try J2KXMLBox(xmlString: xmlString)
        
        let data = try box.write()
        
        var decoded = try J2KXMLBox(xmlString: "")
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.xmlString, xmlString)
    }
    
    func testXMLBoxWithUnicode() throws {
        let xmlString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <metadata>
            <title>测试图像</title>
            <description>Тестовое изображение</description>
            <author>José García</author>
        </metadata>
        """
        
        let box = try J2KXMLBox(xmlString: xmlString)
        
        let data = try box.write()
        
        var decoded = try J2KXMLBox(xmlString: "")
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.xmlString, xmlString)
    }
    
    func testXMLBoxWithSpecialCharacters() throws {
        let xmlString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <data>
            <value>&lt;![CDATA[Special &amp; characters]]&gt;</value>
            <escaped>&quot;Quotes&quot; and &apos;apostrophes&apos;</escaped>
        </data>
        """
        
        let box = try J2KXMLBox(xmlString: xmlString)
        
        let data = try box.write()
        
        var decoded = try J2KXMLBox(xmlString: "")
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.xmlString, xmlString)
    }
    
    func testXMLBoxFromData() throws {
        let xmlString = "<root><item>Test</item></root>"
        let xmlData = xmlString.data(using: .utf8)!
        
        let box = try J2KXMLBox(data: xmlData)
        
        XCTAssertEqual(box.xmlString, xmlString)
    }
    
    func testXMLBoxFromDataInvalidUTF8() throws {
        // Invalid UTF-8 sequence
        let invalidData = Data([0xFF, 0xFE, 0xFD])
        
        XCTAssertThrowsError(try J2KXMLBox(data: invalidData)) { error in
            if case J2KError.fileFormatError(let message) = error {
                XCTAssertTrue(message.contains("UTF-8"))
            } else {
                XCTFail("Expected fileFormatError")
            }
        }
    }
    
    func testXMLBoxLarge() throws {
        // Test with a large XML document
        var xmlString = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<items>\n"
        for i in 0..<1000 {
            xmlString += "    <item id=\"\(i)\">Value \(i)</item>\n"
        }
        xmlString += "</items>"
        
        let box = try J2KXMLBox(xmlString: xmlString)
        
        let data = try box.write()
        
        var decoded = try J2KXMLBox(xmlString: "")
        try decoded.read(from: data)
        
        XCTAssertEqual(decoded.xmlString, xmlString)
    }
    
    // MARK: - Integration Tests
    
    func testResolutionBoxWithinHeaderBox() throws {
        // Test that resolution box works within a JP2 header
        let captureRes = J2KCaptureResolutionBox(
            horizontalResolution: (300, 1, 0),
            verticalResolution: (300, 1, 0),
            unit: .inch
        )
        
        let displayRes = J2KDisplayResolutionBox(
            horizontalResolution: (72, 1, 0),
            verticalResolution: (72, 1, 0),
            unit: .inch
        )
        
        let resBox = J2KResolutionBox(
            captureResolution: captureRes,
            displayResolution: displayRes
        )
        
        // Write resolution box with full headers
        var writer = J2KBoxWriter()
        try writer.writeBox(resBox)
        let data = writer.data
        
        // Read it back
        var reader = J2KBoxReader(data: data)
        let boxInfo = try reader.readNextBox()
        
        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type, .res)
        
        let content = reader.extractContent(from: boxInfo!)
        var decoded = J2KResolutionBox()
        try decoded.read(from: content)
        
        XCTAssertNotNil(decoded.captureResolution)
        XCTAssertNotNil(decoded.displayResolution)
    }
    
    func testUUIDBoxWithinFile() throws {
        // Test UUID box as part of a JP2 file structure
        let uuid = UUID()
        let metadata = """
        {"format": "JPEG 2000", "version": "1.0"}
        """.data(using: .utf8)!
        
        let box = J2KUUIDBox(uuid: uuid, data: metadata)
        
        var writer = J2KBoxWriter()
        try writer.writeBox(box)
        let data = writer.data
        
        var reader = J2KBoxReader(data: data)
        let boxInfo = try reader.readNextBox()
        
        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type, .uuid)
        
        let content = reader.extractContent(from: boxInfo!)
        var decoded = J2KUUIDBox(uuid: UUID(), data: Data())
        try decoded.read(from: content)
        
        XCTAssertEqual(decoded.uuid, uuid)
        XCTAssertEqual(decoded.data, metadata)
    }
    
    func testXMLBoxWithinFile() throws {
        // Test XML box as part of a JP2 file structure
        let xmlString = """
        <?xml version="1.0"?>
        <metadata>
            <creator>Test Suite</creator>
        </metadata>
        """
        
        let box = try J2KXMLBox(xmlString: xmlString)
        
        var writer = J2KBoxWriter()
        try writer.writeBox(box)
        let data = writer.data
        
        var reader = J2KBoxReader(data: data)
        let boxInfo = try reader.readNextBox()
        
        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type, .xml)
        
        let content = reader.extractContent(from: boxInfo!)
        var decoded = try J2KXMLBox(xmlString: "")
        try decoded.read(from: content)
        
        XCTAssertEqual(decoded.xmlString, xmlString)
    }
}
