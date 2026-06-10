//
// J2KPart1ConformanceTests.swift
// J2KSwift
//
/// # J2KPart1ConformanceTests
///
/// Week 256–258 conformance hardening milestone for JPEG 2000 Part 1 (ISO/IEC 15444-1).
///
/// Covers marker-segment validation, codestream syntax ordering, numerical precision
/// verification, and the standard Part 1 conformance test suite.

import XCTest
@testable import J2KCore

// MARK: - Marker Segment Validator Tests

final class J2KMarkerSegmentValidatorTests: XCTestCase {

    // MARK: - SOC Validation

    func testSOCValidationAcceptsValidCodestream() {
        // Arrange
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KMarkerSegmentValidator.validateSOC(data)

        // Assert
        XCTAssertTrue(result.isCompliant, "A well-formed codestream starting with 0xFF4F must be SOC-compliant.")
        XCTAssertEqual(result.errorCount, 0)
    }

    func testSOCValidationRejectsInvalidCodestream() {
        // Arrange — stream begins with 0x0000 instead of 0xFF4F
        let data = Data([0x00, 0x00, 0xFF, 0x51, 0xFF, 0xD9])

        // Act
        let result = J2KMarkerSegmentValidator.validateSOC(data)

        // Assert
        XCTAssertFalse(result.isCompliant, "A codestream without SOC at byte 0 must not be compliant.")
        XCTAssertGreaterThan(result.errorCount, 0)
    }

    func testSOCValidationRejectsTooShortData() {
        // Arrange
        let data = Data([0xFF])  // Only one byte — cannot hold a two-byte marker

        // Act
        let result = J2KMarkerSegmentValidator.validateSOC(data)

        // Assert
        XCTAssertFalse(result.isCompliant)
        XCTAssertGreaterThan(result.errorCount, 0)
    }

    // MARK: - SIZ Validation

    func testSIZValidationAcceptsValidMarker() {
        // Arrange — place SIZ at offset 2 (immediately after SOC)
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 16, height: 16, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KMarkerSegmentValidator.validateSIZ(data, offset: 2)

        // Assert
        XCTAssertTrue(result.isCompliant, "The SIZ segment in a synthetic codestream must be valid.")
        XCTAssertEqual(result.errorCount, 0)
    }

    func testSIZValidationRejectsTooShort() {
        // Arrange — build a SIZ segment whose Lsiz is below the 41-byte minimum
        var data = Data()
        data.append(contentsOf: [0xFF, 0x4F])  // SOC
        data.append(contentsOf: [0xFF, 0x51])  // SIZ marker
        data.append(contentsOf: [0x00, 0x05])  // Lsiz = 5 (far below minimum of 41)
        data.append(contentsOf: [0x00, 0x00, 0x00])  // Padding to fill declared length

        // Act
        let result = J2KMarkerSegmentValidator.validateSIZ(data, offset: 2)

        // Assert
        XCTAssertFalse(result.isCompliant)
        XCTAssertGreaterThan(result.errorCount, 0)
    }

    func testSIZValidationRejectsWrongMarkerCode() {
        // Arrange — marker code at offset is not 0xFF51
        var data = Data()
        data.append(contentsOf: [0xFF, 0x4F])  // SOC
        data.append(contentsOf: [0xFF, 0x52])  // COD marker instead of SIZ

        // Act
        let result = J2KMarkerSegmentValidator.validateSIZ(data, offset: 2)

        // Assert
        XCTAssertFalse(result.isCompliant)
    }

    // MARK: - COD Validation

    func testCODValidationAcceptsValidMarker() {
        // Arrange — locate COD within the synthetic codestream
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )
        let codOffset = findMarker(0xFF52, in: data)

        // Act
        guard let offset = codOffset else {
            XCTFail("Synthetic codestream must contain a COD marker (0xFF52).")
            return
        }
        let result = J2KMarkerSegmentValidator.validateCOD(data, offset: offset)

        // Assert
        XCTAssertTrue(result.isCompliant, "COD segment in synthetic codestream must be valid.")
        XCTAssertEqual(result.errorCount, 0)
    }

    // MARK: - EOC Validation

    func testEOCValidationAcceptsValidCodestream() {
        // Arrange
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KMarkerSegmentValidator.validateEOC(data)

        // Assert
        XCTAssertTrue(result.isCompliant, "EOC must be present at the end of the synthetic codestream.")
        XCTAssertEqual(result.errorCount, 0)
    }

    func testEOCValidationRejectsMissingEOC() {
        // Arrange — strip the last two bytes (EOC)
        var data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )
        data = data.dropLast(2)

        // Act
        let result = J2KMarkerSegmentValidator.validateEOC(data)

        // Assert
        XCTAssertFalse(result.isCompliant)
        XCTAssertGreaterThan(result.errorCount, 0)
    }

    // MARK: - Full Codestream Validation

    func testFullCodestreamValidation() {
        // Arrange
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KMarkerSegmentValidator.validateCodestream(data)

        // Assert
        XCTAssertTrue(result.isCompliant, "A well-formed synthetic codestream must pass full validation.")
        XCTAssertEqual(result.errorCount, 0)
    }

    func testFullCodestreamValidationRejectsMissingSOC() {
        // Arrange
        let data = Data([0x00, 0x00, 0xFF, 0x51, 0x00, 0x29]) + Data(repeating: 0, count: 37) + Data([0xFF, 0xD9])

        // Act
        let result = J2KMarkerSegmentValidator.validateCodestream(data)

        // Assert
        XCTAssertFalse(result.isCompliant)
    }

    // MARK: - Private Helpers

    /// Finds the byte offset of the first occurrence of a two-byte marker in `data`.
    private func findMarker(_ marker: UInt16, in data: Data) -> Int? {
        let hi = UInt8((marker >> 8) & 0xFF)
        let lo = UInt8(marker & 0xFF)
        for i in 0..<(data.count - 1) {
            if data[i] == hi && data[i + 1] == lo { return i }
        }
        return nil
    }
}

// MARK: - Codestream Syntax Validator Tests

final class J2KCodestreamSyntaxValidatorTests: XCTestCase {

    // MARK: - Marker Ordering

    func testMarkerOrderingValidSOCFirst() {
        // Arrange
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KCodestreamSyntaxValidator.validateMarkerOrdering(data)

        // Assert
        XCTAssertTrue(result.isValid, "Synthetic codestream must pass marker ordering validation.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testMarkerOrderingValidSIZAfterSOC() {
        // Arrange
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KCodestreamSyntaxValidator.validateMarkerOrdering(data)

        // Assert — no errors about SIZ placement
        let sizErrors = result.errors.filter { $0.contains("SIZ") }
        XCTAssertTrue(sizErrors.isEmpty, "SIZ must be accepted immediately after SOC.")
    }

    func testSyntaxValidatorRejectsMissingSOC() {
        // Arrange — stream starts without SOC
        var data = Data()
        data.append(contentsOf: [0xFF, 0x51])  // SIZ without SOC
        data.append(contentsOf: Data(repeating: 0, count: 39))
        data.append(contentsOf: [0xFF, 0xD9])

        // Act
        let result = J2KCodestreamSyntaxValidator.validateMarkerOrdering(data)

        // Assert
        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testSyntaxValidatorRejectsMissingEOC() {
        // Arrange — remove EOC from the end
        var data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )
        data = data.dropLast(2)

        // Act
        let result = J2KCodestreamSyntaxValidator.validateMarkerOrdering(data)

        // Assert
        XCTAssertFalse(result.isValid)
        let eocErrors = result.errors.filter { $0.contains("EOC") }
        XCTAssertFalse(eocErrors.isEmpty)
    }

    func testSyntaxValidatorAcceptsMinimalCodestream() {
        // Arrange
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 4, height: 4, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KCodestreamSyntaxValidator.validateMarkerOrdering(data)

        // Assert
        XCTAssertTrue(result.isValid)
        XCTAssertGreaterThan(result.markerCount, 0, "At least one marker must be counted.")
    }

    // MARK: - Progression Order

    func testProgressionOrderValidRange() {
        // All values 0–4 are valid
        for order: UInt8 in 0...4 {
            XCTAssertTrue(
                J2KCodestreamSyntaxValidator.validateProgressionOrder(order),
                "Progression order \(order) must be valid."
            )
        }
    }

    func testProgressionOrderInvalidAboveFour() {
        // Values 5–255 are invalid
        for order: UInt8 in [5, 10, 100, 255] {
            XCTAssertFalse(
                J2KCodestreamSyntaxValidator.validateProgressionOrder(order),
                "Progression order \(order) must be invalid."
            )
        }
    }

    // MARK: - Tile-Part Structure

    func testTilePartStructureValidSOT() {
        // Arrange — synthetic codestream has a valid SOT+SOD tile part
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KCodestreamSyntaxValidator.validateTilePartStructure(data)

        // Assert
        XCTAssertTrue(result.isValid, "Synthetic codestream must have a valid tile-part structure.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testTilePartStructureCountsMarkers() {
        // Arrange
        let data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KCodestreamSyntaxValidator.validateTilePartStructure(data)

        // Assert
        XCTAssertGreaterThanOrEqual(result.markerCount, 1, "At least one marker must be encountered.")
    }
}
