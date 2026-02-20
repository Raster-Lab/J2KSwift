//
// J2KDCOffsetExtensionBoxTests.swift
// J2KSwift
//
// J2KDCOffsetExtensionBoxTests.swift
// J2KSwift
//
// Tests for JP2/JPX DC offset extension box (Part 2).
//

import XCTest
@testable import J2KFileFormat
@testable import J2KCodec
@testable import J2KCore

/// Tests for the DC offset extension box in JP2/JPX file format.
final class J2KDCOffsetExtensionBoxTests: XCTestCase {
    // MARK: - Box Type Tests

    func testDCOffsetBoxType() {
        XCTAssertEqual(J2KBoxType.dcof.stringValue, "dcof")
    }

    func testDCOffsetBoxTypeCreation() {
        let box = J2KDCOffsetExtensionBox()
        XCTAssertEqual(box.boxType, .dcof)
    }

    // MARK: - Write Tests

    func testWriteDefaultBox() throws {
        let box = J2KDCOffsetExtensionBox()
        let data = try box.write()

        XCTAssertEqual(data.count, 4)
        // Offset type: 0 (integer)
        XCTAssertEqual(data[0], 0x00)
        // Component count: 0
        XCTAssertEqual(data[1], 0x00)
        XCTAssertEqual(data[2], 0x00)
        // Flags: 0x01 (enabled)
        XCTAssertEqual(data[3], 0x01)
    }

    func testWriteCustomBox() throws {
        let box = J2KDCOffsetExtensionBox(
            offsetType: .floatingPoint,
            componentCount: 3,
            enabled: true
        )
        let data = try box.write()

        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data[0], 0x01) // floating-point
        XCTAssertEqual(data[1], 0x00) // high byte of 3
        XCTAssertEqual(data[2], 0x03) // low byte of 3
        XCTAssertEqual(data[3], 0x01) // enabled
    }

    func testWriteDisabledBox() throws {
        let box = J2KDCOffsetExtensionBox(
            offsetType: .integer,
            componentCount: 1,
            enabled: false
        )
        let data = try box.write()
        XCTAssertEqual(data[3], 0x00) // disabled
    }

    // MARK: - Read Tests

    func testReadBox() throws {
        let data = Data([0x00, 0x00, 0x03, 0x01]) // integer, 3 components, enabled
        var box = J2KDCOffsetExtensionBox()
        try box.read(from: data)

        XCTAssertEqual(box.offsetType, .integer)
        XCTAssertEqual(box.componentCount, 3)
        XCTAssertTrue(box.enabled)
    }

    func testReadBoxFloatingPoint() throws {
        let data = Data([0x01, 0x00, 0x04, 0x01])
        var box = J2KDCOffsetExtensionBox()
        try box.read(from: data)

        XCTAssertEqual(box.offsetType, .floatingPoint)
        XCTAssertEqual(box.componentCount, 4)
        XCTAssertTrue(box.enabled)
    }

    func testReadBoxDisabled() throws {
        let data = Data([0x00, 0x00, 0x01, 0x00])
        var box = J2KDCOffsetExtensionBox()
        try box.read(from: data)

        XCTAssertFalse(box.enabled)
    }

    func testReadBoxTooShort() {
        let data = Data([0x00, 0x00])
        var box = J2KDCOffsetExtensionBox()
        XCTAssertThrowsError(try box.read(from: data))
    }

    func testReadBoxInvalidOffsetType() {
        let data = Data([0xFF, 0x00, 0x01, 0x01])
        var box = J2KDCOffsetExtensionBox()
        XCTAssertThrowsError(try box.read(from: data))
    }

    // MARK: - Round-Trip Tests

    func testRoundTrip() throws {
        let original = J2KDCOffsetExtensionBox(
            offsetType: .floatingPoint,
            componentCount: 5,
            enabled: true
        )
        let data = try original.write()

        var decoded = J2KDCOffsetExtensionBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.offsetType, original.offsetType)
        XCTAssertEqual(decoded.componentCount, original.componentCount)
        XCTAssertEqual(decoded.enabled, original.enabled)
    }

    func testRoundTripWithBoxWriter() throws {
        let box = J2KDCOffsetExtensionBox(
            offsetType: .integer,
            componentCount: 3,
            enabled: true
        )

        var writer = J2KBoxWriter()
        try writer.writeBox(box)
        let fullData = writer.data

        // Verify the box header
        XCTAssertGreaterThan(fullData.count, 8)

        // Parse with box reader
        var reader = J2KBoxReader(data: fullData)
        let boxInfo = try reader.readNextBox()

        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type, .dcof)

        // Read content
        let content = reader.extractContent(from: boxInfo!)
        var readBox = J2KDCOffsetExtensionBox()
        try readBox.read(from: content)

        XCTAssertEqual(readBox.offsetType, .integer)
        XCTAssertEqual(readBox.componentCount, 3)
        XCTAssertTrue(readBox.enabled)
    }
}
