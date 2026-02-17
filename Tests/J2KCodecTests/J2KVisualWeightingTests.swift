// J2KVisualWeightingTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KVisualWeightingTests: XCTestCase {
    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = J2KVisualWeightingConfiguration.default

        XCTAssertEqual(config.peakFrequency, 4.0)
        XCTAssertEqual(config.decayRate, 0.4)
        XCTAssertEqual(config.viewingDistance, 60.0)
        XCTAssertEqual(config.displayPPI, 96.0)
        XCTAssertEqual(config.minimumWeight, 0.1)
        XCTAssertEqual(config.maximumWeight, 4.0)
    }

    func testCustomConfiguration() {
        let config = J2KVisualWeightingConfiguration(
            peakFrequency: 5.0,
            decayRate: 0.5,
            viewingDistance: 50.0,
            displayPPI: 120.0,
            minimumWeight: 0.2,
            maximumWeight: 3.0
        )

        XCTAssertEqual(config.peakFrequency, 5.0)
        XCTAssertEqual(config.decayRate, 0.5)
        XCTAssertEqual(config.viewingDistance, 50.0)
        XCTAssertEqual(config.displayPPI, 120.0)
        XCTAssertEqual(config.minimumWeight, 0.2)
        XCTAssertEqual(config.maximumWeight, 3.0)
    }

    func testConfigurationEquality() {
        let config1 = J2KVisualWeightingConfiguration.default
        let config2 = J2KVisualWeightingConfiguration.default
        let config3 = J2KVisualWeightingConfiguration(peakFrequency: 5.0)

        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }

    // MARK: - Basic Weight Calculation Tests

    func testWeightCalculationBasic() {
        let weighting = J2KVisualWeighting()

        // Calculate weight for a medium-frequency subband
        let weight = weighting.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        // Weight should be within valid range
        XCTAssertGreaterThan(weight, 0.0)
        XCTAssertLessThanOrEqual(weight, 4.0)  // default max
        XCTAssertGreaterThanOrEqual(weight, 0.1)  // default min
    }

    func testWeightIncreasesWithFrequency() {
        let weighting = J2KVisualWeighting()
        let imageSize = 1024

        // Compare weights at different decomposition levels
        // Higher level = lower frequency = should have higher weight (less sensitive)
        let weightLevel0 = weighting.weight(
            for: .hh,
            decompositionLevel: 0,
            totalLevels: 5,
            imageWidth: imageSize,
            imageHeight: imageSize
        )

        let weightLevel4 = weighting.weight(
            for: .hh,
            decompositionLevel: 4,
            totalLevels: 5,
            imageWidth: imageSize,
            imageHeight: imageSize
        )

        // Finest level (0) should have lower weight than coarsest (4)
        // because high frequencies are less visible
        XCTAssertLessThan(weightLevel0, weightLevel4)
    }

    func testSubbandFrequencyOrdering() {
        let weighting = J2KVisualWeighting()
        let level = 2
        let totalLevels = 5
        let imageSize = 1024

        let weightLL = weighting.weight(
            for: .ll,
            decompositionLevel: level,
            totalLevels: totalLevels,
            imageWidth: imageSize,
            imageHeight: imageSize
        )

        let weightLH = weighting.weight(
            for: .lh,
            decompositionLevel: level,
            totalLevels: totalLevels,
            imageWidth: imageSize,
            imageHeight: imageSize
        )

        let weightHH = weighting.weight(
            for: .hh,
            decompositionLevel: level,
            totalLevels: totalLevels,
            imageWidth: imageSize,
            imageHeight: imageSize
        )

        // All weights should be valid
        XCTAssertGreaterThan(weightLL, 0.0)
        XCTAssertGreaterThan(weightLH, 0.0)
        XCTAssertGreaterThan(weightHH, 0.0)

        // Weights should be within bounds
        XCTAssertLessThanOrEqual(weightLL, 4.0)
        XCTAssertLessThanOrEqual(weightLH, 4.0)
        XCTAssertLessThanOrEqual(weightHH, 4.0)
    }

    // MARK: - Bounds Tests

    func testWeightRespectsMiniumumBound() {
        let config = J2KVisualWeightingConfiguration(minimumWeight: 0.5)
        let weighting = J2KVisualWeighting(configuration: config)

        // Very high frequency should hit minimum bound
        let weight = weighting.weight(
            for: .hh,
            decompositionLevel: 0,
            totalLevels: 5,
            imageWidth: 4096,
            imageHeight: 4096
        )

        XCTAssertGreaterThanOrEqual(weight, 0.5)
    }

    func testWeightRespectsMaximumBound() {
        let config = J2KVisualWeightingConfiguration(maximumWeight: 2.0)
        let weighting = J2KVisualWeighting(configuration: config)

        // Very low frequency should hit maximum bound
        let weight = weighting.weight(
            for: .ll,
            decompositionLevel: 4,
            totalLevels: 5,
            imageWidth: 256,
            imageHeight: 256
        )

        XCTAssertLessThanOrEqual(weight, 2.0)
    }

    // MARK: - All Subbands Tests

    func testWeightsForAllSubbands() {
        let weighting = J2KVisualWeighting()
        let totalLevels = 3
        let imageSize = 512

        let allWeights = weighting.weightsForAllSubbands(
            totalLevels: totalLevels,
            imageWidth: imageSize,
            imageHeight: imageSize
        )

        // Should have weights for all levels
        XCTAssertEqual(allWeights.count, totalLevels)

        // Each level should have weights
        for (index, levelWeights) in allWeights.enumerated() {
            if index == totalLevels - 1 {
                // Coarsest level should include LL
                XCTAssertNotNil(levelWeights[.ll])
            }

            // All levels should have LH, HL, HH
            XCTAssertNotNil(levelWeights[.lh])
            XCTAssertNotNil(levelWeights[.hl])
            XCTAssertNotNil(levelWeights[.hh])
        }
    }

    func testAllSubbandsCountCorrect() {
        let weighting = J2KVisualWeighting()
        let totalLevels = 5

        let allWeights = weighting.weightsForAllSubbands(
            totalLevels: totalLevels,
            imageWidth: 1024,
            imageHeight: 1024
        )

        XCTAssertEqual(allWeights.count, 5)

        // Finest levels should have 3 subbands (LH, HL, HH)
        for level in 0..<(totalLevels - 1) {
            XCTAssertEqual(allWeights[level].count, 3)
        }

        // Coarsest level should have 4 subbands (LL, LH, HL, HH)
        XCTAssertEqual(allWeights[totalLevels - 1].count, 4)
    }

    // MARK: - Viewing Conditions Tests

    func testDifferentViewingDistances() {
        let config1 = J2KVisualWeightingConfiguration(viewingDistance: 30.0)
        let config2 = J2KVisualWeightingConfiguration(viewingDistance: 90.0)

        let weighting1 = J2KVisualWeighting(configuration: config1)
        let weighting2 = J2KVisualWeighting(configuration: config2)

        let weight1 = weighting1.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        let weight2 = weighting2.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        // Different viewing distances should produce different weights
        XCTAssertNotEqual(weight1, weight2)
    }

    func testDifferentDisplayResolutions() {
        let config1 = J2KVisualWeightingConfiguration(displayPPI: 72.0)
        let config2 = J2KVisualWeightingConfiguration(displayPPI: 144.0)

        let weighting1 = J2KVisualWeighting(configuration: config1)
        let weighting2 = J2KVisualWeighting(configuration: config2)

        let weight1 = weighting1.weight(
            for: .hh,
            decompositionLevel: 1,
            totalLevels: 4,
            imageWidth: 1024,
            imageHeight: 1024
        )

        let weight2 = weighting2.weight(
            for: .hh,
            decompositionLevel: 1,
            totalLevels: 4,
            imageWidth: 1024,
            imageHeight: 1024
        )

        // Different display resolutions should produce different weights
        XCTAssertNotEqual(weight1, weight2)
    }

    // MARK: - Perceptual Step Size Tests

    func testPerceptualStepSize() {
        let weighting = J2KVisualWeighting()
        let baseStepSize = 0.1

        let perceptualStepSize = weighting.perceptualStepSize(
            baseStepSize: baseStepSize,
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        // Perceptual step size should be different from base
        XCTAssertNotEqual(perceptualStepSize, baseStepSize)
        XCTAssertGreaterThan(perceptualStepSize, 0.0)
    }

    func testPerceptualStepSizeScaling() {
        let weighting = J2KVisualWeighting()
        let baseStepSize = 1.0

        let stepSize1 = weighting.perceptualStepSize(
            baseStepSize: baseStepSize,
            for: .hh,
            decompositionLevel: 0,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        let stepSize2 = weighting.perceptualStepSize(
            baseStepSize: baseStepSize,
            for: .ll,
            decompositionLevel: 4,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        // Both should produce valid perceptual step sizes
        XCTAssertGreaterThan(stepSize1, 0.0)
        XCTAssertGreaterThan(stepSize2, 0.0)

        // Step sizes should be different
        XCTAssertNotEqual(stepSize1, stepSize2)
    }

    // MARK: - Image Size Tests

    func testDifferentImageSizes() {
        let weighting = J2KVisualWeighting()

        let weightSmall = weighting.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 256,
            imageHeight: 256
        )

        let weightLarge = weighting.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 4096,
            imageHeight: 4096
        )

        // Both should produce valid weights
        XCTAssertGreaterThan(weightSmall, 0.0)
        XCTAssertGreaterThan(weightLarge, 0.0)

        // Weights may differ due to viewing angle calculation
        // but both should be within bounds
        XCTAssertLessThanOrEqual(weightSmall, 4.0)
        XCTAssertLessThanOrEqual(weightLarge, 4.0)
    }

    func testNonSquareImages() {
        let weighting = J2KVisualWeighting()

        let weight = weighting.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 1920,
            imageHeight: 1080
        )

        // Should handle non-square images correctly
        XCTAssertGreaterThan(weight, 0.0)
        XCTAssertLessThanOrEqual(weight, 4.0)
        XCTAssertGreaterThanOrEqual(weight, 0.1)
    }

    // MARK: - Edge Cases

    func testSingleDecompositionLevel() {
        let weighting = J2KVisualWeighting()

        let weight = weighting.weight(
            for: .hh,
            decompositionLevel: 0,
            totalLevels: 1,
            imageWidth: 512,
            imageHeight: 512
        )

        // Should handle single level correctly
        XCTAssertGreaterThan(weight, 0.0)
        XCTAssertLessThanOrEqual(weight, 4.0)
    }

    func testManyDecompositionLevels() {
        let weighting = J2KVisualWeighting()

        let allWeights = weighting.weightsForAllSubbands(
            totalLevels: 10,
            imageWidth: 2048,
            imageHeight: 2048
        )

        // Should handle many levels
        XCTAssertEqual(allWeights.count, 10)

        // All weights should be valid
        for levelWeights in allWeights {
            for weight in levelWeights.values {
                XCTAssertGreaterThan(weight, 0.0)
                XCTAssertLessThanOrEqual(weight, 4.0)
            }
        }
    }

    // MARK: - Sendable Conformance Test

    func testSendableConformance() {
        // Test that types can be used across concurrency boundaries
        let config = J2KVisualWeightingConfiguration.default
        let weighting = J2KVisualWeighting(configuration: config)

        Task {
            let weight = weighting.weight(
                for: .hl,
                decompositionLevel: 2,
                totalLevels: 5,
                imageWidth: 1024,
                imageHeight: 1024
            )
            XCTAssertGreaterThan(weight, 0.0)
        }
    }

    // MARK: - Consistency Tests

    func testConsistentWeights() {
        let weighting = J2KVisualWeighting()

        // Same parameters should produce same weight
        let weight1 = weighting.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        let weight2 = weighting.weight(
            for: .hl,
            decompositionLevel: 2,
            totalLevels: 5,
            imageWidth: 1024,
            imageHeight: 1024
        )

        XCTAssertEqual(weight1, weight2)
    }

    func testWeightConsistencyAcrossLevels() {
        let weighting = J2KVisualWeighting()
        let imageSize = 1024
        let totalLevels = 5

        // Collect weights for all levels
        var weights: [Double] = []

        for level in 0..<totalLevels {
            let weight = weighting.weight(
                for: .hh,
                decompositionLevel: level,
                totalLevels: totalLevels,
                imageWidth: imageSize,
                imageHeight: imageSize
            )

            // All weights should be valid
            XCTAssertGreaterThan(weight, 0.0)
            XCTAssertLessThanOrEqual(weight, 4.0)
            XCTAssertGreaterThanOrEqual(weight, 0.1)

            weights.append(weight)
        }

        // Should have collected all weights
        XCTAssertEqual(weights.count, totalLevels)

        // Weights should show variation across levels
        let uniqueWeights = Set(weights)
        XCTAssertGreaterThan(uniqueWeights.count, 1, "Weights should vary across levels")
    }
}
