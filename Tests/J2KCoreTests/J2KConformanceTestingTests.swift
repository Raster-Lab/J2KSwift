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
}
