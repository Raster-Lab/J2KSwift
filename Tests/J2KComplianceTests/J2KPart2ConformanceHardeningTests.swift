//
// J2KPart2ConformanceHardeningTests.swift
// J2KSwift
//
/// # J2KPart2ConformanceHardeningTests
///
/// Week 259–260 conformance hardening milestone for JPEG 2000 Part 2 (ISO/IEC 15444-2).
///
/// Covers JPX file-format validation, per-extension conformance validators
/// (MCT, NLT, TCQ, Extended ROI, Arbitrary Wavelets, DC-Offset), and the
/// standard Part 2 conformance test suite.

import XCTest
@testable import J2KCore

// MARK: - JPX File-Format Validator Tests

final class J2KJPXFileFormatValidatorTests: XCTestCase {

    // MARK: - JP2 Signature Validation

    func testJP2SignatureValidation() {
        // Arrange — build the exact 12-byte JP2 signature
        let signature: [UInt8] = [
            0x00, 0x00, 0x00, 0x0C,
            0x6A, 0x50, 0x20, 0x20,
            0x0D, 0x0A, 0x87, 0x0A
        ]
        let data = Data(signature + [UInt8](repeating: 0, count: 20))

        // Act
        let result = J2KJPXFileFormatValidator.validateJP2Signature(data)

        // Assert
        XCTAssertTrue(result.isValid, "A correct JP2 signature must pass validation.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testJP2SignatureValidationRejectsShortData() {
        // Arrange — only 4 bytes
        let data = Data([0x00, 0x00, 0x00, 0x0C])

        // Act
        let result = J2KJPXFileFormatValidator.validateJP2Signature(data)

        // Assert
        XCTAssertFalse(result.isValid, "Data shorter than 12 bytes must fail JP2 signature validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testJP2SignatureValidationRejectsWrongSignature() {
        // Arrange — correct length but wrong content
        let wrong: [UInt8] = [UInt8](repeating: 0xFF, count: 12) + [UInt8](repeating: 0, count: 8)
        let data = Data(wrong)

        // Act
        let result = J2KJPXFileFormatValidator.validateJP2Signature(data)

        // Assert
        XCTAssertFalse(result.isValid, "Incorrect signature bytes must fail validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testJP2FileTypeBoxValidation() {
        // Arrange — signature + ftyp box header (length 0x00000010, type "ftyp")
        let signature: [UInt8] = [
            0x00, 0x00, 0x00, 0x0C,
            0x6A, 0x50, 0x20, 0x20,
            0x0D, 0x0A, 0x87, 0x0A
        ]
        let ftypBox: [UInt8] = [
            0x00, 0x00, 0x00, 0x10,   // LBox = 16
            0x66, 0x74, 0x79, 0x70,   // TBox = "ftyp"
            0x6A, 0x70, 0x32, 0x20,   // brand = "jp2 "
            0x00, 0x00, 0x00, 0x00    // MinV
        ]
        let data = Data(signature + ftypBox)

        // Act
        let result = J2KJPXFileFormatValidator.validateJP2FileTypeBox(data)

        // Assert
        XCTAssertTrue(result.isValid, "A well-formed ftyp box at offset 12 must pass validation.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testJPXCapabilitiesNoExtensionsValid() {
        // Arrange
        let extensions: [J2KPart2Extension] = []

        // Act
        let result = J2KJPXFileFormatValidator.validateJPXCapabilities(extensions)

        // Assert
        XCTAssertTrue(result.isValid, "Empty extension list must not produce errors.")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testJPXCapabilitiesExtensionsGenerateWarning() {
        // Arrange
        let extensions: [J2KPart2Extension] = [.multiComponentTransform]

        // Act
        let result = J2KJPXFileFormatValidator.validateJPXCapabilities(extensions)

        // Assert
        XCTAssertTrue(result.isValid, "Extensions should produce a warning, not an error.")
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty, "A Part 2 extension must generate a JPX compatibility warning.")
    }

    func testJP2SignatureValidationEdgeCaseAllZeros() {
        // Arrange
        let data = Data(repeating: 0x00, count: 32)

        // Act
        let result = J2KJPXFileFormatValidator.validateJP2Signature(data)

        // Assert
        XCTAssertFalse(result.isValid, "All-zero data must fail JP2 signature validation.")
    }

    func testJPXCapabilitiesMultipleExtensions() {
        // Arrange
        let extensions: [J2KPart2Extension] = [.multiComponentTransform, .nonLinearTransform, .trellisCodedQuantisation]

        // Act
        let result = J2KJPXFileFormatValidator.validateJPXCapabilities(extensions)

        // Assert
        XCTAssertTrue(result.isValid)
        XCTAssertFalse(result.warnings.isEmpty, "Multiple extensions must still produce a JPX warning.")
        XCTAssertTrue(result.warnings.first?.contains("MCT") == true || result.warnings.first?.contains("NLT") == true)
    }
}

// MARK: - Part 2 Conformance Validator Tests

final class J2KPart2ConformanceValidatorTests: XCTestCase {

    // MARK: - MCT

    func testMCTValidationAcceptsValidConfig() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateMCT(componentCount: 3, transformCount: 2)

        // Assert
        XCTAssertTrue(result.isCompliant, "3 components and 2 stages is a valid MCT configuration.")
        XCTAssertEqual(result.extension, .multiComponentTransform)
        XCTAssertTrue(result.isSupported)
    }

    func testMCTValidationRejectsSingleComponent() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateMCT(componentCount: 1, transformCount: 1)

        // Assert
        XCTAssertFalse(result.isCompliant, "MCT requires at least 2 components.")
    }

    func testNLTValidationAcceptsValidTypes() {
        // Arrange / Act / Assert
        for type_ in [UInt8(0), UInt8(1), UInt8(2)] {
            let result = J2KPart2ConformanceValidator.validateNLT(type: type_)
            XCTAssertTrue(result.isCompliant, "NLT type \(type_) must be valid.")
        }
    }

    func testNLTValidationRejectsInvalidType() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateNLT(type: 99)

        // Assert
        XCTAssertFalse(result.isCompliant, "NLT type 99 is not defined and must be rejected.")
        XCTAssertEqual(result.extension, .nonLinearTransform)
    }

    func testTCQValidationAcceptsValidConfig() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateTCQ(guardbits: 2, stepCount: 8)

        // Assert
        XCTAssertTrue(result.isCompliant, "Guard bits 2 and 8 steps is a valid TCQ configuration.")
        XCTAssertEqual(result.extension, .trellisCodedQuantisation)
    }

    func testTCQValidationRejectsZeroStepCount() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateTCQ(guardbits: 2, stepCount: 0)

        // Assert
        XCTAssertFalse(result.isCompliant, "A step count of 0 must be rejected.")
    }

    func testExtendedROIValidationAcceptsValidShift() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateExtendedROI(shift: 10, maxShift: 37)

        // Assert
        XCTAssertTrue(result.isCompliant, "Shift of 10 within max 37 must be valid.")
        XCTAssertEqual(result.extension, .extendedROI)
    }

    func testExtendedROIValidationRejectsExcessiveShift() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateExtendedROI(shift: 38, maxShift: 37)

        // Assert
        XCTAssertFalse(result.isCompliant, "Shift exceeding the absolute maximum of 37 must be rejected.")
    }
}

// MARK: - Arbitrary Wavelet and DC-Offset Conformance Tests

final class J2KArbitraryWaveletConformanceTests: XCTestCase {

    // MARK: - Arbitrary Wavelet

    func testArbitraryWaveletValidSymmetric() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateArbitraryWavelet(tapCount: 5, isSymmetric: true)

        // Assert
        XCTAssertTrue(result.isCompliant, "Symmetric 5-tap wavelet is valid.")
        XCTAssertEqual(result.extension, .arbitraryWavelets)
    }

    func testArbitraryWaveletRejectsTooFewTaps() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateArbitraryWavelet(tapCount: 2, isSymmetric: true)

        // Assert
        XCTAssertFalse(result.isCompliant, "Symmetric filter with 2 taps must be rejected (must be odd ≥ 3).")
    }

    func testArbitraryWaveletAsymmetricMinimum() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateArbitraryWavelet(tapCount: 2, isSymmetric: false)

        // Assert
        XCTAssertTrue(result.isCompliant, "Asymmetric filter with 2 taps is at the minimum and must be valid.")
    }

    // MARK: - DC Offset

    func testDCOffsetValidationAcceptsUnsigned8Bit() {
        // Arrange / Act
        let result = J2KPart2ConformanceValidator.validateDCOffset(offset: 128, bitDepth: 8, isSigned: false)

        // Assert
        XCTAssertTrue(result.isCompliant, "DC-Offset 128 is within [0, 255] for 8-bit unsigned.")
        XCTAssertEqual(result.extension, .dcOffset)
    }

    func testDCOffsetValidationRejectsOutOfRangeUnsigned() {
        // Arrange / Act — 256 exceeds max of 255 for 8-bit unsigned
        let result = J2KPart2ConformanceValidator.validateDCOffset(offset: 256, bitDepth: 8, isSigned: false)

        // Assert
        XCTAssertFalse(result.isCompliant, "DC-Offset 256 exceeds the maximum for 8-bit unsigned.")
    }

    func testDCOffsetValidationAcceptsSigned8Bit() {
        // Arrange / Act — valid range is [-128, 127]
        let result = J2KPart2ConformanceValidator.validateDCOffset(offset: -128, bitDepth: 8, isSigned: true)

        // Assert
        XCTAssertTrue(result.isCompliant, "DC-Offset -128 is the minimum for 8-bit signed.")
    }

    func testDCOffsetValidationRejectsOutOfRangeSigned() {
        // Arrange / Act — -129 is below minimum of -128
        let result = J2KPart2ConformanceValidator.validateDCOffset(offset: -129, bitDepth: 8, isSigned: true)

        // Assert
        XCTAssertFalse(result.isCompliant, "DC-Offset -129 is below the minimum for 8-bit signed.")
    }
}

// MARK: - Part 2 Conformance Test Suite Tests

final class J2KPart2ConformanceTestSuiteTests: XCTestCase {

    // MARK: - Standard Test Cases

    func testStandardTestCasesNonEmpty() {
        // Act
        let cases = J2KPart2ConformanceTestSuite.standardTestCases()

        // Assert
        XCTAssertFalse(cases.isEmpty, "The standard test case list must not be empty.")
    }

    func testStandardTestCasesAtLeast20() {
        // Act
        let cases = J2KPart2ConformanceTestSuite.standardTestCases()

        // Assert
        XCTAssertGreaterThanOrEqual(cases.count, 20, "At least 20 standard test cases must be provided.")
    }

    func testAllTestCategoriesCovered() {
        // Arrange
        let cases = J2KPart2ConformanceTestSuite.standardTestCases()
        let coveredCategories = Set(cases.map(\.category))

        // Assert
        for category in J2KPart2ConformanceTestSuite.TestCategory.allCases {
            XCTAssertTrue(coveredCategories.contains(category), "Category '\(category.rawValue)' must be represented in the standard test cases.")
        }
    }

    func testTestCasesHaveUniqueIdentifiers() {
        // Arrange
        let cases = J2KPart2ConformanceTestSuite.standardTestCases()
        let identifiers = cases.map(\.identifier)
        let uniqueIdentifiers = Set(identifiers)

        // Assert
        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count, "All test case identifiers must be unique.")
    }

    func testExtensionEnumAllCases() {
        // Assert — every Part 2 extension is iterable
        XCTAssertFalse(J2KPart2Extension.allCases.isEmpty)
        XCTAssertGreaterThanOrEqual(J2KPart2Extension.allCases.count, 7, "All 7 Part 2 extensions must be declared.")
    }

    func testTestCategoryAllCases() {
        // Assert — every test category is iterable
        XCTAssertFalse(J2KPart2ConformanceTestSuite.TestCategory.allCases.isEmpty)
        XCTAssertGreaterThanOrEqual(J2KPart2ConformanceTestSuite.TestCategory.allCases.count, 7)
    }

    func testReportGenerationNonEmpty() {
        // Arrange
        let cases = J2KPart2ConformanceTestSuite.standardTestCases()
        let results = cases.map { ($0, $0.expectedCompliant) }

        // Act
        let report = J2KPart2ConformanceTestSuite.generateReport(results: results)

        // Assert
        XCTAssertFalse(report.isEmpty, "Generated report must not be empty.")
        XCTAssertTrue(report.contains("Part 2"), "Report must reference Part 2.")
    }

    func testCompliantAndNonCompliantCasesPresent() {
        // Arrange
        let cases = J2KPart2ConformanceTestSuite.standardTestCases()

        // Assert — the suite must include both valid and invalid configurations
        XCTAssertTrue(cases.contains(where: { $0.expectedCompliant }), "At least one expected-compliant test case is required.")
        XCTAssertTrue(cases.contains(where: { !$0.expectedCompliant }), "At least one expected-non-compliant test case is required.")
    }
}
