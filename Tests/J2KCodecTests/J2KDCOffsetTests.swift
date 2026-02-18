// J2KDCOffsetTests.swift
// J2KSwift
//
// Tests for JPEG 2000 Part 2 variable DC offset and extended precision.
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Comprehensive tests for DC offset and extended precision.
final class J2KDCOffsetTests: XCTestCase {

    // MARK: - DC Offset Configuration Tests

    func testDefaultConfiguration() {
        let config = J2KDCOffsetConfiguration.default
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.method, .mean)
        XCTAssertFalse(config.optimizeForNaturalImages)
    }

    func testDisabledConfiguration() {
        let config = J2KDCOffsetConfiguration.disabled
        XCTAssertFalse(config.enabled)
    }

    func testNaturalImageConfiguration() {
        let config = J2KDCOffsetConfiguration.naturalImage
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.method, .mean)
        XCTAssertTrue(config.optimizeForNaturalImages)
    }

    func testCustomConfiguration() {
        let config = J2KDCOffsetConfiguration(
            enabled: true,
            method: .midrange,
            optimizeForNaturalImages: false
        )
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.method, .midrange)
        XCTAssertFalse(config.optimizeForNaturalImages)
    }

    // MARK: - DC Offset Method Tests

    func testDCOffsetMethodAllCases() {
        let allMethods = J2KDCOffsetMethod.allCases
        XCTAssertEqual(allMethods.count, 3)
        XCTAssertTrue(allMethods.contains(.mean))
        XCTAssertTrue(allMethods.contains(.midrange))
        XCTAssertTrue(allMethods.contains(.custom))
    }

    // MARK: - Statistics Computation Tests

    func testStatisticsEmpty() {
        let dcOffset = J2KDCOffset()
        let stats = dcOffset.computeStatistics([])
        XCTAssertEqual(stats.mean, 0.0)
        XCTAssertEqual(stats.minimum, 0)
        XCTAssertEqual(stats.maximum, 0)
        XCTAssertEqual(stats.count, 0)
    }

    func testStatisticsSingleValue() {
        let dcOffset = J2KDCOffset()
        let stats = dcOffset.computeStatistics([42])
        XCTAssertEqual(stats.mean, 42.0)
        XCTAssertEqual(stats.minimum, 42)
        XCTAssertEqual(stats.maximum, 42)
        XCTAssertEqual(stats.count, 1)
    }

    func testStatisticsUniform() {
        let dcOffset = J2KDCOffset()
        let data = [Int32](repeating: 128, count: 100)
        let stats = dcOffset.computeStatistics(data)
        XCTAssertEqual(stats.mean, 128.0, accuracy: 1e-10)
        XCTAssertEqual(stats.minimum, 128)
        XCTAssertEqual(stats.maximum, 128)
        XCTAssertEqual(stats.count, 100)
    }

    func testStatisticsRange() {
        let dcOffset = J2KDCOffset()
        let data: [Int32] = [0, 50, 100, 150, 200, 250]
        let stats = dcOffset.computeStatistics(data)
        XCTAssertEqual(stats.mean, 125.0, accuracy: 1e-10)
        XCTAssertEqual(stats.minimum, 0)
        XCTAssertEqual(stats.maximum, 250)
        XCTAssertEqual(stats.count, 6)
        XCTAssertEqual(stats.midrange, 125.0, accuracy: 1e-10)
    }

    func testStatisticsSignedData() {
        let dcOffset = J2KDCOffset()
        let data: [Int32] = [-100, -50, 0, 50, 100]
        let stats = dcOffset.computeStatistics(data)
        XCTAssertEqual(stats.mean, 0.0, accuracy: 1e-10)
        XCTAssertEqual(stats.minimum, -100)
        XCTAssertEqual(stats.maximum, 100)
        XCTAssertEqual(stats.midrange, 0.0, accuracy: 1e-10)
    }

    // MARK: - DC Offset Computation Tests

    func testComputeOffsetMean() {
        let dcOffset = J2KDCOffset(configuration: .default)
        let stats = J2KComponentStatistics(mean: 128.5, minimum: 0, maximum: 255, count: 1000)
        let offset = dcOffset.computeOffset(from: stats, componentIndex: 0, bitDepth: 8, signed: false)
        XCTAssertEqual(offset.componentIndex, 0)
        XCTAssertEqual(offset.value, 128.5, accuracy: 1e-10)
    }

    func testComputeOffsetMidrange() {
        let config = J2KDCOffsetConfiguration(method: .midrange)
        let dcOffset = J2KDCOffset(configuration: config)
        let stats = J2KComponentStatistics(mean: 100.0, minimum: 10, maximum: 200, count: 100)
        let offset = dcOffset.computeOffset(from: stats, componentIndex: 0, bitDepth: 8, signed: false)
        XCTAssertEqual(offset.value, 105.0, accuracy: 1e-10) // (10 + 200) / 2
    }

    func testComputeOffsetDisabled() {
        let dcOffset = J2KDCOffset(configuration: .disabled)
        let stats = J2KComponentStatistics(mean: 128.0, minimum: 0, maximum: 255, count: 100)
        let offset = dcOffset.computeOffset(from: stats, componentIndex: 0, bitDepth: 8, signed: false)
        XCTAssertEqual(offset.value, 0.0)
    }

    func testComputeOffsetNaturalImage() {
        let dcOffset = J2KDCOffset(configuration: .naturalImage)
        let stats = J2KComponentStatistics(mean: 128.3, minimum: 0, maximum: 255, count: 1000)
        let offset = dcOffset.computeOffset(from: stats, componentIndex: 0, bitDepth: 8, signed: false)
        // Natural image optimization rounds to nearest integer
        XCTAssertEqual(offset.value, 128.0, accuracy: 1e-10)
    }

    // MARK: - DC Offset Value Tests

    func testDCOffsetValueInteger() {
        let offset = J2KDCOffsetValue(componentIndex: 0, value: 128.7)
        XCTAssertEqual(offset.integerValue, 129)
    }

    func testDCOffsetValueZero() {
        let offset = J2KDCOffsetValue.zero(componentIndex: 2)
        XCTAssertEqual(offset.componentIndex, 2)
        XCTAssertEqual(offset.value, 0.0)
        XCTAssertEqual(offset.integerValue, 0)
    }

    // MARK: - Compute and Remove Tests

    func testComputeAndRemoveBasic() throws {
        let dcOffset = J2KDCOffset()
        let data: [Int32] = [100, 110, 120, 130, 140]
        let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 8)

        // Mean = 120, so offset should be 120
        XCTAssertEqual(result.offset.value, 120.0, accuracy: 1e-10)
        XCTAssertEqual(result.adjustedData, [-20, -10, 0, 10, 20])
    }

    func testComputeAndRemoveUniform() throws {
        let dcOffset = J2KDCOffset()
        let data = [Int32](repeating: 200, count: 50)
        let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 8)

        XCTAssertEqual(result.offset.value, 200.0, accuracy: 1e-10)
        for value in result.adjustedData {
            XCTAssertEqual(value, 0)
        }
    }

    func testComputeAndRemoveDisabled() throws {
        let dcOffset = J2KDCOffset(configuration: .disabled)
        let data: [Int32] = [100, 200, 150]
        let result = try dcOffset.computeAndRemove(componentData: data, bitDepth: 8)

        XCTAssertEqual(result.offset.value, 0.0)
        XCTAssertEqual(result.adjustedData, data)
    }

    func testComputeAndRemoveInvalidBitDepth() {
        let dcOffset = J2KDCOffset()
        XCTAssertThrowsError(try dcOffset.computeAndRemove(componentData: [1, 2, 3], bitDepth: 0))
        XCTAssertThrowsError(try dcOffset.computeAndRemove(componentData: [1, 2, 3], bitDepth: 39))
    }

    // MARK: - Apply (Restore) Tests

    func testApplyOffset() {
        let dcOffset = J2KDCOffset()
        let offset = J2KDCOffsetValue(componentIndex: 0, value: 128.0)
        let data: [Int32] = [-28, -18, -8, 2, 12]
        let restored = dcOffset.apply(offset: offset, to: data)
        XCTAssertEqual(restored, [100, 110, 120, 130, 140])
    }

    func testApplyZeroOffset() {
        let dcOffset = J2KDCOffset()
        let offset = J2KDCOffsetValue.zero(componentIndex: 0)
        let data: [Int32] = [10, 20, 30]
        let restored = dcOffset.apply(offset: offset, to: data)
        XCTAssertEqual(restored, data)
    }

    // MARK: - Round-Trip Tests

    func testRoundTripInteger() throws {
        let dcOffset = J2KDCOffset()
        let original: [Int32] = [100, 110, 120, 130, 140]

        let result = try dcOffset.computeAndRemove(componentData: original, bitDepth: 8)
        let restored = dcOffset.apply(offset: result.offset, to: result.adjustedData)

        XCTAssertEqual(restored, original)
    }

    func testRoundTripZeroMean() throws {
        let dcOffset = J2KDCOffset()
        let original: [Int32] = [-20, -10, 0, 10, 20]

        let result = try dcOffset.computeAndRemove(componentData: original, bitDepth: 8, signed: true)
        let restored = dcOffset.apply(offset: result.offset, to: result.adjustedData)

        XCTAssertEqual(restored, original)
    }

    func testRoundTripLargeValues() throws {
        let dcOffset = J2KDCOffset()
        let original: [Int32] = [10000, 20000, 30000, 40000, 50000]

        let result = try dcOffset.computeAndRemove(componentData: original, bitDepth: 16)
        let restored = dcOffset.apply(offset: result.offset, to: result.adjustedData)

        XCTAssertEqual(restored, original)
    }

    func testRoundTripMidrange() throws {
        let config = J2KDCOffsetConfiguration(method: .midrange)
        let dcOffset = J2KDCOffset(configuration: config)
        let original: [Int32] = [10, 50, 100, 150, 200]

        let result = try dcOffset.computeAndRemove(componentData: original, bitDepth: 8)
        let restored = dcOffset.apply(offset: result.offset, to: result.adjustedData)

        XCTAssertEqual(restored, original)
    }

    // MARK: - Multi-Component Tests

    func testComputeAndRemoveAll() throws {
        let dcOffset = J2KDCOffset()
        let components: [[Int32]] = [
            [100, 110, 120, 130, 140],  // R
            [50, 60, 70, 80, 90],       // G
            [200, 210, 220, 230, 240]   // B
        ]
        let bitDepths = [8, 8, 8]
        let signed = [false, false, false]

        let results = try dcOffset.computeAndRemoveAll(
            components: components,
            bitDepths: bitDepths,
            signed: signed
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].offset.componentIndex, 0)
        XCTAssertEqual(results[1].offset.componentIndex, 1)
        XCTAssertEqual(results[2].offset.componentIndex, 2)
    }

    func testApplyAll() throws {
        let dcOffset = J2KDCOffset()
        let offsets = [
            J2KDCOffsetValue(componentIndex: 0, value: 120.0),
            J2KDCOffsetValue(componentIndex: 1, value: 70.0),
            J2KDCOffsetValue(componentIndex: 2, value: 220.0),
        ]
        let components: [[Int32]] = [
            [-20, -10, 0, 10, 20],
            [-20, -10, 0, 10, 20],
            [-20, -10, 0, 10, 20],
        ]

        let restored = try dcOffset.applyAll(offsets: offsets, to: components)
        XCTAssertEqual(restored[0], [100, 110, 120, 130, 140])
        XCTAssertEqual(restored[1], [50, 60, 70, 80, 90])
        XCTAssertEqual(restored[2], [200, 210, 220, 230, 240])
    }

    func testComponentCountMismatch() {
        let dcOffset = J2KDCOffset()
        XCTAssertThrowsError(try dcOffset.computeAndRemoveAll(
            components: [[1, 2], [3, 4]],
            bitDepths: [8],
            signed: [false, false]
        ))

        XCTAssertThrowsError(try dcOffset.applyAll(
            offsets: [.zero(componentIndex: 0)],
            to: [[1, 2], [3, 4]]
        ))
    }

    // MARK: - DCO Marker Segment Tests

    func testDCOMarkerSegmentEncodeInteger() throws {
        let marker = J2KDCOMarkerSegment(
            offsetType: .integer,
            offsets: [
                J2KDCOffsetValue(componentIndex: 0, value: 128.0),
                J2KDCOffsetValue(componentIndex: 1, value: 64.0),
            ]
        )

        let data = try marker.encode()
        XCTAssertGreaterThan(data.count, 0)

        // Verify marker code
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x5C)
    }

    func testDCOMarkerSegmentRoundTrip() throws {
        let original = J2KDCOMarkerSegment(
            offsetType: .integer,
            offsets: [
                J2KDCOffsetValue(componentIndex: 0, value: 128.0),
                J2KDCOffsetValue(componentIndex: 1, value: -50.0),
                J2KDCOffsetValue(componentIndex: 2, value: 200.0),
            ]
        )

        let encoded = try original.encode()

        // Decode: skip marker code (2 bytes)
        let payload = encoded.subdata(in: 2..<encoded.count)
        let decoded = try J2KDCOMarkerSegment.decode(from: payload)

        XCTAssertEqual(decoded.offsetType, original.offsetType)
        XCTAssertEqual(decoded.offsets.count, original.offsets.count)

        for (dec, orig) in zip(decoded.offsets, original.offsets) {
            XCTAssertEqual(dec.componentIndex, orig.componentIndex)
            XCTAssertEqual(dec.integerValue, orig.integerValue)
        }
    }

    func testDCOMarkerSegmentDecodeError() {
        // Too short
        XCTAssertThrowsError(try J2KDCOMarkerSegment.decode(from: Data([0x00])))
        // Invalid offset type
        XCTAssertThrowsError(try J2KDCOMarkerSegment.decode(from: Data([0x00, 0x03, 0xFF])))
    }

    func testCreateMarkerSegment() throws {
        let dcOffset = J2KDCOffset()
        let results = try dcOffset.computeAndRemoveAll(
            components: [[100, 200], [50, 150]],
            bitDepths: [8, 8],
            signed: [false, false]
        )

        let marker = dcOffset.createMarkerSegment(from: results)
        XCTAssertEqual(marker.offsets.count, 2)
        XCTAssertEqual(marker.offsetType, .integer)
    }

    // MARK: - Extended Guard Bits Tests

    func testExtendedGuardBitsValid() throws {
        for count in 0...15 {
            let guardBits = try J2KExtendedGuardBits(count: count)
            XCTAssertEqual(guardBits.count, count)
        }
    }

    func testExtendedGuardBitsInvalid() {
        XCTAssertThrowsError(try J2KExtendedGuardBits(count: -1))
        XCTAssertThrowsError(try J2KExtendedGuardBits(count: 16))
        XCTAssertThrowsError(try J2KExtendedGuardBits(count: 100))
    }

    func testExtendedGuardBitsDefaults() {
        XCTAssertEqual(J2KExtendedGuardBits.default.count, 2)
        XCTAssertEqual(J2KExtendedGuardBits.maximum.count, 15)
        XCTAssertEqual(J2KExtendedGuardBits.highBitDepth.count, 4)
    }

    // MARK: - Rounding Mode Tests

    func testRoundingModeAllCases() {
        let allModes = J2KRoundingMode.allCases
        XCTAssertEqual(allModes.count, 3)
        XCTAssertTrue(allModes.contains(.truncate))
        XCTAssertTrue(allModes.contains(.roundToNearest))
        XCTAssertTrue(allModes.contains(.roundToEven))
    }

    func testTruncateRounding() {
        let config = J2KExtendedPrecisionConfiguration(roundingMode: .truncate)
        let precision = J2KExtendedPrecision(configuration: config)

        XCTAssertEqual(precision.round(2.7), 2.0)
        XCTAssertEqual(precision.round(2.3), 2.0)
        XCTAssertEqual(precision.round(-2.7), -2.0)
        XCTAssertEqual(precision.round(-2.3), -2.0)
    }

    func testRoundToNearestRounding() {
        let config = J2KExtendedPrecisionConfiguration(roundingMode: .roundToNearest)
        let precision = J2KExtendedPrecision(configuration: config)

        XCTAssertEqual(precision.round(2.7), 3.0)
        XCTAssertEqual(precision.round(2.3), 2.0)
        XCTAssertEqual(precision.round(-2.7), -3.0)
        XCTAssertEqual(precision.round(-2.3), -2.0)
    }

    func testRoundToEvenRounding() {
        let config = J2KExtendedPrecisionConfiguration(roundingMode: .roundToEven)
        let precision = J2KExtendedPrecision(configuration: config)

        // 0.5 cases: round to even
        XCTAssertEqual(precision.round(2.5), 2.0)  // 2 is even
        XCTAssertEqual(precision.round(3.5), 4.0)  // 4 is even
        // Non-0.5 cases: standard rounding
        XCTAssertEqual(precision.round(2.3), 2.0)
        XCTAssertEqual(precision.round(2.7), 3.0)
    }

    // MARK: - Extended Precision Configuration Tests

    func testDefaultPrecisionConfig() {
        let config = J2KExtendedPrecisionConfiguration.default
        XCTAssertEqual(config.internalBitDepth, 32)
        XCTAssertEqual(config.guardBits.count, 2)
        XCTAssertEqual(config.roundingMode, .roundToNearest)
        XCTAssertFalse(config.extendedDynamicRange)
    }

    func testHighPrecisionConfig() {
        let config = J2KExtendedPrecisionConfiguration.highPrecision
        XCTAssertEqual(config.internalBitDepth, 64)
        XCTAssertEqual(config.guardBits.count, 4)
        XCTAssertEqual(config.roundingMode, .roundToEven)
        XCTAssertTrue(config.extendedDynamicRange)
    }

    func testInternalBitDepthClamping() {
        let tooLow = J2KExtendedPrecisionConfiguration(internalBitDepth: 8)
        XCTAssertEqual(tooLow.internalBitDepth, 16)

        let tooHigh = J2KExtendedPrecisionConfiguration(internalBitDepth: 128)
        XCTAssertEqual(tooHigh.internalBitDepth, 64)
    }

    // MARK: - Extended Precision Arithmetic Tests

    func testMultiplyInt32() {
        let precision = J2KExtendedPrecision()
        XCTAssertEqual(precision.multiply(Int32(100), by: 2.0), 200)
        XCTAssertEqual(precision.multiply(Int32(-50), by: 3.0), -150)
        XCTAssertEqual(precision.multiply(Int32(7), by: 0.5), 4) // 3.5 rounds to 4
    }

    func testDivideInt32() throws {
        let precision = J2KExtendedPrecision()
        XCTAssertEqual(try precision.divide(Int32(100), by: 2.0), 50)
        XCTAssertEqual(try precision.divide(Int32(7), by: 2.0), 4) // 3.5 rounds to 4
    }

    func testDivideByZero() {
        let precision = J2KExtendedPrecision()
        XCTAssertThrowsError(try precision.divide(Int32(100), by: 0.0))
    }

    // MARK: - Max Magnitude Tests

    func testMaxMagnitudeStandard() {
        let precision = J2KExtendedPrecision()
        let maxMag = precision.maxMagnitude(forBitDepth: 8)
        // 8 bit depth + 2 guard bits = 10 bits, max = 1023
        XCTAssertEqual(maxMag, 1023)
    }

    func testMaxMagnitudeExtended() {
        let config = J2KExtendedPrecisionConfiguration(
            guardBits: .highBitDepth,
            extendedDynamicRange: true
        )
        let precision = J2KExtendedPrecision(configuration: config)
        let maxMag = precision.maxMagnitude(forBitDepth: 16)
        // 16 + 4 = 20 bits
        XCTAssertEqual(maxMag, (1 << 20) - 1)
    }

    // MARK: - Coefficient Scaling Tests

    func testScaleCoefficients() {
        let precision = J2KExtendedPrecision()
        let coefficients: [Int32] = [10, -20, 30, -40]
        let scaled = precision.scaleCoefficients(coefficients, by: 2.0, bitDepth: 8)
        XCTAssertEqual(scaled, [20, -40, 60, -80])
    }

    // MARK: - Extended Range Conversion Tests

    func testToExtendedRange() {
        let precision = J2KExtendedPrecision()
        let data: [Int32] = [100, -200, 300]
        let extended = precision.toExtendedRange(data)
        XCTAssertEqual(extended, [100, -200, 300])
    }

    func testFromExtendedRange() {
        let precision = J2KExtendedPrecision()
        let data: [Int64] = [100, -200, 300]
        let result = precision.fromExtendedRange(data, bitDepth: 8)
        XCTAssertEqual(result, [100, -200, 300])
    }

    // MARK: - Guard Bit Validation Tests

    func testValidateGuardBitsSufficient() {
        let config = J2KExtendedPrecisionConfiguration(
            guardBits: try! J2KExtendedGuardBits(count: 5)
        )
        let precision = J2KExtendedPrecision(configuration: config)
        XCTAssertTrue(precision.validateGuardBits(forBitDepth: 8, decompositionLevels: 5))
        XCTAssertTrue(precision.validateGuardBits(forBitDepth: 8, decompositionLevels: 3))
    }

    func testValidateGuardBitsInsufficient() {
        let precision = J2KExtendedPrecision() // default 2 guard bits
        XCTAssertFalse(precision.validateGuardBits(forBitDepth: 8, decompositionLevels: 5))
    }

    func testRecommendedGuardBits() {
        // Standard 8-bit, 3 levels
        let bits1 = J2KExtendedPrecision.recommendedGuardBits(forBitDepth: 8, decompositionLevels: 3)
        XCTAssertEqual(bits1, 3)

        // 16-bit, 5 levels
        let bits2 = J2KExtendedPrecision.recommendedGuardBits(forBitDepth: 16, decompositionLevels: 5)
        XCTAssertEqual(bits2, 6) // 5 + 1 extra for bit depth > 12

        // HDR 32-bit, 5 levels
        let bits3 = J2KExtendedPrecision.recommendedGuardBits(forBitDepth: 32, decompositionLevels: 5)
        XCTAssertEqual(bits3, 7) // 5 + 2 extra for bit depth > 16
    }
}
