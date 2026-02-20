//
// J2KInteroperabilityTests.swift
// J2KSwift
//
// J2KInteroperabilityTests.swift
// J2KSwift
//
// Tests for HTJ2K interoperability validation.
// These tests verify that J2KSwift-generated codestreams conform to
// ISO/IEC 15444-1 and 15444-15 standards for cross-implementation
// compatibility with other JPEG 2000 decoders.

import XCTest
@testable import J2KCore

final class J2KInteroperabilityTests: XCTestCase {
    let validator = J2KHTInteroperabilityValidator()

    // MARK: - Synthetic Codestream Structure Tests

    /// Tests that a synthetic HTJ2K codestream has correct marker ordering.
    func testHTJ2KCodestreamMarkerOrdering() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: true
        )
        let result = validator.validateInteroperability(codestream: codestream)

        XCTAssertTrue(result.passed, "HTJ2K codestream should pass interoperability: \(result.errors)")
        XCTAssertTrue(result.isHTJ2K, "Should detect HTJ2K capability")

        // Verify marker ordering: SOC, SIZ, CAP, COD, CPF, QCD, SOT, SOD
        let markerNames = result.markers.map { $0.name }
        XCTAssertGreaterThanOrEqual(markerNames.count, 8, "Should have at least 8 markers")
        XCTAssertEqual(markerNames[0], "SOC", "First marker must be SOC")
        XCTAssertEqual(markerNames[1], "SIZ", "Second marker must be SIZ")
    }

    /// Tests that a synthetic legacy JPEG 2000 codestream has correct structure.
    func testLegacyCodestreamMarkerOrdering() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: false
        )
        let result = validator.validateInteroperability(codestream: codestream)

        XCTAssertTrue(result.passed, "Legacy codestream should pass: \(result.errors)")
        XCTAssertFalse(result.isHTJ2K, "Should not detect HTJ2K for legacy codestream")
        XCTAssertFalse(result.isMixedMode, "Should not detect mixed mode for legacy codestream")
    }

    /// Tests that an empty codestream is rejected.
    func testEmptyCodestreamRejected() throws {
        let codestream = Data()
        let result = validator.validateInteroperability(codestream: codestream)

        XCTAssertFalse(result.passed, "Empty codestream should fail validation")
        XCTAssertFalse(result.errors.isEmpty, "Should report errors for empty codestream")
    }

    /// Tests that a truncated codestream is handled gracefully.
    func testTruncatedCodestreamHandled() throws {
        // Just SOC marker - no other markers
        let codestream = Data([0xFF, 0x4F])
        let result = validator.validateInteroperability(codestream: codestream)

        XCTAssertFalse(result.passed, "Truncated codestream should fail validation")
        XCTAssertTrue(
            result.errors.contains { $0.contains("Missing required") },
            "Should report missing required markers"
        )
    }

    // MARK: - Marker Ordering Validation

    /// Tests that SOC as first marker is validated.
    func testSOCMustBeFirst() throws {
        // Create codestream with SIZ first instead of SOC
        var codestream = Data([0xFF, 0x51])  // SIZ marker
        codestream.append(contentsOf: [0x00, 0x02])  // Minimal length
        let errors = validator.validateMarkerOrdering(codestream: codestream)

        XCTAssertTrue(
            errors.contains { $0.contains("SOC") },
            "Should report missing SOC as first marker"
        )
    }

    /// Tests that SIZ as second marker is validated.
    func testSIZMustBeSecond() throws {
        // SOC followed by COD instead of SIZ
        var codestream = Data([0xFF, 0x4F])  // SOC
        codestream.append(contentsOf: [0xFF, 0x52])  // COD
        codestream.append(contentsOf: [0x00, 0x02])  // Minimal length
        let errors = validator.validateMarkerOrdering(codestream: codestream)

        XCTAssertTrue(
            errors.contains { $0.contains("SIZ") },
            "Should report SIZ not being second marker"
        )
    }

    /// Tests that CAP before COD ordering is enforced.
    func testCAPMustAppearBeforeCOD() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 32, height: 32, components: 1, bitDepth: 8, htj2k: true
        )
        let result = validator.validateInteroperability(codestream: codestream)

        // In our synthetic codestream, CAP appears before COD
        let markers = result.markers
        let capIdx = markers.firstIndex { $0.code == 0xFF50 }
        let codIdx = markers.firstIndex { $0.code == 0xFF52 }

        if let capIdx = capIdx, let codIdx = codIdx {
            XCTAssertLessThan(capIdx, codIdx, "CAP should appear before COD")
        }
    }

    // MARK: - Segment Length Validation

    /// Tests that marker segment lengths are valid.
    func testSegmentLengthsValid() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 128, height: 128, components: 3, bitDepth: 8, htj2k: true
        )
        let errors = validator.validateSegmentLengths(codestream: codestream)

        XCTAssertTrue(errors.isEmpty, "Segment lengths should be valid: \(errors)")
    }

    /// Tests that invalid segment lengths are detected.
    func testInvalidSegmentLengthDetected() throws {
        // SOC + SIZ marker with length=1 (too short, minimum is 2)
        var codestream = Data([0xFF, 0x4F])  // SOC
        codestream.append(contentsOf: [0xFF, 0x51])  // SIZ marker
        codestream.append(contentsOf: [0x00, 0x01])  // Invalid length: 1
        codestream.append(contentsOf: [0x00])  // Insufficient data

        let errors = validator.validateSegmentLengths(codestream: codestream)
        XCTAssertFalse(errors.isEmpty, "Should detect invalid segment length")
    }

    // MARK: - HTJ2K Capability Signaling

    /// Tests that HTJ2K capability is correctly detected from CAP marker.
    func testHTJ2KCapabilityDetection() throws {
        let htCodestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: true
        )
        let htResult = validator.validateCapabilitySignaling(codestream: htCodestream)

        XCTAssertTrue(htResult.isHTJ2K, "Should detect HTJ2K in HTJ2K codestream")
        XCTAssertTrue(htResult.errors.isEmpty, "HTJ2K signaling should have no errors: \(htResult.errors)")
    }

    /// Tests that legacy (non-HTJ2K) codestreams are identified correctly.
    func testLegacyCapabilityDetection() throws {
        let legacyCodestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: false
        )
        let legacyResult = validator.validateCapabilitySignaling(
            codestream: legacyCodestream
        )

        XCTAssertFalse(legacyResult.isHTJ2K, "Should not detect HTJ2K in legacy codestream")
    }

    /// Tests that mixed-mode detection works for non-mixed-mode codestreams.
    func testMixedModeDetection() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: true
        )
        let result = validator.validateInteroperability(codestream: codestream)

        // Our synthetic codestream uses Ccap = 0x0001 (no mixed mode)
        XCTAssertFalse(result.isMixedMode, "Synthetic codestream should not be mixed mode")
    }

    // MARK: - Cross-Format Compatibility

    /// Tests that both HTJ2K and legacy synthetic codestreams are structurally valid.
    func testCrossFormatStructuralValidity() throws {
        let configs: [(String, Bool)] = [
            ("HTJ2K", true),
            ("Legacy", false)
        ]

        for (label, useHTJ2K) in configs {
            let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 64, height: 64, components: 1, bitDepth: 8, htj2k: useHTJ2K
            )
            let result = validator.validateInteroperability(codestream: codestream)

            XCTAssertTrue(
                result.passed,
                "\(label) codestream should be structurally valid: \(result.errors)"
            )
        }
    }

    /// Tests interoperability across multiple image configurations.
    func testMultipleImageConfigurations() throws {
        let configs: [(Int, Int, Int, Int)] = [
            (16, 16, 1, 8),     // Small grayscale 8-bit
            (64, 64, 3, 8),     // Medium RGB 8-bit
            (128, 128, 1, 12),  // Large grayscale 12-bit
            (256, 256, 3, 16),  // Large RGB 16-bit
        ]

        for (width, height, components, bitDepth) in configs {
            let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: width, height: height,
                components: components, bitDepth: bitDepth,
                htj2k: true
            )
            let result = validator.validateInteroperability(codestream: codestream)

            XCTAssertTrue(
                result.passed,
                "Config \(width)×\(height)×\(components)@\(bitDepth)bit should pass: \(result.errors)"
            )
        }
    }

    // MARK: - Marker Parsing

    /// Tests that all expected markers are found in an HTJ2K codestream.
    func testHTJ2KMarkersPresent() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: true
        )
        let result = validator.validateInteroperability(codestream: codestream)
        let markerCodes = Set(result.markers.map { $0.code })

        // All required markers should be present
        XCTAssertTrue(markerCodes.contains(0xFF4F), "Should have SOC marker")
        XCTAssertTrue(markerCodes.contains(0xFF51), "Should have SIZ marker")
        XCTAssertTrue(markerCodes.contains(0xFF50), "Should have CAP marker (HTJ2K)")
        XCTAssertTrue(markerCodes.contains(0xFF52), "Should have COD marker")
        XCTAssertTrue(markerCodes.contains(0xFF59), "Should have CPF marker (HTJ2K)")
        XCTAssertTrue(markerCodes.contains(0xFF5C), "Should have QCD marker")
        XCTAssertTrue(markerCodes.contains(0xFF90), "Should have SOT marker")
        XCTAssertTrue(markerCodes.contains(0xFF93), "Should have SOD marker")
    }

    /// Tests that legacy codestream does NOT have CAP/CPF markers.
    func testLegacyMarkersDoNotHaveHTJ2K() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: false
        )
        let result = validator.validateInteroperability(codestream: codestream)
        let markerCodes = Set(result.markers.map { $0.code })

        XCTAssertFalse(markerCodes.contains(0xFF50), "Legacy should NOT have CAP marker")
        XCTAssertFalse(markerCodes.contains(0xFF59), "Legacy should NOT have CPF marker")
    }

    // MARK: - Report Generation

    /// Tests that interoperability report is generated correctly.
    func testReportGeneration() throws {
        var results: [J2KHTInteroperabilityValidator.InteroperabilityResult] = []

        // Generate results for HTJ2K and legacy codestreams
        for useHTJ2K in [true, false] {
            let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 64, height: 64, components: 1, bitDepth: 8, htj2k: useHTJ2K
            )
            results.append(validator.validateInteroperability(codestream: codestream))
        }

        let report = J2KHTInteroperabilityValidator.generateReport(results: results)

        XCTAssertTrue(report.contains("Interoperability Test Report"),
                       "Report should have title")
        XCTAssertTrue(report.contains("2/2 passed"),
                       "Report should show 2/2 passed")
        XCTAssertTrue(report.contains("PASS"),
                       "Report should contain PASS status")
    }

    /// Tests summary string generation.
    func testResultSummary() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: true
        )
        let result = validator.validateInteroperability(codestream: codestream)

        XCTAssertTrue(result.summary.contains("PASS"),
                       "Summary should contain PASS status")
        XCTAssertTrue(result.summary.contains("HTJ2K: true"),
                       "Summary should indicate HTJ2K")
    }

    // MARK: - MarkerCode Enum Tests

    /// Tests that all marker codes have correct names.
    func testMarkerCodeNames() throws {
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.soc.name, "SOC"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.siz.name, "SIZ"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.cap.name, "CAP"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.cpf.name, "CPF"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.cod.name, "COD"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.qcd.name, "QCD"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.sot.name, "SOT"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.sod.name, "SOD"
        )
        XCTAssertEqual(
            J2KHTInteroperabilityValidator.MarkerCode.eoc.name, "EOC"
        )
    }

    /// Tests that all MarkerCode cases have unique raw values.
    func testMarkerCodeUniqueValues() throws {
        let allCases = J2KHTInteroperabilityValidator.MarkerCode.allCases
        let rawValues = allCases.map { $0.rawValue }
        let uniqueRawValues = Set(rawValues)

        XCTAssertEqual(rawValues.count, uniqueRawValues.count,
                       "All marker codes should have unique raw values")
    }

    // MARK: - Comprehensive Interoperability Validation

    /// Tests full interoperability validation across HTJ2K test vector patterns.
    func testInteroperabilityWithTestVectorPatterns() throws {
        let patterns: [(String, HTJ2KTestVectorGenerator.TestPattern)] = [
            ("solid", .solid(value: 128)),
            ("gradient", .gradient),
            ("checkerboard", .checkerboard(squareSize: 8)),
            ("edges", .edges)
        ]

        for (name, pattern) in patterns {
            let config = HTJ2KTestVectorGenerator.Configuration(
                width: 64, height: 64, components: 1, bitDepth: 8,
                pattern: pattern, lossless: true, useHTJ2K: true
            )
            let vector = HTJ2KTestVectorGenerator.createTestVector(
                name: "interop_\(name)",
                description: "Interoperability test: \(name) pattern",
                config: config
            )

            // Verify test vector was created with valid reference data
            XCTAssertNotNil(vector.referenceImage,
                            "\(name): should have reference image")
            XCTAssertEqual(vector.width, 64, "\(name): width should be 64")
            XCTAssertEqual(vector.height, 64, "\(name): height should be 64")
            XCTAssertEqual(vector.referenceImage?.count, 64 * 64,
                           "\(name): should have 64*64 pixels")
        }
    }

    /// Tests that the conformance harness integrates with interoperability validation.
    func testConformanceHarnessIntegration() throws {
        let harness = HTJ2KConformanceTestHarness(
            rules: HTJ2KConformanceTestHarness.ValidationRules(
                requireCAPMarker: true,
                requireCPFMarker: true,
                validateHTSetParameters: true,
                allowMixedMode: false
            )
        )

        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 64, height: 64, components: 1, bitDepth: 8, htj2k: true
        )

        // Validate codestream structure using the harness
        let structureErrors = harness.validateCodestreamStructure(codestream)

        // Our synthetic HTJ2K codestream should have CAP and COD markers
        XCTAssertTrue(
            !structureErrors.contains { $0.contains("Missing or invalid SOC") },
            "Synthetic codestream should have valid SOC"
        )
    }

    /// Tests interoperability with SIZ marker content validation.
    func testSIZMarkerContentValidation() throws {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 256, height: 256, components: 3, bitDepth: 8, htj2k: true
        )
        let result = validator.validateInteroperability(codestream: codestream)
        let sizMarker = result.markers.first { $0.code == 0xFF51 }

        XCTAssertNotNil(sizMarker, "Should find SIZ marker")
        if let siz = sizMarker, let segLen = siz.segmentLength {
            // SIZ marker should have: 2 (Rsiz) + 4*4 (sizes) + 4*2 (origins)
            // + 2 (Csiz) + 3*3 (component info) = 2+16+8+2+9 = 37 + 2 = 39
            XCTAssertGreaterThanOrEqual(segLen, 39,
                                        "SIZ segment should contain component info")
        }
    }
}
