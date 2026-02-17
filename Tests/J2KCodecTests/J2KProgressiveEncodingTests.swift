// J2KProgressiveEncodingTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-07.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KProgressiveEncodingTests: XCTestCase {
    // MARK: - Progressive Mode Tests

    func testSNRProgressiveMode() throws {
        let mode = J2KProgressiveMode.snr(layers: 8)

        XCTAssertEqual(mode.qualityLayers, 8)
        XCTAssertNil(mode.decompositionLevels)
        XCTAssertEqual(mode.recommendedProgressionOrder, .lrcp)
        XCTAssertNoThrow(try mode.validate())
    }

    func testSpatialProgressiveMode() throws {
        let mode = J2KProgressiveMode.spatial(maxLevel: 5)

        XCTAssertEqual(mode.qualityLayers, 1)
        XCTAssertEqual(mode.decompositionLevels, 5)
        XCTAssertEqual(mode.recommendedProgressionOrder, .rlcp)
        XCTAssertNoThrow(try mode.validate())
    }

    func testLayerProgressiveModeQualityFirst() throws {
        let mode = J2KProgressiveMode.layerProgressive(layers: 6, resolutionFirst: false)

        XCTAssertEqual(mode.qualityLayers, 6)
        XCTAssertNil(mode.decompositionLevels)
        XCTAssertEqual(mode.recommendedProgressionOrder, .lrcp)
        XCTAssertNoThrow(try mode.validate())
    }

    func testLayerProgressiveModeResolutionFirst() throws {
        let mode = J2KProgressiveMode.layerProgressive(layers: 6, resolutionFirst: true)

        XCTAssertEqual(mode.qualityLayers, 6)
        XCTAssertNil(mode.decompositionLevels)
        XCTAssertEqual(mode.recommendedProgressionOrder, .rpcl)
        XCTAssertNoThrow(try mode.validate())
    }

    func testCombinedProgressiveMode() throws {
        let mode = J2KProgressiveMode.combined(qualityLayers: 8, decompositionLevels: 5)

        XCTAssertEqual(mode.qualityLayers, 8)
        XCTAssertEqual(mode.decompositionLevels, 5)
        XCTAssertEqual(mode.recommendedProgressionOrder, .rpcl)
        XCTAssertNoThrow(try mode.validate())
    }

    func testNoneProgressiveMode() throws {
        let mode = J2KProgressiveMode.none

        XCTAssertEqual(mode.qualityLayers, 1)
        XCTAssertNil(mode.decompositionLevels)
        XCTAssertEqual(mode.recommendedProgressionOrder, .lrcp)
        XCTAssertNoThrow(try mode.validate())
    }

    // MARK: - Progressive Mode Validation Tests

    func testSNRModeInvalidLayers() throws {
        let mode1 = J2KProgressiveMode.snr(layers: 0)
        XCTAssertThrowsError(try mode1.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Quality layers"))
        }

        let mode2 = J2KProgressiveMode.snr(layers: 25)
        XCTAssertThrowsError(try mode2.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Quality layers"))
        }
    }

    func testSpatialModeInvalidLevel() throws {
        let mode1 = J2KProgressiveMode.spatial(maxLevel: -1)
        XCTAssertThrowsError(try mode1.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Decomposition level"))
        }

        let mode2 = J2KProgressiveMode.spatial(maxLevel: 15)
        XCTAssertThrowsError(try mode2.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Decomposition level"))
        }
    }

    func testCombinedModeInvalidParameters() throws {
        let mode1 = J2KProgressiveMode.combined(qualityLayers: 0, decompositionLevels: 5)
        XCTAssertThrowsError(try mode1.validate())

        let mode2 = J2KProgressiveMode.combined(qualityLayers: 5, decompositionLevels: -1)
        XCTAssertThrowsError(try mode2.validate())
    }

    // MARK: - Progressive Decoding Options Tests

    func testDecodingOptionsDefault() throws {
        let options = J2KProgressiveDecodingOptions()

        XCTAssertNil(options.maxLayer)
        XCTAssertNil(options.maxResolutionLevel)
        XCTAssertNil(options.region)
        XCTAssertTrue(options.earlyStop)
    }

    func testDecodingOptionsWithLayer() throws {
        let options = J2KProgressiveDecodingOptions(maxLayer: 3)

        XCTAssertEqual(options.maxLayer, 3)
        XCTAssertNil(options.maxResolutionLevel)
        XCTAssertNil(options.region)
        XCTAssertTrue(options.earlyStop)
    }

    func testDecodingOptionsWithResolution() throws {
        let options = J2KProgressiveDecodingOptions(maxResolutionLevel: 2)

        XCTAssertNil(options.maxLayer)
        XCTAssertEqual(options.maxResolutionLevel, 2)
        XCTAssertNil(options.region)
        XCTAssertTrue(options.earlyStop)
    }

    func testDecodingOptionsWithRegion() throws {
        let region = J2KRegion(x: 100, y: 100, width: 512, height: 512)
        let options = J2KProgressiveDecodingOptions(region: region)

        XCTAssertNil(options.maxLayer)
        XCTAssertNil(options.maxResolutionLevel)
        XCTAssertEqual(options.region, region)
        XCTAssertTrue(options.earlyStop)
    }

    func testDecodingOptionsNoEarlyStop() throws {
        let options = J2KProgressiveDecodingOptions(earlyStop: false)

        XCTAssertFalse(options.earlyStop)
    }

    // MARK: - Region Tests

    func testRegionCreation() throws {
        let region = J2KRegion(x: 10, y: 20, width: 100, height: 200)

        XCTAssertEqual(region.x, 10)
        XCTAssertEqual(region.y, 20)
        XCTAssertEqual(region.width, 100)
        XCTAssertEqual(region.height, 200)
    }

    func testRegionValidation() throws {
        let region = J2KRegion(x: 100, y: 100, width: 512, height: 512)

        // Valid region
        XCTAssertNoThrow(try region.validate(imageWidth: 1024, imageHeight: 1024))

        // Region extends beyond bounds
        XCTAssertThrowsError(try region.validate(imageWidth: 500, imageHeight: 1024)) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("extends beyond"))
        }
    }

    func testRegionValidationNegativeCoordinates() throws {
        let region = J2KRegion(x: -10, y: 20, width: 100, height: 100)

        XCTAssertThrowsError(try region.validate(imageWidth: 1024, imageHeight: 1024)) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("non-negative"))
        }
    }

    func testRegionValidationZeroDimensions() throws {
        let region = J2KRegion(x: 10, y: 10, width: 0, height: 100)

        XCTAssertThrowsError(try region.validate(imageWidth: 1024, imageHeight: 1024)) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("positive"))
        }
    }

    // MARK: - Progressive Encoding Strategy Tests

    func testQualityProgressiveStrategy() throws {
        let strategy = J2KProgressiveEncodingStrategy.qualityProgressive(layers: 8)

        XCTAssertEqual(strategy.mode.qualityLayers, 8)
        XCTAssertTrue(strategy.snrScalable)
        XCTAssertFalse(strategy.spatialScalable)
        XCTAssertNil(strategy.layerBitrates)
        XCTAssertNoThrow(try strategy.validate())
    }

    func testResolutionProgressiveStrategy() throws {
        let strategy = J2KProgressiveEncodingStrategy.resolutionProgressive(levels: 5)

        XCTAssertEqual(strategy.mode.decompositionLevels, 5)
        XCTAssertFalse(strategy.snrScalable)
        XCTAssertTrue(strategy.spatialScalable)
        XCTAssertNil(strategy.layerBitrates)
        XCTAssertNoThrow(try strategy.validate())
    }

    func testStreamingStrategy() throws {
        let strategy = J2KProgressiveEncodingStrategy.streaming(layers: 6, levels: 4)

        XCTAssertEqual(strategy.mode.qualityLayers, 6)
        XCTAssertEqual(strategy.mode.decompositionLevels, 4)
        XCTAssertTrue(strategy.snrScalable)
        XCTAssertTrue(strategy.spatialScalable)
        XCTAssertNil(strategy.layerBitrates)
        XCTAssertNoThrow(try strategy.validate())
    }

    func testStrategyWithLayerBitrates() throws {
        let bitrates = [0.1, 0.2, 0.4, 0.8, 1.6]
        let strategy = J2KProgressiveEncodingStrategy(
            mode: .snr(layers: 5),
            layerBitrates: bitrates
        )

        XCTAssertEqual(strategy.layerBitrates, bitrates)
        XCTAssertNoThrow(try strategy.validate())
    }

    func testStrategyInvalidBitrateCount() throws {
        let bitrates = [0.1, 0.2, 0.4]  // 3 bitrates
        let strategy = J2KProgressiveEncodingStrategy(
            mode: .snr(layers: 5),  // 5 layers
            layerBitrates: bitrates
        )

        XCTAssertThrowsError(try strategy.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("must match"))
        }
    }

    func testStrategyNonIncreasingBitrates() throws {
        let bitrates = [0.1, 0.2, 0.2, 0.4, 0.8]  // Not strictly increasing
        let strategy = J2KProgressiveEncodingStrategy(
            mode: .snr(layers: 5),
            layerBitrates: bitrates
        )

        XCTAssertThrowsError(try strategy.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("strictly increasing"))
        }
    }

    func testStrategyNegativeBitrate() throws {
        let bitrates = [0.1, -0.2, 0.4, 0.8, 1.6]
        let strategy = J2KProgressiveEncodingStrategy(
            mode: .snr(layers: 5),
            layerBitrates: bitrates
        )

        XCTAssertThrowsError(try strategy.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("positive"))
        }
    }

    // MARK: - Configuration Extension Tests

    func testConfigurationProgressiveModeDerived() throws {
        var config1 = J2KEncodingConfiguration()
        config1.qualityLayers = 5
        config1.decompositionLevels = 3

        let mode1 = config1.progressiveMode
        XCTAssertEqual(mode1.qualityLayers, 5)
        XCTAssertEqual(mode1.decompositionLevels, 3)

        var config2 = J2KEncodingConfiguration()
        config2.qualityLayers = 1
        config2.decompositionLevels = 0

        let mode2 = config2.progressiveMode
        switch mode2 {
        case .none:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected .none mode")
        }
    }

    func testConfigurationProgressiveModeQualityOnly() throws {
        var config = J2KEncodingConfiguration()
        config.qualityLayers = 8
        config.decompositionLevels = 0

        let mode = config.progressiveMode
        XCTAssertEqual(mode.qualityLayers, 8)
    }

    func testConfigurationProgressiveModeSpatialOnly() throws {
        var config = J2KEncodingConfiguration()
        config.qualityLayers = 1
        config.decompositionLevels = 5

        let mode = config.progressiveMode
        XCTAssertEqual(mode.decompositionLevels, 5)
    }

    // MARK: - Description Tests

    func testProgressiveModeDescriptions() throws {
        let snr = J2KProgressiveMode.snr(layers: 8)
        XCTAssertTrue(snr.description.contains("SNR"))
        XCTAssertTrue(snr.description.contains("8"))

        let spatial = J2KProgressiveMode.spatial(maxLevel: 5)
        XCTAssertTrue(spatial.description.contains("Spatial"))
        XCTAssertTrue(spatial.description.contains("5"))

        let layer = J2KProgressiveMode.layerProgressive(layers: 6, resolutionFirst: true)
        XCTAssertTrue(layer.description.contains("Layer"))
        XCTAssertTrue(layer.description.contains("resolution-first"))

        let combined = J2KProgressiveMode.combined(qualityLayers: 8, decompositionLevels: 5)
        XCTAssertTrue(combined.description.contains("Combined"))
        XCTAssertTrue(combined.description.contains("8"))
        XCTAssertTrue(combined.description.contains("5"))

        let none = J2KProgressiveMode.none
        XCTAssertTrue(none.description.contains("Non-progressive"))
    }

    func testRegionDescription() throws {
        let region = J2KRegion(x: 100, y: 200, width: 512, height: 768)
        XCTAssertEqual(region.description, "(100, 200, 512×768)")
    }

    // MARK: - Equality Tests

    func testProgressiveModeEquality() throws {
        let mode1 = J2KProgressiveMode.snr(layers: 8)
        let mode2 = J2KProgressiveMode.snr(layers: 8)
        let mode3 = J2KProgressiveMode.snr(layers: 7)

        XCTAssertEqual(mode1, mode2)
        XCTAssertNotEqual(mode1, mode3)
    }

    func testRegionEquality() throws {
        let region1 = J2KRegion(x: 10, y: 20, width: 100, height: 200)
        let region2 = J2KRegion(x: 10, y: 20, width: 100, height: 200)
        let region3 = J2KRegion(x: 10, y: 20, width: 101, height: 200)

        XCTAssertEqual(region1, region2)
        XCTAssertNotEqual(region1, region3)
    }

    func testDecodingOptionsEquality() throws {
        let options1 = J2KProgressiveDecodingOptions(maxLayer: 3)
        let options2 = J2KProgressiveDecodingOptions(maxLayer: 3)
        let options3 = J2KProgressiveDecodingOptions(maxLayer: 4)

        XCTAssertEqual(options1, options2)
        XCTAssertNotEqual(options1, options3)
    }

    // MARK: - Edge Cases Tests

    func testMinimumQualityLayers() throws {
        let mode = J2KProgressiveMode.snr(layers: 1)
        XCTAssertNoThrow(try mode.validate())
        XCTAssertEqual(mode.qualityLayers, 1)
    }

    func testMaximumQualityLayers() throws {
        let mode = J2KProgressiveMode.snr(layers: 20)
        XCTAssertNoThrow(try mode.validate())
        XCTAssertEqual(mode.qualityLayers, 20)
    }

    func testMinimumDecompositionLevel() throws {
        let mode = J2KProgressiveMode.spatial(maxLevel: 0)
        XCTAssertNoThrow(try mode.validate())
        XCTAssertEqual(mode.decompositionLevels, 0)
    }

    func testMaximumDecompositionLevel() throws {
        let mode = J2KProgressiveMode.spatial(maxLevel: 10)
        XCTAssertNoThrow(try mode.validate())
        XCTAssertEqual(mode.decompositionLevels, 10)
    }
}
