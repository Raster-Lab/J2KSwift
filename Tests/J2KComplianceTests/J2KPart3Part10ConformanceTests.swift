//
// J2KPart3Part10ConformanceTests.swift
// J2KSwift
//
/// # J2KPart3Part10ConformanceTests
///
/// Week 261–262 conformance milestone for JPEG 2000 Part 3 (Motion JPEG 2000)
/// and Part 10 (JP3D Volumetric).
///
/// Covers MJ2 file-structure validation, frame-rate and temporal-metadata
/// validation, JP3D volume-extent and wavelet-level validation, 3D tiling,
/// cross-part interaction checks, and the standard Part 3/Part 10 test suite.

import XCTest
@testable import J2KCore
@testable import J2K3D

// MARK: - MJ2 Conformance Validator Tests

final class J2KMJ2ConformanceValidatorTests: XCTestCase {

    // MARK: - MJ2 Signature Validation

    func testMJ2SignatureValidation() {
        // Arrange — 12-byte JP2/MJ2 signature followed by filler
        let signature: [UInt8] = [
            0x00, 0x00, 0x00, 0x0C,
            0x6A, 0x50, 0x20, 0x20,
            0x0D, 0x0A, 0x87, 0x0A
        ]
        let data = Data(signature + [UInt8](repeating: 0, count: 20))

        // Act
        let result = J2KMJ2ConformanceValidator.validateMJ2Signature(data)

        // Assert
        XCTAssertTrue(result.isValid, "A correct MJ2 signature must pass validation.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testMJ2SignatureValidationRejectsShortData() {
        // Arrange
        let data = Data([0x00, 0x00, 0x00])

        // Act
        let result = J2KMJ2ConformanceValidator.validateMJ2Signature(data)

        // Assert
        XCTAssertFalse(result.isValid, "Data shorter than 12 bytes must fail MJ2 signature validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testMJ2FileTypeValidation() {
        // Arrange — JP2 signature + ftyp box with mjp2 brand
        let signature: [UInt8] = [
            0x00, 0x00, 0x00, 0x0C,
            0x6A, 0x50, 0x20, 0x20,
            0x0D, 0x0A, 0x87, 0x0A
        ]
        let ftypBox: [UInt8] = [
            0x00, 0x00, 0x00, 0x14,   // LBox = 20
            0x66, 0x74, 0x79, 0x70,   // TBox = "ftyp"
            0x6D, 0x6A, 0x70, 0x32,   // brand = "mjp2"
            0x00, 0x00, 0x00, 0x00,   // MinV
            0x6D, 0x6A, 0x70, 0x32    // compat = "mjp2"
        ]
        let data = Data(signature + ftypBox)

        // Act
        let result = J2KMJ2ConformanceValidator.validateMJ2FileType(data)

        // Assert
        XCTAssertTrue(result.isValid, "An ftyp box declaring the mjp2 brand must be valid.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testFrameRateValidationAcceptsNormal() {
        // Arrange / Act — 30 fps
        let result = J2KMJ2ConformanceValidator.validateFrameRate(numerator: 30, denominator: 1)

        // Assert
        XCTAssertTrue(result.isValid, "30/1 fps is well within the valid range.")
    }

    func testFrameRateValidationRejectsZeroDenominator() {
        // Arrange / Act
        let result = J2KMJ2ConformanceValidator.validateFrameRate(numerator: 30, denominator: 0)

        // Assert
        XCTAssertFalse(result.isValid, "Zero denominator must be rejected.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testFrameRateValidationRejectsZeroNumerator() {
        // Arrange / Act
        let result = J2KMJ2ConformanceValidator.validateFrameRate(numerator: 0, denominator: 1)

        // Assert
        XCTAssertFalse(result.isValid, "Zero numerator must be rejected.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testTemporalMetadataValidationConsistent() {
        // Arrange — 300 frames at 30 fps over 10 seconds (consistent within 1 %)
        // Act
        let result = J2KMJ2ConformanceValidator.validateTemporalMetadata(
            frameCount: 300,
            duration: 10.0,
            frameRate: 30.0
        )

        // Assert
        XCTAssertTrue(result.isValid, "Consistent temporal metadata must be valid.")
        XCTAssertEqual(result.frameCount, 300)
    }

    func testMJ2StructureValidationAcceptsValid() {
        // Arrange / Act
        let result = J2KMJ2ConformanceValidator.validateMJ2Structure(
            frameCount: 24,
            width: 1920,
            height: 1080,
            bitDepth: 8
        )

        // Assert
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.frameCount, 24)
        XCTAssertTrue(result.errors.isEmpty)
    }
}

// MARK: - JP3D Conformance Validator Tests

final class J2KJP3DConformanceValidatorTests: XCTestCase {

    // MARK: - Volume Extents

    func testVolumeExtentsValidationAcceptsMinimum() {
        // Arrange / Act
        let result = J2KJP3DConformanceValidator.validateVolumeExtents(width: 1, height: 1, depth: 1)

        // Assert
        XCTAssertTrue(result.isValid, "Minimum 1×1×1 volume must be valid.")
        XCTAssertEqual(result.voxelCount, 1)
    }

    func testVolumeExtentsValidationRejectsZeroWidth() {
        // Arrange / Act
        let result = J2KJP3DConformanceValidator.validateVolumeExtents(width: 0, height: 4, depth: 4)

        // Assert
        XCTAssertFalse(result.isValid, "Width of 0 must be rejected.")
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertEqual(result.voxelCount, 0)
    }

    func testVolumeExtentsValidationWarnsLargeDimension() {
        // Arrange / Act
        let result = J2KJP3DConformanceValidator.validateVolumeExtents(width: 5000, height: 4, depth: 4)

        // Assert
        XCTAssertTrue(result.isValid, "Large dimension produces a warning, not an error.")
        XCTAssertFalse(result.warnings.isEmpty, "Width > 4096 must trigger a warning.")
    }

    // MARK: - 3D Wavelet Levels

    func test3DWaveletLevelsValidationAcceptsValid() {
        // Arrange / Act
        let result = J2KJP3DConformanceValidator.validate3DWaveletLevels(xyLevels: 5, zLevels: 2, depth: 8)

        // Assert
        XCTAssertTrue(result.isValid)
    }

    func test3DWaveletLevelsValidationRejectsExcessiveLevels() {
        // Arrange — depth=4 allows at most floor(log2(4))+1 = 3 Z levels
        // Act
        let result = J2KJP3DConformanceValidator.validate3DWaveletLevels(xyLevels: 5, zLevels: 10, depth: 4)

        // Assert
        XCTAssertFalse(result.isValid, "Z levels exceeding the maximum for the given depth must be rejected.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - 3D Tiling

    func test3DTilingValidationAcceptsValid() {
        // Arrange / Act
        let result = J2KJP3DConformanceValidator.validate3DTilingConfiguration(
            tileWidth: 32, tileHeight: 32, tileDepth: 8,
            volumeWidth: 128, volumeHeight: 128, volumeDepth: 16
        )

        // Assert
        XCTAssertTrue(result.isValid)
    }

    func test3DTilingValidationRejectsTileExceedsVolume() {
        // Arrange / Act — tile depth (20) exceeds volume depth (16)
        let result = J2KJP3DConformanceValidator.validate3DTilingConfiguration(
            tileWidth: 32, tileHeight: 32, tileDepth: 20,
            volumeWidth: 128, volumeHeight: 128, volumeDepth: 16
        )

        // Assert
        XCTAssertFalse(result.isValid, "Tile depth exceeding volume depth must be rejected.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Volumetric Codestream Structure

    func testVolumetricCodestreamValidation() {
        // Arrange — minimal SOC … EOC codestream
        var data = Data([0xFF, 0x4F])                     // SOC
        data.append(contentsOf: [0xFF, 0x90])              // SOT (filler)
        data.append(contentsOf: [0xFF, 0xD9])              // EOC

        // Act
        let result = J2KJP3DConformanceValidator.validateVolumetricCodestreamStructure(data)

        // Assert
        XCTAssertTrue(result.isValid, "A codestream with SOC at start and EOC at end must be valid.")
        XCTAssertTrue(result.errors.isEmpty)
    }
}

// MARK: - Cross-Part Conformance Validator Tests

final class J2KCrossPartConformanceValidatorTests: XCTestCase {

    // MARK: - Part 3 ↔ Part 1

    func testPart3Part1InteractionValid() {
        // Act
        let result = J2KCrossPartConformanceValidator.validatePart3Part1Interaction(
            mj2FrameCount: 10,
            part1Valid: true
        )

        // Assert
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testPart3Part1InteractionFailsIfPart1Invalid() {
        // Act
        let result = J2KCrossPartConformanceValidator.validatePart3Part1Interaction(
            mj2FrameCount: 10,
            part1Valid: false
        )

        // Assert
        XCTAssertFalse(result.isValid, "Invalid Part 1 codestream must fail cross-part validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testPart3Part1InteractionFailsIfNoFrames() {
        // Act
        let result = J2KCrossPartConformanceValidator.validatePart3Part1Interaction(
            mj2FrameCount: 0,
            part1Valid: true
        )

        // Assert
        XCTAssertFalse(result.isValid, "Zero frame count must fail cross-part validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Part 10 ↔ Part 1

    func testPart10Part1InteractionValid() {
        // Act
        let result = J2KCrossPartConformanceValidator.validatePart10Part1Interaction(
            jp3dVolumeValid: true,
            part1Valid: true
        )

        // Assert
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testPart10Part1InteractionFailsIfPart1Invalid() {
        // Act
        let result = J2KCrossPartConformanceValidator.validatePart10Part1Interaction(
            jp3dVolumeValid: true,
            part1Valid: false
        )

        // Assert
        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testCrossPartResultFields() {
        // Act
        let result = J2KCrossPartConformanceValidator.validatePart3Part1Interaction(
            mj2FrameCount: 5,
            part1Valid: true
        )

        // Assert
        XCTAssertFalse(result.parts.isEmpty, "Cross-part result must declare the involved parts.")
        XCTAssertTrue(result.parts.contains("Part 1 (Core)"))
        XCTAssertTrue(result.parts.contains("Part 3 (MJ2)"))
    }

    func testCrossPartResultHasParts() {
        // Act
        let result = J2KCrossPartConformanceValidator.validatePart10Part1Interaction(
            jp3dVolumeValid: true,
            part1Valid: true
        )

        // Assert
        XCTAssertEqual(result.parts.count, 2)
        XCTAssertTrue(result.parts.contains("Part 10 (JP3D)"))
    }
}

// MARK: - Part 3 / Part 10 Conformance Test Suite Tests

final class J2KPart3Part10ConformanceTestSuiteTests: XCTestCase {

    // MARK: - Standard Test Cases

    func testStandardTestCasesNonEmpty() {
        // Act
        let cases = J2KPart3Part10ConformanceTestSuite.standardTestCases()

        // Assert
        XCTAssertFalse(cases.isEmpty, "The standard test case list must not be empty.")
    }

    func testStandardTestCasesAtLeast20() {
        // Act
        let cases = J2KPart3Part10ConformanceTestSuite.standardTestCases()

        // Assert
        XCTAssertGreaterThanOrEqual(cases.count, 20, "At least 20 standard test cases must be provided.")
    }

    func testAllCategoriesCovered() {
        // Arrange
        let cases = J2KPart3Part10ConformanceTestSuite.standardTestCases()
        let coveredCategories = Set(cases.map(\.category))

        // Assert
        for category in J2KPart3Part10ConformanceTestSuite.TestCategory.allCases {
            XCTAssertTrue(coveredCategories.contains(category), "Category '\(category.rawValue)' must be represented.")
        }
    }

    func testTestCasesHaveUniqueIdentifiers() {
        // Arrange
        let cases = J2KPart3Part10ConformanceTestSuite.standardTestCases()
        let identifiers = cases.map(\.identifier)
        let uniqueIdentifiers = Set(identifiers)

        // Assert
        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count, "All test case identifiers must be unique.")
    }

    func testTestCategoryAllCases() {
        // Assert
        XCTAssertFalse(J2KPart3Part10ConformanceTestSuite.TestCategory.allCases.isEmpty)
        XCTAssertGreaterThanOrEqual(J2KPart3Part10ConformanceTestSuite.TestCategory.allCases.count, 7)
    }

    func testReportGenerationNonEmpty() {
        // Arrange
        let cases = J2KPart3Part10ConformanceTestSuite.standardTestCases()
        let results = cases.map { ($0, $0.expectedValid) }

        // Act
        let report = J2KPart3Part10ConformanceTestSuite.generateReport(results: results)

        // Assert
        XCTAssertFalse(report.isEmpty, "Generated report must not be empty.")
        XCTAssertTrue(report.contains("Part 3") || report.contains("Part 10"))
    }

    func testValidAndInvalidCasesPresent() {
        // Arrange
        let cases = J2KPart3Part10ConformanceTestSuite.standardTestCases()

        // Assert
        XCTAssertTrue(cases.contains(where: { $0.expectedValid }), "At least one expected-valid test case is required.")
        XCTAssertTrue(cases.contains(where: { !$0.expectedValid }), "At least one expected-invalid test case is required.")
    }

    func testMJ2ValidationResult() {
        // Act — validate a well-formed MJ2 structure
        let result = J2KMJ2ConformanceValidator.validateMJ2Structure(
            frameCount: 1,
            width: 640,
            height: 480,
            bitDepth: 8
        )

        // Assert
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.frameCount, 1)
        XCTAssertTrue(result.warnings.isEmpty)
    }
}
