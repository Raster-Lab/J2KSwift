//
// J2KAcceleratePerformance.swift
// J2KSwift
//
/// # J2KAcceleratePerformance
///
/// Accelerate framework performance optimization and tuning.
///
/// This module provides Accelerate framework performance optimization
/// including vDSP optimization, NEON code paths, AMX support detection,
/// and data conversion minimization.

#if canImport(Accelerate)
import Accelerate
#endif
import Foundation

#if canImport(Accelerate)

/// Accelerate framework performance optimizer.
///
/// This actor coordinates Accelerate framework optimizations including:
/// - vDSP operation selection and optimization
/// - NEON SIMD code path utilization
/// - AMX (Apple Matrix coprocessor) detection and usage
/// - Data format conversion minimization
/// - Batch processing for efficiency
///
/// Example:
/// ```swift
/// let optimizer = J2KAcceleratePerformance()
/// let config = await optimizer.optimizeForThroughput()
/// let metrics = await optimizer.performanceMetrics()
/// ```
public actor J2KAcceleratePerformance {
    /// Performance optimization configuration.
    public struct Configuration: Sendable {
        /// Enable aggressive vDSP optimization.
        public var enableVDSPOptimization: Bool

        /// Use NEON-specific code paths when available.
        public var useNEONPaths: Bool

        /// Enable AMX operations when available (Apple Silicon).
        public var enableAMX: Bool

        /// Minimum array size for Accelerate operations.
        public var minAccelerateSize: Int

        /// Batch size for vectorized operations.
        public var vectorBatchSize: Int

        /// Enable in-place operations to reduce allocations.
        public var enableInPlaceOperations: Bool

        /// Minimize data type conversions.
        public var minimizeConversions: Bool

        /// Creates default configuration.
        public init(
            enableVDSPOptimization: Bool = true,
            useNEONPaths: Bool = true,
            enableAMX: Bool = true,
            minAccelerateSize: Int = 64,
            vectorBatchSize: Int = 4096,
            enableInPlaceOperations: Bool = true,
            minimizeConversions: Bool = true
        ) {
            self.enableVDSPOptimization = enableVDSPOptimization
            self.useNEONPaths = useNEONPaths
            self.enableAMX = enableAMX
            self.minAccelerateSize = minAccelerateSize
            self.vectorBatchSize = vectorBatchSize
            self.enableInPlaceOperations = enableInPlaceOperations
            self.minimizeConversions = minimizeConversions
        }

        /// High-throughput configuration.
        public static var highThroughput: Configuration {
            Configuration(
                enableVDSPOptimization: true,
                useNEONPaths: true,
                enableAMX: true,
                minAccelerateSize: 32,
                vectorBatchSize: 8192,
                enableInPlaceOperations: true,
                minimizeConversions: true
            )
        }

        /// Low-power configuration.
        public static var lowPower: Configuration {
            Configuration(
                enableVDSPOptimization: true,
                useNEONPaths: false,
                enableAMX: false,
                minAccelerateSize: 128,
                vectorBatchSize: 2048,
                enableInPlaceOperations: true,
                minimizeConversions: true
            )
        }

        /// Balanced configuration.
        public static var balanced: Configuration {
            Configuration()
        }
    }

    /// Performance metrics.
    public struct Metrics: Sendable {
        /// Total vDSP operations performed.
        public let totalVDSPOperations: Int

        /// Total NEON operations performed.
        public let totalNEONOperations: Int

        /// Total AMX operations performed.
        public let totalAMXOperations: Int

        /// Total data conversions.
        public let totalConversions: Int

        /// Total in-place operations.
        public let totalInPlaceOperations: Int

        /// Total time in vDSP operations (seconds).
        public let vdspTime: TimeInterval

        /// Average speedup vs scalar operations.
        public let averageSpeedup: Double

        /// Memory saved by in-place operations (bytes).
        public let memorySaved: Int
    }

    /// Operation record.
    private struct OperationRecord {
        let type: String
        let duration: TimeInterval
        let dataSize: Int
        let inPlace: Bool
        let timestamp: Date
    }

    // MARK: - State

    /// Current configuration.
    private var configuration: Configuration = .balanced

    /// Recorded operations.
    private var operations: [OperationRecord] = []

    /// Session start time.
    private var sessionStart: Date?

    /// Detected capabilities.
    private var capabilities: Capabilities

    /// Platform capabilities.
    private struct Capabilities: Sendable {
        let hasNEON: Bool
        let hasAMX: Bool
        let vectorWidth: Int

        static func detect() -> Capabilities {
            var hasNEON = false
            var hasAMX = false
            var vectorWidth = 128 // bits

            #if arch(arm64)
            hasNEON = true
            vectorWidth = 128

            // Check for Apple Silicon AMX
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            // AMX is available on A14 and later (M1 and later on macOS)
            if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
                hasAMX = true
            }
            #endif
            #elseif arch(x86_64)
            // x86_64 typically has AVX/AVX2
            vectorWidth = 256 // AVX
            #endif

            return Capabilities(
                hasNEON: hasNEON,
                hasAMX: hasAMX,
                vectorWidth: vectorWidth
            )
        }
    }

    // MARK: - Initialization

    /// Creates an Accelerate performance optimizer.
    ///
    /// - Parameter configuration: Initial configuration (default: .balanced).
    public init(configuration: Configuration = .balanced) {
        self.configuration = configuration
        self.capabilities = Capabilities.detect()
    }

    // MARK: - Configuration

    /// Optimizes configuration for maximum throughput.
    ///
    /// - Returns: Optimized configuration.
    public func optimizeForThroughput() -> Configuration {
        configuration = .highThroughput
        return configuration
    }

    /// Optimizes configuration for low power consumption.
    ///
    /// - Returns: Optimized configuration.
    public func optimizeForLowPower() -> Configuration {
        configuration = .lowPower
        return configuration
    }

    /// Sets custom configuration.
    ///
    /// - Parameter config: Custom configuration.
    public func setConfiguration(_ config: Configuration) {
        configuration = config
    }

    /// Returns current configuration.
    public func currentConfiguration() -> Configuration {
        configuration
    }

    // MARK: - Operation Selection

    /// Determines if Accelerate should be used for the given array size.
    ///
    /// - Parameter arraySize: Size of array to process.
    /// - Returns: True if Accelerate is recommended.
    public func shouldUseAccelerate(arraySize: Int) -> Bool {
        guard configuration.enableVDSPOptimization else { return false }
        return arraySize >= configuration.minAccelerateSize
    }

    /// Determines optimal batch size for vectorized operations.
    ///
    /// - Parameters:
    ///   - totalSize: Total number of elements.
    ///   - elementSize: Size of each element in bytes.
    /// - Returns: Optimal batch size.
    public func optimalBatchSize(totalSize: Int, elementSize: Int) -> Int {
        let targetBytes = configuration.vectorBatchSize * elementSize
        let batchSize = min(totalSize, targetBytes / elementSize)

        // Align to vector width for efficiency
        let alignment = capabilities.vectorWidth / (elementSize * 8)
        return (batchSize / alignment) * alignment
    }

    /// Recommends vDSP function for the given operation.
    ///
    /// - Parameters:
    ///   - operation: Operation type (e.g., "add", "multiply", "fft").
    ///   - dataType: Data type ("float", "double", "int").
    ///   - size: Data size.
    /// - Returns: Recommended vDSP function name.
    public func recommendVDSPFunction(
        operation: String,
        dataType: String,
        size: Int
    ) -> String {
        let prefix = dataType == "double" ? "vDSP_" : "vDSP_"
        let suffix = dataType == "double" ? "D" : ""

        switch operation {
        case "add":
            return "\(prefix)vadd\(suffix)"
        case "subtract":
            return "\(prefix)vsub\(suffix)"
        case "multiply":
            return "\(prefix)vmul\(suffix)"
        case "divide":
            return "\(prefix)vdiv\(suffix)"
        case "dotProduct":
            return "\(prefix)dotpr\(suffix)"
        case "sum":
            return "\(prefix)sve\(suffix)"
        case "mean":
            return "\(prefix)meanv\(suffix)"
        case "rms":
            return "\(prefix)rmsqv\(suffix)"
        case "fft":
            return size.isPowerOfTwo ? "vDSP_fft_zip" : "vDSP_DFT"
        default:
            return "\(prefix)\(operation)\(suffix)"
        }
    }

    // MARK: - NEON Optimization

    /// Checks if NEON paths should be used.
    ///
    /// - Returns: True if NEON is available and enabled.
    public func shouldUseNEON() -> Bool {
        guard configuration.useNEONPaths else { return false }
        return capabilities.hasNEON
    }

    /// Returns optimal NEON vector width in bytes.
    public func neonVectorWidth() -> Int {
        guard capabilities.hasNEON else { return 16 }
        return 16 // 128-bit NEON vectors
    }

    // MARK: - AMX Optimization

    /// Checks if AMX should be used for matrix operations.
    ///
    /// - Parameters:
    ///   - rows: Number of rows.
    ///   - cols: Number of columns.
    /// - Returns: True if AMX is recommended.
    public func shouldUseAMX(rows: Int, cols: Int) -> Bool {
        guard configuration.enableAMX else { return false }
        guard capabilities.hasAMX else { return false }

        // AMX is beneficial for larger matrices
        let minSize = 16
        return rows >= minSize && cols >= minSize
    }

    /// Returns optimal tile size for AMX operations.
    ///
    /// - Returns: Tile size (width, height) for AMX.
    public func amxTileSize() -> (width: Int, height: Int) {
        guard capabilities.hasAMX else { return (16, 16) }

        // AMX typically uses 64-byte tiles
        // For FP32: 16x16 = 256 elements = 1024 bytes
        // For FP16: 32x32 = 1024 elements = 2048 bytes
        return (16, 16)
    }

    // MARK: - Data Conversion Optimization

    /// Determines if data conversion can be avoided.
    ///
    /// - Parameters:
    ///   - sourceType: Source data type.
    ///   - targetType: Target data type.
    /// - Returns: True if conversion is necessary.
    public func needsConversion(sourceType: String, targetType: String) -> Bool {
        guard configuration.minimizeConversions else { return true }
        return sourceType != targetType
    }

    /// Recommends optimal data type for operations.
    ///
    /// - Parameters:
    ///   - operationType: Type of operation.
    ///   - precision: Required precision.
    /// - Returns: Recommended data type.
    public func recommendedDataType(
        operationType: String,
        precision: String
    ) -> String {
        if precision == "high" {
            return "double"
        } else if operationType == "matrix" && capabilities.hasAMX {
            return "float16" // AMX optimized for FP16
        } else {
            return "float"
        }
    }

    // MARK: - In-Place Operations

    /// Checks if in-place operation should be used.
    ///
    /// - Parameters:
    ///   - dataSize: Size of data in bytes.
    ///   - operation: Operation type.
    /// - Returns: True if in-place is recommended.
    public func shouldUseInPlace(dataSize: Int, operation: String) -> Bool {
        guard configuration.enableInPlaceOperations else { return false }

        // In-place is beneficial for large data to save memory
        let threshold = 1024 * 1024 // 1 MB
        return dataSize >= threshold
    }

    /// Estimates memory saved by using in-place operations.
    ///
    /// - Parameter dataSize: Size of data in bytes.
    /// - Returns: Estimated memory saved.
    public func memorySavedByInPlace(dataSize: Int) -> Int {
        dataSize // Full data size is saved
    }

    // MARK: - Performance Tracking

    /// Records an Accelerate operation for performance tracking.
    ///
    /// - Parameters:
    ///   - type: Operation type (e.g., "vDSP", "NEON", "AMX").
    ///   - duration: Operation duration in seconds.
    ///   - dataSize: Size of data processed.
    ///   - inPlace: Whether in-place operation was used.
    public func recordOperation(
        type: String,
        duration: TimeInterval,
        dataSize: Int,
        inPlace: Bool = false
    ) {
        let record = OperationRecord(
            type: type,
            duration: duration,
            dataSize: dataSize,
            inPlace: inPlace,
            timestamp: Date()
        )

        operations.append(record)

        // Keep only recent operations (last 1000)
        if operations.count > 1000 {
            operations.removeFirst(operations.count - 1000)
        }
    }

    /// Starts a performance monitoring session.
    public func startSession() {
        sessionStart = Date()
        operations.removeAll()
    }

    /// Ends the performance monitoring session and returns metrics.
    ///
    /// - Returns: Performance metrics for the session.
    public func endSession() -> Metrics {
        let vdspOps = operations.filter { $0.type == "vDSP" }.count
        let neonOps = operations.filter { $0.type == "NEON" }.count
        let amxOps = operations.filter { $0.type == "AMX" }.count
        let conversions = operations.filter { $0.type == "conversion" }.count
        let inPlaceOps = operations.filter { $0.inPlace }.count

        let vdspTime = operations
            .filter { $0.type == "vDSP" }
            .reduce(0) { $0 + $1.duration }

        // Estimate speedup (typical 5-15× for vDSP operations)
        let averageSpeedup = vdspOps > 0 ? 10.0 : 1.0

        let memorySaved = operations
            .filter { $0.inPlace }
            .reduce(0) { $0 + $1.dataSize }

        return Metrics(
            totalVDSPOperations: vdspOps,
            totalNEONOperations: neonOps,
            totalAMXOperations: amxOps,
            totalConversions: conversions,
            totalInPlaceOperations: inPlaceOps,
            vdspTime: vdspTime,
            averageSpeedup: averageSpeedup,
            memorySaved: memorySaved
        )
    }

    /// Returns current performance metrics.
    public func performanceMetrics() -> Metrics {
        endSession()
    }

    // MARK: - Platform Capabilities

    /// Returns platform capabilities.
    public func platformCapabilities() -> (
        hasNEON: Bool,
        hasAMX: Bool,
        vectorWidth: Int
    ) {
        (
            capabilities.hasNEON,
            capabilities.hasAMX,
            capabilities.vectorWidth
        )
    }
}

#endif // canImport(Accelerate)

// MARK: - Helper Extensions

extension Int {
    fileprivate var isPowerOfTwo: Bool {
        self > 0 && (self & (self - 1)) == 0
    }
}
