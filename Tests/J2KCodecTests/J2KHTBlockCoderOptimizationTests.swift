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
    // MARK: - Pooled Encoder Tests

    func testPooledEncoderBasicFunctionality() async throws {
        let width = 32
        let height = 32
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -100...100) }

        let encoder = HTBlockEncoderPooled(width: width, height: height, subband: .hh)
        let encoded = try await encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        XCTAssertEqual(encoded.width, width)
        XCTAssertEqual(encoded.height, height)
        XCTAssertEqual(encoded.passType, .htCleanup)
        XCTAssertGreaterThan(encoded.codedData.count, 0)
    }

    func testPooledEncoderMatchesStandardEncoder() async throws {
        let width = 32
        let height = 32
        let coefficients = (0..<(width * height)).map { _ in Int.random(in: -50...50) }

        // Standard encoder
        let standardEncoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let standardEncoded = try standardEncoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        // Pooled encoder
        let pooledEncoder = HTBlockEncoderPooled(width: width, height: height, subband: .hh)
        let pooledEncoded = try await pooledEncoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        // Results should be identical
        XCTAssertEqual(standardEncoded.melLength, pooledEncoded.melLength)
        XCTAssertEqual(standardEncoded.vlcLength, pooledEncoded.vlcLength)
        XCTAssertEqual(standardEncoded.magsgnLength, pooledEncoded.magsgnLength)
        XCTAssertEqual(standardEncoded.codedData, pooledEncoded.codedData)
    }

    func testPooledEncoderDifferentBlockSizes() async throws {
        let blockSizes = [(16, 16), (32, 32), (64, 64)]

        for (width, height) in blockSizes {
            let coefficients = (0..<(width * height)).map { _ in Int.random(in: -100...100) }
            let encoder = HTBlockEncoderPooled(width: width, height: height, subband: .hh)

            let encoded = try await encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

            XCTAssertGreaterThan(encoded.codedData.count, 0, "Failed for \(width)×\(height)")
        }
    }

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

    // MARK: - Pool Configuration Tests

    func testPoolConfigPrewarm32x32() async throws {
        let config = HTBlockCoderPoolConfig.standard32x32
        await config.prewarmPool()

        // Verify pool has cached buffers
        let pool = J2KBufferPool.shared
        let stats = await pool.statistics()

        // Should have some cached buffers for the estimated size
        let estimatedSize = (32 * 32) / 2
        XCTAssertNotNil(stats.uint8[estimatedSize], "Pool should have buffers cached")
    }

    func testPoolConfigPrewarm64x64() async throws {
        let config = HTBlockCoderPoolConfig.standard64x64
        await config.prewarmPool()

        let pool = J2KBufferPool.shared
        let stats = await pool.statistics()

        let estimatedSize = (64 * 64) / 2
        XCTAssertNotNil(stats.uint8[estimatedSize], "Pool should have buffers cached")
    }

    // MARK: - Performance Comparison Tests

    func testPooledVsStandardEncodingPerformance() async throws {
        let width = 32
        let height = 32
        let iterations = 10

        // Warm up
        let warmupCoeffs = (0..<(width * height)).map { _ in Int.random(in: -100...100) }
        let warmupEncoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        _ = try warmupEncoder.encodeCleanup(coefficients: warmupCoeffs, bitPlane: 7)

        // Standard encoder timing
        let standardStart = Date()
        for _ in 0..<iterations {
            let coeffs = (0..<(width * height)).map { _ in Int.random(in: -100...100) }
            let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
            _ = try encoder.encodeCleanup(coefficients: coeffs, bitPlane: 7)
        }
        let standardTime = Date().timeIntervalSince(standardStart)

        // Pooled encoder timing
        let pooledStart = Date()
        for _ in 0..<iterations {
            let coeffs = (0..<(width * height)).map { _ in Int.random(in: -100...100) }
            let encoder = HTBlockEncoderPooled(width: width, height: height, subband: .hh)
            _ = try await encoder.encodeCleanup(coefficients: coeffs, bitPlane: 7)
        }
        let pooledTime = Date().timeIntervalSince(pooledStart)

        print("Standard encoder: \(standardTime)s")
        print("Pooled encoder: \(pooledTime)s")
        print("Speedup: \(standardTime / pooledTime)x")

        // Pooled should be faster or comparable
        // (In practice, pooled is faster for repeated encoding)
    }
}
