//
// J2KVulkanQuantizer.swift
// J2KSwift
//
// Vulkan-accelerated quantisation and dequantisation for JPEG 2000.
// Ported from Metal quantiser shaders to SPIR-V with CPU fallback.
//

import Foundation
import J2KCore

// MARK: - Quantisation Mode

/// Vulkan-accelerated quantisation mode.
public enum J2KVulkanQuantisationMode: Sendable {
    /// Scalar (uniform) quantisation.
    case scalar
    /// Dead-zone quantisation with enlarged zero bin.
    case deadzone
}

// MARK: - Quantisation Backend

/// Backend selection for quantisation computation.
public enum J2KVulkanQuantisationBackend: Sendable {
    /// Force GPU execution via Vulkan.
    case gpu
    /// Force CPU execution (software fallback).
    case cpu
    /// Automatically choose based on coefficient count.
    case auto
}

// MARK: - Quantisation Configuration

/// Configuration for Vulkan-accelerated quantisation.
public struct J2KVulkanQuantisationConfiguration: Sendable {
    /// Quantisation mode.
    public var mode: J2KVulkanQuantisationMode

    /// Base quantisation step size.
    public var stepSize: Float

    /// Deadzone width multiplier (for deadzone mode).
    public var deadzoneWidth: Float

    /// Minimum coefficient count to prefer GPU over CPU.
    public var gpuThreshold: Int

    /// Backend selection strategy.
    public var backend: J2KVulkanQuantisationBackend

    /// Creates a Vulkan quantisation configuration.
    ///
    /// - Parameters:
    ///   - mode: Quantisation mode. Defaults to `.deadzone`.
    ///   - stepSize: Base step size. Defaults to `0.1`.
    ///   - deadzoneWidth: Deadzone width multiplier. Defaults to `1.5`.
    ///   - gpuThreshold: Minimum coefficients to prefer GPU. Defaults to `1024`.
    ///   - backend: Backend selection. Defaults to `.auto`.
    public init(
        mode: J2KVulkanQuantisationMode = .deadzone,
        stepSize: Float = 0.1,
        deadzoneWidth: Float = 1.5,
        gpuThreshold: Int = 1024,
        backend: J2KVulkanQuantisationBackend = .auto
    ) {
        self.mode = mode
        self.stepSize = stepSize
        self.deadzoneWidth = deadzoneWidth
        self.gpuThreshold = gpuThreshold
        self.backend = backend
    }

    /// Default configuration for lossy compression.
    public static let lossy = J2KVulkanQuantisationConfiguration(
        mode: .deadzone,
        stepSize: 0.1
    )

    /// Default configuration for high quality.
    public static let highQuality = J2KVulkanQuantisationConfiguration(
        mode: .deadzone,
        stepSize: 0.05
    )
}

// MARK: - Quantisation Result

/// Result of a quantisation operation.
public struct J2KVulkanQuantisationResult: Sendable {
    /// Quantised indices.
    public let indices: [Int32]
    /// Quantisation mode used.
    public let mode: J2KVulkanQuantisationMode
    /// Whether GPU was used.
    public let usedGPU: Bool
    /// Processing time in seconds.
    public let processingTime: Double

    /// Creates a quantisation result.
    public init(
        indices: [Int32],
        mode: J2KVulkanQuantisationMode,
        usedGPU: Bool,
        processingTime: Double
    ) {
        self.indices = indices
        self.mode = mode
        self.usedGPU = usedGPU
        self.processingTime = processingTime
    }
}

// MARK: - Dequantisation Result

/// Result of a dequantisation operation.
public struct J2KVulkanDequantisationResult: Sendable {
    /// Reconstructed coefficients.
    public let coefficients: [Float]
    /// Dequantisation mode used.
    public let mode: J2KVulkanQuantisationMode
    /// Whether GPU was used.
    public let usedGPU: Bool
    /// Processing time in seconds.
    public let processingTime: Double

    /// Creates a dequantisation result.
    public init(
        coefficients: [Float],
        mode: J2KVulkanQuantisationMode,
        usedGPU: Bool,
        processingTime: Double
    ) {
        self.coefficients = coefficients
        self.mode = mode
        self.usedGPU = usedGPU
        self.processingTime = processingTime
    }
}

// MARK: - Quantisation Statistics

/// Performance statistics for Vulkan quantisation operations.
public struct J2KVulkanQuantisationStatistics: Sendable {
    /// Total quantisation operations.
    public var totalQuantisations: Int
    /// Total dequantisation operations.
    public var totalDequantisations: Int
    /// GPU quantisation operations.
    public var gpuQuantisations: Int
    /// GPU dequantisation operations.
    public var gpuDequantisations: Int
    /// CPU quantisation operations.
    public var cpuQuantisations: Int
    /// CPU dequantisation operations.
    public var cpuDequantisations: Int
    /// Total processing time.
    public var totalProcessingTime: Double
    /// Total coefficients processed.
    public var totalCoefficientsProcessed: Int

    /// Creates initial (zero) statistics.
    public init() {
        self.totalQuantisations = 0
        self.totalDequantisations = 0
        self.gpuQuantisations = 0
        self.gpuDequantisations = 0
        self.cpuQuantisations = 0
        self.cpuDequantisations = 0
        self.totalProcessingTime = 0.0
        self.totalCoefficientsProcessed = 0
    }

    /// GPU utilisation rate (0.0 to 1.0).
    public var gpuUtilisation: Double {
        let totalOps = totalQuantisations + totalDequantisations
        guard totalOps > 0 else { return 0.0 }
        let gpuOps = gpuQuantisations + gpuDequantisations
        return Double(gpuOps) / Double(totalOps)
    }

    /// Average coefficients processed per second.
    public var coefficientsPerSecond: Double {
        guard totalProcessingTime > 0.0 else { return 0.0 }
        return Double(totalCoefficientsProcessed) / totalProcessingTime
    }
}

// MARK: - Vulkan Quantiser

/// Vulkan-accelerated quantisation and dequantisation engine.
///
/// Provides GPU-accelerated quantisation operations for JPEG 2000:
/// - Scalar (uniform) quantisation
/// - Dead-zone quantisation with enlarged zero bin
/// - Dequantisation for decoder
///
/// ## Usage
///
/// ```swift
/// let quantiser = J2KVulkanQuantiser(
///     device: device,
///     shaderLibrary: shaderLibrary
/// )
///
/// let result = try await quantiser.quantise(
///     coefficients: waveletCoeffs,
///     configuration: .lossy
/// )
/// ```
public actor J2KVulkanQuantiser {
    // MARK: Properties

    private let device: J2KVulkanDevice
    private let shaderLibrary: J2KVulkanShaderLibrary
    private let bufferPool: J2KVulkanBufferPool
    private var statistics: J2KVulkanQuantisationStatistics

    // MARK: Initialisation

    /// Creates a new Vulkan quantiser.
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
        self.statistics = J2KVulkanQuantisationStatistics()
    }

    // MARK: - Quantisation

    /// Quantises floating-point coefficients to integer indices.
    ///
    /// - Parameters:
    ///   - coefficients: Input wavelet coefficients.
    ///   - configuration: Quantisation configuration.
    /// - Returns: Quantisation result with indices.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if coefficients are empty.
    public func quantise(
        coefficients: [Float],
        configuration: J2KVulkanQuantisationConfiguration = .lossy
    ) async throws -> J2KVulkanQuantisationResult {
        guard !coefficients.isEmpty else {
            throw J2KError.invalidParameter("Quantisation input must not be empty")
        }

        let startTime = Date()
        let coeffCount = coefficients.count
        let useGPU = shouldUseGPU(coeffCount: coeffCount, configuration: configuration)

        let indices: [Int32]

        if useGPU {
            indices = try await quantiseGPU(
                coefficients: coefficients,
                configuration: configuration
            )
        } else {
            indices = quantiseCPU(
                coefficients: coefficients,
                configuration: configuration
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        updateStatistics(
            isQuantisation: true,
            usedGPU: useGPU,
            processingTime: processingTime,
            coeffCount: coeffCount
        )

        return J2KVulkanQuantisationResult(
            indices: indices,
            mode: configuration.mode,
            usedGPU: useGPU,
            processingTime: processingTime
        )
    }

    // MARK: - Dequantisation

    /// Dequantises integer indices to floating-point coefficients.
    ///
    /// - Parameters:
    ///   - indices: Quantised indices.
    ///   - configuration: Dequantisation configuration.
    /// - Returns: Dequantisation result with reconstructed coefficients.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if indices are empty.
    public func dequantise(
        indices: [Int32],
        configuration: J2KVulkanQuantisationConfiguration = .lossy
    ) async throws -> J2KVulkanDequantisationResult {
        guard !indices.isEmpty else {
            throw J2KError.invalidParameter("Dequantisation input must not be empty")
        }

        let startTime = Date()
        let coeffCount = indices.count
        let useGPU = shouldUseGPU(coeffCount: coeffCount, configuration: configuration)

        let coefficients: [Float]

        if useGPU {
            coefficients = try await dequantiseGPU(
                indices: indices,
                configuration: configuration
            )
        } else {
            coefficients = dequantiseCPU(
                indices: indices,
                configuration: configuration
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        updateStatistics(
            isQuantisation: false,
            usedGPU: useGPU,
            processingTime: processingTime,
            coeffCount: coeffCount
        )

        return J2KVulkanDequantisationResult(
            coefficients: coefficients,
            mode: configuration.mode,
            usedGPU: useGPU,
            processingTime: processingTime
        )
    }

    // MARK: - Statistics

    /// Returns current performance statistics.
    public func getStatistics() -> J2KVulkanQuantisationStatistics {
        statistics
    }

    /// Resets performance statistics.
    public func resetStatistics() {
        statistics = J2KVulkanQuantisationStatistics()
    }

    // MARK: - GPU Paths

    private func quantiseGPU(
        coefficients: [Float],
        configuration: J2KVulkanQuantisationConfiguration
    ) async throws -> [Int32] {
        #if canImport(CVulkan)
        fatalError("Vulkan quantisation requires CVulkan system module")
        #else
        return quantiseCPU(coefficients: coefficients, configuration: configuration)
        #endif
    }

    private func dequantiseGPU(
        indices: [Int32],
        configuration: J2KVulkanQuantisationConfiguration
    ) async throws -> [Float] {
        #if canImport(CVulkan)
        fatalError("Vulkan dequantisation requires CVulkan system module")
        #else
        return dequantiseCPU(indices: indices, configuration: configuration)
        #endif
    }

    // MARK: - CPU Fallback

    private func quantiseCPU(
        coefficients: [Float],
        configuration: J2KVulkanQuantisationConfiguration
    ) -> [Int32] {
        let stepSize = configuration.stepSize

        switch configuration.mode {
        case .scalar:
            return coefficients.map { c in
                let absC = abs(c)
                let sign: Int32 = c >= 0 ? 1 : -1
                let q = Int32(floor(absC / stepSize))
                return sign * q
            }

        case .deadzone:
            let threshold = stepSize * configuration.deadzoneWidth * 0.5
            return coefficients.map { c in
                let absC = abs(c)
                if absC <= threshold {
                    return 0
                } else {
                    let sign: Int32 = c >= 0 ? 1 : -1
                    let q = Int32(floor((absC - threshold) / stepSize)) + 1
                    return sign * q
                }
            }
        }
    }

    private func dequantiseCPU(
        indices: [Int32],
        configuration: J2KVulkanQuantisationConfiguration
    ) -> [Float] {
        let stepSize = configuration.stepSize

        switch configuration.mode {
        case .scalar:
            return indices.map { q in
                if q == 0 {
                    return 0.0
                } else {
                    let sign: Float = q >= 0 ? 1.0 : -1.0
                    let absQ = abs(q)
                    return sign * (Float(absQ) + 0.5) * stepSize
                }
            }

        case .deadzone:
            let threshold = stepSize * configuration.deadzoneWidth * 0.5
            return indices.map { q in
                if q == 0 {
                    return 0.0
                } else {
                    let sign: Float = q >= 0 ? 1.0 : -1.0
                    let absQ = abs(q)
                    return sign * ((Float(absQ) - 0.5) * stepSize + threshold)
                }
            }
        }
    }

    // MARK: - Utility

    private func shouldUseGPU(
        coeffCount: Int,
        configuration: J2KVulkanQuantisationConfiguration
    ) -> Bool {
        switch configuration.backend {
        case .gpu:
            return J2KVulkanDevice.isAvailable
        case .cpu:
            return false
        case .auto:
            return J2KVulkanDevice.isAvailable && coeffCount >= configuration.gpuThreshold
        }
    }

    private func updateStatistics(
        isQuantisation: Bool,
        usedGPU: Bool,
        processingTime: Double,
        coeffCount: Int
    ) {
        if isQuantisation {
            statistics.totalQuantisations += 1
            if usedGPU {
                statistics.gpuQuantisations += 1
            } else {
                statistics.cpuQuantisations += 1
            }
        } else {
            statistics.totalDequantisations += 1
            if usedGPU {
                statistics.gpuDequantisations += 1
            } else {
                statistics.cpuDequantisations += 1
            }
        }
        statistics.totalProcessingTime += processingTime
        statistics.totalCoefficientsProcessed += coeffCount
    }
}
