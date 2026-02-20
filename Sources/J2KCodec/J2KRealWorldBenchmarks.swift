//
// J2KRealWorldBenchmarks.swift
// J2KSwift
//
/// # J2KRealWorldBenchmarks
///
/// Comprehensive real-world benchmarking suite for J2KSwift.
///
/// This module provides benchmarks for realistic use cases including
/// 4K/8K images, multi-spectral imagery, HDR video frames, and batch
/// processing scenarios.

import Foundation
import J2KCore

/// Real-world benchmark suite for J2KSwift performance testing.
///
/// This suite tests performance on realistic workloads:
/// - 4K images (3840×2160, 8.3 megapixels)
/// - 8K images (7680×4320, 33.2 megapixels)
/// - Multi-spectral imagery (4-16 components)
/// - HDR video frames (10-bit, 12-bit depth)
/// - Batch processing (multiple images)
///
/// Example:
/// ```swift
/// let suite = J2KRealWorldBenchmarks()
/// let results = suite.run4KBenchmark()
/// print("4K encoding: \(results.encodingTime)s")
/// print("Throughput: \(results.throughputMBps) MB/s")
/// ```
public struct J2KRealWorldBenchmarks {
    /// Benchmark result for a single test.
    public struct Result {
        /// Test name.
        public let name: String

        /// Image dimensions.
        public let width: Int
        public let height: Int

        /// Number of components.
        public let components: Int

        /// Bit depth.
        public let bitDepth: Int

        /// Encoding time in seconds.
        public let encodingTime: TimeInterval

        /// Decoding time in seconds.
        public let decodingTime: TimeInterval

        /// Compressed data size in bytes.
        public let compressedSize: Int

        /// Uncompressed data size in bytes.
        public var uncompressedSize: Int {
            width * height * components * ((bitDepth + 7) / 8)
        }

        /// Compression ratio.
        public var compressionRatio: Double {
            guard compressedSize > 0 else { return 0 }
            return Double(uncompressedSize) / Double(compressedSize)
        }

        /// Encoding throughput in MB/s.
        public var encodingThroughputMBps: Double {
            guard encodingTime > 0 else { return 0 }
            return Double(uncompressedSize) / (1024 * 1024) / encodingTime
        }

        /// Decoding throughput in MB/s.
        public var decodingThroughputMBps: Double {
            guard decodingTime > 0 else { return 0 }
            return Double(uncompressedSize) / (1024 * 1024) / decodingTime
        }

        /// Total throughput (encode + decode) in MB/s.
        public var totalThroughputMBps: Double {
            let totalTime = encodingTime + decodingTime
            guard totalTime > 0 else { return 0 }
            return Double(uncompressedSize * 2) / (1024 * 1024) / totalTime
        }
    }

    /// Batch benchmark result.
    public struct BatchResult {
        /// Individual results.
        public let results: [Result]

        /// Total processing time.
        public let totalTime: TimeInterval

        /// Average encoding time.
        public var averageEncodingTime: TimeInterval {
            guard !results.isEmpty else { return 0 }
            return results.reduce(0) { $0 + $1.encodingTime } / Double(results.count)
        }

        /// Average decoding time.
        public var averageDecodingTime: TimeInterval {
            guard !results.isEmpty else { return 0 }
            return results.reduce(0) { $0 + $1.decodingTime } / Double(results.count)
        }

        /// Average throughput in MB/s.
        public var averageThroughputMBps: Double {
            guard !results.isEmpty else { return 0 }
            return results.reduce(0) { $0 + $1.totalThroughputMBps } / Double(results.count)
        }

        /// Total data processed in bytes.
        public var totalDataProcessed: Int {
            results.reduce(0) { $0 + $1.uncompressedSize * 2 } // encode + decode
        }

        /// Batch throughput in MB/s.
        public var batchThroughputMBps: Double {
            guard totalTime > 0 else { return 0 }
            return Double(totalDataProcessed) / (1024 * 1024) / totalTime
        }
    }

    /// Creates a new benchmark suite.
    public init() {}

    // MARK: - Image Generation

    /// Creates a test image with the specified dimensions and properties.
    private func createTestImage(
        width: Int,
        height: Int,
        components: Int = 3,
        bitDepth: Int = 8
    ) -> J2KImage {
        let pixelCount = width * height
        var imageComponents: [J2KComponent] = []

        for i in 0..<components {
            var data: [Int32] = []
            data.reserveCapacity(pixelCount)

            // Generate gradient pattern for testing
            for y in 0..<height {
                for x in 0..<width {
                    let value = ((x * 255) / width + (y * 255) / height) / 2
                    data.append(Int32(value))
                }
            }

            // Convert to Data
            let dataBytes = data.withUnsafeBytes { Data($0) }

            let component = J2KComponent(
                index: i,
                bitDepth: bitDepth,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: dataBytes
            )
            imageComponents.append(component)
        }

        return J2KImage(
            width: width,
            height: height,
            components: imageComponents
        )
    }

    // MARK: - 4K Benchmarks

    /// Runs benchmark on 4K image (3840×2160).
    ///
    /// - Parameter quality: Compression quality (default: 0.95).
    /// - Returns: Benchmark result.
    public func run4KBenchmark(quality: Double = 0.95) throws -> Result {
        let width = 3840
        let height = 2160
        let components = 3
        let bitDepth = 8

        let image = createTestImage(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth
        )

        return try benchmarkImage(
            name: "4K (3840×2160)",
            image: image,
            quality: quality
        )
    }

    /// Runs benchmark on 4K 10-bit HDR image.
    public func run4KHDR10Benchmark(quality: Double = 0.95) throws -> Result {
        let width = 3840
        let height = 2160
        let components = 3
        let bitDepth = 10

        let image = createTestImage(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth
        )

        return try benchmarkImage(
            name: "4K HDR10 (3840×2160, 10-bit)",
            image: image,
            quality: quality
        )
    }

    // MARK: - 8K Benchmarks

    /// Runs benchmark on 8K image (7680×4320).
    public func run8KBenchmark(quality: Double = 0.95) throws -> Result {
        let width = 7680
        let height = 4320
        let components = 3
        let bitDepth = 8

        let image = createTestImage(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth
        )

        return try benchmarkImage(
            name: "8K (7680×4320)",
            image: image,
            quality: quality
        )
    }

    /// Runs benchmark on 8K 12-bit HDR image.
    public func run8KHDR12Benchmark(quality: Double = 0.95) throws -> Result {
        let width = 7680
        let height = 4320
        let components = 3
        let bitDepth = 12

        let image = createTestImage(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth
        )

        return try benchmarkImage(
            name: "8K HDR12 (7680×4320, 12-bit)",
            image: image,
            quality: quality
        )
    }

    // MARK: - Multi-Spectral Benchmarks

    /// Runs benchmark on multi-spectral image (4 components).
    public func runMultiSpectral4Benchmark(quality: Double = 0.95) throws -> Result {
        let width = 2048
        let height = 2048
        let components = 4
        let bitDepth = 12

        let image = createTestImage(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth
        )

        return try benchmarkImage(
            name: "Multi-spectral 4C (2048×2048, 12-bit)",
            image: image,
            quality: quality
        )
    }

    /// Runs benchmark on multi-spectral image (8 components).
    public func runMultiSpectral8Benchmark(quality: Double = 0.95) throws -> Result {
        let width = 2048
        let height: Int = 2048
        let components = 8
        let bitDepth = 12

        let image = createTestImage(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth
        )

        return try benchmarkImage(
            name: "Multi-spectral 8C (2048×2048, 12-bit)",
            image: image,
            quality: quality
        )
    }

    /// Runs benchmark on multi-spectral image (16 components).
    public func runMultiSpectral16Benchmark(quality: Double = 0.95) throws -> Result {
        let width = 1024
        let height = 1024
        let components = 16
        let bitDepth = 12

        let image = createTestImage(
            width: width,
            height: height,
            components: components,
            bitDepth: bitDepth
        )

        return try benchmarkImage(
            name: "Multi-spectral 16C (1024×1024, 12-bit)",
            image: image,
            quality: quality
        )
    }

    // MARK: - Batch Benchmarks

    /// Runs batch benchmark on multiple Full HD images.
    public func runBatchFullHDBenchmark(
        count: Int = 10,
        quality: Double = 0.95
    ) throws -> BatchResult {
        let startTime = Date()
        var results: [Result] = []

        for i in 0..<count {
            let image = createTestImage(
                width: 1920,
                height: 1080,
                components: 3,
                bitDepth: 8
            )

            let result = try benchmarkImage(
                name: "Batch Full HD #\(i + 1)",
                image: image,
                quality: quality
            )
            results.append(result)
        }

        let totalTime = Date().timeIntervalSince(startTime)

        return BatchResult(results: results, totalTime: totalTime)
    }

    /// Runs batch benchmark on multiple 4K images.
    public func runBatch4KBenchmark(
        count: Int = 5,
        quality: Double = 0.95
    ) throws -> BatchResult {
        let startTime = Date()
        var results: [Result] = []

        for i in 0..<count {
            let image = createTestImage(
                width: 3840,
                height: 2160,
                components: 3,
                bitDepth: 8
            )

            let result = try benchmarkImage(
                name: "Batch 4K #\(i + 1)",
                image: image,
                quality: quality
            )
            results.append(result)
        }

        let totalTime = Date().timeIntervalSince(startTime)

        return BatchResult(results: results, totalTime: totalTime)
    }

    // MARK: - Core Benchmarking

    /// Benchmarks encoding and decoding of an image.
    private func benchmarkImage(
        name: String,
        image: J2KImage,
        quality: Double
    ) throws -> Result {
        // Encoding
        let encoder = J2KEncoder()
        let startEncode = Date()
        let encoded = try encoder.encode(image)
        let encodingTime = Date().timeIntervalSince(startEncode)

        // Decoding
        let decoder = J2KDecoder()
        let startDecode = Date()
        _ = try decoder.decode(encoded)
        let decodingTime = Date().timeIntervalSince(startDecode)

        // Get bit depth from first component
        let bitDepth = image.components.first?.bitDepth ?? 8

        return Result(
            name: name,
            width: image.width,
            height: image.height,
            components: image.components.count,
            bitDepth: bitDepth,
            encodingTime: encodingTime,
            decodingTime: decodingTime,
            compressedSize: encoded.count
        )
    }

    // MARK: - Full Suite

    /// Runs all benchmarks and returns results.
    public func runFullSuite(quality: Double = 0.95) throws -> [Result] {
        var results: [Result] = []

        print("Running 4K benchmark...")
        results.append(try run4KBenchmark(quality: quality))

        print("Running 4K HDR10 benchmark...")
        results.append(try run4KHDR10Benchmark(quality: quality))

        print("Running 8K benchmark...")
        results.append(try run8KBenchmark(quality: quality))

        print("Running multi-spectral 4C benchmark...")
        results.append(try runMultiSpectral4Benchmark(quality: quality))

        print("Running multi-spectral 8C benchmark...")
        results.append(try runMultiSpectral8Benchmark(quality: quality))

        return results
    }

    /// Prints a summary of benchmark results.
    public static func printSummary(_ results: [Result]) {
        print("\n═══════════════════════════════════════════════════════════")
        print("J2KSwift Real-World Benchmark Results")
        print("═══════════════════════════════════════════════════════════")

        for result in results {
            print("\n\(result.name):")
            print("  Resolution:    \(result.width)×\(result.height)")
            print("  Components:    \(result.components)")
            print("  Bit Depth:     \(result.bitDepth)")
            print("  Encoding:      \(String(format: "%.3f", result.encodingTime))s (\(String(format: "%.2f", result.encodingThroughputMBps)) MB/s)")
            print("  Decoding:      \(String(format: "%.3f", result.decodingTime))s (\(String(format: "%.2f", result.decodingThroughputMBps)) MB/s)")
            print("  Compression:   \(String(format: "%.2f", result.compressionRatio)):1")
            print("  Total:         \(String(format: "%.2f", result.totalThroughputMBps)) MB/s")
        }

        print("\n═══════════════════════════════════════════════════════════")
    }

    /// Prints a summary of batch results.
    public static func printBatchSummary(_ result: BatchResult) {
        print("\n═══════════════════════════════════════════════════════════")
        print("J2KSwift Batch Benchmark Results")
        print("═══════════════════════════════════════════════════════════")
        print("  Images:          \(result.results.count)")
        print("  Total Time:      \(String(format: "%.3f", result.totalTime))s")
        print("  Avg Encoding:    \(String(format: "%.3f", result.averageEncodingTime))s")
        print("  Avg Decoding:    \(String(format: "%.3f", result.averageDecodingTime))s")
        print("  Avg Throughput:  \(String(format: "%.2f", result.averageThroughputMBps)) MB/s")
        print("  Batch Throughput:\(String(format: "%.2f", result.batchThroughputMBps)) MB/s")
        print("═══════════════════════════════════════════════════════════")
    }
}
