// J2KISOTestSuiteTests.swift
// J2KSwift
//
// Tests for ISO/IEC 15444-4 conformance test suite validation.
// These tests validate J2KSwift against synthetic test vectors based on
// the ISO/IEC 15444-4 specification, covering baseline and extended profiles.

import XCTest
@testable import J2KCore

final class J2KISOTestSuiteTests: XCTestCase {
    // MARK: - ISO Test Suite Loader Tests

    func testISOTestCaseCatalogNotEmpty() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        XCTAssertGreaterThan(catalog.count, 0, "ISO test case catalog should not be empty")
    }

    func testISOTestCaseCatalogContainsAllProfiles() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()

        let profile0Cases = catalog.filter { $0.conformanceClass == .profile0 }
        let profile1Cases = catalog.filter { $0.conformanceClass == .profile1 }
        let htj2kCases = catalog.filter { $0.conformanceClass == .htj2k }

        XCTAssertGreaterThan(profile0Cases.count, 0, "Should have Profile-0 test cases")
        XCTAssertGreaterThan(profile1Cases.count, 0, "Should have Profile-1 test cases")
        XCTAssertGreaterThan(htj2kCases.count, 0, "Should have HTJ2K test cases")
    }

    func testISOTestCaseCatalogUniqueIdentifiers() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        let identifiers = catalog.map { $0.identifier }
        let uniqueIdentifiers = Set(identifiers)

        XCTAssertEqual(identifiers.count, uniqueIdentifiers.count,
                       "All test case identifiers should be unique")
    }

    func testISOTestCaseMetadataValidity() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()

        for testCase in catalog {
            XCTAssertFalse(testCase.identifier.isEmpty,
                           "Test case identifier should not be empty")
            XCTAssertFalse(testCase.description.isEmpty,
                           "Test case description should not be empty")
            XCTAssertGreaterThan(testCase.width, 0,
                                "\(testCase.identifier): width should be positive")
            XCTAssertGreaterThan(testCase.height, 0,
                                "\(testCase.identifier): height should be positive")
            XCTAssertGreaterThan(testCase.components, 0,
                                "\(testCase.identifier): components should be positive")
            XCTAssertGreaterThanOrEqual(testCase.bitDepth, 1,
                                       "\(testCase.identifier): bitDepth should be >= 1")
            XCTAssertLessThanOrEqual(testCase.bitDepth, 38,
                                    "\(testCase.identifier): bitDepth should be <= 38")
            XCTAssertGreaterThanOrEqual(testCase.maxAllowableError, 0,
                                       "\(testCase.identifier): maxAllowableError should be >= 0")
        }
    }

    func testISOTestCaseLosslessHasZeroError() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        let losslessCases = catalog.filter { $0.isLossless }

        XCTAssertGreaterThan(losslessCases.count, 0, "Should have lossless test cases")

        for testCase in losslessCases {
            XCTAssertEqual(testCase.maxAllowableError, 0,
                           "\(testCase.identifier): lossless tests must have zero error tolerance")
            XCTAssertEqual(testCase.waveletFilter, .reversible5_3,
                           "\(testCase.identifier): lossless tests must use 5/3 wavelet")
        }
    }

    func testISOTestCaseLossyUsesIrreversibleFilter() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        let lossyCases = catalog.filter { !$0.isLossless }

        XCTAssertGreaterThan(lossyCases.count, 0, "Should have lossy test cases")

        for testCase in lossyCases {
            XCTAssertEqual(testCase.waveletFilter, .irreversible9_7,
                           "\(testCase.identifier): lossy tests should use 9/7 wavelet")
            XCTAssertGreaterThan(testCase.maxAllowableError, 0,
                                "\(testCase.identifier): lossy tests should allow some error")
        }
    }

    // MARK: - Synthetic Test Vector Generation

    func testSyntheticTestVectorsGenerated() throws {
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()
        XCTAssertGreaterThan(vectors.count, 0, "Should generate synthetic test vectors")

        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        XCTAssertEqual(vectors.count, catalog.count,
                       "Should generate one vector per catalog entry")
    }

    func testSyntheticTestVectorProperties() throws {
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        for vector in vectors {
            XCTAssertFalse(vector.name.isEmpty, "Vector name should not be empty")
            XCTAssertFalse(vector.description.isEmpty, "Vector description should not be empty")
            XCTAssertNotNil(vector.referenceImage,
                            "\(vector.name): should have reference image")

            if let ref = vector.referenceImage {
                let expectedPixels = vector.width * vector.height * vector.components
                XCTAssertEqual(ref.count, expectedPixels,
                               "\(vector.name): reference image size mismatch")
            }
        }
    }

    func testSyntheticTestVectorReferenceImagesValid() throws {
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        for vector in vectors {
            guard let ref = vector.referenceImage else { continue }

            let maxValue = Int32((1 << vector.bitDepth) - 1)

            for pixel in ref {
                XCTAssertGreaterThanOrEqual(pixel, 0,
                    "\(vector.name): pixel values should be non-negative")
                XCTAssertLessThanOrEqual(pixel, maxValue,
                    "\(vector.name): pixel values should not exceed max for bit depth")
            }
        }
    }

    // MARK: - Test Image Generation

    func testGenerateTestImageGrayscale() throws {
        let pixels = J2KISOTestSuiteLoader.generateTestImage(
            width: 16, height: 16, components: 1, bitDepth: 8
        )

        XCTAssertEqual(pixels.count, 16 * 16 * 1)

        // Check pixel values are within range
        for pixel in pixels {
            XCTAssertGreaterThanOrEqual(pixel, 0)
            XCTAssertLessThanOrEqual(pixel, 255)
        }
    }

    func testGenerateTestImageRGB() throws {
        let pixels = J2KISOTestSuiteLoader.generateTestImage(
            width: 32, height: 32, components: 3, bitDepth: 8
        )

        XCTAssertEqual(pixels.count, 32 * 32 * 3)

        for pixel in pixels {
            XCTAssertGreaterThanOrEqual(pixel, 0)
            XCTAssertLessThanOrEqual(pixel, 255)
        }
    }

    func testGenerateTestImageHighBitDepth() throws {
        let pixels = J2KISOTestSuiteLoader.generateTestImage(
            width: 8, height: 8, components: 1, bitDepth: 12
        )

        XCTAssertEqual(pixels.count, 8 * 8 * 1)

        let maxValue = Int32((1 << 12) - 1) // 4095
        for pixel in pixels {
            XCTAssertGreaterThanOrEqual(pixel, 0)
            XCTAssertLessThanOrEqual(pixel, maxValue)
        }
    }

    func testGenerateTestImage16Bit() throws {
        let pixels = J2KISOTestSuiteLoader.generateTestImage(
            width: 4, height: 4, components: 1, bitDepth: 16
        )

        XCTAssertEqual(pixels.count, 4 * 4 * 1)

        let maxValue = Int32((1 << 16) - 1) // 65535
        for pixel in pixels {
            XCTAssertGreaterThanOrEqual(pixel, 0)
            XCTAssertLessThanOrEqual(pixel, maxValue)
        }
    }

    func testGenerateTestImageDeterministic() throws {
        let pixels1 = J2KISOTestSuiteLoader.generateTestImage(
            width: 16, height: 16, components: 1, bitDepth: 8
        )
        let pixels2 = J2KISOTestSuiteLoader.generateTestImage(
            width: 16, height: 16, components: 1, bitDepth: 8
        )

        XCTAssertEqual(pixels1, pixels2,
                       "Test image generation should be deterministic")
    }

    func testGenerateTestImageGradientPattern() throws {
        let width = 16
        let pixels = J2KISOTestSuiteLoader.generateTestImage(
            width: width, height: 16, components: 1, bitDepth: 8
        )

        // First row should be a horizontal gradient
        let firstPixel = pixels[0]
        let lastPixelInRow = pixels[width - 1]

        XCTAssertEqual(firstPixel, 0, "Gradient should start at 0")
        XCTAssertEqual(lastPixelInRow, 255, "Gradient should end at max value")
    }

    // MARK: - Conformance Validation with Synthetic Vectors

    func testValidateSyntheticVectorPerfectMatch() throws {
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()
        guard let vector = vectors.first else {
            XCTFail("No synthetic test vectors available")
            return
        }
        guard let decoded = vector.referenceImage else {
            XCTFail("Synthetic vector should have reference image")
            return
        }

        let result = J2KConformanceValidator.validate(
            decoded: decoded,
            against: vector
        )

        XCTAssertTrue(result.passed, "Perfect match should pass")
        XCTAssertNil(result.errorMessage)
        XCTAssertNotNil(result.mse)
        XCTAssertNotNil(result.mae)
        XCTAssertEqual(result.mse ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(result.mae ?? -1, 0)
    }

    func testValidateAllSyntheticVectorsPerfectMatch() throws {
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        for vector in vectors {
            guard let decoded = vector.referenceImage else { continue }

            let result = J2KConformanceValidator.validate(
                decoded: decoded,
                against: vector
            )

            XCTAssertTrue(result.passed,
                          "\(vector.name): perfect match should pass - \(result.errorMessage ?? "")")
        }
    }

    func testValidateSyntheticVectorWithinTolerance() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        guard let lossyCase = catalog.first(where: { !$0.isLossless }) else {
            XCTFail("No lossy test case found")
            return
        }

        let referenceImage = J2KISOTestSuiteLoader.generateTestImage(
            width: lossyCase.width,
            height: lossyCase.height,
            components: lossyCase.components,
            bitDepth: lossyCase.bitDepth
        )

        // Simulate lossy decoding with small errors within tolerance
        var decoded = referenceImage
        for i in stride(from: 0, to: decoded.count, by: 10) {
            decoded[i] = min(decoded[i] + Int32(lossyCase.maxAllowableError - 1),
                             Int32((1 << lossyCase.bitDepth) - 1))
        }

        let vector = J2KTestVector(
            name: lossyCase.identifier,
            description: lossyCase.description,
            codestream: Data(),
            referenceImage: referenceImage,
            width: lossyCase.width,
            height: lossyCase.height,
            components: lossyCase.components,
            bitDepth: lossyCase.bitDepth,
            maxAllowableError: lossyCase.maxAllowableError
        )

        let result = J2KConformanceValidator.validate(
            decoded: decoded,
            against: vector
        )

        XCTAssertTrue(result.passed,
                      "\(vector.name): error within tolerance should pass")
    }

    func testValidateSyntheticVectorExceedsTolerance() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        guard let losslessCase = catalog.first(where: { $0.isLossless }) else {
            XCTFail("No lossless test case found")
            return
        }

        let referenceImage = J2KISOTestSuiteLoader.generateTestImage(
            width: losslessCase.width,
            height: losslessCase.height,
            components: losslessCase.components,
            bitDepth: losslessCase.bitDepth
        )

        // Introduce error in a lossless test (should fail)
        var decoded = referenceImage
        decoded[0] += 1

        let vector = J2KTestVector(
            name: losslessCase.identifier,
            description: losslessCase.description,
            codestream: Data(),
            referenceImage: referenceImage,
            width: losslessCase.width,
            height: losslessCase.height,
            components: losslessCase.components,
            bitDepth: losslessCase.bitDepth,
            maxAllowableError: 0
        )

        let result = J2KConformanceValidator.validate(
            decoded: decoded,
            against: vector
        )

        XCTAssertFalse(result.passed,
                       "Error in lossless test should fail")
        XCTAssertNotNil(result.errorMessage)
    }

    // MARK: - ISO Test Suite Loader

    func testLoaderCreation() throws {
        let loader = J2KISOTestSuiteLoader()
        XCTAssertNotNil(loader)
    }

    func testLoaderTestSuiteNotAvailable() throws {
        let loader = J2KISOTestSuiteLoader()
        let available = loader.isTestSuiteAvailable(at: "/nonexistent/path")
        XCTAssertFalse(available, "Non-existent path should not be available")
    }

    func testLoaderTestSuiteLoadFailsGracefully() throws {
        let loader = J2KISOTestSuiteLoader()
        XCTAssertThrowsError(
            try loader.loadTestVectors(from: "/nonexistent/iso-test-suite")
        ) { error in
            XCTAssertTrue("\(error)".contains("not found"),
                          "Error should mention path not found")
        }
    }

    // MARK: - Conformance Report with ISO Vectors

    func testConformanceReportWithSyntheticVectors() throws {
        let vectors = J2KISOTestSuiteLoader.syntheticTestVectors()

        // Simulate all passing (perfect match)
        let results = vectors.compactMap { vector -> J2KConformanceValidator.TestResult? in
            guard let decoded = vector.referenceImage else { return nil }
            return J2KConformanceValidator.validate(decoded: decoded, against: vector)
        }

        let report = J2KConformanceValidator.generateReport(results: results)

        XCTAssertTrue(report.contains("Conformance Test Report"))
        XCTAssertTrue(report.contains("tests passed"))
        XCTAssertTrue(report.contains("100.0%"),
                      "All synthetic tests with perfect match should pass")
    }

    // MARK: - Profile-Specific Validation

    func testProfile0BaselineTestCases() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        let profile0 = catalog.filter { $0.conformanceClass == .profile0 }

        // Profile 0 should have both lossless and lossy tests
        let lossless = profile0.filter { $0.isLossless }
        let lossy = profile0.filter { !$0.isLossless }

        XCTAssertGreaterThan(lossless.count, 0,
                             "Profile-0 should have lossless tests")
        XCTAssertGreaterThan(lossy.count, 0,
                             "Profile-0 should have lossy tests")

        // Profile 0 should cover different bit depths
        let bitDepths = Set(profile0.map { $0.bitDepth })
        XCTAssertGreaterThan(bitDepths.count, 1,
                             "Profile-0 should test multiple bit depths")
    }

    func testProfile1ExtendedTestCases() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        let profile1 = catalog.filter { $0.conformanceClass == .profile1 }

        XCTAssertGreaterThan(profile1.count, 0,
                             "Should have Profile-1 test cases")

        // Profile 1 should have multi-component tests
        let multiComponent = profile1.filter { $0.components > 1 }
        XCTAssertGreaterThan(multiComponent.count, 0,
                             "Profile-1 should include multi-component tests")
    }

    func testHTJ2KConformanceTestCases() throws {
        let catalog = J2KISOTestSuiteLoader.isoTestCaseCatalog()
        let htj2k = catalog.filter { $0.conformanceClass == .htj2k }

        XCTAssertGreaterThan(htj2k.count, 0,
                             "Should have HTJ2K test cases")

        // HTJ2K should have both lossless and lossy
        let lossless = htj2k.filter { $0.isLossless }
        let lossy = htj2k.filter { !$0.isLossless }

        XCTAssertGreaterThan(lossless.count, 0,
                             "HTJ2K should have lossless tests")
        XCTAssertGreaterThan(lossy.count, 0,
                             "HTJ2K should have lossy tests")
    }

    // MARK: - Error Metrics with ISO-Like Data

    func testMSEWithProfile0GrayscaleData() throws {
        let width = 256
        let height = 256
        let reference = J2KISOTestSuiteLoader.generateTestImage(
            width: width, height: height, components: 1, bitDepth: 8
        )

        // Simulate small quantization errors
        var decoded = reference
        for i in stride(from: 0, to: decoded.count, by: 3) {
            decoded[i] = min(decoded[i] + 1, 255)
        }

        let mse = J2KErrorMetrics.meanSquaredError(reference: reference, test: decoded)
        XCTAssertNotNil(mse)
        XCTAssertGreaterThan(mse!, 0.0)
        XCTAssertLessThan(mse!, 1.0, "Small quantization errors should have low MSE")
    }

    func testPSNRWithProfile0Data() throws {
        let reference = J2KISOTestSuiteLoader.generateTestImage(
            width: 64, height: 64, components: 1, bitDepth: 8
        )

        var decoded = reference
        for i in stride(from: 0, to: decoded.count, by: 4) {
            decoded[i] = min(decoded[i] + 2, 255)
        }

        let psnr = J2KErrorMetrics.peakSignalToNoiseRatio(
            reference: reference, test: decoded, bitDepth: 8
        )
        XCTAssertNotNil(psnr)
        XCTAssertGreaterThan(psnr!, 30.0,
                             "Small errors should yield high PSNR (>30 dB)")
    }

    func testMAEWithLosslessConformance() throws {
        let reference = J2KISOTestSuiteLoader.generateTestImage(
            width: 32, height: 32, components: 1, bitDepth: 8
        )

        // Perfect reconstruction
        let decoded = reference

        let mae = J2KErrorMetrics.maximumAbsoluteError(
            reference: reference, test: decoded
        )
        XCTAssertNotNil(mae)
        XCTAssertEqual(mae!, 0, "Lossless should have zero MAE")
    }

    // MARK: - Conformance Class Enumeration

    func testConformanceClassAllCases() throws {
        let allCases = J2KISOTestSuiteLoader.ConformanceClass.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.profile0))
        XCTAssertTrue(allCases.contains(.profile1))
        XCTAssertTrue(allCases.contains(.htj2k))
    }

    func testConformanceClassRawValues() throws {
        XCTAssertEqual(J2KISOTestSuiteLoader.ConformanceClass.profile0.rawValue, "Profile-0")
        XCTAssertEqual(J2KISOTestSuiteLoader.ConformanceClass.profile1.rawValue, "Profile-1")
        XCTAssertEqual(J2KISOTestSuiteLoader.ConformanceClass.htj2k.rawValue, "HTJ2K")
    }

    func testWaveletFilterRawValues() throws {
        XCTAssertEqual(J2KISOTestSuiteLoader.WaveletFilter.reversible5_3.rawValue, "5/3")
        XCTAssertEqual(J2KISOTestSuiteLoader.WaveletFilter.irreversible9_7.rawValue, "9/7")
    }
}
