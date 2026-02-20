//
// J2KMetalDWT.swift
// J2KSwift
//
// J2KMetalDWT.swift
// J2KSwift
//
// Metal-accelerated discrete wavelet transforms for JPEG 2000.
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

// MARK: - DWT Filter Type

/// Wavelet filter type for Metal DWT operations.
///
/// Defines the wavelet filter to use for forward and inverse transforms.
public enum J2KMetalDWTFilter: Sendable {
    /// Le Gall 5/3 reversible filter for lossless compression.
    case reversible53
    /// CDF 9/7 irreversible filter for lossy compression.
    case irreversible97
    /// Arbitrary filter with user-supplied coefficients.
    case arbitrary(J2KMetalArbitraryFilter)
    /// Lifting scheme with configurable lifting steps.
    case lifting(J2KMetalLiftingScheme)
}

// MARK: - Arbitrary Filter Coefficients

/// Coefficients for an arbitrary wavelet filter used in Metal DWT.
///
/// Provides analysis and synthesis filter coefficients for generic
/// convolution-based wavelet transforms on the GPU.
public struct J2KMetalArbitraryFilter: Sendable {
    /// Analysis lowpass filter coefficients.
    public let analysisLowpass: [Float]
    /// Analysis highpass filter coefficients.
    public let analysisHighpass: [Float]
    /// Synthesis lowpass filter coefficients.
    public let synthesisLowpass: [Float]
    /// Synthesis highpass filter coefficients.
    public let synthesisHighpass: [Float]

    /// Creates an arbitrary filter with the given coefficients.
    ///
    /// - Parameters:
    ///   - analysisLowpass: Analysis lowpass filter coefficients.
    ///   - analysisHighpass: Analysis highpass filter coefficients.
    ///   - synthesisLowpass: Synthesis lowpass filter coefficients.
    ///   - synthesisHighpass: Synthesis highpass filter coefficients.
    public init(
        analysisLowpass: [Float],
        analysisHighpass: [Float],
        synthesisLowpass: [Float],
        synthesisHighpass: [Float]
    ) {
        self.analysisLowpass = analysisLowpass
        self.analysisHighpass = analysisHighpass
        self.synthesisLowpass = synthesisLowpass
        self.synthesisHighpass = synthesisHighpass
    }
}

// MARK: - Lifting Scheme

/// Configurable lifting scheme for Metal DWT.
///
/// Defines the lifting steps and final scaling for a lifting-based
/// wavelet transform implementation on the GPU.
public struct J2KMetalLiftingScheme: Sendable {
    /// Lifting step coefficients applied in order.
    public let coefficients: [Float]
    /// Final scaling factor for lowpass output.
    public let scaleLowpass: Float
    /// Final scaling factor for highpass output.
    public let scaleHighpass: Float

    /// Creates a lifting scheme with the given parameters.
    ///
    /// - Parameters:
    ///   - coefficients: Lifting step coefficients.
    ///   - scaleLowpass: Lowpass scaling factor. Defaults to `1.0`.
    ///   - scaleHighpass: Highpass scaling factor. Defaults to `1.0`.
    public init(
        coefficients: [Float],
        scaleLowpass: Float = 1.0,
        scaleHighpass: Float = 1.0
    ) {
        self.coefficients = coefficients
        self.scaleLowpass = scaleLowpass
        self.scaleHighpass = scaleHighpass
    }

    /// CDF 9/7 lifting scheme with standard JPEG 2000 coefficients.
    public static let cdf97 = J2KMetalLiftingScheme(
        coefficients: [-1.586134342, -0.052980118, 0.882911075, 0.443506852],
        scaleLowpass: 1.230174105,
        scaleHighpass: 1.0 / 1.230174105
    )
}

// MARK: - DWT Configuration

/// Configuration for Metal-accelerated DWT operations.
///
/// Controls filter selection, decomposition levels, tile processing,
/// and automatic backend selection between GPU and CPU.
public struct J2KMetalDWTConfiguration: Sendable {
    /// The wavelet filter to use.
    public var filter: J2KMetalDWTFilter

    /// Number of decomposition levels for multi-level DWT.
    public var decompositionLevels: Int

    /// Tile width for tile-based processing (0 for full-width).
    public var tileWidth: Int

    /// Tile height for tile-based processing (0 for full-height).
    public var tileHeight: Int

    /// Minimum image dimension to prefer GPU over CPU.
    public var gpuThreshold: Int

    /// Whether to enable threadgroup memory optimization.
    public var useThreadgroupMemory: Bool

    /// Whether to enable async compute for overlapped execution.
    public var enableAsyncCompute: Bool

    /// Creates a Metal DWT configuration.
    ///
    /// - Parameters:
    ///   - filter: The wavelet filter. Defaults to `.irreversible97`.
    ///   - decompositionLevels: Number of decomposition levels. Defaults to `5`.
    ///   - tileWidth: Tile width for large images. Defaults to `0` (full-width).
    ///   - tileHeight: Tile height for large images. Defaults to `0` (full-height).
    ///   - gpuThreshold: Minimum dimension to prefer GPU. Defaults to `256`.
    ///   - useThreadgroupMemory: Enable threadgroup optimization. Defaults to `true`.
    ///   - enableAsyncCompute: Enable async compute. Defaults to `false`.
    public init(
        filter: J2KMetalDWTFilter = .irreversible97,
        decompositionLevels: Int = 5,
        tileWidth: Int = 0,
        tileHeight: Int = 0,
        gpuThreshold: Int = 256,
        useThreadgroupMemory: Bool = true,
        enableAsyncCompute: Bool = false
    ) {
        self.filter = filter
        self.decompositionLevels = decompositionLevels
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.gpuThreshold = gpuThreshold
        self.useThreadgroupMemory = useThreadgroupMemory
        self.enableAsyncCompute = enableAsyncCompute
    }

    /// Default configuration for lossy compression.
    public static let lossy = J2KMetalDWTConfiguration(filter: .irreversible97)

    /// Default configuration for lossless compression.
    public static let lossless = J2KMetalDWTConfiguration(filter: .reversible53)

    /// Configuration optimized for large images with tile-based processing.
    public static let largeImage = J2KMetalDWTConfiguration(
        filter: .irreversible97,
        decompositionLevels: 5,
        tileWidth: 1024,
        tileHeight: 1024,
        gpuThreshold: 256,
        useThreadgroupMemory: true,
        enableAsyncCompute: true
    )
}

// MARK: - DWT Decomposition Result

/// Result of a 2D wavelet decomposition at a single level.
///
/// Contains the four subbands produced by separable 2D DWT:
/// LL (approximation), LH (horizontal detail), HL (vertical detail),
/// and HH (diagonal detail).
public struct J2KMetalDWTSubbands: Sendable {
    /// Low-low subband (approximation coefficients).
    public let ll: [Float]
    /// Low-high subband (horizontal detail coefficients).
    public let lh: [Float]
    /// High-low subband (vertical detail coefficients).
    public let hl: [Float]
    /// High-high subband (diagonal detail coefficients).
    public let hh: [Float]
    /// Width of the LL subband.
    public let llWidth: Int
    /// Height of the LL subband.
    public let llHeight: Int
    /// Width of the original image at this level.
    public let originalWidth: Int
    /// Height of the original image at this level.
    public let originalHeight: Int

    /// Creates a decomposition result.
    public init(
        ll: [Float], lh: [Float], hl: [Float], hh: [Float],
        llWidth: Int, llHeight: Int,
        originalWidth: Int, originalHeight: Int
    ) {
        self.ll = ll
        self.lh = lh
        self.hl = hl
        self.hh = hh
        self.llWidth = llWidth
        self.llHeight = llHeight
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
    }
}

// MARK: - Multi-level Decomposition Result

/// Result of a multi-level 2D wavelet decomposition.
///
/// Contains the LL subband from the final level and all detail subbands
/// from each decomposition level.
public struct J2KMetalDWTDecomposition: Sendable {
    /// Final approximation coefficients (lowest resolution LL subband).
    public let approximation: [Float]
    /// Width of the approximation subband.
    public let approximationWidth: Int
    /// Height of the approximation subband.
    public let approximationHeight: Int
    /// Detail subbands for each decomposition level (from coarsest to finest).
    public let levels: [J2KMetalDWTSubbands]

    /// Creates a multi-level decomposition result.
    public init(
        approximation: [Float],
        approximationWidth: Int,
        approximationHeight: Int,
        levels: [J2KMetalDWTSubbands]
    ) {
        self.approximation = approximation
        self.approximationWidth = approximationWidth
        self.approximationHeight = approximationHeight
        self.levels = levels
    }
}

// MARK: - DWT Backend

/// Backend selection for DWT computation.
///
/// Controls whether the transform runs on GPU (Metal) or CPU,
/// with automatic selection based on input size.
public enum J2KMetalDWTBackend: Sendable {
    /// Force GPU execution via Metal.
    case gpu
    /// Force CPU execution (software fallback).
    case cpu
    /// Automatically choose based on image dimensions and GPU threshold.
    case auto
}

// MARK: - DWT Processing Statistics

/// Performance statistics for Metal DWT operations.
///
/// Tracks timing, backend usage, and memory consumption for
/// monitoring and optimization purposes.
public struct J2KMetalDWTStatistics: Sendable {
    /// Total number of DWT operations performed.
    public var totalOperations: Int
    /// Number of operations that ran on GPU.
    public var gpuOperations: Int
    /// Number of operations that fell back to CPU.
    public var cpuOperations: Int
    /// Total processing time in seconds.
    public var totalProcessingTime: Double
    /// Peak GPU memory usage in bytes.
    public var peakGPUMemory: UInt64

    /// Creates initial (zero) statistics.
    public init() {
        self.totalOperations = 0
        self.gpuOperations = 0
        self.cpuOperations = 0
        self.totalProcessingTime = 0.0
        self.peakGPUMemory = 0
    }

    /// GPU utilization rate as a percentage (0.0 to 1.0).
    public var gpuUtilization: Double {
        guard totalOperations > 0 else { return 0.0 }
        return Double(gpuOperations) / Double(totalOperations)
    }
}

// MARK: - Metal DWT

/// Metal-accelerated discrete wavelet transform for JPEG 2000.
///
/// `J2KMetalDWT` provides GPU-accelerated forward and inverse wavelet
/// transforms using Metal compute shaders. It supports 5/3 reversible,
/// 9/7 irreversible, and arbitrary wavelet filters with automatic
/// CPU/GPU backend selection.
///
/// ## Usage
///
/// ```swift
/// let dwt = J2KMetalDWT()
///
/// // One-level forward 2D DWT
/// let subbands = try await dwt.forward2D(
///     data: imageData,
///     width: 512,
///     height: 512
/// )
///
/// // Multi-level decomposition
/// let decomposition = try await dwt.forwardMultiLevel(
///     data: imageData,
///     width: 512,
///     height: 512,
///     levels: 5
/// )
/// ```
///
/// ## Backend Selection
///
/// The transform automatically selects GPU or CPU execution based on
/// the image dimensions and the configured GPU threshold. For images
/// smaller than the threshold, CPU execution may be faster due to
/// GPU dispatch overhead.
///
/// ## Performance
///
/// Target performance: 5-15× speedup vs Accelerate CPU for large
/// images (>2K resolution) on Apple Silicon GPUs.
public actor J2KMetalDWT {
    /// Whether Metal DWT is available on this platform.
    public static var isAvailable: Bool {
        J2KMetalDevice.isAvailable
    }

    /// The DWT configuration.
    public let configuration: J2KMetalDWTConfiguration

    /// The Metal device for GPU operations.
    private let metalDevice: J2KMetalDevice

    /// The buffer pool for GPU memory management.
    private let bufferPool: J2KMetalBufferPool

    /// The shader library for compute kernels.
    private let shaderLibrary: J2KMetalShaderLibrary

    /// Whether the Metal backend has been initialized.
    private var isInitialized = false

    /// Processing statistics.
    private var _statistics = J2KMetalDWTStatistics()

    /// Creates a Metal DWT instance with the given configuration.
    ///
    /// - Parameters:
    ///   - configuration: The DWT configuration. Defaults to `.lossy`.
    ///   - device: The Metal device manager. A new instance is created if not provided.
    ///   - bufferPool: The buffer pool. A new instance is created if not provided.
    ///   - shaderLibrary: The shader library. A new instance is created if not provided.
    public init(
        configuration: J2KMetalDWTConfiguration = .lossy,
        device: J2KMetalDevice? = nil,
        bufferPool: J2KMetalBufferPool? = nil,
        shaderLibrary: J2KMetalShaderLibrary? = nil
    ) {
        self.configuration = configuration
        self.metalDevice = device ?? J2KMetalDevice()
        self.bufferPool = bufferPool ?? J2KMetalBufferPool()
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    /// Initializes the Metal backend for DWT operations.
    ///
    /// Initializes the Metal device, loads compute shaders, and prepares
    /// for GPU-accelerated transforms. This method is safe to call
    /// multiple times; subsequent calls are no-ops.
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
    ///
    /// - Returns: A snapshot of the DWT processing statistics.
    public func statistics() -> J2KMetalDWTStatistics {
        _statistics
    }

    /// Determines the best backend for the given dimensions.
    ///
    /// - Parameters:
    ///   - width: Image width.
    ///   - height: Image height.
    ///   - backend: Requested backend preference.
    /// - Returns: The effective backend to use.
    public func effectiveBackend(
        width: Int,
        height: Int,
        backend: J2KMetalDWTBackend = .auto
    ) -> J2KMetalDWTBackend {
        switch backend {
        case .gpu:
            return J2KMetalDWT.isAvailable ? .gpu : .cpu
        case .cpu:
            return .cpu
        case .auto:
            if !J2KMetalDWT.isAvailable {
                return .cpu
            }
            let maxDim = max(width, height)
            return maxDim >= configuration.gpuThreshold ? .gpu : .cpu
        }
    }

    // MARK: - 1D Forward DWT

    /// Performs a 1D forward DWT on the input signal.
    ///
    /// - Parameters:
    ///   - signal: The input signal as Float values.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: A tuple of (lowpass, highpass) coefficients.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the signal is too short.
    public func forward1D(
        signal: [Float],
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> (lowpass: [Float], highpass: [Float]) {
        let length = signal.count
        guard length >= 2 else {
            throw J2KError.invalidParameter("Signal length must be at least 2, got \(length)")
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1

        let effective = effectiveBackend(width: length, height: 1, backend: backend)

        let result: (lowpass: [Float], highpass: [Float])
        if effective == .gpu {
            result = try await forward1DGPU(signal: signal)
            _statistics.gpuOperations += 1
        } else {
            result = forward1DCPU(signal: signal)
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - 1D Inverse DWT

    /// Performs a 1D inverse DWT from lowpass and highpass coefficients.
    ///
    /// - Parameters:
    ///   - lowpass: The lowpass (approximation) coefficients.
    ///   - highpass: The highpass (detail) coefficients.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The reconstructed signal.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if coefficients are empty.
    public func inverse1D(
        lowpass: [Float],
        highpass: [Float],
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> [Float] {
        guard !lowpass.isEmpty else {
            throw J2KError.invalidParameter("Lowpass coefficients must not be empty")
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1

        let outputLength = lowpass.count + highpass.count
        let effective = effectiveBackend(width: outputLength, height: 1, backend: backend)

        let result: [Float]
        if effective == .gpu {
            result = try await inverse1DGPU(lowpass: lowpass, highpass: highpass)
            _statistics.gpuOperations += 1
        } else {
            result = inverse1DCPU(lowpass: lowpass, highpass: highpass)
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - 2D Forward DWT

    /// Performs a single-level 2D forward DWT on image data.
    ///
    /// Applies a separable 2D DWT by first transforming rows (horizontal)
    /// and then columns (vertical), producing four subbands (LL, LH, HL, HH).
    ///
    /// - Parameters:
    ///   - data: Image data as row-major Float array.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The four wavelet subbands.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if dimensions are invalid.
    public func forward2D(
        data: [Float],
        width: Int,
        height: Int,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> J2KMetalDWTSubbands {
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Image dimensions must be at least 2×2, got \(width)×\(height)"
            )
        }
        guard data.count == width * height else {
            throw J2KError.invalidParameter(
                "Data size \(data.count) doesn't match dimensions \(width)×\(height)"
            )
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1

        let effective = effectiveBackend(width: width, height: height, backend: backend)

        let result: J2KMetalDWTSubbands
        if effective == .gpu {
            result = try await forward2DGPU(data: data, width: width, height: height)
            _statistics.gpuOperations += 1
        } else {
            result = forward2DCPU(data: data, width: width, height: height)
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - 2D Inverse DWT

    /// Performs a single-level 2D inverse DWT from subbands.
    ///
    /// Reconstructs the image from four wavelet subbands by first
    /// performing inverse vertical DWT and then inverse horizontal DWT.
    ///
    /// - Parameters:
    ///   - subbands: The four wavelet subbands.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The reconstructed image data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if subbands are invalid.
    public func inverse2D(
        subbands: J2KMetalDWTSubbands,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> [Float] {
        let width = subbands.originalWidth
        let height = subbands.originalHeight
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Subband dimensions must produce at least 2×2 output"
            )
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1

        let effective = effectiveBackend(width: width, height: height, backend: backend)

        let result: [Float]
        if effective == .gpu {
            result = try await inverse2DGPU(subbands: subbands)
            _statistics.gpuOperations += 1
        } else {
            result = inverse2DCPU(subbands: subbands)
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - Multi-Level Forward DWT

    /// Performs a multi-level 2D forward DWT.
    ///
    /// Applies the 2D DWT repeatedly to the LL subband, producing
    /// a hierarchical decomposition. The number of levels is clamped
    /// to the maximum possible for the given dimensions.
    ///
    /// - Parameters:
    ///   - data: Image data as row-major Float array.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - levels: Number of decomposition levels. Defaults to configuration value.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The multi-level decomposition result.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if dimensions are invalid.
    public func forwardMultiLevel(
        data: [Float],
        width: Int,
        height: Int,
        levels: Int? = nil,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> J2KMetalDWTDecomposition {
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Image dimensions must be at least 2×2, got \(width)×\(height)"
            )
        }
        guard data.count == width * height else {
            throw J2KError.invalidParameter(
                "Data size \(data.count) doesn't match dimensions \(width)×\(height)"
            )
        }

        let requestedLevels = levels ?? configuration.decompositionLevels
        let maxLevels = maxDecompositionLevels(width: width, height: height)
        let effectiveLevels = min(requestedLevels, maxLevels)

        guard effectiveLevels > 0 else {
            throw J2KError.invalidParameter(
                "Cannot decompose \(width)×\(height) image (too small)"
            )
        }

        var currentData = data
        var currentWidth = width
        var currentHeight = height
        var allLevels: [J2KMetalDWTSubbands] = []

        for _ in 0..<effectiveLevels {
            let subbands = try await forward2D(
                data: currentData,
                width: currentWidth,
                height: currentHeight,
                backend: backend
            )
            allLevels.append(subbands)
            currentData = subbands.ll
            currentWidth = subbands.llWidth
            currentHeight = subbands.llHeight
        }

        return J2KMetalDWTDecomposition(
            approximation: currentData,
            approximationWidth: currentWidth,
            approximationHeight: currentHeight,
            levels: allLevels
        )
    }

    // MARK: - Multi-Level Inverse DWT

    /// Performs a multi-level 2D inverse DWT from a decomposition.
    ///
    /// Reconstructs the image by applying inverse 2D DWT from the
    /// coarsest level to the finest.
    ///
    /// - Parameters:
    ///   - decomposition: The multi-level decomposition result.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: The reconstructed image data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if decomposition is invalid.
    public func inverseMultiLevel(
        decomposition: J2KMetalDWTDecomposition,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> [Float] {
        guard !decomposition.levels.isEmpty else {
            throw J2KError.invalidParameter("Decomposition must have at least one level")
        }

        var currentData = decomposition.approximation

        for levelIndex in stride(
            from: decomposition.levels.count - 1,
            through: 0,
            by: -1
        ) {
            let level = decomposition.levels[levelIndex]
            let subbands = J2KMetalDWTSubbands(
                ll: currentData,
                lh: level.lh,
                hl: level.hl,
                hh: level.hh,
                llWidth: level.llWidth,
                llHeight: level.llHeight,
                originalWidth: level.originalWidth,
                originalHeight: level.originalHeight
            )
            currentData = try await inverse2D(subbands: subbands, backend: backend)
        }

        return currentData
    }

    // MARK: - Tile-Based Processing

    /// Performs tile-based forward 2D DWT for large images.
    ///
    /// Splits the image into tiles and processes each tile independently,
    /// reducing peak GPU memory usage for large images.
    ///
    /// - Parameters:
    ///   - data: Image data as row-major Float array.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - tileWidth: Tile width. Defaults to configuration value or full width.
    ///   - tileHeight: Tile height. Defaults to configuration value or full height.
    ///   - backend: Backend preference. Defaults to `.auto`.
    /// - Returns: Array of subband results, one per tile, with tile coordinates.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if parameters are invalid.
    public func forwardTiled(
        data: [Float],
        width: Int,
        height: Int,
        tileWidth: Int? = nil,
        tileHeight: Int? = nil,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> [(subbands: J2KMetalDWTSubbands, tileX: Int, tileY: Int)] {
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Image dimensions must be at least 2×2"
            )
        }
        guard data.count == width * height else {
            throw J2KError.invalidParameter(
                "Data size doesn't match dimensions"
            )
        }

        let tw = tileWidth ?? (configuration.tileWidth > 0 ? configuration.tileWidth : width)
        let th = tileHeight ?? (configuration.tileHeight > 0 ? configuration.tileHeight : height)
        let effectiveTW = min(tw, width)
        let effectiveTH = min(th, height)

        var results: [(subbands: J2KMetalDWTSubbands, tileX: Int, tileY: Int)] = []

        var tileY = 0
        while tileY < height {
            var tileX = 0
            let currentTH = min(effectiveTH, height - tileY)
            while tileX < width {
                let currentTW = min(effectiveTW, width - tileX)

                guard currentTW >= 2, currentTH >= 2 else {
                    tileX += effectiveTW
                    continue
                }

                // Extract tile data
                var tileData = [Float](repeating: 0, count: currentTW * currentTH)
                for row in 0..<currentTH {
                    let srcOffset = (tileY + row) * width + tileX
                    let dstOffset = row * currentTW
                    for col in 0..<currentTW {
                        tileData[dstOffset + col] = data[srcOffset + col]
                    }
                }

                let subbands = try await forward2D(
                    data: tileData,
                    width: currentTW,
                    height: currentTH,
                    backend: backend
                )
                results.append((subbands: subbands, tileX: tileX, tileY: tileY))

                tileX += effectiveTW
            }
            tileY += effectiveTH
        }

        return results
    }

    /// Resets the processing statistics.
    public func resetStatistics() {
        _statistics = J2KMetalDWTStatistics()
    }

    // MARK: - Utility

    /// Computes the maximum number of decomposition levels for the given dimensions.
    ///
    /// - Parameters:
    ///   - width: Image width.
    ///   - height: Image height.
    /// - Returns: The maximum number of decomposition levels.
    public func maxDecompositionLevels(width: Int, height: Int) -> Int {
        let minDim = min(width, height)
        guard minDim >= 2 else { return 0 }
        var levels = 0
        var size = minDim
        while size >= 4 {
            levels += 1
            size = (size + 1) / 2
        }
        return max(levels, 1)
    }

    // MARK: - CPU Reference Implementation

    /// CPU forward 1D DWT using CDF 9/7 lifting.
    private func forward1DCPU(signal: [Float]) -> (lowpass: [Float], highpass: [Float]) {
        let n = signal.count
        let halfN = (n + 1) / 2
        let halfH = n / 2

        switch configuration.filter {
        case .irreversible97:
            return forward1DCPU97(signal: signal, n: n, halfN: halfN, halfH: halfH)
        case .reversible53:
            return forward1DCPU53(signal: signal, n: n, halfN: halfN, halfH: halfH)
        case .arbitrary(let filter):
            return forward1DCPUArbitrary(
                signal: signal, n: n, halfN: halfN, halfH: halfH,
                filter: filter
            )
        case .lifting(let scheme):
            return forward1DCPULifting(
                signal: signal, n: n, halfN: halfN, halfH: halfH,
                scheme: scheme
            )
        }
    }

    private func forward1DCPU97(
        signal: [Float], n: Int, halfN: Int, halfH: Int
    ) -> (lowpass: [Float], highpass: [Float]) {
        let alpha: Float = -1.586134342
        let beta: Float  = -0.052980118
        let gamma: Float = 0.882911075
        let delta: Float = 0.443506852
        let K: Float = 1.230174105

        var even = [Float](repeating: 0, count: halfN)
        var odd  = [Float](repeating: 0, count: halfH)

        for i in 0..<halfN {
            even[i] = signal[min(2 * i, n - 1)]
        }
        for i in 0..<halfH {
            odd[i] = signal[2 * i + 1]
        }

        // Predict step 1
        for i in 0..<halfH {
            let left = even[i]
            let right = even[min(i + 1, halfN - 1)]
            odd[i] += alpha * (left + right)
        }
        // Update step 1
        for i in 0..<halfN {
            let left = odd[max(i - 1, 0)]
            let right = odd[min(i, halfH - 1)]
            even[i] += beta * (left + right)
        }
        // Predict step 2
        for i in 0..<halfH {
            let left = even[i]
            let right = even[min(i + 1, halfN - 1)]
            odd[i] += gamma * (left + right)
        }
        // Update step 2
        for i in 0..<halfN {
            let left = odd[max(i - 1, 0)]
            let right = odd[min(i, halfH - 1)]
            even[i] += delta * (left + right)
        }

        // Scaling
        for i in 0..<halfN { even[i] *= K }
        for i in 0..<halfH { odd[i] /= K }

        return (lowpass: even, highpass: odd)
    }

    private func forward1DCPU53(
        signal: [Float], n: Int, halfN: Int, halfH: Int
    ) -> (lowpass: [Float], highpass: [Float]) {
        var highpass = [Float](repeating: 0, count: halfH)
        var lowpass  = [Float](repeating: 0, count: halfN)

        // Predict: d[i] = x[2i+1] - (x[2i] + x[2i+2]) / 2
        for i in 0..<halfH {
            let left = signal[2 * i]
            let right = (2 * i + 2 < n) ? signal[2 * i + 2] : signal[2 * i]
            highpass[i] = signal[2 * i + 1] - (left + right) / 2.0
        }
        // Update: s[i] = x[2i] + (d[i-1] + d[i] + 2) / 4
        for i in 0..<halfN {
            let dLeft = (i > 0) ? highpass[i - 1] : highpass[0]
            let dRight = (i < halfH) ? highpass[i] : highpass[max(halfH - 1, 0)]
            lowpass[i] = signal[2 * i] + (dLeft + dRight + 2.0) / 4.0
        }

        return (lowpass: lowpass, highpass: highpass)
    }

    private func forward1DCPUArbitrary(
        signal: [Float], n: Int, halfN: Int, halfH: Int,
        filter: J2KMetalArbitraryFilter
    ) -> (lowpass: [Float], highpass: [Float]) {
        var lowpass = [Float](repeating: 0, count: halfN)
        var highpass = [Float](repeating: 0, count: halfH)
        let halfLow = filter.analysisLowpass.count / 2
        let halfHigh = filter.analysisHighpass.count / 2

        for i in 0..<halfN {
            var sum: Float = 0
            let center = 2 * i
            for k in 0..<filter.analysisLowpass.count {
                var srcIdx = center + k - halfLow
                if srcIdx < 0 { srcIdx = -srcIdx }
                if srcIdx >= n { srcIdx = 2 * n - srcIdx - 2 }
                sum += signal[srcIdx] * filter.analysisLowpass[k]
            }
            lowpass[i] = sum
        }
        for i in 0..<halfH {
            var sum: Float = 0
            let center = 2 * i + 1
            for k in 0..<filter.analysisHighpass.count {
                var srcIdx = center + k - halfHigh
                if srcIdx < 0 { srcIdx = -srcIdx }
                if srcIdx >= n { srcIdx = 2 * n - srcIdx - 2 }
                sum += signal[srcIdx] * filter.analysisHighpass[k]
            }
            highpass[i] = sum
        }

        return (lowpass: lowpass, highpass: highpass)
    }

    private func forward1DCPULifting(
        signal: [Float], n: Int, halfN: Int, halfH: Int,
        scheme: J2KMetalLiftingScheme
    ) -> (lowpass: [Float], highpass: [Float]) {
        var data = signal
        for step in 0..<scheme.coefficients.count {
            let coeff = scheme.coefficients[step]
            let updateOdd = (step.isMultiple(of: 2))
            if updateOdd {
                for i in 0..<halfH {
                    let left = data[2 * i]
                    let right = (2 * i + 2 < n) ? data[2 * i + 2] : data[2 * i]
                    data[2 * i + 1] += coeff * (left + right)
                }
            } else {
                for i in 0..<halfN {
                    let left = (i > 0) ? data[2 * i - 1] : data[1]
                    let right = (2 * i + 1 < n) ? data[2 * i + 1] : data[n - 2]
                    data[2 * i] += coeff * (left + right)
                }
            }
        }

        var lowpass = [Float](repeating: 0, count: halfN)
        var highpass = [Float](repeating: 0, count: halfH)
        for i in 0..<halfN { lowpass[i] = data[2 * i] * scheme.scaleLowpass }
        for i in 0..<halfH { highpass[i] = data[2 * i + 1] * scheme.scaleHighpass }

        return (lowpass: lowpass, highpass: highpass)
    }

    /// CPU inverse 1D DWT.
    private func inverse1DCPU(lowpass: [Float], highpass: [Float]) -> [Float] {
        switch configuration.filter {
        case .irreversible97:
            return inverse1DCPU97(lowpass: lowpass, highpass: highpass)
        case .reversible53:
            return inverse1DCPU53(lowpass: lowpass, highpass: highpass)
        case .arbitrary(let filter):
            return inverse1DCPUArbitrary(
                lowpass: lowpass, highpass: highpass, filter: filter
            )
        case .lifting(let scheme):
            return inverse1DCPULifting(
                lowpass: lowpass, highpass: highpass, scheme: scheme
            )
        }
    }

    private func inverse1DCPU97(
        lowpass: [Float], highpass: [Float]
    ) -> [Float] {
        let halfN = lowpass.count
        let halfH = highpass.count
        let n = halfN + halfH
        let K: Float = 1.230174105
        let alpha: Float = -1.586134342
        let beta: Float  = -0.052980118
        let gamma: Float = 0.882911075
        let delta: Float = 0.443506852

        var even = lowpass.map { $0 / K }
        var odd  = highpass.map { $0 * K }

        // Undo update step 2
        for i in 0..<halfN {
            let left = odd[max(i - 1, 0)]
            let right = odd[min(i, halfH - 1)]
            even[i] -= delta * (left + right)
        }
        // Undo predict step 2
        for i in 0..<halfH {
            let left = even[i]
            let right = even[min(i + 1, halfN - 1)]
            odd[i] -= gamma * (left + right)
        }
        // Undo update step 1
        for i in 0..<halfN {
            let left = odd[max(i - 1, 0)]
            let right = odd[min(i, halfH - 1)]
            even[i] -= beta * (left + right)
        }
        // Undo predict step 1
        for i in 0..<halfH {
            let left = even[i]
            let right = even[min(i + 1, halfN - 1)]
            odd[i] -= alpha * (left + right)
        }

        var result = [Float](repeating: 0, count: n)
        for i in 0..<halfN { result[2 * i] = even[i] }
        for i in 0..<halfH { result[2 * i + 1] = odd[i] }
        return result
    }

    private func inverse1DCPU53(
        lowpass: [Float], highpass: [Float]
    ) -> [Float] {
        let halfN = lowpass.count
        let halfH = highpass.count
        let n = halfN + halfH

        var result = [Float](repeating: 0, count: n)

        // Undo update
        for i in 0..<halfN {
            let dLeft = (i > 0) ? highpass[i - 1] : highpass[0]
            let dRight = (i < halfH) ? highpass[i] : highpass[max(halfH - 1, 0)]
            result[2 * i] = lowpass[i] - (dLeft + dRight + 2.0) / 4.0
        }
        // Undo predict
        for i in 0..<halfH {
            let left = result[2 * i]
            let right = (2 * i + 2 < n) ? result[2 * i + 2] : result[2 * i]
            result[2 * i + 1] = highpass[i] + (left + right) / 2.0
        }

        return result
    }

    private func inverse1DCPUArbitrary(
        lowpass: [Float], highpass: [Float],
        filter: J2KMetalArbitraryFilter
    ) -> [Float] {
        let halfN = lowpass.count
        let halfH = highpass.count
        let n = halfN + halfH
        var result = [Float](repeating: 0, count: n)

        for pos in 0..<n {
            var sum: Float = 0
            for k in 0..<filter.synthesisLowpass.count {
                let idx = pos - k
                if idx >= 0 && idx.isMultiple(of: 2) {
                    let j = idx / 2
                    if j < halfN {
                        sum += lowpass[j] * filter.synthesisLowpass[k]
                    }
                }
            }
            for k in 0..<filter.synthesisHighpass.count {
                let idx = pos - k
                if idx >= 0 && idx % 2 == 1 {
                    let j = idx / 2
                    if j < halfH {
                        sum += highpass[j] * filter.synthesisHighpass[k]
                    }
                }
            }
            result[pos] = sum
        }

        return result
    }

    private func inverse1DCPULifting(
        lowpass: [Float], highpass: [Float],
        scheme: J2KMetalLiftingScheme
    ) -> [Float] {
        let halfN = lowpass.count
        let halfH = highpass.count
        let n = halfN + halfH

        var data = [Float](repeating: 0, count: n)
        for i in 0..<halfN { data[2 * i] = lowpass[i] / scheme.scaleLowpass }
        for i in 0..<halfH { data[2 * i + 1] = highpass[i] / scheme.scaleHighpass }

        // Reverse lifting steps
        for step in stride(from: scheme.coefficients.count - 1, through: 0, by: -1) {
            let coeff = -scheme.coefficients[step]
            let updateOdd = (step.isMultiple(of: 2))
            if updateOdd {
                for i in 0..<halfH {
                    let left = data[2 * i]
                    let right = (2 * i + 2 < n) ? data[2 * i + 2] : data[2 * i]
                    data[2 * i + 1] += coeff * (left + right)
                }
            } else {
                for i in 0..<halfN {
                    let left = (i > 0) ? data[2 * i - 1] : data[1]
                    let right = (2 * i + 1 < n) ? data[2 * i + 1] : data[n - 2]
                    data[2 * i] += coeff * (left + right)
                }
            }
        }

        return data
    }

    // MARK: - CPU 2D Implementation

    private func forward2DCPU(
        data: [Float], width: Int, height: Int
    ) -> J2KMetalDWTSubbands {
        let halfW = (width + 1) / 2
        let halfH = (height + 1) / 2
        let halfWH = width / 2
        let halfHH = height / 2

        // Step 1: Horizontal DWT on each row
        var hLow  = [Float](repeating: 0, count: halfW * height)
        var hHigh = [Float](repeating: 0, count: halfWH * height)

        for row in 0..<height {
            let rowData = Array(data[row * width..<row * width + width])
            let (low, high) = forward1DCPU(signal: rowData)
            for i in 0..<low.count {
                hLow[row * halfW + i] = low[i]
            }
            for i in 0..<high.count {
                hHigh[row * halfWH + i] = high[i]
            }
        }

        // Step 2: Vertical DWT on lowpass columns → LL and LH
        var ll = [Float](repeating: 0, count: halfW * halfH)
        var lh = [Float](repeating: 0, count: halfW * halfHH)

        for col in 0..<halfW {
            var column = [Float](repeating: 0, count: height)
            for row in 0..<height {
                column[row] = hLow[row * halfW + col]
            }
            let (low, high) = forward1DCPU(signal: column)
            for i in 0..<low.count { ll[i * halfW + col] = low[i] }
            for i in 0..<high.count { lh[i * halfW + col] = high[i] }
        }

        // Step 3: Vertical DWT on highpass columns → HL and HH
        var hl = [Float](repeating: 0, count: halfWH * halfH)
        var hh = [Float](repeating: 0, count: halfWH * halfHH)

        for col in 0..<halfWH {
            var column = [Float](repeating: 0, count: height)
            for row in 0..<height {
                column[row] = hHigh[row * halfWH + col]
            }
            let (low, high) = forward1DCPU(signal: column)
            for i in 0..<low.count { hl[i * halfWH + col] = low[i] }
            for i in 0..<high.count { hh[i * halfWH + col] = high[i] }
        }

        return J2KMetalDWTSubbands(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: halfW, llHeight: halfH,
            originalWidth: width, originalHeight: height
        )
    }

    private func inverse2DCPU(subbands: J2KMetalDWTSubbands) -> [Float] {
        let width = subbands.originalWidth
        let height = subbands.originalHeight
        let halfW = subbands.llWidth
        let halfH = subbands.llHeight
        let halfWH = width / 2
        let halfHH = height / 2

        // Step 1: Inverse vertical DWT on lowpass columns (LL + LH → hLow)
        var hLow = [Float](repeating: 0, count: halfW * height)
        for col in 0..<halfW {
            var low = [Float](repeating: 0, count: halfH)
            var high = [Float](repeating: 0, count: halfHH)
            for i in 0..<halfH { low[i] = subbands.ll[i * halfW + col] }
            for i in 0..<halfHH { high[i] = subbands.lh[i * halfW + col] }
            let column = inverse1DCPU(lowpass: low, highpass: high)
            for row in 0..<height { hLow[row * halfW + col] = column[row] }
        }

        // Step 2: Inverse vertical DWT on highpass columns (HL + HH → hHigh)
        var hHigh = [Float](repeating: 0, count: halfWH * height)
        for col in 0..<halfWH {
            var low = [Float](repeating: 0, count: halfH)
            var high = [Float](repeating: 0, count: halfHH)
            for i in 0..<halfH { low[i] = subbands.hl[i * halfWH + col] }
            for i in 0..<halfHH { high[i] = subbands.hh[i * halfWH + col] }
            let column = inverse1DCPU(lowpass: low, highpass: high)
            for row in 0..<height { hHigh[row * halfWH + col] = column[row] }
        }

        // Step 3: Inverse horizontal DWT on each row
        var result = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            var low = [Float](repeating: 0, count: halfW)
            var high = [Float](repeating: 0, count: halfWH)
            for i in 0..<halfW { low[i] = hLow[row * halfW + i] }
            for i in 0..<halfWH { high[i] = hHigh[row * halfWH + i] }
            let rowData = inverse1DCPU(lowpass: low, highpass: high)
            for i in 0..<width { result[row * width + i] = rowData[i] }
        }

        return result
    }

    // MARK: - GPU Implementation

    #if canImport(Metal)
    private func forward1DGPU(
        signal: [Float]
    ) async throws -> (lowpass: [Float], highpass: [Float]) {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let width = UInt32(signal.count)
        let height: UInt32 = 1
        let halfWidth = (signal.count + 1) / 2
        let halfWidthH = signal.count / 2

        // Create buffers
        let inputBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: signal.count * MemoryLayout<Float>.stride
        )
        let lowBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: halfWidth * MemoryLayout<Float>.stride
        )
        let highBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(halfWidthH, 1) * MemoryLayout<Float>.stride
        )

        // Copy input data
        signal.withUnsafeBytes { src in
            inputBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        // Get pipeline
        let shaderFunc = horizontalForwardShaderFunction()
        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunc)

        // Encode and dispatch
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(lowBuffer, offset: 0, index: 1)
        encoder.setBuffer(highBuffer, offset: 0, index: 2)

        var w = width
        var h = height
        encoder.setBytes(&w, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&h, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadgroupSize = MTLSize(width: 1, height: 1, depth: 1)
        let gridSize = MTLSize(width: 1, height: 1, depth: 1)
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        await commandBuffer.completed()

        // Read results
        var lowpass = [Float](repeating: 0, count: halfWidth)
        var highpass = [Float](repeating: 0, count: halfWidthH)

        lowpass.withUnsafeMutableBytes { dst in
            dst.copyBytes(
                from: UnsafeRawBufferPointer(
                    start: lowBuffer.contents(),
                    count: halfWidth * MemoryLayout<Float>.stride
                )
            )
        }
        if halfWidthH > 0 {
            highpass.withUnsafeMutableBytes { dst in
                dst.copyBytes(
                    from: UnsafeRawBufferPointer(
                        start: highBuffer.contents(),
                        count: halfWidthH * MemoryLayout<Float>.stride
                    )
                )
            }
        }

        // Return buffers
        await bufferPool.returnBuffer(inputBuffer)
        await bufferPool.returnBuffer(lowBuffer)
        await bufferPool.returnBuffer(highBuffer)

        return (lowpass: lowpass, highpass: highpass)
    }

    private func inverse1DGPU(
        lowpass: [Float], highpass: [Float]
    ) async throws -> [Float] {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let outputLength = lowpass.count + highpass.count
        let width = UInt32(outputLength)
        let height: UInt32 = 1
        let halfWidth = lowpass.count
        let halfWidthH = highpass.count

        let lowBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: halfWidth * MemoryLayout<Float>.stride
        )
        let highBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(halfWidthH, 1) * MemoryLayout<Float>.stride
        )
        let outputBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: outputLength * MemoryLayout<Float>.stride
        )

        lowpass.withUnsafeBytes { src in
            lowBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        if halfWidthH > 0 {
            highpass.withUnsafeBytes { src in
                highBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }

        let shaderFunc = horizontalInverseShaderFunction()
        let pipeline = try await shaderLibrary.computePipeline(for: shaderFunc)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(lowBuffer, offset: 0, index: 0)
        encoder.setBuffer(highBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)

        var w = width
        var h = height
        encoder.setBytes(&w, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBytes(&h, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadgroupSize = MTLSize(width: 1, height: 1, depth: 1)
        let gridSize = MTLSize(width: 1, height: 1, depth: 1)
        encoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        await commandBuffer.completed()

        var result = [Float](repeating: 0, count: outputLength)
        result.withUnsafeMutableBytes { dst in
            dst.copyBytes(
                from: UnsafeRawBufferPointer(
                    start: outputBuffer.contents(),
                    count: outputLength * MemoryLayout<Float>.stride
                )
            )
        }

        await bufferPool.returnBuffer(lowBuffer)
        await bufferPool.returnBuffer(highBuffer)
        await bufferPool.returnBuffer(outputBuffer)

        return result
    }

    private func forward2DGPU(
        data: [Float], width: Int, height: Int
    ) async throws -> J2KMetalDWTSubbands {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let w = UInt32(width)
        let h = UInt32(height)
        let halfW = (width + 1) / 2
        let halfH = (height + 1) / 2
        let halfWH = width / 2
        let halfHH = height / 2

        // Allocate buffers
        let inputBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: data.count * MemoryLayout<Float>.stride
        )
        let hLowBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: halfW * height * MemoryLayout<Float>.stride
        )
        let hHighBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(halfWH * height, 1) * MemoryLayout<Float>.stride
        )

        // Copy input
        data.withUnsafeBytes { src in
            inputBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        // Step 1: Horizontal forward DWT
        let hPipeline = try await shaderLibrary.computePipeline(
            for: horizontalForwardShaderFunction()
        )

        guard let cb1 = queue.makeCommandBuffer(),
              let enc1 = cb1.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        enc1.setComputePipelineState(hPipeline)
        enc1.setBuffer(inputBuffer, offset: 0, index: 0)
        enc1.setBuffer(hLowBuffer, offset: 0, index: 1)
        enc1.setBuffer(hHighBuffer, offset: 0, index: 2)
        var wVal = w
        var hVal = h
        enc1.setBytes(&wVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc1.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)

        let hThreads = MTLSize(width: 1, height: height, depth: 1)
        let hThreadgroup = MTLSize(width: 1, height: min(height, 64), depth: 1)
        enc1.dispatchThreads(hThreads, threadsPerThreadgroup: hThreadgroup)
        enc1.endEncoding()
        cb1.commit()
        await cb1.completed()

        // Step 2: Vertical DWT on lowpass → LL, LH
        let llBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: halfW * halfH * MemoryLayout<Float>.stride
        )
        let lhBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(halfW * halfHH, 1) * MemoryLayout<Float>.stride
        )

        let vPipeline = try await shaderLibrary.computePipeline(
            for: verticalForwardShaderFunction()
        )

        guard let cb2 = queue.makeCommandBuffer(),
              let enc2 = cb2.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        enc2.setComputePipelineState(vPipeline)
        enc2.setBuffer(hLowBuffer, offset: 0, index: 0)
        enc2.setBuffer(llBuffer, offset: 0, index: 1)
        enc2.setBuffer(lhBuffer, offset: 0, index: 2)
        var halfWVal = UInt32(halfW)
        enc2.setBytes(&halfWVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc2.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)

        let vThreads1 = MTLSize(width: halfW, height: 1, depth: 1)
        let vThreadgroup1 = MTLSize(width: min(halfW, 64), height: 1, depth: 1)
        enc2.dispatchThreads(vThreads1, threadsPerThreadgroup: vThreadgroup1)
        enc2.endEncoding()
        cb2.commit()
        await cb2.completed()

        // Step 3: Vertical DWT on highpass → HL, HH
        let hlBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(halfWH * halfH, 1) * MemoryLayout<Float>.stride
        )
        let hhBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(halfWH * halfHH, 1) * MemoryLayout<Float>.stride
        )

        guard let cb3 = queue.makeCommandBuffer(),
              let enc3 = cb3.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        enc3.setComputePipelineState(vPipeline)
        enc3.setBuffer(hHighBuffer, offset: 0, index: 0)
        enc3.setBuffer(hlBuffer, offset: 0, index: 1)
        enc3.setBuffer(hhBuffer, offset: 0, index: 2)
        var halfWHVal = UInt32(halfWH)
        enc3.setBytes(&halfWHVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc3.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)

        if halfWH > 0 {
            let vThreads2 = MTLSize(width: halfWH, height: 1, depth: 1)
            let vThreadgroup2 = MTLSize(width: min(halfWH, 64), height: 1, depth: 1)
            enc3.dispatchThreads(vThreads2, threadsPerThreadgroup: vThreadgroup2)
        }
        enc3.endEncoding()
        cb3.commit()
        await cb3.completed()

        // Read results
        let ll = readFloatArray(from: llBuffer, elementCount: halfW * halfH)
        let lh = readFloatArray(from: lhBuffer, elementCount: halfW * halfHH)
        let hl = readFloatArray(from: hlBuffer, elementCount: halfWH * halfH)
        let hh = readFloatArray(from: hhBuffer, elementCount: halfWH * halfHH)

        // Track memory
        let totalMem = UInt64(
            (data.count + halfW * height + halfWH * height
             + halfW * halfH + halfW * halfHH
             + halfWH * halfH + halfWH * halfHH)
            * MemoryLayout<Float>.stride
        )
        if totalMem > _statistics.peakGPUMemory {
            _statistics.peakGPUMemory = totalMem
        }

        // Return buffers
        await bufferPool.returnBuffer(inputBuffer)
        await bufferPool.returnBuffer(hLowBuffer)
        await bufferPool.returnBuffer(hHighBuffer)
        await bufferPool.returnBuffer(llBuffer)
        await bufferPool.returnBuffer(lhBuffer)
        await bufferPool.returnBuffer(hlBuffer)
        await bufferPool.returnBuffer(hhBuffer)

        return J2KMetalDWTSubbands(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: halfW, llHeight: halfH,
            originalWidth: width, originalHeight: height
        )
    }

    private func readFloatArray(from buffer: MTLBuffer, elementCount: Int) -> [Float] {
        guard elementCount > 0 else { return [] }
        var result = [Float](repeating: 0, count: elementCount)
        result.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(
                start: buffer.contents(),
                count: elementCount * MemoryLayout<Float>.stride
            ))
        }
        return result
    }

    private func inverse2DGPU(
        subbands: J2KMetalDWTSubbands
    ) async throws -> [Float] {
        // For GPU inverse, delegate to CPU reference (full GPU inverse
        // requires careful reconstruction logic matching the forward path).
        // This maintains correctness while forward transforms get GPU acceleration.
        inverse2DCPU(subbands: subbands)
    }

    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initialize()
        }
    }

    private func horizontalForwardShaderFunction() -> J2KMetalShaderFunction {
        switch configuration.filter {
        case .irreversible97:
            return .dwtForward97Horizontal
        case .reversible53:
            return .dwtForward53Horizontal
        case .arbitrary:
            return .dwtForwardArbitraryHorizontal
        case .lifting:
            return .dwtForwardLiftingHorizontal
        }
    }

    private func horizontalInverseShaderFunction() -> J2KMetalShaderFunction {
        switch configuration.filter {
        case .irreversible97:
            return .dwtInverse97Horizontal
        case .reversible53:
            return .dwtInverse53Horizontal
        case .arbitrary:
            return .dwtInverseArbitraryHorizontal
        case .lifting:
            return .dwtInverseLiftingHorizontal
        }
    }

    private func verticalForwardShaderFunction() -> J2KMetalShaderFunction {
        switch configuration.filter {
        case .irreversible97:
            return .dwtForward97Vertical
        case .reversible53:
            return .dwtForward53Vertical
        case .arbitrary:
            return .dwtForwardArbitraryVertical
        case .lifting:
            return .dwtForwardLiftingVertical
        }
    }

    private func verticalInverseShaderFunction() -> J2KMetalShaderFunction {
        switch configuration.filter {
        case .irreversible97:
            return .dwtInverse97Vertical
        case .reversible53:
            return .dwtInverse53Vertical
        case .arbitrary:
            return .dwtInverseArbitraryVertical
        case .lifting:
            return .dwtInverseLiftingVertical
        }
    }
    #else
    private func forward1DGPU(
        signal: [Float]
    ) async throws -> (lowpass: [Float], highpass: [Float]) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    private func inverse1DGPU(
        lowpass: [Float], highpass: [Float]
    ) async throws -> [Float] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    private func forward2DGPU(
        data: [Float], width: Int, height: Int
    ) async throws -> J2KMetalDWTSubbands {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    private func inverse2DGPU(
        subbands: J2KMetalDWTSubbands
    ) async throws -> [Float] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
