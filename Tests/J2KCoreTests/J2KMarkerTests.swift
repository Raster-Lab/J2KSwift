//
// J2KMarkerTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests for the marker segment parser functionality.
final class J2KMarkerTests: XCTestCase {
    // MARK: - J2KMarker Tests

    func testMarkerValues() throws {
        // Delimiting markers
        XCTAssertEqual(J2KMarker.soc.rawValue, 0xFF4F)
        XCTAssertEqual(J2KMarker.sot.rawValue, 0xFF90)
        XCTAssertEqual(J2KMarker.sod.rawValue, 0xFF93)
        XCTAssertEqual(J2KMarker.eoc.rawValue, 0xFFD9)

        // Fixed information markers
        XCTAssertEqual(J2KMarker.siz.rawValue, 0xFF51)

        // Functional markers
        XCTAssertEqual(J2KMarker.cod.rawValue, 0xFF52)
        XCTAssertEqual(J2KMarker.coc.rawValue, 0xFF53)
        XCTAssertEqual(J2KMarker.qcd.rawValue, 0xFF5C)
        XCTAssertEqual(J2KMarker.qcc.rawValue, 0xFF5D)

        // In-bitstream markers
        XCTAssertEqual(J2KMarker.sop.rawValue, 0xFF91)
        XCTAssertEqual(J2KMarker.eph.rawValue, 0xFF92)

        // Informational markers
        XCTAssertEqual(J2KMarker.com.rawValue, 0xFF64)
    }

    func testMarkerHasSegment() throws {
        // Markers without segments
        XCTAssertFalse(J2KMarker.soc.hasSegment)
        XCTAssertFalse(J2KMarker.sod.hasSegment)
        XCTAssertFalse(J2KMarker.eoc.hasSegment)
        XCTAssertFalse(J2KMarker.eph.hasSegment)

        // Markers with segments
        XCTAssertTrue(J2KMarker.siz.hasSegment)
        XCTAssertTrue(J2KMarker.cod.hasSegment)
        XCTAssertTrue(J2KMarker.qcd.hasSegment)
        XCTAssertTrue(J2KMarker.sot.hasSegment)
        XCTAssertTrue(J2KMarker.com.hasSegment)
    }

    func testMarkerIsDelimiting() throws {
        XCTAssertTrue(J2KMarker.soc.isDelimiting)
        XCTAssertTrue(J2KMarker.sot.isDelimiting)
        XCTAssertTrue(J2KMarker.sod.isDelimiting)
        XCTAssertTrue(J2KMarker.eoc.isDelimiting)

        XCTAssertFalse(J2KMarker.siz.isDelimiting)
        XCTAssertFalse(J2KMarker.cod.isDelimiting)
        XCTAssertFalse(J2KMarker.com.isDelimiting)
    }

    func testMarkerCanAppearInMainHeader() throws {
        XCTAssertTrue(J2KMarker.siz.canAppearInMainHeader)
        XCTAssertTrue(J2KMarker.cod.canAppearInMainHeader)
        XCTAssertTrue(J2KMarker.coc.canAppearInMainHeader)
        XCTAssertTrue(J2KMarker.qcd.canAppearInMainHeader)
        XCTAssertTrue(J2KMarker.qcc.canAppearInMainHeader)
        XCTAssertTrue(J2KMarker.com.canAppearInMainHeader)

        XCTAssertFalse(J2KMarker.sot.canAppearInMainHeader)
        XCTAssertFalse(J2KMarker.sod.canAppearInMainHeader)
        XCTAssertFalse(J2KMarker.plt.canAppearInMainHeader)
    }

    func testMarkerCanAppearInTileHeader() throws {
        XCTAssertTrue(J2KMarker.cod.canAppearInTileHeader)
        XCTAssertTrue(J2KMarker.coc.canAppearInTileHeader)
        XCTAssertTrue(J2KMarker.qcd.canAppearInTileHeader)
        XCTAssertTrue(J2KMarker.plt.canAppearInTileHeader)
        XCTAssertTrue(J2KMarker.com.canAppearInTileHeader)

        XCTAssertFalse(J2KMarker.siz.canAppearInTileHeader)
        XCTAssertFalse(J2KMarker.tlm.canAppearInTileHeader)
    }

    func testMarkerName() throws {
        XCTAssertEqual(J2KMarker.soc.name, "SOC (Start of codestream)")
        XCTAssertEqual(J2KMarker.eoc.name, "EOC (End of codestream)")
        XCTAssertEqual(J2KMarker.siz.name, "SIZ (Image and tile size)")
        XCTAssertEqual(J2KMarker.cod.name, "COD (Coding style default)")
        XCTAssertEqual(J2KMarker.com.name, "COM (Comment)")
    }

    // MARK: - J2KMarkerSegment Tests

    func testMarkerSegmentInitialization() throws {
        let data = Data([0x01, 0x02, 0x03])
        let segment = J2KMarkerSegment(marker: .cod, position: 10, data: data)

        XCTAssertEqual(segment.marker, .cod)
        XCTAssertEqual(segment.position, 10)
        XCTAssertEqual(segment.data, data)
    }

    func testMarkerSegmentTotalLength() throws {
        let data = Data([0x01, 0x02, 0x03])

        // Marker with segment: marker (2) + length (2) + data (3) = 7
        let codSegment = J2KMarkerSegment(marker: .cod, position: 0, data: data)
        XCTAssertEqual(codSegment.totalLength, 7)

        // Marker without segment: just marker (2)
        let socSegment = J2KMarkerSegment(marker: .soc, position: 0)
        XCTAssertEqual(socSegment.totalLength, 2)
    }

    // MARK: - J2KMarkerParser Tests

    func testParseMarkerSegmentSOC() throws {
        let data = Data([0xFF, 0x4F])
        let parser = J2KMarkerParser(data: data)

        let segment = try parser.parseMarkerSegment(at: 0)

        XCTAssertEqual(segment.marker, .soc)
        XCTAssertEqual(segment.position, 0)
        XCTAssertTrue(segment.data.isEmpty)
    }

    func testParseMarkerSegmentWithData() throws {
        // COM marker with 3 bytes of data
        // Format: marker (FF64) + length (0005) + data (01 02 03)
        let data = Data([0xFF, 0x64, 0x00, 0x05, 0x01, 0x02, 0x03])
        let parser = J2KMarkerParser(data: data)

        let segment = try parser.parseMarkerSegment(at: 0)

        XCTAssertEqual(segment.marker, .com)
        XCTAssertEqual(segment.position, 0)
        XCTAssertEqual(segment.data, Data([0x01, 0x02, 0x03]))
    }

    func testParseMainHeader() throws {
        // Minimal valid codestream: SOC + SIZ + COD + QCD + SOT
        var data = Data()

        // SOC marker
        data.append(contentsOf: [0xFF, 0x4F])

        // SIZ marker segment (minimal)
        data.append(contentsOf: [0xFF, 0x51]) // marker
        data.append(contentsOf: [0x00, 0x29]) // length = 41 (2 + 39 for 1 component)
        data.append(contentsOf: [0x00, 0x00]) // Rsiz
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Xsiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Ysiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XOsiz
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YOsiz
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // XTsiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // YTsiz = 256
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XTOsiz
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YTOsiz
        data.append(contentsOf: [0x00, 0x01]) // Csiz = 1 component
        data.append(contentsOf: [0x07]) // Ssiz = 8 bits
        data.append(contentsOf: [0x01]) // XRsiz
        data.append(contentsOf: [0x01]) // YRsiz

        // COD marker segment (minimal)
        data.append(contentsOf: [0xFF, 0x52]) // marker
        data.append(contentsOf: [0x00, 0x0C]) // length = 12
        data.append(contentsOf: [0x00]) // Scod
        data.append(contentsOf: [0x00]) // SGcod progression order
        data.append(contentsOf: [0x00, 0x01]) // SGcod layers
        data.append(contentsOf: [0x00]) // SGcod MCT
        data.append(contentsOf: [0x05]) // SPcod levels
        data.append(contentsOf: [0x03]) // SPcod code-block width
        data.append(contentsOf: [0x03]) // SPcod code-block height
        data.append(contentsOf: [0x00]) // SPcod style
        data.append(contentsOf: [0x00]) // SPcod transform

        // SOT marker (end of main header)
        data.append(contentsOf: [0xFF, 0x90]) // marker
        data.append(contentsOf: [0x00, 0x0A]) // length = 10
        data.append(contentsOf: [0x00, 0x00]) // Isot = tile 0
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Psot = 0 (unknown)
        data.append(contentsOf: [0x00]) // TPsot
        data.append(contentsOf: [0x01]) // TNsot

        let parser = J2KMarkerParser(data: data)
        let segments = try parser.parseMainHeader()

        // Should have SOC, SIZ, COD, SOT
        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments[0].marker, .soc)
        XCTAssertEqual(segments[1].marker, .siz)
        XCTAssertEqual(segments[2].marker, .cod)
        XCTAssertEqual(segments[3].marker, .sot)
    }

    func testValidateBasicStructure() throws {
        // Valid codestream starting with SOC, SIZ
        let validData = Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x10])
        let validParser = J2KMarkerParser(data: validData)
        XCTAssertTrue(validParser.validateBasicStructure())

        // Invalid: doesn't start with SOC
        let invalidData1 = Data([0xFF, 0x51, 0x00, 0x10])
        let invalidParser1 = J2KMarkerParser(data: invalidData1)
        XCTAssertFalse(invalidParser1.validateBasicStructure())

        // Invalid: too small
        let invalidData2 = Data([0xFF])
        let invalidParser2 = J2KMarkerParser(data: invalidData2)
        XCTAssertFalse(invalidParser2.validateBasicStructure())
    }

    func testFindMarkers() throws {
        let data = Data([
            0xFF, 0x4F,             // SOC at 0
            0xFF, 0x51, 0x00, 0x04, 0x00, 0x00, // SIZ at 2
            0xFF, 0x64, 0x00, 0x03, 0x00, // COM at 8
            0xFF, 0x64, 0x00, 0x03, 0x00  // COM at 13
        ])
        let parser = J2KMarkerParser(data: data)

        let socPositions = parser.findMarkers(.soc)
        XCTAssertEqual(socPositions, [0])

        let comPositions = parser.findMarkers(.com)
        XCTAssertEqual(comPositions, [8, 13])

        let eocPositions = parser.findMarkers(.eoc)
        XCTAssertEqual(eocPositions, [])
    }

    func testParseInvalidMarker() throws {
        let data = Data([0x00, 0x00]) // Not a valid marker
        let parser = J2KMarkerParser(data: data)

        XCTAssertThrowsError(try parser.parseMarkerSegment(at: 0)) { error in
            guard case J2KError.invalidData = error else {
                XCTFail("Expected invalidData error")
                return
            }
        }
    }

    func testParseTruncatedSegment() throws {
        // COM marker with incomplete data
        let data = Data([0xFF, 0x64, 0x00, 0x10]) // Length says 16 bytes, but only 4 present
        let parser = J2KMarkerParser(data: data)

        XCTAssertThrowsError(try parser.parseMarkerSegment(at: 0)) { error in
            guard case J2KError.invalidData = error else {
                XCTFail("Expected invalidData error")
                return
            }
        }
    }

    func testParseMainHeaderWithoutSOC() throws {
        let data = Data([0xFF, 0x51, 0x00, 0x04, 0x00, 0x00])
        let parser = J2KMarkerParser(data: data)

        XCTAssertThrowsError(try parser.parseMainHeader()) { error in
            guard case J2KError.invalidData = error else {
                XCTFail("Expected invalidData error")
                return
            }
        }
    }
}
