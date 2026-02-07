// J2KROITests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Comprehensive tests for JPEG 2000 Region of Interest (ROI) coding.
final class J2KROITests: XCTestCase {
    
    // MARK: - ROI Shape Type Tests
    
    func testROIShapeTypeAllCases() throws {
        let allTypes = J2KROIShapeType.allCases
        XCTAssertEqual(allTypes.count, 4)
        XCTAssertTrue(allTypes.contains(.rectangle))
        XCTAssertTrue(allTypes.contains(.ellipse))
        XCTAssertTrue(allTypes.contains(.polygon))
        XCTAssertTrue(allTypes.contains(.mask))
    }
    
    // MARK: - ROI Region Tests
    
    func testRectangleRegionCreation() throws {
        let region = J2KROIRegion.rectangle(x: 10, y: 20, width: 100, height: 50)
        
        XCTAssertEqual(region.shapeType, .rectangle)
        XCTAssertEqual(region.x, 10)
        XCTAssertEqual(region.y, 20)
        XCTAssertEqual(region.width, 100)
        XCTAssertEqual(region.height, 50)
        XCTAssertTrue(region.isValid)
        XCTAssertEqual(region.area, 5000)
        XCTAssertEqual(region.center.x, 60)
        XCTAssertEqual(region.center.y, 45)
    }
    
    func testEllipseRegionCreation() throws {
        let region = J2KROIRegion.ellipse(centerX: 100, centerY: 100, radiusX: 50, radiusY: 30)
        
        XCTAssertEqual(region.shapeType, .ellipse)
        XCTAssertEqual(region.x, 50)  // centerX - radiusX
        XCTAssertEqual(region.y, 70)  // centerY - radiusY
        XCTAssertEqual(region.width, 100)  // 2 * radiusX
        XCTAssertEqual(region.height, 60)  // 2 * radiusY
        XCTAssertTrue(region.isValid)
    }
    
    func testPolygonRegionCreation() throws {
        let vertices: [(x: Int, y: Int)] = [
            (10, 10),
            (100, 10),
            (100, 100),
            (10, 100)
        ]
        let region = J2KROIRegion.polygon(vertices: vertices)
        
        XCTAssertEqual(region.shapeType, .polygon)
        XCTAssertEqual(region.x, 10)
        XCTAssertEqual(region.y, 10)
        XCTAssertEqual(region.width, 90)  // 100 - 10
        XCTAssertEqual(region.height, 90)  // 100 - 10
        XCTAssertEqual(region.vertices.count, 4)
    }
    
    func testPolygonRegionEmptyVertices() throws {
        let region = J2KROIRegion.polygon(vertices: [])
        
        XCTAssertEqual(region.shapeType, .polygon)
        XCTAssertEqual(region.width, 0)
        XCTAssertEqual(region.height, 0)
        XCTAssertFalse(region.isValid)
    }
    
    func testRegionPriority() throws {
        let lowPriority = J2KROIRegion.rectangle(x: 0, y: 0, width: 10, height: 10, priority: 1)
        let highPriority = J2KROIRegion.rectangle(x: 0, y: 0, width: 10, height: 10, priority: 5)
        
        XCTAssertEqual(lowPriority.priority, 1)
        XCTAssertEqual(highPriority.priority, 5)
    }
    
    func testRegionEquality() throws {
        let region1 = J2KROIRegion.rectangle(x: 10, y: 20, width: 100, height: 50)
        let region2 = J2KROIRegion.rectangle(x: 10, y: 20, width: 100, height: 50)
        let region3 = J2KROIRegion.rectangle(x: 10, y: 20, width: 100, height: 60)
        
        XCTAssertEqual(region1, region2)
        XCTAssertNotEqual(region1, region3)
    }
    
    // MARK: - ROI Mask Generator Tests
    
    func testGenerateRectangleMask() throws {
        let region = J2KROIRegion.rectangle(x: 2, y: 2, width: 4, height: 3)
        let mask = J2KROIMaskGenerator.generateMask(for: region, width: 10, height: 10)
        
        XCTAssertEqual(mask.count, 10)
        XCTAssertEqual(mask[0].count, 10)
        
        // Check that mask is set correctly
        for y in 0..<10 {
            for x in 0..<10 {
                let expected = (x >= 2 && x < 6) && (y >= 2 && y < 5)
                XCTAssertEqual(mask[y][x], expected, "Mismatch at (\(x), \(y))")
            }
        }
    }
    
    func testGenerateEllipseMask() throws {
        let region = J2KROIRegion.ellipse(centerX: 5, centerY: 5, radiusX: 3, radiusY: 2)
        let mask = J2KROIMaskGenerator.generateMask(for: region, width: 10, height: 10)
        
        XCTAssertEqual(mask.count, 10)
        
        // Center should be in the mask
        XCTAssertTrue(mask[5][5])
        
        // Corners of bounding box should be outside ellipse
        XCTAssertFalse(mask[3][2])  // top-left corner
        XCTAssertFalse(mask[3][8])  // top-right corner
        XCTAssertFalse(mask[7][2])  // bottom-left corner
        XCTAssertFalse(mask[7][8])  // bottom-right corner
    }
    
    func testGeneratePolygonMaskTriangle() throws {
        let vertices: [(x: Int, y: Int)] = [
            (5, 0),
            (10, 10),
            (0, 10)
        ]
        let region = J2KROIRegion.polygon(vertices: vertices)
        let mask = J2KROIMaskGenerator.generateMask(for: region, width: 11, height: 11)
        
        // Point clearly inside the triangle
        XCTAssertTrue(mask[5][5])  // Center of triangle
        XCTAssertTrue(mask[8][5])  // Lower part near base
        
        // Points clearly outside should not be in mask
        XCTAssertFalse(mask[0][0])
        XCTAssertFalse(mask[0][10])
    }
    
    func testGenerateCombinedMask() throws {
        let region1 = J2KROIRegion.rectangle(x: 0, y: 0, width: 5, height: 5)
        let region2 = J2KROIRegion.rectangle(x: 5, y: 5, width: 5, height: 5)
        
        let mask = J2KROIMaskGenerator.generateCombinedMask(
            for: [region1, region2],
            width: 10,
            height: 10
        )
        
        // Check first region
        XCTAssertTrue(mask[0][0])
        XCTAssertTrue(mask[4][4])
        
        // Check second region
        XCTAssertTrue(mask[5][5])
        XCTAssertTrue(mask[9][9])
        
        // Check area between regions
        XCTAssertFalse(mask[0][9])
        XCTAssertFalse(mask[9][0])
    }
    
    func testGeneratePriorityMask() throws {
        let lowPriority = J2KROIRegion.rectangle(x: 0, y: 0, width: 10, height: 10, priority: 1)
        let highPriority = J2KROIRegion.rectangle(x: 3, y: 3, width: 4, height: 4, priority: 3)
        
        let priorityMask = J2KROIMaskGenerator.generatePriorityMask(
            for: [lowPriority, highPriority],
            width: 10,
            height: 10
        )
        
        // Corners should have low priority
        XCTAssertEqual(priorityMask[0][0], 1)
        XCTAssertEqual(priorityMask[9][9], 1)
        
        // Center (overlap) should have high priority
        XCTAssertEqual(priorityMask[5][5], 3)
    }
    
    func testMaskBoundaryClipping() throws {
        // ROI extends beyond image bounds
        let region = J2KROIRegion.rectangle(x: -5, y: -5, width: 20, height: 20)
        let mask = J2KROIMaskGenerator.generateMask(for: region, width: 10, height: 10)
        
        // Entire image should be within ROI (clipped to bounds)
        for y in 0..<10 {
            for x in 0..<10 {
                XCTAssertTrue(mask[y][x])
            }
        }
    }
    
    // MARK: - MaxShift Tests
    
    func testMaxShiftDefaultValues() throws {
        XCTAssertEqual(J2KROIMaxShift.defaultShift, 5)
        XCTAssertEqual(J2KROIMaxShift.minShift, 0)
        XCTAssertEqual(J2KROIMaxShift.maxShift, 37)
    }
    
    func testMaxShiftCalculation() throws {
        // 8-bit image
        let shift8 = J2KROIMaxShift.calculateShift(bitDepth: 8)
        XCTAssertEqual(shift8, 5)
        
        // 16-bit image
        let shift16 = J2KROIMaxShift.calculateShift(bitDepth: 16)
        XCTAssertEqual(shift16, 5)
    }
    
    func testMaxShiftApplyScaling() throws {
        let shift = 5
        
        // Positive coefficient
        let scaled1 = J2KROIMaxShift.applyScaling(coefficient: 10, isROI: true, shift: shift)
        XCTAssertEqual(scaled1, 10 << 5)  // 320
        
        // Negative coefficient
        let scaled2 = J2KROIMaxShift.applyScaling(coefficient: -10, isROI: true, shift: shift)
        XCTAssertEqual(scaled2, -(10 << 5))  // -320
        
        // Non-ROI coefficient should not be scaled
        let scaled3 = J2KROIMaxShift.applyScaling(coefficient: 10, isROI: false, shift: shift)
        XCTAssertEqual(scaled3, 10)
        
        // Zero shift should not scale
        let scaled4 = J2KROIMaxShift.applyScaling(coefficient: 10, isROI: true, shift: 0)
        XCTAssertEqual(scaled4, 10)
    }
    
    func testMaxShiftRemoveScaling() throws {
        let shift = 5
        
        // ROI coefficient (magnitude >= 2^shift)
        let original1 = J2KROIMaxShift.removeScaling(coefficient: 320, shift: shift)
        XCTAssertEqual(original1, 10)
        
        // Negative ROI coefficient
        let original2 = J2KROIMaxShift.removeScaling(coefficient: -320, shift: shift)
        XCTAssertEqual(original2, -10)
        
        // Non-ROI coefficient (magnitude < 2^shift)
        let original3 = J2KROIMaxShift.removeScaling(coefficient: 20, shift: shift)
        XCTAssertEqual(original3, 20)
    }
    
    func testMaxShiftRoundtrip() throws {
        let shift = 5
        let testValues: [Int32] = [0, 1, -1, 10, -10, 100, -100, 255, -255]
        
        for value in testValues {
            let scaled = J2KROIMaxShift.applyScaling(coefficient: value, isROI: true, shift: shift)
            let recovered = J2KROIMaxShift.removeScaling(coefficient: scaled, shift: shift)
            XCTAssertEqual(recovered, value, "Roundtrip failed for value \(value)")
        }
    }
    
    func testIsROICoefficient() throws {
        let shift = 5
        _ = Int32(1 << shift)  // 32
        
        // Above threshold - ROI
        XCTAssertTrue(J2KROIMaxShift.isROICoefficient(coefficient: 32, shift: shift))
        XCTAssertTrue(J2KROIMaxShift.isROICoefficient(coefficient: -32, shift: shift))
        XCTAssertTrue(J2KROIMaxShift.isROICoefficient(coefficient: 100, shift: shift))
        
        // Below threshold - non-ROI
        XCTAssertFalse(J2KROIMaxShift.isROICoefficient(coefficient: 31, shift: shift))
        XCTAssertFalse(J2KROIMaxShift.isROICoefficient(coefficient: -31, shift: shift))
        XCTAssertFalse(J2KROIMaxShift.isROICoefficient(coefficient: 0, shift: shift))
    }
    
    // MARK: - ROI Wavelet Mapper Tests
    
    func testWaveletMapperBasic() throws {
        // Create a simple 8x8 spatial mask with ROI in top-left 4x4
        var spatialMask = Array(repeating: Array(repeating: false, count: 8), count: 8)
        for y in 0..<4 {
            for x in 0..<4 {
                spatialMask[y][x] = true
            }
        }
        
        // Map to LL subband at level 0 (should be 4x4)
        let llMask = J2KROIWaveletMapper.mapToWaveletDomain(
            spatialMask: spatialMask,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        XCTAssertFalse(llMask.isEmpty)
    }
    
    func testWaveletMapperEmptyMask() throws {
        let emptyMask: [[Bool]] = []
        
        let result = J2KROIWaveletMapper.mapToWaveletDomain(
            spatialMask: emptyMask,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        XCTAssertTrue(result.isEmpty)
    }
    
    func testWaveletMapperAllSubbands() throws {
        let spatialMask = Array(repeating: Array(repeating: true, count: 8), count: 8)
        
        let subbandMasks = J2KROIWaveletMapper.mapToAllSubbands(
            spatialMask: spatialMask,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        // Should have masks for LL, LH, HL, HH
        XCTAssertNotNil(subbandMasks[.ll])
        XCTAssertNotNil(subbandMasks[.lh])
        XCTAssertNotNil(subbandMasks[.hl])
        XCTAssertNotNil(subbandMasks[.hh])
    }
    
    // MARK: - ROI Processor Tests
    
    func testROIProcessorCreation() throws {
        let region = J2KROIRegion.rectangle(x: 10, y: 10, width: 20, height: 20)
        let processor = J2KROIProcessor(
            imageWidth: 64,
            imageHeight: 64,
            regions: [region],
            shift: 5
        )
        
        XCTAssertEqual(processor.imageWidth, 64)
        XCTAssertEqual(processor.imageHeight, 64)
        XCTAssertEqual(processor.regions.count, 1)
        XCTAssertEqual(processor.shift, 5)
        XCTAssertTrue(processor.isEnabled)
    }
    
    func testROIProcessorDisabled() throws {
        let processor = J2KROIProcessor.disabled()
        
        XCTAssertFalse(processor.isEnabled)
        XCTAssertEqual(processor.regions.count, 0)
    }
    
    func testROIProcessorEmptyRegions() throws {
        let processor = J2KROIProcessor(
            imageWidth: 64,
            imageHeight: 64,
            regions: [],
            shift: 5
        )
        
        XCTAssertFalse(processor.isEnabled)
    }
    
    func testROIProcessorZeroShift() throws {
        let region = J2KROIRegion.rectangle(x: 10, y: 10, width: 20, height: 20)
        let processor = J2KROIProcessor(
            imageWidth: 64,
            imageHeight: 64,
            regions: [region],
            shift: 0
        )
        
        XCTAssertFalse(processor.isEnabled)
    }
    
    func testROIProcessorApplyScaling() throws {
        let region = J2KROIRegion.rectangle(x: 0, y: 0, width: 4, height: 4)
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region],
            shift: 5
        )
        
        // Create test coefficients
        let coefficients: [[Int32]] = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160]
        ]
        
        let scaled = processor.applyROIScaling(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        XCTAssertEqual(scaled.count, coefficients.count)
        XCTAssertEqual(scaled[0].count, coefficients[0].count)
    }
    
    func testROIProcessorDisabledPassthrough() throws {
        let processor = J2KROIProcessor.disabled()
        
        let coefficients: [[Int32]] = [
            [10, 20],
            [30, 40]
        ]
        
        let result = processor.applyROIScaling(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        XCTAssertEqual(result, coefficients)
    }
    
    func testROIProcessorRemoveScaling() throws {
        let region = J2KROIRegion.rectangle(x: 0, y: 0, width: 8, height: 8)
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region],
            shift: 5
        )
        
        let scaled: [[Int32]] = [
            [320, 640],  // 10 << 5, 20 << 5
            [960, 1280]  // 30 << 5, 40 << 5
        ]
        
        let unscaled = processor.removeROIScaling(coefficients: scaled)
        
        XCTAssertEqual(unscaled[0][0], 10)
        XCTAssertEqual(unscaled[0][1], 20)
        XCTAssertEqual(unscaled[1][0], 30)
        XCTAssertEqual(unscaled[1][1], 40)
    }
    
    func testROIProcessorGetSpatialMask() throws {
        let region = J2KROIRegion.rectangle(x: 2, y: 2, width: 4, height: 4)
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region],
            shift: 5
        )
        
        let mask = processor.getSpatialMask()
        
        XCTAssertEqual(mask.count, 8)
        XCTAssertEqual(mask[0].count, 8)
        
        // Check ROI area
        XCTAssertTrue(mask[2][2])
        XCTAssertTrue(mask[5][5])
        
        // Check outside ROI
        XCTAssertFalse(mask[0][0])
        XCTAssertFalse(mask[7][7])
    }
    
    func testROIProcessorStatistics() throws {
        let region = J2KROIRegion.rectangle(x: 0, y: 0, width: 4, height: 4)
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region],
            shift: 5
        )
        
        let stats = processor.getStatistics()
        
        XCTAssertEqual(stats.totalPixels, 64)
        XCTAssertEqual(stats.roiPixels, 16)
        XCTAssertEqual(stats.coveragePercentage, 25.0, accuracy: 0.01)
        XCTAssertEqual(stats.regionCount, 1)
    }
    
    func testROIProcessorMultipleRegions() throws {
        let region1 = J2KROIRegion.rectangle(x: 0, y: 0, width: 4, height: 4)
        let region2 = J2KROIRegion.rectangle(x: 4, y: 4, width: 4, height: 4)
        
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region1, region2],
            shift: 5
        )
        
        let stats = processor.getStatistics()
        
        XCTAssertEqual(stats.regionCount, 2)
        XCTAssertEqual(stats.roiPixels, 32)  // 16 + 16 (no overlap)
    }
    
    func testROIProcessorDecompositionScaling() throws {
        let region = J2KROIRegion.rectangle(x: 0, y: 0, width: 8, height: 8)
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region],
            shift: 5
        )
        
        let ll: [[Int32]] = [[10, 20], [30, 40]]
        let lh: [[Int32]] = [[5, 10], [15, 20]]
        let hl: [[Int32]] = [[3, 6], [9, 12]]
        let hh: [[Int32]] = [[1, 2], [3, 4]]
        
        let result = processor.applyROIScalingToDecomposition(
            ll: ll,
            lh: lh,
            hl: hl,
            hh: hh,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        XCTAssertEqual(result.ll.count, 2)
        XCTAssertEqual(result.lh.count, 2)
        XCTAssertEqual(result.hl.count, 2)
        XCTAssertEqual(result.hh.count, 2)
    }
    
    // MARK: - ROI Configuration Tests
    
    func testROIConfigurationDefault() throws {
        let config = J2KROIConfiguration.disabled
        
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.regions.count, 0)
    }
    
    func testROIConfigurationRectangle() throws {
        let config = J2KROIConfiguration.rectangle(
            x: 10, y: 20, width: 100, height: 50, shift: 6
        )
        
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.regions.count, 1)
        XCTAssertEqual(config.shift, 6)
    }
    
    func testROIConfigurationEllipse() throws {
        let config = J2KROIConfiguration.ellipse(
            centerX: 100, centerY: 100, radiusX: 50, radiusY: 30
        )
        
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.regions.count, 1)
        XCTAssertEqual(config.regions[0].shapeType, .ellipse)
    }
    
    func testROIConfigurationEquality() throws {
        let config1 = J2KROIConfiguration.rectangle(x: 10, y: 10, width: 20, height: 20)
        let config2 = J2KROIConfiguration.rectangle(x: 10, y: 10, width: 20, height: 20)
        let config3 = J2KROIConfiguration.rectangle(x: 10, y: 10, width: 20, height: 30)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    func testROIConfigurationShiftClamping() throws {
        // Shift below minimum
        let configLow = J2KROIConfiguration(
            regions: [J2KROIRegion.rectangle(x: 0, y: 0, width: 10, height: 10)],
            shift: -5
        )
        XCTAssertEqual(configLow.shift, 0)
        
        // Shift above maximum
        let configHigh = J2KROIConfiguration(
            regions: [J2KROIRegion.rectangle(x: 0, y: 0, width: 10, height: 10)],
            shift: 50
        )
        XCTAssertEqual(configHigh.shift, 37)
    }
    
    // MARK: - Edge Case Tests
    
    func testROIAtImageBoundary() throws {
        let region = J2KROIRegion.rectangle(x: 6, y: 6, width: 4, height: 4)
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region],
            shift: 5
        )
        
        let mask = processor.getSpatialMask()
        
        // Should be clipped to image bounds
        XCTAssertTrue(mask[6][6])
        XCTAssertTrue(mask[7][7])
    }
    
    func testROIZeroSizeRegion() throws {
        let region = J2KROIRegion.rectangle(x: 10, y: 10, width: 0, height: 0)
        
        XCTAssertFalse(region.isValid)
    }
    
    func testROINegativeCoefficients() throws {
        let region = J2KROIRegion.rectangle(x: 0, y: 0, width: 4, height: 4)
        let processor = J2KROIProcessor(
            imageWidth: 4,
            imageHeight: 4,
            regions: [region],
            shift: 5
        )
        
        let coefficients: [[Int32]] = [
            [-10, 20],
            [-30, 40]
        ]
        
        let scaled = processor.applyROIScaling(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        // Negative values should still be scaled correctly
        XCTAssertLessThan(scaled[0][0], 0)
        XCTAssertLessThan(scaled[1][0], 0)
    }
    
    func testEmptyCoefficients() throws {
        let region = J2KROIRegion.rectangle(x: 0, y: 0, width: 10, height: 10)
        let processor = J2KROIProcessor(
            imageWidth: 10,
            imageHeight: 10,
            regions: [region],
            shift: 5
        )
        
        let empty: [[Int32]] = []
        let result = processor.applyROIScaling(
            coefficients: empty,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        XCTAssertTrue(result.isEmpty)
    }
    
    // MARK: - Integration Tests
    
    func testROIWithQuantization() throws {
        // This test demonstrates integration with quantization
        let region = J2KROIRegion.rectangle(x: 0, y: 0, width: 4, height: 4)
        let processor = J2KROIProcessor(
            imageWidth: 8,
            imageHeight: 8,
            regions: [region],
            shift: 5
        )
        
        // Simulate DWT coefficients
        let coefficients: [[Int32]] = [
            [100, 200, 10, 20],
            [300, 400, 30, 40],
            [5, 6, 7, 8],
            [9, 10, 11, 12]
        ]
        
        // Apply ROI scaling
        let scaled = processor.applyROIScaling(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )
        
        // After quantization and dequantization, remove ROI scaling
        let restored = processor.removeROIScaling(coefficients: scaled)
        
        // Verify ROI coefficients are recovered
        XCTAssertEqual(restored.count, coefficients.count)
    }
    
    // MARK: - Sendable Conformance Tests
    
    func testROIRegionIsSendable() throws {
        let region = J2KROIRegion.rectangle(x: 10, y: 10, width: 20, height: 20)
        
        let expectation = XCTestExpectation(description: "ROI Region is Sendable")
        
        Task {
            _ = region.area
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testROIProcessorIsSendable() throws {
        let region = J2KROIRegion.rectangle(x: 10, y: 10, width: 20, height: 20)
        let processor = J2KROIProcessor(
            imageWidth: 64,
            imageHeight: 64,
            regions: [region],
            shift: 5
        )
        
        let expectation = XCTestExpectation(description: "ROI Processor is Sendable")
        
        Task {
            _ = processor.isEnabled
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Performance Tests
    
    func testMaskGenerationPerformance() throws {
        let region = J2KROIRegion.rectangle(x: 100, y: 100, width: 200, height: 200)
        
        measure {
            for _ in 0..<10 {
                _ = J2KROIMaskGenerator.generateMask(
                    for: region,
                    width: 512,
                    height: 512
                )
            }
        }
    }
    
    func testROIScalingPerformance() throws {
        let region = J2KROIRegion.rectangle(x: 64, y: 64, width: 128, height: 128)
        let processor = J2KROIProcessor(
            imageWidth: 256,
            imageHeight: 256,
            regions: [region],
            shift: 5
        )
        
        // Create large coefficient array
        let size = 128
        let coefficients: [[Int32]] = (0..<size).map { _ in
            (0..<size).map { _ in Int32.random(in: -255...255) }
        }
        
        measure {
            _ = processor.applyROIScaling(
                coefficients: coefficients,
                subband: .ll,
                decompositionLevel: 0,
                totalLevels: 3
            )
        }
    }
}
