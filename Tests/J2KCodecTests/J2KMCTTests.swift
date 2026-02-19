// J2KMCTTests.swift
// J2KSwift
//
// Tests for Multi-Component Transform (MCT) implementation
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

#if canImport(J2KAccelerate)
@testable import J2KAccelerate
#endif

final class J2KMCTTests: XCTestCase {
    
    // MARK: - Matrix Creation and Validation Tests
    
    func testMatrixCreation() throws {
        // Test valid 3×3 matrix
        let matrix = try J2KMCTMatrix(
            size: 3,
            coefficients: [
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0
            ]
        )
        
        XCTAssertEqual(matrix.size, 3)
        XCTAssertEqual(matrix.coefficients.count, 9)
        XCTAssertEqual(matrix.precision, .floatingPoint)
    }
    
    func testMatrixCreationInvalidSize() {
        // Test zero size
        XCTAssertThrowsError(try J2KMCTMatrix(size: 0, coefficients: [])) { error in
            if case J2KError.invalidParameter(let msg) = error {
                XCTAssertTrue(msg.contains("positive"))
            } else {
                XCTFail("Expected invalidParameter error")
            }
        }
    }
    
    func testMatrixCreationWrongCoefficientCount() {
        // Test mismatched coefficient count
        XCTAssertThrowsError(try J2KMCTMatrix(size: 3, coefficients: [1.0, 2.0])) { error in
            if case J2KError.invalidParameter(let msg) = error {
                XCTAssertTrue(msg.contains("count"))
            } else {
                XCTFail("Expected invalidParameter error")
            }
        }
    }
    
    func testIdentityMatrix() {
        // Test identity matrix creation
        let identity3 = J2KMCTMatrix.identity(size: 3)
        XCTAssertEqual(identity3.size, 3)
        XCTAssertEqual(identity3.coefficients[0], 1.0)
        XCTAssertEqual(identity3.coefficients[4], 1.0)
        XCTAssertEqual(identity3.coefficients[8], 1.0)
        XCTAssertEqual(identity3.coefficients[1], 0.0)
        
        let identity4 = J2KMCTMatrix.identity(size: 4)
        XCTAssertEqual(identity4.size, 4)
    }
    
    func testMatrixInverse() throws {
        // Create a simple invertible matrix
        let matrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                2.0, 0.0,
                0.0, 3.0
            ]
        )
        
        let inverse = try matrix.inverse()
        XCTAssertEqual(inverse.size, 2)
        XCTAssertEqual(inverse.coefficients[0], 0.5, accuracy: 1e-10)
        XCTAssertEqual(inverse.coefficients[3], 1.0 / 3.0, accuracy: 1e-10)
    }
    
    func testMatrixInverseSingular() {
        // Test singular matrix (non-invertible)
        let singular = try! J2KMCTMatrix(
            size: 2,
            coefficients: [
                1.0, 2.0,
                2.0, 4.0
            ]
        )
        
        XCTAssertThrowsError(try singular.inverse()) { error in
            if case J2KError.invalidParameter(let msg) = error {
                XCTAssertTrue(msg.contains("singular"))
            } else {
                XCTFail("Expected invalidParameter error")
            }
        }
    }
    
    func testMatrixTranspose() throws {
        let matrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                1.0, 2.0,
                3.0, 4.0
            ]
        )
        
        let transposed = matrix.transpose()
        XCTAssertEqual(transposed.coefficients[0], 1.0)
        XCTAssertEqual(transposed.coefficients[1], 3.0)
        XCTAssertEqual(transposed.coefficients[2], 2.0)
        XCTAssertEqual(transposed.coefficients[3], 4.0)
    }
    
    func testMatrixReconstructibility() throws {
        // Test perfect reconstruction validation
        let goodMatrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                1.0, 0.5,
                0.0, 1.0
            ]
        )
        XCTAssertTrue(goodMatrix.validateReconstructibility())
        
        // Singular matrix should fail
        let badMatrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                1.0, 1.0,
                1.0, 1.0
            ]
        )
        XCTAssertFalse(badMatrix.validateReconstructibility())
    }
    
    // MARK: - Forward Transform Tests
    
    func testForwardTransformIdentity() throws {
        let mct = J2KMCT()
        let identity = J2KMCTMatrix.identity(size: 3)
        
        let input: [[Double]] = [
            [1.0, 2.0, 3.0, 4.0],
            [5.0, 6.0, 7.0, 8.0],
            [9.0, 10.0, 11.0, 12.0]
        ]
        
        let output = try mct.forwardTransform(components: input, matrix: identity)
        
        // Identity transform should produce identical output
        XCTAssertEqual(output.count, 3)
        for i in 0..<3 {
            XCTAssertEqual(output[i], input[i])
        }
    }
    
    func testForwardTransformSimple() throws {
        let mct = J2KMCT()
        
        // Simple 2×2 transform
        let matrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                1.0, 1.0,
                1.0, -1.0
            ]
        )
        
        let input: [[Double]] = [
            [2.0, 4.0],
            [1.0, 3.0]
        ]
        
        let output = try mct.forwardTransform(components: input, matrix: matrix)
        
        // Expected: [3, 7] and [1, 1]
        XCTAssertEqual(output[0][0], 3.0, accuracy: 1e-10)
        XCTAssertEqual(output[0][1], 7.0, accuracy: 1e-10)
        XCTAssertEqual(output[1][0], 1.0, accuracy: 1e-10)
        XCTAssertEqual(output[1][1], 1.0, accuracy: 1e-10)
    }
    
    func testForwardTransformRGBToYCbCr() throws {
        let mct = J2KMCT()
        
        // Test predefined RGB to YCbCr matrix
        let input: [[Double]] = [
            [255.0, 0.0, 0.0],     // Red
            [0.0, 255.0, 0.0],     // Green
            [0.0, 0.0, 255.0]      // Blue
        ]
        
        let output = try mct.forwardTransform(
            components: input,
            matrix: J2KMCTMatrix.rgbToYCbCr
        )
        
        // Check that transform produces reasonable YCbCr values
        XCTAssertGreaterThan(output[0][0], 0.0) // Y from red
        XCTAssertGreaterThan(output[0][1], 0.0) // Y from green
        XCTAssertGreaterThan(output[0][2], 0.0) // Y from blue
    }
    
    func testForwardTransformEmptyInput() {
        let mct = J2KMCT()
        let matrix = J2KMCTMatrix.identity(size: 3)
        
        XCTAssertThrowsError(try mct.forwardTransform(components: [[Double]](), matrix: matrix))
    }
    
    func testForwardTransformMismatchedSize() throws {
        let mct = J2KMCT()
        let matrix = J2KMCTMatrix.identity(size: 3)
        
        let input: [[Double]] = [
            [1.0, 2.0],
            [3.0, 4.0]
        ]
        
        XCTAssertThrowsError(try mct.forwardTransform(components: input, matrix: matrix))
    }
    
    func testForwardTransformMismatchedLengths() throws {
        let mct = J2KMCT()
        let matrix = J2KMCTMatrix.identity(size: 3)
        
        let input: [[Double]] = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0],
            [6.0, 7.0, 8.0]
        ]
        
        XCTAssertThrowsError(try mct.forwardTransform(components: input, matrix: matrix))
    }
    
    // MARK: - Inverse Transform Tests
    
    func testInverseTransformRoundTrip() throws {
        let mct = J2KMCT()
        
        let matrix = try J2KMCTMatrix(
            size: 3,
            coefficients: [
                1.0, 0.5, 0.0,
                0.0, 1.0, 0.5,
                0.0, 0.0, 1.0
            ]
        )
        
        let inverse = try matrix.inverse()
        
        let input: [[Double]] = [
            [1.0, 2.0, 3.0, 4.0],
            [5.0, 6.0, 7.0, 8.0],
            [9.0, 10.0, 11.0, 12.0]
        ]
        
        let transformed = try mct.forwardTransform(components: input, matrix: matrix)
        let reconstructed = try mct.inverseTransform(components: transformed, matrix: inverse)
        
        // Check round-trip accuracy
        for i in 0..<3 {
            for j in 0..<4 {
                XCTAssertEqual(reconstructed[i][j], input[i][j], accuracy: 1e-10)
            }
        }
    }
    
    func testInverseTransformYCbCrToRGB() throws {
        let mct = J2KMCT()
        
        let input: [[Double]] = [
            [128.0, 64.0, 192.0],
            [255.0, 128.0, 32.0],
            [0.0, 192.0, 64.0]
        ]
        
        // Forward: RGB → YCbCr
        let ycbcr = try mct.forwardTransform(
            components: input,
            matrix: J2KMCTMatrix.rgbToYCbCr
        )
        
        // Inverse: YCbCr → RGB
        let rgb = try mct.inverseTransform(
            components: ycbcr,
            matrix: J2KMCTMatrix.yCbCrToRGB
        )
        
        // Check round-trip
        for i in 0..<3 {
            for j in 0..<3 {
                XCTAssertEqual(rgb[i][j], input[i][j], accuracy: 1e-6)
            }
        }
    }
    
    // MARK: - Integer Transform Tests
    
    func testForwardTransformInteger() throws {
        let mct = J2KMCT()
        
        let matrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                1.0, 1.0,
                1.0, -1.0
            ],
            precision: .integer
        )
        
        let input: [[Int32]] = [
            [10, 20, 30],
            [5, 15, 25]
        ]
        
        let output = try mct.forwardTransformInteger(components: input, matrix: matrix)
        
        XCTAssertEqual(output[0][0], 15)
        XCTAssertEqual(output[0][1], 35)
        XCTAssertEqual(output[0][2], 55)
        XCTAssertEqual(output[1][0], 5)
        XCTAssertEqual(output[1][1], 5)
        XCTAssertEqual(output[1][2], 5)
    }
    
    func testInverseTransformIntegerRoundTrip() throws {
        let mct = J2KMCT()
        
        let matrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                2.0, 0.0,
                0.0, 2.0
            ],
            precision: .integer
        )
        
        let inverse = try J2KMCTMatrix(
            size: 2,
            coefficients: [
                0.5, 0.0,
                0.0, 0.5
            ],
            precision: .integer
        )
        
        let input: [[Int32]] = [
            [100, 200, 300],
            [50, 150, 250]
        ]
        
        let transformed = try mct.forwardTransformInteger(components: input, matrix: matrix)
        let reconstructed = try mct.inverseTransformInteger(components: transformed, matrix: inverse)
        
        for i in 0..<2 {
            for j in 0..<3 {
                XCTAssertEqual(reconstructed[i][j], input[i][j])
            }
        }
    }
    
    // MARK: - Component-Based Transform Tests
    
    func testComponentBasedTransform() throws {
        let mct = J2KMCT()
        
        // Create test components
        let comp0 = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 2,
            height: 2,
            data: Data([128, 64, 192, 255])
        )
        
        let comp1 = J2KComponent(
            index: 1,
            bitDepth: 8,
            signed: false,
            width: 2,
            height: 2,
            data: Data([255, 192, 128, 64])
        )
        
        let comp2 = J2KComponent(
            index: 2,
            bitDepth: 8,
            signed: false,
            width: 2,
            height: 2,
            data: Data([0, 64, 128, 192])
        )
        
        let components = [comp0, comp1, comp2]
        
        // Apply transform
        let matrix = J2KMCTMatrix.identity3
        let transformed = try mct.forwardTransform(components: components, matrix: matrix)
        
        XCTAssertEqual(transformed.count, 3)
        XCTAssertEqual(transformed[0].width, 2)
        XCTAssertEqual(transformed[0].height, 2)
    }
    
    func testComponentBasedTransformMismatchedDimensions() throws {
        let mct = J2KMCT()
        
        let comp0 = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 2,
            height: 2,
            data: Data([1, 2, 3, 4])
        )
        
        let comp1 = J2KComponent(
            index: 1,
            bitDepth: 8,
            signed: false,
            width: 3,
            height: 2,
            data: Data([1, 2, 3, 4, 5, 6])
        )
        
        let components = [comp0, comp1]
        let matrix = try J2KMCTMatrix(size: 2, coefficients: [1, 0, 0, 1])
        
        XCTAssertThrowsError(try mct.forwardTransform(components: components, matrix: matrix))
    }
    
    // MARK: - Predefined Matrix Tests
    
    func testPredefinedRGBToYCbCrMatrix() {
        let matrix = J2KMCTMatrix.rgbToYCbCr
        XCTAssertEqual(matrix.size, 3)
        XCTAssertEqual(matrix.precision, .floatingPoint)
        XCTAssertTrue(matrix.validateReconstructibility())
    }
    
    func testPredefinedYCbCrToRGBMatrix() {
        let matrix = J2KMCTMatrix.yCbCrToRGB
        XCTAssertEqual(matrix.size, 3)
        XCTAssertTrue(matrix.validateReconstructibility())
    }
    
    func testPredefinedAveraging3Matrix() {
        let matrix = J2KMCTMatrix.averaging3
        XCTAssertEqual(matrix.size, 3)
        XCTAssertTrue(matrix.validateReconstructibility())
    }
    
    // MARK: - Accelerated MCT Tests
    
    #if canImport(J2KAccelerate)
    
    func testAcceleratedAvailability() {
        #if canImport(Accelerate)
        XCTAssertTrue(J2KAcceleratedMCT.isAvailable)
        #else
        XCTAssertFalse(J2KAcceleratedMCT.isAvailable)
        #endif
    }
    
    #if canImport(Accelerate)
    
    func testAcceleratedForwardTransform() throws {
        let accelerated = J2KAcceleratedMCT()
        
        let matrix = try J2KMCTMatrix(
            size: 3,
            coefficients: [
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0
            ]
        )
        
        let input: [[Double]] = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0]
        ]
        
        let output = try accelerated.forwardTransform(components: input, matrix: matrix)
        
        XCTAssertEqual(output.count, 3)
        for i in 0..<3 {
            XCTAssertEqual(output[i], input[i])
        }
    }
    
    func testAccelerated3x3FastPath() throws {
        let accelerated = J2KAcceleratedMCT()
        
        let input: [[Double]] = [
            [255.0, 128.0, 64.0],
            [0.0, 128.0, 255.0],
            [128.0, 64.0, 192.0]
        ]
        
        let output = try accelerated.forwardTransform3x3(
            components: input,
            matrix: J2KMCTMatrix.rgbToYCbCr
        )
        
        XCTAssertEqual(output.count, 3)
        XCTAssertEqual(output[0].count, 3)
    }
    
    func testAccelerated4x4FastPath() throws {
        let accelerated = J2KAcceleratedMCT()
        
        let matrix = J2KMCTMatrix.identity4
        
        let input: [[Double]] = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0],
            [10.0, 11.0, 12.0]
        ]
        
        let output = try accelerated.forwardTransform4x4(components: input, matrix: matrix)
        
        XCTAssertEqual(output.count, 4)
        for i in 0..<4 {
            XCTAssertEqual(output[i], input[i])
        }
    }
    
    func testAcceleratedIntegerTransform() throws {
        let accelerated = J2KAcceleratedMCT()
        
        let matrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [1.0, 1.0, 1.0, -1.0],
            precision: .integer
        )
        
        let input: [[Int32]] = [
            [10, 20],
            [5, 15]
        ]
        
        let output = try accelerated.forwardTransformInteger(components: input, matrix: matrix)
        
        XCTAssertEqual(output[0][0], 15)
        XCTAssertEqual(output[1][0], 5)
    }
    
    func testAcceleratedRoundTrip() throws {
        let accelerated = J2KAcceleratedMCT()
        let mct = J2KMCT()
        
        let matrix = J2KMCTMatrix.rgbToYCbCr
        let inverse = J2KMCTMatrix.yCbCrToRGB
        
        let input: [[Double]] = [
            Array(repeating: 128.0, count: 1000),
            Array(repeating: 64.0, count: 1000),
            Array(repeating: 192.0, count: 1000)
        ]
        
        // Accelerated path
        let transformed = try accelerated.forwardTransform(components: input, matrix: matrix)
        let reconstructed = try accelerated.forwardTransform(components: transformed, matrix: inverse)
        
        // Check accuracy
        for i in 0..<3 {
            for j in 0..<1000 {
                XCTAssertEqual(reconstructed[i][j], input[i][j], accuracy: 1e-6)
            }
        }
    }
    
    func testAcceleratedVsScalarConsistency() throws {
        let accelerated = J2KAcceleratedMCT()
        let scalar = J2KMCT()
        
        let matrix = J2KMCTMatrix.averaging3
        
        let input: [[Double]] = [
            [100.0, 150.0, 200.0],
            [50.0, 75.0, 125.0],
            [25.0, 50.0, 100.0]
        ]
        
        let accelOutput = try accelerated.forwardTransform(components: input, matrix: matrix)
        let scalarOutput = try scalar.forwardTransform(components: input, matrix: matrix)
        
        // Results should be very close
        for i in 0..<3 {
            for j in 0..<3 {
                XCTAssertEqual(accelOutput[i][j], scalarOutput[i][j], accuracy: 1e-6)
            }
        }
    }
    
    func testOptimalBatchSize() {
        let batch1 = J2KAcceleratedMCT.optimalBatchSize(sampleCount: 100, componentCount: 3)
        XCTAssertGreaterThan(batch1, 0)
        XCTAssertLessThanOrEqual(batch1, 100)
        
        let batch2 = J2KAcceleratedMCT.optimalBatchSize(sampleCount: 100000, componentCount: 3)
        XCTAssertGreaterThan(batch2, 256)
        XCTAssertLessThanOrEqual(batch2, 2048)
    }
    
    #endif // canImport(Accelerate)
    
    #endif // canImport(J2KAccelerate)
    
    // MARK: - Performance Tests
    
    func testPerformanceScalarTransform() throws {
        let mct = J2KMCT()
        let matrix = J2KMCTMatrix.rgbToYCbCr
        
        let sampleCount = 1024 * 1024
        let input: [[Double]] = [
            Array(repeating: 128.0, count: sampleCount),
            Array(repeating: 64.0, count: sampleCount),
            Array(repeating: 192.0, count: sampleCount)
        ]
        
        measure {
            _ = try? mct.forwardTransform(components: input, matrix: matrix)
        }
    }
    
    #if canImport(J2KAccelerate) && canImport(Accelerate)
    
    func testPerformanceAcceleratedTransform() throws {
        let accelerated = J2KAcceleratedMCT()
        let matrix = J2KMCTMatrix.rgbToYCbCr
        
        let sampleCount = 1024 * 1024
        let input: [[Double]] = [
            Array(repeating: 128.0, count: sampleCount),
            Array(repeating: 64.0, count: sampleCount),
            Array(repeating: 192.0, count: sampleCount)
        ]
        
        measure {
            _ = try? accelerated.forwardTransform(components: input, matrix: matrix)
        }
    }
    
    #endif
    
    // MARK: - MCT Marker Segment Tests
    
    func testMCTMarkerCreation() throws {
        let matrix = J2KMCTMatrix.rgbToYCbCr
        let marker = try J2KMCTMarkerSegment.from(matrix: matrix, index: 0)
        
        XCTAssertEqual(marker.index, 0)
        XCTAssertEqual(marker.transformType, .decorrelation)
        XCTAssertEqual(marker.componentType, .irreversible)
        XCTAssertEqual(marker.outputComponentCount, 3)
        XCTAssertGreaterThan(marker.coefficients.count, 0)
    }
    
    func testMCTMarkerEncodeDecode() throws {
        let matrix = J2KMCTMatrix.identity3
        let original = try J2KMCTMarkerSegment.from(matrix: matrix, index: 1)
        
        let encoded = try original.encode()
        XCTAssertGreaterThan(encoded.count, 0)
        
        // Parse back (skip marker and length)
        let segmentData = encoded.subdata(in: 4..<encoded.count)
        let decoded = try J2KMCTMarkerSegment.parse(from: segmentData)
        
        XCTAssertEqual(decoded.index, original.index)
        XCTAssertEqual(decoded.transformType, original.transformType)
        XCTAssertEqual(decoded.componentType, original.componentType)
        XCTAssertEqual(decoded.outputComponentCount, original.outputComponentCount)
    }
    
    func testMCTMarkerToMatrix() throws {
        let originalMatrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [1.0, 0.5, 0.0, 1.0],
            precision: .floatingPoint
        )
        
        let marker = try J2KMCTMarkerSegment.from(matrix: originalMatrix, index: 0)
        let reconstructedMatrix = try marker.toMatrix(inputComponentCount: 2)
        
        XCTAssertEqual(reconstructedMatrix.size, 2)
        XCTAssertEqual(reconstructedMatrix.coefficients.count, 4)
        
        // Check approximate equality (floating-point precision)
        for i in 0..<4 {
            XCTAssertEqual(
                reconstructedMatrix.coefficients[i],
                originalMatrix.coefficients[i],
                accuracy: 0.01
            )
        }
    }
    
    func testMCCMarkerCreation() {
        let marker = J2KMCCMarkerSegment(
            index: 0,
            inputComponents: [0, 1, 2],
            outputComponents: [0, 1, 2],
            mctIndex: 0
        )
        
        XCTAssertEqual(marker.index, 0)
        XCTAssertEqual(marker.inputComponents.count, 3)
        XCTAssertEqual(marker.outputComponents.count, 3)
        XCTAssertEqual(marker.mctIndex, 0)
    }
    
    func testMCCMarkerEncodeDecode() throws {
        let original = J2KMCCMarkerSegment(
            index: 1,
            inputComponents: [0, 1, 2],
            outputComponents: [3, 4, 5],
            mctIndex: 0
        )
        
        let encoded = try original.encode()
        XCTAssertGreaterThan(encoded.count, 0)
        
        // Parse back (skip marker and length)
        let segmentData = encoded.subdata(in: 4..<encoded.count)
        let decoded = try J2KMCCMarkerSegment.parse(from: segmentData)
        
        XCTAssertEqual(decoded.index, original.index)
        XCTAssertEqual(decoded.inputComponents, original.inputComponents)
        XCTAssertEqual(decoded.outputComponents, original.outputComponents)
        XCTAssertEqual(decoded.mctIndex, original.mctIndex)
    }
    
    func testMCOMarkerCreation() {
        let marker = J2KMCOMarkerSegment(mccOrder: [0, 1, 2])
        XCTAssertEqual(marker.mccOrder.count, 3)
        XCTAssertEqual(marker.mccOrder[0], 0)
    }
    
    func testMCOMarkerEncodeDecode() throws {
        let original = J2KMCOMarkerSegment(mccOrder: [0, 1, 2, 3])
        
        let encoded = try original.encode()
        XCTAssertGreaterThan(encoded.count, 0)
        
        // Parse back (skip marker and length)
        let segmentData = encoded.subdata(in: 4..<encoded.count)
        let decoded = try J2KMCOMarkerSegment.parse(from: segmentData)
        
        XCTAssertEqual(decoded.mccOrder, original.mccOrder)
    }
    
    func testMCTMarkerWithReversibleTransform() throws {
        let matrix = try J2KMCTMatrix(
            size: 2,
            coefficients: [1.0, 0.0, 0.0, 1.0],
            precision: .integer
        )
        
        let marker = try J2KMCTMarkerSegment.from(matrix: matrix, index: 0)
        
        XCTAssertEqual(marker.componentType, .reversible)
        
        let reconstructed = try marker.toMatrix(inputComponentCount: 2)
        XCTAssertEqual(reconstructed.precision, .integer)
    }
}
