//
// J2KHTBlockCoderOptimizationTests.swift
// J2KSwift
//
// J2KHTBlockCoderOptimizationTests.swift
// J2KSwift
//
// Tests for HT block coder memory optimizations
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KHTBlockCoderOptimizationTests: XCTestCase {
    // MARK: - Optimized Encoder Tests

    func testOptimizedEncoderSmallBlocks() throws {
        let width = 8
        let height = 8
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -50...50) }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let encoded = try encoder.encodeCleanupOptimized(coefficients: coefficients, bitPlane: 7)

        XCTAssertGreaterThan(encoded.codedData.count, 0)
        XCTAssertEqual(encoded.width, width)
        XCTAssertEqual(encoded.height, height)
    }

    func testOptimizedEncoderLargeBlocks() throws {
        let width = 64
        let height = 64
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -100...100) }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let encoded = try encoder.encodeCleanupOptimized(coefficients: coefficients, bitPlane: 7)

        XCTAssertGreaterThan(encoded.codedData.count, 0)
    }

    func testOptimizedEncoderMatchesStandard() throws {
        let width = 16
        let height = 16
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -50...50) }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

        let standard = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)
        let optimized = try encoder.encodeCleanupOptimized(coefficients: coefficients, bitPlane: 7)

        // Should produce identical results
        XCTAssertEqual(standard.codedData, optimized.codedData)
        XCTAssertEqual(standard.melLength, optimized.melLength)
        XCTAssertEqual(standard.vlcLength, optimized.vlcLength)
        XCTAssertEqual(standard.magsgnLength, optimized.magsgnLength)
    }

    // MARK: - Optimized Decoder Tests

    func testOptimizedDecoderSmallBlocks() throws {
        let width = 8
        let height = 8
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -50...50) }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let encoded = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        let decoded = try decoder.decodeCleanupOptimized(from: encoded)

        XCTAssertEqual(decoded.count, width * height)
    }

    func testOptimizedDecoderMatchesStandard() throws {
        let width = 16
        let height = 16
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -50...50) }

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let encoded = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)

        let standard = try decoder.decodeCleanup(from: encoded)
        let optimized = try decoder.decodeCleanupOptimized(from: encoded)

        XCTAssertEqual(standard, optimized)
    }

    // MARK: - In-Place Transform Tests

    func testQuantizeInPlace() {
        var coefficients = [100, -200, 50, -75, 0]
        let stepSize = 10.0

        HTCoefficientTransform.quantizeInPlace(&coefficients, stepSize: stepSize)

        XCTAssertEqual(coefficients[0], 10)
        XCTAssertEqual(coefficients[1], -20)
        XCTAssertEqual(coefficients[2], 5)
        XCTAssertEqual(coefficients[3], -7)
        XCTAssertEqual(coefficients[4], 0)
    }

    func testDequantizeInPlace() {
        var coefficients = [10, -20, 5, -7, 0]
        let stepSize = 10.0

        HTCoefficientTransform.dequantizeInPlace(&coefficients, stepSize: stepSize)

        XCTAssertEqual(coefficients[0], 100)
        XCTAssertEqual(coefficients[1], -200)
        XCTAssertEqual(coefficients[2], 50)
        XCTAssertEqual(coefficients[3], -70)
        XCTAssertEqual(coefficients[4], 0)
    }

    func testQuantizeDequantizeRoundtrip() {
        var original = [100, -200, 50, -80, 0]
        let stepSize = 10.0

        var quantized = original
        HTCoefficientTransform.quantizeInPlace(&quantized, stepSize: stepSize)
        HTCoefficientTransform.dequantizeInPlace(&quantized, stepSize: stepSize)

        // Should be close to original (within quantization error)
        for i in 0..<original.count {
            let diff = abs(original[i] - quantized[i])
            XCTAssertLessThan(diff, Int(stepSize), "Index \(i) differs too much")
        }
    }

    // MARK: - Lazy Coding Pass Tests

    func testLazySigPropNotNeeded() throws {
        let width = 16
        let height = 16
        let coefficients = [Int](repeating: 0, count: width * height)
        let significanceState = [Bool](repeating: false, count: width * height)

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

        let result = try HTLazyCodingPasses.encodeSigPropIfNeeded(
            encoder: encoder,
            coefficients: coefficients,
            significanceState: significanceState,
            bitPlane: 7,
            needsSigProp: false
        )

        XCTAssertNil(result, "Should not encode when not needed")
    }

    func testLazySigPropNeeded() throws {
        let width = 16
        let height = 16
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -50...50) }
        let significanceState = [Bool](repeating: false, count: width * height)

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

        let result = try HTLazyCodingPasses.encodeSigPropIfNeeded(
            encoder: encoder,
            coefficients: coefficients,
            significanceState: significanceState,
            bitPlane: 7,
            needsSigProp: true
        )

        XCTAssertNotNil(result, "Should encode when needed")
    }

    func testLazyMagRefNotNeeded() throws {
        let width = 16
        let height = 16
        let coefficients = [Int](repeating: 0, count: width * height)
        let significanceState = [Bool](repeating: false, count: width * height)

        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)

        let result = try HTLazyCodingPasses.encodeMagRefIfNeeded(
            encoder: encoder,
            coefficients: coefficients,
            significanceState: significanceState,
            bitPlane: 7,
            needsMagRef: false
        )

        XCTAssertNil(result, "Should not encode when not needed")
    }
}
