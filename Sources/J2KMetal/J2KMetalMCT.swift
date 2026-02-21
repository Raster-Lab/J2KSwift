//
// J2KMetalMCT.swift
// J2KSwift
//
// J2KMetalMCT.swift
// J2KSwift
//
// Metal-accelerated multi-component transforms for JPEG 2000.
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

// MARK: - MCT Backend

/// Backend selection for MCT computation.
///
/// Controls whether the transform runs on GPU (Metal) or CPU,
/// with automatic selection based on sample count and matrix size.
public enum J2KMetalMCTBackend: Sendable {
    /// Force GPU execution via Metal.
    case gpu
    /// Force CPU execution (software fallback).
    case cpu
    /// Automatically choose based on data size and GPU threshold.
    case auto
}

// MARK: - MCT Configuration

/// Configuration for Metal-accelerated MCT operations.
///
/// Controls backend selection, batch processing, and GPU dispatch
/// parameters for optimal multi-component transform performance.
public struct J2KMetalMCTConfiguration: Sendable {
    /// Minimum sample count to prefer GPU over CPU.
    public var gpuThreshold: Int

    /// Maximum batch size for GPU processing.
    public var batchSize: Int

    /// Creates a Metal MCT configuration.
    ///
    /// - Parameters:
    ///   - gpuThreshold: Minimum samples to prefer GPU. Defaults to `512`.
    ///   - batchSize: Maximum batch size. Defaults to `4096`.
    public init(
        gpuThreshold: Int = 512,
        batchSize: Int = 4096
    ) {
        self.gpuThreshold = gpuThreshold
        self.batchSize = batchSize
    }

    /// Default MCT configuration.
    public static let `default` = J2KMetalMCTConfiguration()

    /// High-performance configuration with lower GPU threshold.
    public static let highPerformance = J2KMetalMCTConfiguration(
        gpuThreshold: 256,
        batchSize: 8192
    )
}

// MARK: - MCT Result

/// Result of a multi-component transform operation.
///
/// Contains the transformed components and metadata about how the
/// transform was performed.
public struct J2KMetalMCTResult: Sendable {
    /// Transformed component data, one array per component.
    public let components: [[Float]]
    /// Number of components.
    public let componentCount: Int
    /// Number of samples per component.
    public let sampleCount: Int
    /// Whether the GPU was used for this operation.
    public let usedGPU: Bool

    /// Creates an MCT result.
    public init(
        components: [[Float]],
        componentCount: Int,
        sampleCount: Int,
        usedGPU: Bool
    ) {
        self.components = components
        self.componentCount = componentCount
        self.sampleCount = sampleCount
        self.usedGPU = usedGPU
    }
}

// MARK: - MCT Statistics

/// Performance statistics for Metal MCT operations.
///
/// Tracks timing, backend usage, and throughput for monitoring
/// and optimisation purposes.
public struct J2KMetalMCTStatistics: Sendable {
    /// Total number of MCT operations performed.
    public var totalOperations: Int
    /// Number of operations that ran on GPU.
    public var gpuOperations: Int
    /// Number of operations that fell back to CPU.
    public var cpuOperations: Int
    /// Total processing time in seconds.
    public var totalProcessingTime: Double
    /// Total samples processed across all operations.
    public var totalSamplesProcessed: Int
    /// Number of 3×3 fast-path operations.
    public var fastPath3x3Operations: Int
    /// Number of 4×4 fast-path operations.
    public var fastPath4x4Operations: Int

    /// Creates initial (zero) statistics.
    public init() {
        self.totalOperations = 0
        self.gpuOperations = 0
        self.cpuOperations = 0
        self.totalProcessingTime = 0.0
        self.totalSamplesProcessed = 0
        self.fastPath3x3Operations = 0
        self.fastPath4x4Operations = 0
    }

    /// GPU utilization rate as a percentage (0.0 to 1.0).
    public var gpuUtilization: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(gpuOperations) / Double(totalOperations)
    }

    /// Fast-path utilization as a percentage (0.0 to 1.0).
    public var fastPathUtilization: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(fastPath3x3Operations + fastPath4x4Operations) / Double(totalOperations)
    }
}

// MARK: - Metal MCT

/// Metal-accelerated multi-component transforms for JPEG 2000.
///
/// `J2KMetalMCT` provides GPU-accelerated N×N matrix-based component
/// transforms using Metal compute shaders. It supports general N×N
/// transforms with optimised 3×3 and 4×4 fast paths, batch processing,
/// and fused colour+MCT operations.
///
/// ## Usage
///
/// ```swift
/// let mct = J2KMetalMCT()
///
/// // Forward MCT with 3×3 matrix
/// let matrix: [Float] = [
///     0.299, 0.587, 0.114,
///     -0.16875, -0.33126, 0.5,
///     0.5, -0.41869, -0.08131
/// ]
/// let result = try await mct.forwardTransform(
///     components: [redData, greenData, blueData],
///     matrix: matrix,
///     componentCount: 3
/// )
/// ```
///
/// ## Performance
///
/// - 3×3 fast path: Unrolled computation avoiding loop overhead
/// - 4×4 fast path: Optimised for 4-component images
/// - General N×N: Supports arbitrary component counts up to 16
/// - Target: 10-25× speedup vs CPU on Apple Silicon
public actor J2KMetalMCT {
    /// Whether Metal MCT is available on this platform.
    public static var isAvailable: Bool {
        J2KMetalDevice.isAvailable
    }

    /// The MCT configuration.
    public let configuration: J2KMetalMCTConfiguration

    /// The Metal device for GPU operations.
    private let metalDevice: J2KMetalDevice

    /// The buffer pool for GPU memory management.
    private let bufferPool: J2KMetalBufferPool

    /// The shader library for compute kernels.
    private let shaderLibrary: J2KMetalShaderLibrary

    /// Whether the Metal backend has been initialised.
    private var isInitialized = false

    /// Processing statistics.
    private var _statistics = J2KMetalMCTStatistics()

    /// Creates a Metal MCT instance.
    ///
    /// - Parameters:
    ///   - configuration: The MCT configuration. Defaults to `.default`.
    ///   - device: The Metal device manager. A new instance is created if not provided.
    ///   - bufferPool: The buffer pool. A new instance is created if not provided.
    ///   - shaderLibrary: The shader library. A new instance is created if not provided.
    public init(
        configuration: J2KMetalMCTConfiguration = .default,
        device: J2KMetalDevice? = nil,
        bufferPool: J2KMetalBufferPool? = nil,
        shaderLibrary: J2KMetalShaderLibrary? = nil
    ) {
        self.configuration = configuration
        self.metalDevice = device ?? J2KMetalDevice()
        self.bufferPool = bufferPool ?? J2KMetalBufferPool()
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    /// Initializes the Metal backend for MCT operations.
    ///
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Metal is not available.
    /// - Throws: ``J2KError/internalError(_:)`` if initialisation fails.
    public func initialize() async throws {
        guard !isInitialized else { return }

        try await metalDevice.initialize()
        #if canImport(Metal)
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)
        #endif
        isInitialized = true
    }

    /// Returns the current processing statistics.
    public func statistics() -> J2KMetalMCTStatistics {
        _statistics
    }

    /// Resets the processing statistics.
    public func resetStatistics() {
        _statistics = J2KMetalMCTStatistics()
    }

    /// Determines the best backend for the given parameters.
    ///
    /// - Parameters:
    ///   - sampleCount: Number of samples per component.
    ///   - componentCount: Number of components.
    ///   - backend: Requested backend preference.
    /// - Returns: The effective backend to use.
    public func effectiveBackend(
        sampleCount: Int,
        componentCount: Int,
        backend: J2KMetalMCTBackend = .auto
    ) -> J2KMetalMCTBackend {
        switch backend {
        case .gpu:
            return J2KMetalMCT.isAvailable ? .gpu : .cpu
        case .cpu:
            return .cpu
        case .auto:
            if !J2KMetalMCT.isAvailable {
                return .cpu
            }
            return sampleCount >= configuration.gpuThreshold ? .gpu : .cpu
        }
    }

    // MARK: - Forward Transform

    /// Performs a forward MCT using the given matrix.
    ///
    /// Transforms N components using an N×N matrix. Uses optimised fast
    /// paths for 3×3 and 4×4 matrices when available.
    ///
    /// - Parameters:
    ///   - components: Input component data, one array per component.
    ///   - matrix: Transform matrix as a flat row-major Float array (N×N).
    ///   - componentCount: Number of components (N).
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The MCT result with transformed components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func forwardTransform(
        components: [[Float]],
        matrix: [Float],
        componentCount: Int,
        backend: J2KMetalMCTBackend = .auto
    ) async throws -> J2KMetalMCTResult {
        guard componentCount >= 2 else {
            throw J2KError.invalidParameter(
                "Component count must be at least 2, got \(componentCount)"
            )
        }
        guard components.count == componentCount else {
            throw J2KError.invalidParameter(
                "Expected \(componentCount) components, got \(components.count)"
            )
        }
        guard matrix.count == componentCount * componentCount else {
            throw J2KError.invalidParameter(
                "Matrix must be \(componentCount)×\(componentCount) (\(componentCount * componentCount) elements), got \(matrix.count)"
            )
        }
        let sampleCount = components[0].count
        guard sampleCount > 0 else {
            throw J2KError.invalidParameter("Components must not be empty")
        }
        for i in 1..<componentCount {
            guard components[i].count == sampleCount else {
                throw J2KError.invalidParameter(
                    "All components must have the same length"
                )
            }
        }
        guard componentCount <= 16 else {
            throw J2KError.invalidParameter(
                "Component count must not exceed 16, got \(componentCount)"
            )
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1
        _statistics.totalSamplesProcessed += sampleCount * componentCount

        let effective = effectiveBackend(
            sampleCount: sampleCount,
            componentCount: componentCount,
            backend: backend
        )

        let result: J2KMetalMCTResult
        if effective == .gpu {
            result = try await forwardTransformGPU(
                components: components, matrix: matrix,
                componentCount: componentCount, sampleCount: sampleCount
            )
            _statistics.gpuOperations += 1
        } else {
            result = forwardTransformCPU(
                components: components, matrix: matrix,
                componentCount: componentCount, sampleCount: sampleCount
            )
            _statistics.cpuOperations += 1
        }

        if componentCount == 3 {
            _statistics.fastPath3x3Operations += 1
        } else if componentCount == 4 {
            _statistics.fastPath4x4Operations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - Inverse Transform

    /// Performs an inverse MCT using the given matrix.
    ///
    /// Applies the inverse matrix to recover original components.
    /// The caller must provide the inverse of the forward transform matrix.
    ///
    /// - Parameters:
    ///   - components: Transformed component data.
    ///   - matrix: Inverse transform matrix as a flat row-major Float array.
    ///   - componentCount: Number of components.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The MCT result with recovered components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func inverseTransform(
        components: [[Float]],
        matrix: [Float],
        componentCount: Int,
        backend: J2KMetalMCTBackend = .auto
    ) async throws -> J2KMetalMCTResult {
        // Inverse transform uses the same matrix-vector multiply,
        // the caller provides the inverse matrix.
        try await forwardTransform(
            components: components,
            matrix: matrix,
            componentCount: componentCount,
            backend: backend
        )
    }

    // MARK: - Fused Colour + MCT

    /// Performs a fused colour transform and MCT in a single GPU pass.
    ///
    /// Combines a colour space transform and an MCT into one operation,
    /// reducing memory bandwidth by avoiding intermediate storage.
    ///
    /// - Parameters:
    ///   - components: Input component data.
    ///   - colorMatrix: Colour transform matrix (N×N flat row-major).
    ///   - mctMatrix: MCT matrix (N×N flat row-major).
    ///   - componentCount: Number of components.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The MCT result after both transforms.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func fusedColorMCTTransform(
        components: [[Float]],
        colorMatrix: [Float],
        mctMatrix: [Float],
        componentCount: Int,
        backend: J2KMetalMCTBackend = .auto
    ) async throws -> J2KMetalMCTResult {
        guard componentCount >= 2, componentCount <= 16 else {
            throw J2KError.invalidParameter(
                "Component count must be 2-16, got \(componentCount)"
            )
        }
        guard components.count == componentCount else {
            throw J2KError.invalidParameter(
                "Expected \(componentCount) components, got \(components.count)"
            )
        }
        guard colorMatrix.count == componentCount * componentCount else {
            throw J2KError.invalidParameter("Color matrix size mismatch")
        }
        guard mctMatrix.count == componentCount * componentCount else {
            throw J2KError.invalidParameter("MCT matrix size mismatch")
        }
        let sampleCount = components[0].count
        guard sampleCount > 0 else {
            throw J2KError.invalidParameter("Components must not be empty")
        }
        for i in 1..<componentCount {
            guard components[i].count == sampleCount else {
                throw J2KError.invalidParameter(
                    "All components must have the same length"
                )
            }
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1
        _statistics.totalSamplesProcessed += sampleCount * componentCount

        let effective = effectiveBackend(
            sampleCount: sampleCount,
            componentCount: componentCount,
            backend: backend
        )

        let result: J2KMetalMCTResult
        if effective == .gpu {
            result = try await fusedColorMCTGPU(
                components: components, colorMatrix: colorMatrix,
                mctMatrix: mctMatrix, componentCount: componentCount,
                sampleCount: sampleCount
            )
            _statistics.gpuOperations += 1
        } else {
            result = fusedColorMCTCPU(
                components: components, colorMatrix: colorMatrix,
                mctMatrix: mctMatrix, componentCount: componentCount,
                sampleCount: sampleCount
            )
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - Batch Transform

    /// Performs MCT on multiple tiles in a single batch operation.
    ///
    /// Processes multiple sets of component data using the same matrix,
    /// amortizing GPU setup costs across multiple tiles.
    ///
    /// - Parameters:
    ///   - tiles: Array of component sets, each containing N component arrays.
    ///   - matrix: Transform matrix (N×N flat row-major).
    ///   - componentCount: Number of components.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: Array of MCT results, one per tile.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func batchTransform(
        tiles: [[[Float]]],
        matrix: [Float],
        componentCount: Int,
        backend: J2KMetalMCTBackend = .auto
    ) async throws -> [J2KMetalMCTResult] {
        guard !tiles.isEmpty else {
            throw J2KError.invalidParameter("Tiles must not be empty")
        }

        var results: [J2KMetalMCTResult] = []
        results.reserveCapacity(tiles.count)

        for tile in tiles {
            let result = try await forwardTransform(
                components: tile,
                matrix: matrix,
                componentCount: componentCount,
                backend: backend
            )
            results.append(result)
        }

        return results
    }

    // MARK: - Matrix Utilities

    /// Computes the product of two N×N matrices.
    ///
    /// - Parameters:
    ///   - a: First matrix (N×N flat row-major).
    ///   - b: Second matrix (N×N flat row-major).
    ///   - n: Matrix dimension.
    /// - Returns: The product matrix (N×N flat row-major).
    public func matrixMultiply(
        _ a: [Float], _ b: [Float], n: Int
    ) -> [Float] {
        var result = [Float](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in 0..<n {
                var sum: Float = 0
                for k in 0..<n {
                    sum += a[i * n + k] * b[k * n + j]
                }
                result[i * n + j] = sum
            }
        }
        return result
    }

    /// Returns the N×N identity matrix.
    ///
    /// - Parameter n: Matrix dimension.
    /// - Returns: Identity matrix (N×N flat row-major).
    public func identityMatrix(n: Int) -> [Float] {
        var matrix = [Float](repeating: 0, count: n * n)
        for i in 0..<n {
            matrix[i * n + i] = 1.0
        }
        return matrix
    }

    /// Returns the transpose of an N×N matrix.
    ///
    /// - Parameters:
    ///   - matrix: Input matrix (N×N flat row-major).
    ///   - n: Matrix dimension.
    /// - Returns: Transposed matrix (N×N flat row-major).
    public func transposeMatrix(
        _ matrix: [Float], n: Int
    ) -> [Float] {
        var result = [Float](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in 0..<n {
                result[j * n + i] = matrix[i * n + j]
            }
        }
        return result
    }

    // MARK: - Predefined Matrices

    /// Standard ICT forward transform matrix (RGB → YCbCr).
    public static let ictForwardMatrix: [Float] = [
        0.299, 0.587, 0.114,
        -0.16875, -0.33126, 0.5,
        0.5, -0.41869, -0.08131
    ]

    /// Standard ICT inverse transform matrix (YCbCr → RGB).
    public static let ictInverseMatrix: [Float] = [
        1.0, 0.0, 1.402,
        1.0, -0.34413, -0.71414,
        1.0, 1.772, 0.0
    ]

    /// Simple averaging decorrelation matrix for 3 components.
    public static let averaging3Matrix: [Float] = [
        1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0,
        1.0, -1.0, 0.0,
        0.0, 1.0, -1.0
    ]

    // MARK: - CPU Reference Implementation

    private func forwardTransformCPU(
        components: [[Float]], matrix: [Float],
        componentCount: Int, sampleCount: Int
    ) -> J2KMetalMCTResult {
        var output = [[Float]](
            repeating: [Float](repeating: 0, count: sampleCount),
            count: componentCount
        )

        if componentCount == 3 {
            // Optimised 3×3 fast path
            for i in 0..<sampleCount {
                let c0 = components[0][i]
                let c1 = components[1][i]
                let c2 = components[2][i]
                output[0][i] = matrix[0] * c0 + matrix[1] * c1 + matrix[2] * c2
                output[1][i] = matrix[3] * c0 + matrix[4] * c1 + matrix[5] * c2
                output[2][i] = matrix[6] * c0 + matrix[7] * c1 + matrix[8] * c2
            }
        } else if componentCount == 4 {
            // Optimised 4×4 fast path
            for i in 0..<sampleCount {
                let c0 = components[0][i]
                let c1 = components[1][i]
                let c2 = components[2][i]
                let c3 = components[3][i]
                output[0][i] = matrix[0] * c0 + matrix[1] * c1 + matrix[2] * c2 + matrix[3] * c3
                output[1][i] = matrix[4] * c0 + matrix[5] * c1 + matrix[6] * c2 + matrix[7] * c3
                output[2][i] = matrix[8] * c0 + matrix[9] * c1 + matrix[10] * c2 + matrix[11] * c3
                output[3][i] = matrix[12] * c0 + matrix[13] * c1 + matrix[14] * c2 + matrix[15] * c3
            }
        } else {
            // General N×N
            for i in 0..<sampleCount {
                for c in 0..<componentCount {
                    var sum: Float = 0
                    for k in 0..<componentCount {
                        sum += matrix[c * componentCount + k] * components[k][i]
                    }
                    output[c][i] = sum
                }
            }
        }

        return J2KMetalMCTResult(
            components: output,
            componentCount: componentCount,
            sampleCount: sampleCount,
            usedGPU: false
        )
    }

    private func fusedColorMCTCPU(
        components: [[Float]], colorMatrix: [Float],
        mctMatrix: [Float], componentCount: Int,
        sampleCount: Int
    ) -> J2KMetalMCTResult {
        var output = [[Float]](
            repeating: [Float](repeating: 0, count: sampleCount),
            count: componentCount
        )

        for i in 0..<sampleCount {
            // Apply colour transform
            var temp = [Float](repeating: 0, count: componentCount)
            for c in 0..<componentCount {
                var sum: Float = 0
                for k in 0..<componentCount {
                    sum += colorMatrix[c * componentCount + k] * components[k][i]
                }
                temp[c] = sum
            }

            // Apply MCT
            for c in 0..<componentCount {
                var sum: Float = 0
                for k in 0..<componentCount {
                    sum += mctMatrix[c * componentCount + k] * temp[k]
                }
                output[c][i] = sum
            }
        }

        return J2KMetalMCTResult(
            components: output,
            componentCount: componentCount,
            sampleCount: sampleCount,
            usedGPU: false
        )
    }

    // MARK: - GPU Implementations

    #if canImport(Metal)
    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initialize()
        }
    }

    private func forwardTransformGPU(
        components: [[Float]], matrix: [Float],
        componentCount: Int, sampleCount: Int
    ) async throws -> J2KMetalMCTResult {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        // Select optimised shader based on component count
        let shaderFunc: J2KMetalShaderFunction
        switch componentCount {
        case 3:
            shaderFunc = .mctMatrixMultiply3x3
        case 4:
            shaderFunc = .mctMatrixMultiply4x4
        default:
            shaderFunc = .mctMatrixMultiply
        }

        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunc)

        // Pack components into a single interleaved buffer
        let totalSamples = componentCount * sampleCount
        let inputBufferSize = totalSamples * MemoryLayout<Float>.stride
        let matrixBufferSize = matrix.count * MemoryLayout<Float>.stride

        let inputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: inputBufferSize
        )
        let outputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: inputBufferSize
        )
        let matrixBuffer = try await bufferPool.acquireBuffer(
            device: device, size: matrixBufferSize
        )

        // Copy component data: component-major layout [c0s0, c0s1, ..., c1s0, c1s1, ...]
        let inputPtr = inputBuffer.contents().bindMemory(
            to: Float.self, capacity: totalSamples
        )
        for c in 0..<componentCount {
            components[c].withUnsafeBufferPointer { src in
                let offset = c * sampleCount
                for i in 0..<sampleCount {
                    inputPtr[offset + i] = src[i]
                }
            }
        }

        // Copy matrix
        matrix.withUnsafeBytes { src in
            matrixBuffer.contents().copyMemory(
                from: src.baseAddress!, byteCount: src.count
            )
        }

        // Encode command
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(matrixBuffer, offset: 0, index: 2)

        switch componentCount {
        case 3, 4:
            // Optimised: only sampleCount parameter
            var sc = UInt32(sampleCount)
            encoder.setBytes(&sc, length: MemoryLayout<UInt32>.stride, index: 3)
        default:
            // General: componentCount + sampleCount
            var cc = UInt32(componentCount)
            var sc = UInt32(sampleCount)
            encoder.setBytes(&cc, length: MemoryLayout<UInt32>.stride, index: 3)
            encoder.setBytes(&sc, length: MemoryLayout<UInt32>.stride, index: 4)
        }

        let threadgroupSize = MTLSize(
            width: min(pipeline.maxTotalThreadsPerThreadgroup, 256),
            height: 1, depth: 1
        )
        let gridSize = MTLSize(
            width: (sampleCount + threadgroupSize.width - 1) / threadgroupSize.width,
            height: 1, depth: 1
        )
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        await commandBuffer.completed()

        // Read results
        var output = [[Float]](
            repeating: [Float](repeating: 0, count: sampleCount),
            count: componentCount
        )
        let outputPtr = outputBuffer.contents().bindMemory(
            to: Float.self, capacity: totalSamples
        )
        for c in 0..<componentCount {
            let offset = c * sampleCount
            for i in 0..<sampleCount {
                output[c][i] = outputPtr[offset + i]
            }
        }

        await bufferPool.returnBuffer(inputBuffer)
        await bufferPool.returnBuffer(outputBuffer)
        await bufferPool.returnBuffer(matrixBuffer)

        return J2KMetalMCTResult(
            components: output,
            componentCount: componentCount,
            sampleCount: sampleCount,
            usedGPU: true
        )
    }

    private func fusedColorMCTGPU(
        components: [[Float]], colorMatrix: [Float],
        mctMatrix: [Float], componentCount: Int,
        sampleCount: Int
    ) async throws -> J2KMetalMCTResult {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let pipeline = try await shaderLibrary.computePipeline(for: .colorMCTFused)

        let totalSamples = componentCount * sampleCount
        let inputBufferSize = totalSamples * MemoryLayout<Float>.stride
        let matrixBufferSize = colorMatrix.count * MemoryLayout<Float>.stride

        let inputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: inputBufferSize
        )
        let outputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: inputBufferSize
        )
        let colorMatrixBuffer = try await bufferPool.acquireBuffer(
            device: device, size: matrixBufferSize
        )
        let mctMatrixBuffer = try await bufferPool.acquireBuffer(
            device: device, size: matrixBufferSize
        )

        // Copy component data
        let inputPtr = inputBuffer.contents().bindMemory(
            to: Float.self, capacity: totalSamples
        )
        for c in 0..<componentCount {
            components[c].withUnsafeBufferPointer { src in
                let offset = c * sampleCount
                for i in 0..<sampleCount {
                    inputPtr[offset + i] = src[i]
                }
            }
        }

        // Copy matrices
        colorMatrix.withUnsafeBytes { src in
            colorMatrixBuffer.contents().copyMemory(
                from: src.baseAddress!, byteCount: src.count
            )
        }
        mctMatrix.withUnsafeBytes { src in
            mctMatrixBuffer.contents().copyMemory(
                from: src.baseAddress!, byteCount: src.count
            )
        }

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBuffer(colorMatrixBuffer, offset: 0, index: 2)
        encoder.setBuffer(mctMatrixBuffer, offset: 0, index: 3)
        var cc = UInt32(componentCount)
        var sc = UInt32(sampleCount)
        encoder.setBytes(&cc, length: MemoryLayout<UInt32>.stride, index: 4)
        encoder.setBytes(&sc, length: MemoryLayout<UInt32>.stride, index: 5)

        let threadgroupSize = MTLSize(
            width: min(pipeline.maxTotalThreadsPerThreadgroup, 256),
            height: 1, depth: 1
        )
        let gridSize = MTLSize(
            width: (sampleCount + threadgroupSize.width - 1) / threadgroupSize.width,
            height: 1, depth: 1
        )
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        await commandBuffer.completed()

        // Read results
        var output = [[Float]](
            repeating: [Float](repeating: 0, count: sampleCount),
            count: componentCount
        )
        let outputPtr = outputBuffer.contents().bindMemory(
            to: Float.self, capacity: totalSamples
        )
        for c in 0..<componentCount {
            let offset = c * sampleCount
            for i in 0..<sampleCount {
                output[c][i] = outputPtr[offset + i]
            }
        }

        await bufferPool.returnBuffer(inputBuffer)
        await bufferPool.returnBuffer(outputBuffer)
        await bufferPool.returnBuffer(colorMatrixBuffer)
        await bufferPool.returnBuffer(mctMatrixBuffer)

        return J2KMetalMCTResult(
            components: output,
            componentCount: componentCount,
            sampleCount: sampleCount,
            usedGPU: true
        )
    }

    #else
    // Non-Metal platforms: GPU methods throw unsupported errors

    private func forwardTransformGPU(
        components: [[Float]], matrix: [Float],
        componentCount: Int, sampleCount: Int
    ) async throws -> J2KMetalMCTResult {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    private func fusedColorMCTGPU(
        components: [[Float]], colorMatrix: [Float],
        mctMatrix: [Float], componentCount: Int,
        sampleCount: Int
    ) async throws -> J2KMetalMCTResult {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    // MARK: - Utility

    private func currentTime() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
