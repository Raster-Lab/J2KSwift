// J2KEncodingPresetsTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-07.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KEncodingPresetsTests: XCTestCase {
    
    // MARK: - Preset Configuration Tests
    
    func testFastPresetConfiguration() throws {
        let config = J2KEncodingPreset.fast.configuration()
        
        XCTAssertEqual(config.quality, 0.9)
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.decompositionLevels, 3)
        XCTAssertEqual(config.codeBlockSize.width, 64)
        XCTAssertEqual(config.codeBlockSize.height, 64)
        XCTAssertEqual(config.qualityLayers, 3)
        XCTAssertEqual(config.progressionOrder, .lrcp)
        XCTAssertFalse(config.enableVisualWeighting)
        XCTAssertEqual(config.tileSize.width, 512)
        XCTAssertEqual(config.tileSize.height, 512)
        XCTAssertEqual(config.maxThreads, 1)
    }
    
    func testBalancedPresetConfiguration() throws {
        let config = J2KEncodingPreset.balanced.configuration()
        
        XCTAssertEqual(config.quality, 0.9)
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.decompositionLevels, 5)
        XCTAssertEqual(config.codeBlockSize.width, 32)
        XCTAssertEqual(config.codeBlockSize.height, 32)
        XCTAssertEqual(config.qualityLayers, 5)
        XCTAssertEqual(config.progressionOrder, .rpcl)
        XCTAssertTrue(config.enableVisualWeighting)
        XCTAssertEqual(config.tileSize.width, 1024)
        XCTAssertEqual(config.tileSize.height, 1024)
        XCTAssertEqual(config.maxThreads, 0)
    }
    
    func testQualityPresetConfiguration() throws {
        let config = J2KEncodingPreset.quality.configuration()
        
        XCTAssertEqual(config.quality, 0.9)
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.decompositionLevels, 6)
        XCTAssertEqual(config.codeBlockSize.width, 32)
        XCTAssertEqual(config.codeBlockSize.height, 32)
        XCTAssertEqual(config.qualityLayers, 10)
        XCTAssertEqual(config.progressionOrder, .rpcl)
        XCTAssertTrue(config.enableVisualWeighting)
        XCTAssertEqual(config.tileSize.width, 2048)
        XCTAssertEqual(config.tileSize.height, 2048)
        XCTAssertEqual(config.maxThreads, 0)
    }
    
    func testPresetWithCustomQuality() throws {
        let config = J2KEncodingPreset.balanced.configuration(quality: 0.7)
        
        XCTAssertEqual(config.quality, 0.7)
        XCTAssertTrue(config.enableVisualWeighting)
    }
    
    func testPresetWithLossless() throws {
        let config = J2KEncodingPreset.quality.configuration(lossless: true)
        
        XCTAssertTrue(config.lossless)
        XCTAssertEqual(config.quality, 0.9)
    }
    
    func testBalancedPresetDisablesWeightingForLossless() throws {
        let config = J2KEncodingPreset.balanced.configuration(quality: 1.0)
        
        XCTAssertEqual(config.quality, 1.0)
        XCTAssertFalse(config.enableVisualWeighting)
    }
    
    // MARK: - Configuration Validation Tests
    
    func testConfigurationValidationSuccess() throws {
        let config = J2KEncodingConfiguration()
        XCTAssertNoThrow(try config.validate())
    }
    
    func testConfigurationValidationInvalidQuality() throws {
        var config = J2KEncodingConfiguration()
        config.quality = 1.5
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Quality"))
        }
    }
    
    func testConfigurationValidationInvalidDecompositionLevels() throws {
        var config = J2KEncodingConfiguration()
        config.decompositionLevels = 15
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Decomposition levels"))
        }
    }
    
    func testConfigurationValidationInvalidCodeBlockSize() throws {
        var config = J2KEncodingConfiguration()
        config.codeBlockSize = (width: 2, height: 32)
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Code block width"))
        }
    }
    
    func testConfigurationValidationInvalidQualityLayers() throws {
        var config = J2KEncodingConfiguration()
        config.qualityLayers = 25
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Quality layers"))
        }
    }
    
    func testConfigurationValidationNegativeTileSize() throws {
        var config = J2KEncodingConfiguration()
        config.tileSize = (width: -10, height: 512)
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("Tile size"))
        }
    }
    
    // MARK: - Progression Order Tests
    
    func testAllProgressionOrders() throws {
        XCTAssertEqual(J2KProgressionOrder.allCases.count, 5)
        
        let orders: [J2KProgressionOrder] = [.lrcp, .rlcp, .rpcl, .pcrl, .cprl]
        XCTAssertEqual(Set(orders).count, 5)
    }
    
    func testProgressionOrderRawValues() throws {
        XCTAssertEqual(J2KProgressionOrder.lrcp.rawValue, "LRCP")
        XCTAssertEqual(J2KProgressionOrder.rlcp.rawValue, "RLCP")
        XCTAssertEqual(J2KProgressionOrder.rpcl.rawValue, "RPCL")
        XCTAssertEqual(J2KProgressionOrder.pcrl.rawValue, "PCRL")
        XCTAssertEqual(J2KProgressionOrder.cprl.rawValue, "CPRL")
    }
    
    // MARK: - Bitrate Mode Tests
    
    func testConstantQualityMode() throws {
        let mode = J2KBitrateMode.constantQuality
        
        switch mode {
        case .constantQuality:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected constantQuality mode")
        }
    }
    
    func testConstantBitrateMode() throws {
        let mode = J2KBitrateMode.constantBitrate(bitsPerPixel: 0.5)
        
        switch mode {
        case .constantBitrate(let bpp):
            XCTAssertEqual(bpp, 0.5)
        default:
            XCTFail("Expected constantBitrate mode")
        }
    }
    
    func testVariableBitrateMode() throws {
        let mode = J2KBitrateMode.variableBitrate(minQuality: 0.7, maxBitsPerPixel: 1.0)
        
        switch mode {
        case .variableBitrate(let minQuality, let maxBpp):
            XCTAssertEqual(minQuality, 0.7)
            XCTAssertEqual(maxBpp, 1.0)
        default:
            XCTFail("Expected variableBitrate mode")
        }
    }
    
    func testLosslessMode() throws {
        let mode = J2KBitrateMode.lossless
        
        switch mode {
        case .lossless:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected lossless mode")
        }
    }
    
    func testBitrateModeEquality() throws {
        XCTAssertEqual(J2KBitrateMode.constantQuality, J2KBitrateMode.constantQuality)
        XCTAssertEqual(J2KBitrateMode.lossless, J2KBitrateMode.lossless)
        XCTAssertEqual(
            J2KBitrateMode.constantBitrate(bitsPerPixel: 0.5),
            J2KBitrateMode.constantBitrate(bitsPerPixel: 0.5)
        )
        XCTAssertNotEqual(
            J2KBitrateMode.constantBitrate(bitsPerPixel: 0.5),
            J2KBitrateMode.constantBitrate(bitsPerPixel: 0.6)
        )
    }
    
    // MARK: - Configuration Bounds Tests
    
    func testConfigurationClampsBounds() throws {
        // Quality clamped to [0, 1]
        let config1 = J2KEncodingConfiguration(quality: -0.5)
        XCTAssertEqual(config1.quality, 0.0)
        
        let config2 = J2KEncodingConfiguration(quality: 1.5)
        XCTAssertEqual(config2.quality, 1.0)
        
        // Decomposition levels clamped to [0, 10]
        let config3 = J2KEncodingConfiguration(decompositionLevels: -1)
        XCTAssertEqual(config3.decompositionLevels, 0)
        
        let config4 = J2KEncodingConfiguration(decompositionLevels: 15)
        XCTAssertEqual(config4.decompositionLevels, 10)
        
        // Code block size clamped to [4, 1024]
        let config5 = J2KEncodingConfiguration(codeBlockSize: (2, 2))
        XCTAssertEqual(config5.codeBlockSize.width, 4)
        XCTAssertEqual(config5.codeBlockSize.height, 4)
        
        let config6 = J2KEncodingConfiguration(codeBlockSize: (2048, 2048))
        XCTAssertEqual(config6.codeBlockSize.width, 1024)
        XCTAssertEqual(config6.codeBlockSize.height, 1024)
        
        // Quality layers clamped to [1, 20]
        let config7 = J2KEncodingConfiguration(qualityLayers: 0)
        XCTAssertEqual(config7.qualityLayers, 1)
        
        let config8 = J2KEncodingConfiguration(qualityLayers: 30)
        XCTAssertEqual(config8.qualityLayers, 20)
    }
    
    // MARK: - Preset Description Tests
    
    func testPresetDescriptions() throws {
        XCTAssertEqual(J2KEncodingPreset.fast.description, "Fast (2-3× faster, good quality)")
        XCTAssertEqual(J2KEncodingPreset.balanced.description, "Balanced (optimal quality/speed)")
        XCTAssertEqual(J2KEncodingPreset.quality.description, "Quality (best quality, slower)")
    }
    
    func testBitrateModeDescriptions() throws {
        XCTAssertEqual(J2KBitrateMode.constantQuality.description, "Constant Quality")
        XCTAssertEqual(J2KBitrateMode.lossless.description, "Lossless")
        
        let cbr = J2KBitrateMode.constantBitrate(bitsPerPixel: 0.5)
        XCTAssertTrue(cbr.description.contains("0.50"))
        
        let vbr = J2KBitrateMode.variableBitrate(minQuality: 0.7, maxBitsPerPixel: 1.0)
        XCTAssertTrue(vbr.description.contains("0.70"))
        XCTAssertTrue(vbr.description.contains("1.00"))
    }
    
    // MARK: - All Presets Test
    
    func testAllPresets() throws {
        for preset in J2KEncodingPreset.allCases {
            let config = preset.configuration()
            XCTAssertNoThrow(try config.validate())
            
            // Verify preset characteristics
            switch preset {
            case .fast:
                XCTAssertEqual(config.decompositionLevels, 3)
                XCTAssertEqual(config.maxThreads, 1)
            case .balanced:
                XCTAssertEqual(config.decompositionLevels, 5)
                XCTAssertEqual(config.maxThreads, 0)
            case .quality:
                XCTAssertEqual(config.decompositionLevels, 6)
                XCTAssertEqual(config.qualityLayers, 10)
            }
        }
    }
    
    // MARK: - Custom Configuration Tests
    
    func testCustomConfiguration() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.85,
            lossless: false,
            decompositionLevels: 4,
            codeBlockSize: (48, 48),
            qualityLayers: 7,
            progressionOrder: .pcrl,
            enableVisualWeighting: true,
            tileSize: (768, 768),
            bitrateMode: .constantBitrate(bitsPerPixel: 0.75),
            maxThreads: 4
        )
        
        XCTAssertEqual(config.quality, 0.85)
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.decompositionLevels, 4)
        XCTAssertEqual(config.codeBlockSize.width, 48)
        XCTAssertEqual(config.codeBlockSize.height, 48)
        XCTAssertEqual(config.qualityLayers, 7)
        XCTAssertEqual(config.progressionOrder, .pcrl)
        XCTAssertTrue(config.enableVisualWeighting)
        XCTAssertEqual(config.tileSize.width, 768)
        XCTAssertEqual(config.tileSize.height, 768)
        XCTAssertEqual(config.maxThreads, 4)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    // MARK: - Configuration Equality Tests
    
    func testConfigurationEquality() throws {
        let config1 = J2KEncodingConfiguration()
        let config2 = J2KEncodingConfiguration()
        
        XCTAssertEqual(config1, config2)
        
        var config3 = J2KEncodingConfiguration()
        config3.quality = 0.8
        
        XCTAssertNotEqual(config1, config3)
    }
}
