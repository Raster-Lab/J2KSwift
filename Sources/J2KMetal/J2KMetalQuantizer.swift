//
// J2KMetalQuantizer.swift
// J2KSwift
//
// J2KMetalQuantizer.swift
// J2KSwift
//
// Metal-accelerated quantization and dequantization for JPEG 2000.
//

import Foundation
import J2KCore

#if canImport(Metal)
import Metal
#endif

// MARK: - Quantization Mode

/// Metal-accelerated quantization mode.
public enum J2KMetalQuantizationMode: Sendable {
    /// Scalar (uniform) quantization.
    case scalar
    /// Dead-zone quantization with enlarged zero bin.
    case deadzone
}

// MARK: - Quantization Backend

/// Backend selection for quantization computation.
public enum J2KMetalQuantizationBackend: Sendable {
    /// Force GPU execution via Metal.
    case gpu
    /// Force CPU execution (software fallback).
    case cpu
    /// Automatically choose based on coefficient count.
    case auto
}

// MARK: - Quantization Configuration

/// Configuration for Metal-accelerated quantization.
public struct J2KMetalQuantizationConfiguration: Sendable {
    /// Quantization mode.
    public var mode: J2KMetalQuantizationMode

    /// Base quantization step size.
    public var stepSize: Float

    /// Deadzone width multiplier (for deadzone mode).
    public var deadzoneWidth: Float

    /// Minimum coefficient count to prefer GPU over CPU.
    public var gpuThreshold: Int

    /// Backend selection strategy.
    public var backend: J2KMetalQuantizationBackend

    /// Creates a Metal quantization configuration.
    ///
    /// - Parameters:
    ///   - mode: Quantization mode. Defaults to `.deadzone`.
    ///   - stepSize: Base step size. Defaults to `0.1`.
    ///   - deadzoneWidth: Deadzone width multiplier. Defaults to `1.5`.
    ///   - gpuThreshold: Minimum coefficients to prefer GPU. Defaults to `1024`.
    ///   - backend: Backend selection. Defaults to `.auto`.
    public init(
        mode: J2KMetalQuantizationMode = .deadzone,
        stepSize: Float = 0.1,
        deadzoneWidth: Float = 1.5,
        gpuThreshold: Int = 1024,
        backend: J2KMetalQuantizationBackend = .auto
    ) {
        self.mode = mode
        self.stepSize = stepSize
        self.deadzoneWidth = deadzoneWidth
        self.gpuThreshold = gpuThreshold
        self.backend = backend
    }

    /// Default configuration for lossy compression.
    public static let lossy = J2KMetalQuantizationConfiguration(
        mode: .deadzone,
        stepSize: 0.1
    )

    /// Default configuration for high quality.
    public static let highQuality = J2KMetalQuantizationConfiguration(
        mode: .deadzone,
        stepSize: 0.05
    )
}

// MARK: - Quantization Result

/// Result of a quantization operation.
public struct J2KMetalQuantizationResult: Sendable {
    /// Quantized indices.
    public let indices: [Int32]
    /// Quantization mode used.
    public let mode: J2KMetalQuantizationMode
    /// Whether GPU was used.
    public let usedGPU: Bool
    /// Processing time in seconds.
    public let processingTime: Double

    /// Creates a quantization result.
    public init(
        indices: [Int32],
        mode: J2KMetalQuantizationMode,
        usedGPU: Bool,
        processingTime: Double
    ) {
        self.indices = indices
        self.mode = mode
        self.usedGPU = usedGPU
        self.processingTime = processingTime
    }
}

// MARK: - Dequantization Result

/// Result of a dequantization operation.
public struct J2KMetalDequantizationResult: Sendable {
    /// Reconstructed coefficients.
    public let coefficients: [Float]
    /// Dequantization mode used.
    public let mode: J2KMetalQuantizationMode
    /// Whether GPU was used.
    public let usedGPU: Bool
    /// Processing time in seconds.
    public let processingTime: Double

    /// Creates a dequantization result.
    public init(
        coefficients: [Float],
        mode: J2KMetalQuantizationMode,
        usedGPU: Bool,
        processingTime: Double
    ) {
        self.coefficients = coefficients
        self.mode = mode
        self.usedGPU = usedGPU
        self.processingTime = processingTime
    }
}

// MARK: - Quantization Statistics

/// Performance statistics for Metal quantization operations.
public struct J2KMetalQuantizationStatistics: Sendable {
    /// Total quantization operations.
    public var totalQuantizations: Int
    /// Total dequantization operations.
    public var totalDequantizations: Int
    /// GPU quantization operations.
    public var gpuQuantizations: Int
    /// GPU dequantization operations.
    public var gpuDequantizations: Int
    /// CPU quantization operations.
    public var cpuQuantizations: Int
    /// CPU dequantization operations.
    public var cpuDequantizations: Int
    /// Total processing time.
    public var totalProcessingTime: Double
    /// Total coefficients processed.
    public var totalCoefficientsProcessed: Int

    /// Creates initial (zero) statistics.
    public init() {
        self.totalQuantizations = 0
        self.totalDequantizations = 0
        self.gpuQuantizations = 0
        self.gpuDequantizations = 0
        self.cpuQuantizations = 0
        self.cpuDequantizations = 0
        self.totalProcessingTime = 0.0
        self.totalCoefficientsProcessed = 0
    }

    /// GPU utilization rate (0.0 to 1.0).
    public var gpuUtilization: Double {
        let totalOps = totalQuantizations + totalDequantizations
        guard totalOps > 0 else { return 0.0 }
        let gpuOps = gpuQuantizations + gpuDequantizations
        return Double(gpuOps) / Double(totalOps)
    }

    /// Average coefficients processed per second.
    public var coefficientsPerSecond: Double {
        guard totalProcessingTime > 0.0 else { return 0.0 }
        return Double(totalCoefficientsProcessed) / totalProcessingTime
    }
}

#if canImport(Metal)

// MARK: - Metal Quantizer Actor

/// Metal-accelerated quantization and dequantization engine.
///
/// Provides GPU-accelerated quantization operations for JPEG 2000:
/// - Scalar (uniform) quantization
/// - Dead-zone quantization with enlarged zero bin
/// - Dequantization for decoder
/// - Visual frequency weighting
/// - Perceptual quantization
///
/// ## Usage
///
/// ```swift
/// let quantizer = try await J2KMetalQuantizer(
///     device: device,
///     shaderLibrary: shaderLibrary
/// )
///
/// let result = try await quantizer.quantize(
///     coefficients: waveletCoeffs,
///     configuration: .lossy
/// )
/// ```
public actor J2KMetalQuantizer {
    // MARK: Properties

    private let device: J2KMetalDevice
    private let shaderLibrary: J2KMetalShaderLibrary
    private let bufferPool: J2KMetalBufferPool
    private var statistics: J2KMetalQuantizationStatistics

    // MARK: Initialization

    /// Creates a new Metal quantizer.
    ///
    /// - Parameters:
    ///   - device: The Metal device to use.
    ///   - shaderLibrary: The shader library for pipeline creation.
    /// - Throws: ``J2KError/metalNotAvailable`` if Metal is unavailable.
    public init(
        device: J2KMetalDevice,
        shaderLibrary: J2KMetalShaderLibrary
    ) async throws {
        self.device = device
        self.shaderLibrary = shaderLibrary
        self.bufferPool = try await J2KMetalBufferPool(device: device)
        self.statistics = J2KMetalQuantizationStatistics()
    }

    // MARK: - Quantization

    /// Quantizes floating-point coefficients to integer indices.
    ///
    /// - Parameters:
    ///   - coefficients: Input wavelet coefficients.
    ///   - configuration: Quantization configuration.
    /// - Returns: Quantization result with indices.
    /// - Throws: ``J2KError/metalOperationFailed(_:)`` if GPU operation fails.
    public func quantize(
        coefficients: [Float],
        configuration: J2KMetalQuantizationConfiguration = .lossy
    ) async throws -> J2KMetalQuantizationResult {
        let startTime = Date()
        let coeffCount = coefficients.count

        // Determine backend
        let useGPU = shouldUseGPU(coeffCount: coeffCount, configuration: configuration)

        let indices: [Int32]

        if useGPU {
            indices = try await quantizeGPU(
                coefficients: coefficients,
                configuration: configuration
            )
        } else {
            indices = quantizeCPU(
                coefficients: coefficients,
                configuration: configuration
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        updateStatistics(
            isQuantization: true,
            usedGPU: useGPU,
            processingTime: processingTime,
            coeffCount: coeffCount
        )

        return J2KMetalQuantizationResult(
            indices: indices,
            mode: configuration.mode,
            usedGPU: useGPU,
            processingTime: processingTime
        )
    }

    /// Quantizes 2D coefficient array.
    ///
    /// - Parameters:
    ///   - coefficients: 2D input coefficients.
    ///   - configuration: Quantization configuration.
    /// - Returns: 2D quantized indices.
    /// - Throws: ``J2KError/metalOperationFailed(_:)`` if GPU operation fails.
    public func quantize2D(
        coefficients: [[Float]],
        configuration: J2KMetalQuantizationConfiguration = .lossy
    ) async throws -> [[Int32]] {
        let flatCoeffs = coefficients.flatMap { $0 }
        let height = coefficients.count
        let width = height > 0 ? coefficients[0].count : 0

        let result = try await quantize(
            coefficients: flatCoeffs,
            configuration: configuration
        )

        // Reshape to 2D
        var output = Array(repeating: Array(repeating: Int32(0), count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                output[y][x] = result.indices[y * width + x]
            }
        }

        return output
    }

    // MARK: - Dequantization

    /// Dequantizes integer indices to floating-point coefficients.
    ///
    /// - Parameters:
    ///   - indices: Quantized indices.
    ///   - configuration: Dequantization configuration (uses same params as quantization).
    /// - Returns: Dequantization result with reconstructed coefficients.
    /// - Throws: ``J2KError/metalOperationFailed(_:)`` if GPU operation fails.
    public func dequantize(
        indices: [Int32],
        configuration: J2KMetalQuantizationConfiguration = .lossy
    ) async throws -> J2KMetalDequantizationResult {
        let startTime = Date()
        let coeffCount = indices.count

        // Determine backend
        let useGPU = shouldUseGPU(coeffCount: coeffCount, configuration: configuration)

        let coefficients: [Float]

        if useGPU {
            coefficients = try await dequantizeGPU(
                indices: indices,
                configuration: configuration
            )
        } else {
            coefficients = dequantizeCPU(
                indices: indices,
                configuration: configuration
            )
        }

        let processingTime = Date().timeIntervalSince(startTime)

        updateStatistics(
            isQuantization: false,
            usedGPU: useGPU,
            processingTime: processingTime,
            coeffCount: coeffCount
        )

        return J2KMetalDequantizationResult(
            coefficients: coefficients,
            mode: configuration.mode,
            usedGPU: useGPU,
            processingTime: processingTime
        )
    }

    /// Dequantizes 2D index array.
    ///
    /// - Parameters:
    ///   - indices: 2D quantized indices.
    ///   - configuration: Dequantization configuration.
    /// - Returns: 2D reconstructed coefficients.
    /// - Throws: ``J2KError/metalOperationFailed(_:)`` if GPU operation fails.
    public func dequantize2D(
        indices: [[Int32]],
        configuration: J2KMetalQuantizationConfiguration = .lossy
    ) async throws -> [[Float]] {
        let flatIndices = indices.flatMap { $0 }
        let height = indices.count
        let width = height > 0 ? indices[0].count : 0

        let result = try await dequantize(
            indices: flatIndices,
            configuration: configuration
        )

        // Reshape to 2D
        var output = Array(repeating: Array(repeating: Float(0), count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                output[y][x] = result.coefficients[y * width + x]
            }
        }

        return output
    }

    // MARK: - Statistics

    /// Returns current performance statistics.
    public func getStatistics() -> J2KMetalQuantizationStatistics {
        statistics
    }

    /// Resets performance statistics.
    public func resetStatistics() {
        statistics = J2KMetalQuantizationStatistics()
    }

    // MARK: - Private Methods (GPU)

    private func quantizeGPU(
        coefficients: [Float],
        configuration: J2KMetalQuantizationConfiguration
    ) async throws -> [Int32] {
        let mtlDevice = try await device.metalDevice()
        let commandQueue = try await device.commandQueue()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.metalOperationFailed("Failed to create command buffer/encoder")
        }

        // Get pipeline state based on mode
        let shaderFunction: J2KMetalShaderFunction
        switch configuration.mode {
        case .scalar:
            shaderFunction = .quantizeScalar
        case .deadzone:
            shaderFunction = .quantizeDeadzone
        }

        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunction)
        computeEncoder.setComputePipelineState(pipeline)

        // Allocate buffers
        let coeffCount = coefficients.count
        let inputBuffer = try await bufferPool.allocateBuffer(
            size: coeffCount * MemoryLayout<Float>.size,
            storageMode: .shared
        )
        let outputBuffer = try await bufferPool.allocateBuffer(
            size: coeffCount * MemoryLayout<Int32>.size,
            storageMode: .shared
        )

        // Copy data
        memcpy(inputBuffer.contents(), coefficients, coeffCount * MemoryLayout<Float>.size)

        // Set buffers
        computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)

        // Set parameters
        var stepSize = configuration.stepSize
        var deadzoneWidth = configuration.deadzoneWidth
        var count = UInt32(coeffCount)

        computeEncoder.setBytes(&stepSize, length: MemoryLayout<Float>.size, index: 2)

        if configuration.mode == .deadzone {
            computeEncoder.setBytes(&deadzoneWidth, length: MemoryLayout<Float>.size, index: 3)
            computeEncoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 4)
        } else {
            computeEncoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 3)
        }

        // Dispatch
        let threadgroupSize = 256
        let threadgroups = (coeffCount + threadgroupSize - 1) / threadgroupSize
        computeEncoder.dispatchThreadgroups(
            MTLSize(width: threadgroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
        )

        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read results
        let outputPtr = outputBuffer.contents().bindMemory(to: Int32.self, capacity: coeffCount)
        return Array(UnsafeBufferPointer(start: outputPtr, count: coeffCount))
    }

    private func dequantizeGPU(
        indices: [Int32],
        configuration: J2KMetalQuantizationConfiguration
    ) async throws -> [Float] {
        let mtlDevice = try await device.metalDevice()
        let commandQueue = try await device.commandQueue()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.metalOperationFailed("Failed to create command buffer/encoder")
        }

        // Get pipeline state based on mode
        let shaderFunction: J2KMetalShaderFunction
        switch configuration.mode {
        case .scalar:
            shaderFunction = .dequantizeScalar
        case .deadzone:
            shaderFunction = .dequantizeDeadzone
        }

        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunction)
        computeEncoder.setComputePipelineState(pipeline)

        // Allocate buffers
        let coeffCount = indices.count
        let inputBuffer = try await bufferPool.allocateBuffer(
            size: coeffCount * MemoryLayout<Int32>.size,
            storageMode: .shared
        )
        let outputBuffer = try await bufferPool.allocateBuffer(
            size: coeffCount * MemoryLayout<Float>.size,
            storageMode: .shared
        )

        // Copy data
        memcpy(inputBuffer.contents(), indices, coeffCount * MemoryLayout<Int32>.size)

        // Set buffers
        computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)

        // Set parameters
        var stepSize = configuration.stepSize
        var deadzoneWidth = configuration.deadzoneWidth
        var count = UInt32(coeffCount)

        computeEncoder.setBytes(&stepSize, length: MemoryLayout<Float>.size, index: 2)

        if configuration.mode == .deadzone {
            computeEncoder.setBytes(&deadzoneWidth, length: MemoryLayout<Float>.size, index: 3)
            computeEncoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 4)
        } else {
            computeEncoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 3)
        }

        // Dispatch
        let threadgroupSize = 256
        let threadgroups = (coeffCount + threadgroupSize - 1) / threadgroupSize
        computeEncoder.dispatchThreadgroups(
            MTLSize(width: threadgroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
        )

        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read results
        let outputPtr = outputBuffer.contents().bindMemory(to: Float.self, capacity: coeffCount)
        return Array(UnsafeBufferPointer(start: outputPtr, count: coeffCount))
    }

    // MARK: - Private Methods (CPU Fallback)

    private func quantizeCPU(
        coefficients: [Float],
        configuration: J2KMetalQuantizationConfiguration
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

    private func dequantizeCPU(
        indices: [Int32],
        configuration: J2KMetalQuantizationConfiguration
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
                    return (Float(absQ) + 0.5 * sign) * stepSize
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
        configuration: J2KMetalQuantizationConfiguration
    ) -> Bool {
        switch configuration.backend {
        case .gpu:
            return true
        case .cpu:
            return false
        case .auto:
            return coeffCount >= configuration.gpuThreshold
        }
    }

    private func updateStatistics(
        isQuantization: Bool,
        usedGPU: Bool,
        processingTime: Double,
        coeffCount: Int
    ) {
        if isQuantization {
            statistics.totalQuantizations += 1
            if usedGPU {
                statistics.gpuQuantizations += 1
            } else {
                statistics.cpuQuantizations += 1
            }
        } else {
            statistics.totalDequantizations += 1
            if usedGPU {
                statistics.gpuDequantizations += 1
            } else {
                statistics.cpuDequantizations += 1
            }
        }
        statistics.totalProcessingTime += processingTime
        statistics.totalCoefficientsProcessed += coeffCount
    }
}

#endif // canImport(Metal)
