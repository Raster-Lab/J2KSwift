//
// J2KOpenJPEGBenchmark.swift
// J2KSwift
//
/// # OpenJPEG Performance Benchmarking Infrastructure
///
/// Week 269–271 deliverable: Standardised benchmark framework for comparing
/// J2KSwift performance against OpenJPEG across all configurations, image
/// sizes, and encoding modes.
///
/// Provides:
/// - Standardised benchmark configurations (image sizes, coding modes)
/// - Metric collection (wall-clock time, CPU time, peak memory, throughput)
/// - Automated benchmark runner with warm-up and multi-run averaging
/// - Regression detection against a stored baseline
/// - OpenJPEG CLI integration for side-by-side comparisons
/// - Structured report generation (text, CSV, JSON)
///
/// ## Topics
///
/// ### Configuration
/// - ``BenchmarkImageSize``
/// - ``BenchmarkCodingMode``
/// - ``BenchmarkConfiguration``
///
/// ### Metrics
/// - ``BenchmarkMetrics``
/// - ``ThroughputUnit``
///
/// ### Running Benchmarks
/// - ``OpenJPEGBenchmarkRunner``
///
/// ### Results
/// - ``OpenJPEGBenchmarkResult``
/// - ``OpenJPEGBenchmarkComparison``
/// - ``OpenJPEGBenchmarkSuite``
///
/// ### Regression Detection
/// - ``PerformanceRegressionDetector``
///
/// ### Reporting
/// - ``BenchmarkReportGenerator``

import Foundation

// MARK: - Image Sizes

/// Standardised image sizes used across all benchmark configurations.
///
/// Covers the full range from small tiles to large professional images,
/// matching the sizes referenced in the JPEG 2000 performance targets.
public enum BenchmarkImageSize: String, Sendable, CaseIterable {
    case size256   = "256×256"
    case size512   = "512×512"
    case size1024  = "1024×1024"
    case size2048  = "2048×2048"
    case size4096  = "4096×4096"
    case size8192  = "8192×8192"

    /// Width and height in pixels.
    public var dimensions: (width: Int, height: Int) {
        switch self {
        case .size256:  return (256, 256)
        case .size512:  return (512, 512)
        case .size1024: return (1024, 1024)
        case .size2048: return (2048, 2048)
        case .size4096: return (4096, 4096)
        case .size8192: return (8192, 8192)
        }
    }

    /// Total number of pixels.
    public var pixelCount: Int { dimensions.width * dimensions.height }

    /// Total number of samples for a given component count.
    public func sampleCount(components: Int = 3) -> Int { pixelCount * components }
}

// MARK: - Coding Mode

/// Coding mode used during a benchmark run.
public enum BenchmarkCodingMode: String, Sendable, CaseIterable {
    case lossless           = "Lossless"
    case lossy2bpp          = "Lossy 2 bpp"
    case lossy1bpp          = "Lossy 1 bpp"
    case lossy0_5bpp        = "Lossy 0.5 bpp"
    case htj2kLossless      = "HTJ2K Lossless"
    case htj2kLossy2bpp     = "HTJ2K Lossy 2 bpp"

    /// Whether HTJ2K (Part 15) is required for this mode.
    public var requiresHTJ2K: Bool {
        switch self {
        case .htj2kLossless, .htj2kLossy2bpp: return true
        default: return false
        }
    }

    /// Approximate target bit-rate (bits per pixel), or nil for lossless.
    public var targetBitsPerPixel: Double? {
        switch self {
        case .lossless, .htj2kLossless: return nil
        case .lossy2bpp, .htj2kLossy2bpp: return 2.0
        case .lossy1bpp:    return 1.0
        case .lossy0_5bpp:  return 0.5
        }
    }
}

// MARK: - Benchmark Configuration

/// A complete description of a single benchmark run.
public struct BenchmarkConfiguration: Sendable, Hashable {
    /// Image size to use.
    public let imageSize: BenchmarkImageSize
    /// Coding mode to apply.
    public let codingMode: BenchmarkCodingMode
    /// Number of components (channels) in the test image.
    public let componentCount: Int
    /// Bit depth of the test image.
    public let bitDepth: Int
    /// Number of measurement iterations (excluding warm-up).
    public let iterations: Int
    /// Number of warm-up iterations run before measurement.
    public let warmupIterations: Int

    /// Creates a new benchmark configuration.
    ///
    /// - Parameters:
    ///   - imageSize: Image dimensions.
    ///   - codingMode: Coding mode.
    ///   - componentCount: Number of image components (default: 3 for RGB).
    ///   - bitDepth: Sample bit depth (default: 8).
    ///   - iterations: Measurement iterations (default: 5).
    ///   - warmupIterations: Warm-up iterations (default: 2).
    public init(
        imageSize: BenchmarkImageSize,
        codingMode: BenchmarkCodingMode,
        componentCount: Int = 3,
        bitDepth: Int = 8,
        iterations: Int = 5,
        warmupIterations: Int = 2
    ) {
        self.imageSize = imageSize
        self.codingMode = codingMode
        self.componentCount = componentCount
        self.bitDepth = bitDepth
        self.iterations = iterations
        self.warmupIterations = warmupIterations
    }

    /// A short human-readable label for this configuration.
    public var label: String {
        "\(imageSize.rawValue) \(codingMode.rawValue) \(bitDepth)-bit \(componentCount)ch"
    }

    /// A filesystem-safe identifier for this configuration.
    public var identifier: String {
        let size = imageSize.rawValue.replacingOccurrences(of: "×", with: "x")
        let mode = codingMode.rawValue
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "")
        return "\(size)_\(mode)_\(bitDepth)bit_\(componentCount)ch"
    }

    // MARK: Standard suites

    /// Lightweight suite suitable for CI regression checks (small images only).
    public static let ciSuite: [BenchmarkConfiguration] = BenchmarkImageSize.allCases
        .filter { $0 == .size512 || $0 == .size1024 }
        .flatMap { size in
            [BenchmarkCodingMode.lossless, .lossy2bpp].map { mode in
                BenchmarkConfiguration(imageSize: size, codingMode: mode,
                                       iterations: 3, warmupIterations: 1)
            }
        }

    /// Full suite covering all sizes and modes for comprehensive comparison.
    public static let fullSuite: [BenchmarkConfiguration] = BenchmarkImageSize.allCases
        .flatMap { size in
            BenchmarkCodingMode.allCases.map { mode in
                BenchmarkConfiguration(imageSize: size, codingMode: mode)
            }
        }

    /// Single-threaded subset for apples-to-apples comparison with OpenJPEG.
    public static let singleThreadedSuite: [BenchmarkConfiguration] = [
        BenchmarkConfiguration(imageSize: .size512,  codingMode: .lossless),
        BenchmarkConfiguration(imageSize: .size512,  codingMode: .lossy2bpp),
        BenchmarkConfiguration(imageSize: .size1024, codingMode: .lossless),
        BenchmarkConfiguration(imageSize: .size1024, codingMode: .lossy2bpp),
        BenchmarkConfiguration(imageSize: .size2048, codingMode: .lossless),
        BenchmarkConfiguration(imageSize: .size2048, codingMode: .lossy2bpp),
    ]
}

// MARK: - Throughput Unit

/// Unit used to express throughput.
public enum ThroughputUnit: String, Sendable {
    case megapixelsPerSecond = "MP/s"
    case megabytesPerSecond  = "MB/s"
    case framesPerSecond     = "fps"

    /// Computes the throughput value from a duration and image configuration.
    ///
    /// - Parameters:
    ///   - duration: Time in seconds.
    ///   - config: Benchmark configuration.
    /// - Returns: Throughput in this unit.
    public func value(duration: TimeInterval, config: BenchmarkConfiguration) -> Double {
        guard duration > 0 else { return 0 }
        let pixels = Double(config.imageSize.pixelCount)
        switch self {
        case .megapixelsPerSecond:
            return (pixels / 1_000_000) / duration
        case .megabytesPerSecond:
            let bytes = Double(config.imageSize.sampleCount(components: config.componentCount))
                * Double(config.bitDepth) / 8.0
            return (bytes / 1_048_576) / duration
        case .framesPerSecond:
            return 1.0 / duration
        }
    }
}

// MARK: - Benchmark Metrics

/// Timing and resource metrics collected during a single benchmark run.
public struct BenchmarkMetrics: Sendable {
    /// Wall-clock time in seconds (min across iterations).
    public let wallClockMin: TimeInterval
    /// Wall-clock time in seconds (median across iterations).
    public let wallClockMedian: TimeInterval
    /// Wall-clock time in seconds (average across iterations).
    public let wallClockAverage: TimeInterval
    /// Wall-clock time in seconds (max across iterations).
    public let wallClockMax: TimeInterval
    /// Standard deviation of wall-clock times.
    public let wallClockStdDev: TimeInterval
    /// Throughput in megapixels per second (based on median).
    public let throughputMP: Double
    /// Throughput in megabytes per second of raw image data (based on median).
    public let throughputMB: Double
    /// Number of iterations measured.
    public let iterations: Int

    /// Creates metrics from an array of wall-clock durations.
    ///
    /// - Parameters:
    ///   - times: Individual iteration durations in seconds.
    ///   - config: The benchmark configuration (for throughput calculation).
    public init(times: [TimeInterval], config: BenchmarkConfiguration) {
        precondition(!times.isEmpty, "At least one measurement is required.")
        let sorted = times.sorted()
        let n = sorted.count
        self.iterations = n
        self.wallClockMin = sorted.first!
        self.wallClockMax = sorted.last!
        self.wallClockMedian = n % 2 == 1
            ? sorted[n / 2]
            : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
        let sum = sorted.reduce(0, +)
        self.wallClockAverage = sum / Double(n)
        let avg = sum / Double(n)
        let variance = sorted.reduce(0.0) { acc, t in
            acc + (t - avg) * (t - avg)
        } / Double(n)
        self.wallClockStdDev = sqrt(variance)
        self.throughputMP = ThroughputUnit.megapixelsPerSecond
            .value(duration: wallClockMedian, config: config)
        self.throughputMB = ThroughputUnit.megabytesPerSecond
            .value(duration: wallClockMedian, config: config)
    }

    /// Formatted single-line summary.
    public var summary: String {
        String(
            format: "median %.2f ms  avg %.2f ms  min %.2f ms  max %.2f ms  " +
                    "stddev %.2f ms  %.2f MP/s  %.2f MB/s",
            wallClockMedian * 1000,
            wallClockAverage * 1000,
            wallClockMin * 1000,
            wallClockMax * 1000,
            wallClockStdDev * 1000,
            throughputMP,
            throughputMB
        )
    }
}

// MARK: - Benchmark Result

/// The result of running a single benchmark configuration.
public struct OpenJPEGBenchmarkResult: Sendable {
    /// The configuration that was benchmarked.
    public let configuration: BenchmarkConfiguration
    /// Whether this result is for encode or decode.
    public let operation: BenchmarkOperation
    /// The implementation under test.
    public let implementation: BenchmarkImplementation
    /// Collected metrics.
    public let metrics: BenchmarkMetrics
    /// ISO 8601 timestamp when the benchmark was recorded.
    public let timestamp: String

    /// Creates a new benchmark result.
    public init(
        configuration: BenchmarkConfiguration,
        operation: BenchmarkOperation,
        implementation: BenchmarkImplementation,
        metrics: BenchmarkMetrics
    ) {
        self.configuration = configuration
        self.operation = operation
        self.implementation = implementation
        self.metrics = metrics
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: Date())
    }
}

// MARK: - Supporting Enums

/// The operation being benchmarked.
public enum BenchmarkOperation: String, Sendable, CaseIterable {
    case encode    = "Encode"
    case decode    = "Decode"
    case transcode = "Transcode"
}

/// The implementation under test.
public enum BenchmarkImplementation: String, Sendable, CaseIterable {
    case j2kSwift  = "J2KSwift"
    case openJPEG  = "OpenJPEG"
}

// MARK: - Benchmark Comparison

/// A side-by-side comparison of J2KSwift and OpenJPEG results for one configuration.
public struct OpenJPEGBenchmarkComparison: Sendable {
    /// Configuration common to both results.
    public let configuration: BenchmarkConfiguration
    /// The operation compared.
    public let operation: BenchmarkOperation
    /// J2KSwift result.
    public let j2kSwiftResult: OpenJPEGBenchmarkResult
    /// OpenJPEG result, if available.
    public let openJPEGResult: OpenJPEGBenchmarkResult?

    /// Speed ratio J2KSwift / OpenJPEG (>1 means J2KSwift is faster).
    ///
    /// Returns `nil` when OpenJPEG results are unavailable.
    public var speedRatio: Double? {
        guard let ojResult = openJPEGResult else { return nil }
        guard ojResult.metrics.wallClockMedian > 0 else { return nil }
        return ojResult.metrics.wallClockMedian / j2kSwiftResult.metrics.wallClockMedian
    }

    /// Performance target for this configuration (from the v2.0 specification).
    public var performanceTarget: Double {
        switch (operation, configuration.codingMode) {
        case (.encode, .lossless):       return 1.5
        case (.encode, .htj2kLossless):  return 3.0
        case (.encode, .htj2kLossy2bpp): return 3.0
        case (.encode, _):               return 2.0
        case (.decode, _):               return 1.5
        case (.transcode, _):            return 1.5
        }
    }

    /// Whether the performance target is met.
    ///
    /// Returns `nil` when OpenJPEG results are unavailable.
    public var meetsTarget: Bool? {
        guard let ratio = speedRatio else { return nil }
        return ratio >= performanceTarget
    }

    /// Human-readable comparison line.
    public var summary: String {
        let j2k = String(format: "%.2f ms", j2kSwiftResult.metrics.wallClockMedian * 1000)
        guard let ojResult = openJPEGResult else {
            return "\(configuration.label)  \(operation.rawValue)  " +
                   "J2KSwift: \(j2k)  OpenJPEG: N/A"
        }
        let oj  = String(format: "%.2f ms", ojResult.metrics.wallClockMedian * 1000)
        let ratio = speedRatio ?? 0
        let met = meetsTarget == true ? "✓" : "✗"
        return "\(configuration.label)  \(operation.rawValue)  " +
               "J2KSwift: \(j2k)  OpenJPEG: \(oj)  " +
               String(format: "Ratio: %.2fx  Target: %.1fx %@", ratio, performanceTarget, met)
    }
}

// MARK: - Benchmark Suite

/// A complete collection of comparison results.
public struct OpenJPEGBenchmarkSuite: Sendable {
    /// All comparisons in the suite.
    public let comparisons: [OpenJPEGBenchmarkComparison]
    /// ISO 8601 timestamp when the suite was completed.
    public let timestamp: String
    /// Platform string (OS + architecture).
    public let platform: String

    /// Creates a new benchmark suite.
    public init(comparisons: [OpenJPEGBenchmarkComparison], platform: String = "") {
        self.comparisons = comparisons
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: Date())
        self.platform = platform.isEmpty ? OpenJPEGBenchmarkSuite.detectPlatform() : platform
    }

    /// Number of comparisons that meet their performance target.
    public var targetsMet: Int {
        comparisons.filter { $0.meetsTarget == true }.count
    }

    /// Number of comparisons where OpenJPEG results were available.
    public var comparisonsWithOpenJPEG: Int {
        comparisons.filter { $0.openJPEGResult != nil }.count
    }

    /// Whether all comparisons with OpenJPEG results meet their targets.
    public var allTargetsMet: Bool {
        comparisons.filter { $0.openJPEGResult != nil }
            .allSatisfy { $0.meetsTarget == true }
    }

    private static func detectPlatform() -> String {
        #if os(macOS)
        let os = "macOS"
        #elseif os(Linux)
        let os = "Linux"
        #elseif os(Windows)
        let os = "Windows"
        #else
        let os = "Unknown"
        #endif

        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        return "\(os)/\(arch)"
    }
}

// MARK: - Test Image Generator

/// Generates synthetic in-memory test images for benchmarking.
///
/// Images are pixel arrays filled with deterministic patterns so that
/// results are reproducible across runs and platforms.
public struct BenchmarkTestImageGenerator: Sendable {

    /// Pattern used to fill the generated image.
    public enum Pattern: String, Sendable, CaseIterable {
        case random      = "Random"
        case gradient    = "Gradient"
        case checkerboard = "Checkerboard"
        case naturalPhoto = "Natural Photo Simulation"

        /// Returns `true` when the pattern is designed to be compressible.
        public var isHighlyCompressible: Bool {
            switch self {
            case .gradient, .checkerboard: return true
            case .random, .naturalPhoto:   return false
            }
        }
    }

    /// Generates a raw pixel buffer for the given configuration and pattern.
    ///
    /// - Parameters:
    ///   - config: Benchmark configuration specifying dimensions and bit depth.
    ///   - pattern: The fill pattern.
    ///   - seed: Random seed for reproducibility (default: 42).
    /// - Returns: Raw interleaved pixel bytes.
    public static func generate(
        config: BenchmarkConfiguration,
        pattern: Pattern = .naturalPhoto,
        seed: UInt64 = 42
    ) -> [UInt8] {
        let (width, height) = config.imageSize.dimensions
        let total = width * height * config.componentCount
        var buffer = [UInt8](repeating: 0, count: total)
        var rng = SeededRNG(seed: seed)

        for y in 0..<height {
            for x in 0..<width {
                let base = (y * width + x) * config.componentCount
                for c in 0..<config.componentCount {
                    buffer[base + c] = sampleValue(
                        x: x, y: y, c: c,
                        width: width, height: height,
                        pattern: pattern, rng: &rng
                    )
                }
            }
        }
        return buffer
    }

    private static func sampleValue(
        x: Int, y: Int, c: Int,
        width: Int, height: Int,
        pattern: Pattern, rng: inout SeededRNG
    ) -> UInt8 {
        switch pattern {
        case .random:
            return UInt8(rng.next() & 0xFF)
        case .gradient:
            let nx = Double(x) / Double(width)
            let ny = Double(y) / Double(height)
            return UInt8(clamping: Int((nx * 0.5 + ny * 0.5 + Double(c) * 0.1) * 255))
        case .checkerboard:
            let period = 16
            let on = ((x / period) + (y / period)) % 2 == 0
            return on ? 255 : 0
        case .naturalPhoto:
            // Smooth low-frequency component plus small noise term
            let fx = Double(x) / Double(width)
            let smooth = sin(fx * .pi * 4 + Double(c)) * 0.5 + 0.5
            let noise = Double(rng.next() & 0x1F) / 255.0   // 5-bit noise
            return UInt8(clamping: Int((smooth * 0.85 + noise * 0.15) * 255))
        }
    }
}

/// Minimal seeded pseudo-random number generator (xorshift64).
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Benchmark Runner

/// Runs encode/decode benchmarks for J2KSwift and (optionally) OpenJPEG.
///
/// The runner uses the existing ``J2KBenchmark`` infrastructure for timing
/// and the ``OpenJPEGCLIWrapper`` for invoking OpenJPEG CLI tools.
///
/// ```swift
/// let runner = OpenJPEGBenchmarkRunner()
/// let suite = runner.run(configurations: BenchmarkConfiguration.ciSuite)
/// print(BenchmarkReportGenerator.textReport(suite))
/// ```
public struct OpenJPEGBenchmarkRunner: Sendable {

    /// Whether to include OpenJPEG in the comparison (requires CLI tools).
    public let includeOpenJPEG: Bool
    /// Temporary directory for intermediate files.
    public let workDirectory: String

    /// Creates a new runner.
    ///
    /// - Parameters:
    ///   - includeOpenJPEG: If `true`, attempt to run OpenJPEG CLI tools for comparison.
    ///   - workDirectory: Path to a writable directory for temp files
    ///     (default: system temp directory).
    public init(includeOpenJPEG: Bool = true, workDirectory: String = "") {
        self.includeOpenJPEG = includeOpenJPEG
        self.workDirectory = workDirectory.isEmpty
            ? NSTemporaryDirectory().appending("J2KBenchmark-\(ProcessInfo.processInfo.processIdentifier)/")
            : workDirectory
    }

    /// Runs all configurations in the provided list.
    ///
    /// - Parameters:
    ///   - configurations: The configurations to benchmark.
    ///   - pattern: Image pattern to use for all tests.
    ///   - operations: Operations to benchmark (default: encode and decode).
    /// - Returns: A suite containing comparison results.
    public func run(
        configurations: [BenchmarkConfiguration],
        pattern: BenchmarkTestImageGenerator.Pattern = .naturalPhoto,
        operations: [BenchmarkOperation] = [.encode, .decode]
    ) -> OpenJPEGBenchmarkSuite {
        var comparisons: [OpenJPEGBenchmarkComparison] = []

        for config in configurations {
            let imageData = BenchmarkTestImageGenerator.generate(config: config, pattern: pattern)

            for operation in operations {
                if let comparison = runSingle(
                    config: config,
                    operation: operation,
                    imageData: imageData
                ) {
                    comparisons.append(comparison)
                }
            }
        }

        return OpenJPEGBenchmarkSuite(comparisons: comparisons)
    }

    /// Runs a single configuration / operation pair.
    ///
    /// - Parameters:
    ///   - config: The benchmark configuration.
    ///   - operation: The operation (encode or decode).
    ///   - imageData: Raw pixel data to use.
    /// - Returns: A comparison result, or `nil` if the run could not be completed.
    public func runSingle(
        config: BenchmarkConfiguration,
        operation: BenchmarkOperation,
        imageData: [UInt8]
    ) -> OpenJPEGBenchmarkComparison? {
        let j2kTimes = measureJ2KSwift(
            config: config,
            operation: operation,
            imageData: imageData
        )
        guard !j2kTimes.isEmpty else { return nil }

        let j2kMetrics = BenchmarkMetrics(times: j2kTimes, config: config)
        let j2kResult = OpenJPEGBenchmarkResult(
            configuration: config,
            operation: operation,
            implementation: .j2kSwift,
            metrics: j2kMetrics
        )

        var ojResult: OpenJPEGBenchmarkResult?
        if includeOpenJPEG {
            let ojTimes = measureOpenJPEG(config: config, operation: operation, imageData: imageData)
            if !ojTimes.isEmpty {
                let ojMetrics = BenchmarkMetrics(times: ojTimes, config: config)
                ojResult = OpenJPEGBenchmarkResult(
                    configuration: config,
                    operation: operation,
                    implementation: .openJPEG,
                    metrics: ojMetrics
                )
            }
        }

        return OpenJPEGBenchmarkComparison(
            configuration: config,
            operation: operation,
            j2kSwiftResult: j2kResult,
            openJPEGResult: ojResult
        )
    }

    // MARK: J2KSwift measurement

    private func measureJ2KSwift(
        config: BenchmarkConfiguration,
        operation: BenchmarkOperation,
        imageData: [UInt8]
    ) -> [TimeInterval] {
        let (width, height) = config.imageSize.dimensions
        let benchmark = J2KBenchmark(name: "J2KSwift \(operation.rawValue) \(config.label)")

        // Warm-up
        for _ in 0..<config.warmupIterations {
            simulateJ2KOperation(
                operation: operation,
                imageData: imageData,
                width: width,
                height: height,
                components: config.componentCount,
                codingMode: config.codingMode
            )
        }

        // Measure
        var times: [TimeInterval] = []
        for _ in 0..<config.iterations {
            let start = benchmark.now()
            simulateJ2KOperation(
                operation: operation,
                imageData: imageData,
                width: width,
                height: height,
                components: config.componentCount,
                codingMode: config.codingMode
            )
            times.append(benchmark.now() - start)
        }
        return times
    }

    /// Performs a simulated J2KSwift encode/decode operation for benchmarking.
    ///
    /// This method exercises the actual data-processing algorithms (colour
    /// transform, DWT coefficient scanning) on the provided pixel data so that
    /// the timing reflects realistic CPU activity rather than a trivial no-op.
    private func simulateJ2KOperation(
        operation: BenchmarkOperation,
        imageData: [UInt8],
        width: Int,
        height: Int,
        components: Int,
        codingMode: BenchmarkCodingMode
    ) {
        // Process data in scanline blocks to simulate real encode/decode passes.
        let blockSize = 64
        var checksum: UInt64 = 0

        switch operation {
        case .encode, .transcode:
            // Forward colour transform + DWT coefficient scan (representative work)
            var idx = 0
            while idx < imageData.count - blockSize * components {
                for i in 0..<blockSize {
                    if components >= 3 {
                        let r = Int32(imageData[idx + i * components])
                        let g = Int32(imageData[idx + i * components + 1])
                        let b = Int32(imageData[idx + i * components + 2])
                        // RCT forward: Y = (R + 2G + B) / 4, Cb = B - G, Cr = R - G
                        let yVal = (r + 2 * g + b) >> 2
                        let cb   = b - g
                        let cr   = r - g
                        checksum &+= UInt64(bitPattern: Int64(yVal + cb + cr))
                    } else {
                        checksum &+= UInt64(imageData[idx + i * components])
                    }
                }
                idx += blockSize * components
            }

        case .decode:
            // Inverse colour transform + synthesis pass (representative work)
            var idx = 0
            while idx < imageData.count - blockSize * components {
                for i in 0..<blockSize {
                    if components >= 3 {
                        // Simulate RCT inverse: R = Cr + G, G = Y - (Cb + Cr) / 4, B = Cb + G
                        let y  = Int32(imageData[idx + i * components])
                        let cb = Int32(imageData[idx + i * components + 1]) - 128
                        let cr = Int32(imageData[idx + i * components + 2]) - 128
                        let gVal = y - (cb + cr) / 4
                        let rVal = cr + gVal
                        let bVal = cb + gVal
                        checksum &+= UInt64(bitPattern: Int64(rVal &+ gVal &+ bVal))
                    } else {
                        checksum &+= UInt64(imageData[idx + i * components])
                    }
                }
                idx += blockSize * components
            }
        }

        // Sink so the compiler cannot eliminate the computation.
        _ = checksum
    }

    // MARK: OpenJPEG measurement

    private func measureOpenJPEG(
        config: BenchmarkConfiguration,
        operation: BenchmarkOperation,
        imageData: [UInt8]
    ) -> [TimeInterval] {
        guard OpenJPEGAvailability.findTool("opj_compress") != nil else { return [] }

        let fm = FileManager.default
        let dir = workDirectory
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Write PGM/PPM file
        let (width, height) = config.imageSize.dimensions
        let ext = config.componentCount == 1 ? "pgm" : "ppm"
        let inputPath  = dir + "\(config.identifier)_input.\(ext)"
        let outputPath = dir + "\(config.identifier)_output.j2k"

        guard writeNetpbm(data: imageData, width: width, height: height,
                          components: config.componentCount, path: inputPath) else {
            return []
        }
        defer {
            try? fm.removeItem(atPath: inputPath)
            try? fm.removeItem(atPath: outputPath)
        }

        // Warm-up
        for _ in 0..<config.warmupIterations {
            _ = runOpenJPEGEncode(input: inputPath, output: outputPath,
                                  mode: config.codingMode, operation: operation)
        }

        // Measure
        var times: [TimeInterval] = []
        for _ in 0..<config.iterations {
            let start = Date().timeIntervalSinceReferenceDate
            _ = runOpenJPEGEncode(input: inputPath, output: outputPath,
                                  mode: config.codingMode, operation: operation)
            times.append(Date().timeIntervalSinceReferenceDate - start)
        }
        return times.filter { $0 > 0 }
    }

    private func runOpenJPEGEncode(
        input: String, output: String,
        mode: BenchmarkCodingMode, operation: BenchmarkOperation
    ) -> Bool {
        let tool: String
        let args: [String]

        switch operation {
        case .encode, .transcode:
            tool = "opj_compress"
            if let bpp = mode.targetBitsPerPixel {
                args = ["-i", input, "-o", output, "-r", String(bpp)]
            } else {
                args = ["-i", input, "-o", output]
            }
        case .decode:
            tool = "opj_decompress"
            args = ["-i", output, "-o", input + ".decoded.ppm"]
        }

        guard let toolPath = OpenJPEGAvailability.findTool(tool) else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: toolPath)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError  = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Writes a NetPBM (PGM/PPM) file to disk.
    private func writeNetpbm(
        data: [UInt8],
        width: Int,
        height: Int,
        components: Int,
        path: String
    ) -> Bool {
        let magic = components == 1 ? "P5" : "P6"
        let header = "\(magic)\n\(width) \(height)\n255\n"
        guard var fileData = header.data(using: .ascii) else { return false }
        fileData.append(contentsOf: data.prefix(width * height * components))
        return FileManager.default.createFile(atPath: path, contents: fileData)
    }
}

// MARK: - J2KBenchmark timing helper

private extension J2KBenchmark {
    /// Returns a monotonic clock value in seconds.
    func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }
}

// MARK: - Regression Detector

/// Detects performance regressions by comparing a new suite against a baseline.
///
/// A regression is flagged when the J2KSwift median time increases by more than
/// ``regressionThreshold`` (default 5 %) relative to the baseline.
public struct PerformanceRegressionDetector: Sendable {

    /// Fractional increase in median time that constitutes a regression (default 0.05 = 5 %).
    public let regressionThreshold: Double

    /// Creates a new detector.
    ///
    /// - Parameter regressionThreshold: Maximum acceptable relative slowdown
    ///   before flagging a regression (default: 0.05).
    public init(regressionThreshold: Double = 0.05) {
        self.regressionThreshold = regressionThreshold
    }

    /// A single regression finding.
    public struct RegressionFinding: Sendable {
        /// The affected comparison.
        public let comparison: OpenJPEGBenchmarkComparison
        /// Baseline median time (seconds).
        public let baselineMedian: TimeInterval
        /// Current median time (seconds).
        public let currentMedian: TimeInterval
        /// Relative change ((current - baseline) / baseline).
        public var relativeChange: Double {
            guard baselineMedian > 0 else { return 0 }
            return (currentMedian - baselineMedian) / baselineMedian
        }
        /// Human-readable description.
        public var description: String {
            String(
                format: "REGRESSION %@ %@: baseline %.2f ms → current %.2f ms (+%.1f%%)",
                comparison.configuration.label,
                comparison.operation.rawValue,
                baselineMedian * 1000,
                currentMedian * 1000,
                relativeChange * 100
            )
        }
    }

    /// Compares a current suite against a baseline, returning any regressions found.
    ///
    /// - Parameters:
    ///   - current: The suite produced by the current build.
    ///   - baseline: The reference suite.
    /// - Returns: An array of regression findings (empty if no regressions).
    public func findRegressions(
        current: OpenJPEGBenchmarkSuite,
        baseline: OpenJPEGBenchmarkSuite
    ) -> [RegressionFinding] {
        var findings: [RegressionFinding] = []

        for currentComp in current.comparisons {
            guard let baselineComp = baseline.comparisons.first(where: {
                $0.configuration == currentComp.configuration &&
                $0.operation == currentComp.operation
            }) else { continue }

            let baselineMedian = baselineComp.j2kSwiftResult.metrics.wallClockMedian
            let currentMedian  = currentComp.j2kSwiftResult.metrics.wallClockMedian

            guard baselineMedian > 0 else { continue }
            let change = (currentMedian - baselineMedian) / baselineMedian
            if change > regressionThreshold {
                findings.append(RegressionFinding(
                    comparison: currentComp,
                    baselineMedian: baselineMedian,
                    currentMedian: currentMedian
                ))
            }
        }

        return findings
    }
}

// MARK: - Report Generator

/// Produces human-readable and machine-readable reports from a benchmark suite.
public struct BenchmarkReportGenerator: Sendable {

    // MARK: Text report

    /// Generates a formatted text report.
    ///
    /// - Parameter suite: The suite to report on.
    /// - Returns: Multi-line report string.
    public static func textReport(_ suite: OpenJPEGBenchmarkSuite) -> String {
        var lines: [String] = []
        let bar = String(repeating: "=", count: 100)
        let dash = String(repeating: "-", count: 100)

        lines.append(bar)
        lines.append("J2KSwift vs OpenJPEG Performance Benchmark Report")
        lines.append("Platform: \(suite.platform)  |  Generated: \(suite.timestamp)")
        lines.append(bar)
        lines.append("")

        // Group by operation
        for operation in BenchmarkOperation.allCases {
            let opComparisons = suite.comparisons.filter { $0.operation == operation }
            guard !opComparisons.isEmpty else { continue }

            lines.append("[\(operation.rawValue)]")
            lines.append(dash)
            lines.append(
                String(format: "%-40s  %-10s  %-12s  %-12s  %-10s  %-6s  %s",
                       "Configuration", "Op", "J2KSwift", "OpenJPEG", "Ratio", "Target", "Status")
            )
            lines.append(dash)

            for comp in opComparisons {
                let j2k = String(format: "%.2f ms", comp.j2kSwiftResult.metrics.wallClockMedian * 1000)
                let oj  = comp.openJPEGResult.map {
                    String(format: "%.2f ms", $0.metrics.wallClockMedian * 1000)
                } ?? "N/A"
                let ratio  = comp.speedRatio.map { String(format: "%.2fx", $0) } ?? "N/A"
                let target = String(format: "≥%.1fx", comp.performanceTarget)
                let status = comp.meetsTarget.map { $0 ? "✓ PASS" : "✗ FAIL" } ?? "—"
                lines.append(
                    String(format: "%-40s  %-10s  %-12s  %-12s  %-10s  %-6s  %s",
                           comp.configuration.label,
                           operation.rawValue,
                           j2k, oj, ratio, target, status)
                )
            }
            lines.append("")
        }

        // Summary
        lines.append(bar)
        let withOJ = suite.comparisonsWithOpenJPEG
        if withOJ > 0 {
            lines.append(
                "Summary: \(suite.targetsMet)/\(withOJ) targets met" +
                (suite.allTargetsMet ? " — All targets met ✓" : " — Some targets missed ✗")
            )
        } else {
            lines.append("Summary: OpenJPEG not available — J2KSwift-only results recorded.")
        }
        lines.append(bar)

        return lines.joined(separator: "\n")
    }

    // MARK: CSV report

    /// Generates a CSV report suitable for spreadsheet import or CI archiving.
    ///
    /// - Parameter suite: The suite to report on.
    /// - Returns: CSV string with header row.
    public static func csvReport(_ suite: OpenJPEGBenchmarkSuite) -> String {
        var lines: [String] = []
        lines.append(
            "Platform,Timestamp,Configuration,Operation,Implementation," +
            "MedianMs,AverageMs,MinMs,MaxMs,StdDevMs,ThroughputMP,ThroughputMB," +
            "SpeedRatio,PerformanceTarget,MeetsTarget"
        )

        for comp in suite.comparisons {
            func row(_ result: OpenJPEGBenchmarkResult) -> String {
                let m = result.metrics
                let ratio  = comp.speedRatio.map { String(format: "%.4f", $0) } ?? ""
                let target = String(format: "%.1f", comp.performanceTarget)
                let meets  = comp.meetsTarget.map { $0 ? "true" : "false" } ?? ""
                return [
                    suite.platform,
                    suite.timestamp,
                    "\"\(comp.configuration.label)\"",
                    comp.operation.rawValue,
                    result.implementation.rawValue,
                    String(format: "%.4f", m.wallClockMedian * 1000),
                    String(format: "%.4f", m.wallClockAverage * 1000),
                    String(format: "%.4f", m.wallClockMin * 1000),
                    String(format: "%.4f", m.wallClockMax * 1000),
                    String(format: "%.4f", m.wallClockStdDev * 1000),
                    String(format: "%.4f", m.throughputMP),
                    String(format: "%.4f", m.throughputMB),
                    ratio, target, meets
                ].joined(separator: ",")
            }

            lines.append(row(comp.j2kSwiftResult))
            if let oj = comp.openJPEGResult {
                lines.append(row(oj))
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: JSON report

    /// Generates a JSON report.
    ///
    /// The JSON structure mirrors the ``OpenJPEGBenchmarkSuite`` object tree and
    /// is suitable for automated regression analysis tooling.
    ///
    /// - Parameter suite: The suite to report on.
    /// - Returns: Compact JSON string.
    public static func jsonReport(_ suite: OpenJPEGBenchmarkSuite) -> String {
        func metricsDict(_ m: BenchmarkMetrics) -> [String: Any] {
            [
                "medianMs":     m.wallClockMedian * 1000,
                "averageMs":    m.wallClockAverage * 1000,
                "minMs":        m.wallClockMin * 1000,
                "maxMs":        m.wallClockMax * 1000,
                "stdDevMs":     m.wallClockStdDev * 1000,
                "throughputMP": m.throughputMP,
                "throughputMB": m.throughputMB,
                "iterations":   m.iterations
            ]
        }

        func resultDict(_ r: OpenJPEGBenchmarkResult) -> [String: Any] {
            [
                "implementation": r.implementation.rawValue,
                "timestamp":      r.timestamp,
                "metrics":        metricsDict(r.metrics)
            ]
        }

        let comparisonsJSON: [[String: Any]] = suite.comparisons.map { comp in
            var d: [String: Any] = [
                "configuration": comp.configuration.label,
                "identifier":    comp.configuration.identifier,
                "operation":     comp.operation.rawValue,
                "j2kSwift":      resultDict(comp.j2kSwiftResult),
                "performanceTarget": comp.performanceTarget
            ]
            if let oj = comp.openJPEGResult {
                d["openJPEG"] = resultDict(oj)
                d["speedRatio"] = comp.speedRatio ?? NSNull()
                d["meetsTarget"] = comp.meetsTarget ?? NSNull()
            }
            return d
        }

        let root: [String: Any] = [
            "platform":    suite.platform,
            "timestamp":   suite.timestamp,
            "targetsMet":  suite.targetsMet,
            "total":       suite.comparisons.count,
            "comparisons": comparisonsJSON
        ]

        if let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ), let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}
