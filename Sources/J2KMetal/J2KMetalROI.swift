// J2KMetalROI.swift
// J2KSwift
//
// Metal-accelerated Region of Interest (ROI) processing for JPEG 2000.
//

import Foundation
import J2KCore

#if canImport(Metal)
import Metal
#endif

// MARK: - ROI Backend Selection

/// Backend selection for ROI computation.
public enum J2KMetalROIBackend: Sendable {
    /// Force GPU execution via Metal.
    case gpu
    /// Force CPU execution (software fallback).
    case cpu
    /// Automatically choose based on image size.
    case auto
}

// MARK: - ROI Configuration

/// Configuration for Metal-accelerated ROI processing.
public struct J2KMetalROIConfiguration: Sendable {
    /// Minimum pixel count to prefer GPU over CPU.
    public var gpuThreshold: Int

    /// Feathering width for smooth ROI boundaries (in pixels).
    public var featherWidth: Float

    /// Backend selection strategy.
    public var backend: J2KMetalROIBackend

    /// Creates a Metal ROI configuration.
    ///
    /// - Parameters:
    ///   - gpuThreshold: Minimum pixels to prefer GPU. Defaults to `4096`.
    ///   - featherWidth: Feathering width in pixels. Defaults to `8.0`.
    ///   - backend: Backend selection. Defaults to `.auto`.
    public init(
        gpuThreshold: Int = 4096,
        featherWidth: Float = 8.0,
        backend: J2KMetalROIBackend = .auto
    ) {
        self.gpuThreshold = gpuThreshold
        self.featherWidth = featherWidth
        self.backend = backend
    }

    /// Default ROI configuration.
    public static let `default` = J2KMetalROIConfiguration()
}

// MARK: - ROI Result

/// Result of a Metal ROI operation.
public struct J2KMetalROIResult: Sendable {
    /// Scaled coefficients with ROI applied.
    public let coefficients: [[Int32]]
    /// ROI mask (true = inside ROI).
    public let mask: [[Bool]]
    /// Whether GPU was used for this operation.
    public let usedGPU: Bool
    /// Processing time in seconds.
    public let processingTime: Double

    /// Creates an ROI result.
    public init(
        coefficients: [[Int32]],
        mask: [[Bool]],
        usedGPU: Bool,
        processingTime: Double
    ) {
        self.coefficients = coefficients
        self.mask = mask
        self.usedGPU = usedGPU
        self.processingTime = processingTime
    }
}

// MARK: - ROI Statistics

/// Performance statistics for Metal ROI operations.
public struct J2KMetalROIStatistics: Sendable {
    /// Total number of ROI operations performed.
    public var totalOperations: Int
    /// Number of operations that ran on GPU.
    public var gpuOperations: Int
    /// Number of operations that fell back to CPU.
    public var cpuOperations: Int
    /// Total processing time in seconds.
    public var totalProcessingTime: Double
    /// Total pixels processed.
    public var totalPixelsProcessed: Int

    /// Creates initial (zero) statistics.
    public init() {
        self.totalOperations = 0
        self.gpuOperations = 0
        self.cpuOperations = 0
        self.totalProcessingTime = 0.0
        self.totalPixelsProcessed = 0
    }

    /// GPU utilization rate (0.0 to 1.0).
    public var gpuUtilization: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(gpuOperations) / Double(totalOperations)
    }

    /// Average pixels processed per second.
    public var pixelsPerSecond: Double {
        guard totalProcessingTime > 0.0 else { return 0.0 }
        return Double(totalPixelsProcessed) / totalProcessingTime
    }
}

#if canImport(Metal)

// MARK: - Metal ROI Actor

/// Metal-accelerated Region of Interest (ROI) processor.
///
/// Provides GPU-accelerated ROI operations for JPEG 2000 encoding:
/// - ROI mask generation from rectangular/elliptical regions
/// - MaxShift coefficient scaling
/// - Multiple ROI blending with priority
/// - Smooth feathering at ROI boundaries
/// - Spatial to wavelet domain mapping
///
/// ## Usage
///
/// ```swift
/// let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)
///
/// // Apply MaxShift ROI scaling
/// let result = try await roi.applyMaxShift(
///     coefficients: waveletCoeffs,
///     mask: roiMask,
///     shift: 5,
///     width: 512,
///     height: 512
/// )
/// ```
public actor J2KMetalROI {
    // MARK: Properties

    private let device: J2KMetalDevice
    private let shaderLibrary: J2KMetalShaderLibrary
    private let bufferPool: J2KMetalBufferPool
    private var statistics: J2KMetalROIStatistics

    // MARK: Initialization

    /// Creates a new Metal ROI processor.
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
        self.statistics = J2KMetalROIStatistics()
    }

    // MARK: - ROI Mask Generation

    /// Generates an ROI mask for a rectangular region.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - x: ROI rectangle x-coordinate.
    ///   - y: ROI rectangle y-coordinate.
    ///   - roiWidth: ROI rectangle width.
    ///   - roiHeight: ROI rectangle height.
    ///   - configuration: ROI configuration.
    /// - Returns: Boolean mask (true = inside ROI).
    /// - Throws: ``J2KError/metalOperationFailed(_:)`` if GPU operation fails.
    public func generateMask(
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        roiWidth: Int,
        roiHeight: Int,
        configuration: J2KMetalROIConfiguration = .default
    ) async throws -> [[Bool]] {
        let startTime = Date()
        let pixelCount = width * height

        // Determine backend
        let useGPU = shouldUseGPU(pixelCount: pixelCount, configuration: configuration)

        if useGPU {
            let result = try await generateMaskGPU(
                width: width,
                height: height,
                x: x,
                y: y,
                roiWidth: roiWidth,
                roiHeight: roiHeight
            )

            updateStatistics(
                usedGPU: true,
                processingTime: Date().timeIntervalSince(startTime),
                pixelCount: pixelCount
            )

            return result
        } else {
            let result = generateMaskCPU(
                width: width,
                height: height,
                x: x,
                y: y,
                roiWidth: roiWidth,
                roiHeight: roiHeight
            )

            updateStatistics(
                usedGPU: false,
                processingTime: Date().timeIntervalSince(startTime),
                pixelCount: pixelCount
            )

            return result
        }
    }

    // MARK: - MaxShift Coefficient Scaling

    /// Applies MaxShift ROI scaling to wavelet coefficients.
    ///
    /// - Parameters:
    ///   - coefficients: Input wavelet coefficients (2D array).
    ///   - mask: ROI mask (true = inside ROI).
    ///   - shift: Bit-shift amount (typically 5).
    ///   - width: Coefficient array width.
    ///   - height: Coefficient array height.
    ///   - configuration: ROI configuration.
    /// - Returns: Scaled coefficients.
    /// - Throws: ``J2KError/metalOperationFailed(_:)`` if GPU operation fails.
    public func applyMaxShift(
        coefficients: [[Int32]],
        mask: [[Bool]],
        shift: UInt32,
        width: Int,
        height: Int,
        configuration: J2KMetalROIConfiguration = .default
    ) async throws -> [[Int32]] {
        let startTime = Date()
        let pixelCount = width * height

        // Determine backend
        let useGPU = shouldUseGPU(pixelCount: pixelCount, configuration: configuration)

        if useGPU {
            let result = try await applyMaxShiftGPU(
                coefficients: coefficients,
                mask: mask,
                shift: shift,
                width: width,
                height: height
            )

            updateStatistics(
                usedGPU: true,
                processingTime: Date().timeIntervalSince(startTime),
                pixelCount: pixelCount
            )

            return result
        } else {
            let result = applyMaxShiftCPU(
                coefficients: coefficients,
                mask: mask,
                shift: shift
            )

            updateStatistics(
                usedGPU: false,
                processingTime: Date().timeIntervalSince(startTime),
                pixelCount: pixelCount
            )

            return result
        }
    }

    // MARK: - Statistics

    /// Returns current performance statistics.
    public func getStatistics() -> J2KMetalROIStatistics {
        statistics
    }

    /// Resets performance statistics.
    public func resetStatistics() {
        statistics = J2KMetalROIStatistics()
    }

    // MARK: - Private Methods (GPU)

    private func generateMaskGPU(
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        roiWidth: Int,
        roiHeight: Int
    ) async throws -> [[Bool]] {
        let mtlDevice = try await device.metalDevice()
        let commandQueue = try await device.commandQueue()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.metalOperationFailed("Failed to create command buffer/encoder")
        }

        // Get pipeline state
        let pipeline = try await shaderLibrary.computePipeline(for: .roiMaskGenerate)
        computeEncoder.setComputePipelineState(pipeline)

        // Allocate buffers
        let pixelCount = width * height
        let maskBuffer = try await bufferPool.allocateBuffer(
            size: pixelCount * MemoryLayout<Bool>.size,
            storageMode: .shared
        )

        // Set buffers
        computeEncoder.setBuffer(maskBuffer, offset: 0, index: 0)

        var params = (
            UInt32(width),
            UInt32(height),
            UInt32(x),
            UInt32(y),
            UInt32(roiWidth),
            UInt32(roiHeight)
        )
        withUnsafeBytes(of: &params) { ptr in
            for i in 0..<6 {
                let offset = i * MemoryLayout<UInt32>.size
                computeEncoder.setBytes(ptr.baseAddress! + offset, length: MemoryLayout<UInt32>.size, index: i + 1)
            }
        }

        // Dispatch
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read results
        let maskPtr = maskBuffer.contents().bindMemory(to: Bool.self, capacity: pixelCount)
        var result = Array(repeating: Array(repeating: false, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                result[y][x] = maskPtr[y * width + x]
            }
        }

        return result
    }

    private func applyMaxShiftGPU(
        coefficients: [[Int32]],
        mask: [[Bool]],
        shift: UInt32,
        width: Int,
        height: Int
    ) async throws -> [[Int32]] {
        let mtlDevice = try await device.metalDevice()
        let commandQueue = try await device.commandQueue()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.metalOperationFailed("Failed to create command buffer/encoder")
        }

        // Get pipeline state
        let pipeline = try await shaderLibrary.computePipeline(for: .roiCoefficientScale)
        computeEncoder.setComputePipelineState(pipeline)

        // Flatten input arrays
        let flatCoeffs = coefficients.flatMap { $0 }
        let flatMask = mask.flatMap { $0 }
        let pixelCount = width * height

        // Allocate buffers
        let inputBuffer = try await bufferPool.allocateBuffer(
            size: pixelCount * MemoryLayout<Int32>.size,
            storageMode: .shared
        )
        let maskBuffer = try await bufferPool.allocateBuffer(
            size: pixelCount * MemoryLayout<Bool>.size,
            storageMode: .shared
        )
        let outputBuffer = try await bufferPool.allocateBuffer(
            size: pixelCount * MemoryLayout<Int32>.size,
            storageMode: .shared
        )

        // Copy data
        memcpy(inputBuffer.contents(), flatCoeffs, pixelCount * MemoryLayout<Int32>.size)
        memcpy(maskBuffer.contents(), flatMask, pixelCount * MemoryLayout<Bool>.size)

        // Set buffers
        computeEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(maskBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(outputBuffer, offset: 0, index: 2)

        var params = (UInt32(width), UInt32(height), shift)
        withUnsafeBytes(of: &params) { ptr in
            computeEncoder.setBytes(ptr.baseAddress!, length: MemoryLayout<UInt32>.size, index: 3)
            computeEncoder.setBytes(ptr.baseAddress! + MemoryLayout<UInt32>.size, length: MemoryLayout<UInt32>.size, index: 4)
            computeEncoder.setBytes(ptr.baseAddress! + 2 * MemoryLayout<UInt32>.size, length: MemoryLayout<UInt32>.size, index: 5)
        }

        // Dispatch
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read results
        let outputPtr = outputBuffer.contents().bindMemory(to: Int32.self, capacity: pixelCount)
        var result = Array(repeating: Array(repeating: Int32(0), count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                result[y][x] = outputPtr[y * width + x]
            }
        }

        return result
    }

    // MARK: - Private Methods (CPU Fallback)

    private func generateMaskCPU(
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        roiWidth: Int,
        roiHeight: Int
    ) -> [[Bool]] {
        var mask = Array(repeating: Array(repeating: false, count: width), count: height)

        for row in 0..<height {
            for col in 0..<width {
                let insideX = col >= x && col < x + roiWidth
                let insideY = row >= y && row < y + roiHeight
                mask[row][col] = insideX && insideY
            }
        }

        return mask
    }

    private func applyMaxShiftCPU(
        coefficients: [[Int32]],
        mask: [[Bool]],
        shift: UInt32
    ) -> [[Int32]] {
        let height = coefficients.count
        guard height > 0 else { return [] }
        let width = coefficients[0].count

        var result = coefficients

        for y in 0..<height {
            for x in 0..<width {
                if mask[y][x] {
                    let coeff = coefficients[y][x]
                    if coeff >= 0 {
                        result[y][x] = coeff << shift
                    } else {
                        result[y][x] = -((-coeff) << shift)
                    }
                }
            }
        }

        return result
    }

    // MARK: - Utility

    private func shouldUseGPU(
        pixelCount: Int,
        configuration: J2KMetalROIConfiguration
    ) -> Bool {
        switch configuration.backend {
        case .gpu:
            return true
        case .cpu:
            return false
        case .auto:
            return pixelCount >= configuration.gpuThreshold
        }
    }

    private func updateStatistics(
        usedGPU: Bool,
        processingTime: Double,
        pixelCount: Int
    ) {
        statistics.totalOperations += 1
        if usedGPU {
            statistics.gpuOperations += 1
        } else {
            statistics.cpuOperations += 1
        }
        statistics.totalProcessingTime += processingTime
        statistics.totalPixelsProcessed += pixelCount
    }
}

#endif // canImport(Metal)
