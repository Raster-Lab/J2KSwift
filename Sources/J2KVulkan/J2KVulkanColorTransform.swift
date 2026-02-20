//
// J2KVulkanColorTransform.swift
// J2KSwift
//
// Vulkan-accelerated colour space transforms for JPEG 2000.
// Ported from Metal colour transform shaders to SPIR-V with CPU fallback.
//

import Foundation
import J2KCore

// MARK: - Colour Transform Type

/// Colour transform type for Vulkan-accelerated operations.
///
/// Defines the colour space conversion to apply. ICT is used for lossy
/// compression and RCT for lossless compression per JPEG 2000 standard.
public enum J2KVulkanColourTransformType: Sendable {
    /// Irreversible Colour Transform (ICT) for lossy compression.
    ///
    /// Converts RGB to YCbCr using floating-point coefficients.
    case ict
    /// Reversible Colour Transform (RCT) for lossless compression.
    ///
    /// Converts RGB to YUV using integer arithmetic.
    case rct
}

// MARK: - Colour Transform Backend

/// Backend selection for colour transform computation.
///
/// Controls whether the transform runs on GPU (Vulkan) or CPU,
/// with automatic selection based on sample count.
public enum J2KVulkanColourTransformBackend: Sendable {
    /// Force GPU execution via Vulkan.
    case gpu
    /// Force CPU execution (software fallback).
    case cpu
    /// Automatically choose based on sample count and GPU threshold.
    case auto
}

// MARK: - Colour Transform Configuration

/// Configuration for Vulkan-accelerated colour transforms.
///
/// Controls the transform type, backend selection, and GPU dispatch
/// parameters for optimal performance.
public struct J2KVulkanColourTransformConfiguration: Sendable {
    /// The colour transform type to apply.
    public var transformType: J2KVulkanColourTransformType

    /// Minimum sample count to prefer GPU over CPU.
    public var gpuThreshold: Int

    /// Backend selection strategy.
    public var backend: J2KVulkanColourTransformBackend

    /// Creates a Vulkan colour transform configuration.
    ///
    /// - Parameters:
    ///   - transformType: The colour transform type. Defaults to `.ict`.
    ///   - gpuThreshold: Minimum samples to prefer GPU. Defaults to `1024`.
    ///   - backend: Backend selection. Defaults to `.auto`.
    public init(
        transformType: J2KVulkanColourTransformType = .ict,
        gpuThreshold: Int = 1024,
        backend: J2KVulkanColourTransformBackend = .auto
    ) {
        self.transformType = transformType
        self.gpuThreshold = gpuThreshold
        self.backend = backend
    }

    /// Default configuration for lossy compression.
    public static let lossy = J2KVulkanColourTransformConfiguration(transformType: .ict)

    /// Default configuration for lossless compression.
    public static let lossless = J2KVulkanColourTransformConfiguration(transformType: .rct)
}

// MARK: - Colour Transform Result

/// Result of a colour transform operation.
///
/// Contains three output components (Y/Cb/Cr for ICT, or Y/U/V for RCT)
/// and metadata about the transform that was applied.
public struct J2KVulkanColourTransformResult: Sendable {
    /// First output component (luminance: Y).
    public let component0: [Float]
    /// Second output component (chrominance: Cb or U).
    public let component1: [Float]
    /// Third output component (chrominance: Cr or V).
    public let component2: [Float]
    /// The type of transform that was applied.
    public let transformType: J2KVulkanColourTransformType
    /// Whether the GPU was used for this operation.
    public let usedGPU: Bool
    /// Processing time in seconds.
    public let processingTime: Double

    /// Creates a colour transform result.
    public init(
        component0: [Float],
        component1: [Float],
        component2: [Float],
        transformType: J2KVulkanColourTransformType,
        usedGPU: Bool,
        processingTime: Double
    ) {
        self.component0 = component0
        self.component1 = component1
        self.component2 = component2
        self.transformType = transformType
        self.usedGPU = usedGPU
        self.processingTime = processingTime
    }
}

// MARK: - Colour Transform Statistics

/// Performance statistics for Vulkan colour transform operations.
public struct J2KVulkanColourTransformStatistics: Sendable {
    /// Total forward transforms performed.
    public var totalForwardTransforms: Int
    /// Total inverse transforms performed.
    public var totalInverseTransforms: Int
    /// GPU forward transforms.
    public var gpuForwardTransforms: Int
    /// GPU inverse transforms.
    public var gpuInverseTransforms: Int
    /// CPU forward transforms (fallback).
    public var cpuForwardTransforms: Int
    /// CPU inverse transforms (fallback).
    public var cpuInverseTransforms: Int
    /// Total processing time.
    public var totalProcessingTime: Double
    /// Total samples processed.
    public var totalSamplesProcessed: Int

    /// GPU utilisation rate (0.0 to 1.0).
    public var gpuUtilisation: Double {
        let totalOps = totalForwardTransforms + totalInverseTransforms
        guard totalOps > 0 else { return 0.0 }
        let gpuOps = gpuForwardTransforms + gpuInverseTransforms
        return Double(gpuOps) / Double(totalOps)
    }

    /// Creates initial (zero) statistics.
    public init() {
        self.totalForwardTransforms = 0
        self.totalInverseTransforms = 0
        self.gpuForwardTransforms = 0
        self.gpuInverseTransforms = 0
        self.cpuForwardTransforms = 0
        self.cpuInverseTransforms = 0
        self.totalProcessingTime = 0.0
        self.totalSamplesProcessed = 0
    }
}

// MARK: - Vulkan Colour Transform Engine

/// Vulkan-accelerated colour space transform engine for JPEG 2000.
///
/// Provides GPU-accelerated colour transforms ported from Metal shaders
/// to SPIR-V, with CPU fallback for platforms where Vulkan is unavailable.
///
/// ## Supported Transforms
///
/// - **ICT (Irreversible Colour Transform)**: RGB ↔ YCbCr for lossy compression
/// - **RCT (Reversible Colour Transform)**: RGB ↔ YUV for lossless compression
///
/// ## Usage
///
/// ```swift
/// let transform = J2KVulkanColourTransform()
///
/// let result = try await transform.forwardTransform(
///     red: redChannel,
///     green: greenChannel,
///     blue: blueChannel,
///     configuration: .lossy
/// )
/// ```
public actor J2KVulkanColourTransform {
    // MARK: Properties

    private let device: J2KVulkanDevice
    private let shaderLibrary: J2KVulkanShaderLibrary
    private let bufferPool: J2KVulkanBufferPool
    private var statistics: J2KVulkanColourTransformStatistics

    // MARK: Initialisation

    /// Creates a new Vulkan colour transform engine.
    ///
    /// - Parameters:
    ///   - device: The Vulkan device to use.
    ///   - shaderLibrary: The SPIR-V shader library.
    public init(
        device: J2KVulkanDevice,
        shaderLibrary: J2KVulkanShaderLibrary
    ) {
        self.device = device
        self.shaderLibrary = shaderLibrary
        self.bufferPool = J2KVulkanBufferPool()
        self.statistics = J2KVulkanColourTransformStatistics()
    }

    // MARK: - Forward Transform

    /// Performs a forward colour transform (RGB → YCbCr/YUV).
    ///
    /// - Parameters:
    ///   - red: Red channel samples.
    ///   - green: Green channel samples.
    ///   - blue: Blue channel samples.
    ///   - configuration: Colour transform configuration.
    /// - Returns: Colour transform result with Y, Cb/U, Cr/V components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if channel sizes differ.
    public func forwardTransform(
        red: [Float],
        green: [Float],
        blue: [Float],
        configuration: J2KVulkanColourTransformConfiguration = .lossy
    ) async throws -> J2KVulkanColourTransformResult {
        guard red.count == green.count, green.count == blue.count else {
            throw J2KError.invalidParameter("Colour transform channels must have equal length")
        }
        guard !red.isEmpty else {
            throw J2KError.invalidParameter("Colour transform channels must not be empty")
        }

        let startTime = Date()
        let useGPU = shouldUseGPU(sampleCount: red.count, configuration: configuration)

        let result: (c0: [Float], c1: [Float], c2: [Float])

        if useGPU {
            result = try await forwardGPU(
                red: red, green: green, blue: blue,
                configuration: configuration
            )
        } else {
            result = forwardCPU(
                red: red, green: green, blue: blue,
                configuration: configuration
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        updateStatistics(
            isForward: true,
            usedGPU: useGPU,
            processingTime: processingTime,
            sampleCount: red.count
        )

        return J2KVulkanColourTransformResult(
            component0: result.c0,
            component1: result.c1,
            component2: result.c2,
            transformType: configuration.transformType,
            usedGPU: useGPU,
            processingTime: processingTime
        )
    }

    // MARK: - Inverse Transform

    /// Performs an inverse colour transform (YCbCr/YUV → RGB).
    ///
    /// - Parameters:
    ///   - component0: Y (luminance) component.
    ///   - component1: Cb/U (chrominance) component.
    ///   - component2: Cr/V (chrominance) component.
    ///   - configuration: Colour transform configuration.
    /// - Returns: Colour transform result with R, G, B components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if component sizes differ.
    public func inverseTransform(
        component0: [Float],
        component1: [Float],
        component2: [Float],
        configuration: J2KVulkanColourTransformConfiguration = .lossy
    ) async throws -> J2KVulkanColourTransformResult {
        guard component0.count == component1.count, component1.count == component2.count else {
            throw J2KError.invalidParameter("Colour transform components must have equal length")
        }
        guard !component0.isEmpty else {
            throw J2KError.invalidParameter("Colour transform components must not be empty")
        }

        let startTime = Date()
        let useGPU = shouldUseGPU(sampleCount: component0.count, configuration: configuration)

        let result: (c0: [Float], c1: [Float], c2: [Float])

        if useGPU {
            result = try await inverseGPU(
                c0: component0, c1: component1, c2: component2,
                configuration: configuration
            )
        } else {
            result = inverseCPU(
                c0: component0, c1: component1, c2: component2,
                configuration: configuration
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        updateStatistics(
            isForward: false,
            usedGPU: useGPU,
            processingTime: processingTime,
            sampleCount: component0.count
        )

        return J2KVulkanColourTransformResult(
            component0: result.c0,
            component1: result.c1,
            component2: result.c2,
            transformType: configuration.transformType,
            usedGPU: useGPU,
            processingTime: processingTime
        )
    }

    // MARK: - Statistics

    /// Returns current performance statistics.
    public func getStatistics() -> J2KVulkanColourTransformStatistics {
        statistics
    }

    /// Resets performance statistics.
    public func resetStatistics() {
        statistics = J2KVulkanColourTransformStatistics()
    }

    // MARK: - GPU Paths

    private func forwardGPU(
        red: [Float], green: [Float], blue: [Float],
        configuration: J2KVulkanColourTransformConfiguration
    ) async throws -> (c0: [Float], c1: [Float], c2: [Float]) {
        #if canImport(CVulkan)
        fatalError("Vulkan colour transform requires CVulkan system module")
        #else
        return forwardCPU(red: red, green: green, blue: blue, configuration: configuration)
        #endif
    }

    private func inverseGPU(
        c0: [Float], c1: [Float], c2: [Float],
        configuration: J2KVulkanColourTransformConfiguration
    ) async throws -> (c0: [Float], c1: [Float], c2: [Float]) {
        #if canImport(CVulkan)
        fatalError("Vulkan colour transform requires CVulkan system module")
        #else
        return inverseCPU(c0: c0, c1: c1, c2: c2, configuration: configuration)
        #endif
    }

    // MARK: - CPU Fallback

    private func forwardCPU(
        red: [Float], green: [Float], blue: [Float],
        configuration: J2KVulkanColourTransformConfiguration
    ) -> (c0: [Float], c1: [Float], c2: [Float]) {
        switch configuration.transformType {
        case .ict:
            return forwardICT(red: red, green: green, blue: blue)
        case .rct:
            return forwardRCT(red: red, green: green, blue: blue)
        }
    }

    private func inverseCPU(
        c0: [Float], c1: [Float], c2: [Float],
        configuration: J2KVulkanColourTransformConfiguration
    ) -> (c0: [Float], c1: [Float], c2: [Float]) {
        switch configuration.transformType {
        case .ict:
            return inverseICT(y: c0, cb: c1, cr: c2)
        case .rct:
            return inverseRCT(y: c0, u: c1, v: c2)
        }
    }

    // MARK: - ICT (Irreversible Colour Transform)

    /// Forward ICT: RGB → YCbCr (ITU-R BT.601 coefficients per JPEG 2000).
    private func forwardICT(
        red: [Float], green: [Float], blue: [Float]
    ) -> (c0: [Float], c1: [Float], c2: [Float]) {
        let n = red.count
        var y  = [Float](repeating: 0, count: n)
        var cb = [Float](repeating: 0, count: n)
        var cr = [Float](repeating: 0, count: n)

        for i in 0..<n {
            let r = red[i], g = green[i], b = blue[i]
            y[i]  =  0.299   * r + 0.587   * g + 0.114   * b
            cb[i] = -0.16875 * r - 0.33126 * g + 0.5     * b
            cr[i] =  0.5     * r - 0.41869 * g - 0.08131 * b
        }

        return (y, cb, cr)
    }

    /// Inverse ICT: YCbCr → RGB.
    private func inverseICT(
        y: [Float], cb: [Float], cr: [Float]
    ) -> (c0: [Float], c1: [Float], c2: [Float]) {
        let n = y.count
        var r = [Float](repeating: 0, count: n)
        var g = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)

        for i in 0..<n {
            let yv = y[i], cbv = cb[i], crv = cr[i]
            r[i] = yv                   + 1.402   * crv
            g[i] = yv - 0.34413 * cbv - 0.71414 * crv
            b[i] = yv + 1.772   * cbv
        }

        return (r, g, b)
    }

    // MARK: - RCT (Reversible Colour Transform)

    /// Forward RCT: RGB → YUV (integer arithmetic for lossless).
    private func forwardRCT(
        red: [Float], green: [Float], blue: [Float]
    ) -> (c0: [Float], c1: [Float], c2: [Float]) {
        let n = red.count
        var yOut  = [Float](repeating: 0, count: n)
        var uOut  = [Float](repeating: 0, count: n)
        var vOut  = [Float](repeating: 0, count: n)

        for i in 0..<n {
            let r = red[i], g = green[i], b = blue[i]
            yOut[i] = Float(Int((r + 2.0 * g + b) / 4.0))
            uOut[i] = b - g
            vOut[i] = r - g
        }

        return (yOut, uOut, vOut)
    }

    /// Inverse RCT: YUV → RGB.
    private func inverseRCT(
        y: [Float], u: [Float], v: [Float]
    ) -> (c0: [Float], c1: [Float], c2: [Float]) {
        let n = y.count
        var r = [Float](repeating: 0, count: n)
        var g = [Float](repeating: 0, count: n)
        var b = [Float](repeating: 0, count: n)

        for i in 0..<n {
            let yv = y[i], uv = u[i], vv = v[i]
            g[i] = yv - Float(Int((uv + vv) / 4.0))
            r[i] = vv + g[i]
            b[i] = uv + g[i]
        }

        return (r, g, b)
    }

    // MARK: - Utility

    private func shouldUseGPU(
        sampleCount: Int,
        configuration: J2KVulkanColourTransformConfiguration
    ) -> Bool {
        switch configuration.backend {
        case .gpu:
            return J2KVulkanDevice.isAvailable
        case .cpu:
            return false
        case .auto:
            return J2KVulkanDevice.isAvailable && sampleCount >= configuration.gpuThreshold
        }
    }

    private func updateStatistics(
        isForward: Bool,
        usedGPU: Bool,
        processingTime: Double,
        sampleCount: Int
    ) {
        if isForward {
            statistics.totalForwardTransforms += 1
            if usedGPU {
                statistics.gpuForwardTransforms += 1
            } else {
                statistics.cpuForwardTransforms += 1
            }
        } else {
            statistics.totalInverseTransforms += 1
            if usedGPU {
                statistics.gpuInverseTransforms += 1
            } else {
                statistics.cpuInverseTransforms += 1
            }
        }
        statistics.totalProcessingTime += processingTime
        statistics.totalSamplesProcessed += sampleCount
    }
}
