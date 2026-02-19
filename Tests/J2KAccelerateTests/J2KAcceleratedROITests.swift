// J2KAcceleratedROITests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-19.
//

#if canImport(Accelerate)
import XCTest
@testable import J2KAccelerate
@testable import J2KCodec
import J2KCore

/// Tests for Accelerate-optimized ROI operations.
final class J2KAcceleratedROITests: XCTestCase {
    // MARK: - Setup
    
    var accelerated: J2KAcceleratedROI!
    
    override func setUp() {
        super.setUp()
        accelerated = J2KAcceleratedROI(imageWidth: 256, imageHeight: 256)
    }
    
    // MARK: - Mask Generation Tests
    
    func testGenerateRectangleMask() throws {
        let mask = accelerated.generateRectangleMask(
            x: 50,
            y: 50,
            width: 100,
            height: 100,
            imageWidth: 256,
            imageHeight: 256
        )
        
        XCTAssertEqual(mask.count, 256 * 256)
        
        // Check ROI region
        let centerIdx = 100 * 256 + 100
        XCTAssertEqual(mask[centerIdx], 1.0, accuracy: 0.001)
        
        // Check outside ROI
        let outsideIdx = 10 * 256 + 10
        XCTAssertEqual(mask[outsideIdx], 0.0, accuracy: 0.001)
    }
    
    func testGenerateRectangleMaskBoundary() throws {
        // Test mask at image boundary
        let mask = accelerated.generateRectangleMask(
            x: 200,
            y: 200,
            width: 100,
            height: 100,
            imageWidth: 256,
            imageHeight: 256
        )
        
        XCTAssertEqual(mask.count, 256 * 256)
        
        // Should clip to image boundary
        let insideIdx = 250 * 256 + 250
        XCTAssertEqual(mask[insideIdx], 1.0, accuracy: 0.001)
    }
    
    func testGenerateEllipseMask() throws {
        let mask = accelerated.generateEllipseMask(
            centerX: 128,
            centerY: 128,
            radiusX: 50,
            radiusY: 30,
            imageWidth: 256,
            imageHeight: 256
        )
        
        XCTAssertEqual(mask.count, 256 * 256)
        
        // Check center should be in ROI
        let centerIdx = 128 * 256 + 128
        XCTAssertEqual(mask[centerIdx], 1.0, accuracy: 0.001)
        
        // Check far outside should not be in ROI
        let outsideIdx = 0 * 256 + 0
        XCTAssertEqual(mask[outsideIdx], 0.0, accuracy: 0.001)
    }
    
    func testGenerateEllipseMaskCircle() throws {
        // Test circular mask (equal radii)
        let mask = accelerated.generateEllipseMask(
            centerX: 128,
            centerY: 128,
            radiusX: 50,
            radiusY: 50,
            imageWidth: 256,
            imageHeight: 256
        )
        
        XCTAssertEqual(mask.count, 256 * 256)
        
        // Check center
        let centerIdx = 128 * 256 + 128
        XCTAssertEqual(mask[centerIdx], 1.0, accuracy: 0.001)
    }
    
    // MARK: - Coefficient Scaling Tests
    
    func testApplyScaling() throws {
        let coefficients: [[Int32]] = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160]
        ]
        
        let scalingMap: [[Double]] = [
            [2.0, 2.0, 1.0, 1.0],
            [2.0, 2.0, 1.0, 1.0],
            [1.0, 1.0, 1.0, 1.0],
            [1.0, 1.0, 1.0, 1.0]
        ]
        
        let scaled = accelerated.applyScaling(
            coefficients: coefficients,
            scalingMap: scalingMap
        )
        
        XCTAssertEqual(scaled.count, 4)
        XCTAssertEqual(scaled[0].count, 4)
        
        // Check scaled region
        XCTAssertEqual(scaled[0][0], 20)  // 10 * 2.0
        XCTAssertEqual(scaled[0][1], 40)  // 20 * 2.0
        
        // Check non-scaled region
        XCTAssertEqual(scaled[0][2], 30)  // 30 * 1.0
        XCTAssertEqual(scaled[2][2], 110) // 110 * 1.0
    }
    
    func testApplyScalingMismatchedSize() throws {
        let coefficients: [[Int32]] = [
            [10, 20],
            [30, 40]
        ]
        
        let scalingMap: [[Double]] = [
            [2.0, 2.0, 1.0],  // Wrong size
            [2.0, 2.0, 1.0]
        ]
        
        let scaled = accelerated.applyScaling(
            coefficients: coefficients,
            scalingMap: scalingMap
        )
        
        // Should return original on size mismatch
        XCTAssertEqual(scaled, coefficients)
    }
    
    func testApplyUniformScaling() throws {
        let coefficients: [[Int32]] = [
            [10, 20, 30, 40],
            [50, 60, 70, 80]
        ]
        
        let mask: [[Bool]] = [
            [true, true, false, false],
            [true, true, false, false]
        ]
        
        let scaled = accelerated.applyUniformScaling(
            coefficients: coefficients,
            mask: mask,
            scalingFactor: 3.0
        )
        
        XCTAssertEqual(scaled.count, 2)
        XCTAssertEqual(scaled[0].count, 4)
        
        // Check scaled region
        XCTAssertEqual(scaled[0][0], 30)  // 10 * 3.0
        XCTAssertEqual(scaled[0][1], 60)  // 20 * 3.0
        
        // Check non-scaled region
        XCTAssertEqual(scaled[0][2], 30)  // No scaling
        XCTAssertEqual(scaled[0][3], 40)  // No scaling
    }
    
    func testApplyUniformScalingAllMasked() throws {
        let coefficients: [[Int32]] = [
            [10, 20],
            [30, 40]
        ]
        
        let mask: [[Bool]] = [
            [true, true],
            [true, true]
        ]
        
        let scaled = accelerated.applyUniformScaling(
            coefficients: coefficients,
            mask: mask,
            scalingFactor: 2.0
        )
        
        // All coefficients should be scaled
        XCTAssertEqual(scaled[0][0], 20)
        XCTAssertEqual(scaled[0][1], 40)
        XCTAssertEqual(scaled[1][0], 60)
        XCTAssertEqual(scaled[1][1], 80)
    }
    
    // MARK: - Feathering Tests
    
    func testApplyFeathering() throws {
        let mask: [[Bool]] = [
            [false, false, false, false, false],
            [false, true, true, true, false],
            [false, true, true, true, false],
            [false, true, true, true, false],
            [false, false, false, false, false]
        ]
        
        let feathered = accelerated.applyFeathering(
            mask: mask,
            featherWidth: 2
        )
        
        XCTAssertEqual(feathered.count, 5)
        XCTAssertEqual(feathered[0].count, 5)
        
        // Center should be 1.0
        XCTAssertEqual(feathered[2][2], 1.0, accuracy: 0.001)
        
        // Edges should have intermediate values
        XCTAssertGreaterThanOrEqual(feathered[1][1], 0.0)
        XCTAssertLessThanOrEqual(feathered[1][1], 1.0)
    }
    
    func testApplyFeatheringNoROI() throws {
        let mask: [[Bool]] = [
            [false, false, false],
            [false, false, false],
            [false, false, false]
        ]
        
        let feathered = accelerated.applyFeathering(
            mask: mask,
            featherWidth: 1
        )
        
        // All values should be 0.0
        for row in feathered {
            for value in row {
                XCTAssertEqual(value, 0.0, accuracy: 0.001)
            }
        }
    }
    
    func testApplyFeatheringFullROI() throws {
        let mask: [[Bool]] = [
            [true, true, true],
            [true, true, true],
            [true, true, true]
        ]
        
        let feathered = accelerated.applyFeathering(
            mask: mask,
            featherWidth: 1
        )
        
        // All values should be 1.0
        for row in feathered {
            for value in row {
                XCTAssertEqual(value, 1.0, accuracy: 0.001)
            }
        }
    }
    
    // MARK: - Blending Tests
    
    func testBlendScalingMapsMaximum() throws {
        let map1: [[Double]] = [
            [1.0, 2.0],
            [3.0, 1.5]
        ]
        
        let map2: [[Double]] = [
            [2.5, 1.5],
            [2.0, 3.0]
        ]
        
        let blended = accelerated.blendScalingMaps(
            map1: map1,
            map2: map2,
            mode: .maximum
        )
        
        XCTAssertEqual(blended[0][0], 2.5, accuracy: 0.001)
        XCTAssertEqual(blended[0][1], 2.0, accuracy: 0.001)
        XCTAssertEqual(blended[1][0], 3.0, accuracy: 0.001)
        XCTAssertEqual(blended[1][1], 3.0, accuracy: 0.001)
    }
    
    func testBlendScalingMapsMinimum() throws {
        let map1: [[Double]] = [
            [1.0, 2.0],
            [3.0, 1.5]
        ]
        
        let map2: [[Double]] = [
            [2.5, 1.5],
            [2.0, 3.0]
        ]
        
        let blended = accelerated.blendScalingMaps(
            map1: map1,
            map2: map2,
            mode: .minimum
        )
        
        XCTAssertEqual(blended[0][0], 1.0, accuracy: 0.001)
        XCTAssertEqual(blended[0][1], 1.5, accuracy: 0.001)
        XCTAssertEqual(blended[1][0], 2.0, accuracy: 0.001)
        XCTAssertEqual(blended[1][1], 1.5, accuracy: 0.001)
    }
    
    func testBlendScalingMapsAverage() throws {
        let map1: [[Double]] = [
            [1.0, 2.0],
            [3.0, 4.0]
        ]
        
        let map2: [[Double]] = [
            [3.0, 4.0],
            [5.0, 6.0]
        ]
        
        let blended = accelerated.blendScalingMaps(
            map1: map1,
            map2: map2,
            mode: .average
        )
        
        XCTAssertEqual(blended[0][0], 2.0, accuracy: 0.001)  // (1.0 + 3.0) / 2
        XCTAssertEqual(blended[0][1], 3.0, accuracy: 0.001)  // (2.0 + 4.0) / 2
        XCTAssertEqual(blended[1][0], 4.0, accuracy: 0.001)  // (3.0 + 5.0) / 2
        XCTAssertEqual(blended[1][1], 5.0, accuracy: 0.001)  // (4.0 + 6.0) / 2
    }
    
    func testBlendScalingMapsMismatchedSize() throws {
        let map1: [[Double]] = [
            [1.0, 2.0],
            [3.0, 4.0]
        ]
        
        let map2: [[Double]] = [
            [1.0, 2.0, 3.0],  // Wrong size
            [4.0, 5.0, 6.0]
        ]
        
        let blended = accelerated.blendScalingMaps(
            map1: map1,
            map2: map2,
            mode: .maximum
        )
        
        // Should return map1 on size mismatch
        XCTAssertEqual(blended, map1)
    }
    
    // MARK: - Batch Processing Tests
    
    func testApplyScalingBatch() throws {
        let coeff1: [[Int32]] = [
            [10, 20],
            [30, 40]
        ]
        
        let coeff2: [[Int32]] = [
            [50, 60],
            [70, 80]
        ]
        
        let scale1: [[Double]] = [
            [2.0, 2.0],
            [2.0, 2.0]
        ]
        
        let scale2: [[Double]] = [
            [1.5, 1.5],
            [1.5, 1.5]
        ]
        
        let results = accelerated.applyScalingBatch(
            coefficientsBatch: [coeff1, coeff2],
            scalingMapsBatch: [scale1, scale2]
        )
        
        XCTAssertEqual(results.count, 2)
        
        // Check first result
        XCTAssertEqual(results[0][0][0], 20)  // 10 * 2.0
        
        // Check second result
        XCTAssertEqual(results[1][0][0], 75)  // 50 * 1.5
    }
    
    func testApplyScalingBatchMismatchedCount() throws {
        let coeff1: [[Int32]] = [[10, 20]]
        let coeff2: [[Int32]] = [[30, 40]]
        
        let scale1: [[Double]] = [[2.0, 2.0]]
        
        let results = accelerated.applyScalingBatch(
            coefficientsBatch: [coeff1, coeff2],
            scalingMapsBatch: [scale1]  // Mismatched count
        )
        
        // Should return original batch on count mismatch
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], coeff1)
        XCTAssertEqual(results[1], coeff2)
    }
    
    // MARK: - Performance Benchmarks
    
    func testBenchmarkMaskGeneration() throws {
        let avgTime = accelerated.benchmarkMaskGeneration(
            iterations: 10,
            width: 256,
            height: 256
        )
        
        // Should complete reasonably fast
        XCTAssertLessThan(avgTime, 100.0)  // Less than 100ms per iteration
        XCTAssertGreaterThan(avgTime, 0.0)
    }
    
    func testBenchmarkScaling() throws {
        let avgTime = accelerated.benchmarkScaling(
            iterations: 10,
            size: 256
        )
        
        // Should complete reasonably fast
        XCTAssertLessThan(avgTime, 100.0)  // Less than 100ms per iteration
        XCTAssertGreaterThan(avgTime, 0.0)
    }
    
    // MARK: - Integration Tests
    
    func testRectangleMaskAndScaling() throws {
        // Generate mask
        let mask = accelerated.generateRectangleMask(
            x: 0,
            y: 0,
            width: 2,
            height: 2,
            imageWidth: 4,
            imageHeight: 4
        )
        
        // Convert to 2D bool array
        var boolMask: [[Bool]] = []
        for y in 0..<4 {
            var row: [Bool] = []
            for x in 0..<4 {
                let idx = y * 4 + x
                row.append(mask[idx] > 0.5)
            }
            boolMask.append(row)
        }
        
        // Apply scaling
        let coefficients: [[Int32]] = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160]
        ]
        
        let scaled = accelerated.applyUniformScaling(
            coefficients: coefficients,
            mask: boolMask,
            scalingFactor: 2.0
        )
        
        // Check ROI region is scaled
        XCTAssertEqual(scaled[0][0], 20)
        XCTAssertEqual(scaled[1][1], 120)
        
        // Check non-ROI region is not scaled
        XCTAssertEqual(scaled[2][2], 110)
        XCTAssertEqual(scaled[3][3], 160)
    }
    
    func testEllipseMaskAndScaling() throws {
        // Generate ellipse mask
        let mask = accelerated.generateEllipseMask(
            centerX: 2,
            centerY: 2,
            radiusX: 1,
            radiusY: 1,
            imageWidth: 4,
            imageHeight: 4
        )
        
        // Convert to 2D bool array
        var boolMask: [[Bool]] = []
        for y in 0..<4 {
            var row: [Bool] = []
            for x in 0..<4 {
                let idx = y * 4 + x
                row.append(mask[idx] > 0.5)
            }
            boolMask.append(row)
        }
        
        // Apply scaling
        let coefficients: [[Int32]] = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160]
        ]
        
        let scaled = accelerated.applyUniformScaling(
            coefficients: coefficients,
            mask: boolMask,
            scalingFactor: 2.0
        )
        
        // Center should be scaled
        XCTAssertEqual(scaled[2][2], 220)  // 110 * 2.0
    }
}

#endif // canImport(Accelerate)
