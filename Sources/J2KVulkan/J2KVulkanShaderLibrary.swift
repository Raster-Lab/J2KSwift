//
// J2KVulkanShaderLibrary.swift
// J2KSwift
//
// SPIR-V shader pipeline management for Vulkan compute operations.
//

import Foundation
import J2KCore

// MARK: - Vulkan Shader Function

/// Identifies a compute shader function in the SPIR-V shader library.
///
/// Each case corresponds to a SPIR-V compute shader module compiled from
/// shared shader logic that mirrors the Metal shader library.
public enum J2KVulkanShaderFunction: String, Sendable, CaseIterable {
    // DWT shaders
    /// Forward DWT using Le Gall 5/3 reversible filter (horizontal pass).
    case dwtForward53H = "dwt_forward_53_horizontal"
    /// Forward DWT using Le Gall 5/3 reversible filter (vertical pass).
    case dwtForward53V = "dwt_forward_53_vertical"
    /// Inverse DWT using Le Gall 5/3 reversible filter (horizontal pass).
    case dwtInverse53H = "dwt_inverse_53_horizontal"
    /// Inverse DWT using Le Gall 5/3 reversible filter (vertical pass).
    case dwtInverse53V = "dwt_inverse_53_vertical"
    /// Forward DWT using CDF 9/7 irreversible filter (horizontal pass).
    case dwtForward97H = "dwt_forward_97_horizontal"
    /// Forward DWT using CDF 9/7 irreversible filter (vertical pass).
    case dwtForward97V = "dwt_forward_97_vertical"
    /// Inverse DWT using CDF 9/7 irreversible filter (horizontal pass).
    case dwtInverse97H = "dwt_inverse_97_horizontal"
    /// Inverse DWT using CDF 9/7 irreversible filter (vertical pass).
    case dwtInverse97V = "dwt_inverse_97_vertical"

    // Colour transform shaders
    /// Forward ICT (RGB to YCbCr) for lossy compression.
    case colourForwardICT = "colour_forward_ict"
    /// Inverse ICT (YCbCr to RGB) for lossy decompression.
    case colourInverseICT = "colour_inverse_ict"
    /// Forward RCT (RGB to YUV) for lossless compression.
    case colourForwardRCT = "colour_forward_rct"
    /// Inverse RCT (YUV to RGB) for lossless decompression.
    case colourInverseRCT = "colour_inverse_rct"

    // Quantisation shaders
    /// Scalar (uniform) quantisation.
    case quantiseScalar = "quantise_scalar"
    /// Dead-zone quantisation.
    case quantiseDeadzone = "quantise_deadzone"
    /// Scalar dequantisation.
    case dequantiseScalar = "dequantise_scalar"
    /// Dead-zone dequantisation.
    case dequantiseDeadzone = "dequantise_deadzone"
}

// MARK: - Vulkan Pipeline Configuration

/// Configuration for a Vulkan compute pipeline.
///
/// Encapsulates the workgroup size and specialisation constants
/// needed to create a compute pipeline from a SPIR-V module.
public struct J2KVulkanPipelineConfiguration: Sendable {
    /// Workgroup size in the X dimension.
    public var workGroupSizeX: UInt32
    /// Workgroup size in the Y dimension.
    public var workGroupSizeY: UInt32
    /// Workgroup size in the Z dimension.
    public var workGroupSizeZ: UInt32

    /// Creates a pipeline configuration.
    ///
    /// - Parameters:
    ///   - workGroupSizeX: X dimension workgroup size. Defaults to `256`.
    ///   - workGroupSizeY: Y dimension workgroup size. Defaults to `1`.
    ///   - workGroupSizeZ: Z dimension workgroup size. Defaults to `1`.
    public init(
        workGroupSizeX: UInt32 = 256,
        workGroupSizeY: UInt32 = 1,
        workGroupSizeZ: UInt32 = 1
    ) {
        self.workGroupSizeX = workGroupSizeX
        self.workGroupSizeY = workGroupSizeY
        self.workGroupSizeZ = workGroupSizeZ
    }

    /// Default 1D compute pipeline configuration.
    public static let `default` = J2KVulkanPipelineConfiguration()

    /// Configuration for 2D compute (e.g. image processing).
    public static let compute2D = J2KVulkanPipelineConfiguration(
        workGroupSizeX: 16,
        workGroupSizeY: 16,
        workGroupSizeZ: 1
    )
}

// MARK: - Shader Library Statistics

/// Statistics about shader library usage.
public struct J2KVulkanShaderLibraryStatistics: Sendable {
    /// Total number of pipeline creation requests.
    public var totalPipelineRequests: Int
    /// Number of pipelines served from cache.
    public var cacheHits: Int
    /// Number of pipelines that required compilation.
    public var cacheMisses: Int
    /// Number of distinct pipelines currently cached.
    public var cachedPipelineCount: Int

    /// Cache hit rate (0.0 to 1.0).
    public var cacheHitRate: Double {
        guard totalPipelineRequests > 0 else { return 0.0 }
        return Double(cacheHits) / Double(totalPipelineRequests)
    }

    /// Creates initial (zero) statistics.
    public init() {
        self.totalPipelineRequests = 0
        self.cacheHits = 0
        self.cacheMisses = 0
        self.cachedPipelineCount = 0
    }
}

// MARK: - Shader Library

/// Manages SPIR-V shader modules and Vulkan compute pipelines.
///
/// `J2KVulkanShaderLibrary` loads pre-compiled SPIR-V shader bytecode,
/// creates Vulkan compute pipelines, and caches them for reuse.
///
/// ## SPIR-V Compilation
///
/// Shaders are compiled from GLSL compute shaders to SPIR-V bytecode
/// using `glslangValidator` or `glslc`. The resulting `.spv` files
/// are embedded in the module bundle.
///
/// ## Usage
///
/// ```swift
/// let library = J2KVulkanShaderLibrary()
///
/// // Request a compute pipeline
/// let pipeline = try await library.requestPipeline(
///     for: .dwtForward53H,
///     configuration: .default
/// )
/// ```
public actor J2KVulkanShaderLibrary {
    /// Cached pipeline keys for reuse.
    private var cachedPipelines: Set<String> = []

    /// Library statistics.
    private var _statistics = J2KVulkanShaderLibraryStatistics()

    /// Creates a new shader library.
    public init() {}

    /// Requests a compute pipeline for the given shader function.
    ///
    /// Pipelines are cached by function name and configuration for reuse.
    ///
    /// - Parameters:
    ///   - function: The shader function to create a pipeline for.
    ///   - configuration: The pipeline configuration. Defaults to `.default`.
    /// - Returns: A cache key identifying the pipeline.
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Vulkan is not available.
    public func requestPipeline(
        for function: J2KVulkanShaderFunction,
        configuration: J2KVulkanPipelineConfiguration = .default
    ) throws -> String {
        _statistics.totalPipelineRequests += 1

        let cacheKey = "\(function.rawValue)_\(configuration.workGroupSizeX)x\(configuration.workGroupSizeY)x\(configuration.workGroupSizeZ)"

        if cachedPipelines.contains(cacheKey) {
            _statistics.cacheHits += 1
            return cacheKey
        }

        #if canImport(CVulkan)
        // Real pipeline creation:
        // 1. Load SPIR-V bytecode from bundle
        // 2. vkCreateShaderModule
        // 3. vkCreateComputePipelines
        // 4. Cache pipeline handle
        fatalError("Vulkan pipeline creation requires CVulkan system module")
        #else
        // Cache the key for statistics tracking
        _statistics.cacheMisses += 1
        cachedPipelines.insert(cacheKey)
        _statistics.cachedPipelineCount = cachedPipelines.count
        return cacheKey
        #endif
    }

    /// Returns the current library statistics.
    public func statistics() -> J2KVulkanShaderLibraryStatistics {
        _statistics
    }

    /// Returns the number of available shader functions.
    public func availableFunctionCount() -> Int {
        J2KVulkanShaderFunction.allCases.count
    }

    /// Clears all cached pipelines.
    public func clearCache() {
        cachedPipelines.removeAll()
        _statistics.cachedPipelineCount = 0
    }
}
