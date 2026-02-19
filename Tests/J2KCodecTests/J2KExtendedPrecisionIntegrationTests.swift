// J2KExtendedPrecisionIntegrationTests.swift
// J2KSwift
//
// Integration and validation tests for Week 157-158:
// Extended Precision Integration and Validation (ISO/IEC 15444-2).
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Comprehensive integration and validation tests for extended precision
/// and DC offset integration with the encoding/decoding pipeline.
final class J2KExtendedPrecisionIntegrationTests: XCTestCase {

    // MARK: - Encoder Configuration Integration

    func testEncoderConfigDefaultDCOffsetDisabled() {
        let config = J2KEncodingConfiguration()
        XCTAssertFalse(config.dcOffsetConfiguration.enabled)
        XCTAssertEqual(config.extendedPrecisionConfiguration.internalBitDepth, 32)
        XCTAssertEqual(config.extendedPrecisionConfiguration.guardBits.count, 2)
    }

    func testEncoderConfigWithDCOffsetEnabled() {
        let config = J2KEncodingConfiguration(
            dcOffsetConfiguration: .default,
            extendedPrecisionConfiguration: .highPrecision
        )
        XCTAssertTrue(config.dcOffsetConfiguration.enabled)
        XCTAssertEqual(config.dcOffsetConfiguration.method, .mean)
        XCTAssertEqual(config.extendedPrecisionConfiguration.internalBitDepth, 64)
        XCTAssertEqual(config.extendedPrecisionConfiguration.guardBits.count, 4)
        XCTAssertTrue(config.extendedPrecisionConfiguration.extendedDynamicRange)
    }

    func testEncoderConfigWithCustomDCOffset() {
        let dcConfig = J2KDCOffsetConfiguration(
            enabled: true,
            method: .midrange,
            optimizeForNaturalImages: true
        )
        let precConfig = J2KExtendedPrecisionConfiguration(
            internalBitDepth: 48,
            guardBits: try! J2KExtendedGuardBits(count: 6),
            roundingMode: .roundToEven,
            extendedDynamicRange: true
        )
        let config = J2KEncodingConfiguration(
            dcOffsetConfiguration: dcConfig,
            extendedPrecisionConfiguration: precConfig
        )
        XCTAssertTrue(config.dcOffsetConfiguration.enabled)
        XCTAssertEqual(config.dcOffsetConfiguration.method, .midrange)
        XCTAssertTrue(config.dcOffsetConfiguration.optimizeForNaturalImages)
        XCTAssertEqual(config.extendedPrecisionConfiguration.internalBitDepth, 48)
        XCTAssertEqual(config.extendedPrecisionConfiguration.guardBits.count, 6)
        XCTAssertEqual(config.extendedPrecisionConfiguration.roundingMode, .roundToEven)
    }

    func testEncoderConfigEquality() {
        let config1 = J2KEncodingConfiguration(
            dcOffsetConfiguration: .default,
            extendedPrecisionConfiguration: .standard
        )
        let config2 = J2KEncodingConfiguration(
            dcOffsetConfiguration: .default,
            extendedPrecisionConfiguration: .standard
        )
        let config3 = J2KEncodingConfiguration(
            dcOffsetConfiguration: .disabled,
            extendedPrecisionConfiguration: .standard
        )
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }

    func testEncoderConfigPresetCompatibility() {
        // Presets should still work (they use default DC offset = disabled)
        let fastConfig = J2KEncodingPreset.fast.configuration()
        XCTAssertFalse(fastConfig.dcOffsetConfiguration.enabled)

        let balancedConfig = J2KEncodingPreset.balanced.configuration()
        XCTAssertFalse(balancedConfig.dcOffsetConfiguration.enabled)

        let qualityConfig = J2KEncodingPreset.quality.configuration()
        XCTAssertFalse(qualityConfig.dcOffsetConfiguration.enabled)
    }

    func testEncoderWithDCOffsetConfig() {
        // The encoder should accept DC offset configuration via J2KEncodingConfiguration
        let config = J2KEncodingConfiguration(
            dcOffsetConfiguration: .default,
            extendedPrecisionConfiguration: .standard
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        XCTAssertTrue(encoder.encodingConfiguration.dcOffsetConfiguration.enabled)
    }

    // MARK: - Decoder Configuration Integration

    func testDecoderConfigDefaultNoDCOffsets() {
        let config = DecoderConfiguration()
        XCTAssertNil(config.dcOffsets)
        XCTAssertEqual(config.extendedPrecision.internalBitDepth, 32)
        XCTAssertEqual(config.extendedPrecision.guardBits.count, 2)
    }

    func testDecoderConfigWithDCOffsets() {
        var config = DecoderConfiguration()
        config.dcOffsets = [
            J2KDCOffsetValue(componentIndex: 0, value: 128.0),
            J2KDCOffsetValue(componentIndex: 1, value: 64.0),
            J2KDCOffsetValue(componentIndex: 2, value: 200.0),
        ]
        config.extendedPrecision = .highPrecision

        XCTAssertNotNil(config.dcOffsets)
        XCTAssertEqual(config.dcOffsets?.count, 3)
        XCTAssertEqual(config.extendedPrecision.guardBits.count, 4)
    }

    func testCodestreamMetadataWithDCOMarker() {
        var metadata = CodestreamMetadata(
            width: 256,
            height: 256,
            componentCount: 3,
            components: [
                .init(bitDepth: 8, signed: false, subsamplingX: 1, subsamplingY: 1),
                .init(bitDepth: 8, signed: false, subsamplingX: 1, subsamplingY: 1),
                .init(bitDepth: 8, signed: false, subsamplingX: 1, subsamplingY: 1),
            ],
            tileSize: (width: 256, height: 256),
            configuration: DecoderConfiguration(),
            quantizationSteps: [:]
        )

        XCTAssertNil(metadata.dcoMarkerSegment)

        let dcoMarker = J2KDCOMarkerSegment(
            offsetType: .integer,
            offsets: [
                J2KDCOffsetValue(componentIndex: 0, value: 128.0),
                J2KDCOffsetValue(componentIndex: 1, value: 64.0),
                J2KDCOffsetValue(componentIndex: 2, value: 200.0),
            ]
        )
        metadata.dcoMarkerSegment = dcoMarker

        XCTAssertNotNil(metadata.dcoMarkerSegment)
        XCTAssertEqual(metadata.dcoMarkerSegment?.offsets.count, 3)
        XCTAssertEqual(metadata.dcoMarkerSegment?.offsetType, .integer)
    }

    // MARK: - Rate-Distortion Integration

    func testDCOffsetDistortionAdjustmentNoOffset() {
        let adjustment = J2KDCOffsetDistortionAdjustment(
            offsets: [.zero(componentIndex: 0)],
            bitDepths: [8]
        )
        let gain = adjustment.compressionEfficiencyGain(forComponent: 0)
        XCTAssertEqual(gain, 1.0, accuracy: 1e-10)

        let distortion = adjustment.adjustDistortion(100.0, forComponent: 0)
        XCTAssertEqual(distortion, 100.0, accuracy: 1e-10)
    }

    func testDCOffsetDistortionAdjustmentWithOffset() {
        let adjustment = J2KDCOffsetDistortionAdjustment(
            offsets: [J2KDCOffsetValue(componentIndex: 0, value: 128.0)],
            bitDepths: [8]
        )
        let gain = adjustment.compressionEfficiencyGain(forComponent: 0)
        // 128 / 256 = 0.5, gain = 1.0 + 0.5 * 0.15 = 1.075
        XCTAssertEqual(gain, 1.075, accuracy: 1e-10)
        XCTAssertGreaterThan(gain, 1.0)

        let distortion = adjustment.adjustDistortion(100.0, forComponent: 0)
        XCTAssertLessThan(distortion, 100.0)
    }

    func testDCOffsetDistortionAdjustmentMultiComponent() {
        let adjustment = J2KDCOffsetDistortionAdjustment(
            offsets: [
                J2KDCOffsetValue(componentIndex: 0, value: 128.0),
                J2KDCOffsetValue(componentIndex: 1, value: 0.0),
                J2KDCOffsetValue(componentIndex: 2, value: 200.0),
            ],
            bitDepths: [8, 8, 8]
        )

        // Component 0: non-zero offset → gain > 1.0
        let gain0 = adjustment.compressionEfficiencyGain(forComponent: 0)
        XCTAssertGreaterThan(gain0, 1.0)

        // Component 1: zero offset → gain = 1.0
        let gain1 = adjustment.compressionEfficiencyGain(forComponent: 1)
        XCTAssertEqual(gain1, 1.0, accuracy: 1e-10)

        // Component 2: larger offset → larger gain
        let gain2 = adjustment.compressionEfficiencyGain(forComponent: 2)
        XCTAssertGreaterThan(gain2, gain0)
    }

    func testDCOffsetDistortionAdjustmentOutOfBounds() {
        let adjustment = J2KDCOffsetDistortionAdjustment(
            offsets: [J2KDCOffsetValue(componentIndex: 0, value: 128.0)],
            bitDepths: [8]
        )
        // Out-of-bounds component returns 1.0 (no gain)
        let gain = adjustment.compressionEfficiencyGain(forComponent: 5)
        XCTAssertEqual(gain, 1.0, accuracy: 1e-10)
    }

    func testDCOffsetDistortionAdjustmentHighBitDepth() {
        let adjustment = J2KDCOffsetDistortionAdjustment(
            offsets: [J2KDCOffsetValue(componentIndex: 0, value: 32768.0)],
            bitDepths: [16]
        )
        let gain = adjustment.compressionEfficiencyGain(forComponent: 0)
        // 32768 / 65536 = 0.5, gain = 1.0 + 0.5 * 0.15 = 1.075
        XCTAssertEqual(gain, 1.075, accuracy: 1e-10)
    }

    // MARK: - Part 2 Conformance Tests

    func testDCOMarkerSegmentConformanceIntegerType() throws {
        // Verify DCO marker segment conforms to ISO/IEC 15444-2 Annex A.3
        let offsets = [
            J2KDCOffsetValue(componentIndex: 0, value: 128.0),
            J2KDCOffsetValue(componentIndex: 1, value: -50.0),
            J2KDCOffsetValue(componentIndex: 2, value: 200.0),
        ]
        let marker = J2KDCOMarkerSegment(offsetType: .integer, offsets: offsets)
        let encoded = try marker.encode()

        // Verify marker code 0xFF5C
        XCTAssertEqual(encoded[0], 0xFF)
        XCTAssertEqual(encoded[1], 0x5C)

        // Verify segment length: 2 (Ldco) + 1 (Sdco) + 3*4 (offsets) = 15
        let segmentLength = Int(encoded[2]) << 8 | Int(encoded[3])
        XCTAssertEqual(segmentLength, 15)

        // Verify offset type: 0 = integer
        XCTAssertEqual(encoded[4], 0x00)

        // Decode and verify round-trip
        let payload = encoded.subdata(in: 2..<encoded.count)
        let decoded = try J2KDCOMarkerSegment.decode(from: payload)
        XCTAssertEqual(decoded.offsetType, .integer)
        XCTAssertEqual(decoded.offsets.count, 3)
        XCTAssertEqual(decoded.offsets[0].integerValue, 128)
        XCTAssertEqual(decoded.offsets[1].integerValue, -50)
        XCTAssertEqual(decoded.offsets[2].integerValue, 200)
    }

    func testDCOMarkerSegmentConformanceFloatingPointType() throws {
        let offsets = [
            J2KDCOffsetValue(componentIndex: 0, value: 128.5),
            J2KDCOffsetValue(componentIndex: 1, value: -50.25),
        ]
        let marker = J2KDCOMarkerSegment(offsetType: .floatingPoint, offsets: offsets)
        let encoded = try marker.encode()

        // Verify offset type: 1 = floating-point
        XCTAssertEqual(encoded[4], 0x01)

        let payload = encoded.subdata(in: 2..<encoded.count)
        let decoded = try J2KDCOMarkerSegment.decode(from: payload)
        XCTAssertEqual(decoded.offsetType, .floatingPoint)
        XCTAssertEqual(decoded.offsets.count, 2)
        // Float precision comparison
        XCTAssertEqual(decoded.offsets[0].value, 128.5, accuracy: 0.01)
        XCTAssertEqual(decoded.offsets[1].value, -50.25, accuracy: 0.01)
    }

    func testExtendedGuardBitsConformance() throws {
        // Part 2 allows 0-15 guard bits (vs 0-7 in Part 1)
        for count in 0...15 {
            let guardBits = try J2KExtendedGuardBits(count: count)
            XCTAssertEqual(guardBits.count, count)
        }
        // 16 is out of range for Part 2
        XCTAssertThrowsError(try J2KExtendedGuardBits(count: 16))
    }

    // MARK: - Edge Case Tests

    func testDCOffsetExtremePositiveValue() throws {
        let dcOffset = J2KDCOffset()
        let data = [Int32](repeating: Int32.max / 2, count: 10)
        let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 32)

        // All values should be centered around zero
        for value in result.adjustedData {
            XCTAssertEqual(value, 0)
        }
    }

    func testDCOffsetExtremeNegativeValue() throws {
        let dcOffset = J2KDCOffset()
        let data = [Int32](repeating: Int32.min / 2 + 1, count: 10)
        let result = try dcOffset.computeAndRemove(
            componentData: data,
            bitDepth: 32,
            signed: true
        )

        for value in result.adjustedData {
            XCTAssertEqual(value, 0)
        }
    }

    func testDCOffsetPrecisionLimits() throws {
        // Test with values at precision boundaries
        let dcOffset = J2KDCOffset()
        let data: [Int32] = [0, 1]
        let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 1)
        // Mean = 0.5, integer offset = 1 (rounded)
        XCTAssertNotNil(result.offset)
    }

    func testExtendedPrecisionMaxBitDepth() {
        let config = J2KExtendedPrecisionConfiguration(
            internalBitDepth: 64,
            guardBits: .maximum,
            roundingMode: .roundToEven,
            extendedDynamicRange: true
        )
        let precision = J2KExtendedPrecision(configuration: config)

        // 32-bit depth + 15 guard bits = 47 bits
        let maxMag = precision.maxMagnitude(forBitDepth: 32)
        XCTAssertEqual(maxMag, (1 << 47) - 1)
    }

    func testExtendedPrecisionOverflowProtection() {
        let precision = J2KExtendedPrecision(configuration: .highPrecision)

        // Clamping should prevent overflow
        let largeValue: Int64 = Int64.max / 2
        let clamped = precision.clampCoefficient(largeValue, bitDepth: 16)
        let maxMag = precision.maxMagnitude(forBitDepth: 16)
        XCTAssertLessThanOrEqual(clamped, maxMag)
    }

    func testDCOffsetSingleSample() throws {
        let dcOffset = J2KDCOffset()
        let data: [Int32] = [42]
        let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 8)
        XCTAssertEqual(result.offset.value, 42.0, accuracy: 1e-10)
        XCTAssertEqual(result.adjustedData, [0])

        let restored = dcOffset.apply(offset: result.offset, to: result.adjustedData)
        XCTAssertEqual(restored, data)
    }

    // MARK: - Cross-Platform Consistency Tests

    func testRoundingConsistencyAcrossModes() {
        // Verify that all rounding modes produce consistent results
        let values: [Double] = [2.5, 3.5, -2.5, -3.5, 4.49, 4.51, -4.49, -4.51]

        for mode in J2KRoundingMode.allCases {
            let config = J2KExtendedPrecisionConfiguration(roundingMode: mode)
            let precision = J2KExtendedPrecision(configuration: config)

            for value in values {
                let rounded = precision.round(value)
                let int32 = precision.roundToInt32(value)
                // roundToInt32 should be consistent with round
                XCTAssertEqual(Int32(rounded), int32,
                    "Inconsistency for value \(value) with mode \(mode)")
            }
        }
    }

    func testDCOffsetMethodConsistency() throws {
        // All methods should produce valid round-trip results
        let data: [Int32] = [10, 50, 100, 150, 200]

        for method in J2KDCOffsetMethod.allCases {
            if method == .custom { continue } // Custom doesn't auto-compute
            let config = J2KDCOffsetConfiguration(method: method)
            let dcOffset = J2KDCOffset(configuration: config)

            let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 8)
            let restored = dcOffset.apply(offset: result.offset, to: result.adjustedData)
            XCTAssertEqual(restored, data,
                "Round-trip failed for method \(method)")
        }
    }

    func testExtendedPrecisionCoefficientRoundTrip() {
        let precision = J2KExtendedPrecision(configuration: .highPrecision)
        let coefficients: [Int32] = [-1000, -100, -1, 0, 1, 100, 1000]

        // Convert to extended range and back
        let extended = precision.toExtendedRange(coefficients)
        let restored = precision.fromExtendedRange(extended, bitDepth: 16)
        XCTAssertEqual(restored, coefficients)
    }

    // MARK: - Memory Validation Tests

    func testLargeDataDCOffset() throws {
        // Test with a large dataset to validate memory efficiency
        let size = 100_000
        let data = (0..<size).map { Int32($0 % 256) }

        let dcOffset = J2KDCOffset()
        let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 8)

        XCTAssertEqual(result.adjustedData.count, size)
        XCTAssertEqual(result.statistics.count, size)

        // Verify round-trip
        let restored = dcOffset.apply(offset: result.offset, to: result.adjustedData)
        XCTAssertEqual(restored, data)
    }

    func testLargeDataExtendedPrecisionScaling() {
        let precision = J2KExtendedPrecision()
        let size = 50_000
        let coefficients = (0..<size).map { Int32($0 % 512 - 256) }

        let scaled = precision.scaleCoefficients(coefficients, by: 2.0, bitDepth: 16)
        XCTAssertEqual(scaled.count, size)

        // Verify scaling was applied
        for (i, coeff) in coefficients.enumerated() {
            XCTAssertEqual(scaled[i], coeff * 2,
                "Scaling mismatch at index \(i)")
        }
    }

    // MARK: - DCO Marker Interoperability Tests

    func testDCOMarkerSegmentMultiComponentRoundTrip() throws {
        // Simulate a 4-component image (CMYK)
        let offsets = (0..<4).map {
            J2KDCOffsetValue(componentIndex: $0, value: Double($0 * 50 + 10))
        }

        for offsetType in [J2KDCOOffsetType.integer, .floatingPoint] {
            let marker = J2KDCOMarkerSegment(offsetType: offsetType, offsets: offsets)
            let encoded = try marker.encode()
            let payload = encoded.subdata(in: 2..<encoded.count)
            let decoded = try J2KDCOMarkerSegment.decode(from: payload)

            XCTAssertEqual(decoded.offsetType, offsetType)
            XCTAssertEqual(decoded.offsets.count, 4)
            for i in 0..<4 {
                if offsetType == .integer {
                    XCTAssertEqual(decoded.offsets[i].integerValue, offsets[i].integerValue)
                } else {
                    XCTAssertEqual(decoded.offsets[i].value, offsets[i].value, accuracy: 0.1)
                }
            }
        }
    }

    func testDCOMarkerSegmentEmptyComponents() throws {
        // Edge case: zero components
        let marker = J2KDCOMarkerSegment(offsetType: .integer, offsets: [])
        let encoded = try marker.encode()
        let payload = encoded.subdata(in: 2..<encoded.count)
        let decoded = try J2KDCOMarkerSegment.decode(from: payload)
        XCTAssertEqual(decoded.offsets.count, 0)
    }

    func testDCOMarkerSegmentNegativeOffsets() throws {
        let offsets = [
            J2KDCOffsetValue(componentIndex: 0, value: -1000.0),
            J2KDCOffsetValue(componentIndex: 1, value: -1.0),
        ]
        let marker = J2KDCOMarkerSegment(offsetType: .integer, offsets: offsets)
        let encoded = try marker.encode()
        let payload = encoded.subdata(in: 2..<encoded.count)
        let decoded = try J2KDCOMarkerSegment.decode(from: payload)

        XCTAssertEqual(decoded.offsets[0].integerValue, -1000)
        XCTAssertEqual(decoded.offsets[1].integerValue, -1)
    }

    // MARK: - Pipeline Integration End-to-End

    func testEncoderDecoderDCOffsetPipeline() throws {
        // Simulate the full pipeline: encoder computes offset → generates marker →
        // decoder parses marker → applies offset
        let components: [[Int32]] = [
            [100, 110, 120, 130, 140],
            [50, 60, 70, 80, 90],
            [200, 210, 220, 230, 240],
        ]

        // Encoder path
        let encoderDCOffset = J2KDCOffset(configuration: .default)
        let results = try encoderDCOffset.computeAndRemoveAll(
            components: components,
            bitDepths: [8, 8, 8],
            signed: [false, false, false]
        )

        // Generate DCO marker
        let marker = encoderDCOffset.createMarkerSegment(from: results)
        let encodedMarker = try marker.encode()

        // Decoder path: parse DCO marker
        let payload = encodedMarker.subdata(in: 2..<encodedMarker.count)
        let decodedMarker = try J2KDCOMarkerSegment.decode(from: payload)

        // Apply offsets to recover data
        let decoderDCOffset = J2KDCOffset()
        let restored = try decoderDCOffset.applyAll(
            offsets: decodedMarker.offsets,
            to: results.map { $0.adjustedData }
        )

        // Verify perfect reconstruction
        for i in 0..<3 {
            XCTAssertEqual(restored[i], components[i],
                "Component \(i) reconstruction failed")
        }
    }

    func testPrecisionPreservationThroughPipeline() {
        // Verify precision is preserved through scaling operations
        let precision = J2KExtendedPrecision(configuration: .highPrecision)
        let original: [Int32] = [1000, -2000, 3000, -4000]

        // Scale up then scale down should preserve values
        let scaledUp = precision.scaleCoefficients(original, by: 2.0, bitDepth: 16)
        let scaledDown = precision.scaleCoefficients(scaledUp, by: 0.5, bitDepth: 16)

        XCTAssertEqual(scaledDown, original)
    }

    // MARK: - Guard Bit Recommendation Tests

    func testGuardBitRecommendationForStandardImages() {
        let bits = J2KExtendedPrecision.recommendedGuardBits(
            forBitDepth: 8,
            decompositionLevels: 5
        )
        XCTAssertEqual(bits, 5)
    }

    func testGuardBitRecommendationForHDR() {
        let bits = J2KExtendedPrecision.recommendedGuardBits(
            forBitDepth: 32,
            decompositionLevels: 6
        )
        // 6 levels + 2 extra for > 16-bit depth = 8
        XCTAssertEqual(bits, 8)
    }

    func testGuardBitRecommendationClamped() {
        let bits = J2KExtendedPrecision.recommendedGuardBits(
            forBitDepth: 32,
            decompositionLevels: 15
        )
        // Should be clamped to 15 (maximum)
        XCTAssertLessThanOrEqual(bits, 15)
    }
}
