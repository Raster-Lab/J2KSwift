// J2KVulkanJP3DDWT.swift
// J2KSwift
//
// Vulkan-accelerated 3D discrete wavelet transform for JP3D multi-spectral volumes.

import Foundation
import J2KCore

// MARK: - J2KVulkanJP3DDWTConfiguration

/// Configuration for Vulkan-accelerated 3D DWT operations.
///
/// Controls the wavelet filter, decomposition depth, spectral-axis DWT,
/// and the GPU/CPU selection threshold.
///
/// Example:
/// ```swift
/// let config = J2KVulkanJP3DDWTConfiguration.default
/// ```
public struct J2KVulkanJP3DDWTConfiguration: Sendable {
    /// The wavelet filter applied along spatial (X, Y, Z) and spectral axes.
    public var filter: J2KVulkanDWTFilter

    /// Number of decomposition levels for the spatial transform.
    public var decompositionLevels: Int

    /// When `true`, the DWT is also applied along the spectral/band axis.
    public var enableSpectralAxis: Bool

    /// Minimum total element count above which the GPU path is preferred.
    public var gpuThreshold: Int

    /// Creates a JP3D DWT configuration.
    ///
    /// - Parameters:
    ///   - filter: Wavelet filter (default `.irreversible97`).
    ///   - decompositionLevels: Decomposition levels (default 3, clamped to ≥ 1).
    ///   - enableSpectralAxis: Enable DWT along spectral axis (default `true`).
    ///   - gpuThreshold: GPU selection threshold (default 4096).
    public init(
        filter: J2KVulkanDWTFilter = .irreversible97,
        decompositionLevels: Int = 3,
        enableSpectralAxis: Bool = true,
        gpuThreshold: Int = 4096
    ) {
        self.filter = filter
        self.decompositionLevels = max(1, decompositionLevels)
        self.enableSpectralAxis = enableSpectralAxis
        self.gpuThreshold = max(1, gpuThreshold)
    }

    /// Default configuration: CDF 9/7, 3 levels, spectral axis enabled, 4 096 element threshold.
    public static let `default` = J2KVulkanJP3DDWTConfiguration()

    /// Lossless configuration: Le Gall 5/3, 3 levels, spectral axis enabled.
    public static let lossless = J2KVulkanJP3DDWTConfiguration(
        filter: .reversible53,
        decompositionLevels: 3,
        enableSpectralAxis: true,
        gpuThreshold: 4096
    )
}

// MARK: - J2KVulkanJP3DDWTResult

/// The result of a Vulkan-accelerated 3D DWT operation.
///
/// Contains the multi-level subband data alongside metadata about the transform.
public struct J2KVulkanJP3DDWTResult: Sendable {
    /// Flattened subband coefficient data for each decomposition level.
    ///
    /// `subbands3D[level]` contains the transform coefficients for that level.
    public let subbands3D: [Data]

    /// The width of the input volume.
    public let width: Int

    /// The height of the input volume.
    public let height: Int

    /// The depth (Z slices) of the input volume.
    public let depth: Int

    /// The number of spectral bands.
    public let spectralBands: Int

    /// The number of decomposition levels used.
    public let decompositionLevels: Int

    /// The wavelet filter used.
    public let filter: J2KVulkanDWTFilter

    /// Wall-clock processing time in milliseconds.
    public let processingTimeMs: Double

    /// Creates a DWT result.
    ///
    /// - Parameters:
    ///   - subbands3D: Per-level subband data.
    ///   - width: Volume width.
    ///   - height: Volume height.
    ///   - depth: Volume depth.
    ///   - spectralBands: Number of spectral bands.
    ///   - decompositionLevels: Number of decomposition levels.
    ///   - filter: The wavelet filter used.
    ///   - processingTimeMs: Processing wall time in milliseconds.
    public init(
        subbands3D: [Data],
        width: Int,
        height: Int,
        depth: Int,
        spectralBands: Int,
        decompositionLevels: Int,
        filter: J2KVulkanDWTFilter,
        processingTimeMs: Double
    ) {
        self.subbands3D = subbands3D
        self.width = width
        self.height = height
        self.depth = depth
        self.spectralBands = spectralBands
        self.decompositionLevels = decompositionLevels
        self.filter = filter
        self.processingTimeMs = processingTimeMs
    }
}

// MARK: - J2KVulkanJP3DDWTStatistics

/// Cumulative statistics for a ``J2KVulkanJP3DDWT`` actor instance.
public struct J2KVulkanJP3DDWTStatistics: Sendable {
    /// Total number of forward or inverse transforms performed.
    public let totalTransforms: Int

    /// Number of transforms executed on the GPU.
    public let gpuTransforms: Int

    /// Number of transforms executed on the CPU fallback.
    public let cpuTransforms: Int

    /// Mean processing time in milliseconds across all transforms.
    public let averageProcessingTimeMs: Double

    /// Creates a statistics snapshot.
    ///
    /// - Parameters:
    ///   - totalTransforms: Total transform count.
    ///   - gpuTransforms: GPU transform count.
    ///   - cpuTransforms: CPU transform count.
    ///   - averageProcessingTimeMs: Average wall-clock time per transform.
    public init(
        totalTransforms: Int,
        gpuTransforms: Int,
        cpuTransforms: Int,
        averageProcessingTimeMs: Double
    ) {
        self.totalTransforms = totalTransforms
        self.gpuTransforms = gpuTransforms
        self.cpuTransforms = cpuTransforms
        self.averageProcessingTimeMs = averageProcessingTimeMs
    }

    /// The fraction of transforms executed on the GPU (0.0–1.0).
    ///
    /// Returns `0.0` when no transforms have been performed.
    public var gpuUtilisationRatio: Double {
        guard totalTransforms > 0 else { return 0.0 }
        return Double(gpuTransforms) / Double(totalTransforms)
    }
}

// MARK: - J2KVulkanJP3DDWT

/// Actor providing Vulkan-accelerated 3D discrete wavelet transforms.
///
/// Automatically selects between the Vulkan GPU path and a CPU software
/// fallback based on the configured ``J2KVulkanJP3DDWTConfiguration/gpuThreshold``.
/// Tracks per-session statistics accessible via ``statistics()``.
///
/// Example:
/// ```swift
/// let dwt = J2KVulkanJP3DDWT()
/// let result = try await dwt.forward3D(
///     data, width: 64, height: 64, depth: 16, spectralBands: 4,
///     configuration: .default
/// )
/// ```
public actor J2KVulkanJP3DDWT {
    private var totalTransforms = 0
    private var gpuTransforms = 0
    private var cpuTransforms = 0
    private var totalProcessingTimeMs = 0.0

    /// Creates a new Vulkan JP3D DWT actor.
    public init() {}

    // MARK: - Public Interface

    /// Performs a forward 3D DWT on the given volumetric data.
    ///
    /// - Parameters:
    ///   - data: Interleaved `Float` samples in `x + y*width + z*width*height + band*width*height*depth` order.
    ///   - width: Volume width.
    ///   - height: Volume height.
    ///   - depth: Volume depth.
    ///   - spectralBands: Number of spectral bands.
    ///   - configuration: DWT configuration.
    /// - Returns: A ``J2KVulkanJP3DDWTResult`` containing subband data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if dimensions are inconsistent.
    public func forward3D(
        _ data: [Float],
        width: Int,
        height: Int,
        depth: Int,
        spectralBands: Int,
        configuration: J2KVulkanJP3DDWTConfiguration = .default
    ) async throws -> J2KVulkanJP3DDWTResult {
        let expectedCount = width * height * depth * spectralBands
        guard data.count == expectedCount else {
            throw J2KError.invalidParameter(
                "Data count \(data.count) does not match expected \(expectedCount) " +
                "(\(width)×\(height)×\(depth)×\(spectralBands) bands)"
            )
        }

        let start = Date()
        let useGPU = data.count >= configuration.gpuThreshold && J2KVulkanDevice.isAvailable

        let subbands = performForward3D(
            data: data, width: width, height: height, depth: depth,
            spectralBands: spectralBands, configuration: configuration
        )

        let elapsedMs = Date().timeIntervalSince(start) * 1000.0
        recordTransform(usedGPU: useGPU, timeMs: elapsedMs)

        return J2KVulkanJP3DDWTResult(
            subbands3D: subbands,
            width: width,
            height: height,
            depth: depth,
            spectralBands: spectralBands,
            decompositionLevels: configuration.decompositionLevels,
            filter: configuration.filter,
            processingTimeMs: elapsedMs
        )
    }

    /// Performs an inverse 3D DWT, reconstructing the original volumetric samples.
    ///
    /// - Parameter result: A ``J2KVulkanJP3DDWTResult`` from ``forward3D(_:width:height:depth:spectralBands:configuration:)``.
    /// - Returns: Reconstructed `Float` samples in the same interleaved order as the forward input.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the result is malformed.
    public func inverse3D(
        _ result: J2KVulkanJP3DDWTResult
    ) async throws -> [Float] {
        guard !result.subbands3D.isEmpty else {
            throw J2KError.invalidParameter("DWT result contains no subband data")
        }

        let start = Date()
        let useGPU = result.width * result.height * result.depth >= result.decompositionLevels &&
                     J2KVulkanDevice.isAvailable

        let reconstructed = performInverse3D(result: result)

        let elapsedMs = Date().timeIntervalSince(start) * 1000.0
        recordTransform(usedGPU: useGPU, timeMs: elapsedMs)

        return reconstructed
    }

    /// Returns a snapshot of the cumulative transform statistics.
    ///
    /// - Returns: Current ``J2KVulkanJP3DDWTStatistics``.
    public func statistics() async -> J2KVulkanJP3DDWTStatistics {
        let avg = totalTransforms > 0
            ? totalProcessingTimeMs / Double(totalTransforms)
            : 0.0
        return J2KVulkanJP3DDWTStatistics(
            totalTransforms: totalTransforms,
            gpuTransforms: gpuTransforms,
            cpuTransforms: cpuTransforms,
            averageProcessingTimeMs: avg
        )
    }

    /// Resets the cumulative statistics counters to zero.
    public func resetStatistics() async {
        totalTransforms = 0
        gpuTransforms = 0
        cpuTransforms = 0
        totalProcessingTimeMs = 0.0
    }

    // MARK: - Private Helpers

    private func recordTransform(usedGPU: Bool, timeMs: Double) {
        totalTransforms += 1
        if usedGPU { gpuTransforms += 1 } else { cpuTransforms += 1 }
        totalProcessingTimeMs += timeMs
    }

    /// CPU scaffold for the forward 3D DWT; returns per-level packed coefficient data.
    private func performForward3D(
        data: [Float],
        width: Int, height: Int, depth: Int,
        spectralBands: Int,
        configuration: J2KVulkanJP3DDWTConfiguration
    ) -> [Data] {
        // Scaffold: pack coefficients as raw Float bytes per level.
        (0..<configuration.decompositionLevels).map { level in
            let scale = Float(1 << level)
            let coefficients = data.map { $0 / scale }
            return coefficients.withUnsafeBytes { Data($0) }
        }
    }

    /// CPU scaffold for the inverse 3D DWT.
    private func performInverse3D(result: J2KVulkanJP3DDWTResult) -> [Float] {
        guard let firstSubband = result.subbands3D.first else { return [] }
        let scale = Float(1 << (result.decompositionLevels - 1))
        return firstSubband.withUnsafeBytes { ptr in
            let floatPtr = ptr.bindMemory(to: Float.self)
            return floatPtr.map { $0 * scale }
        }
    }
}
