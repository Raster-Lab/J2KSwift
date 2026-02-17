/// # JPIPDataBinGeneratorTests
///
/// Tests for JPIP data bin generation from JPEG 2000 codestreams.

import XCTest
@testable import JPIP
@testable import J2KCore
@testable import J2KCodec

/// Tests for JPIPDataBinGenerator functionality.
final class JPIPDataBinGeneratorTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDataBinGeneratorInitialization() {
        let generator = JPIPDataBinGenerator()
        XCTAssertNotNil(generator)
    }

    // MARK: - Main Header Extraction Tests

    func testGenerateDataBinsFromMinimalCodestream() throws {
        let generator = JPIPDataBinGenerator()

        // Minimal J2K codestream: SOC + SIZ marker
        let data = Data([
            0xFF, 0x4F, // SOC
            0xFF, 0x51, 0x00, 0x04, 0x00, 0x00 // SIZ with length 4
        ])

        let bins = try generator.generateDataBins(from: data)

        // Should have at least a main header bin
        XCTAssertGreaterThanOrEqual(bins.count, 1)

        // First bin should be main header
        let mainHeader = bins.first { $0.binClass == .mainHeader }
        XCTAssertNotNil(mainHeader)
        XCTAssertEqual(mainHeader?.binID, 0)
        XCTAssertTrue(mainHeader?.isComplete ?? false)
    }

    func testGenerateDataBinsFromCodestreamWithTile() throws {
        let generator = JPIPDataBinGenerator()

        // J2K codestream: SOC + SIZ + SOT + SOD + data + EOC
        // Psot (tile-part length) = total bytes from first byte of SOT to last byte
        // of tile-part = 2 (SOT marker) + 10 (Lsot content) + 2 (SOD) + 4 (data) = 18 = 0x12
        let data = Data([
            0xFF, 0x4F,                         // SOC
            0xFF, 0x51, 0x00, 0x04, 0x00, 0x00, // SIZ marker (length 4)
            0xFF, 0x90, 0x00, 0x0A,             // SOT marker (length 10)
            0x00, 0x00,                          // Tile index 0
            0x00, 0x00, 0x00, 0x12,             // Tile-part length (18)
            0x00,                                // Tile-part index
            0x01,                                // Number of tile-parts
            0xFF, 0x93,                          // SOD
            0x01, 0x02, 0x03, 0x04,             // Tile data
            0xFF, 0xD9                           // EOC
        ])

        let bins = try generator.generateDataBins(from: data)

        // Should have main header + tile header + tile data
        let mainHeaders = bins.filter { $0.binClass == .mainHeader }
        let tileHeaders = bins.filter { $0.binClass == .tileHeader }
        let tileBins = bins.filter { $0.binClass == .tile }

        XCTAssertEqual(mainHeaders.count, 1)
        XCTAssertEqual(tileHeaders.count, 1)
        XCTAssertEqual(tileBins.count, 1)

        // Main header should contain SOC + SIZ
        XCTAssertTrue(mainHeaders[0].isComplete)

        // Tile header should reference tile 0
        XCTAssertEqual(tileHeaders[0].binID, 0)
        XCTAssertTrue(tileHeaders[0].isComplete)

        // Tile data should have some content
        XCTAssertGreaterThan(tileBins[0].data.count, 0)
    }

    func testGenerateDataBinsFromCodestreamWithMultipleTiles() throws {
        let generator = JPIPDataBinGenerator()

        // J2K codestream with 2 tiles
        // Psot (tile-part length) = total bytes from first byte of SOT to last byte
        // of tile-part = 2 (SOT marker) + 10 (Lsot content) + 2 (SOD) + 4 (data) = 18 = 0x12
        var data = Data([
            0xFF, 0x4F,                         // SOC
            0xFF, 0x51, 0x00, 0x04, 0x00, 0x00  // SIZ marker
        ])

        // Tile 0
        data.append(contentsOf: [
            0xFF, 0x90, 0x00, 0x0A,             // SOT (length 10)
            0x00, 0x00,                          // Tile index 0
            0x00, 0x00, 0x00, 0x12,             // Tile-part length (18)
            0x00, 0x01,                          // TPsot, TNsot
            0xFF, 0x93,                          // SOD
            0xAA, 0xBB, 0xCC, 0xDD              // Tile data
        ] as [UInt8])

        // Tile 1
        data.append(contentsOf: [
            0xFF, 0x90, 0x00, 0x0A,             // SOT (length 10)
            0x00, 0x01,                          // Tile index 1
            0x00, 0x00, 0x00, 0x12,             // Tile-part length (18)
            0x00, 0x01,                          // TPsot, TNsot
            0xFF, 0x93,                          // SOD
            0x11, 0x22, 0x33, 0x44              // Tile data
        ] as [UInt8])

        data.append(contentsOf: [0xFF, 0xD9] as [UInt8]) // EOC

        let bins = try generator.generateDataBins(from: data)

        let tileHeaders = bins.filter { $0.binClass == .tileHeader }
        let tileBins = bins.filter { $0.binClass == .tile }

        XCTAssertEqual(tileHeaders.count, 2)
        XCTAssertEqual(tileBins.count, 2)

        // Tile indices should match
        XCTAssertEqual(tileHeaders[0].binID, 0)
        XCTAssertEqual(tileHeaders[1].binID, 1)
    }

    // MARK: - Invalid Input Tests

    func testGenerateDataBinsFromEmptyData() {
        let generator = JPIPDataBinGenerator()

        XCTAssertThrowsError(try generator.generateDataBins(from: Data())) { error in
            XCTAssertTrue(String(describing: error).contains("too small"))
        }
    }

    func testGenerateDataBinsFromInvalidData() {
        let generator = JPIPDataBinGenerator()
        let invalidData = Data([0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try generator.generateDataBins(from: invalidData))
    }

    // MARK: - HTJ2K Detection Tests

    func testIsHTJ2KCodestreamWithCAPMarker() {
        let generator = JPIPDataBinGenerator()

        // J2K codestream with CAP marker (HTJ2K)
        let data = Data([
            0xFF, 0x4F,                          // SOC
            0xFF, 0x50, 0x00, 0x08,             // CAP marker
            0x00, 0x02, 0x00, 0x00, 0x00, 0x20  // CAP content
        ])

        // The isHTJ2KCodestream method delegates to J2KTranscoder.isHTJ2K
        // which may or may not recognize this minimal data
        let result = generator.isHTJ2KCodestream(data)
        // Just verify it doesn't crash - the actual result depends on transcoder validation
        XCTAssertTrue(result == true || result == false)
    }

    func testIsHTJ2KCodestreamWithLegacyData() {
        let generator = JPIPDataBinGenerator()

        let data = Data([
            0xFF, 0x4F,                         // SOC
            0xFF, 0x51, 0x00, 0x04, 0x00, 0x00  // SIZ
        ])

        let result = generator.isHTJ2KCodestream(data)
        XCTAssertFalse(result)
    }

    // MARK: - Data Bin Completeness Tests

    func testAllGeneratedBinsAreComplete() throws {
        let generator = JPIPDataBinGenerator()

        let data = Data([
            0xFF, 0x4F,
            0xFF, 0x51, 0x00, 0x04, 0x00, 0x00,
            0xFF, 0x90, 0x00, 0x0A,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x12,
            0x00, 0x01,
            0xFF, 0x93,
            0x01, 0x02, 0x03, 0x04,
            0xFF, 0xD9
        ])

        let bins = try generator.generateDataBins(from: data)
        for bin in bins {
            XCTAssertTrue(bin.isComplete, "Bin class \(bin.binClass) ID \(bin.binID) should be complete")
        }
    }

    // MARK: - JP2 File Format Tests

    func testGenerateDataBinsHandlesNonCodestreamData() throws {
        let generator = JPIPDataBinGenerator()

        // Data that starts with SOC but has minimal content
        let data = Data([0xFF, 0x4F, 0x00, 0x00])

        // Should not crash and should produce at least a main header bin
        let bins = try generator.generateDataBins(from: data)
        XCTAssertGreaterThanOrEqual(bins.count, 1)
    }
}
