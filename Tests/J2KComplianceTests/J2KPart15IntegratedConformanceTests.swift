//
// J2KPart15IntegratedConformanceTests.swift
// J2KSwift
//
/// # J2KPart15IntegratedConformanceTests
///
/// Week 263–265 conformance milestone for JPEG 2000 Part 15 (HTJ2K) and
/// integrated cross-part validation.
///
/// Covers HT marker-segment validation (CAP, CPF), codestream-profile
/// validation, lossless transcoding, integrated multi-part conformance,
/// the J2KSwift conformance matrix, and the automation runner.

import XCTest
@testable import J2KCore

// MARK: - HT Conformance Validator Tests

final class J2KHTConformanceValidatorTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a minimal, well-formed CAP marker segment with Pcap bit 17 set.
    private func makeValidCAPMarker() -> Data {
        var data = Data()
        data.append(contentsOf: [0xFF, 0x50])   // CAP marker code
        data.append(contentsOf: [0x00, 0x08])   // Lcap = 8 (marker + length + Pcap)
        // Pcap (UInt32 big-endian) with bit 17 set: 0x00020000
        data.append(contentsOf: [0x00, 0x02, 0x00, 0x00])
        return data
    }

    /// Builds a minimal, well-formed CPF marker segment with Pcpf bit 15 set.
    private func makeValidCPFMarker() -> Data {
        var data = Data()
        data.append(contentsOf: [0xFF, 0x59])   // CPF marker code
        data.append(contentsOf: [0x00, 0x04])   // Lcpf = 4
        // Pcpf (UInt16 big-endian) with bit 15 set: 0x8000
        data.append(contentsOf: [0x80, 0x00])
        return data
    }

    // MARK: - CAP Marker

    func testCAPMarkerValidationAcceptsValidMarker() {
        // Arrange
        let data = makeValidCAPMarker()

        // Act
        let result = J2KHTConformanceValidator.validateCAPMarker(data)

        // Assert
        XCTAssertTrue(result.isCompliant, "A well-formed CAP marker with Pcap bit 17 set must be compliant.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testCAPMarkerValidationRejectsEmptyData() {
        // Act
        let result = J2KHTConformanceValidator.validateCAPMarker(Data())

        // Assert
        XCTAssertFalse(result.isCompliant, "Empty data must fail CAP validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testCAPMarkerValidationRejectsMissingPcapBit() {
        // Arrange — CAP marker present but Pcap bit 17 is NOT set
        var data = Data()
        data.append(contentsOf: [0xFF, 0x50])               // CAP marker code
        data.append(contentsOf: [0x00, 0x08])               // Lcap
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // Pcap with no bits set

        // Act
        let result = J2KHTConformanceValidator.validateCAPMarker(data)

        // Assert
        XCTAssertFalse(result.isCompliant, "CAP marker without Pcap bit 17 must fail validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - CPF Marker

    func testCPFMarkerValidationAcceptsValidMarker() {
        // Arrange
        let data = makeValidCPFMarker()

        // Act
        let result = J2KHTConformanceValidator.validateCPFMarker(data)

        // Assert
        XCTAssertTrue(result.isCompliant, "A well-formed CPF marker with Pcpf bit 15 set must be compliant.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testCPFMarkerValidationRejectsEmptyData() {
        // Act
        let result = J2KHTConformanceValidator.validateCPFMarker(Data())

        // Assert
        XCTAssertFalse(result.isCompliant, "Empty data must fail CPF validation.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Codestream Profile

    func testHTCodestreamProfileUnrestricted() {
        // Arrange — minimal SOC codestream, no CAP marker required for Unrestricted
        var data = Data([0xFF, 0x4F])   // SOC
        data.append(contentsOf: [0xFF, 0xD9])   // EOC

        // Act
        let result = J2KHTConformanceValidator.validateHTCodestreamProfile(data, expectedLevel: .unrestricted)

        // Assert
        XCTAssertTrue(result.isCompliant, "Unrestricted profile requires only SOC.")
        XCTAssertEqual(result.level, .unrestricted)
    }

    func testHTCodestreamProfileHTOnly() {
        // Arrange — SOC + CAP marker + EOC
        var data = Data([0xFF, 0x4F])                               // SOC
        data.append(contentsOf: makeValidCAPMarker())               // CAP
        data.append(contentsOf: [0xFF, 0xD9])                       // EOC

        // Act
        let result = J2KHTConformanceValidator.validateHTCodestreamProfile(data, expectedLevel: .htOnly)

        // Assert
        XCTAssertTrue(result.isCompliant, "HT-Only codestream with CAP marker must be compliant.")
    }

    // MARK: - Lossless Transcoding

    func testLosslessTranscodingValidation() {
        // Arrange — identical original and transcoded arrays
        let samples: [Int32] = [100, 200, 50, 75, 130, 255, 0, 1]

        // Act
        let result = J2KHTConformanceValidator.validateLosslessTranscoding(
            original: samples,
            transcoded: samples
        )

        // Assert
        XCTAssertTrue(result.isCompliant, "Identical arrays must confirm lossless transcoding.")
        XCTAssertEqual(result.level, .htRevOnly)
    }
}

// MARK: - Integrated Conformance Suite Tests

final class J2KIntegratedConformanceSuiteTests: XCTestCase {

    // MARK: - Part 1 + Part 2

    func testPart1PlusPart2ValidClass1WithExtensions() {
        // Act
        let result = J2KIntegratedConformanceSuite.validatePart1PlusPart2(
            decoderClass: .class1,
            extensions: [.multiComponentTransform, .nonLinearTransform]
        )

        // Assert
        XCTAssertTrue(result.passed, "Class-1 decoder with extensions must be valid.")
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testPart1PlusPart2Class0RejectsExtensions() {
        // Act
        let result = J2KIntegratedConformanceSuite.validatePart1PlusPart2(
            decoderClass: .class0,
            extensions: [.multiComponentTransform]
        )

        // Assert
        XCTAssertFalse(result.passed, "Class-0 decoder must not use Part 2 extensions.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    // MARK: - Part 1 + Part 15

    func testPart1PlusPart15ValidUnrestricted() {
        // Arrange — minimal codestream with only SOC
        let codestream = Data([0xFF, 0x4F, 0xFF, 0xD9])

        // Act
        let result = J2KIntegratedConformanceSuite.validatePart1PlusPart15(
            codestream: codestream,
            htLevel: .unrestricted
        )

        // Assert
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.parts.contains("Part 1"))
        XCTAssertTrue(result.parts.contains("Part 15"))
    }

    func testPart1PlusPart15ValidHTOnly() {
        // Arrange — SOC + CAP + EOC
        var codestream = Data([0xFF, 0x4F])
        // Embed a valid CAP marker
        codestream.append(contentsOf: [0xFF, 0x50, 0x00, 0x08, 0x00, 0x02, 0x00, 0x00])
        codestream.append(contentsOf: [0xFF, 0xD9])

        // Act
        let result = J2KIntegratedConformanceSuite.validatePart1PlusPart15(
            codestream: codestream,
            htLevel: .htOnly
        )

        // Assert
        XCTAssertTrue(result.passed, "HT-Only codestream with CAP marker must be valid in JP2 container.")
    }

    // MARK: - Part 3 + Part 15

    func testPart3PlusPart15ValidHTJ2KInMJ2() {
        // Act
        let result = J2KIntegratedConformanceSuite.validatePart3PlusPart15(
            mj2FrameCount: 60,
            htLevel: .htOnly
        )

        // Assert
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.parts.contains("Part 3"))
    }

    // MARK: - Part 10 + Part 15

    func testPart10PlusPart15ValidHTJ2KInJP3D() {
        // Act
        let result = J2KIntegratedConformanceSuite.validatePart10PlusPart15(
            jp3dVolumeValid: true,
            htLevel: .htRevOnly
        )

        // Assert
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.parts.contains("Part 10"))
    }

    func testPart10PlusPart15FailsIfJP3DInvalid() {
        // Act
        let result = J2KIntegratedConformanceSuite.validatePart10PlusPart15(
            jp3dVolumeValid: false,
            htLevel: .htOnly
        )

        // Assert
        XCTAssertFalse(result.passed, "Invalid JP3D volume must cause integrated validation to fail.")
        XCTAssertFalse(result.errors.isEmpty)
    }

    func testIntegratedResultFields() {
        // Act
        let result = J2KIntegratedConformanceSuite.validatePart3PlusPart15(
            mj2FrameCount: 10,
            htLevel: .unrestricted
        )

        // Assert
        XCTAssertFalse(result.testId.isEmpty, "Test ID must not be empty.")
        XCTAssertFalse(result.parts.isEmpty, "Parts list must not be empty.")
    }
}

// MARK: - Conformance Matrix Tests

final class J2KConformanceMatrixTests: XCTestCase {

    // MARK: - Current Status

    func testCurrentStatusNonEmpty() {
        // Act
        let statuses = J2KConformanceMatrix.currentStatus()

        // Assert
        XCTAssertFalse(statuses.isEmpty, "Conformance matrix must contain at least one entry.")
    }

    func testCurrentStatusContainsAllParts() {
        // Arrange
        let statuses = J2KConformanceMatrix.currentStatus()
        let parts = Set(statuses.map(\.part))

        // Assert
        for expectedPart in ["Part 1", "Part 2", "Part 3", "Part 10", "Part 15"] {
            XCTAssertTrue(parts.contains(expectedPart), "Conformance matrix must include \(expectedPart).")
        }
    }

    func testCurrentStatusPart1Compliant() {
        // Arrange
        let statuses = J2KConformanceMatrix.currentStatus()
        let part1 = statuses.first(where: { $0.part == "Part 1" })

        // Assert
        XCTAssertNotNil(part1, "Part 1 must be present in the conformance matrix.")
        XCTAssertTrue(part1?.class0 == true, "J2KSwift must declare Part 1 Class-0 conformance.")
        XCTAssertTrue(part1?.class1 == true, "J2KSwift must declare Part 1 Class-1 conformance.")
    }

    func testCurrentStatusPart15Compliant() {
        // Arrange
        let statuses = J2KConformanceMatrix.currentStatus()
        let part15 = statuses.first(where: { $0.part == "Part 15" })

        // Assert
        XCTAssertNotNil(part15, "Part 15 must be present in the conformance matrix.")
        XCTAssertTrue(part15?.class0 == true)
        XCTAssertTrue(part15?.class1 == true)
    }

    func testGenerateMatrixNonEmpty() {
        // Act
        let matrix = J2KConformanceMatrix.generateMatrix()

        // Assert
        XCTAssertFalse(matrix.isEmpty, "Generated conformance matrix must not be empty.")
    }

    func testGenerateMatrixContainsHeader() {
        // Act
        let matrix = J2KConformanceMatrix.generateMatrix()

        // Assert
        XCTAssertTrue(matrix.contains("Conformance Matrix") || matrix.contains("Part"), "Matrix must contain a meaningful header.")
    }

    func testPartConformanceStatusFields() {
        // Arrange
        let statuses = J2KConformanceMatrix.currentStatus()

        // Assert — every status must have non-empty part identifier, title, and notes
        for status in statuses {
            XCTAssertFalse(status.part.isEmpty, "Part identifier must not be empty.")
            XCTAssertFalse(status.title.isEmpty, "Part title must not be empty.")
            XCTAssertFalse(status.notes.isEmpty, "Part notes must not be empty.")
        }
    }
}

// MARK: - Conformance Automation Runner Tests

final class J2KConformanceAutomationRunnerTests: XCTestCase {

    // MARK: - Run All Suites

    func testRunAllSuitesNonZeroTests() {
        // Act
        let result = J2KConformanceAutomationRunner.runAllSuites()

        // Assert
        XCTAssertGreaterThan(result.totalTests, 0, "Automation runner must execute at least one test.")
    }

    func testRunAllSuitesPassRatePositive() {
        // Act
        let result = J2KConformanceAutomationRunner.runAllSuites()

        // Assert
        XCTAssertGreaterThan(result.passRate, 0.0, "Pass rate must be positive after running all suites.")
    }

    func testRunResultPassRateComputed() {
        // Arrange
        let result = J2KConformanceAutomationRunner.RunResult(totalTests: 10, passed: 8, failed: 2, skipped: 0)

        // Act / Assert
        XCTAssertEqual(result.passRate, 0.8, accuracy: 0.001, "Pass rate must be passed / totalTests.")
    }

    func testRunResultFieldsValid() {
        // Act
        let result = J2KConformanceAutomationRunner.runAllSuites()

        // Assert
        XCTAssertEqual(result.totalTests, result.passed + result.failed + result.skipped, "Totals must be consistent.")
    }

    func testGenerateConformanceReportNonEmpty() {
        // Arrange
        let result = J2KConformanceAutomationRunner.runAllSuites()

        // Act
        let report = J2KConformanceAutomationRunner.generateConformanceReport(result)

        // Assert
        XCTAssertFalse(report.isEmpty, "Generated conformance report must not be empty.")
    }

    func testGenerateConformanceReportContainsPassRate() {
        // Arrange
        let result = J2KConformanceAutomationRunner.runAllSuites()

        // Act
        let report = J2KConformanceAutomationRunner.generateConformanceReport(result)

        // Assert
        XCTAssertTrue(report.contains("Pass Rate") || report.contains("%"), "Report must include pass-rate information.")
    }

    // MARK: - Supporting Types

    func testHTConformanceLevelAllCases() {
        // Assert — all three HT conformance levels must be iterable
        XCTAssertEqual(J2KHTConformanceLevel.allCases.count, 3)
        XCTAssertTrue(J2KHTConformanceLevel.allCases.contains(.unrestricted))
        XCTAssertTrue(J2KHTConformanceLevel.allCases.contains(.htOnly))
        XCTAssertTrue(J2KHTConformanceLevel.allCases.contains(.htRevOnly))
    }

    func testConformanceMatrixAllPartsPresent() {
        // Act
        let statuses = J2KConformanceMatrix.currentStatus()

        // Assert
        XCTAssertGreaterThanOrEqual(statuses.count, 5, "All five JPEG 2000 parts must appear in the matrix.")
    }
}
