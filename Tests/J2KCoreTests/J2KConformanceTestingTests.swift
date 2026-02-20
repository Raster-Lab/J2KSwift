//
// J2KConformanceTestingTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests for the conformance testing framework.
final class J2KConformanceTestingTests: XCTestCase {
    // MARK: - Error Metrics Tests

    func testMSEIdenticalImages() throws {
        let image1 = [Int32](repeating: 100, count: 100)
        let image2 = [Int32](repeating: 100, count: 100)

        let mse = J2KErrorMetrics.meanSquaredError(reference: image1, test: image2)
        XCTAssertNotNil(mse)
        XCTAssertEqual(mse!, 0.0, accuracy: 0.0001)
    }

    func testMSEDifferentImages() throws {
        let image1 = [Int32](repeating: 100, count: 100)
        let image2 = [Int32](repeating: 110, count: 100)

        let mse = J2KErrorMetrics.meanSquaredError(reference: image1, test: image2)
        XCTAssertNotNil(mse)
        XCTAssertEqual(mse!, 100.0, accuracy: 0.0001) // (110-100)^2 = 100
    }

    func testMSEDifferentSizes() throws {
        let image1 = [Int32](repeating: 100, count: 100)
        let image2 = [Int32](repeating: 100, count: 50)

        let mse = J2KErrorMetrics.meanSquaredError(reference: image1, test: image2)
        XCTAssertNil(mse)
    }

    func testMSEEmpty() throws {
        let image1: [Int32] = []
        let image2: [Int32] = []

        let mse = J2KErrorMetrics.meanSquaredError(reference: image1, test: image2)
        XCTAssertNotNil(mse)
        XCTAssertEqual(mse!, 0.0)
    }

    func testPSNRIdenticalImages() throws {
        let image1 = [Int32](repeating: 100, count: 100)
        let image2 = [Int32](repeating: 100, count: 100)

        let psnr = J2KErrorMetrics.peakSignalToNoiseRatio(reference: image1, test: image2, bitDepth: 8)
        XCTAssertNotNil(psnr)
        XCTAssertEqual(psnr!, Double.infinity)
    }

    func testPSNRDifferentImages() throws {
        let image1 = [Int32](repeating: 100, count: 100)
        let image2 = [Int32](repeating: 110, count: 100)

        let psnr = J2KErrorMetrics.peakSignalToNoiseRatio(reference: image1, test: image2, bitDepth: 8)
        XCTAssertNotNil(psnr)
        // For bitDepth=8: maxValue=255, MSE=100, PSNR = 10*log10(255^2/100) ≈ 28.13 dB
        XCTAssertGreaterThan(psnr!, 28.0)
        XCTAssertLessThan(psnr!, 29.0)
    }

    func testMAEIdenticalImages() throws {
        let image1 = [Int32](repeating: 100, count: 100)
        let image2 = [Int32](repeating: 100, count: 100)

        let mae = J2KErrorMetrics.maximumAbsoluteError(reference: image1, test: image2)
        XCTAssertNotNil(mae)
        XCTAssertEqual(mae!, 0)
    }

    func testMAEDifferentImages() throws {
        var image1 = [Int32](repeating: 100, count: 100)
        var image2 = [Int32](repeating: 100, count: 100)
        image2[50] = 115  // Maximum error of 15

        let mae = J2KErrorMetrics.maximumAbsoluteError(reference: image1, test: image2)
        XCTAssertNotNil(mae)
        XCTAssertEqual(mae!, 15)
    }

    func testMAENegativeValues() throws {
        let image1: [Int32] = [100, -50, 0, 25]
        let image2: [Int32] = [105, -55, 3, 20]

        let mae = J2KErrorMetrics.maximumAbsoluteError(reference: image1, test: image2)
        XCTAssertNotNil(mae)
        XCTAssertEqual(mae!, 5) // max(|100-105|, |-50-(-55)|, |0-3|, |25-20|) = 5
    }

    func testWithinTolerance() throws {
        let image1 = [Int32](repeating: 100, count: 100)
        var image2 = [Int32](repeating: 100, count: 100)
        image2[50] = 103  // Error of 3

        XCTAssertTrue(J2KErrorMetrics.withinTolerance(reference: image1, test: image2, maxError: 3))
        XCTAssertTrue(J2KErrorMetrics.withinTolerance(reference: image1, test: image2, maxError: 4))
        XCTAssertFalse(J2KErrorMetrics.withinTolerance(reference: image1, test: image2, maxError: 2))
    }

    // MARK: - Test Vector Tests

    func testTestVectorCreation() throws {
        let codestream = Data([0xFF, 0x4F]) // SOC marker
        let vector = J2KTestVector(
            name: "test_vector",
            description: "Test description",
            codestream: codestream,
            referenceImage: nil,
            width: 256,
            height: 256,
            components: 3,
            bitDepth: 8,
            maxAllowableError: 0,
            shouldSucceed: true
        )

        XCTAssertEqual(vector.name, "test_vector")
        XCTAssertEqual(vector.width, 256)
        XCTAssertEqual(vector.height, 256)
        XCTAssertEqual(vector.components, 3)
        XCTAssertEqual(vector.bitDepth, 8)
        XCTAssertEqual(vector.maxAllowableError, 0)
        XCTAssertTrue(vector.shouldSucceed)
    }

    // MARK: - Conformance Validator Tests

    func testValidatePerfectMatch() throws {
        let reference = [Int32](repeating: 100, count: 100)
        let decoded = [Int32](repeating: 100, count: 100)

        let vector = J2KTestVector(
            name: "perfect_match",
            description: "Test perfect match",
            codestream: Data(),
            referenceImage: reference,
            width: 10,
            height: 10,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 0
        )

        let result = J2KConformanceValidator.validate(decoded: decoded, against: vector)
        XCTAssertTrue(result.passed)
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.mse!, 0.0, accuracy: 0.0001)
        XCTAssertEqual(result.psnr!, Double.infinity)
        XCTAssertEqual(result.mae!, 0)
    }

    func testValidateWithinTolerance() throws {
        let reference = [Int32](repeating: 100, count: 100)
        var decoded = [Int32](repeating: 100, count: 100)
        decoded[50] = 102  // Error of 2

        let vector = J2KTestVector(
            name: "within_tolerance",
            description: "Test within tolerance",
            codestream: Data(),
            referenceImage: reference,
            width: 10,
            height: 10,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 2
        )

        let result = J2KConformanceValidator.validate(decoded: decoded, against: vector)
        XCTAssertTrue(result.passed)
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.mae!, 2)
    }

    func testValidateExceedsTolerance() throws {
        let reference = [Int32](repeating: 100, count: 100)
        var decoded = [Int32](repeating: 100, count: 100)
        decoded[50] = 105  // Error of 5

        let vector = J2KTestVector(
            name: "exceeds_tolerance",
            description: "Test exceeds tolerance",
            codestream: Data(),
            referenceImage: reference,
            width: 10,
            height: 10,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 2
        )

        let result = J2KConformanceValidator.validate(decoded: decoded, against: vector)
        XCTAssertFalse(result.passed)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(result.mae!, 5)
    }

    func testValidateSizeMismatch() throws {
        let reference = [Int32](repeating: 100, count: 100)
        let decoded = [Int32](repeating: 100, count: 50)  // Wrong size

        let vector = J2KTestVector(
            name: "size_mismatch",
            description: "Test size mismatch",
            codestream: Data(),
            referenceImage: reference,
            width: 10,
            height: 10,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 0
        )

        let result = J2KConformanceValidator.validate(decoded: decoded, against: vector)
        XCTAssertFalse(result.passed)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertTrue(result.errorMessage!.contains("Size mismatch"))
    }

    func testValidateNoReferenceImage() throws {
        let decoded = [Int32](repeating: 100, count: 100)

        let vector = J2KTestVector(
            name: "no_reference",
            description: "Test with no reference",
            codestream: Data(),
            referenceImage: nil,  // No reference
            width: 10,
            height: 10,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 0
        )

        let result = J2KConformanceValidator.validate(decoded: decoded, against: vector)
        XCTAssertFalse(result.passed)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertTrue(result.errorMessage!.contains("No reference image"))
    }

    func testRunTestSuite() throws {
        let reference1 = [Int32](repeating: 100, count: 100)
        let reference2 = [Int32](repeating: 50, count: 100)

        let vectors = [
            J2KTestVector(
                name: "test1",
                description: "First test",
                codestream: Data([0x01]),
                referenceImage: reference1,
                width: 10,
                height: 10,
                components: 1,
                bitDepth: 8,
                maxAllowableError: 0
            ),
            J2KTestVector(
                name: "test2",
                description: "Second test",
                codestream: Data([0x02]),
                referenceImage: reference2,
                width: 10,
                height: 10,
                components: 1,
                bitDepth: 8,
                maxAllowableError: 0
            )
        ]

        // Mock decoder that returns the reference data
        let decoder: (Data) throws -> [Int32] = { data in
            if data == Data([0x01]) {
                return reference1
            } else {
                return reference2
            }
        }

        let results = J2KConformanceValidator.runTestSuite(vectors: vectors, decoder: decoder)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.passed })
    }

    func testGenerateReport() throws {
        let reference = [Int32](repeating: 100, count: 100)
        var decoded1 = reference
        var decoded2 = reference
        decoded2[50] = 105  // Error in second test

        let vector1 = J2KTestVector(
            name: "pass_test",
            description: "Should pass",
            codestream: Data(),
            referenceImage: reference,
            width: 10,
            height: 10,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 0
        )

        let vector2 = J2KTestVector(
            name: "fail_test",
            description: "Should fail",
            codestream: Data(),
            referenceImage: reference,
            width: 10,
            height: 10,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 2
        )

        let results = [
            J2KConformanceValidator.validate(decoded: decoded1, against: vector1),
            J2KConformanceValidator.validate(decoded: decoded2, against: vector2)
        ]

        let report = J2KConformanceValidator.generateReport(results: results)
        XCTAssertTrue(report.contains("1/2 tests passed"))
        XCTAssertTrue(report.contains("fail_test"))
    }

    // MARK: - HTJ2K Test Vector Generator Tests

    func testHTJ2KTestVectorGeneratorSolidPattern() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 32,
            height: 32,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 128)
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels.count, 32 * 32 * 1)
        XCTAssertTrue(pixels.allSatisfy { $0 == 128 }, "All pixels should be 128")
    }

    func testHTJ2KTestVectorGeneratorGradient() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 16,
            height: 16,
            components: 1,
            bitDepth: 8,
            pattern: .gradient
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels.count, 16 * 16 * 1)
        // Check that gradient increases
        XCTAssertTrue(pixels.first! <= pixels.last!, "Gradient should increase")
    }

    func testHTJ2KTestVectorGeneratorCheckerboard() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 16,
            height: 16,
            components: 1,
            bitDepth: 8,
            pattern: .checkerboard(squareSize: 4)
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels.count, 16 * 16 * 1)
        // Check that we have both 0 and 255 values
        XCTAssertTrue(pixels.contains(0), "Should contain black squares")
        XCTAssertTrue(pixels.contains(255), "Should contain white squares")
    }

    func testHTJ2KTestVectorGeneratorRandomNoise() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 32,
            height: 32,
            components: 1,
            bitDepth: 8,
            pattern: .randomNoise(seed: 12345)
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels.count, 32 * 32 * 1)
        // Check that we have varied values (not all the same)
        let uniqueValues = Set(pixels)
        XCTAssertGreaterThan(uniqueValues.count, 10, "Should have varied pixel values")
    }

    func testHTJ2KTestVectorGeneratorRandomNoiseReproducibility() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 16,
            height: 16,
            components: 1,
            bitDepth: 8,
            pattern: .randomNoise(seed: 67890)
        )

        let pixels1 = HTJ2KTestVectorGenerator.generateImage(config: config)
        let pixels2 = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels1, pixels2, "Same seed should produce same random data")
    }

    func testHTJ2KTestVectorGeneratorFrequencySweep() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 32,
            height: 32,
            components: 1,
            bitDepth: 8,
            pattern: .frequencySweep
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels.count, 32 * 32 * 1)
        // Check that we have varied values
        let uniqueValues = Set(pixels)
        XCTAssertGreaterThan(uniqueValues.count, 5, "Should have varied pixel values")
    }

    func testHTJ2KTestVectorGeneratorEdges() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 32,
            height: 32,
            components: 1,
            bitDepth: 8,
            pattern: .edges
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels.count, 32 * 32 * 1)
        // Check that we have both 0 and 255 values (edges and non-edges)
        XCTAssertTrue(pixels.contains(0), "Should contain non-edge pixels")
        XCTAssertTrue(pixels.contains(255), "Should contain edge pixels")
    }

    func testHTJ2KTestVectorGeneratorMultiComponent() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 16,
            height: 16,
            components: 3,
            bitDepth: 8,
            pattern: .solid(value: 100)
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)

        XCTAssertEqual(pixels.count, 16 * 16 * 3, "Should have 3 components per pixel")
        XCTAssertTrue(pixels.allSatisfy { $0 == 100 }, "All component values should be 100")
    }

    func testHTJ2KTestVectorGeneratorBitDepthClamping() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 8,
            height: 8,
            components: 1,
            bitDepth: 4,
            pattern: .solid(value: 20)
        )

        let pixels = HTJ2KTestVectorGenerator.generateImage(config: config)
        let maxValue = (1 << 4) - 1  // 15 for 4-bit

        XCTAssertTrue(pixels.allSatisfy { $0 <= maxValue }, "Values should be clamped to bit depth")
    }

    func testHTJ2KCreateTestVector() throws {
        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 16,
            height: 16,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 128)
        )

        let vector = HTJ2KTestVectorGenerator.createTestVector(
            name: "test_solid_128",
            description: "Solid gray image at value 128",
            config: config
        )

        XCTAssertEqual(vector.name, "test_solid_128")
        XCTAssertEqual(vector.width, 16)
        XCTAssertEqual(vector.height, 16)
        XCTAssertEqual(vector.components, 1)
        XCTAssertEqual(vector.bitDepth, 8)
        XCTAssertNotNil(vector.referenceImage)
        XCTAssertEqual(vector.referenceImage?.count, 16 * 16 * 1)
        XCTAssertTrue(vector.shouldSucceed)
    }

    func testHTJ2KTestVectorLosslessErrorTolerance() throws {
        let losslessConfig = HTJ2KTestVectorGenerator.Configuration(
            width: 8,
            height: 8,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 100),
            lossless: true
        )

        let losslessVector = HTJ2KTestVectorGenerator.createTestVector(
            name: "lossless_test",
            description: "Lossless test",
            config: losslessConfig
        )

        XCTAssertEqual(losslessVector.maxAllowableError, 0, "Lossless should have zero error tolerance")
    }

    func testHTJ2KTestVectorLossyErrorTolerance() throws {
        let lossyConfig = HTJ2KTestVectorGenerator.Configuration(
            width: 8,
            height: 8,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 100),
            lossless: false,
            quality: 0.9
        )

        let lossyVector = HTJ2KTestVectorGenerator.createTestVector(
            name: "lossy_test",
            description: "Lossy test",
            config: lossyConfig
        )

        XCTAssertGreaterThan(lossyVector.maxAllowableError, 0, "Lossy should allow some error")
    }

    // MARK: - HTJ2K Conformance Test Harness Tests

    func testHTJ2KConformanceTestHarnessInitialization() throws {
        let harness = HTJ2KConformanceTestHarness()
        XCTAssertTrue(harness.rules.requireCAPMarker)
        XCTAssertTrue(harness.rules.requireCPFMarker)
        XCTAssertTrue(harness.rules.validateHTSetParameters)
        XCTAssertFalse(harness.rules.allowMixedMode)
        XCTAssertNil(harness.rules.maxProcessingTime)
    }

    func testHTJ2KConformanceTestHarnessCustomRules() throws {
        let rules = HTJ2KConformanceTestHarness.ValidationRules(
            requireCAPMarker: false,
            requireCPFMarker: true,
            validateHTSetParameters: false,
            allowMixedMode: true,
            maxProcessingTime: 1.0
        )
        let harness = HTJ2KConformanceTestHarness(rules: rules)

        XCTAssertFalse(harness.rules.requireCAPMarker)
        XCTAssertTrue(harness.rules.requireCPFMarker)
        XCTAssertFalse(harness.rules.validateHTSetParameters)
        XCTAssertTrue(harness.rules.allowMixedMode)
        XCTAssertEqual(harness.rules.maxProcessingTime, 1.0)
    }

    func testHTJ2KValidateCodestreamStructureEmpty() throws {
        let harness = HTJ2KConformanceTestHarness()
        let emptyData = Data()

        let errors = harness.validateCodestreamStructure(emptyData)
        XCTAssertFalse(errors.isEmpty, "Should have errors for empty codestream")
        XCTAssertTrue(errors.contains("Codestream too short"))
    }

    func testHTJ2KValidateCodestreamStructureInvalidSOC() throws {
        let harness = HTJ2KConformanceTestHarness()
        var data = Data()
        data.append(0x00)  // Invalid SOC
        data.append(0x00)

        let errors = harness.validateCodestreamStructure(data)
        XCTAssertTrue(errors.contains("Missing or invalid SOC marker"))
    }

    func testHTJ2KValidateCodestreamStructureValidSOC() throws {
        let harness = HTJ2KConformanceTestHarness()
        var data = Data()
        data.append(0xFF)  // SOC marker
        data.append(0x4F)

        let errors = harness.validateCodestreamStructure(data)
        // Should have errors about missing markers but not about SOC
        XCTAssertFalse(errors.contains("Missing or invalid SOC marker"))
    }

    func testHTJ2KValidateCodestreamStructureMissingCAP() throws {
        let rules = HTJ2KConformanceTestHarness.ValidationRules(requireCAPMarker: true)
        let harness = HTJ2KConformanceTestHarness(rules: rules)

        var data = Data()
        data.append(0xFF)  // SOC
        data.append(0x4F)
        data.append(0xFF)  // COD marker
        data.append(0x52)
        data.append(0x00)  // Length
        data.append(0x0C)

        let errors = harness.validateCodestreamStructure(data)
        XCTAssertTrue(errors.contains("Missing required CAP marker for HTJ2K"))
    }

    func testHTJ2KValidateWithTestVector() throws {
        let harness = HTJ2KConformanceTestHarness()

        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 8,
            height: 8,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 100),
            lossless: true
        )

        let vector = HTJ2KTestVectorGenerator.createTestVector(
            name: "test_vector",
            description: "Test validation",
            config: config
        )

        // Create a simple codestream with SOC marker
        var codestream = Data()
        codestream.append(0xFF)
        codestream.append(0x4F)

        let decoded = vector.referenceImage ?? []
        let result = harness.validate(
            decoded: decoded,
            against: vector,
            codestream: codestream,
            processingTime: 0.1
        )

        XCTAssertNotNil(result.conformanceResult)
        XCTAssertNotNil(result.processingTime)
        XCTAssertEqual(result.processingTime, 0.1)
    }

    func testHTJ2KValidateProcessingTimeExceeded() throws {
        let rules = HTJ2KConformanceTestHarness.ValidationRules(maxProcessingTime: 0.5)
        let harness = HTJ2KConformanceTestHarness(rules: rules)

        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 8,
            height: 8,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 100)
        )

        let vector = HTJ2KTestVectorGenerator.createTestVector(
            name: "test_time",
            description: "Test time limit",
            config: config
        )

        var codestream = Data()
        codestream.append(0xFF)
        codestream.append(0x4F)

        let decoded = vector.referenceImage ?? []
        let result = harness.validate(
            decoded: decoded,
            against: vector,
            codestream: codestream,
            processingTime: 1.0  // Exceeds limit
        )

        XCTAssertTrue(result.htValidationErrors.contains(where: { $0.contains("Processing time") }))
    }

    func testHTJ2KGenerateReport() throws {
        let harness = HTJ2KConformanceTestHarness()

        let config = HTJ2KTestVectorGenerator.Configuration(
            width: 8,
            height: 8,
            components: 1,
            bitDepth: 8,
            pattern: .solid(value: 100)
        )

        let vector = HTJ2KTestVectorGenerator.createTestVector(
            name: "test_report",
            description: "Test report generation",
            config: config
        )

        var codestream = Data()
        codestream.append(0xFF)
        codestream.append(0x4F)

        let decoded = vector.referenceImage ?? []
        let result = harness.validate(
            decoded: decoded,
            against: vector,
            codestream: codestream
        )

        let report = HTJ2KConformanceTestHarness.generateReport(results: [result])

        XCTAssertTrue(report.contains("HTJ2K Conformance Test Report"))
        XCTAssertTrue(report.contains("test_report"))
    }

    func testHTJ2KCreateStandardTestVectors() throws {
        let vectors = HTJ2KConformanceTestHarness.createStandardTestVectors()

        XCTAssertEqual(vectors.count, 5, "Should create 5 standard test vectors")

        // Check that we have different types
        let names = vectors.map { $0.name }
        XCTAssertTrue(names.contains(where: { $0.contains("lossless") }))
        XCTAssertTrue(names.contains(where: { $0.contains("lossy") }))
        XCTAssertTrue(names.contains(where: { $0.contains("edges") }))
        XCTAssertTrue(names.contains(where: { $0.contains("noise") }))
        XCTAssertTrue(names.contains(where: { $0.contains("solid") }))

        // Verify all vectors have reference images
        XCTAssertTrue(vectors.allSatisfy { $0.referenceImage != nil })
    }

    // MARK: - HTJ2K Test Vector Parser Tests

    func testHTJ2KTestVectorParserBasic() throws {
        let text = """
        NAME: test_basic
        DESCRIPTION: Basic test vector
        WIDTH: 32
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: solid(128)
        LOSSLESS: true
        HTJ2K: true
        """

        let vector = try HTJ2KTestVectorParser.parse(text)

        XCTAssertEqual(vector.name, "test_basic")
        XCTAssertEqual(vector.description, "Basic test vector")
        XCTAssertEqual(vector.width, 32)
        XCTAssertEqual(vector.height, 32)
        XCTAssertEqual(vector.components, 1)
        XCTAssertEqual(vector.bitDepth, 8)
        XCTAssertNotNil(vector.referenceImage)
    }

    func testHTJ2KTestVectorParserWithComments() throws {
        let text = """
        # This is a comment
        NAME: test_comments
        # Another comment
        DESCRIPTION: Test with comments
        WIDTH: 16
        HEIGHT: 16
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: gradient
        """

        let vector = try HTJ2KTestVectorParser.parse(text)
        XCTAssertEqual(vector.name, "test_comments")
    }

    func testHTJ2KTestVectorParserCheckerboard() throws {
        let text = """
        NAME: test_checkerboard
        DESCRIPTION: Checkerboard pattern
        WIDTH: 32
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: checkerboard(8)
        """

        let vector = try HTJ2KTestVectorParser.parse(text)
        XCTAssertEqual(vector.name, "test_checkerboard")
        XCTAssertNotNil(vector.referenceImage)
    }

    func testHTJ2KTestVectorParserRandomNoise() throws {
        let text = """
        NAME: test_random
        DESCRIPTION: Random noise pattern
        WIDTH: 64
        HEIGHT: 64
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: randomnoise(12345)
        """

        let vector = try HTJ2KTestVectorParser.parse(text)
        XCTAssertEqual(vector.name, "test_random")
    }

    func testHTJ2KTestVectorParserGradient() throws {
        let text = """
        NAME: test_gradient
        DESCRIPTION: Gradient pattern
        WIDTH: 64
        HEIGHT: 64
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: gradient
        """

        let vector = try HTJ2KTestVectorParser.parse(text)
        XCTAssertEqual(vector.name, "test_gradient")
    }

    func testHTJ2KTestVectorParserFrequencySweep() throws {
        let text = """
        NAME: test_frequency
        DESCRIPTION: Frequency sweep pattern
        WIDTH: 32
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: frequencysweep
        """

        let vector = try HTJ2KTestVectorParser.parse(text)
        XCTAssertEqual(vector.name, "test_frequency")
    }

    func testHTJ2KTestVectorParserEdges() throws {
        let text = """
        NAME: test_edges
        DESCRIPTION: Edge pattern
        WIDTH: 32
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: edges
        """

        let vector = try HTJ2KTestVectorParser.parse(text)
        XCTAssertEqual(vector.name, "test_edges")
    }

    func testHTJ2KTestVectorParserMissingField() throws {
        let text = """
        NAME: test_missing
        WIDTH: 32
        HEIGHT: 32
        """

        XCTAssertThrowsError(try HTJ2KTestVectorParser.parse(text)) { error in
            guard case HTJ2KTestVectorParser.ParseError.missingField = error else {
                XCTFail("Expected missingField error")
                return
            }
        }
    }

    func testHTJ2KTestVectorParserInvalidWidth() throws {
        let text = """
        NAME: test_invalid
        DESCRIPTION: Invalid width
        WIDTH: invalid
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: solid(100)
        """

        XCTAssertThrowsError(try HTJ2KTestVectorParser.parse(text)) { error in
            guard case HTJ2KTestVectorParser.ParseError.invalidValue = error else {
                XCTFail("Expected invalidValue error")
                return
            }
        }
    }

    func testHTJ2KTestVectorParserUnknownPattern() throws {
        let text = """
        NAME: test_unknown
        DESCRIPTION: Unknown pattern
        WIDTH: 32
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: unknown_pattern
        """

        XCTAssertThrowsError(try HTJ2KTestVectorParser.parse(text)) { error in
            guard case HTJ2KTestVectorParser.ParseError.unknownPattern = error else {
                XCTFail("Expected unknownPattern error")
                return
            }
        }
    }

    func testHTJ2KTestVectorParserMultiple() throws {
        let text = """
        NAME: test1
        DESCRIPTION: First test
        WIDTH: 16
        HEIGHT: 16
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: solid(100)
        ---
        NAME: test2
        DESCRIPTION: Second test
        WIDTH: 32
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: gradient
        """

        let vectors = try HTJ2KTestVectorParser.parseMultiple(text)

        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0].name, "test1")
        XCTAssertEqual(vectors[1].name, "test2")
    }

    func testHTJ2KTestVectorParserValidate() throws {
        let validText = """
        NAME: test_valid
        DESCRIPTION: Valid test
        WIDTH: 32
        HEIGHT: 32
        COMPONENTS: 1
        BITDEPTH: 8
        PATTERN: solid(128)
        """

        let invalidText = """
        NAME: test_invalid
        WIDTH: invalid_value
        """

        XCTAssertTrue(HTJ2KTestVectorParser.validate(validText))
        XCTAssertFalse(HTJ2KTestVectorParser.validate(invalidText))
    }

    func testHTJ2KTestVectorParserLossyQuality() throws {
        let text = """
        NAME: test_lossy
        DESCRIPTION: Lossy compression test
        WIDTH: 64
        HEIGHT: 64
        COMPONENTS: 3
        BITDEPTH: 8
        PATTERN: gradient
        LOSSLESS: false
        QUALITY: 0.85
        HTJ2K: true
        """

        let vector = try HTJ2KTestVectorParser.parse(text)

        XCTAssertEqual(vector.name, "test_lossy")
        XCTAssertEqual(vector.components, 3)
        XCTAssertGreaterThan(vector.maxAllowableError, 0, "Lossy should allow some error")
    }
}
