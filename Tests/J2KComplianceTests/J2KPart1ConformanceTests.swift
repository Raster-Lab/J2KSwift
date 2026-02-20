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

    func testCODValidationRejectsInvalidProgressionOrder() {
        // Arrange — build a COD segment with progression order 0x0A (> 4)
        let data = J2KPart1ConformanceTestSuite.standardTestCases()
            .first { $0.identifier == "p1-mrk-004" }!
            .codestream
        let codOffset = findMarker(0xFF52, in: data)

        guard let offset = codOffset else {
            XCTFail("Test codestream p1-mrk-004 must contain a COD marker.")
            return
        }

        // Act
        let result = J2KMarkerSegmentValidator.validateCOD(data, offset: offset)

        // Assert
        XCTAssertFalse(result.isCompliant, "Progression order 10 is out of range and must cause an error.")
        XCTAssertGreaterThan(result.errorCount, 0)
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

// MARK: - Numerical Precision Validator Tests

final class J2KNumericalPrecisionValidatorTests: XCTestCase {

    // MARK: - Lossless Round-Trip

    func testLosslessRoundTripPassesWithIdenticalData() {
        // Arrange
        let samples: [Int32] = (0..<256).map { Int32($0) }

        // Act
        let result = J2KNumericalPrecisionValidator.validateLosslessRoundTrip(
            original: samples,
            reconstructed: samples
        )

        // Assert
        XCTAssertTrue(result.isExact)
        XCTAssertEqual(result.maxAbsoluteError, 0)
        XCTAssertEqual(result.meanSquaredError, 0.0, accuracy: 1e-12)
        XCTAssertTrue(result.passesConformance)
    }

    func testLosslessRoundTripFailsWithDifference() {
        // Arrange
        let original: [Int32]      = [0, 50, 100, 200]
        let reconstructed: [Int32] = [0, 50, 101, 200]  // One sample differs by 1

        // Act
        let result = J2KNumericalPrecisionValidator.validateLosslessRoundTrip(
            original: original,
            reconstructed: reconstructed
        )

        // Assert
        XCTAssertFalse(result.isExact)
        XCTAssertEqual(result.maxAbsoluteError, 1)
        XCTAssertFalse(result.passesConformance)
    }

    func testLosslessRoundTripFailsOnSizeMismatch() {
        // Arrange
        let original: [Int32]      = [1, 2, 3]
        let reconstructed: [Int32] = [1, 2]

        // Act
        let result = J2KNumericalPrecisionValidator.validateLosslessRoundTrip(
            original: original,
            reconstructed: reconstructed
        )

        // Assert
        XCTAssertFalse(result.passesConformance)
        XCTAssertEqual(result.maxAbsoluteError, Int32.max)
    }

    // MARK: - Lossy PSNR

    func testLossyPSNRPassesHighQuality() {
        // Arrange — near-identical arrays; PSNR will be very high
        let original: [Int32]      = Array(repeating: 128, count: 1024)
        var reconstructed = original
        reconstructed[0] = 129  // Single sample off by 1

        // Act
        let result = J2KNumericalPrecisionValidator.validateLossyPSNR(
            original: original,
            reconstructed: reconstructed,
            bitDepth: 8,
            minimumPSNR: 30.0
        )

        // Assert
        XCTAssertTrue(result.passesConformance, "Near-lossless data must easily exceed 30 dB PSNR.")
    }

    func testLossyPSNRFailsLowQuality() {
        // Arrange — large errors → low PSNR
        let original: [Int32]      = Array(repeating: 0, count: 16)
        let reconstructed: [Int32] = Array(repeating: 255, count: 16)

        // Act
        let result = J2KNumericalPrecisionValidator.validateLossyPSNR(
            original: original,
            reconstructed: reconstructed,
            bitDepth: 8,
            minimumPSNR: 50.0
        )

        // Assert
        XCTAssertFalse(result.passesConformance, "Maximum-error data must fail a 50 dB PSNR requirement.")
    }

    func testLossyPSNRPassesIdenticalData() {
        // Arrange
        let samples: [Int32] = [10, 20, 30, 40]

        // Act
        let result = J2KNumericalPrecisionValidator.validateLossyPSNR(
            original: samples,
            reconstructed: samples,
            bitDepth: 8,
            minimumPSNR: 100.0
        )

        // Assert — MSE = 0 → infinite PSNR → always passes
        XCTAssertTrue(result.passesConformance)
        XCTAssertEqual(result.meanSquaredError, 0.0, accuracy: 1e-12)
    }

    // MARK: - Bit-Depth Range

    func testBitDepthRangeValidFor8Bit() {
        // Arrange
        let samples: [Int32] = [0, 1, 127, 254, 255]

        // Act
        let isValid = J2KNumericalPrecisionValidator.validateBitDepthRange(
            samples, bitDepth: 8, isSigned: false
        )

        // Assert
        XCTAssertTrue(isValid, "All values 0–255 are valid for an 8-bit unsigned component.")
    }

    func testBitDepthRangeValidFor12Bit() {
        // Arrange
        let samples: [Int32] = [0, 2048, 4095]

        // Act
        let isValid = J2KNumericalPrecisionValidator.validateBitDepthRange(
            samples, bitDepth: 12, isSigned: false
        )

        // Assert
        XCTAssertTrue(isValid, "Values 0–4095 are valid for a 12-bit unsigned component.")
    }

    func testBitDepthRangeValidFor16Bit() {
        // Arrange
        let samples: [Int32] = [0, 32767, 65535]

        // Act
        let isValid = J2KNumericalPrecisionValidator.validateBitDepthRange(
            samples, bitDepth: 16, isSigned: false
        )

        // Assert
        XCTAssertTrue(isValid)
    }

    func testBitDepthRangeInvalidOutOfRange() {
        // Arrange — 256 is out of range for 8-bit unsigned
        let samples: [Int32] = [0, 128, 256]

        // Act
        let isValid = J2KNumericalPrecisionValidator.validateBitDepthRange(
            samples, bitDepth: 8, isSigned: false
        )

        // Assert
        XCTAssertFalse(isValid, "Value 256 must be out of range for an 8-bit unsigned component.")
    }

    func testBitDepthRangeValidSignedSamples() {
        // Arrange — signed 8-bit: range is -128…127
        let samples: [Int32] = [-128, 0, 127]

        // Act
        let isValid = J2KNumericalPrecisionValidator.validateBitDepthRange(
            samples, bitDepth: 8, isSigned: true
        )

        // Assert
        XCTAssertTrue(isValid)
    }

    func testBitDepthRangeInvalidSignedOutOfRange() {
        // Arrange — 128 is out of range for signed 8-bit
        let samples: [Int32] = [-128, 0, 128]

        // Act
        let isValid = J2KNumericalPrecisionValidator.validateBitDepthRange(
            samples, bitDepth: 8, isSigned: true
        )

        // Assert
        XCTAssertFalse(isValid)
    }

    func testPrecisionResultFields() {
        // Arrange
        let original: [Int32]      = [100, 200, 150]
        let reconstructed: [Int32] = [100, 202, 150]  // Error of 2 on second sample

        // Act
        let result = J2KNumericalPrecisionValidator.validateLosslessRoundTrip(
            original: original,
            reconstructed: reconstructed
        )

        // Assert
        XCTAssertFalse(result.isExact)
        XCTAssertEqual(result.maxAbsoluteError, 2)
        XCTAssertGreaterThan(result.meanSquaredError, 0.0)
        XCTAssertFalse(result.passesConformance)
    }
}

// MARK: - Part 1 Conformance Test Suite Tests

final class J2KPart1ConformanceTestSuiteTests: XCTestCase {

    // MARK: - Test Case Collection

    func testStandardTestCasesNonEmpty() {
        // Act
        let cases = J2KPart1ConformanceTestSuite.standardTestCases()

        // Assert
        XCTAssertGreaterThanOrEqual(cases.count, 20, "Standard test suite must contain at least 20 cases.")
    }

    func testStandardTestCasesHaveUniqueIdentifiers() {
        // Arrange
        let cases = J2KPart1ConformanceTestSuite.standardTestCases()

        // Act
        let identifiers = cases.map(\.identifier)
        let uniqueIdentifiers = Set(identifiers)

        // Assert
        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count, "Every test case must have a unique identifier.")
    }

    func testStandardTestCasesCoversAllCategories() {
        // Arrange
        let cases = J2KPart1ConformanceTestSuite.standardTestCases()
        let categoriesPresent = Set(cases.map(\.category))

        // Act & Assert — every defined category must appear at least once
        for category in J2KPart1ConformanceTestSuite.TestCategory.allCases {
            XCTAssertTrue(
                categoriesPresent.contains(category),
                "Category '\(category.rawValue)' must be represented in the standard test suite."
            )
        }
    }

    func testStandardTestCasesHaveNonEmptyDescriptions() {
        // Arrange
        let cases = J2KPart1ConformanceTestSuite.standardTestCases()

        // Assert
        for testCase in cases {
            XCTAssertFalse(
                testCase.description.isEmpty,
                "Test case '\(testCase.identifier)' must have a non-empty description."
            )
        }
    }

    // MARK: - Valid / Invalid Codestream Integrity

    func testValidTestCasesHaveValidCodestreams() {
        // Arrange
        let validCases = J2KPart1ConformanceTestSuite.standardTestCases()
            .filter { $0.expectedValid }

        for testCase in validCases {
            // Act
            let result = J2KMarkerSegmentValidator.validateCodestream(testCase.codestream)

            // Assert
            XCTAssertTrue(
                result.isCompliant,
                "Test case '\(testCase.identifier)' is marked expectedValid=true "
                    + "but its codestream fails marker validation."
            )
        }
    }

    func testInvalidTestCasesHaveInvalidCodestreams() {
        // Arrange
        let invalidCases = J2KPart1ConformanceTestSuite.standardTestCases()
            .filter { !$0.expectedValid }

        for testCase in invalidCases {
            // Act
            let result = J2KMarkerSegmentValidator.validateCodestream(testCase.codestream)

            // Assert
            XCTAssertFalse(
                result.isCompliant,
                "Test case '\(testCase.identifier)' is marked expectedValid=false "
                    + "but its codestream passes marker validation."
            )
        }
    }

    // MARK: - Report Generation

    func testConformanceReportGeneration() {
        // Arrange
        let cases = J2KPart1ConformanceTestSuite.standardTestCases()
        let results: [(J2KPart1ConformanceTestSuite.ConformanceTestCase, Bool)] = cases.map { ($0, true) }

        // Act
        let report = J2KPart1ConformanceTestSuite.generateReport(results: results)

        // Assert
        XCTAssertFalse(report.isEmpty, "Generated report must not be empty.")
        XCTAssertTrue(report.contains("# JPEG 2000 Part 1 Conformance Report"), "Report must have a heading.")
        XCTAssertTrue(report.contains("Pass rate"), "Report must include a pass-rate metric.")
    }

    func testConformanceReportShowsFailures() {
        // Arrange
        let cases = J2KPart1ConformanceTestSuite.standardTestCases().prefix(2)
        let results: [(J2KPart1ConformanceTestSuite.ConformanceTestCase, Bool)] = [
            (cases[cases.startIndex], true),
            (cases[cases.index(after: cases.startIndex)], false)
        ]

        // Act
        let report = J2KPart1ConformanceTestSuite.generateReport(results: results)

        // Assert
        XCTAssertTrue(report.contains("❌"), "Report must mark failed cases with ❌.")
        XCTAssertTrue(report.contains("✅"), "Report must mark passed cases with ✅.")
    }

    func testConformanceReportHandlesEmptyResults() {
        // Arrange
        let results: [(J2KPart1ConformanceTestSuite.ConformanceTestCase, Bool)] = []

        // Act
        let report = J2KPart1ConformanceTestSuite.generateReport(results: results)

        // Assert
        XCTAssertFalse(report.isEmpty, "Even an empty result set must produce a valid report.")
        XCTAssertTrue(report.contains("N/A"), "An empty result set must report N/A for pass rate.")
    }

    // MARK: - Enumeration Cases

    func testDecoderClassCases() {
        // Assert
        XCTAssertEqual(J2KDecoderConformanceClass.allCases.count, 2)
        XCTAssertTrue(J2KDecoderConformanceClass.allCases.contains(.class0))
        XCTAssertTrue(J2KDecoderConformanceClass.allCases.contains(.class1))
    }

    func testDecoderClassRawValues() {
        // Assert
        XCTAssertEqual(J2KDecoderConformanceClass.class0.rawValue, "Class-0")
        XCTAssertEqual(J2KDecoderConformanceClass.class1.rawValue, "Class-1")
    }

    func testTestCategoryAllCases() {
        // Assert
        let categories = J2KPart1ConformanceTestSuite.TestCategory.allCases
        XCTAssertEqual(categories.count, 5)
        XCTAssertTrue(categories.contains(.decoderClass0))
        XCTAssertTrue(categories.contains(.decoderClass1))
        XCTAssertTrue(categories.contains(.markerValidation))
        XCTAssertTrue(categories.contains(.numericalPrecision))
        XCTAssertTrue(categories.contains(.errorResilience))
    }

    func testTestCategoryRawValues() {
        // Assert
        XCTAssertEqual(J2KPart1ConformanceTestSuite.TestCategory.decoderClass0.rawValue, "decoderClass0")
        XCTAssertEqual(J2KPart1ConformanceTestSuite.TestCategory.decoderClass1.rawValue, "decoderClass1")
        XCTAssertEqual(J2KPart1ConformanceTestSuite.TestCategory.markerValidation.rawValue, "markerValidation")
        XCTAssertEqual(J2KPart1ConformanceTestSuite.TestCategory.numericalPrecision.rawValue, "numericalPrecision")
        XCTAssertEqual(J2KPart1ConformanceTestSuite.TestCategory.errorResilience.rawValue, "errorResilience")
    }

    // MARK: - Test Case Field Validation

    func testConformanceTestCaseFieldsAccessible() {
        // Arrange
        let testCase = J2KPart1ConformanceTestSuite.ConformanceTestCase(
            identifier: "test-001",
            category: .decoderClass0,
            description: "Unit test case.",
            codestream: Data([0xFF, 0x4F, 0xFF, 0xD9]),
            expectedValid: true,
            expectedDecoderClass: .class0
        )

        // Assert
        XCTAssertEqual(testCase.identifier, "test-001")
        XCTAssertEqual(testCase.category, .decoderClass0)
        XCTAssertEqual(testCase.description, "Unit test case.")
        XCTAssertEqual(testCase.codestream, Data([0xFF, 0x4F, 0xFF, 0xD9]))
        XCTAssertTrue(testCase.expectedValid)
        XCTAssertEqual(testCase.expectedDecoderClass, .class0)
    }

    func testConformanceTestCaseOptionalDecoderClass() {
        // Arrange
        let testCase = J2KPart1ConformanceTestSuite.ConformanceTestCase(
            identifier: "test-002",
            category: .errorResilience,
            description: "Invalid codestream with no expected decoder class.",
            codestream: Data(),
            expectedValid: false
        )

        // Assert
        XCTAssertNil(testCase.expectedDecoderClass)
    }
}
