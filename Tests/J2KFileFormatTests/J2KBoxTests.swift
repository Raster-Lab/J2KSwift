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
}
