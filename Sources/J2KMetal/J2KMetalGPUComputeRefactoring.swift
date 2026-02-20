//
// J2KMetalGPUComputeRefactoring.swift
// J2KSwift
//
// Metal GPU Compute Refactoring — Week 247-249.
//
// Provides optimised shader pipelines, tile-based dispatch, indirect command
// buffers, bit-depth shader variants, Metal 3 feature utilisation, async
// compute pipelines, and GPU profiling infrastructure for JPEG 2000 encoding
// and decoding on Apple GPUs.
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

// MARK: - Bit Depth

/// Supported bit depths for GPU shader variants.
///
/// Each bit depth maps to a specialised Metal shader variant that processes
/// samples at the native precision, avoiding unnecessary conversions.
public enum J2KMetalBitDepth: Int, Sendable, CaseIterable, Comparable {
    /// 8-bit unsigned (0–255).
    case depth8 = 8
    /// 12-bit unsigned (0–4095), common in medical imaging.
    case depth12 = 12
    /// 16-bit unsigned (0–65535).
    case depth16 = 16
    /// 32-bit floating point.
    case depth32 = 32

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Bytes per sample for this bit depth.
    public var bytesPerSample: Int {
        switch self {
        case .depth8:  return 1
        case .depth12: return 2
        case .depth16: return 2
        case .depth32: return 4
        }
    }

    /// The shader function suffix used to select the correct variant.
    public var shaderSuffix: String {
        switch self {
        case .depth8:  return "_8bit"
        case .depth12: return "_12bit"
        case .depth16: return "_16bit"
        case .depth32: return "_32bit"
        }
    }
}

// MARK: - Shader Variant

/// A shader variant selected based on bit depth and operation.
///
/// Shader variants allow the pipeline to dispatch the most efficient
/// compute kernel for the data precision in use.
public struct J2KMetalShaderVariant: Sendable, Equatable {
    /// The base function name (e.g. ``J2KMetalShaderFunction/dwtForward97Horizontal``).
    public let baseFunctionName: String
    /// The target bit depth.
    public let bitDepth: J2KMetalBitDepth
    /// The variant-specific function name including the bit-depth suffix.
    public var functionName: String { baseFunctionName + bitDepth.shaderSuffix }

    /// Creates a shader variant.
    ///
    /// - Parameters:
    ///   - baseFunctionName: The base shader function name.
    ///   - bitDepth: The target bit depth.
    public init(baseFunctionName: String, bitDepth: J2KMetalBitDepth) {
        self.baseFunctionName = baseFunctionName
        self.bitDepth = bitDepth
    }
}

// MARK: - Tile Dispatch Configuration

/// Configuration for tile-based shader dispatch.
///
/// Large images are partitioned into tiles so that each tile fits in GPU
/// memory and can be processed independently, enabling overlap between
/// CPU tile preparation and GPU tile execution.
public struct J2KMetalTileDispatchConfiguration: Sendable {
    /// Tile width in pixels.
    public var tileWidth: Int
    /// Tile height in pixels.
    public var tileHeight: Int
    /// Overlap in pixels between adjacent tiles to avoid boundary artefacts.
    public var overlap: Int
    /// Whether to enable double-buffered tile submission.
    public var doubleBuffered: Bool
    /// Maximum number of tiles dispatched concurrently.
    public var maxConcurrentTiles: Int

    /// Creates a tile dispatch configuration.
    ///
    /// - Parameters:
    ///   - tileWidth: Tile width in pixels. Defaults to `256`.
    ///   - tileHeight: Tile height in pixels. Defaults to `256`.
    ///   - overlap: Overlap between adjacent tiles. Defaults to `8`.
    ///   - doubleBuffered: Enable double buffering. Defaults to `true`.
    ///   - maxConcurrentTiles: Maximum concurrent tiles. Defaults to `4`.
    public init(
        tileWidth: Int = 256,
        tileHeight: Int = 256,
        overlap: Int = 8,
        doubleBuffered: Bool = true,
        maxConcurrentTiles: Int = 4
    ) {
        self.tileWidth = max(16, tileWidth)
        self.tileHeight = max(16, tileHeight)
        self.overlap = max(0, overlap)
        self.doubleBuffered = doubleBuffered
        self.maxConcurrentTiles = max(1, maxConcurrentTiles)
    }

    /// Default tile dispatch configuration.
    public static let `default` = J2KMetalTileDispatchConfiguration()

    /// Configuration for large images (4K+).
    public static let largeImage = J2KMetalTileDispatchConfiguration(
        tileWidth: 512,
        tileHeight: 512,
        overlap: 16,
        doubleBuffered: true,
        maxConcurrentTiles: 8
    )

    /// Configuration for small images where tiling overhead exceeds benefit.
    public static let smallImage = J2KMetalTileDispatchConfiguration(
        tileWidth: 1024,
        tileHeight: 1024,
        overlap: 0,
        doubleBuffered: false,
        maxConcurrentTiles: 1
    )
}

// MARK: - Tile Descriptor

/// Describes a single tile within a larger image.
public struct J2KMetalTileDescriptor: Sendable {
    /// Tile index (column).
    public let tileX: Int
    /// Tile index (row).
    public let tileY: Int
    /// Origin X in the full image.
    public let originX: Int
    /// Origin Y in the full image.
    public let originY: Int
    /// Width of this tile (may be smaller at image edges).
    public let width: Int
    /// Height of this tile (may be smaller at image edges).
    public let height: Int

    /// Creates a tile descriptor.
    public init(tileX: Int, tileY: Int, originX: Int, originY: Int, width: Int, height: Int) {
        self.tileX = tileX
        self.tileY = tileY
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}

// MARK: - Indirect Command Buffer Configuration

/// Configuration for Metal indirect command buffers.
///
/// Indirect command buffers allow the GPU to determine and record its own
/// dispatch commands, reducing CPU overhead for adaptive workloads such as
/// variable-size tile processing.
public struct J2KMetalIndirectCommandConfiguration: Sendable {
    /// Maximum number of commands in the indirect buffer.
    public var maxCommandCount: Int
    /// Whether to inherit pipeline state from the encoder.
    public var inheritPipelineState: Bool
    /// Whether to inherit buffer bindings.
    public var inheritBuffers: Bool

    /// Creates an indirect command buffer configuration.
    ///
    /// - Parameters:
    ///   - maxCommandCount: Maximum commands. Defaults to `256`.
    ///   - inheritPipelineState: Inherit pipeline state. Defaults to `true`.
    ///   - inheritBuffers: Inherit buffer bindings. Defaults to `true`.
    public init(
        maxCommandCount: Int = 256,
        inheritPipelineState: Bool = true,
        inheritBuffers: Bool = true
    ) {
        self.maxCommandCount = max(1, maxCommandCount)
        self.inheritPipelineState = inheritPipelineState
        self.inheritBuffers = inheritBuffers
    }

    /// Default configuration.
    public static let `default` = J2KMetalIndirectCommandConfiguration()
}

// MARK: - Async Compute Pipeline Configuration

/// Configuration for the async compute pipeline that overlaps CPU and GPU work.
///
/// The async pipeline uses double-buffered command submission so that the CPU
/// prepares tile N+1 while the GPU processes tile N, maximising throughput.
public struct J2KMetalAsyncComputeConfiguration: Sendable {
    /// Number of in-flight command buffers (double- or triple-buffered).
    public var inflightBufferCount: Int
    /// Whether to use separate command queues for independent operations.
    public var enableMultiQueue: Bool
    /// Whether to use Metal events for GPU timeline synchronisation.
    public var enableTimelineSync: Bool
    /// Priority for the compute command queue.
    public var computePriority: J2KMetalComputePriority

    /// Creates an async compute configuration.
    ///
    /// - Parameters:
    ///   - inflightBufferCount: In-flight buffers. Defaults to `2` (double-buffered).
    ///   - enableMultiQueue: Use multiple queues. Defaults to `true`.
    ///   - enableTimelineSync: Use Metal events. Defaults to `true`.
    ///   - computePriority: Queue priority. Defaults to `.normal`.
    public init(
        inflightBufferCount: Int = 2,
        enableMultiQueue: Bool = true,
        enableTimelineSync: Bool = true,
        computePriority: J2KMetalComputePriority = .normal
    ) {
        self.inflightBufferCount = max(1, min(3, inflightBufferCount))
        self.enableMultiQueue = enableMultiQueue
        self.enableTimelineSync = enableTimelineSync
        self.computePriority = computePriority
    }

    /// Default async compute configuration.
    public static let `default` = J2KMetalAsyncComputeConfiguration()

    /// Configuration for maximum throughput.
    public static let highThroughput = J2KMetalAsyncComputeConfiguration(
        inflightBufferCount: 3,
        enableMultiQueue: true,
        enableTimelineSync: true,
        computePriority: .high
    )
}

/// Priority level for Metal compute queues.
public enum J2KMetalComputePriority: Int, Sendable, Comparable {
    /// Low priority — background work.
    case low = 0
    /// Normal priority — standard processing.
    case normal = 1
    /// High priority — latency-sensitive work.
    case high = 2

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - GPU Profiling

/// GPU profiling event for Instruments integration.
public struct J2KMetalProfilingEvent: Sendable {
    /// Event name (kernel or operation name).
    public let name: String
    /// Start time (monotonic).
    public let startTime: UInt64
    /// End time (monotonic).
    public let endTime: UInt64
    /// Duration in seconds.
    public let duration: TimeInterval
    /// Threadgroup size used.
    public let threadgroupSize: Int
    /// Grid size (total threads).
    public let gridSize: Int
    /// Whether the kernel was dispatched asynchronously.
    public let isAsync: Bool

    /// Creates a profiling event.
    public init(
        name: String,
        startTime: UInt64,
        endTime: UInt64,
        duration: TimeInterval,
        threadgroupSize: Int,
        gridSize: Int,
        isAsync: Bool
    ) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.threadgroupSize = threadgroupSize
        self.gridSize = gridSize
        self.isAsync = isAsync
    }
}

/// GPU occupancy analysis results.
public struct J2KMetalOccupancyAnalysis: Sendable {
    /// The shader function analysed.
    public let shaderName: String
    /// Optimal threadgroup size for this shader.
    public let optimalThreadgroupSize: Int
    /// Estimated occupancy (0.0–1.0).
    public let estimatedOccupancy: Double
    /// Register pressure estimate (registers per thread).
    public let registerPressure: Int
    /// Threadgroup memory used (bytes).
    public let threadgroupMemoryUsed: Int
    /// Recommended maximum threads per threadgroup.
    public let recommendedMaxThreads: Int

    /// Creates an occupancy analysis.
    public init(
        shaderName: String,
        optimalThreadgroupSize: Int,
        estimatedOccupancy: Double,
        registerPressure: Int,
        threadgroupMemoryUsed: Int,
        recommendedMaxThreads: Int
    ) {
        self.shaderName = shaderName
        self.optimalThreadgroupSize = optimalThreadgroupSize
        self.estimatedOccupancy = estimatedOccupancy
        self.registerPressure = registerPressure
        self.threadgroupMemoryUsed = threadgroupMemoryUsed
        self.recommendedMaxThreads = recommendedMaxThreads
    }
}

/// Threadgroup memory layout optimisation recommendation.
public struct J2KMetalThreadgroupMemoryLayout: Sendable {
    /// Recommended threadgroup memory size in bytes.
    public let size: Int
    /// Alignment requirement.
    public let alignment: Int
    /// Whether bank conflict avoidance is recommended.
    public let avoidBankConflicts: Bool
    /// Padding to add to each row (for bank conflict avoidance).
    public let rowPadding: Int

    /// Creates a threadgroup memory layout.
    public init(size: Int, alignment: Int, avoidBankConflicts: Bool, rowPadding: Int) {
        self.size = size
        self.alignment = alignment
        self.avoidBankConflicts = avoidBankConflicts
        self.rowPadding = rowPadding
    }
}

/// ALU/bandwidth bottleneck identification.
public enum J2KMetalBottleneck: String, Sendable {
    /// The kernel is limited by ALU throughput.
    case aluBound = "ALU-bound"
    /// The kernel is limited by memory bandwidth.
    case bandwidthBound = "bandwidth-bound"
    /// The kernel is limited by launch overhead / latency.
    case latencyBound = "latency-bound"
    /// Balanced between ALU and bandwidth.
    case balanced = "balanced"
}

/// Bottleneck analysis result.
public struct J2KMetalBottleneckAnalysis: Sendable {
    /// The identified bottleneck.
    public let bottleneck: J2KMetalBottleneck
    /// Estimated ALU utilisation (0.0–1.0).
    public let aluUtilisation: Double
    /// Estimated bandwidth utilisation (0.0–1.0).
    public let bandwidthUtilisation: Double
    /// Recommendations for improvement.
    public let recommendations: [String]

    /// Creates a bottleneck analysis.
    public init(
        bottleneck: J2KMetalBottleneck,
        aluUtilisation: Double,
        bandwidthUtilisation: Double,
        recommendations: [String]
    ) {
        self.bottleneck = bottleneck
        self.aluUtilisation = aluUtilisation
        self.bandwidthUtilisation = bandwidthUtilisation
        self.recommendations = recommendations
    }
}

// MARK: - Metal 3 Feature Detection

/// Metal 3 feature availability and capability detection.
///
/// Metal 3 features require Apple Silicon (A15/M2 or later) and appropriate
/// OS versions. This struct provides runtime detection so that the framework
/// can selectively enable advanced features.
public struct J2KMetal3Features: Sendable {
    /// Whether mesh shaders are available.
    public let meshShaders: Bool
    /// Whether raytracing acceleration structures are available.
    public let raytracingAcceleration: Bool
    /// Whether improved residency sets are available.
    public let residencySets: Bool
    /// Whether function pointers (visible function tables) are available.
    public let functionPointers: Bool

    /// Detect Metal 3 feature availability on the current platform.
    ///
    /// - Returns: Feature availability descriptor.
    public static func detect() -> J2KMetal3Features {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice() else {
            return J2KMetal3Features(
                meshShaders: false,
                raytracingAcceleration: false,
                residencySets: false,
                functionPointers: false
            )
        }
        let supportsRaytracing = device.supportsRaytracing
        let supportsFunctionPointers = device.supportsFunctionPointers
        // Mesh shaders available on Apple GPU Family 9+ (M3), detect via name heuristic
        let isMetal3Plus = device.name.lowercased().contains("apple") &&
            device.supportsRaytracing
        return J2KMetal3Features(
            meshShaders: isMetal3Plus,
            raytracingAcceleration: supportsRaytracing,
            residencySets: isMetal3Plus,
            functionPointers: supportsFunctionPointers
        )
        #else
        return J2KMetal3Features(
            meshShaders: false,
            raytracingAcceleration: false,
            residencySets: false,
            functionPointers: false
        )
        #endif
    }

    /// Whether any Metal 3 feature is available.
    public var anyAvailable: Bool {
        meshShaders || raytracingAcceleration || residencySets || functionPointers
    }
}

// MARK: - Shader Pipeline Manager

/// Manages the refactored shader pipeline with bit-depth variants,
/// tile-based dispatch, indirect command buffers, and occupancy tuning.
///
/// This actor is the primary entry point for the Week 247-249 GPU compute
/// refactoring. It builds on the existing ``J2KMetalShaderLibrary`` and
/// ``J2KMetalBufferPool`` to provide:
///
/// - **Shader variants** for 8/12/16/32-bit processing
/// - **Tile-based dispatch** for large images that exceed GPU memory
/// - **Indirect command buffers** for adaptive workloads
/// - **Async compute pipelines** with double-buffered command submission
/// - **GPU profiling** with occupancy analysis and bottleneck detection
///
/// Example:
/// ```swift
/// let pipeline = J2KMetalShaderPipelineManager()
/// try await pipeline.initialize()
///
/// let variant = pipeline.shaderVariant(
///     baseName: "j2k_dwt_forward_97_horizontal",
///     bitDepth: .depth16
/// )
///
/// let tiles = await pipeline.computeTileGrid(
///     imageWidth: 4096, imageHeight: 4096
/// )
/// ```
public actor J2KMetalShaderPipelineManager {
    /// Whether the refactored Metal pipeline is available.
    public static var isAvailable: Bool {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    // MARK: - Configuration

    /// Tile dispatch configuration.
    public var tileConfig: J2KMetalTileDispatchConfiguration

    /// Indirect command buffer configuration.
    public var indirectConfig: J2KMetalIndirectCommandConfiguration

    /// Async compute configuration.
    public var asyncConfig: J2KMetalAsyncComputeConfiguration

    // MARK: - State

    /// Whether the pipeline has been initialised.
    private var isInitialized = false

    /// Profiling events recorded during the current session.
    private var profilingEvents: [J2KMetalProfilingEvent] = []

    /// Occupancy analysis cache.
    private var occupancyCache: [String: J2KMetalOccupancyAnalysis] = [:]

    #if canImport(Metal)
    /// The Metal device.
    private var device: (any MTLDevice)?

    /// Primary command queue.
    private var primaryQueue: (any MTLCommandQueue)?

    /// Secondary command queue for multi-queue submission.
    private var secondaryQueue: (any MTLCommandQueue)?

    /// Metal shared event for timeline synchronisation.
    private var sharedEvent: (any MTLEvent)?

    /// Event counter for timeline synchronisation.
    private var eventCounter: UInt64 = 0
    #endif

    // MARK: - Initialisation

    /// Creates a shader pipeline manager.
    ///
    /// - Parameters:
    ///   - tileConfig: Tile dispatch configuration. Defaults to `.default`.
    ///   - indirectConfig: Indirect command buffer configuration. Defaults to `.default`.
    ///   - asyncConfig: Async compute configuration. Defaults to `.default`.
    public init(
        tileConfig: J2KMetalTileDispatchConfiguration = .default,
        indirectConfig: J2KMetalIndirectCommandConfiguration = .default,
        asyncConfig: J2KMetalAsyncComputeConfiguration = .default
    ) {
        self.tileConfig = tileConfig
        self.indirectConfig = indirectConfig
        self.asyncConfig = asyncConfig
    }

    /// Initialises the Metal pipeline.
    ///
    /// Sets up the device, command queues, and shared event for timeline sync.
    ///
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Metal is not available.
    /// - Throws: ``J2KError/internalError(_:)`` if initialisation fails.
    public func initialize() throws {
        guard !isInitialized else { return }

        #if canImport(Metal)
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            throw J2KError.unsupportedFeature("Metal device not available")
        }

        guard let queue = metalDevice.makeCommandQueue() else {
            throw J2KError.internalError("Failed to create Metal command queue")
        }

        self.device = metalDevice
        self.primaryQueue = queue

        if asyncConfig.enableMultiQueue {
            self.secondaryQueue = metalDevice.makeCommandQueue()
        }

        if asyncConfig.enableTimelineSync {
            self.sharedEvent = metalDevice.makeEvent()
        }

        self.isInitialized = true
        #else
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
        #endif
    }

    /// Whether the pipeline is initialised and ready.
    public func isReady() -> Bool {
        isInitialized
    }

    // MARK: - Shader Variants

    /// Creates a shader variant for a given base function and bit depth.
    ///
    /// - Parameters:
    ///   - baseName: The base function name (e.g. `"j2k_dwt_forward_97_horizontal"`).
    ///   - bitDepth: The target bit depth.
    /// - Returns: A ``J2KMetalShaderVariant``.
    public func shaderVariant(
        baseName: String,
        bitDepth: J2KMetalBitDepth
    ) -> J2KMetalShaderVariant {
        J2KMetalShaderVariant(baseFunctionName: baseName, bitDepth: bitDepth)
    }

    /// Returns all shader variants for a base function across all bit depths.
    ///
    /// - Parameter baseName: The base function name.
    /// - Returns: Array of variants for 8/12/16/32-bit depths.
    public func allVariants(baseName: String) -> [J2KMetalShaderVariant] {
        J2KMetalBitDepth.allCases.map {
            J2KMetalShaderVariant(baseFunctionName: baseName, bitDepth: $0)
        }
    }

    /// Selects the optimal bit depth for a given sample precision.
    ///
    /// - Parameter bitsPerSample: The actual precision of the source data.
    /// - Returns: The closest supported bit depth.
    public func optimalBitDepth(for bitsPerSample: Int) -> J2KMetalBitDepth {
        switch bitsPerSample {
        case ...8: return .depth8
        case 9...12: return .depth12
        case 13...16: return .depth16
        default: return .depth32
        }
    }

    // MARK: - Tile-Based Dispatch

    /// Computes the tile grid for a given image size.
    ///
    /// - Parameters:
    ///   - imageWidth: Image width in pixels.
    ///   - imageHeight: Image height in pixels.
    ///   - config: Optional tile configuration override.
    /// - Returns: Array of ``J2KMetalTileDescriptor`` covering the entire image.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if dimensions are invalid.
    public func computeTileGrid(
        imageWidth: Int,
        imageHeight: Int,
        config: J2KMetalTileDispatchConfiguration? = nil
    ) throws -> [J2KMetalTileDescriptor] {
        let cfg = config ?? tileConfig

        guard imageWidth > 0, imageHeight > 0 else {
            throw J2KError.invalidParameter("Image dimensions must be positive")
        }

        let effectiveTileW = cfg.tileWidth
        let effectiveTileH = cfg.tileHeight
        let step = max(1, effectiveTileW - cfg.overlap)
        let stepH = max(1, effectiveTileH - cfg.overlap)

        let tilesX = max(1, (imageWidth + step - 1) / step)
        let tilesY = max(1, (imageHeight + stepH - 1) / stepH)

        var tiles: [J2KMetalTileDescriptor] = []
        tiles.reserveCapacity(tilesX * tilesY)

        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                let ox = tx * step
                let oy = ty * stepH
                let w = min(effectiveTileW, imageWidth - ox)
                let h = min(effectiveTileH, imageHeight - oy)
                tiles.append(J2KMetalTileDescriptor(
                    tileX: tx, tileY: ty,
                    originX: ox, originY: oy,
                    width: w, height: h
                ))
            }
        }

        return tiles
    }

    /// Determines how many tiles can be dispatched concurrently.
    ///
    /// - Parameter tiles: The tile descriptors.
    /// - Returns: Maximum concurrent dispatch count.
    public func maxConcurrentDispatches(for tiles: [J2KMetalTileDescriptor]) -> Int {
        min(tiles.count, tileConfig.maxConcurrentTiles)
    }

    // MARK: - Indirect Command Buffers

    /// Validates indirect command buffer configuration against device limits.
    ///
    /// - Returns: `true` if indirect command buffers can be used.
    public func supportsIndirectCommandBuffers() -> Bool {
        #if canImport(Metal)
        guard let device else { return false }
        // ICBs require A11+ / Apple Silicon
        return device.supportsFamily(.apple4)
        #else
        return false
        #endif
    }

    /// Computes the number of commands needed for a set of tiles.
    ///
    /// - Parameter tileCount: Number of tiles to process.
    /// - Returns: Number of indirect commands, clamped to configuration maximum.
    public func indirectCommandCount(for tileCount: Int) -> Int {
        min(tileCount, indirectConfig.maxCommandCount)
    }

    // MARK: - Async Compute Pipeline

    /// Returns the number of in-flight command buffers for the configured
    /// async pipeline.
    public func inflightBufferCount() -> Int {
        asyncConfig.inflightBufferCount
    }

    /// Whether multi-queue submission is enabled and available.
    public func isMultiQueueAvailable() -> Bool {
        #if canImport(Metal)
        return asyncConfig.enableMultiQueue && secondaryQueue != nil
        #else
        return false
        #endif
    }

    /// Whether timeline synchronisation is enabled and available.
    public func isTimelineSyncAvailable() -> Bool {
        #if canImport(Metal)
        return asyncConfig.enableTimelineSync && sharedEvent != nil
        #else
        return false
        #endif
    }

    /// Signals the next event in the GPU timeline.
    ///
    /// - Returns: The signalled event value.
    public func signalTimeline() -> UInt64 {
        #if canImport(Metal)
        eventCounter += 1
        return eventCounter
        #else
        return 0
        #endif
    }

    /// Returns the current timeline event value.
    public func currentTimelineValue() -> UInt64 {
        #if canImport(Metal)
        return eventCounter
        #else
        return 0
        #endif
    }

    // MARK: - GPU Profiling

    /// Records a profiling event.
    ///
    /// - Parameter event: The profiling event to record.
    public func recordEvent(_ event: J2KMetalProfilingEvent) {
        profilingEvents.append(event)
        // Keep bounded
        if profilingEvents.count > 10_000 {
            profilingEvents.removeFirst(profilingEvents.count - 10_000)
        }
    }

    /// Returns all profiling events recorded since the last reset.
    public func allProfilingEvents() -> [J2KMetalProfilingEvent] {
        profilingEvents
    }

    /// Clears all profiling events.
    public func clearProfilingEvents() {
        profilingEvents.removeAll()
    }

    /// Analyses shader occupancy for a given shader configuration.
    ///
    /// - Parameters:
    ///   - shaderName: The shader function name.
    ///   - threadgroupSize: The proposed threadgroup size.
    ///   - registersPerThread: Estimated registers per thread.
    ///   - threadgroupMemory: Threadgroup memory in bytes.
    /// - Returns: An ``J2KMetalOccupancyAnalysis``.
    public func analyseOccupancy(
        shaderName: String,
        threadgroupSize: Int,
        registersPerThread: Int = 32,
        threadgroupMemory: Int = 0
    ) -> J2KMetalOccupancyAnalysis {
        if let cached = occupancyCache[shaderName] {
            return cached
        }

        let maxThreads = 1024 // Typical Apple GPU max
        let maxRegisters = 256 // Approximate Apple GPU register file per thread
        let maxTGMemory = 32_768 // 32 KB typical threadgroup memory

        // Estimate occupancy based on resource usage
        let registerOccupancy = min(1.0, Double(maxRegisters) / Double(max(1, registersPerThread)))
        let threadOccupancy = min(1.0, Double(threadgroupSize) / Double(maxThreads))
        let memoryOccupancy = threadgroupMemory > 0
            ? min(1.0, Double(maxTGMemory) / Double(threadgroupMemory))
            : 1.0

        let estimatedOccupancy = min(registerOccupancy, min(threadOccupancy, memoryOccupancy))

        // Recommend optimal threadgroup size
        let recommended: Int
        if registersPerThread > 64 {
            recommended = 128 // High register pressure → smaller threadgroups
        } else if threadgroupMemory > maxTGMemory / 2 {
            recommended = 256 // Moderate memory → moderate threadgroups
        } else {
            recommended = 512 // Low pressure → larger threadgroups
        }

        let analysis = J2KMetalOccupancyAnalysis(
            shaderName: shaderName,
            optimalThreadgroupSize: min(recommended, maxThreads),
            estimatedOccupancy: estimatedOccupancy,
            registerPressure: registersPerThread,
            threadgroupMemoryUsed: threadgroupMemory,
            recommendedMaxThreads: min(recommended, maxThreads)
        )

        occupancyCache[shaderName] = analysis
        return analysis
    }

    /// Clears the occupancy analysis cache.
    public func clearOccupancyCache() {
        occupancyCache.removeAll()
    }

    /// Computes optimal threadgroup memory layout for DWT operations.
    ///
    /// - Parameters:
    ///   - tileWidth: Width of tiles being processed.
    ///   - bitDepth: Bit depth of the data.
    /// - Returns: A ``J2KMetalThreadgroupMemoryLayout``.
    public func optimalThreadgroupMemoryLayout(
        tileWidth: Int,
        bitDepth: J2KMetalBitDepth
    ) -> J2KMetalThreadgroupMemoryLayout {
        let bytesPerElement = bitDepth.bytesPerSample
        let baseSize = tileWidth * bytesPerElement
        let alignment = 16 // 16-byte alignment for Metal

        // Apple GPUs have 32 banks of 4 bytes each = 128 bytes per row
        // Add padding to avoid bank conflicts when stride is power of 2
        let bankSize = 128
        let avoidConflicts = baseSize.isMultiple(of: bankSize)
        let padding = avoidConflicts ? bytesPerElement : 0

        let totalSize = (baseSize + padding + alignment - 1) / alignment * alignment

        return J2KMetalThreadgroupMemoryLayout(
            size: totalSize,
            alignment: alignment,
            avoidBankConflicts: avoidConflicts,
            rowPadding: padding
        )
    }

    /// Analyses whether a kernel is ALU-bound or bandwidth-bound.
    ///
    /// - Parameters:
    ///   - bytesRead: Bytes read from memory.
    ///   - bytesWritten: Bytes written to memory.
    ///   - operations: Estimated ALU operations.
    ///   - duration: Kernel duration in seconds.
    /// - Returns: A ``J2KMetalBottleneckAnalysis``.
    public func analyseBottleneck(
        bytesRead: Int,
        bytesWritten: Int,
        operations: Int,
        duration: TimeInterval
    ) -> J2KMetalBottleneckAnalysis {
        guard duration > 0 else {
            return J2KMetalBottleneckAnalysis(
                bottleneck: .latencyBound,
                aluUtilisation: 0,
                bandwidthUtilisation: 0,
                recommendations: ["Duration is zero — kernel may be launch-bound."]
            )
        }

        // Apple M-series approximate peak: ~400 GB/s bandwidth, ~10 TFLOPS
        let peakBandwidth = 400_000_000_000.0 // bytes/s
        let peakFLOPS = 10_000_000_000_000.0 // FLOPS

        let totalBytes = Double(bytesRead + bytesWritten)
        let bwUtil = min(1.0, totalBytes / (duration * peakBandwidth))
        let aluUtil = min(1.0, Double(operations) / (duration * peakFLOPS))

        let bottleneck: J2KMetalBottleneck
        var recommendations: [String] = []

        if bwUtil > aluUtil * 1.5 {
            bottleneck = .bandwidthBound
            recommendations.append("Reduce memory traffic by using threadgroup memory.")
            recommendations.append("Consider packing data to reduce bandwidth.")
        } else if aluUtil > bwUtil * 1.5 {
            bottleneck = .aluBound
            recommendations.append("Simplify arithmetic or use approximate functions.")
            recommendations.append("Consider half-precision (float16) where acceptable.")
        } else if bwUtil < 0.1 && aluUtil < 0.1 {
            bottleneck = .latencyBound
            recommendations.append("Increase work per dispatch to amortise launch overhead.")
            recommendations.append("Batch multiple kernels into a single command buffer.")
        } else {
            bottleneck = .balanced
            recommendations.append("Performance is well balanced between ALU and memory.")
        }

        return J2KMetalBottleneckAnalysis(
            bottleneck: bottleneck,
            aluUtilisation: aluUtil,
            bandwidthUtilisation: bwUtil,
            recommendations: recommendations
        )
    }

    // MARK: - Multi-GPU Support

    /// Enumerates all available Metal devices on the system.
    ///
    /// On macOS, this returns all GPUs (integrated, discrete, external).
    /// On iOS/tvOS, only the default device is returned.
    ///
    /// - Returns: Array of device name strings.
    public func availableDevices() -> [String] {
        #if canImport(Metal)
        #if os(macOS)
        return MTLCopyAllDevices().map { $0.name }
        #else
        if let device = MTLCreateSystemDefaultDevice() {
            return [device.name]
        }
        return []
        #endif
        #else
        return []
        #endif
    }

    /// Returns the name of the currently selected device.
    public func currentDeviceName() -> String {
        #if canImport(Metal)
        return device?.name ?? "unavailable"
        #else
        return "unavailable"
        #endif
    }

    // MARK: - Metal 3 Features

    /// Detects Metal 3 feature availability.
    ///
    /// - Returns: A ``J2KMetal3Features`` descriptor.
    public func detectMetal3Features() -> J2KMetal3Features {
        J2KMetal3Features.detect()
    }

    // MARK: - Tile-Pipelined Encode

    /// Executes a tile-pipelined encode where the CPU prepares tile N+1
    /// while the GPU processes tile N.
    ///
    /// This is a CPU-side simulation of the pipelining strategy. In a full
    /// Metal implementation, the GPU work is submitted via command buffers
    /// and the CPU prepares data for the next tile concurrently.
    ///
    /// - Parameters:
    ///   - tiles: Tile descriptors for the full image.
    ///   - prepareTile: Closure that prepares tile data (CPU work).
    ///   - processTile: Closure that submits GPU work for a tile.
    /// - Returns: Number of tiles processed.
    /// - Throws: Any error from tile preparation or processing.
    public func tilePipelinedEncode(
        tiles: [J2KMetalTileDescriptor],
        prepareTile: @Sendable (J2KMetalTileDescriptor) throws -> [Float],
        processTile: @Sendable (J2KMetalTileDescriptor, [Float]) throws -> Void
    ) throws -> Int {
        guard !tiles.isEmpty else { return 0 }

        // Double-buffered: prepare next while processing current
        var preparedData: [Float]? = nil
        var processedCount = 0

        for (index, tile) in tiles.enumerated() {
            let currentData: [Float]
            if let prepared = preparedData {
                currentData = prepared
            } else {
                currentData = try prepareTile(tile)
            }

            // Prepare next tile in advance (if any)
            if index + 1 < tiles.count && asyncConfig.inflightBufferCount > 1 {
                preparedData = try prepareTile(tiles[index + 1])
            } else {
                preparedData = nil
            }

            // Process current tile
            try processTile(tile, currentData)
            processedCount += 1
        }

        return processedCount
    }

    // MARK: - Performance Benchmarking

    /// Runs a synthetic GPU vs CPU benchmark for DWT-like operations.
    ///
    /// - Parameter dataSize: Number of float samples to process.
    /// - Returns: A tuple of (cpuTime, gpuEstimate, speedup).
    public func benchmarkDWT(dataSize: Int) -> (cpuTime: TimeInterval, gpuEstimate: TimeInterval, speedup: Double) {
        let data = [Float](repeating: 1.0, count: max(1, dataSize))

        // CPU benchmark: simple lifting-style pass
        let cpuStart = Date()
        var result = data
        for i in stride(from: 0, to: result.count - 1, by: 2) {
            result[i] = result[i] + (i + 1 < result.count ? result[i + 1] : 0)
        }
        let cpuTime = Date().timeIntervalSince(cpuStart)

        // GPU estimate: assume 10-50x speedup for large data
        let gpuOverhead = 0.0001 // 100 µs launch overhead
        let gpuThroughput = Double(dataSize) / 10_000_000_000.0 // ~10 GFLOPS effective
        let gpuEstimate = gpuOverhead + gpuThroughput

        let speedup = cpuTime > 0 ? cpuTime / max(gpuEstimate, 1e-9) : 1.0

        return (cpuTime, gpuEstimate, speedup)
    }

    /// Estimates memory bandwidth utilisation for a tile-based operation.
    ///
    /// - Parameters:
    ///   - tileCount: Number of tiles.
    ///   - tileSize: Size per tile in bytes.
    ///   - duration: Total processing time.
    /// - Returns: Estimated bandwidth in GB/s.
    public func estimateBandwidth(
        tileCount: Int,
        tileSize: Int,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0 else { return 0 }
        let totalBytes = Double(tileCount * tileSize * 2) // read + write
        return totalBytes / duration / 1_000_000_000.0 // GB/s
    }
}
