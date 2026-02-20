//
// J2KAdaptiveBlockSizeTests.swift
// J2KSwift
//
// J2KAdaptiveBlockSizeTests.swift
// J2KSwift
//
// Tests for adaptive block size selection (Week 137-138).
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KAdaptiveBlockSizeTests: XCTestCase {
    // MARK: - Content Analyzer Tests

    func testEdgeDensityUniformImage() {
        let analyzer = J2KContentAnalyzer()
        let width = 32
        let height = 32
        // Uniform image: all pixels same value → no edges
        let samples = [Int32](repeating: 128, count: width * height)
        let density = analyzer.estimateEdgeDensity(samples: samples, width: width, height: height)
        XCTAssertEqual(density, 0.0, accuracy: 0.001, "Uniform image should have zero edge density")
    }

    func testEdgeDensityHighContrastEdges() {
        let analyzer = J2KContentAnalyzer()
        let width = 32
        let height = 32
        // Vertical edge: left half = 0, right half = 255
        var samples = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in (width / 2)..<width {
                samples[y * width + x] = 255
            }
        }
        let density = analyzer.estimateEdgeDensity(samples: samples, width: width, height: height)
        XCTAssertGreaterThan(density, 0.0, "Edge image should have positive edge density")
    }

    func testEdgeDensityBlockPattern() {
        let analyzer = J2KContentAnalyzer()
        let width = 32
        let height = 32
        // Block pattern: 4×4 blocks alternating 0 and 255, producing strong edges
        var samples = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                if ((x / 4) + (y / 4)).isMultiple(of: 2) {
                    samples[y * width + x] = 255
                }
            }
        }
        let density = analyzer.estimateEdgeDensity(samples: samples, width: width, height: height)
        XCTAssertGreaterThan(density, 0.1, "Block pattern should have notable edge density")
    }

    func testEdgeDensityTooSmallImage() {
        let analyzer = J2KContentAnalyzer()
        // Image too small for Sobel (< 3 in either dimension)
        let samples = [Int32](repeating: 128, count: 4)
        let density = analyzer.estimateEdgeDensity(samples: samples, width: 2, height: 2)
        XCTAssertEqual(density, 0.0, "Too-small image should return zero")
    }

    func testFrequencyContentUniformImage() {
        let analyzer = J2KContentAnalyzer()
        let width = 32
        let height = 32
        let samples = [Int32](repeating: 128, count: width * height)
        let energy = analyzer.analyzeFrequencyContent(samples: samples, width: width, height: height)
        XCTAssertEqual(energy, 0.0, accuracy: 0.001, "Uniform image should have zero frequency energy")
    }

    func testFrequencyContentHighFrequency() {
        let analyzer = J2KContentAnalyzer()
        let width = 32
        let height = 32
        // Checkerboard pattern has high frequency content
        var samples = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                samples[y * width + x] = ((x + y).isMultiple(of: 2)) ? 0 : 255
            }
        }
        let energy = analyzer.analyzeFrequencyContent(samples: samples, width: width, height: height)
        XCTAssertGreaterThan(energy, 0.3, "Checkerboard should have high frequency energy")
    }

    func testFrequencyContentGradient() {
        let analyzer = J2KContentAnalyzer()
        let width = 32
        let height = 32
        // Smooth gradient has mostly low-frequency content
        var samples = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                samples[y * width + x] = Int32(x * 255 / (width - 1))
            }
        }
        let energy = analyzer.analyzeFrequencyContent(samples: samples, width: width, height: height)
        // Gradient should have some frequency energy but less than checkerboard
        XCTAssertLessThan(energy, 0.5, "Gradient should have moderate frequency energy")
    }

    func testFrequencyContentTooSmallImage() {
        let analyzer = J2KContentAnalyzer()
        let samples = [Int32](repeating: 128, count: 6)
        let energy = analyzer.analyzeFrequencyContent(samples: samples, width: 3, height: 2)
        XCTAssertEqual(energy, 0.0, "Too-small image should return zero")
    }

    func testTextureComplexityWeighting() {
        let analyzer = J2KContentAnalyzer()
        // Known inputs: 0.4 * edgeDensity + 0.6 * frequencyEnergy
        let complexity = analyzer.computeTextureComplexity(edgeDensity: 0.5, frequencyEnergy: 0.5)
        XCTAssertEqual(complexity, 0.5, accuracy: 0.001)

        let complexity2 = analyzer.computeTextureComplexity(edgeDensity: 1.0, frequencyEnergy: 0.0)
        XCTAssertEqual(complexity2, 0.4, accuracy: 0.001)

        let complexity3 = analyzer.computeTextureComplexity(edgeDensity: 0.0, frequencyEnergy: 1.0)
        XCTAssertEqual(complexity3, 0.6, accuracy: 0.001)
    }

    func testAnalyzeRegionReturnsValidMetrics() {
        let analyzer = J2KContentAnalyzer()
        let width = 32
        let height = 32
        var samples = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                samples[y * width + x] = ((x + y).isMultiple(of: 2)) ? 0 : 200
            }
        }
        let metrics = analyzer.analyzeRegion(samples: samples, width: width, height: height)
        XCTAssertGreaterThanOrEqual(metrics.edgeDensity, 0.0)
        XCTAssertLessThanOrEqual(metrics.edgeDensity, 1.0)
        XCTAssertGreaterThanOrEqual(metrics.frequencyEnergy, 0.0)
        XCTAssertLessThanOrEqual(metrics.frequencyEnergy, 1.0)
        XCTAssertGreaterThanOrEqual(metrics.textureComplexity, 0.0)
        XCTAssertLessThanOrEqual(metrics.textureComplexity, 1.0)
    }

    // MARK: - Block Size Selection Tests

    func testBlockSizeSelectionConservative() {
        let analyzer = J2KContentAnalyzer()

        // Low complexity → 64×64
        let lowMetrics = J2KContentMetrics(edgeDensity: 0.1, frequencyEnergy: 0.1, textureComplexity: 0.1)
        let lowSize = analyzer.selectBlockSize(for: lowMetrics, aggressiveness: .conservative)
        XCTAssertEqual(lowSize.width, 64)
        XCTAssertEqual(lowSize.height, 64)

        // Medium complexity → 32×32 (above 0.4 threshold)
        let medMetrics = J2KContentMetrics(edgeDensity: 0.5, frequencyEnergy: 0.5, textureComplexity: 0.5)
        let medSize = analyzer.selectBlockSize(for: medMetrics, aggressiveness: .conservative)
        XCTAssertEqual(medSize.width, 32)
        XCTAssertEqual(medSize.height, 32)

        // High complexity → 16×16 (above 0.7 threshold)
        let highMetrics = J2KContentMetrics(edgeDensity: 0.9, frequencyEnergy: 0.9, textureComplexity: 0.8)
        let highSize = analyzer.selectBlockSize(for: highMetrics, aggressiveness: .conservative)
        XCTAssertEqual(highSize.width, 16)
        XCTAssertEqual(highSize.height, 16)
    }

    func testBlockSizeSelectionBalanced() {
        let analyzer = J2KContentAnalyzer()

        // Low complexity → 64×64
        let lowMetrics = J2KContentMetrics(edgeDensity: 0.1, frequencyEnergy: 0.1, textureComplexity: 0.1)
        let lowSize = analyzer.selectBlockSize(for: lowMetrics, aggressiveness: .balanced)
        XCTAssertEqual(lowSize.width, 64)
        XCTAssertEqual(lowSize.height, 64)

        // Medium complexity → 32×32 (above 0.25 threshold)
        let medMetrics = J2KContentMetrics(edgeDensity: 0.3, frequencyEnergy: 0.3, textureComplexity: 0.3)
        let medSize = analyzer.selectBlockSize(for: medMetrics, aggressiveness: .balanced)
        XCTAssertEqual(medSize.width, 32)
        XCTAssertEqual(medSize.height, 32)

        // High complexity → 16×16 (above 0.5 threshold)
        let highMetrics = J2KContentMetrics(edgeDensity: 0.7, frequencyEnergy: 0.7, textureComplexity: 0.6)
        let highSize = analyzer.selectBlockSize(for: highMetrics, aggressiveness: .balanced)
        XCTAssertEqual(highSize.width, 16)
        XCTAssertEqual(highSize.height, 16)
    }

    func testBlockSizeSelectionAggressive() {
        let analyzer = J2KContentAnalyzer()

        // Low complexity → 64×64 (below 0.15 threshold)
        let lowMetrics = J2KContentMetrics(edgeDensity: 0.05, frequencyEnergy: 0.05, textureComplexity: 0.1)
        let lowSize = analyzer.selectBlockSize(for: lowMetrics, aggressiveness: .aggressive)
        XCTAssertEqual(lowSize.width, 64)
        XCTAssertEqual(lowSize.height, 64)

        // Medium complexity → 32×32 (above 0.15 threshold)
        let medMetrics = J2KContentMetrics(edgeDensity: 0.2, frequencyEnergy: 0.2, textureComplexity: 0.2)
        let medSize = analyzer.selectBlockSize(for: medMetrics, aggressiveness: .aggressive)
        XCTAssertEqual(medSize.width, 32)
        XCTAssertEqual(medSize.height, 32)

        // High complexity → 16×16 (above 0.3 threshold)
        let highMetrics = J2KContentMetrics(edgeDensity: 0.5, frequencyEnergy: 0.5, textureComplexity: 0.4)
        let highSize = analyzer.selectBlockSize(for: highMetrics, aggressiveness: .aggressive)
        XCTAssertEqual(highSize.width, 16)
        XCTAssertEqual(highSize.height, 16)
    }

    // MARK: - Content Metrics Tests

    func testContentMetricsClampValues() {
        let metrics = J2KContentMetrics(edgeDensity: 1.5, frequencyEnergy: -0.5, textureComplexity: 2.0)
        XCTAssertEqual(metrics.edgeDensity, 1.0)
        XCTAssertEqual(metrics.frequencyEnergy, 0.0)
        XCTAssertEqual(metrics.textureComplexity, 1.0)
    }

    func testContentMetricsEquality() {
        let metrics1 = J2KContentMetrics(edgeDensity: 0.5, frequencyEnergy: 0.3, textureComplexity: 0.4)
        let metrics2 = J2KContentMetrics(edgeDensity: 0.5, frequencyEnergy: 0.3, textureComplexity: 0.4)
        XCTAssertEqual(metrics1, metrics2)
    }

    // MARK: - Block Size Mode Tests

    func testBlockSizeModeEquality() {
        XCTAssertEqual(J2KBlockSizeMode.fixed, J2KBlockSizeMode.fixed)
        XCTAssertEqual(
            J2KBlockSizeMode.adaptive(aggressiveness: .balanced),
            J2KBlockSizeMode.adaptive(aggressiveness: .balanced)
        )
        XCTAssertNotEqual(J2KBlockSizeMode.fixed, J2KBlockSizeMode.adaptive(aggressiveness: .balanced))
        XCTAssertNotEqual(
            J2KBlockSizeMode.adaptive(aggressiveness: .conservative),
            J2KBlockSizeMode.adaptive(aggressiveness: .aggressive)
        )
    }

    // MARK: - Aggressiveness Tests

    func testAggressivenessAllCases() {
        XCTAssertEqual(J2KBlockSizeAggressiveness.allCases.count, 3)
        XCTAssertTrue(J2KBlockSizeAggressiveness.allCases.contains(.conservative))
        XCTAssertTrue(J2KBlockSizeAggressiveness.allCases.contains(.balanced))
        XCTAssertTrue(J2KBlockSizeAggressiveness.allCases.contains(.aggressive))
    }

    // MARK: - Encoding Configuration Integration Tests

    func testDefaultBlockSizeModeIsFixed() {
        let config = J2KEncodingConfiguration()
        XCTAssertEqual(config.blockSizeMode, .fixed)
        XCTAssertTrue(config.tileBlockSizeOverrides.isEmpty)
    }

    func testAdaptiveBlockSizeModeInConfiguration() {
        let config = J2KEncodingConfiguration(
            blockSizeMode: .adaptive(aggressiveness: .balanced)
        )
        XCTAssertEqual(config.blockSizeMode, .adaptive(aggressiveness: .balanced))
    }

    func testConfigurationWithOverrides() {
        let overrides: [Int: (width: Int, height: Int)] = [0: (32, 32), 3: (16, 16)]
        let config = J2KEncodingConfiguration(
            blockSizeMode: .adaptive(aggressiveness: .balanced),
            tileBlockSizeOverrides: overrides
        )
        XCTAssertEqual(config.tileBlockSizeOverrides.count, 2)
        XCTAssertEqual(config.tileBlockSizeOverrides[0]?.width, 32)
        XCTAssertEqual(config.tileBlockSizeOverrides[3]?.width, 16)
    }

    func testBackwardCompatibilityManualBlockSize() {
        // Existing code without blockSizeMode should still work
        let config = J2KEncodingConfiguration(
            codeBlockSize: (width: 64, height: 64)
        )
        XCTAssertEqual(config.codeBlockSize.width, 64)
        XCTAssertEqual(config.codeBlockSize.height, 64)
        XCTAssertEqual(config.blockSizeMode, .fixed)
    }

    func testPresetConfigurationsStillWork() {
        let fast = J2KEncodingPreset.fast.configuration()
        XCTAssertEqual(fast.codeBlockSize.width, 64)
        XCTAssertEqual(fast.blockSizeMode, .fixed)

        let balanced = J2KEncodingPreset.balanced.configuration()
        XCTAssertEqual(balanced.codeBlockSize.width, 32)
        XCTAssertEqual(balanced.blockSizeMode, .fixed)

        let quality = J2KEncodingPreset.quality.configuration()
        XCTAssertEqual(quality.codeBlockSize.width, 32)
        XCTAssertEqual(quality.blockSizeMode, .fixed)
    }

    // MARK: - Adaptive Block Size Selector Tests

    func testSelectorUniformImage() {
        let selector = J2KAdaptiveBlockSizeSelector(aggressiveness: .balanced)

        // Create uniform grayscale image
        let width = 64
        let height = 64
        let data = Data(repeating: 128, count: width * height)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: data
        )
        let image = J2KImage(width: width, height: height, components: [component])

        let sizes = selector.selectBlockSizes(for: image)
        XCTAssertEqual(sizes.count, 1)
        // Uniform images should get large blocks (low complexity)
        XCTAssertEqual(sizes[0].width, 64)
        XCTAssertEqual(sizes[0].height, 64)
    }

    func testSelectorCheckerboardImage() {
        let selector = J2KAdaptiveBlockSizeSelector(aggressiveness: .balanced)

        let width = 64
        let height = 64
        var bytes = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                bytes[y * width + x] = ((x + y).isMultiple(of: 2)) ? 0 : 255
            }
        }
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: Data(bytes)
        )
        let image = J2KImage(width: width, height: height, components: [component])

        let sizes = selector.selectBlockSizes(for: image)
        XCTAssertEqual(sizes.count, 1)
        // Checkerboard is high complexity → smaller blocks
        XCTAssertLessThanOrEqual(sizes[0].width, 32)
    }

    func testSelectorWithTileOverride() {
        let overrides: [Int: (width: Int, height: Int)] = [0: (16, 16)]
        let selector = J2KAdaptiveBlockSizeSelector(
            aggressiveness: .balanced,
            overrides: overrides
        )

        let width = 64
        let height = 64
        let data = Data(repeating: 128, count: width * height)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: data
        )
        let image = J2KImage(width: width, height: height, components: [component])

        let sizes = selector.selectBlockSizes(for: image)
        XCTAssertEqual(sizes.count, 1)
        // Override should be used instead of analysis
        XCTAssertEqual(sizes[0].width, 16)
        XCTAssertEqual(sizes[0].height, 16)
    }

    func testSelectorAnalyzeTile() {
        let selector = J2KAdaptiveBlockSizeSelector(aggressiveness: .balanced)

        let width = 32
        let height = 32
        let data = Data(repeating: 128, count: width * height)
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: data
        )
        let image = J2KImage(width: width, height: height, components: [component])

        let metrics = selector.analyzeTile(from: image, tileIndex: 0)
        XCTAssertEqual(metrics.edgeDensity, 0.0, accuracy: 0.001)
        XCTAssertEqual(metrics.frequencyEnergy, 0.0, accuracy: 0.001)
    }

    func testSelectorEmptyImage() {
        let selector = J2KAdaptiveBlockSizeSelector(aggressiveness: .balanced)
        let image = J2KImage(width: 0, height: 0, components: [])
        let sizes = selector.selectBlockSizes(for: image)
        XCTAssertEqual(sizes.count, 1)
    }

    // MARK: - Edge Case Tests

    func testEdgeDensityEmptySamples() {
        let analyzer = J2KContentAnalyzer()
        let density = analyzer.estimateEdgeDensity(samples: [], width: 0, height: 0)
        XCTAssertEqual(density, 0.0)
    }

    func testFrequencyContentEmptySamples() {
        let analyzer = J2KContentAnalyzer()
        let energy = analyzer.analyzeFrequencyContent(samples: [], width: 0, height: 0)
        XCTAssertEqual(energy, 0.0)
    }

    func testGradientImageModerateComplexity() {
        let analyzer = J2KContentAnalyzer()
        let width = 64
        let height = 64
        var samples = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                samples[y * width + x] = Int32(x * 255 / (width - 1))
            }
        }
        let metrics = analyzer.analyzeRegion(samples: samples, width: width, height: height)
        // Gradient has moderate edge density (consistent edges) and some frequency content
        XCTAssertGreaterThan(metrics.edgeDensity, 0.0)
        XCTAssertLessThan(metrics.textureComplexity, 0.8)
    }

    // MARK: - Benchmark Tests (Adaptive vs Fixed)

    func testAdaptiveVsFixedBlockSizeSelection() {
        // Verify that adaptive mode picks different sizes for different content
        let analyzer = J2KContentAnalyzer()

        // Uniform region → large blocks
        let uniformSamples = [Int32](repeating: 128, count: 64 * 64)
        let uniformMetrics = analyzer.analyzeRegion(
            samples: uniformSamples, width: 64, height: 64
        )
        let uniformSize = analyzer.selectBlockSize(
            for: uniformMetrics, aggressiveness: .balanced
        )

        // High-frequency region → small blocks
        var hfSamples = [Int32](repeating: 0, count: 64 * 64)
        for i in 0..<(64 * 64) {
            hfSamples[i] = Int32((i.isMultiple(of: 2)) ? 0 : 255)
        }
        let hfMetrics = analyzer.analyzeRegion(
            samples: hfSamples, width: 64, height: 64
        )
        let hfSize = analyzer.selectBlockSize(
            for: hfMetrics, aggressiveness: .balanced
        )

        // Adaptive should pick different sizes for different content
        XCTAssertGreaterThan(uniformSize.width, hfSize.width,
            "Adaptive should use larger blocks for uniform content")
    }

    func testAllAggressivenessLevelsProduceValidSizes() {
        let analyzer = J2KContentAnalyzer()
        let validSizes = [16, 32, 64]

        for aggressiveness in J2KBlockSizeAggressiveness.allCases {
            for complexity in stride(from: 0.0, through: 1.0, by: 0.1) {
                let metrics = J2KContentMetrics(
                    edgeDensity: complexity,
                    frequencyEnergy: complexity,
                    textureComplexity: complexity
                )
                let size = analyzer.selectBlockSize(
                    for: metrics, aggressiveness: aggressiveness
                )
                XCTAssertTrue(validSizes.contains(size.width),
                    "Width \(size.width) not valid for \(aggressiveness) at complexity \(complexity)")
                XCTAssertTrue(validSizes.contains(size.height),
                    "Height \(size.height) not valid for \(aggressiveness) at complexity \(complexity)")
            }
        }
    }
}
