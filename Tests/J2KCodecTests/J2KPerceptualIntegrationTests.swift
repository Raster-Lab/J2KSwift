// J2KPerceptualIntegrationTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-19.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KPerceptualIntegrationTests: XCTestCase {
    // MARK: - End-to-End Perceptual Encoding Tests
    
    func testBasicPerceptualEncoding() {
        // Create test image
        let width = 256
        let height = 256
        let image = createTestImage(width: width, height: height, pattern: .gradient)
        
        // Create perceptual encoder
        let encoder = J2KPerceptualEncoder(configuration: .default)
        
        // Calculate perceptual quantization steps
        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.1,
            image: image,
            decompositionLevels: 3
        )
        
        // Verify we got steps for all levels
        XCTAssertEqual(steps.count, 3)
        
        // Verify steps are reasonable
        for levelSteps in steps {
            for (_, stepSize) in levelSteps {
                XCTAssertGreaterThan(stepSize, 0.0)
                XCTAssertLessThan(stepSize, 1.0)
            }
        }
    }
    
    func testPerceptualEncodingWithDifferentPatterns() {
        let patterns: [ImagePattern] = [.uniform, .gradient, .checkerboard]
        let encoder = J2KPerceptualEncoder()
        
        for pattern in patterns {
            let image = createTestImage(width: 128, height: 128, pattern: pattern)
            
            let steps = encoder.calculatePerceptualQuantizationSteps(
                baseQuantization: 0.1,
                image: image,
                decompositionLevels: 3
            )
            
            XCTAssertEqual(steps.count, 3, "Failed for pattern \(pattern)")
        }
    }
    
    func testSpatiallyVaryingQuantizationOnRealData() {
        let encoder = J2KPerceptualEncoder()
        
        // Create textured region
        let width = 64
        let height = 64
        var samples = [Int32]()
        for y in 0..<height {
            for x in 0..<width {
                // Create a gradient with some texture
                let value = Int32((x + y) * 255 / (width + height))
                let noise = Int32.random(in: -10...10)
                samples.append(value + noise)
            }
        }
        
        let spatialSteps = encoder.calculateSpatiallyVaryingQuantization(
            samples: samples,
            width: width,
            height: height,
            bitDepth: 8,
            baseQuantization: 0.1,
            subband: .hh,
            decompositionLevel: 1,
            totalLevels: 3
        )
        
        XCTAssertEqual(spatialSteps.count, width * height)
        
        // Steps should vary due to texture
        let uniqueSteps = Set(spatialSteps)
        XCTAssertGreaterThan(uniqueSteps.count, 1)
    }
    
    // MARK: - Quality Metric Integration Tests
    
    func testQualityEvaluationPSNR() throws {
        let metrics = J2KQualityMetrics()
        
        // Create identical images for testing
        let original = createTestImage(width: 64, height: 64, pattern: .uniform)
        let encoded = createTestImage(width: 64, height: 64, pattern: .uniform)
        
        let result = try metrics.psnr(original: original, compressed: encoded)
        
        // Identical images should have infinite PSNR
        XCTAssertTrue(result.value.isInfinite)
    }
    
    func testQualityEvaluationSSIM() throws {
        let metrics = J2KQualityMetrics()
        
        // Create identical images
        let original = createTestImage(width: 64, height: 64, pattern: .uniform)
        let encoded = createTestImage(width: 64, height: 64, pattern: .uniform)
        
        let result = try metrics.ssim(original: original, compressed: encoded)
        
        // Identical images should have SSIM close to 1.0
        XCTAssertGreaterThan(result.value, 0.99)
    }
    
    func testQualityEvaluationMSSSIM() throws {
        let metrics = J2KQualityMetrics()
        
        let original = createTestImage(width: 128, height: 128, pattern: .gradient)
        let encoded = createTestImage(width: 128, height: 128, pattern: .gradient)
        
        let result = try metrics.msssim(original: original, compressed: encoded, scales: 3)
        
        // Similar images should have high MS-SSIM
        XCTAssertGreaterThan(result.value, 0.95)
    }
    
    func testQualityEvaluationWithDifferentImages() throws {
        let metrics = J2KQualityMetrics()
        
        let original = createTestImage(width: 64, height: 64, pattern: .uniform)
        let different = createTestImage(width: 64, height: 64, pattern: .checkerboard)
        
        let psnrResult = try metrics.psnr(original: original, compressed: different)
        let ssimResult = try metrics.ssim(original: original, compressed: different)
        
        // Very different images should have lower quality
        XCTAssertLessThan(psnrResult.value, 30.0)  // Lower PSNR
        XCTAssertLessThan(ssimResult.value, 0.8)   // Lower SSIM
    }
    
    func testCalculateAllQualityMetrics() throws {
        let encoder = J2KPerceptualEncoder()
        let original = createTestImage(width: 64, height: 64, pattern: .gradient)
        let encoded = createTestImage(width: 64, height: 64, pattern: .gradient)
        
        let results = try encoder.calculateAllQualityMetrics(
            original: original,
            encoded: encoded
        )
        
        XCTAssertEqual(results.count, 3)
        XCTAssertNotNil(results["PSNR"])
        XCTAssertNotNil(results["SSIM"])
        XCTAssertNotNil(results["MS-SSIM"])
    }
    
    // MARK: - Visual Masking Integration Tests
    
    func testVisualMaskingWithRealImage() {
        let masking = J2KVisualMasking()
        
        // Create image with varying characteristics
        let width = 64
        let height = 64
        var samples = [Int32]()
        
        for y in 0..<height {
            for x in 0..<width {
                if x < width / 2 {
                    // Left half: dark with low variance
                    samples.append(Int32.random(in: 20...40))
                } else {
                    // Right half: bright with high variance
                    samples.append(Int32.random(in: 180...240))
                }
            }
        }
        
        let maskingFactors = masking.calculateRegionMaskingFactors(
            samples: samples,
            width: width,
            height: height,
            bitDepth: 8,
            motionField: nil
        )
        
        XCTAssertEqual(maskingFactors.count, width * height)
        
        // Factors should vary across the image
        let leftFactors = maskingFactors[0..<(width*height/2)]
        let rightFactors = maskingFactors[(width*height/2)..<(width*height)]
        
        let avgLeft = leftFactors.reduce(0.0, +) / Double(leftFactors.count)
        let avgRight = rightFactors.reduce(0.0, +) / Double(rightFactors.count)
        
        // Both sides should have valid masking factors
        XCTAssertGreaterThan(avgLeft, 0.5)
        XCTAssertLessThan(avgLeft, 3.0)
        XCTAssertGreaterThan(avgRight, 0.5)
        XCTAssertLessThan(avgRight, 3.0)
    }
    
    func testCombinedFrequencyAndSpatialMasking() {
        let weighting = J2KVisualWeighting()
        let masking = J2KVisualMasking()
        
        let image = createTestImage(width: 128, height: 128, pattern: .gradient)
        
        // Get frequency weight
        let frequencyWeight = weighting.weight(
            for: .hh,
            decompositionLevel: 1,
            totalLevels: 3,
            imageWidth: image.width,
            imageHeight: image.height
        )
        
        // Get spatial masking factor
        let spatialFactor = masking.calculateMaskingFactor(
            luminance: 128.0,
            localVariance: 500.0,
            motionVector: nil
        )
        
        // Combined perceptual step size
        let baseStep = 0.1
        let perceptualStep = baseStep * frequencyWeight * spatialFactor
        
        XCTAssertGreaterThan(perceptualStep, 0.0)
        XCTAssertNotEqual(perceptualStep, baseStep)
    }
    
    // MARK: - Configuration Preset Tests
    
    func testHighQualityPreset() {
        let config = J2KPerceptualEncodingConfiguration.highQuality
        let encoder = J2KPerceptualEncoder(configuration: config)
        
        if case .ssim(let value) = config.targetQuality {
            XCTAssertEqual(value, 0.98)
        } else {
            XCTFail("Expected SSIM target")
        }
        
        let image = createTestImage(width: 64, height: 64, pattern: .gradient)
        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.05,
            image: image,
            decompositionLevels: 3
        )
        
        XCTAssertGreaterThan(steps.count, 0)
    }
    
    func testBalancedPreset() {
        let config = J2KPerceptualEncodingConfiguration.balanced
        let encoder = J2KPerceptualEncoder(configuration: config)
        
        if case .msssim(let value) = config.targetQuality {
            XCTAssertEqual(value, 0.95)
        } else {
            XCTFail("Expected MS-SSIM target")
        }
        
        let image = createTestImage(width: 64, height: 64, pattern: .gradient)
        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.1,
            image: image,
            decompositionLevels: 3
        )
        
        XCTAssertGreaterThan(steps.count, 0)
    }
    
    func testHighCompressionPreset() {
        let config = J2KPerceptualEncodingConfiguration.highCompression
        let encoder = J2KPerceptualEncoder(configuration: config)
        
        if case .ssim(let value) = config.targetQuality {
            XCTAssertEqual(value, 0.90)
        } else {
            XCTFail("Expected SSIM target")
        }
        
        // Should use aggressive masking
        XCTAssertEqual(config.maskingConfiguration, .aggressive)
    }
    
    // MARK: - Rate-Distortion Tests
    
    func testEstimateBaseQuantization() {
        let encoder = J2KPerceptualEncoder()
        
        let bitrates = [0.25, 0.5, 1.0, 2.0, 4.0]
        var prevQuant = 10.0
        
        for bitrate in bitrates {
            let quant = encoder.estimateBaseQuantization(
                targetBitrate: bitrate,
                imageSize: 1024 * 1024
            )
            
            // Higher bitrate should produce lower quantization
            XCTAssertLessThan(quant, prevQuant)
            prevQuant = quant
        }
    }
    
    func testQuantizationAdjustment() {
        let encoder = J2KPerceptualEncoder()
        
        // Quality too low, should decrease quantization
        let adjusted1 = encoder.adjustQuantization(
            currentQuantization: 0.1,
            targetQuality: 0.95,
            achievedQuality: 0.88
        )
        XCTAssertLessThan(adjusted1, 0.1)
        
        // Quality too high, should increase quantization
        let adjusted2 = encoder.adjustQuantization(
            currentQuantization: 0.1,
            targetQuality: 0.95,
            achievedQuality: 0.98
        )
        XCTAssertGreaterThan(adjusted2, 0.1)
        
        // Quality perfect, should stay similar
        let adjusted3 = encoder.adjustQuantization(
            currentQuantization: 0.1,
            targetQuality: 0.95,
            achievedQuality: 0.95
        )
        XCTAssertEqual(adjusted3, 0.1, accuracy: 0.01)
    }
    
    // MARK: - JND Integration Tests
    
    func testJNDWithDifferentConditions() {
        let jnd = J2KJNDModel()
        
        // Test various conditions
        let conditions: [(luminance: Double, variance: Double, distance: Double)] = [
            (50.0, 100.0, 60.0),    // Dark, low texture, normal distance
            (128.0, 500.0, 60.0),   // Mid-gray, medium texture, normal distance
            (200.0, 2000.0, 60.0),  // Bright, high texture, normal distance
            (128.0, 500.0, 30.0),   // Mid-gray, medium texture, close viewing
            (128.0, 500.0, 120.0)   // Mid-gray, medium texture, far viewing
        ]
        
        for condition in conditions {
            let threshold = jnd.jndThreshold(
                luminance: condition.luminance,
                localVariance: condition.variance,
                viewingDistance: condition.distance
            )
            
            XCTAssertGreaterThan(threshold, 0.0)
        }
    }
    
    // MARK: - Stress Tests
    
    func testLargeImagePerceptualEncoding() {
        let encoder = J2KPerceptualEncoder()
        let image = createTestImage(width: 512, height: 512, pattern: .gradient)
        
        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.1,
            image: image,
            decompositionLevels: 5
        )
        
        XCTAssertEqual(steps.count, 5)
    }
    
    func testManyDecompositionLevels() {
        let encoder = J2KPerceptualEncoder()
        let image = createTestImage(width: 1024, height: 1024, pattern: .gradient)
        
        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.1,
            image: image,
            decompositionLevels: 8
        )
        
        XCTAssertEqual(steps.count, 8)
    }
    
    // MARK: - Helper Methods
    
    private enum ImagePattern {
        case uniform
        case gradient
        case checkerboard
    }
    
    private func createTestImage(width: Int, height: Int, pattern: ImagePattern) -> J2KImage {
        let componentSize = width * height
        var data = Data(count: componentSize * 4)
        
        data.withUnsafeMutableBytes { buffer in
            let int32Buffer = buffer.bindMemory(to: Int32.self)
            
            switch pattern {
            case .uniform:
                for i in 0..<componentSize {
                    int32Buffer[i] = 128
                }
                
            case .gradient:
                for y in 0..<height {
                    for x in 0..<width {
                        let value = Int32((x + y) * 255 / (width + height))
                        int32Buffer[y * width + x] = value
                    }
                }
                
            case .checkerboard:
                for y in 0..<height {
                    for x in 0..<width {
                        let value: Int32 = ((x / 8 + y / 8) % 2 == 0) ? 50 : 200
                        int32Buffer[y * width + x] = value
                    }
                }
            }
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        return J2KImage(
            width: width,
            height: height,
            components: [component],
            colorSpace: .grayscale
        )
    }
}
