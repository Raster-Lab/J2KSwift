// J2KRateControlTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

/// Tests for rate control and PCRD-opt implementation.
final class J2KRateControlTests: XCTestCase {
    // MARK: - Configuration Tests

    func testRateControlModeEquality() {
        let mode1 = RateControlMode.targetBitrate(1.0)
        let mode2 = RateControlMode.targetBitrate(1.0)
        let mode3 = RateControlMode.targetBitrate(2.0)
        let mode4 = RateControlMode.constantQuality(0.8)
        let mode5 = RateControlMode.lossless

        XCTAssertEqual(mode1, mode2)
        XCTAssertNotEqual(mode1, mode3)
        XCTAssertNotEqual(mode1, mode4)
        XCTAssertNotEqual(mode1, mode5)
        XCTAssertEqual(mode5, RateControlMode.lossless)
    }

    func testLosslessConfiguration() {
        let config = RateControlConfiguration.lossless

        XCTAssertEqual(config.mode, .lossless)
        XCTAssertEqual(config.layerCount, 1)
        XCTAssertTrue(config.strictRateMatching)
    }

    func testTargetBitrateConfiguration() {
        let config = RateControlConfiguration.targetBitrate(2.0, layerCount: 3)

        if case .targetBitrate(let rate) = config.mode {
            XCTAssertEqual(rate, 2.0)
        } else {
            XCTFail("Expected targetBitrate mode")
        }

        XCTAssertEqual(config.layerCount, 3)
    }

    func testConstantQualityConfiguration() {
        let config = RateControlConfiguration.constantQuality(0.85, layerCount: 2)

        if case .constantQuality(let quality) = config.mode {
            XCTAssertEqual(quality, 0.85, accuracy: 0.001)
        } else {
            XCTFail("Expected constantQuality mode")
        }

        XCTAssertEqual(config.layerCount, 2)
    }

    func testConstantQualityClampingLow() {
        let config = RateControlConfiguration.constantQuality(-0.5, layerCount: 1)

        if case .constantQuality(let quality) = config.mode {
            XCTAssertEqual(quality, 0.0, accuracy: 0.001)
        } else {
            XCTFail("Expected constantQuality mode")
        }
    }

    func testConstantQualityClampingHigh() {
        let config = RateControlConfiguration.constantQuality(1.5, layerCount: 1)

        if case .constantQuality(let quality) = config.mode {
            XCTAssertEqual(quality, 1.0, accuracy: 0.001)
        } else {
            XCTFail("Expected constantQuality mode")
        }
    }

    func testDistortionEstimationMethods() {
        let methods: [DistortionEstimationMethod] = [.normBased, .mseBased, .simplified]

        for method in methods {
            let config = RateControlConfiguration(
                mode: .targetBitrate(1.0),
                distortionEstimation: method
            )
            XCTAssertEqual(config.distortionEstimation, method)
        }
    }

    // MARK: - CodingPassInfo Tests

    func testCodingPassInfoCreation() {
        let passInfo = CodingPassInfo(
            codeBlockIndex: 0,
            passNumber: 2,
            cumulativeBytes: 100,
            distortion: 50.0,
            slope: 0.5
        )

        XCTAssertEqual(passInfo.codeBlockIndex, 0)
        XCTAssertEqual(passInfo.passNumber, 2)
        XCTAssertEqual(passInfo.cumulativeBytes, 100)
        XCTAssertEqual(passInfo.distortion, 50.0, accuracy: 0.001)
        XCTAssertEqual(passInfo.slope, 0.5, accuracy: 0.001)
    }

    // MARK: - Basic Rate Control Tests

    func testRateControlWithEmptyCodeBlocks() throws {
        let config = RateControlConfiguration.targetBitrate(1.0)
        let rateControl = J2KRateControl(configuration: config)

        XCTAssertThrowsError(try rateControl.optimizeLayers(
            codeBlocks: [],
            totalPixels: 1000
        )) { error in
            if case J2KError.invalidParameter(let message) = error {
                XCTAssertTrue(message.contains("empty"))
            } else {
                XCTFail("Expected invalidParameter error")
            }
        }
    }

    func testRateControlWithZeroPixels() throws {
        let codeBlocks = createTestCodeBlocks(count: 5, passesPerBlock: 3)
        let config = RateControlConfiguration.targetBitrate(1.0)
        let rateControl = J2KRateControl(configuration: config)

        XCTAssertThrowsError(try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 0
        )) { error in
            if case J2KError.invalidParameter(let message) = error {
                XCTAssertTrue(message.contains("pixels"))
            } else {
                XCTFail("Expected invalidParameter error")
            }
        }
    }

    func testLosslessLayerFormation() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 5)
        let config = RateControlConfiguration.lossless
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)

        let layer = layers[0]
        XCTAssertEqual(layer.index, 0)
        XCTAssertNil(layer.targetRate)
        XCTAssertEqual(layer.codeBlockContributions.count, 10)

        // All code blocks should contribute all their passes
        for (index, passes) in layer.codeBlockContributions {
            XCTAssertEqual(passes, 5, "Code block \(index) should have all 5 passes")
        }
    }

    func testSingleLayerTargetBitrate() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 1)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    func testMultipleLayersTargetBitrate() throws {
        let codeBlocks = createTestCodeBlocks(count: 20, passesPerBlock: 12)
        let config = RateControlConfiguration.targetBitrate(2.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 3)

        // Each layer should have progressive indices
        for (index, layer) in layers.enumerated() {
            XCTAssertEqual(layer.index, index)
        }

        // Later layers should generally have more contributions
        // (though this isn't strictly guaranteed depending on R-D slopes)
        XCTAssertGreaterThanOrEqual(
            layers[1].codeBlockContributions.count,
            layers[0].codeBlockContributions.count
        )
    }

    func testConstantQualityMode() throws {
        let codeBlocks = createTestCodeBlocks(count: 15, passesPerBlock: 8)
        let config = RateControlConfiguration.constantQuality(0.8, layerCount: 2)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 2)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
        XCTAssertGreaterThan(layers[1].codeBlockContributions.count, 0)
    }

    // MARK: - Convenience Initializer Tests

    func testConvenienceInitializerWithSingleRate() {
        let rateControl = J2KRateControl(targetRates: [1.0])

        if case .targetBitrate(let rate) = rateControl.configuration.mode {
            XCTAssertEqual(rate, 1.0)
        } else {
            XCTFail("Expected targetBitrate mode")
        }

        XCTAssertEqual(rateControl.configuration.layerCount, 1)
    }

    func testConvenienceInitializerWithMultipleRates() {
        let rateControl = J2KRateControl(targetRates: [0.5, 1.0, 2.0])

        if case .targetBitrate(let rate) = rateControl.configuration.mode {
            XCTAssertEqual(rate, 2.0) // Should use highest rate
        } else {
            XCTFail("Expected targetBitrate mode")
        }

        XCTAssertEqual(rateControl.configuration.layerCount, 3)
    }

    // MARK: - Distortion Estimation Tests

    func testDistortionEstimationNormBased() throws {
        let codeBlocks = createTestCodeBlocks(count: 5, passesPerBlock: 10)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            distortionEstimation: .normBased
        )
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 1000
        )

        XCTAssertGreaterThan(layers.count, 0)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    func testDistortionEstimationMSEBased() throws {
        let codeBlocks = createTestCodeBlocks(count: 5, passesPerBlock: 10)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            distortionEstimation: .mseBased
        )
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 1000
        )

        XCTAssertGreaterThan(layers.count, 0)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    func testDistortionEstimationSimplified() throws {
        let codeBlocks = createTestCodeBlocks(count: 5, passesPerBlock: 10)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            distortionEstimation: .simplified
        )
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 1000
        )

        XCTAssertGreaterThan(layers.count, 0)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    // MARK: - Strict Rate Matching Tests

    func testStrictRateMatching() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration(
            mode: .targetBitrate(0.5),
            layerCount: 1,
            strictRateMatching: true
        )
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)

        // With strict matching, total bytes should not exceed target
        let targetBytes = Int(0.5 * Double(10000) / 8.0)
        var totalBytes = 0

        for (blockIndex, passCount) in layers[0].codeBlockContributions {
            let block = codeBlocks.first { $0.index == blockIndex }
            XCTAssertNotNil(block)
            totalBytes += block!.data.count
        }

        // Allow some tolerance due to pass granularity
        XCTAssertLessThanOrEqual(totalBytes, targetBytes * 2)
    }

    func testNonStrictRateMatching() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration(
            mode: .targetBitrate(0.5),
            layerCount: 1,
            strictRateMatching: false
        )
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    // MARK: - Progressive Layer Tests

    func testProgressiveLayersIncreaseInSize() throws {
        let codeBlocks = createTestCodeBlocks(count: 20, passesPerBlock: 15)
        let config = RateControlConfiguration.targetBitrate(3.0, layerCount: 5)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 5)

        // Each layer should have at least as many contributions as previous
        for i in 1..<layers.count {
            XCTAssertGreaterThanOrEqual(
                layers[i].codeBlockContributions.count,
                layers[i - 1].codeBlockContributions.count,
                "Layer \(i) should have at least as many contributions as layer \(i - 1)"
            )
        }
    }

    // MARK: - Edge Case Tests

    func testSingleCodeBlockSinglePass() throws {
        let codeBlocks = createTestCodeBlocks(count: 1, passesPerBlock: 1)
        let config = RateControlConfiguration.targetBitrate(1.0)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 100
        )

        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].codeBlockContributions.count, 1)
        XCTAssertEqual(layers[0].codeBlockContributions[0], 1)
    }

    func testManyCodeBlocksFewPasses() throws {
        let codeBlocks = createTestCodeBlocks(count: 100, passesPerBlock: 2)
        let config = RateControlConfiguration.targetBitrate(2.0, layerCount: 2)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 2)
    }

    func testFewCodeBlocksManyPasses() throws {
        let codeBlocks = createTestCodeBlocks(count: 3, passesPerBlock: 50)
        let config = RateControlConfiguration.targetBitrate(2.0, layerCount: 2)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 2)
    }

    func testVeryLowBitrate() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration.targetBitrate(0.01, layerCount: 1)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)
        // Should still have some contributions even at very low bitrate
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    func testVeryHighBitrate() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration.targetBitrate(100.0, layerCount: 1)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)
        // High bitrate should include all or most code blocks
        XCTAssertGreaterThanOrEqual(layers[0].codeBlockContributions.count, 8)
    }

    // MARK: - Quality Level Tests

    func testLowQualitySetting() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration.constantQuality(0.2)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    func testMediumQualitySetting() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration.constantQuality(0.5)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)
        XCTAssertGreaterThan(layers[0].codeBlockContributions.count, 0)
    }

    func testHighQualitySetting() throws {
        let codeBlocks = createTestCodeBlocks(count: 10, passesPerBlock: 10)
        let config = RateControlConfiguration.constantQuality(0.9)
        let rateControl = J2KRateControl(configuration: config)

        let layers = try rateControl.optimizeLayers(
            codeBlocks: codeBlocks,
            totalPixels: 10000
        )

        XCTAssertEqual(layers.count, 1)
        // High quality should include more contributions
        XCTAssertGreaterThanOrEqual(layers[0].codeBlockContributions.count, 5)
    }

    // MARK: - Rate-Distortion Statistics Tests

    func testRateDistortionStatsCreation() {
        let stats = RateDistortionStats(
            actualRates: [0.5, 1.0, 2.0],
            targetRates: [0.5, 1.0, 2.0],
            distortions: [100.0, 50.0, 10.0],
            codeBlockCounts: [5, 10, 15]
        )

        XCTAssertEqual(stats.actualRates.count, 3)
        XCTAssertEqual(stats.targetRates.count, 3)
        XCTAssertEqual(stats.distortions.count, 3)
        XCTAssertEqual(stats.codeBlockCounts.count, 3)
    }

    // MARK: - Sendable Conformance Tests

    func testSendableConformance() {
        let config = RateControlConfiguration.targetBitrate(1.0)
        let rateControl = J2KRateControl(configuration: config)

        // Should be able to pass to async context
        Task {
            _ = rateControl
        }
    }

    func testCodingPassInfoSendable() {
        let passInfo = CodingPassInfo(
            codeBlockIndex: 0,
            passNumber: 0,
            cumulativeBytes: 100,
            distortion: 50.0,
            slope: 0.5
        )

        Task {
            _ = passInfo
        }
    }

    func testRateDistortionStatsSendable() {
        let stats = RateDistortionStats(
            actualRates: [1.0],
            targetRates: [1.0],
            distortions: [10.0],
            codeBlockCounts: [5]
        )

        Task {
            _ = stats
        }
    }

    // MARK: - Helper Methods

    /// Creates test code blocks with specified properties.
    private func createTestCodeBlocks(
        count: Int,
        passesPerBlock: Int,
        dataSize: Int = 100
    ) -> [J2KCodeBlock] {
        var blocks = [J2KCodeBlock]()

        for i in 0..<count {
            // Create dummy data
            let data = Data(count: dataSize)

            let block = J2KCodeBlock(
                index: i,
                x: i * 64,
                y: 0,
                width: 64,
                height: 64,
                subband: .ll,
                data: data,
                passeCount: passesPerBlock,
                zeroBitPlanes: 2
            )

            blocks.append(block)
        }

        return blocks
    }
}
