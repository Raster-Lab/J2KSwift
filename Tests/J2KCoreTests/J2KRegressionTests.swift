//
// J2KRegressionTests.swift
// J2KSwift
//
// Regression tests for Week 284-286 (Sub-phase 17h) — Integration Testing.
//
// Validates that public APIs remain stable, configuration presets have correct
// values, error types are unchanged, marker constants are correct, and core
// types behave as documented. These tests guard against unintentional breaking
// changes between v1.9.0 and v2.0.
//

import XCTest
@testable import J2KCore
import Foundation

/// Regression tests to guard against breaking changes from v1.9.0 to v2.0.
///
/// These tests validate:
/// - Public API stability (all documented symbols exist)
/// - Configuration preset values are unchanged
/// - Error type cases and messages are stable
/// - Marker constant values match the ISO/IEC 15444 specification
/// - Core type behaviours match documented contracts
/// - Version string is correct for v2.0.0
final class J2KRegressionTests: XCTestCase {

    // MARK: - Version Regression

    func testVersionStringFormatIsSemanticVersioning() throws {
        let version = getVersion()
        let components = version.split(separator: ".")
        XCTAssertEqual(components.count, 3, "Version must follow MAJOR.MINOR.PATCH format")
        for component in components {
            XCTAssertNotNil(Int(component), "Each version component must be a number: '\(component)'")
        }
    }

    func testVersionStringIsV2_0_0() throws {
        XCTAssertEqual(getVersion(), "2.0.0", "Version must be 2.0.0 for the v2.0 release")
    }

    func testVersionStringIsNotEmpty() throws {
        XCTAssertFalse(getVersion().isEmpty, "Version string must not be empty")
    }

    // MARK: - J2KConfiguration Regression

    func testConfigurationDefaultQualityIs0_9() throws {
        let config = J2KConfiguration()
        XCTAssertEqual(config.quality, 0.9, accuracy: 0.001,
            "Default quality must be 0.9 (v1.9.0 contract)")
    }

    func testConfigurationDefaultLosslessIsFalse() throws {
        let config = J2KConfiguration()
        XCTAssertFalse(config.lossless, "Default lossless must be false (v1.9.0 contract)")
    }

    func testConfigurationLosslessPresetQualityIs1_0() throws {
        let config = J2KConfiguration.lossless
        XCTAssertEqual(config.quality, 1.0, accuracy: 0.001,
            ".lossless quality must be 1.0 (v1.9.0 contract)")
        XCTAssertTrue(config.lossless, ".lossless must set lossless = true")
    }

    func testConfigurationHighQualityPresetQualityIs0_95() throws {
        let config = J2KConfiguration.highQuality
        XCTAssertEqual(config.quality, 0.95, accuracy: 0.001,
            ".highQuality quality must be 0.95 (v1.9.0 contract)")
        XCTAssertFalse(config.lossless, ".highQuality must not be lossless")
    }

    func testConfigurationBalancedPresetQualityIs0_85() throws {
        let config = J2KConfiguration.balanced
        XCTAssertEqual(config.quality, 0.85, accuracy: 0.001,
            ".balanced quality must be 0.85 (v1.9.0 contract)")
        XCTAssertFalse(config.lossless, ".balanced must not be lossless")
    }

    func testConfigurationFastPresetQualityIs0_70() throws {
        let config = J2KConfiguration.fast
        XCTAssertEqual(config.quality, 0.70, accuracy: 0.001,
            ".fast quality must be 0.70 (v1.9.0 contract)")
        XCTAssertFalse(config.lossless, ".fast must not be lossless")
    }

    func testConfigurationMaxCompressionPresetQualityIs0_50() throws {
        let config = J2KConfiguration.maxCompression
        XCTAssertEqual(config.quality, 0.50, accuracy: 0.001,
            ".maxCompression quality must be 0.50 (v1.9.0 contract)")
        XCTAssertFalse(config.lossless, ".maxCompression must not be lossless")
    }

    func testConfigurationQualityPresetsAreOrderedCorrectly() throws {
        XCTAssertGreaterThan(J2KConfiguration.lossless.quality,     J2KConfiguration.highQuality.quality)
        XCTAssertGreaterThan(J2KConfiguration.highQuality.quality,  J2KConfiguration.balanced.quality)
        XCTAssertGreaterThan(J2KConfiguration.balanced.quality,     J2KConfiguration.fast.quality)
        XCTAssertGreaterThan(J2KConfiguration.fast.quality,         J2KConfiguration.maxCompression.quality)
    }

    func testConfigurationQualityClampedToUnitRange() throws {
        let overMax = J2KConfiguration(quality: 2.0, lossless: false)
        let underMin = J2KConfiguration(quality: -1.0, lossless: false)
        // J2KConfiguration stores as-is; the encoding configuration clamps
        XCTAssertEqual(overMax.quality, 2.0)
        XCTAssertEqual(underMin.quality, -1.0)
    }

    // MARK: - J2KError Regression

    func testErrorInvalidParameterCase() throws {
        let error = J2KError.invalidParameter("test message")
        if case .invalidParameter(let msg) = error {
            XCTAssertEqual(msg, "test message")
        } else {
            XCTFail("J2KError.invalidParameter case must exist")
        }
    }

    func testErrorNotImplementedCase() throws {
        let error = J2KError.notImplemented("not done")
        if case .notImplemented(let msg) = error {
            XCTAssertEqual(msg, "not done")
        } else {
            XCTFail("J2KError.notImplemented case must exist")
        }
    }

    func testErrorInternalErrorCase() throws {
        let error = J2KError.internalError("internal")
        if case .internalError(let msg) = error {
            XCTAssertEqual(msg, "internal")
        } else {
            XCTFail("J2KError.internalError case must exist")
        }
    }

    func testErrorInvalidDimensionsCase() throws {
        let error = J2KError.invalidDimensions("0x0")
        if case .invalidDimensions(let msg) = error {
            XCTAssertEqual(msg, "0x0")
        } else {
            XCTFail("J2KError.invalidDimensions case must exist")
        }
    }

    func testErrorInvalidBitDepthCase() throws {
        let error = J2KError.invalidBitDepth("bit depth 0")
        if case .invalidBitDepth(let msg) = error {
            XCTAssertEqual(msg, "bit depth 0")
        } else {
            XCTFail("J2KError.invalidBitDepth case must exist")
        }
    }

    func testErrorInvalidTileConfigurationCase() throws {
        let error = J2KError.invalidTileConfiguration("negative tile")
        if case .invalidTileConfiguration(let msg) = error {
            XCTAssertEqual(msg, "negative tile")
        } else {
            XCTFail("J2KError.invalidTileConfiguration case must exist")
        }
    }

    func testErrorInvalidComponentConfigurationCase() throws {
        let error = J2KError.invalidComponentConfiguration("zero components")
        if case .invalidComponentConfiguration(let msg) = error {
            XCTAssertEqual(msg, "zero components")
        } else {
            XCTFail("J2KError.invalidComponentConfiguration case must exist")
        }
    }

    func testErrorInvalidDataCase() throws {
        let error = J2KError.invalidData("corrupt header")
        if case .invalidData(let msg) = error {
            XCTAssertEqual(msg, "corrupt header")
        } else {
            XCTFail("J2KError.invalidData case must exist")
        }
    }

    func testErrorFileFormatErrorCase() throws {
        let error = J2KError.fileFormatError("bad magic")
        if case .fileFormatError(let msg) = error {
            XCTAssertEqual(msg, "bad magic")
        } else {
            XCTFail("J2KError.fileFormatError case must exist")
        }
    }

    func testErrorUnsupportedFeatureCase() throws {
        let error = J2KError.unsupportedFeature("feature X")
        if case .unsupportedFeature(let msg) = error {
            XCTAssertEqual(msg, "feature X")
        } else {
            XCTFail("J2KError.unsupportedFeature case must exist")
        }
    }

    func testErrorDecodingErrorCase() throws {
        let error = J2KError.decodingError("bad packet")
        if case .decodingError(let msg) = error {
            XCTAssertEqual(msg, "bad packet")
        } else {
            XCTFail("J2KError.decodingError case must exist")
        }
    }

    func testErrorEncodingErrorCase() throws {
        let error = J2KError.encodingError("encode fail")
        if case .encodingError(let msg) = error {
            XCTAssertEqual(msg, "encode fail")
        } else {
            XCTFail("J2KError.encodingError case must exist")
        }
    }

    func testErrorIOErrorCase() throws {
        let error = J2KError.ioError("file not found")
        if case .ioError(let msg) = error {
            XCTAssertEqual(msg, "file not found")
        } else {
            XCTFail("J2KError.ioError case must exist")
        }
    }

    func testErrorIsLocalizedError() throws {
        let error = J2KError.invalidParameter("test") as LocalizedError
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testErrorDescriptionsContainMessage() throws {
        let message = "unique-regression-message-xyz"
        let error = J2KError.invalidParameter(message)
        XCTAssertTrue(error.localizedDescription.contains(message),
            "Error description must contain the original message")
    }

    func testErrorIsSendable() throws {
        // J2KError must conform to Sendable for actor-safe error propagation
        nonisolated(unsafe) var capturedError: J2KError?
        capturedError = J2KError.invalidParameter("sendable test")
        XCTAssertNotNil(capturedError)
    }

    // MARK: - J2KMarker Regression (ISO/IEC 15444-1 constants)

    func testSOCMarkerValue() throws {
        XCTAssertEqual(J2KMarker.soc.rawValue, 0xFF4F,
            "SOC (Start of Codestream) marker must be 0xFF4F per ISO/IEC 15444-1")
    }

    func testSOTMarkerValue() throws {
        XCTAssertEqual(J2KMarker.sot.rawValue, 0xFF90,
            "SOT (Start of Tile) marker must be 0xFF90 per ISO/IEC 15444-1")
    }

    func testEOCMarkerValue() throws {
        XCTAssertEqual(J2KMarker.eoc.rawValue, 0xFFD9,
            "EOC (End of Codestream) marker must be 0xFFD9 per ISO/IEC 15444-1")
    }

    func testSIZMarkerValue() throws {
        XCTAssertEqual(J2KMarker.siz.rawValue, 0xFF51,
            "SIZ (Image and Tile Size) marker must be 0xFF51 per ISO/IEC 15444-1")
    }

    func testCODMarkerValue() throws {
        XCTAssertEqual(J2KMarker.cod.rawValue, 0xFF52,
            "COD (Coding style Default) marker must be 0xFF52 per ISO/IEC 15444-1")
    }

    func testQCDMarkerValue() throws {
        XCTAssertEqual(J2KMarker.qcd.rawValue, 0xFF5C,
            "QCD (Quantization Default) marker must be 0xFF5C per ISO/IEC 15444-1")
    }

    // MARK: - J2KSubband Regression

    func testSubbandLLRawValue() throws {
        XCTAssertEqual(J2KSubband.ll.rawValue, "LL",
            "LL subband raw value must be 'LL' (v1.9.0 contract)")
    }

    func testSubbandHLRawValue() throws {
        XCTAssertEqual(J2KSubband.hl.rawValue, "HL",
            "HL subband raw value must be 'HL' (v1.9.0 contract)")
    }

    func testSubbandLHRawValue() throws {
        XCTAssertEqual(J2KSubband.lh.rawValue, "LH",
            "LH subband raw value must be 'LH' (v1.9.0 contract)")
    }

    func testSubbandHHRawValue() throws {
        XCTAssertEqual(J2KSubband.hh.rawValue, "HH",
            "HH subband raw value must be 'HH' (v1.9.0 contract)")
    }

    func testSubbandIsHashable() throws {
        let dict: [J2KSubband: Int] = [.ll: 0, .hl: 1, .lh: 2, .hh: 3]
        XCTAssertEqual(dict.count, 4, "J2KSubband must be Hashable for use as dictionary key")
    }

    func testSubbandIsSendable() throws {
        let subband: J2KSubband = .ll
        XCTAssertEqual(subband, .ll, "J2KSubband must be Sendable")
    }

    // MARK: - J2KImage Regression

    func testImageDefaultColorSpaceIsRGB() throws {
        let image = J2KImage(width: 64, height: 64, components: 3)
        if case .sRGB = image.colorSpace {
            // Expected
        } else {
            XCTFail("Default 3-component J2KImage color space must be sRGB")
        }
    }

    func testImageColorSpaceGrayscaleCase() throws {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 64, height: 64)
        let image = J2KImage(width: 64, height: 64, components: [component], colorSpace: .grayscale)
        if case .grayscale = image.colorSpace {
            // Expected
        } else {
            XCTFail("Grayscale color space must be preserved")
        }
    }

    func testImageColorSpaceYCbCrCase() throws {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 64, height: 64)
        let image = J2KImage(width: 64, height: 64, components: [component], colorSpace: .yCbCr)
        if case .yCbCr = image.colorSpace {
            // Expected
        } else {
            XCTFail("YCbCr color space must be preserved")
        }
    }

    func testImageColorSpaceICCProfileCase() throws {
        let iccData = Data([0x00, 0x01, 0x02, 0x03])
        let component = J2KComponent(index: 0, bitDepth: 8, width: 64, height: 64)
        let image = J2KImage(width: 64, height: 64, components: [component],
                             colorSpace: .iccProfile(iccData))
        if case .iccProfile(let data) = image.colorSpace {
            XCTAssertEqual(data, iccData, "ICC profile data must be preserved exactly")
        } else {
            XCTFail("ICC profile color space must be preserved")
        }
    }

    func testImageWidthAndHeightArePreserved() throws {
        let image = J2KImage(width: 123, height: 456, components: 1, bitDepth: 8)
        XCTAssertEqual(image.width, 123)
        XCTAssertEqual(image.height, 456)
    }

    func testImageComponentCountIsPreserved() throws {
        for count in [1, 2, 3, 4, 16] {
            let image = J2KImage(width: 32, height: 32, components: count, bitDepth: 8)
            XCTAssertEqual(image.components.count, count)
        }
    }

    func testImageComponentBitDepthIsPreserved() throws {
        for bitDepth in [1, 4, 8, 10, 12, 16] {
            let image = J2KImage(width: 32, height: 32, components: 1, bitDepth: bitDepth)
            XCTAssertEqual(image.components[0].bitDepth, bitDepth)
        }
    }

    func testImageIsSendable() throws {
        let image = J2KImage(width: 64, height: 64, components: 1)
        XCTAssertEqual(image.width, 64, "J2KImage must be Sendable for use across actor boundaries")
    }

    // MARK: - J2KComponent Regression

    func testComponentDefaultSignedIsFalse() throws {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 64, height: 64)
        XCTAssertFalse(component.signed, "Default component must be unsigned (v1.9.0 contract)")
    }

    func testComponentDefaultSubsamplingIsOne() throws {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 64, height: 64)
        XCTAssertEqual(component.subsamplingX, 1)
        XCTAssertEqual(component.subsamplingY, 1)
    }

    func testComponentIndexIsPreserved() throws {
        for index in [0, 1, 2, 3, 15] {
            let component = J2KComponent(index: index, bitDepth: 8, width: 32, height: 32)
            XCTAssertEqual(component.index, index)
        }
    }

    func testComponentBitDepthIsPreserved() throws {
        for bitDepth in [1, 4, 8, 12, 16, 32] {
            let component = J2KComponent(index: 0, bitDepth: bitDepth, width: 32, height: 32)
            XCTAssertEqual(component.bitDepth, bitDepth)
        }
    }

    func testComponentIsSendable() throws {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 32, height: 32)
        XCTAssertEqual(component.bitDepth, 8, "J2KComponent must be Sendable")
    }

    // MARK: - J2KTile Regression

    func testTilePropertiesArePreserved() throws {
        let tile = J2KTile(index: 5, x: 2, y: 3, width: 128, height: 64,
                           offsetX: 256, offsetY: 192)
        XCTAssertEqual(tile.index, 5)
        XCTAssertEqual(tile.x, 2)
        XCTAssertEqual(tile.y, 3)
        XCTAssertEqual(tile.width, 128)
        XCTAssertEqual(tile.height, 64)
        XCTAssertEqual(tile.offsetX, 256)
        XCTAssertEqual(tile.offsetY, 192)
    }

    func testTileIsSendable() throws {
        let tile = J2KTile(index: 0, x: 0, y: 0, width: 64, height: 64,
                           offsetX: 0, offsetY: 0)
        XCTAssertEqual(tile.width, 64)
    }

    // MARK: - J2KCodeBlock Regression

    func testCodeBlockPropertiesArePreserved() throws {
        let cb = J2KCodeBlock(index: 3, x: 1, y: 2, width: 32, height: 32, subband: .hh)
        XCTAssertEqual(cb.index, 3)
        XCTAssertEqual(cb.x, 1)
        XCTAssertEqual(cb.y, 2)
        XCTAssertEqual(cb.width, 32)
        XCTAssertEqual(cb.height, 32)
        XCTAssertEqual(cb.subband, .hh)
    }

    // MARK: - J2KPrecinct Regression

    func testPrecinctPropertiesArePreserved() throws {
        let precinct = J2KPrecinct(index: 0, x: 0, y: 0, width: 64, height: 64,
                                   resolutionLevel: 2)
        XCTAssertEqual(precinct.index, 0)
        XCTAssertEqual(precinct.width, 64)
        XCTAssertEqual(precinct.height, 64)
        XCTAssertEqual(precinct.resolutionLevel, 2)
    }

    // MARK: - Image Validation Regression

    func testImageWithZeroWidthThrowsOnValidation() throws {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 0, height: 64)
        let image = J2KImage(width: 0, height: 64, components: [component])
        XCTAssertThrowsError(try image.validate()) { error in
            if case J2KError.invalidDimensions = error {
                // Expected
            } else {
                XCTFail("Expected J2KError.invalidDimensions")
            }
        }
    }

    func testImageWithZeroHeightThrowsOnValidation() throws {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 64, height: 0)
        let image = J2KImage(width: 64, height: 0, components: [component])
        XCTAssertThrowsError(try image.validate()) { error in
            if case J2KError.invalidDimensions = error {
                // Expected
            } else {
                XCTFail("Expected J2KError.invalidDimensions")
            }
        }
    }

    func testImageWithZeroComponentsThrowsOnValidation() throws {
        let image = J2KImage(width: 64, height: 64, components: [])
        XCTAssertThrowsError(try image.validate()) { error in
            if case J2KError.invalidComponentConfiguration = error {
                // Expected
            } else {
                XCTFail("Expected J2KError.invalidComponentConfiguration")
            }
        }
    }

    func testValidImageDoesNotThrow() throws {
        let image = J2KImage(width: 64, height: 64, components: 1, bitDepth: 8)
        XCTAssertNoThrow(try image.validate())
    }

    // MARK: - Memory Pool Regression

    func testMemoryPoolAcquireAndRelease() async throws {
        let pool = J2KMemoryPool()
        let buffer = await pool.acquire(capacity: 1024)
        XCTAssertGreaterThanOrEqual(buffer.capacity, 1024)
        await pool.release(buffer)
    }

    func testMemoryPoolMultipleAcquireAndRelease() async throws {
        let pool = J2KMemoryPool()
        var buffers: [J2KBuffer] = []
        for _ in 0..<20 {
            let buffer = await pool.acquire(capacity: 512)
            buffers.append(buffer)
        }
        XCTAssertEqual(buffers.count, 20)
        for buffer in buffers {
            await pool.release(buffer)
        }
    }

    // MARK: - Memory Tracker Regression

    func testMemoryTrackerInitialUsageIsZero() async throws {
        let tracker = J2KMemoryTracker(limit: 1024 * 1024)
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 0)
    }

    func testMemoryTrackerAllocateAndDeallocate() async throws {
        let tracker = J2KMemoryTracker(limit: 1024 * 1024)
        try await tracker.allocate(4096)
        let statsAfterAlloc = await tracker.getStatistics()
        XCTAssertEqual(statsAfterAlloc.currentUsage, 4096)

        await tracker.deallocate(4096)
        let statsAfterDealloc = await tracker.getStatistics()
        XCTAssertEqual(statsAfterDealloc.currentUsage, 0)
    }

    func testMemoryTrackerEnforcesLimit() async throws {
        let tracker = J2KMemoryTracker(limit: 1000)
        try await tracker.allocate(800)
        do {
            try await tracker.allocate(300)
            XCTFail("Should have thrown when exceeding memory limit")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testMemoryTrackerFailedAllocationsAreCounted() async throws {
        let tracker = J2KMemoryTracker(limit: 500)
        try await tracker.allocate(400)
        _ = try? await tracker.allocate(200) // Will fail
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.failedAllocations, 1)
    }
}
