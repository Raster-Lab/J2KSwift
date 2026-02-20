// J2KMetalColorTransform.swift
// J2KSwift
//
// Metal-accelerated color space transforms for JPEG 2000.
//

import Foundation
import J2KCore

#if canImport(Metal)
import Metal
#endif

// MARK: - Color Transform Type

/// Color transform type for Metal-accelerated operations.
///
/// Defines the color space conversion to apply. ICT is used for lossy
/// compression and RCT for lossless compression per JPEG 2000 standard.
public enum J2KMetalColorTransformType: Sendable {
    /// Irreversible Color Transform (ICT) for lossy compression.
    ///
    /// Converts RGB to YCbCr using floating-point coefficients.
    case ict
    /// Reversible Color Transform (RCT) for lossless compression.
    ///
    /// Converts RGB to YUV using integer arithmetic.
    case rct
}

// MARK: - Color Transform Backend

/// Backend selection for color transform computation.
///
/// Controls whether the transform runs on GPU (Metal) or CPU,
/// with automatic selection based on sample count.
public enum J2KMetalColorTransformBackend: Sendable {
    /// Force GPU execution via Metal.
    case gpu
    /// Force CPU execution (software fallback).
    case cpu
    /// Automatically choose based on sample count and GPU threshold.
    case auto
}

// MARK: - Color Transform Configuration

/// Configuration for Metal-accelerated color transforms.
///
/// Controls the transform type, backend selection, and GPU dispatch
/// parameters for optimal performance.
public struct J2KMetalColorTransformConfiguration: Sendable {
    /// The color transform type to apply.
    public var transformType: J2KMetalColorTransformType

    /// Minimum sample count to prefer GPU over CPU.
    public var gpuThreshold: Int

    /// Creates a Metal color transform configuration.
    ///
    /// - Parameters:
    ///   - transformType: The color transform type. Defaults to `.ict`.
    ///   - gpuThreshold: Minimum samples to prefer GPU. Defaults to `1024`.
    public init(
        transformType: J2KMetalColorTransformType = .ict,
        gpuThreshold: Int = 1024
    ) {
        self.transformType = transformType
        self.gpuThreshold = gpuThreshold
    }

    /// Default configuration for lossy compression.
    public static let lossy = J2KMetalColorTransformConfiguration(transformType: .ict)

    /// Default configuration for lossless compression.
    public static let lossless = J2KMetalColorTransformConfiguration(transformType: .rct)
}

// MARK: - Color Transform Result

/// Result of a color transform operation.
///
/// Contains three output components (Y/Cb/Cr for ICT, or Y/U/V for RCT)
/// and metadata about the transform that was applied.
public struct J2KMetalColorTransformResult: Sendable {
    /// First output component (luminance: Y).
    public let component0: [Float]
    /// Second output component (chrominance: Cb or U).
    public let component1: [Float]
    /// Third output component (chrominance: Cr or V).
    public let component2: [Float]
    /// The type of transform that was applied.
    public let transformType: J2KMetalColorTransformType
    /// Whether the GPU was used for this operation.
    public let usedGPU: Bool

    /// Creates a color transform result.
    public init(
        component0: [Float],
        component1: [Float],
        component2: [Float],
        transformType: J2KMetalColorTransformType,
        usedGPU: Bool
    ) {
        self.component0 = component0
        self.component1 = component1
        self.component2 = component2
        self.transformType = transformType
        self.usedGPU = usedGPU
    }
}

// MARK: - Color Transform Statistics

/// Performance statistics for Metal color transform operations.
///
/// Tracks timing, backend usage, and throughput for monitoring
/// and optimization purposes.
public struct J2KMetalColorTransformStatistics: Sendable {
    /// Total number of color transform operations performed.
    public var totalOperations: Int
    /// Number of operations that ran on GPU.
    public var gpuOperations: Int
    /// Number of operations that fell back to CPU.
    public var cpuOperations: Int
    /// Total processing time in seconds.
    public var totalProcessingTime: Double
    /// Total samples processed across all operations.
    public var totalSamplesProcessed: Int

    /// Creates initial (zero) statistics.
    public init() {
        self.totalOperations = 0
        self.gpuOperations = 0
        self.cpuOperations = 0
        self.totalProcessingTime = 0.0
        self.totalSamplesProcessed = 0
    }

    /// GPU utilization rate as a percentage (0.0 to 1.0).
    public var gpuUtilization: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(gpuOperations) / Double(totalOperations)
    }

    /// Average samples processed per second.
    public var samplesPerSecond: Double {
        guard totalProcessingTime > 0.0 else { return 0.0 }
        return Double(totalSamplesProcessed) / totalProcessingTime
    }
}

// MARK: - NLT Transform Type

/// Non-linear transform type for Metal-accelerated operations.
///
/// Defines the type of non-linear point transform to apply.
public enum J2KMetalNLTType: Sendable {
    /// Gamma correction with specified exponent.
    case gamma(Float)
    /// Logarithmic transform with scale and coefficient.
    case logarithmic(scale: Float, coefficient: Float)
    /// Exponential transform with scale and coefficient.
    case exponential(scale: Float, coefficient: Float)
    /// Perceptual Quantizer (SMPTE ST 2084).
    case pq
    /// Hybrid Log-Gamma (ITU-R BT.2100).
    case hlg
    /// LUT-based transform with lookup table and input range.
    case lut(table: [Float], inputMin: Float, inputMax: Float)
}

// MARK: - Metal Color Transform

/// Metal-accelerated color space transforms for JPEG 2000.
///
/// `J2KMetalColorTransform` provides GPU-accelerated forward and inverse
/// color transforms (ICT and RCT) as well as non-linear point transforms
/// using Metal compute shaders. It includes automatic CPU/GPU backend
/// selection based on input size.
///
/// ## Usage
///
/// ```swift
/// let colorTransform = J2KMetalColorTransform()
///
/// // Forward ICT (RGB → YCbCr)
/// let result = try await colorTransform.forwardTransform(
///     red: redChannel,
///     green: greenChannel,
///     blue: blueChannel
/// )
///
/// // Inverse ICT (YCbCr → RGB)
/// let rgb = try await colorTransform.inverseTransform(
///     component0: result.component0,
///     component1: result.component1,
///     component2: result.component2
/// )
/// ```
///
/// ## Performance
///
/// Target performance: 10-25× speedup vs CPU for large images on
/// Apple Silicon GPUs.
public actor J2KMetalColorTransform {
    /// Whether Metal color transform is available on this platform.
    public static var isAvailable: Bool {
        J2KMetalDevice.isAvailable
    }

    /// The color transform configuration.
    public let configuration: J2KMetalColorTransformConfiguration

    /// The Metal device for GPU operations.
    private let metalDevice: J2KMetalDevice

    /// The buffer pool for GPU memory management.
    private let bufferPool: J2KMetalBufferPool

    /// The shader library for compute kernels.
    private let shaderLibrary: J2KMetalShaderLibrary

    /// Whether the Metal backend has been initialized.
    private var isInitialized = false

    /// Processing statistics.
    private var _statistics = J2KMetalColorTransformStatistics()

    /// Creates a Metal color transform instance.
    ///
    /// - Parameters:
    ///   - configuration: The color transform configuration. Defaults to `.lossy`.
    ///   - device: The Metal device manager. A new instance is created if not provided.
    ///   - bufferPool: The buffer pool. A new instance is created if not provided.
    ///   - shaderLibrary: The shader library. A new instance is created if not provided.
    public init(
        configuration: J2KMetalColorTransformConfiguration = .lossy,
        device: J2KMetalDevice? = nil,
        bufferPool: J2KMetalBufferPool? = nil,
        shaderLibrary: J2KMetalShaderLibrary? = nil
    ) {
        self.configuration = configuration
        self.metalDevice = device ?? J2KMetalDevice()
        self.bufferPool = bufferPool ?? J2KMetalBufferPool()
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    /// Initializes the Metal backend for color transform operations.
    ///
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Metal is not available.
    /// - Throws: ``J2KError/internalError(_:)`` if initialization fails.
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
    public func statistics() -> J2KMetalColorTransformStatistics {
        _statistics
    }

    /// Resets the processing statistics.
    public func resetStatistics() {
        _statistics = J2KMetalColorTransformStatistics()
    }

    /// Determines the best backend for the given sample count.
    ///
    /// - Parameters:
    ///   - sampleCount: Number of samples to transform.
    ///   - backend: Requested backend preference.
    /// - Returns: The effective backend to use.
    public func effectiveBackend(
        sampleCount: Int,
        backend: J2KMetalColorTransformBackend = .auto
    ) -> J2KMetalColorTransformBackend {
        switch backend {
        case .gpu:
            return J2KMetalColorTransform.isAvailable ? .gpu : .cpu
        case .cpu:
            return .cpu
        case .auto:
            if !J2KMetalColorTransform.isAvailable {
                return .cpu
            }
            return sampleCount >= configuration.gpuThreshold ? .gpu : .cpu
        }
    }

    // MARK: - Forward Color Transform

    /// Performs a forward color transform on RGB components.
    ///
    /// Converts RGB to YCbCr (ICT) or YUV (RCT) depending on
    /// the configured transform type.
    ///
    /// - Parameters:
    ///   - red: Red channel samples.
    ///   - green: Green channel samples.
    ///   - blue: Blue channel samples.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The color transform result with three output components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func forwardTransform(
        red: [Float],
        green: [Float],
        blue: [Float],
        backend: J2KMetalColorTransformBackend = .auto
    ) async throws -> J2KMetalColorTransformResult {
        let count = red.count
        guard !isEmpty else {
            throw J2KError.invalidParameter("Input components must not be empty")
        }
        guard green.count == count, blue.count == count else {
            throw J2KError.invalidParameter(
                "All components must have the same length"
            )
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1
        _statistics.totalSamplesProcessed += count

        let effective = effectiveBackend(sampleCount: count, backend: backend)

        let result: J2KMetalColorTransformResult
        if effective == .gpu {
            result = try await forwardTransformGPU(
                red: red, green: green, blue: blue
            )
            _statistics.gpuOperations += 1
        } else {
            result = forwardTransformCPU(
                red: red, green: green, blue: blue
            )
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - Inverse Color Transform

    /// Performs an inverse color transform to recover RGB components.
    ///
    /// Converts YCbCr (ICT) or YUV (RCT) back to RGB depending on
    /// the configured transform type.
    ///
    /// - Parameters:
    ///   - component0: First component (Y).
    ///   - component1: Second component (Cb or U).
    ///   - component2: Third component (Cr or V).
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The color transform result with RGB output components.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func inverseTransform(
        component0: [Float],
        component1: [Float],
        component2: [Float],
        backend: J2KMetalColorTransformBackend = .auto
    ) async throws -> J2KMetalColorTransformResult {
        let count = component0.count
        guard !isEmpty else {
            throw J2KError.invalidParameter("Input components must not be empty")
        }
        guard component1.count == count, component2.count == count else {
            throw J2KError.invalidParameter(
                "All components must have the same length"
            )
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1
        _statistics.totalSamplesProcessed += count

        let effective = effectiveBackend(sampleCount: count, backend: backend)

        let result: J2KMetalColorTransformResult
        if effective == .gpu {
            result = try await inverseTransformGPU(
                component0: component0, component1: component1, component2: component2
            )
            _statistics.gpuOperations += 1
        } else {
            result = inverseTransformCPU(
                component0: component0, component1: component1, component2: component2
            )
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - Non-Linear Transform

    /// Applies a non-linear point transform to the input data.
    ///
    /// Supports gamma correction, logarithmic/exponential transforms,
    /// PQ (SMPTE ST 2084), HLG (ITU-R BT.2100), and LUT-based transforms.
    ///
    /// - Parameters:
    ///   - data: Input sample data.
    ///   - type: The type of non-linear transform to apply.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The transformed data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func applyNLT(
        data: [Float],
        type: J2KMetalNLTType,
        backend: J2KMetalColorTransformBackend = .auto
    ) async throws -> [Float] {
        guard !data.isEmpty else {
            throw J2KError.invalidParameter("Input data must not be empty")
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1
        _statistics.totalSamplesProcessed += data.count

        let effective = effectiveBackend(sampleCount: data.count, backend: backend)

        let result: [Float]
        if effective == .gpu {
            result = try await applyNLTGPU(data: data, type: type)
            _statistics.gpuOperations += 1
        } else {
            result = applyNLTCPU(data: data, type: type)
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - CPU Reference Implementations

    private func forwardTransformCPU(
        red: [Float], green: [Float], blue: [Float]
    ) -> J2KMetalColorTransformResult {
        let count = red.count
        var c0 = [Float](repeating: 0, count: count)
        var c1 = [Float](repeating: 0, count: count)
        var c2 = [Float](repeating: 0, count: count)

        switch configuration.transformType {
        case .ict:
            for i in 0..<count {
                let r = red[i]
                let g = green[i]
                let b = blue[i]
                c0[i] = 0.299 * r + 0.587 * g + 0.114 * b
                c1[i] = -0.16875 * r - 0.33126 * g + 0.5 * b
                c2[i] = 0.5 * r - 0.41869 * g - 0.08131 * b
            }
        case .rct:
            for i in 0..<count {
                let r = red[i]
                let g = green[i]
                let b = blue[i]
                let ri = Int32(r)
                let gi = Int32(g)
                let bi = Int32(b)
                c0[i] = Float((ri + 2 * gi + bi) >> 2)
                c1[i] = Float(bi - gi)
                c2[i] = Float(ri - gi)
            }
        }

        return J2KMetalColorTransformResult(
            component0: c0, component1: c1, component2: c2,
            transformType: configuration.transformType,
            usedGPU: false
        )
    }

    private func inverseTransformCPU(
        component0: [Float], component1: [Float], component2: [Float]
    ) -> J2KMetalColorTransformResult {
        let count = component0.count
        var r = [Float](repeating: 0, count: count)
        var g = [Float](repeating: 0, count: count)
        var b = [Float](repeating: 0, count: count)

        switch configuration.transformType {
        case .ict:
            for i in 0..<count {
                let y = component0[i]
                let cb = component1[i]
                let cr = component2[i]
                r[i] = y + 1.402 * cr
                g[i] = y - 0.34413 * cb - 0.71414 * cr
                b[i] = y + 1.772 * cb
            }
        case .rct:
            for i in 0..<count {
                let y = Int32(component0[i])
                let u = Int32(component1[i])
                let v = Int32(component2[i])
                let gv = y - ((u + v) >> 2)
                g[i] = Float(gv)
                r[i] = Float(v + gv)
                b[i] = Float(u + gv)
            }
        }

        return J2KMetalColorTransformResult(
            component0: r, component1: g, component2: b,
            transformType: configuration.transformType,
            usedGPU: false
        )
    }

    private func applyNLTCPU(
        data: [Float], type: J2KMetalNLTType
    ) -> [Float] {
        let count = data.count
        var output = [Float](repeating: 0, count: count)

        switch type {
        case .gamma(let exponent):
            for i in 0..<count {
                let val = data[i]
                let sign: Float = val >= 0 ? 1.0 : -1.0
                output[i] = sign * pow(abs(val), exponent)
            }

        case .logarithmic(let scale, let coefficient):
            for i in 0..<count {
                let val = data[i]
                let sign: Float = val >= 0 ? 1.0 : -1.0
                output[i] = sign * scale * log(1.0 + coefficient * abs(val))
            }

        case .exponential(let scale, let coefficient):
            for i in 0..<count {
                let val = data[i]
                let sign: Float = val >= 0 ? 1.0 : -1.0
                output[i] = sign * scale * (exp(coefficient * abs(val)) - 1.0)
            }

        case .pq:
            let m1: Float = 0.1593017578125
            let m2: Float = 78.84375
            let c1: Float = 0.8359375
            let c2: Float = 18.8515625
            let c3: Float = 18.6875
            for i in 0..<count {
                let y = max(0, min(1, data[i]))
                let ym1 = pow(y, m1)
                output[i] = pow((c1 + c2 * ym1) / (1.0 + c3 * ym1), m2)
            }

        case .hlg:
            let a: Float = 0.17883277
            let b: Float = 0.28466892
            let c: Float = 0.55991073
            for i in 0..<count {
                let e = max(0, min(1, data[i]))
                if e <= 1.0 / 12.0 {
                    output[i] = sqrt(3.0 * e)
                } else {
                    output[i] = a * log(12.0 * e - b) + c
                }
            }

        case .lut(let table, let inputMin, let inputMax):
            let lutSize = table.count
            guard lutSize >= 2 else {
                return data
            }
            let range = inputMax - inputMin
            guard range > 0 else {
                return [Float](repeating: table[0], count: count)
            }
            for i in 0..<count {
                let val = data[i]
                let normalized = (val - inputMin) / range * Float(lutSize - 1)
                let clamped = max(0, min(Float(lutSize - 1), normalized))
                let idx0 = Int(clamped)
                let idx1 = min(idx0 + 1, lutSize - 1)
                let frac = clamped - Float(idx0)
                output[i] = table[idx0] * (1.0 - frac) + table[idx1] * frac
            }
        }

        return output
    }

    // MARK: - GPU Implementations

    #if canImport(Metal)
    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initialize()
        }
    }

    private func forwardTransformGPU(
        red: [Float], green: [Float], blue: [Float]
    ) async throws -> J2KMetalColorTransformResult {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let count = red.count
        let bufferSize = count * MemoryLayout<Float>.stride

        let rBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let gBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let bBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let c0Buffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let c1Buffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let c2Buffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)

        red.withUnsafeBytes { src in
            rBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        green.withUnsafeBytes { src in
            gBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        blue.withUnsafeBytes { src in
            bBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        let shaderFunc: J2KMetalShaderFunction
        switch configuration.transformType {
        case .ict:
            shaderFunc = .ictForward
        case .rct:
            shaderFunc = .rctForward
        }
        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunc)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(rBuffer, offset: 0, index: 0)
        encoder.setBuffer(gBuffer, offset: 0, index: 1)
        encoder.setBuffer(bBuffer, offset: 0, index: 2)
        encoder.setBuffer(c0Buffer, offset: 0, index: 3)
        encoder.setBuffer(c1Buffer, offset: 0, index: 4)
        encoder.setBuffer(c2Buffer, offset: 0, index: 5)
        var sampleCount = UInt32(count)
        encoder.setBytes(&sampleCount, length: MemoryLayout<UInt32>.stride, index: 6)

        let threadgroupSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
        let gridSize = MTLSize(width: (count + threadgroupSize.width - 1) / threadgroupSize.width, height: 1, depth: 1)
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var c0 = [Float](repeating: 0, count: count)
        var c1 = [Float](repeating: 0, count: count)
        var c2 = [Float](repeating: 0, count: count)

        c0.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: c0Buffer.contents(), count: bufferSize))
        }
        c1.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: c1Buffer.contents(), count: bufferSize))
        }
        c2.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: c2Buffer.contents(), count: bufferSize))
        }

        await bufferPool.returnBuffer(rBuffer)
        await bufferPool.returnBuffer(gBuffer)
        await bufferPool.returnBuffer(bBuffer)
        await bufferPool.returnBuffer(c0Buffer)
        await bufferPool.returnBuffer(c1Buffer)
        await bufferPool.returnBuffer(c2Buffer)

        return J2KMetalColorTransformResult(
            component0: c0, component1: c1, component2: c2,
            transformType: configuration.transformType,
            usedGPU: true
        )
    }

    private func inverseTransformGPU(
        component0: [Float], component1: [Float], component2: [Float]
    ) async throws -> J2KMetalColorTransformResult {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let count = component0.count
        let bufferSize = count * MemoryLayout<Float>.stride

        let c0Buffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let c1Buffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let c2Buffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let rBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let gBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let bBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)

        component0.withUnsafeBytes { src in
            c0Buffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        component1.withUnsafeBytes { src in
            c1Buffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        component2.withUnsafeBytes { src in
            c2Buffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        let shaderFunc: J2KMetalShaderFunction
        switch configuration.transformType {
        case .ict:
            shaderFunc = .ictInverse
        case .rct:
            shaderFunc = .rctInverse
        }
        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunc)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(c0Buffer, offset: 0, index: 0)
        encoder.setBuffer(c1Buffer, offset: 0, index: 1)
        encoder.setBuffer(c2Buffer, offset: 0, index: 2)
        encoder.setBuffer(rBuffer, offset: 0, index: 3)
        encoder.setBuffer(gBuffer, offset: 0, index: 4)
        encoder.setBuffer(bBuffer, offset: 0, index: 5)
        var sampleCount = UInt32(count)
        encoder.setBytes(&sampleCount, length: MemoryLayout<UInt32>.stride, index: 6)

        let threadgroupSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
        let gridSize = MTLSize(width: (count + threadgroupSize.width - 1) / threadgroupSize.width, height: 1, depth: 1)
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var r = [Float](repeating: 0, count: count)
        var g = [Float](repeating: 0, count: count)
        var b = [Float](repeating: 0, count: count)

        r.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: rBuffer.contents(), count: bufferSize))
        }
        g.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: gBuffer.contents(), count: bufferSize))
        }
        b.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: bBuffer.contents(), count: bufferSize))
        }

        await bufferPool.returnBuffer(c0Buffer)
        await bufferPool.returnBuffer(c1Buffer)
        await bufferPool.returnBuffer(c2Buffer)
        await bufferPool.returnBuffer(rBuffer)
        await bufferPool.returnBuffer(gBuffer)
        await bufferPool.returnBuffer(bBuffer)

        return J2KMetalColorTransformResult(
            component0: r, component1: g, component2: b,
            transformType: configuration.transformType,
            usedGPU: true
        )
    }

    private func applyNLTGPU(
        data: [Float], type: J2KMetalNLTType
    ) async throws -> [Float] {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let count = data.count
        let bufferSize = count * MemoryLayout<Float>.stride

        let inputBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)
        let outputBuffer = try await bufferPool.acquireBuffer(device: device, size: bufferSize)

        data.withUnsafeBytes { src in
            inputBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        let shaderFunc: J2KMetalShaderFunction
        var extraBuffers: [(any MTLBuffer)] = []

        switch type {
        case .gamma, .logarithmic, .exponential:
            shaderFunc = .nltParametric
        case .pq:
            shaderFunc = .nltPQ
        case .hlg:
            shaderFunc = .nltHLG
        case .lut:
            shaderFunc = .nltLUT
        }

        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunc)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)

        switch type {
        case .gamma(let exponent):
            var cnt = UInt32(count)
            var transformType: UInt32 = 0
            var p1 = exponent
            var p2: Float = 0
            encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.setBytes(&transformType, length: MemoryLayout<UInt32>.stride, index: 3)
            encoder.setBytes(&p1, length: MemoryLayout<Float>.stride, index: 4)
            encoder.setBytes(&p2, length: MemoryLayout<Float>.stride, index: 5)

        case .logarithmic(let scale, let coefficient):
            var cnt = UInt32(count)
            var transformType: UInt32 = 1
            var p1 = scale
            var p2 = coefficient
            encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.setBytes(&transformType, length: MemoryLayout<UInt32>.stride, index: 3)
            encoder.setBytes(&p1, length: MemoryLayout<Float>.stride, index: 4)
            encoder.setBytes(&p2, length: MemoryLayout<Float>.stride, index: 5)

        case .exponential(let scale, let coefficient):
            var cnt = UInt32(count)
            var transformType: UInt32 = 2
            var p1 = scale
            var p2 = coefficient
            encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.setBytes(&transformType, length: MemoryLayout<UInt32>.stride, index: 3)
            encoder.setBytes(&p1, length: MemoryLayout<Float>.stride, index: 4)
            encoder.setBytes(&p2, length: MemoryLayout<Float>.stride, index: 5)

        case .pq:
            var cnt = UInt32(count)
            var inverse: UInt32 = 0
            encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.setBytes(&inverse, length: MemoryLayout<UInt32>.stride, index: 3)

        case .hlg:
            var cnt = UInt32(count)
            var inverse: UInt32 = 0
            encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.setBytes(&inverse, length: MemoryLayout<UInt32>.stride, index: 3)

        case .lut(let table, let inputMin, let inputMax):
            let lutBufferSize = table.count * MemoryLayout<Float>.stride
            let lutBuffer = try await bufferPool.acquireBuffer(device: device, size: lutBufferSize)
            table.withUnsafeBytes { src in
                lutBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
            extraBuffers.append(lutBuffer)
            encoder.setBuffer(lutBuffer, offset: 0, index: 2)
            var cnt = UInt32(count)
            var lutSize = UInt32(table.count)
            var minVal = inputMin
            var maxVal = inputMax
            encoder.setBytes(&cnt, length: MemoryLayout<UInt32>.stride, index: 3)
            encoder.setBytes(&lutSize, length: MemoryLayout<UInt32>.stride, index: 4)
            encoder.setBytes(&minVal, length: MemoryLayout<Float>.stride, index: 5)
            encoder.setBytes(&maxVal, length: MemoryLayout<Float>.stride, index: 6)
        }

        let threadgroupSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
        let gridSize = MTLSize(width: (count + threadgroupSize.width - 1) / threadgroupSize.width, height: 1, depth: 1)
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(start: outputBuffer.contents(), count: bufferSize))
        }

        await bufferPool.returnBuffer(inputBuffer)
        await bufferPool.returnBuffer(outputBuffer)
        for buffer in extraBuffers {
            await bufferPool.returnBuffer(buffer)
        }

        return result
    }

    #else
    // Non-Metal platforms: GPU methods throw unsupported errors

    private func forwardTransformGPU(
        red: [Float], green: [Float], blue: [Float]
    ) async throws -> J2KMetalColorTransformResult {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    private func inverseTransformGPU(
        component0: [Float], component1: [Float], component2: [Float]
    ) async throws -> J2KMetalColorTransformResult {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    private func applyNLTGPU(
        data: [Float], type: J2KMetalNLTType
    ) async throws -> [Float] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    // MARK: - Utility

    private func currentTime() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
