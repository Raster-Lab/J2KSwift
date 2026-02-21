//
// J2KPart4ConformanceFinalTests.swift
// J2KSwift
//
/// # J2KPart4ConformanceFinalTests
///
/// Week 290–292 conformance final validation milestone for JPEG 2000 Part 4
/// (ISO/IEC 15444-4).
///
/// Covers decoder conformance class validation (Class-0 and Class-1),
/// encoder conformance class validation, cross-part conformance,
/// OpenJPEG cross-validation, conformance archiving, Part 4 test suite,
/// and final certification report generation.

import XCTest
@testable import J2KCore

// MARK: - Decoder Conformance Validator Tests

final class J2KDecoderConformanceValidatorTests: XCTestCase {

    // MARK: - Class-0 Decoder

    func testClass0ValidatorAcceptsSyntheticVectors() {
        // Arrange
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        // Act
        let result = J2KDecoderConformanceValidator.validateClass0(testVectors: vectors)

        // Assert
        XCTAssertTrue(result.isConformant, "Synthetic test vectors must pass Class-0 decoder validation.")
        XCTAssertEqual(result.decoderClass, .class0)
        XCTAssertGreaterThan(result.vectorsValidated, 0)
        XCTAssertEqual(result.vectorsPassed, result.vectorsValidated)
    }

    func testClass0ValidatorRejectsEmptyVectors() {
        // Act
        let result = J2KDecoderConformanceValidator.validateClass0(testVectors: [])

        // Assert
        XCTAssertFalse(result.isConformant, "Empty test vector set must fail Class-0 validation.")
        XCTAssertEqual(result.vectorsValidated, 0)
    }

    func testClass0ValidatorResultIncludesMetrics() {
        // Arrange
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        // Act
        let result = J2KDecoderConformanceValidator.validateClass0(testVectors: vectors)

        // Assert
        XCTAssertEqual(result.maxAbsoluteError, 0, "Lossless Class-0 must have zero MAE.")
        XCTAssertEqual(result.meanSquaredError, 0, accuracy: 0.001, "Lossless Class-0 must have zero MSE.")
    }

    // MARK: - Class-1 Decoder

    func testClass1ValidatorAcceptsSyntheticVectors() {
        // Arrange
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        // Act
        let result = J2KDecoderConformanceValidator.validateClass1(testVectors: vectors)

        // Assert
        XCTAssertTrue(result.isConformant, "Synthetic test vectors must pass Class-1 decoder validation.")
        XCTAssertEqual(result.decoderClass, .class1)
        XCTAssertGreaterThan(result.vectorsValidated, 0)
    }

    func testClass1ValidatorRejectsEmptyVectors() {
        // Act
        let result = J2KDecoderConformanceValidator.validateClass1(testVectors: [])

        // Assert
        XCTAssertFalse(result.isConformant, "Empty test vector set must fail Class-1 validation.")
    }

    func testClass1ValidatorPSNRIsValid() {
        // Arrange
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        // Act
        let result = J2KDecoderConformanceValidator.validateClass1(testVectors: vectors)

        // Assert
        XCTAssertNotNil(result.psnr, "Class-1 validation must produce a PSNR value.")
    }
}

// MARK: - Encoder Conformance Validator Tests

final class J2KEncoderConformanceValidatorTests: XCTestCase {

    // MARK: - Class-0 Encoder

    func testClass0EncoderAcceptsValidCodestreams() {
        // Arrange
        let cs = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KEncoderConformanceValidator.validateClass0(codestreams: [cs])

        // Assert
        XCTAssertTrue(result.isConformant, "A valid codestream must pass Class-0 encoder validation.")
        XCTAssertEqual(result.encoderClass, .class0)
        XCTAssertTrue(result.markerStructureValid)
        XCTAssertEqual(result.imagesPassed, 1)
    }

    func testClass0EncoderRejectsInvalidCodestream() {
        // Arrange
        let invalid = Data([0x00, 0x00, 0xFF, 0xD9])

        // Act
        let result = J2KEncoderConformanceValidator.validateClass0(codestreams: [invalid])

        // Assert
        XCTAssertFalse(result.isConformant, "An invalid codestream must fail Class-0 encoder validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testClass0EncoderRejectsEmptyCodestreams() {
        // Act
        let result = J2KEncoderConformanceValidator.validateClass0(codestreams: [])

        // Assert
        XCTAssertFalse(result.isConformant, "Empty codestream array must fail validation.")
    }

    func testClass0EncoderMultipleCodestreams() {
        // Arrange
        let cs1 = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )
        let cs2 = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 3, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KEncoderConformanceValidator.validateClass0(codestreams: [cs1, cs2])

        // Assert
        XCTAssertEqual(result.imagesValidated, 2)
    }

    // MARK: - Class-1 Encoder

    func testClass1EncoderAcceptsValidCodestreams() {
        // Arrange
        let cs = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Act
        let result = J2KEncoderConformanceValidator.validateClass1(codestreams: [cs])

        // Assert
        XCTAssertTrue(result.isConformant, "A valid codestream must pass Class-1 encoder validation.")
        XCTAssertEqual(result.encoderClass, .class1)
    }

    func testClass1EncoderRejectsInvalidCodestream() {
        // Arrange
        let invalid = Data([0x00, 0x00, 0xFF, 0xD9])

        // Act
        let result = J2KEncoderConformanceValidator.validateClass1(codestreams: [invalid])

        // Assert
        XCTAssertFalse(result.isConformant, "An invalid codestream must fail Class-1 encoder validation.")
    }
}

// MARK: - Cross-Part Conformance Validator Tests

final class J2KPart4CrossPartValidatorTests: XCTestCase {

    func testPart1PlusPart2Class0() {
        // Act
        let result = J2KPart4CrossPartValidator.validatePart1PlusPart2(
            decoderClass: .class0,
            extensions: []
        )

        // Assert
        XCTAssertTrue(result.isConformant, "Part 1 + Part 2 Class-0 (no extensions) must be conformant.")
        XCTAssertEqual(result.parts, ["Part 1", "Part 2"])
        XCTAssertEqual(result.partResults.count, 2)
    }

    func testPart1PlusPart2Class1AllExtensions() {
        // Act
        let result = J2KPart4CrossPartValidator.validatePart1PlusPart2(
            decoderClass: .class1,
            extensions: J2KPart2Extension.allCases
        )

        // Assert
        XCTAssertTrue(result.isConformant, "Part 1 + Part 2 Class-1 (all extensions) must be conformant.")
    }

    func testPart1PlusPart15() {
        // Arrange
        let cs = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: true
        )

        // Act
        let result = J2KPart4CrossPartValidator.validatePart1PlusPart15(
            codestream: cs,
            htLevel: .unrestricted
        )

        // Assert
        XCTAssertTrue(result.isConformant, "Part 1 + Part 15 cross-conformance must pass.")
        XCTAssertEqual(result.parts, ["Part 1", "Part 15"])
    }

    func testPart3PlusPart15() {
        // Act
        let result = J2KPart4CrossPartValidator.validatePart3PlusPart15(
            mj2FrameCount: 30,
            htLevel: .unrestricted
        )

        // Assert
        XCTAssertTrue(result.isConformant, "Part 3 + Part 15 cross-conformance must pass.")
        XCTAssertEqual(result.parts, ["Part 3", "Part 15"])
    }

    func testPart10PlusPart15() {
        // Act
        let result = J2KPart4CrossPartValidator.validatePart10PlusPart15(
            jp3dVolumeValid: true,
            htLevel: .unrestricted
        )

        // Assert
        XCTAssertTrue(result.isConformant, "Part 10 + Part 15 cross-conformance must pass.")
        XCTAssertEqual(result.parts, ["Part 10", "Part 15"])
    }

    func testFullCrossPartValidation() {
        // Act
        let results = J2KPart4CrossPartValidator.runFullCrossPartValidation()

        // Assert
        XCTAssertGreaterThanOrEqual(results.count, 7, "Full cross-part validation must cover at least 7 combinations.")
        for result in results {
            XCTAssertTrue(result.isConformant, "Cross-part validation \(result.parts.joined(separator: "+")) must pass.")
        }
    }
}

// MARK: - OpenJPEG Cross-Validation Tests

final class J2KOpenJPEGCrossValidatorTests: XCTestCase {

    func testCrossValidationReturnsResult() {
        // Act
        let result = J2KOpenJPEGCrossValidator.runCrossValidation()

        // Assert
        XCTAssertTrue(result.isInteroperable, "Cross-validation infrastructure must report interoperability.")
        XCTAssertGreaterThan(result.imagesValidated, 0)
        XCTAssertFalse(result.summary.isEmpty)
    }

    func testCrossValidationHasNoErrors() {
        // Act
        let result = J2KOpenJPEGCrossValidator.runCrossValidation()

        // Assert
        XCTAssertTrue(result.errors.isEmpty, "Cross-validation infrastructure must produce no errors.")
    }
}

// MARK: - Conformance Archive Tests

final class J2KConformanceArchiveTests: XCTestCase {

    func testCreateArchiveEntry() {
        // Arrange
        let runResult = J2KConformanceAutomationRunner.RunResult(
            totalTests: 100,
            passed: 95,
            failed: 3,
            skipped: 2
        )

        // Act
        let entry = J2KConformanceArchive.createArchiveEntry(from: runResult)

        // Assert
        XCTAssertFalse(entry.runId.isEmpty)
        XCTAssertFalse(entry.timestamp.isEmpty)
        XCTAssertEqual(entry.totalTests, 100)
        XCTAssertEqual(entry.passed, 95)
        XCTAssertEqual(entry.failed, 3)
        XCTAssertEqual(entry.skipped, 2)
        XCTAssertEqual(entry.passRate, 0.95, accuracy: 0.001)
        XCTAssertEqual(entry.partsValidated, ["Part 1", "Part 2", "Part 3", "Part 10", "Part 15"])
    }

    func testArchiveReportGeneration() {
        // Arrange
        let runResult = J2KConformanceAutomationRunner.RunResult(
            totalTests: 50,
            passed: 50,
            failed: 0,
            skipped: 0
        )
        let entry = J2KConformanceArchive.createArchiveEntry(from: runResult)

        // Act
        let report = J2KConformanceArchive.generateArchiveReport(entry)

        // Assert
        XCTAssertTrue(report.contains("Conformance Test Archive Entry"))
        XCTAssertTrue(report.contains("100.0%"))
        XCTAssertTrue(report.contains("ISO/IEC 15444-4"))
    }

    func testArchiveEntryPassRateZeroDivision() {
        // Arrange
        let runResult = J2KConformanceAutomationRunner.RunResult(
            totalTests: 0,
            passed: 0,
            failed: 0,
            skipped: 0
        )

        // Act
        let entry = J2KConformanceArchive.createArchiveEntry(from: runResult)

        // Assert
        XCTAssertEqual(entry.passRate, 0, "Pass rate for zero tests must be 0.")
    }
}

// MARK: - Part 4 Conformance Test Suite Tests

final class J2KPart4ConformanceTestSuiteTests: XCTestCase {

    func testStandardTestCasesNotEmpty() {
        // Act
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()

        // Assert
        XCTAssertGreaterThanOrEqual(cases.count, 20, "Part 4 test suite must contain at least 20 test cases.")
    }

    func testStandardTestCasesCoversAllCategories() {
        // Act
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let categoriesCovered = Set(cases.map(\.category))

        // Assert
        for category in J2KPart4TestCategory.allCases {
            XCTAssertTrue(
                categoriesCovered.contains(category),
                "Category \(category.rawValue) must be covered by the test suite."
            )
        }
    }

    func testStandardTestCasesHaveUniqueIdentifiers() {
        // Act
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let ids = cases.map(\.identifier)
        let uniqueIds = Set(ids)

        // Assert
        XCTAssertEqual(ids.count, uniqueIds.count, "All test case identifiers must be unique.")
    }

    func testDecoderClass0TestCases() {
        // Act
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let class0Cases = cases.filter { $0.category == .decoderClass0 }

        // Assert
        XCTAssertGreaterThanOrEqual(class0Cases.count, 3, "Must have at least 3 decoder Class-0 test cases.")
        XCTAssertTrue(class0Cases.contains(where: { $0.expectedValid }), "Must include expected-valid Class-0 cases.")
        XCTAssertTrue(class0Cases.contains(where: { !$0.expectedValid }), "Must include expected-invalid Class-0 cases.")
    }

    func testEncoderClass0TestCases() {
        // Act
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let encCases = cases.filter { $0.category == .encoderClass0 }

        // Assert
        XCTAssertGreaterThanOrEqual(encCases.count, 2, "Must have at least 2 encoder Class-0 test cases.")
    }

    func testCrossPartTestCases() {
        // Act
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let xpCases = cases.filter { $0.category == .crossPart }

        // Assert
        XCTAssertGreaterThanOrEqual(xpCases.count, 5, "Must have at least 5 cross-part test cases.")
    }

    func testOpenJPEGTestCases() {
        // Act
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let opjCases = cases.filter { $0.category == .openJPEGCrossValidation }

        // Assert
        XCTAssertGreaterThanOrEqual(opjCases.count, 2, "Must have at least 2 OpenJPEG cross-validation test cases.")
    }

    func testReportGeneration() {
        // Arrange
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let results: [(J2KPart4ConformanceTestSuite.Part4TestCase, Bool)] = cases.map { ($0, true) }

        // Act
        let report = J2KPart4ConformanceTestSuite.generateReport(results: results)

        // Assert
        XCTAssertTrue(report.contains("Part 4 Conformance Final Validation Report"))
        XCTAssertTrue(report.contains("100.0%"))
        XCTAssertTrue(report.contains("ISO/IEC 15444-4"))
    }

    func testReportGenerationWithFailures() {
        // Arrange
        let cases = J2KPart4ConformanceTestSuite.standardTestCases()
        let results: [(J2KPart4ConformanceTestSuite.Part4TestCase, Bool)] = cases.enumerated().map {
            ($0.element, $0.offset % 3 != 0) // Every third case fails
        }

        // Act
        let report = J2KPart4ConformanceTestSuite.generateReport(results: results)

        // Assert
        XCTAssertTrue(report.contains("❌ Fail"))
        XCTAssertTrue(report.contains("✅ Pass"))
    }
}

// MARK: - Part 4 Certification Report Tests

final class J2KPart4CertificationReportTests: XCTestCase {

    func testCertificationRunsSuccessfully() {
        // Act
        let result = J2KPart4CertificationReport.runCertification()

        // Assert
        XCTAssertFalse(result.libraryVersion.isEmpty)
        XCTAssertFalse(result.platform.isEmpty)
        XCTAssertGreaterThan(result.knownLimitations.count, 0, "Known limitations must be documented.")
    }

    func testCertificationDecoderResults() {
        // Act
        let result = J2KPart4CertificationReport.runCertification()

        // Assert
        XCTAssertTrue(result.decoderClass0.isConformant, "Decoder Class-0 must be conformant.")
        XCTAssertTrue(result.decoderClass1.isConformant, "Decoder Class-1 must be conformant.")
    }

    func testCertificationEncoderResults() {
        // Act
        let result = J2KPart4CertificationReport.runCertification()

        // Assert
        XCTAssertTrue(result.encoderClass0.isConformant, "Encoder Class-0 must be conformant.")
    }

    func testCertificationCrossPartResults() {
        // Act
        let result = J2KPart4CertificationReport.runCertification()

        // Assert
        XCTAssertGreaterThan(result.crossPartResults.count, 0, "Cross-part results must be non-empty.")
    }

    func testCertificationReportGeneration() {
        // Arrange
        let result = J2KPart4CertificationReport.runCertification()

        // Act
        let report = J2KPart4CertificationReport.generateReport(result)

        // Assert
        XCTAssertTrue(report.contains("Part 4 Conformance Certification Report"))
        XCTAssertTrue(report.contains("Decoder Conformance"))
        XCTAssertTrue(report.contains("Encoder Conformance"))
        XCTAssertTrue(report.contains("Cross-Part Conformance"))
        XCTAssertTrue(report.contains("OpenJPEG Cross-Validation"))
        XCTAssertTrue(report.contains("Known Limitations"))
        XCTAssertTrue(report.contains("ISO/IEC 15444-4"))
    }

    func testCertificationStatusIsCertified() {
        // Act
        let result = J2KPart4CertificationReport.runCertification()

        // Assert — with synthetic vectors, the implementation should be certified
        XCTAssertEqual(
            result.status, .certified,
            "With valid synthetic test vectors, status must be Certified."
        )
    }
}

// MARK: - Encoder Conformance Class Tests

final class J2KEncoderConformanceClassTests: XCTestCase {

    func testAllCases() {
        // Assert
        XCTAssertEqual(J2KEncoderConformanceClass.allCases.count, 2)
        XCTAssertEqual(J2KEncoderConformanceClass.class0.rawValue, "Class-0")
        XCTAssertEqual(J2KEncoderConformanceClass.class1.rawValue, "Class-1")
    }
}

// MARK: - Part 4 Test Category Tests

final class J2KPart4TestCategoryTests: XCTestCase {

    func testAllCases() {
        // Assert
        XCTAssertEqual(J2KPart4TestCategory.allCases.count, 6)
    }

    func testCategoryRawValues() {
        // Assert
        XCTAssertEqual(J2KPart4TestCategory.decoderClass0.rawValue, "decoderClass0")
        XCTAssertEqual(J2KPart4TestCategory.encoderClass0.rawValue, "encoderClass0")
        XCTAssertEqual(J2KPart4TestCategory.crossPart.rawValue, "crossPart")
        XCTAssertEqual(J2KPart4TestCategory.openJPEGCrossValidation.rawValue, "openJPEGCrossValidation")
    }
}
