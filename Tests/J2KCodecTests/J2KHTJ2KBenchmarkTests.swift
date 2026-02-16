import XCTest
@testable import J2KCodec
@testable import J2KCore

/// HTJ2K performance benchmarks comparing HTJ2K vs legacy JPEG 2000 encoding/decoding.
///
/// This test suite measures the performance improvements of HTJ2K (High-Throughput
/// JPEG 2000) compared to legacy JPEG 2000 Part 1 encoding. The goal is to achieve
/// 10-100× faster encoding/decoding throughput.
///
/// ## Performance Targets (ISO/IEC 15444-15)
///
/// - HTJ2K encoding speed: 10-100× faster than legacy JPEG 2000
/// - HTJ2K decoding speed: 10-100× faster than legacy JPEG 2000
/// - Compression efficiency: Equivalent to legacy JPEG 2000
/// - Memory usage: Comparable or better than legacy
///
/// ## Test Methodology
///
/// Each test compares:
/// 1. Legacy EBCOT block coding
/// 2. HTJ2K FBCOT block coding
///
/// Tests use identical wavelet coefficients to ensure fair comparison.
final class J2KHTJ2KBenchmarkTests: XCTestCase {
    
    /// Number of iterations for benchmarking.
    private let benchmarkIterations = 100
    
    /// Number of warmup iterations.
    private let warmupIterations = 10
    
    // MARK: - HTJ2K Block Encoder Benchmarks
    
    /// Benchmarks HTJ2K cleanup pass encoding for 32×32 code-block.
    func testHTJ2KCleanupEncode32x32() throws {
        let width = 32
        let height = 32
        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        
        // Create test coefficients with realistic distribution
        var coefficients = [Int](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int.random(in: -64...64)
        }
        
        // Warmup
        for _ in 0..<warmupIterations {
            _ = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 6)
        }
        
        // Benchmark
        var times: [TimeInterval] = []
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 6)
            let elapsed = Date().timeIntervalSince(start)
            times.append(elapsed)
        }
        
        let avgTime = times.reduce(0, +) / Double(times.count)
        let throughput = Double(width * height) / avgTime
        
        print("""
            HTJ2K Cleanup Encode 32×32:
              Avg time: \(String(format: "%.4f", avgTime * 1000)) ms
              Throughput: \(String(format: "%.0f", throughput)) samples/sec
            """)
        
        // Should be reasonably fast
        XCTAssertLessThan(avgTime, 0.01, "HTJ2K cleanup should encode 32×32 in <10ms")
    }
    
    /// Benchmarks HTJ2K cleanup pass encoding for 64×64 code-block.
    func testHTJ2KCleanupEncode64x64() throws {
        let width = 64
        let height = 64
        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        
        var coefficients = [Int](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int.random(in: -128...128)
        }
        
        // Warmup
        for _ in 0..<warmupIterations {
            _ = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)
        }
        
        // Benchmark
        var times: [TimeInterval] = []
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)
            let elapsed = Date().timeIntervalSince(start)
            times.append(elapsed)
        }
        
        let avgTime = times.reduce(0, +) / Double(times.count)
        let throughput = Double(width * height) / avgTime
        
        print("""
            HTJ2K Cleanup Encode 64×64:
              Avg time: \(String(format: "%.4f", avgTime * 1000)) ms
              Throughput: \(String(format: "%.0f", throughput)) samples/sec
            """)
        
        // Should scale reasonably (4× more samples, ~4× more time)
        XCTAssertLessThan(avgTime, 0.04, "HTJ2K cleanup should encode 64×64 in <40ms")
    }
    
    // MARK: - HTJ2K vs Legacy Comparison
    
    /// Compares HTJ2K vs legacy encoding for 32×32 code-block.
    func testHTJ2KvsLegacyEncode32x32() throws {
        let width = 32
        let height = 32
        
        // Create test coefficients
        var coefficients = [Int](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int.random(in: -64...64)
        }
        
        // Benchmark HTJ2K
        let htEncoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        var htTimes: [TimeInterval] = []
        
        for _ in 0..<warmupIterations {
            _ = try htEncoder.encodeCleanup(coefficients: coefficients, bitPlane: 6)
        }
        
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try htEncoder.encodeCleanup(coefficients: coefficients, bitPlane: 6)
            let elapsed = Date().timeIntervalSince(start)
            htTimes.append(elapsed)
        }
        
        // Benchmark Legacy
        let legacyEncoder = BitPlaneCoder(
            width: width,
            height: height,
            subband: .hh,
            options: .default
        )
        var legacyTimes: [TimeInterval] = []
        let coeffsInt32 = coefficients.map { Int32($0) }
        
        for _ in 0..<warmupIterations {
            _ = try legacyEncoder.encode(coefficients: coeffsInt32, bitDepth: 7)
        }
        
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try legacyEncoder.encode(coefficients: coeffsInt32, bitDepth: 7)
            let elapsed = Date().timeIntervalSince(start)
            legacyTimes.append(elapsed)
        }
        
        let htAvg = htTimes.reduce(0, +) / Double(htTimes.count)
        let legacyAvg = legacyTimes.reduce(0, +) / Double(legacyTimes.count)
        let speedup = legacyAvg / htAvg
        
        print("""
            
            HTJ2K vs Legacy Encode Comparison (32×32):
              HTJ2K avg: \(String(format: "%.4f", htAvg * 1000)) ms
              Legacy avg: \(String(format: "%.4f", legacyAvg * 1000)) ms
              Speedup: \(String(format: "%.2f", speedup))× faster
            """)
        
        // HTJ2K should be faster (target: 10-100× faster)
        // Note: Current implementation may not yet achieve full target speedup
        XCTAssertGreaterThan(speedup, 0.5, "HTJ2K should be competitive with legacy")
    }
    
    /// Compares HTJ2K vs legacy encoding for 64×64 code-block.
    func testHTJ2KvsLegacyEncode64x64() throws {
        let width = 64
        let height = 64
        
        var coefficients = [Int](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int.random(in: -128...128)
        }
        
        // Benchmark HTJ2K
        let htEncoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        var htTimes: [TimeInterval] = []
        
        for _ in 0..<warmupIterations {
            _ = try htEncoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)
        }
        
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try htEncoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)
            let elapsed = Date().timeIntervalSince(start)
            htTimes.append(elapsed)
        }
        
        // Benchmark Legacy
        let legacyEncoder = BitPlaneCoder(
            width: width,
            height: height,
            subband: .hh,
            options: .default
        )
        var legacyTimes: [TimeInterval] = []
        let coeffsInt32 = coefficients.map { Int32($0) }
        
        for _ in 0..<warmupIterations {
            _ = try legacyEncoder.encode(coefficients: coeffsInt32, bitDepth: 8)
        }
        
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try legacyEncoder.encode(coefficients: coeffsInt32, bitDepth: 8)
            let elapsed = Date().timeIntervalSince(start)
            legacyTimes.append(elapsed)
        }
        
        let htAvg = htTimes.reduce(0, +) / Double(htTimes.count)
        let legacyAvg = legacyTimes.reduce(0, +) / Double(legacyTimes.count)
        let speedup = legacyAvg / htAvg
        
        print("""
            
            HTJ2K vs Legacy Encode Comparison (64×64):
              HTJ2K avg: \(String(format: "%.4f", htAvg * 1000)) ms
              Legacy avg: \(String(format: "%.4f", legacyAvg * 1000)) ms
              Speedup: \(String(format: "%.2f", speedup))× faster
            """)
        
        XCTAssertGreaterThan(speedup, 0.5, "HTJ2K should be competitive with legacy")
    }
    
    // MARK: - HTJ2K Decoder Benchmarks
    
    /// Benchmarks HTJ2K cleanup pass decoding for 32×32 code-block.
    func testHTJ2KCleanupDecode32x32() throws {
        let width = 32
        let height = 32
        
        // First encode some test data
        let encoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        var coefficients = [Int](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int.random(in: -64...64)
        }
        let encoded = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 6)
        
        // Benchmark decoding
        let decoder = HTBlockDecoder(width: width, height: height, subband: .hh)
        
        // Warmup
        for _ in 0..<warmupIterations {
            _ = try decoder.decodeCleanup(from: encoded)
        }
        
        // Benchmark
        var times: [TimeInterval] = []
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try decoder.decodeCleanup(from: encoded)
            let elapsed = Date().timeIntervalSince(start)
            times.append(elapsed)
        }
        
        let avgTime = times.reduce(0, +) / Double(times.count)
        let throughput = Double(width * height) / avgTime
        
        print("""
            HTJ2K Cleanup Decode 32×32:
              Avg time: \(String(format: "%.4f", avgTime * 1000)) ms
              Throughput: \(String(format: "%.0f", throughput)) samples/sec
            """)
        
        XCTAssertLessThan(avgTime, 0.01, "HTJ2K cleanup should decode 32×32 in <10ms")
    }
    
    // MARK: - End-to-End HTJ2K Benchmarks
    
    /// Benchmarks end-to-end HTJ2K encoding for a full code-block.
    func testHTJ2KEndToEndEncode() throws {
        let config = HTJ2KConfiguration(
            codingMode: .ht,
            allowMixedMode: false,
            quality: 0.9,
            lossless: false,
            qualityLayers: 1,
            decompositionLevels: 5,
            codeBlockWidth: 64,
            codeBlockHeight: 64
        )
        
        let encoder = HTJ2KEncoder(configuration: config)
        
        // Create test coefficients for a 64×64 code-block
        var coefficients = [Int](repeating: 0, count: 64 * 64)
        for i in 0..<coefficients.count {
            coefficients[i] = Int.random(in: -128...128)
        }
        
        // Warmup
        for _ in 0..<warmupIterations {
            _ = try encoder.encodeCodeBlocks(
                coefficients: coefficients,
                width: 64,
                height: 64,
                subband: .hh
            )
        }
        
        // Benchmark
        var times: [TimeInterval] = []
        for _ in 0..<benchmarkIterations {
            let start = Date()
            _ = try encoder.encodeCodeBlocks(
                coefficients: coefficients,
                width: 64,
                height: 64,
                subband: .hh
            )
            let elapsed = Date().timeIntervalSince(start)
            times.append(elapsed)
        }
        
        let avgTime = times.reduce(0, +) / Double(times.count)
        
        print("""
            
            HTJ2K End-to-End Encode (64×64):
              Avg time: \(String(format: "%.4f", avgTime * 1000)) ms
            """)
        
        // Should complete in reasonable time
        XCTAssertLessThan(avgTime, 0.05, "HTJ2K end-to-end should encode in <50ms")
    }
    
    /// Benchmarks compression ratio of HTJ2K vs legacy.
    func testHTJ2KCompressionRatio() throws {
        let width = 64
        let height = 64
        
        var coefficients = [Int](repeating: 0, count: width * height)
        for i in 0..<coefficients.count {
            coefficients[i] = Int.random(in: -128...128)
        }
        
        // Encode with HTJ2K
        let htEncoder = HTBlockEncoder(width: width, height: height, subband: .hh)
        let htEncoded = try htEncoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)
        
        // Encode with Legacy
        let legacyEncoder = BitPlaneCoder(
            width: width,
            height: height,
            subband: .hh,
            options: .default
        )
        let coeffsInt32 = coefficients.map { Int32($0) }
        let legacyResult = try legacyEncoder.encode(coefficients: coeffsInt32, bitDepth: 8)
        
        let htSize = htEncoded.codedData.count
        let legacySize = legacyResult.data.count
        let sizeRatio = Double(htSize) / Double(legacySize)
        
        print("""
            
            Compression Ratio Comparison (64×64):
              HTJ2K size: \(htSize) bytes
              Legacy size: \(legacySize) bytes
              Size ratio: \(String(format: "%.2f", sizeRatio))
            """)
        
        // HTJ2K should have comparable compression efficiency (within 2×)
        XCTAssertLessThan(sizeRatio, 2.0, "HTJ2K should have comparable compression")
    }
}
