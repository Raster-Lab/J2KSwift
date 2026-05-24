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

    /// Whether to enable threadgroup memory optimisation.
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
    ///   - useThreadgroupMemory: Enable threadgroup optimisation. Defaults to `true`.
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

    /// Configuration optimised for large images with tile-based processing.
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

// MARK: - Int32 Decomposition Subbands (bit-exact reversible path)

/// Result of a 2D wavelet decomposition with `Int32` subbands.
///
/// Used by the bit-exact reversible 5/3 GPU path so that no Float
/// conversion happens at the dispatch boundary. The arithmetic in
/// the integer Metal kernels matches the JPEG 2000 spec exactly.
public struct J2KMetalDWTSubbandsInt32: Sendable {
    public let ll: [Int32]
    public let lh: [Int32]
    public let hl: [Int32]
    public let hh: [Int32]
    public let llWidth: Int
    public let llHeight: Int
    public let originalWidth: Int
    public let originalHeight: Int

    /// **v7.1.0 H2.2** — band canvas origin on x. When odd, the
    /// horizontal inverse 5/3 pass uses parity-aware lifting per
    /// ISO 15444-1 Annex F.4.1.1. Default 0 (single-tile, even-origin
    /// — the historical case). Multi-tile per-tile decode populates
    /// this from the tile-component origin at the active decomposition
    /// level.
    public let tileOriginX: Int
    /// Band canvas origin on y. Same semantics as `tileOriginX` for
    /// the vertical inverse 5/3 pass.
    public let tileOriginY: Int

    public init(
        ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32],
        llWidth: Int, llHeight: Int,
        originalWidth: Int, originalHeight: Int,
        tileOriginX: Int = 0,
        tileOriginY: Int = 0
    ) {
        self.ll = ll
        self.lh = lh
        self.hl = hl
        self.hh = hh
        self.llWidth = llWidth
        self.llHeight = llHeight
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.tileOriginX = tileOriginX
        self.tileOriginY = tileOriginY
    }
}

// MARK: - Int32 Decomposition Subbands (zero-copy view variant, v7.2.0 Phase A)

#if canImport(Metal)
/// View-backed result of a 2D wavelet decomposition with `Int32`
/// subbands. Identical semantics to `J2KMetalDWTSubbandsInt32` but
/// the four band stores are `J2KMetalSharedBufferView<Int32>` —
/// each view exposes the GPU output buffer's CPU-visible memory
/// directly, eliminating the readback memcpy that the Array-valued
/// variant performs.
///
/// Used by the v7.2.0 encode-side UMA elimination on Apple Silicon.
/// On platforms without unified memory, fall back to the Array
/// variant.
public struct J2KMetalDWTSubbandsInt32View: @unchecked Sendable {
    public let ll: J2KMetalSharedBufferView<Int32>
    public let lh: J2KMetalSharedBufferView<Int32>
    public let hl: J2KMetalSharedBufferView<Int32>
    public let hh: J2KMetalSharedBufferView<Int32>
    public let llWidth: Int
    public let llHeight: Int
    public let originalWidth: Int
    public let originalHeight: Int
    /// Mirrors `J2KMetalDWTSubbandsInt32.tileOriginX`. Inert on the
    /// forward-DWT producer side; reserved for symmetry with the
    /// inverse path that consults parity for boundary lifting.
    public let tileOriginX: Int
    /// Mirrors `J2KMetalDWTSubbandsInt32.tileOriginY`.
    public let tileOriginY: Int

    public init(
        ll: J2KMetalSharedBufferView<Int32>,
        lh: J2KMetalSharedBufferView<Int32>,
        hl: J2KMetalSharedBufferView<Int32>,
        hh: J2KMetalSharedBufferView<Int32>,
        llWidth: Int, llHeight: Int,
        originalWidth: Int, originalHeight: Int,
        tileOriginX: Int = 0,
        tileOriginY: Int = 0
    ) {
        self.ll = ll
        self.lh = lh
        self.hl = hl
        self.hh = hh
        self.llWidth = llWidth
        self.llHeight = llHeight
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.tileOriginX = tileOriginX
        self.tileOriginY = tileOriginY
    }
}
#endif

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
/// monitoring and optimisation purposes.
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

/// Canvas-anchored 5/3 subband geometry for one decomposition level —
/// the single source of truth for splitting a `width × height` band
/// into LL/LH/HL/HH sub-band dimensions.
///
/// Per ISO/IEC 15444-1 F.4.4 the split depends on the tile-component
/// **canvas origin parity**: the low-pass count is `ceil(N/2)` at an
/// even origin and `floor(N/2)` at an odd origin; the high-pass band
/// is always `N − low`. `N/2` alone is correct ONLY at an even origin
/// — hand-writing `halfHH = height / 2` is exactly the mistake that
/// shipped a latent multi-tile IDWT decode bug across v10.3.0–v10.9.0
/// (the v8.3 fix corrected some call sites and missed others). Routing
/// every band-dimension computation through this type makes a future
/// fix structurally unable to miss a call site.
private struct BandGeometry {
    let llW: Int   // low-pass (LL/LH) band width
    let llH: Int   // low-pass (LL/HL) band height
    let halfWH: Int  // high-pass (HL/HH) band width  = width  − llW
    let halfHH: Int  // high-pass (LH/HH) band height = height − llH

    /// Derive the split from canvas dimensions + tile-component canvas
    /// origin (the forward transform, and any site computing band
    /// counts from geometry). Even origin → `ceil`; odd origin → `floor`.
    init(width: Int, height: Int, originX: Int, originY: Int) {
        llW = (originX & 1) == 0 ? (width  + 1) / 2 : width  / 2
        llH = (originY & 1) == 0 ? (height + 1) / 2 : height / 2
        halfWH = width  - llW
        halfHH = height - llH
    }

    /// Derive the high-pass bands from canvas dimensions + already-known
    /// low-pass dimensions (the inverse transform, where `llW`/`llH`
    /// come from the decoded `J2KMetalDWTSubbandsInt32` structure).
    init(width: Int, height: Int, llW: Int, llH: Int) {
        self.llW = llW
        self.llH = llH
        halfWH = width  - llW
        halfHH = height - llH
    }
}

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

    /// Whether the Metal backend has been initialised.
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

    /// Bit-exact reversible 5/3 single-level inverse 2D DWT on `Int32` subbands.
    ///
    /// Routes through dedicated integer Metal kernels (or the integer CPU
    /// reference when Metal is unavailable / `backend == .cpu`). Output
    /// equals the canonical `J2KDWT1D.inverseTransform53` result for every
    /// row/column, so the encoder→decoder byte-equality check holds for
    /// lossless transfer syntaxes regardless of which backend ran.
    /// v5.7.0: multi-level fused inverse 5/3 inverse 2D. Chains all
    /// decomposition levels into a single command buffer with the
    /// output buffer of level N reused as the LL input of level N-1
    /// — no readback between levels. Single commit + await + final
    /// readback at the outermost level.
    ///
    /// - Parameter subbandsPerLevel: array of subband data, indexed
    ///   from innermost (index 0) to outermost (index N-1). The LL
    ///   on `subbandsPerLevel[0]` is the only LL uploaded from CPU;
    ///   every subsequent level's LL is the previous level's
    ///   inverse-2D output, GPU-resident.
    /// - Returns: the final outermost-level Int32 output, read back
    ///   to host once at the end.
    /// - Throws: ``J2KError`` on Metal failures or dimension
    ///   mismatch (each level's parent dimensions must match the
    ///   previous level's `originalWidth × originalHeight`).
    /// Bit-exact reversible 5/3 multi-level forward 2D DWT on Int32,
    /// chained into a **single Metal command buffer**.
    ///
    /// **Lossless-only pivot — Phase 1.** Symmetric counterpart of
    /// `inverse2DInt32MultiLevelFused`. The first level uploads the
    /// image data once; intermediate LL bands stay GPU-resident
    /// across levels so only the per-level detail bands (LH / HL /
    /// HH) and the final coarsest LL are read back to host. This
    /// amortises the per-call command-buffer commit / wait latency
    /// (~1 ms on Apple M2) across all N decomposition levels — the
    /// step-11 diagnosis showed that single-tile GPU-forward needs
    /// fusion to beat per-tile CPU DWT.
    ///
    /// Returns the levels deepest-last (finest at `[0]`, coarsest at
    /// `[N-1]`), matching the order the decode side already uses.
    /// Each returned `J2KMetalDWTSubbandsInt32`'s `ll` field contains
    /// that level's LL — the next-coarser level's input. The final
    /// element's LL is the coarsest approximation (also accessible
    /// via the helper extension this same phase ships).
    ///
    /// - Parameters:
    ///   - image: Row-major Int32 image of length `width × height`.
    ///   - width: Image width in samples (≥ 2).
    ///   - height: Image height in samples (≥ 2).
    ///   - levels: Decomposition depth (≥ 1). Clamped to the maximum
    ///     possible for the dimensions.
    /// - Returns: `[J2KMetalDWTSubbandsInt32]` with one entry per
    ///   decomposed level, finest first.
    /// - Throws: `J2KError.invalidParameter` on dimension issues,
    ///   `J2KError.internalError` on Metal failures.
    #if canImport(Metal)
    public func forward2DInt32MultiLevelFused(
        image: [Int32],
        width: Int,
        height: Int,
        levels: Int
    ) async throws -> [J2KMetalDWTSubbandsInt32] {
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Image dimensions must be at least 2×2, got \(width)×\(height)")
        }
        guard image.count == width * height else {
            throw J2KError.invalidParameter(
                "Image size \(image.count) doesn't match dimensions \(width)×\(height)")
        }
        let maxLevels = maxDecompositionLevels(width: width, height: height)
        let effectiveLevels = max(1, min(levels, maxLevels))

        try await ensureInitialized()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let stride32 = MemoryLayout<Int32>.stride

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create multi-level forward cb")
        }

        // Buffers in flight — each must outlive cb.completed().
        var inFlight: [any MTLBuffer] = []

        // Track per-level output buffers so we can read back after commit.
        struct LevelDispatch {
            let llBuf: any MTLBuffer
            let lhBuf: any MTLBuffer
            let hlBuf: any MTLBuffer
            let hhBuf: any MTLBuffer
            let llWidth: Int
            let llHeight: Int
            let halfWH: Int
            let halfHH: Int
            let originalWidth: Int
            let originalHeight: Int
        }
        var dispatched: [LevelDispatch] = []

        // First level reads from a CPU upload; subsequent levels
        // read from the previous level's LL output buffer
        // (GPU-resident, no readback in between).
        var currentInput: any MTLBuffer = try await {
            let buf = try await bufferPool.acquireBuffer(
                device: device, size: image.count * stride32)
            image.withUnsafeBytes { src in
                buf.contents().copyMemory(
                    from: src.baseAddress!, byteCount: src.count)
            }
            return buf
        }()
        inFlight.append(currentInput)
        var curW = width
        var curH = height

        let vPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53VerticalInt)
        let hPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53HorizontalInt)

        for _ in 0..<effectiveLevels {
            guard curW >= 2, curH >= 2 else { break }
            let bands = BandGeometry(width: curW, height: curH, originX: 0, originY: 0)
            let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH

            let vLowBuf  = try await bufferPool.acquireBuffer(
                device: device, size: curW * llH * stride32)
            inFlight.append(vLowBuf)
            let vHighBuf = try await bufferPool.acquireBuffer(
                device: device, size: max(curW * halfHH, 1) * stride32)
            inFlight.append(vHighBuf)
            let llBuf  = try await bufferPool.acquireBuffer(
                device: device, size: llW * llH * stride32)
            inFlight.append(llBuf)
            let hlBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(halfWH * llH, 1) * stride32)
            inFlight.append(hlBuf)
            let lhBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(llW * halfHH, 1) * stride32)
            inFlight.append(lhBuf)
            let hhBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(halfWH * halfHH, 1) * stride32)
            inFlight.append(hhBuf)

            // Pass 1: vertical forward — currentInput → vLow + vHigh.
            guard let enc1 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError(
                    "Failed to create vertical forward encoder")
            }
            enc1.setComputePipelineState(vPipeline)
            enc1.setBuffer(currentInput, offset: 0, index: 0)
            enc1.setBuffer(vLowBuf,      offset: 0, index: 1)
            enc1.setBuffer(vHighBuf,     offset: 0, index: 2)
            var widthVal  = UInt32(curW)
            var heightVal = UInt32(curH)
            enc1.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
            enc1.setBytes(&heightVal, length: MemoryLayout<UInt32>.stride, index: 4)
            enc1.dispatchThreads(
                MTLSize(width: curW, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: min(curW, 64), height: 1, depth: 1))
            enc1.endEncoding()

            // Pass 2: horizontal forward — two dispatches into one
            // encoder. New encoder ⇒ implicit memory barrier from
            // pass 1.
            guard let enc2 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError(
                    "Failed to create horizontal forward encoder")
            }
            enc2.setComputePipelineState(hPipeline)
            // 2a: vLow rows → LL + HL.
            enc2.setBuffer(vLowBuf, offset: 0, index: 0)
            enc2.setBuffer(llBuf,   offset: 0, index: 1)
            enc2.setBuffer(hlBuf,   offset: 0, index: 2)
            var llHVal = UInt32(llH)
            enc2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc2.setBytes(&llHVal,   length: MemoryLayout<UInt32>.stride, index: 4)
            enc2.dispatchThreads(
                MTLSize(width: 1, height: llH, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: 1, height: min(llH, 64), depth: 1))
            // 2b: vHigh rows → LH + HH.
            if halfHH > 0 {
                enc2.setBuffer(vHighBuf, offset: 0, index: 0)
                enc2.setBuffer(lhBuf,    offset: 0, index: 1)
                enc2.setBuffer(hhBuf,    offset: 0, index: 2)
                var halfHHVal = UInt32(halfHH)
                enc2.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
                enc2.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 4)
                enc2.dispatchThreads(
                    MTLSize(width: 1, height: halfHH, depth: 1),
                    threadsPerThreadgroup: MTLSize(
                        width: 1, height: min(halfHH, 64), depth: 1))
            }
            enc2.endEncoding()

            dispatched.append(LevelDispatch(
                llBuf: llBuf, lhBuf: lhBuf, hlBuf: hlBuf, hhBuf: hhBuf,
                llWidth: llW, llHeight: llH,
                halfWH: halfWH, halfHH: halfHH,
                originalWidth: curW, originalHeight: curH))

            // Next level's input is this level's LL, GPU-resident.
            currentInput = llBuf
            curW = llW
            curH = llH
        }

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Multi-level fused forward 5/3 GPU dispatch failed: " +
                "\(cb.error?.localizedDescription ?? "(no description)")")
        }

        // Read back per-level outputs. Each returned subbands struct
        // carries the LL of that level too — the same convention as
        // the existing forwardMultiLevel (Float) result.
        var out: [J2KMetalDWTSubbandsInt32] = []
        out.reserveCapacity(dispatched.count)
        for d in dispatched {
            let ll = readInt32Array(from: d.llBuf, elementCount: d.llWidth * d.llHeight)
            let lh = readInt32Array(from: d.lhBuf, elementCount: d.llWidth * d.halfHH)
            let hl = readInt32Array(from: d.hlBuf, elementCount: d.halfWH * d.llHeight)
            let hh = readInt32Array(from: d.hhBuf, elementCount: d.halfWH * d.halfHH)
            out.append(J2KMetalDWTSubbandsInt32(
                ll: ll, lh: lh, hl: hl, hh: hh,
                llWidth: d.llWidth, llHeight: d.llHeight,
                originalWidth: d.originalWidth, originalHeight: d.originalHeight))
        }

        // Return all in-flight buffers to the pool now that cb has completed.
        let pool = bufferPool
        let toReturn = inFlight
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        return out
    }

    /// Bit-exact reversible 5/3 multi-level forward 2D DWT on Int32
    /// with **tile-component image-coordinate origin awareness**,
    /// chained into a single Metal command buffer.
    ///
    /// **Lossless-only pivot — Phase 4 slice 2.** Builds on phase 1
    /// (multi-level fusion) and phase 4 slice 1 (single-level
    /// odd-origin kernels). Per ISO/IEC 15444-1 Eq. B-15, the LL
    /// band's canvas origin at level n+1 is `ceil(parent_origin / 2)`
    /// — for non-negative integers `(x + 1) >> 1`. The recursion
    /// tracks origin per axis per level and dispatches the right
    /// kernel (even or odd) per axis based on `origin & 1`.
    ///
    /// When both starting origins are zero, every level's origin
    /// stays at (0, 0), so this routes through the same kernels as
    /// the no-origin fused entry point — bit-identical output, no
    /// regression.
    ///
    /// - Parameters:
    ///   - image: Row-major Int32 image.
    ///   - width: ≥ 2.
    ///   - height: ≥ 2.
    ///   - levels: Decomposition depth, clamped to maximum.
    ///   - tileOriginX: Image-coord origin in the X axis.
    ///   - tileOriginY: Image-coord origin in the Y axis.
    /// - Returns: `[J2KMetalDWTSubbandsInt32]` finest-first, each
    ///   with parity-aware band sizes.
    public func forward2DInt32MultiLevelFused(
        image: [Int32],
        width: Int,
        height: Int,
        levels: Int,
        tileOriginX: Int,
        tileOriginY: Int
    ) async throws -> [J2KMetalDWTSubbandsInt32] {
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Image dimensions must be at least 2×2, got \(width)×\(height)")
        }
        guard image.count == width * height else {
            throw J2KError.invalidParameter(
                "Image size \(image.count) doesn't match dimensions \(width)×\(height)")
        }
        let maxLevels = maxDecompositionLevels(width: width, height: height)
        let effectiveLevels = max(1, min(levels, maxLevels))

        try await ensureInitialized()
        // v6-alpha5 phase 6 — fresh per-call command queue so
        // concurrent multi-tile dispatches don't serialise on a
        // shared MTLCommandQueue. Phase 5 measured 33–43 %
        // multi-tile regression rooted in the shared-queue serial
        // execution; allocating a per-tile queue lets the GPU
        // scheduler interleave CB execution across tile tasks.
        let queue = try await metalDevice.makeFreshCommandQueue()
        let device = queue.device
        let stride32 = MemoryLayout<Int32>.stride

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create multi-level forward cb")
        }

        var inFlight: [any MTLBuffer] = []
        struct LevelDispatch {
            let llBuf: any MTLBuffer
            let lhBuf: any MTLBuffer
            let hlBuf: any MTLBuffer
            let hhBuf: any MTLBuffer
            let llWidth: Int
            let llHeight: Int
            let halfWH: Int
            let halfHH: Int
            let originalWidth: Int
            let originalHeight: Int
        }
        var dispatched: [LevelDispatch] = []

        var currentInput: any MTLBuffer = try await {
            let buf = try await bufferPool.acquireBuffer(
                device: device, size: image.count * stride32)
            image.withUnsafeBytes { src in
                buf.contents().copyMemory(
                    from: src.baseAddress!, byteCount: src.count)
            }
            return buf
        }()
        inFlight.append(currentInput)
        var curW = width
        var curH = height
        var curOX = tileOriginX
        var curOY = tileOriginY

        // Pre-fetch all four kernel pipelines so per-level kernel
        // selection is a no-op cache hit.
        let vEvenPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53VerticalInt)
        let vOddPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53VerticalIntOdd)
        let hEvenPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53HorizontalInt)
        let hOddPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53HorizontalIntOdd)

        for _ in 0..<effectiveLevels {
            guard curW >= 2, curH >= 2 else { break }

            // Parity-aware band counts per F.4.4: low-pass count is
            // ceil for even origin, floor for odd; high = total - low.
            let bands = BandGeometry(width: curW, height: curH, originX: curOX, originY: curOY)
            let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH

            let vLowBuf  = try await bufferPool.acquireBuffer(
                device: device, size: curW * llH * stride32)
            inFlight.append(vLowBuf)
            let vHighBuf = try await bufferPool.acquireBuffer(
                device: device, size: max(curW * halfHH, 1) * stride32)
            inFlight.append(vHighBuf)
            let llBuf  = try await bufferPool.acquireBuffer(
                device: device, size: llW * llH * stride32)
            inFlight.append(llBuf)
            let hlBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(halfWH * llH, 1) * stride32)
            inFlight.append(hlBuf)
            let lhBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(llW * halfHH, 1) * stride32)
            inFlight.append(lhBuf)
            let hhBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(halfWH * halfHH, 1) * stride32)
            inFlight.append(hhBuf)

            let vPipeline = ((curOY & 1) == 0) ? vEvenPipeline : vOddPipeline
            let hPipeline = ((curOX & 1) == 0) ? hEvenPipeline : hOddPipeline

            // Pass 1: vertical forward — currentInput → vLow + vHigh.
            guard let enc1 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError(
                    "Failed to create vertical forward encoder")
            }
            enc1.setComputePipelineState(vPipeline)
            enc1.setBuffer(currentInput, offset: 0, index: 0)
            enc1.setBuffer(vLowBuf,      offset: 0, index: 1)
            enc1.setBuffer(vHighBuf,     offset: 0, index: 2)
            var widthVal  = UInt32(curW)
            var heightVal = UInt32(curH)
            enc1.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
            enc1.setBytes(&heightVal, length: MemoryLayout<UInt32>.stride, index: 4)
            enc1.dispatchThreads(
                MTLSize(width: curW, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: min(curW, 64), height: 1, depth: 1))
            enc1.endEncoding()

            // Pass 2: horizontal forward — vLow → LL+HL, vHigh → LH+HH.
            guard let enc2 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError(
                    "Failed to create horizontal forward encoder")
            }
            enc2.setComputePipelineState(hPipeline)
            enc2.setBuffer(vLowBuf, offset: 0, index: 0)
            enc2.setBuffer(llBuf,   offset: 0, index: 1)
            enc2.setBuffer(hlBuf,   offset: 0, index: 2)
            var llHVal = UInt32(llH)
            enc2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc2.setBytes(&llHVal,   length: MemoryLayout<UInt32>.stride, index: 4)
            enc2.dispatchThreads(
                MTLSize(width: 1, height: llH, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: 1, height: min(llH, 64), depth: 1))
            if halfHH > 0 {
                enc2.setBuffer(vHighBuf, offset: 0, index: 0)
                enc2.setBuffer(lhBuf,    offset: 0, index: 1)
                enc2.setBuffer(hhBuf,    offset: 0, index: 2)
                var halfHHVal = UInt32(halfHH)
                enc2.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
                enc2.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 4)
                enc2.dispatchThreads(
                    MTLSize(width: 1, height: halfHH, depth: 1),
                    threadsPerThreadgroup: MTLSize(
                        width: 1, height: min(halfHH, 64), depth: 1))
            }
            enc2.endEncoding()

            dispatched.append(LevelDispatch(
                llBuf: llBuf, lhBuf: lhBuf, hlBuf: hlBuf, hhBuf: hhBuf,
                llWidth: llW, llHeight: llH,
                halfWH: halfWH, halfHH: halfHH,
                originalWidth: curW, originalHeight: curH))

            // Next-level input = this level's LL, GPU-resident.
            currentInput = llBuf
            curW = llW
            curH = llH
            // Eq. B-15 origin trajectory: ceil-halving, never floor.
            curOX = (curOX + 1) >> 1
            curOY = (curOY + 1) >> 1
        }

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Multi-level fused parity-aware forward 5/3 GPU dispatch failed: " +
                "\(cb.error?.localizedDescription ?? "(no description)")")
        }

        var out: [J2KMetalDWTSubbandsInt32] = []
        out.reserveCapacity(dispatched.count)
        for d in dispatched {
            let ll = readInt32Array(from: d.llBuf, elementCount: d.llWidth * d.llHeight)
            let lh = readInt32Array(from: d.lhBuf, elementCount: d.llWidth * d.halfHH)
            let hl = readInt32Array(from: d.hlBuf, elementCount: d.halfWH * d.llHeight)
            let hh = readInt32Array(from: d.hhBuf, elementCount: d.halfWH * d.halfHH)
            out.append(J2KMetalDWTSubbandsInt32(
                ll: ll, lh: lh, hl: hl, hh: hh,
                llWidth: d.llWidth, llHeight: d.llHeight,
                originalWidth: d.originalWidth, originalHeight: d.originalHeight))
        }

        let pool = bufferPool
        let toReturn = inFlight
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        return out
    }

    /// **v7.2.0 Phase A — UMA encode-side boundary elimination.**
    ///
    /// Same GPU dispatch as `forward2DInt32MultiLevelFused(image:width:
    /// height:levels:tileOriginX:tileOriginY:)` but returns
    /// `[J2KMetalDWTSubbandsInt32View]` instead of
    /// `[J2KMetalDWTSubbandsInt32]`. Each band's `J2KMetalSharedBufferView<Int32>`
    /// exposes the GPU output buffer's CPU-visible memory directly,
    /// avoiding the readback memcpy that the Array variant performs
    /// 4× per level × `levels` levels (= 20 boundaries on a typical
    /// 5-level lossless encode of DX 6.41 MP, ~25 MB total memcpy
    /// per encode).
    ///
    /// Lifetime: each band view holds a strong reference to its
    /// underlying `MTLBuffer`. Scratch buffers (image-copy input,
    /// vLow / vHigh per level) are returned to the pool immediately
    /// after the CB completes; band buffers are returned via the
    /// view's `release()` / `deinit` — caller controls when the
    /// pool gets the buffers back.
    ///
    /// Bytes byte-identical to the Array variant. Used by the
    /// encoder pipeline when `_gpuForward53Enabled && Metal &&
    /// pixels >= threshold`. CPU fallback path (when the GPU
    /// gates fail) continues to use `AcceleratedDWT2D.forwardDecomposition53`
    /// and constructs SubbandInfo with `coefficients: [Int32]`.
    public func forward2DInt32MultiLevelFusedView(
        image: [Int32],
        width: Int,
        height: Int,
        levels: Int,
        tileOriginX: Int,
        tileOriginY: Int
    ) async throws -> [J2KMetalDWTSubbandsInt32View] {
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Image dimensions must be at least 2×2, got \(width)×\(height)")
        }
        guard image.count == width * height else {
            throw J2KError.invalidParameter(
                "Image size \(image.count) doesn't match dimensions \(width)×\(height)")
        }
        let maxLevels = maxDecompositionLevels(width: width, height: height)
        let effectiveLevels = max(1, min(levels, maxLevels))

        try await ensureInitialized()
        let queue = try await metalDevice.makeFreshCommandQueue()
        let device = queue.device
        let stride32 = MemoryLayout<Int32>.stride

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create multi-level forward cb (view variant)")
        }

        // Scratch buffers — returned to pool immediately after CB
        // completes. Band buffers (per-level llBuf/lhBuf/hlBuf/hhBuf)
        // are NOT in this list; they ride along with the views.
        var scratch: [any MTLBuffer] = []
        struct LevelDispatch {
            let llBuf: any MTLBuffer
            let lhBuf: any MTLBuffer
            let hlBuf: any MTLBuffer
            let hhBuf: any MTLBuffer
            let llWidth: Int
            let llHeight: Int
            let halfWH: Int
            let halfHH: Int
            let originalWidth: Int
            let originalHeight: Int
        }
        var dispatched: [LevelDispatch] = []

        var currentInput: any MTLBuffer = try await {
            let buf = try await bufferPool.acquireBuffer(
                device: device, size: image.count * stride32)
            image.withUnsafeBytes { src in
                buf.contents().copyMemory(
                    from: src.baseAddress!, byteCount: src.count)
            }
            return buf
        }()
        // The initial image-copy buffer is scratch — its only
        // consumer is the first level's vertical pass, which reads
        // it once. After that level dispatches it can return to
        // the pool. We can't return it before CB.completed() fires
        // though; defer to the CB-completion epilogue below.
        scratch.append(currentInput)
        var curW = width
        var curH = height
        var curOX = tileOriginX
        var curOY = tileOriginY

        let vEvenPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53VerticalInt)
        let vOddPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53VerticalIntOdd)
        let hEvenPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53HorizontalInt)
        let hOddPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53HorizontalIntOdd)

        for _ in 0..<effectiveLevels {
            guard curW >= 2, curH >= 2 else { break }

            let bands = BandGeometry(width: curW, height: curH, originX: curOX, originY: curOY)
            let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH

            let vLowBuf  = try await bufferPool.acquireBuffer(
                device: device, size: curW * llH * stride32)
            scratch.append(vLowBuf)
            let vHighBuf = try await bufferPool.acquireBuffer(
                device: device, size: max(curW * halfHH, 1) * stride32)
            scratch.append(vHighBuf)
            // Band buffers — these survive to the views.
            let llBuf  = try await bufferPool.acquireBuffer(
                device: device, size: llW * llH * stride32)
            let hlBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(halfWH * llH, 1) * stride32)
            let lhBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(llW * halfHH, 1) * stride32)
            let hhBuf  = try await bufferPool.acquireBuffer(
                device: device, size: max(halfWH * halfHH, 1) * stride32)

            let vPipeline = ((curOY & 1) == 0) ? vEvenPipeline : vOddPipeline
            let hPipeline = ((curOX & 1) == 0) ? hEvenPipeline : hOddPipeline

            guard let enc1 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError(
                    "Failed to create vertical forward encoder (view variant)")
            }
            enc1.setComputePipelineState(vPipeline)
            enc1.setBuffer(currentInput, offset: 0, index: 0)
            enc1.setBuffer(vLowBuf,      offset: 0, index: 1)
            enc1.setBuffer(vHighBuf,     offset: 0, index: 2)
            var widthVal  = UInt32(curW)
            var heightVal = UInt32(curH)
            enc1.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
            enc1.setBytes(&heightVal, length: MemoryLayout<UInt32>.stride, index: 4)
            enc1.dispatchThreads(
                MTLSize(width: curW, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: min(curW, 64), height: 1, depth: 1))
            enc1.endEncoding()

            guard let enc2 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError(
                    "Failed to create horizontal forward encoder (view variant)")
            }
            enc2.setComputePipelineState(hPipeline)
            enc2.setBuffer(vLowBuf, offset: 0, index: 0)
            enc2.setBuffer(llBuf,   offset: 0, index: 1)
            enc2.setBuffer(hlBuf,   offset: 0, index: 2)
            var llHVal = UInt32(llH)
            enc2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc2.setBytes(&llHVal,   length: MemoryLayout<UInt32>.stride, index: 4)
            enc2.dispatchThreads(
                MTLSize(width: 1, height: llH, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: 1, height: min(llH, 64), depth: 1))
            if halfHH > 0 {
                enc2.setBuffer(vHighBuf, offset: 0, index: 0)
                enc2.setBuffer(lhBuf,    offset: 0, index: 1)
                enc2.setBuffer(hhBuf,    offset: 0, index: 2)
                var halfHHVal = UInt32(halfHH)
                enc2.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
                enc2.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 4)
                enc2.dispatchThreads(
                    MTLSize(width: 1, height: halfHH, depth: 1),
                    threadsPerThreadgroup: MTLSize(
                        width: 1, height: min(halfHH, 64), depth: 1))
            }
            enc2.endEncoding()

            dispatched.append(LevelDispatch(
                llBuf: llBuf, lhBuf: lhBuf, hlBuf: hlBuf, hhBuf: hhBuf,
                llWidth: llW, llHeight: llH,
                halfWH: halfWH, halfHH: halfHH,
                originalWidth: curW, originalHeight: curH))

            // The current level's LL is the next level's input. ARC
            // keeps llBuf alive via `dispatched` so it won't be
            // freed even though we drop currentInput's reference.
            currentInput = llBuf
            curW = llW
            curH = llH
            curOX = (curOX + 1) >> 1
            curOY = (curOY + 1) >> 1
        }

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Multi-level fused parity-aware forward 5/3 GPU dispatch failed (view variant): " +
                "\(cb.error?.localizedDescription ?? "(no description)")")
        }

        // Hand scratch buffers back to the pool. Band buffers stay
        // alive via the views below.
        let pool = bufferPool
        let toReturn = scratch
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        // Wrap each band buffer in a view. The view's deinit (or
        // explicit release()) returns the buffer to the pool — so
        // when the encoder pipeline finishes consuming the views
        // (after entropy + rate-control + codestream emit), the
        // buffers come back automatically.
        var out: [J2KMetalDWTSubbandsInt32View] = []
        out.reserveCapacity(dispatched.count)
        for d in dispatched {
            let llCount = d.llWidth * d.llHeight
            let lhCount = d.llWidth * d.halfHH
            let hlCount = d.halfWH * d.llHeight
            let hhCount = d.halfWH * d.halfHH
            let llView = J2KMetalSharedBufferView<Int32>(
                buffer: d.llBuf, count: llCount, pool: pool)
            let lhView = J2KMetalSharedBufferView<Int32>(
                buffer: d.lhBuf, count: lhCount, pool: pool)
            let hlView = J2KMetalSharedBufferView<Int32>(
                buffer: d.hlBuf, count: hlCount, pool: pool)
            let hhView = J2KMetalSharedBufferView<Int32>(
                buffer: d.hhBuf, count: hhCount, pool: pool)
            out.append(J2KMetalDWTSubbandsInt32View(
                ll: llView, lh: lhView, hl: hlView, hh: hhView,
                llWidth: d.llWidth, llHeight: d.llHeight,
                originalWidth: d.originalWidth, originalHeight: d.originalHeight))
        }

        return out
    }

    public func inverse2DInt32MultiLevelFused(
        subbandsPerLevel: [J2KMetalDWTSubbandsInt32]
    ) async throws -> [Int32] {
        guard !subbandsPerLevel.isEmpty else {
            throw J2KError.invalidParameter("subbandsPerLevel must be non-empty")
        }
        // Validate level chain: each subsequent level's LL must
        // match the previous level's output dimensions.
        for i in 1..<subbandsPerLevel.count {
            let prev = subbandsPerLevel[i - 1]
            let cur = subbandsPerLevel[i]
            guard cur.llWidth == prev.originalWidth,
                  cur.llHeight == prev.originalHeight else {
                throw J2KError.invalidParameter(
                    "subband chain mismatch at level \(i): " +
                    "expected LL=\(prev.originalWidth)×\(prev.originalHeight), " +
                    "got \(cur.llWidth)×\(cur.llHeight)")
            }
        }

        try await ensureInitialized()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let stride32 = MemoryLayout<Int32>.stride

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create multi-level cb")
        }

        // Track all buffers in flight so we can return them to the
        // pool only after the cb completes (every buffer bound to
        // an encoder must outlive cb.completed()). Inline acquire
        // to keep Swift 6 strict-concurrency happy with the
        // captured mutable state.
        var inFlight: [any MTLBuffer] = []

        var currentLLBuffer: (any MTLBuffer)? = nil
        var finalOutputBuffer: (any MTLBuffer)? = nil
        var finalWidth = 0
        var finalHeight = 0

        for subbands in subbandsPerLevel {
            let width = subbands.originalWidth
            let height = subbands.originalHeight
            let llH = subbands.llHeight
            // **v8.3 fix**: LH/HH row count is `H − llH`, not
            // `H / 2`. For canvas-anchored partitioning at an ODD
            // V origin, LL = floor(H/2) and LH/HH = ceil(H/2);
            // `H / 2` under-counts by 1 for odd-H, ODD-V-origin
            // tiles, leaving the last LH/HH row uninitialised in
            // the colHigh buffer and corrupting the V IDWT output.
            let halfHH = height - llH

            // LL: first level uploads from CPU; subsequent levels
            // reuse the previous level's output buffer GPU-resident.
            let llBuffer: any MTLBuffer
            if let prev = currentLLBuffer {
                llBuffer = prev
            } else {
                let buf = try await bufferPool.acquireBuffer(
                    device: device, size: max(subbands.ll.count * stride32, 1))
                inFlight.append(buf)
                subbands.ll.withUnsafeBytes { src in
                    buf.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
                llBuffer = buf
            }

            let lhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(subbands.lh.count, 1) * stride32)
            inFlight.append(lhBuffer)
            let hlBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(subbands.hl.count, 1) * stride32)
            inFlight.append(hlBuffer)
            let hhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(subbands.hh.count, 1) * stride32)
            inFlight.append(hhBuffer)
            if !subbands.lh.isEmpty {
                subbands.lh.withUnsafeBytes { src in
                    lhBuffer.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
            }
            if !subbands.hl.isEmpty {
                subbands.hl.withUnsafeBytes { src in
                    hlBuffer.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
            }
            if !subbands.hh.isEmpty {
                subbands.hh.withUnsafeBytes { src in
                    hhBuffer.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
            }

            let colLowBuffer = try await bufferPool.acquireBuffer(
                device: device, size: width * llH * stride32)
            inFlight.append(colLowBuffer)
            let colHighBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(width * halfHH, 1) * stride32)
            inFlight.append(colHighBuffer)
            let outputBuffer = try await bufferPool.acquireBuffer(
                device: device, size: width * height * stride32)
            inFlight.append(outputBuffer)

            try await encodeInverse2DInt32(
                into: cb,
                ll: llBuffer, lh: lhBuffer, hl: hlBuffer, hh: hhBuffer,
                colLow: colLowBuffer, colHigh: colHighBuffer,
                output: outputBuffer,
                originalWidth: width, originalHeight: height,
                llHeight: llH,
                tileOriginX: subbands.tileOriginX,
                tileOriginY: subbands.tileOriginY)

            currentLLBuffer = outputBuffer
            finalOutputBuffer = outputBuffer
            finalWidth = width
            finalHeight = height
        }

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Multi-level fused inverse 5/3 GPU dispatch failed: " +
                "\(cb.error?.localizedDescription ?? "(no description)")")
        }

        let result = readInt32Array(
            from: finalOutputBuffer!, elementCount: finalWidth * finalHeight)

        // All buffers can now go back to the pool — cb has
        // completed, GPU done with them.
        let pool = bufferPool
        let toReturn = inFlight
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        return result
    }
    #else
    public func forward2DInt32MultiLevelFused(
        image: [Int32], width: Int, height: Int, levels: Int
    ) async throws -> [J2KMetalDWTSubbandsInt32] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    public func forward2DInt32MultiLevelFused(
        image: [Int32], width: Int, height: Int, levels: Int,
        tileOriginX: Int, tileOriginY: Int
    ) async throws -> [J2KMetalDWTSubbandsInt32] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    public func inverse2DInt32MultiLevelFused(
        subbandsPerLevel: [J2KMetalDWTSubbandsInt32]
    ) async throws -> [Int32] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    /// v5.24.0 multi-level fused inverse 9/7 lossy IDWT on `Float`
    /// subbands. Mirrors `inverse2DInt32MultiLevelFused` for the
    /// irreversible97 path: chains all decomposition levels into a
    /// single command buffer with the output buffer of level N
    /// reused as the LL input of level N-1 — no readback between
    /// levels. Single commit + await + final readback.
    ///
    /// On 9/7 lossy this closes the per-level upload/readback
    /// boundary that the per-level `inverse2D` path pays. CPU still
    /// uploads LH/HL/HH per level (the GPU-resident scatter path
    /// remains 5/3-only); LL is uploaded once at the innermost level
    /// and rides the GPU output buffer chain after that.
    ///
    /// - Parameter subbandsPerLevel: array of subband data, indexed
    ///   from innermost (index 0) to outermost (index N-1). Same
    ///   shape contract as the Int32 variant.
    /// - Returns: outermost-level Float output, read back to host
    ///   once at the end.
    /// - Throws: ``J2KError`` on Metal failures or dimension
    ///   mismatch.
    #if canImport(Metal)
    public func inverse2DMultiLevelFused(
        subbandsPerLevel: [J2KMetalDWTSubbands]
    ) async throws -> [Float] {
        guard !subbandsPerLevel.isEmpty else {
            throw J2KError.invalidParameter("subbandsPerLevel must be non-empty")
        }
        for i in 1..<subbandsPerLevel.count {
            let prev = subbandsPerLevel[i - 1]
            let cur = subbandsPerLevel[i]
            guard cur.llWidth == prev.originalWidth,
                  cur.llHeight == prev.originalHeight else {
                throw J2KError.invalidParameter(
                    "subband chain mismatch at level \(i): " +
                    "expected LL=\(prev.originalWidth)×\(prev.originalHeight), " +
                    "got \(cur.llWidth)×\(cur.llHeight)")
            }
        }

        try await ensureInitialized()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let strideF = MemoryLayout<Float>.stride

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create multi-level fused float cb")
        }

        var inFlight: [any MTLBuffer] = []
        var currentLLBuffer: (any MTLBuffer)? = nil
        var finalOutputBuffer: (any MTLBuffer)? = nil
        var finalWidth = 0
        var finalHeight = 0

        for subbands in subbandsPerLevel {
            let width = subbands.originalWidth
            let height = subbands.originalHeight
            let halfW = subbands.llWidth
            let halfWH = width / 2

            let llBuffer: any MTLBuffer
            if let prev = currentLLBuffer {
                llBuffer = prev
            } else {
                let buf = try await bufferPool.acquireBuffer(
                    device: device, size: max(subbands.ll.count * strideF, 1))
                inFlight.append(buf)
                subbands.ll.withUnsafeBytes { src in
                    buf.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
                llBuffer = buf
            }

            let lhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(subbands.lh.count, 1) * strideF)
            inFlight.append(lhBuffer)
            let hlBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(subbands.hl.count, 1) * strideF)
            inFlight.append(hlBuffer)
            let hhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(subbands.hh.count, 1) * strideF)
            inFlight.append(hhBuffer)
            if !subbands.lh.isEmpty {
                subbands.lh.withUnsafeBytes { src in
                    lhBuffer.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
            }
            if !subbands.hl.isEmpty {
                subbands.hl.withUnsafeBytes { src in
                    hlBuffer.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
            }
            if !subbands.hh.isEmpty {
                subbands.hh.withUnsafeBytes { src in
                    hhBuffer.contents().copyMemory(
                        from: src.baseAddress!, byteCount: src.count)
                }
            }

            let hLowBuffer = try await bufferPool.acquireBuffer(
                device: device, size: halfW * height * strideF)
            inFlight.append(hLowBuffer)
            let hHighBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(halfWH * height, 1) * strideF)
            inFlight.append(hHighBuffer)
            let outputBuffer = try await bufferPool.acquireBuffer(
                device: device, size: width * height * strideF)
            inFlight.append(outputBuffer)

            try await encodeInverse2D(
                into: cb,
                ll: llBuffer, lh: lhBuffer, hl: hlBuffer, hh: hhBuffer,
                hLow: hLowBuffer, hHigh: hHighBuffer,
                output: outputBuffer,
                originalWidth: width, originalHeight: height,
                halfW: halfW)

            currentLLBuffer = outputBuffer
            finalOutputBuffer = outputBuffer
            finalWidth = width
            finalHeight = height
        }

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Multi-level fused inverse 9/7 GPU dispatch failed: " +
                "\(cb.error?.localizedDescription ?? "(no description)")")
        }

        let result = readFloatArray(
            from: finalOutputBuffer!, elementCount: finalWidth * finalHeight)

        let pool = bufferPool
        let toReturn = inFlight
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        return result
    }

    /// Chainable encode for single-level Float inverse 9/7 IDWT into
    /// an existing command buffer. Mirrors `encodeInverse2DInt32`'s
    /// shape but uses the existing Float vertical+horizontal kernels.
    /// Caller owns buffer lifetime and command buffer commit/await.
    public func encodeInverse2D(
        into cb: any MTLCommandBuffer,
        ll: any MTLBuffer,
        lh: any MTLBuffer,
        hl: any MTLBuffer,
        hh: any MTLBuffer,
        hLow: any MTLBuffer,
        hHigh: any MTLBuffer,
        output: any MTLBuffer,
        originalWidth: Int,
        originalHeight: Int,
        halfW: Int
    ) async throws {
        let halfWH = originalWidth / 2

        let vPipeline = try await shaderLibrary.computePipeline(
            for: verticalInverseShaderFunction())
        let hPipeline = try await shaderLibrary.computePipeline(
            for: horizontalInverseShaderFunction())

        // Pass 1: vertical inverse — LL+LH → hLow, HL+HH → hHigh.
        guard let enc1 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create vertical compute encoder")
        }
        enc1.setComputePipelineState(vPipeline)
        var hVal = UInt32(originalHeight)

        enc1.setBuffer(ll, offset: 0, index: 0)
        enc1.setBuffer(lh, offset: 0, index: 1)
        enc1.setBuffer(hLow, offset: 0, index: 2)
        var halfWVal = UInt32(halfW)
        enc1.setBytes(&halfWVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc1.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)
        enc1.dispatchThreads(
            MTLSize(width: halfW, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(halfW, 64), height: 1, depth: 1))

        if halfWH > 0 {
            enc1.setBuffer(hl, offset: 0, index: 0)
            enc1.setBuffer(hh, offset: 0, index: 1)
            enc1.setBuffer(hHigh, offset: 0, index: 2)
            var halfWHVal = UInt32(halfWH)
            enc1.setBytes(&halfWHVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc1.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)
            enc1.dispatchThreads(
                MTLSize(width: halfWH, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(halfWH, 64), height: 1, depth: 1))
        }
        enc1.endEncoding()

        // Pass 2: horizontal inverse — hLow+hHigh → output.
        guard let enc2 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create horizontal compute encoder")
        }
        enc2.setComputePipelineState(hPipeline)
        enc2.setBuffer(hLow, offset: 0, index: 0)
        enc2.setBuffer(hHigh, offset: 0, index: 1)
        enc2.setBuffer(output, offset: 0, index: 2)
        var wVal = UInt32(originalWidth)
        enc2.setBytes(&wVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc2.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)
        enc2.dispatchThreads(
            MTLSize(width: 1, height: originalHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: min(originalHeight, 64), depth: 1))
        enc2.endEncoding()
    }
    #else
    public func inverse2DMultiLevelFused(
        subbandsPerLevel: [J2KMetalDWTSubbands]
    ) async throws -> [Float] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    /// Per-level scatter + DWT plan for the v5.8 full-fused entry
    /// point. Carries the placement descriptors (codeblock → LH/HL/HH
    /// in subband 2D buffers) and the dimensions needed to allocate
    /// the level's working buffers.
    public struct LevelScatterPlan: Sendable {
        /// Scatter descriptors for this level only. The kernel
        /// expects each descriptor's `targetSubband` to be 1 (LH),
        /// 2 (HL), or 3 (HH); the LL slot (0) is sourced from the
        /// previous level's output buffer (or the outermost-LL
        /// upload on the first level).
        public let scatterDescriptors: [J2KMetalSubbandScatterDescriptor]
        /// Subband dimensions. LL/LH/HL/HH all share the row pitch
        /// indicated by the descriptors' `subbandStride`; the per-
        /// level dimensions tell the kernel how big the per-subband
        /// 2D buffers must be.
        public let llWidth: Int
        public let llHeight: Int
        public let lhWidth: Int
        public let lhHeight: Int
        public let hlWidth: Int
        public let hlHeight: Int
        public let hhWidth: Int
        public let hhHeight: Int
        /// Output dimensions (= parent level dimensions). Inverse
        /// 5/3 produces an `originalWidth × originalHeight` output.
        public let originalWidth: Int
        public let originalHeight: Int
        /// Largest codeblock width × height across all of this level's
        /// scatter descriptors. Used to size the scatter dispatch grid.
        public let maxBlockWidth: Int
        public let maxBlockHeight: Int

        public init(
            scatterDescriptors: [J2KMetalSubbandScatterDescriptor],
            llWidth: Int, llHeight: Int,
            lhWidth: Int, lhHeight: Int,
            hlWidth: Int, hlHeight: Int,
            hhWidth: Int, hhHeight: Int,
            originalWidth: Int, originalHeight: Int,
            maxBlockWidth: Int, maxBlockHeight: Int
        ) {
            self.scatterDescriptors = scatterDescriptors
            self.llWidth = llWidth; self.llHeight = llHeight
            self.lhWidth = lhWidth; self.lhHeight = lhHeight
            self.hlWidth = hlWidth; self.hlHeight = hlHeight
            self.hhWidth = hhWidth; self.hhHeight = hhHeight
            self.originalWidth = originalWidth
            self.originalHeight = originalHeight
            self.maxBlockWidth = maxBlockWidth
            self.maxBlockHeight = maxBlockHeight
        }
    }

    #if canImport(Metal)
    /// v5.8: end-to-end fused inverse 5/3 from a codeblock-output
    /// buffer (HT cleanup + dequant output). For each decomposition
    /// level: the GPU scatter kernel writes LH/HL/HH from the
    /// codeblock buffer into per-subband 2D buffers; the inverse
    /// 5/3 kernel runs immediately after on the same cb. The output
    /// buffer of level N is reused as the LL input of level N-1.
    /// Single command buffer, single commit + await, single final
    /// readback.
    ///
    /// - Parameters:
    ///   - codeblockBuffer: GPU buffer containing dequantised Int32
    ///     codeblock samples — must be the output of an upstream
    ///     `J2KMetalHTCleanup.runIntegerMagnitude` call (or
    ///     equivalent). Caller is responsible for keeping it alive.
    ///   - levelsPlan: per-level scatter plans, ordered innermost
    ///     (index 0) to outermost (index N-1).
    ///   - initialLL: optional outermost-level LL (uploaded on
    ///     first level only); `nil` defaults to all-zero.
    /// - Returns: outermost-level Int32 output of size
    ///   `levelsPlan.last!.originalWidth × originalHeight`.
    public func inverse2DInt32FullFusedFromCodeblocks(
        codeblockBuffer: any MTLBuffer,
        levelsPlan: [LevelScatterPlan],
        initialLL: [Int32]?
    ) async throws -> [Int32] {
        guard !levelsPlan.isEmpty else {
            throw J2KError.invalidParameter("levelsPlan must be non-empty")
        }
        // Validate inter-level chain: each level's LL dims must
        // match the previous level's output dims.
        for i in 1..<levelsPlan.count {
            let prev = levelsPlan[i - 1]
            let cur = levelsPlan[i]
            guard cur.llWidth == prev.originalWidth,
                  cur.llHeight == prev.originalHeight else {
                throw J2KError.invalidParameter(
                    "levelsPlan chain mismatch at level \(i): " +
                    "expected LL=\(prev.originalWidth)×\(prev.originalHeight), " +
                    "got \(cur.llWidth)×\(cur.llHeight)")
            }
        }

        try await ensureInitialized()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let stride32 = MemoryLayout<Int32>.stride

        let scatterPipeline = try await shaderLibrary.computePipeline(for: .subbandScatter)

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create full-fused cb")
        }

        var inFlight: [any MTLBuffer] = []
        var currentLLBuffer: (any MTLBuffer)? = nil
        var finalOutputBuffer: (any MTLBuffer)? = nil
        var finalWidth = 0
        var finalHeight = 0

        for (planIdx, plan) in levelsPlan.enumerated() {
            let isLastLevel = (planIdx == levelsPlan.count - 1)
            // LL: first level uploads from CPU (initialLL or zeros);
            // subsequent levels reuse previous level's output buffer.
            // v5.10: when `initialLL == nil` (the v5.9e fast-lane and
            // v5.8 batch path), the LL buffer is GPU-only — scatter
            // populates it before the IDWT encoder runs. Allocate as
            // `.storageModePrivate` and use a blit fillBuffer encoder
            // for the zero-init instead of CPU memset.
            //
            // When `initialLL != nil` (multi-level-fused / per-level
            // / 9-7 paths), CPU writes the initial bytes — must
            // stay `.shared`.
            let llBuffer: any MTLBuffer
            if let prev = currentLLBuffer {
                llBuffer = prev
            } else {
                let llCount = plan.llWidth * plan.llHeight
                let bytes = max(llCount * stride32, 1)
                if let initial = initialLL, initial.count == llCount {
                    let buf = try await bufferPool.acquireBuffer(
                        device: device, size: bytes, strategy: .shared)
                    inFlight.append(buf)
                    initial.withUnsafeBytes { src in
                        buf.contents().copyMemory(
                            from: src.baseAddress!, byteCount: src.count)
                    }
                    llBuffer = buf
                } else {
                    let buf = try await bufferPool.acquireBuffer(
                        device: device, size: bytes, strategy: .private)
                    inFlight.append(buf)
                    if let blit = cb.makeBlitCommandEncoder() {
                        blit.fill(buffer: buf, range: 0..<bytes, value: 0)
                        blit.endEncoding()
                    }
                    llBuffer = buf
                }
            }

            // Acquire per-subband output buffers (LH/HL/HH). These
            // must be zero-initialised because the scatter kernel
            // only writes within the descriptors' bounds — padded
            // regions stay zero. v5.10: GPU-only intermediates →
            // `.private`; CPU memset replaced with a blit fillBuffer
            // encoder that runs in the same cb before the scatter
            // encoder reads from these buffers.
            let lhCount = plan.lhWidth * plan.lhHeight
            let hlCount = plan.hlWidth * plan.hlHeight
            let hhCount = plan.hhWidth * plan.hhHeight
            let lhBytes = max(lhCount * stride32, 1)
            let hlBytes = max(hlCount * stride32, 1)
            let hhBytes = max(hhCount * stride32, 1)
            let lhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: lhBytes, strategy: .private)
            inFlight.append(lhBuffer)
            let hlBuffer = try await bufferPool.acquireBuffer(
                device: device, size: hlBytes, strategy: .private)
            inFlight.append(hlBuffer)
            let hhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: hhBytes, strategy: .private)
            inFlight.append(hhBuffer)
            if let blit = cb.makeBlitCommandEncoder() {
                blit.fill(buffer: lhBuffer, range: 0..<lhBytes, value: 0)
                blit.fill(buffer: hlBuffer, range: 0..<hlBytes, value: 0)
                blit.fill(buffer: hhBuffer, range: 0..<hhBytes, value: 0)
                blit.endEncoding()
            }

            // Upload this level's scatter descriptors.
            let descStride = MemoryLayout<J2KMetalSubbandScatterDescriptor>.stride
            let descCount = plan.scatterDescriptors.count
            let descBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(descCount * descStride, 1))
            inFlight.append(descBuffer)
            if descCount > 0 {
                plan.scatterDescriptors.withUnsafeBufferPointer { src in
                    descBuffer.contents().copyMemory(
                        from: UnsafeRawPointer(src.baseAddress!),
                        byteCount: descCount * descStride)
                }
            }

            // Encoder 1: scatter — writes LL/LH/HL/HH from
            // codeblockBuffer. LL descriptors only fire at the
            // innermost level (the deepest residual LL); other
            // levels' LL is the previous level's output buffer
            // (currentLLBuffer = outputBuffer at the bottom of this
            // loop) and the scatter doesn't target it. The IDWT
            // encoder runs after scatter ends — Metal's automatic
            // ordering between successive compute encoders means
            // the IDWT sees the populated LL/LH/HL/HH cells.
            if descCount > 0 {
                guard let scatterEnc = cb.makeComputeCommandEncoder() else {
                    throw J2KError.internalError("Failed to create scatter encoder")
                }
                let scatter = J2KMetalSubbandScatter(
                    metalDevice: metalDevice,
                    shaderLibrary: shaderLibrary,
                    bufferPool: bufferPool)
                try scatter.encode(
                    into: scatterEnc, pipeline: scatterPipeline,
                    descriptorBuffer: descBuffer,
                    descriptorCount: descCount,
                    codeblocksBuffer: codeblockBuffer,
                    llBuffer: llBuffer,
                    lhBuffer: lhBuffer,
                    hlBuffer: hlBuffer,
                    hhBuffer: hhBuffer,
                    maxBlockWidth: plan.maxBlockWidth,
                    maxBlockHeight: plan.maxBlockHeight)
                scatterEnc.endEncoding()
            }

            // Encoder 2 & 3: inverse 5/3 (horizontal + vertical) via
            // the M4P-2 chainable API. Adds two compute encoders
            // into the same cb; implicit memory barrier between them
            // (and from the preceding scatter encoder).
            //
            // v5.10: colLow/colHigh are per-iteration scratch — GPU
            // writes (horizontal pass), GPU reads (vertical pass),
            // never CPU. Always `.private`. The output buffer stays
            // GPU-resident across iterations (becomes next level's
            // LL via `currentLLBuffer`), so intermediate iterations
            // can be `.private`; only the final iteration's output
            // is `.shared` because the caller readback path calls
            // `.contents()` on `finalOutputBuffer`.
            let colLowBuffer = try await bufferPool.acquireBuffer(
                device: device,
                size: plan.originalWidth * plan.llHeight * stride32,
                strategy: .private)
            inFlight.append(colLowBuffer)
            let colHighBuffer = try await bufferPool.acquireBuffer(
                device: device,
                size: max(plan.originalWidth * (plan.originalHeight / 2), 1) * stride32,
                strategy: .private)
            inFlight.append(colHighBuffer)
            let outputBuffer = try await bufferPool.acquireBuffer(
                device: device,
                size: plan.originalWidth * plan.originalHeight * stride32,
                strategy: isLastLevel ? .shared : .private)
            inFlight.append(outputBuffer)

            try await encodeInverse2DInt32(
                into: cb,
                ll: llBuffer, lh: lhBuffer, hl: hlBuffer, hh: hhBuffer,
                colLow: colLowBuffer, colHigh: colHighBuffer,
                output: outputBuffer,
                originalWidth: plan.originalWidth,
                originalHeight: plan.originalHeight,
                llHeight: plan.llHeight)

            currentLLBuffer = outputBuffer
            finalOutputBuffer = outputBuffer
            finalWidth = plan.originalWidth
            finalHeight = plan.originalHeight
        }

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Full-fused inverse 5/3 GPU dispatch failed: " +
                "\(cb.error?.localizedDescription ?? "(no description)")")
        }

        let result = readInt32Array(
            from: finalOutputBuffer!, elementCount: finalWidth * finalHeight)

        let pool = bufferPool
        let toReturn = inFlight
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        return result
    }
    #else
    public func inverse2DInt32FullFusedFromCodeblocks(
        codeblockBuffer: Any,
        levelsPlan: [LevelScatterPlan],
        initialLL: [Int32]?
    ) async throws -> [Int32] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    /// v5.26.0 Float counterpart of `LevelScatterPlan` for the 9/7
    /// lossy fused-from-codeblocks path. The descriptors carry a
    /// per-block Float `stepSize`; the scatter+dequant kernel
    /// applies `(coeff ± 0.5) * stepSize` (HTJ2K conformant
    /// cleanup-only) and writes Float to the per-subband 2D buffers.
    public struct LevelScatterPlanFloat: Sendable {
        public let scatterDescriptors: [J2KMetalSubbandScatterDescriptorFloat]
        public let llWidth: Int
        public let llHeight: Int
        public let lhWidth: Int
        public let lhHeight: Int
        public let hlWidth: Int
        public let hlHeight: Int
        public let hhWidth: Int
        public let hhHeight: Int
        public let originalWidth: Int
        public let originalHeight: Int
        public let maxBlockWidth: Int
        public let maxBlockHeight: Int

        public init(
            scatterDescriptors: [J2KMetalSubbandScatterDescriptorFloat],
            llWidth: Int, llHeight: Int,
            lhWidth: Int, lhHeight: Int,
            hlWidth: Int, hlHeight: Int,
            hhWidth: Int, hhHeight: Int,
            originalWidth: Int, originalHeight: Int,
            maxBlockWidth: Int, maxBlockHeight: Int
        ) {
            self.scatterDescriptors = scatterDescriptors
            self.llWidth = llWidth; self.llHeight = llHeight
            self.lhWidth = lhWidth; self.lhHeight = lhHeight
            self.hlWidth = hlWidth; self.hlHeight = hlHeight
            self.hhWidth = hhWidth; self.hhHeight = hhHeight
            self.originalWidth = originalWidth
            self.originalHeight = originalHeight
            self.maxBlockWidth = maxBlockWidth
            self.maxBlockHeight = maxBlockHeight
        }
    }

    #if canImport(Metal)
    /// v5.26.0 Float counterpart of `inverse2DInt32FullFusedFromCodeblocks`
    /// for the 9/7 lossy path. Mirrors the Int32 version's structure
    /// but uses the Float scatter+dequant kernel and the Float
    /// inverse-IDWT chainable encoder.
    ///
    /// - Parameters:
    ///   - codeblockBuffer: GPU buffer of Int32 codeblock samples
    ///     (HT cleanup integer-magnitude output). Unchanged from the
    ///     Int32 path — dequant is baked into the scatter kernel.
    ///   - levelsPlan: per-level Float scatter plans, ordered
    ///     innermost first.
    ///   - initialLL: optional outermost-level LL Float (uploaded on
    ///     the innermost level only); `nil` defaults to all-zero.
    /// - Returns: outermost-level Float output of size
    ///   `levelsPlan.last!.originalWidth × originalHeight`.
    public func inverse2DFullFusedFromCodeblocks(
        codeblockBuffer: any MTLBuffer,
        levelsPlan: [LevelScatterPlanFloat],
        initialLL: [Float]?
    ) async throws -> [Float] {
        guard !levelsPlan.isEmpty else {
            throw J2KError.invalidParameter("levelsPlan must be non-empty")
        }
        for i in 1..<levelsPlan.count {
            let prev = levelsPlan[i - 1]
            let cur = levelsPlan[i]
            guard cur.llWidth == prev.originalWidth,
                  cur.llHeight == prev.originalHeight else {
                throw J2KError.invalidParameter(
                    "levelsPlan chain mismatch at level \(i): " +
                    "expected LL=\(prev.originalWidth)×\(prev.originalHeight), " +
                    "got \(cur.llWidth)×\(cur.llHeight)")
            }
        }

        try await ensureInitialized()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let strideF = MemoryLayout<Float>.stride

        let scatterPipeline = try await shaderLibrary.computePipeline(for: .subbandScatterFloatDequant)

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create float full-fused cb")
        }

        var inFlight: [any MTLBuffer] = []
        var currentLLBuffer: (any MTLBuffer)? = nil
        var finalOutputBuffer: (any MTLBuffer)? = nil
        var finalWidth = 0
        var finalHeight = 0

        for (planIdx, plan) in levelsPlan.enumerated() {
            let isLastLevel = (planIdx == levelsPlan.count - 1)

            let llBuffer: any MTLBuffer
            if let prev = currentLLBuffer {
                llBuffer = prev
            } else {
                let llCount = plan.llWidth * plan.llHeight
                let bytes = max(llCount * strideF, 1)
                if let initial = initialLL, initial.count == llCount {
                    let buf = try await bufferPool.acquireBuffer(
                        device: device, size: bytes, strategy: .shared)
                    inFlight.append(buf)
                    initial.withUnsafeBytes { src in
                        buf.contents().copyMemory(
                            from: src.baseAddress!, byteCount: src.count)
                    }
                    llBuffer = buf
                } else {
                    let buf = try await bufferPool.acquireBuffer(
                        device: device, size: bytes, strategy: .private)
                    inFlight.append(buf)
                    if let blit = cb.makeBlitCommandEncoder() {
                        blit.fill(buffer: buf, range: 0..<bytes, value: 0)
                        blit.endEncoding()
                    }
                    llBuffer = buf
                }
            }

            let lhCount = plan.lhWidth * plan.lhHeight
            let hlCount = plan.hlWidth * plan.hlHeight
            let hhCount = plan.hhWidth * plan.hhHeight
            let lhBytes = max(lhCount * strideF, 1)
            let hlBytes = max(hlCount * strideF, 1)
            let hhBytes = max(hhCount * strideF, 1)
            let lhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: lhBytes, strategy: .private)
            inFlight.append(lhBuffer)
            let hlBuffer = try await bufferPool.acquireBuffer(
                device: device, size: hlBytes, strategy: .private)
            inFlight.append(hlBuffer)
            let hhBuffer = try await bufferPool.acquireBuffer(
                device: device, size: hhBytes, strategy: .private)
            inFlight.append(hhBuffer)
            if let blit = cb.makeBlitCommandEncoder() {
                blit.fill(buffer: lhBuffer, range: 0..<lhBytes, value: 0)
                blit.fill(buffer: hlBuffer, range: 0..<hlBytes, value: 0)
                blit.fill(buffer: hhBuffer, range: 0..<hhBytes, value: 0)
                blit.endEncoding()
            }

            let descStride = MemoryLayout<J2KMetalSubbandScatterDescriptorFloat>.stride
            let descCount = plan.scatterDescriptors.count
            let descBuffer = try await bufferPool.acquireBuffer(
                device: device, size: max(descCount * descStride, 1))
            inFlight.append(descBuffer)
            if descCount > 0 {
                plan.scatterDescriptors.withUnsafeBufferPointer { src in
                    descBuffer.contents().copyMemory(
                        from: UnsafeRawPointer(src.baseAddress!),
                        byteCount: descCount * descStride)
                }
            }

            // Encoder 1: Float scatter+dequant.
            if descCount > 0 {
                guard let scatterEnc = cb.makeComputeCommandEncoder() else {
                    throw J2KError.internalError("Failed to create float scatter encoder")
                }
                scatterEnc.setComputePipelineState(scatterPipeline)
                scatterEnc.setBuffer(descBuffer, offset: 0, index: 0)
                scatterEnc.setBuffer(codeblockBuffer, offset: 0, index: 1)
                scatterEnc.setBuffer(llBuffer, offset: 0, index: 2)
                scatterEnc.setBuffer(lhBuffer, offset: 0, index: 3)
                scatterEnc.setBuffer(hlBuffer, offset: 0, index: 4)
                scatterEnc.setBuffer(hhBuffer, offset: 0, index: 5)
                var dc = UInt32(descCount)
                scatterEnc.setBytes(&dc, length: MemoryLayout<UInt32>.stride, index: 6)
                let gridW = max(1, plan.maxBlockWidth)
                let gridH = max(1, plan.maxBlockHeight)
                scatterEnc.dispatchThreads(
                    MTLSize(width: gridW, height: gridH, depth: descCount),
                    threadsPerThreadgroup: MTLSize(
                        width: min(gridW, 8), height: min(gridH, 8), depth: 1))
                scatterEnc.endEncoding()
            }

            // Encoders 2-3: Float inverse-2D (vertical + horizontal).
            let hLowBuffer = try await bufferPool.acquireBuffer(
                device: device, size: plan.llWidth * plan.originalHeight * strideF,
                strategy: .private)
            inFlight.append(hLowBuffer)
            let hHighBuffer = try await bufferPool.acquireBuffer(
                device: device,
                size: max(plan.originalWidth / 2, 1) * plan.originalHeight * strideF,
                strategy: .private)
            inFlight.append(hHighBuffer)
            let outputBuffer = try await bufferPool.acquireBuffer(
                device: device,
                size: plan.originalWidth * plan.originalHeight * strideF,
                strategy: isLastLevel ? .shared : .private)
            inFlight.append(outputBuffer)

            try await encodeInverse2D(
                into: cb,
                ll: llBuffer, lh: lhBuffer, hl: hlBuffer, hh: hhBuffer,
                hLow: hLowBuffer, hHigh: hHighBuffer,
                output: outputBuffer,
                originalWidth: plan.originalWidth,
                originalHeight: plan.originalHeight,
                halfW: plan.llWidth)

            currentLLBuffer = outputBuffer
            finalOutputBuffer = outputBuffer
            finalWidth = plan.originalWidth
            finalHeight = plan.originalHeight
        }

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Full-fused inverse 9/7 GPU dispatch failed: " +
                "\(cb.error?.localizedDescription ?? "(no description)")")
        }

        let result = readFloatArray(
            from: finalOutputBuffer!, elementCount: finalWidth * finalHeight)

        let pool = bufferPool
        let toReturn = inFlight
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        return result
    }
    #else
    public func inverse2DFullFusedFromCodeblocks(
        codeblockBuffer: Any,
        levelsPlan: [LevelScatterPlanFloat],
        initialLL: [Float]?
    ) async throws -> [Float] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    /// Bit-exact reversible 5/3 single-level forward 2D DWT on `[Int32]`.
    ///
    /// **Lossless-only pivot — Phase 0.** Symmetric counterpart of
    /// `inverse2DInt32(subbands:backend:)`. The GPU path dispatches the
    /// `j2k_dwt_forward_53_*_int` kernels added in this phase; the CPU
    /// path delegates to the same reference forward 5/3 used elsewhere
    /// in the codebase. Both paths are bit-exact against each other and
    /// against the CPU encoder's `AcceleratedDWT2D.forward53_1D(...)`
    /// (verified by `J2KMetalDWTForward53IntBitExactTests`).
    ///
    /// This entry point intentionally does **NOT** wire into the
    /// production encoder pipeline yet — phase 1 work will add the
    /// dispatch from `J2KEncoderPipeline.applyWaveletTransform(...)`.
    /// Phase 0 only ships the verified building block.
    ///
    /// - Parameters:
    ///   - image: Row-major Int32 image buffer of length `width × height`.
    ///   - width: Image width in samples (≥ 2).
    ///   - height: Image height in samples (≥ 2).
    ///   - backend: GPU / CPU / auto. `.auto` routes by the same
    ///     `effectiveBackend(...)` heuristic used by every other DWT
    ///     entry point on this struct.
    /// - Returns: The four single-level Int32 subbands (LL/LH/HL/HH)
    ///   plus their dimensions.
    public func forward2DInt32(
        image: [Int32],
        width: Int,
        height: Int,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> J2KMetalDWTSubbandsInt32 {
        try await forward2DInt32(
            image: image, width: width, height: height,
            tileOriginX: 0, tileOriginY: 0, backend: backend)
    }

    /// Bit-exact reversible 5/3 single-level forward 2D DWT on Int32
    /// with **tile-component image-coordinate origin awareness**.
    ///
    /// **Lossless-only pivot — Phase 4 slice 1.** Symmetric counterpart
    /// of the parity-aware decoder path landed in v6-alpha3 step 6B.
    /// When both origins are even, output is byte-identical to the
    /// no-origin overload (which routes through the existing Phase 0
    /// even-origin kernels). When either axis has an odd origin, the
    /// new `j2k_dwt_forward_53_*_int_odd` kernels are dispatched on
    /// that axis; band counts swap per ISO/IEC 15444-1 F.4.4.
    ///
    /// The CPU fallback delegates to `forward2DCPUInt32WithOrigin` which
    /// runs the locally-duplicated parity-aware reference. Both paths
    /// are bit-exact-equivalent and bit-exact against the production
    /// CPU reference `AcceleratedDWT2D.forward2D_53(...tileOriginX:
    /// tileOriginY:)`.
    public func forward2DInt32(
        image: [Int32],
        width: Int, height: Int,
        tileOriginX uX: Int, tileOriginY uY: Int,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> J2KMetalDWTSubbandsInt32 {
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Image dimensions must be at least 2×2, got \(width)×\(height)"
            )
        }
        guard image.count == width * height else {
            throw J2KError.invalidParameter(
                "Image size \(image.count) doesn't match dimensions \(width)×\(height)"
            )
        }

        let startTime = currentTime()
        _statistics.totalOperations += 1

        let effective = effectiveBackend(width: width, height: height, backend: backend)

        let result: J2KMetalDWTSubbandsInt32
        if effective == .gpu {
            result = try await forward2DGPUInt32WithOrigin(
                image: image, width: width, height: height, uX: uX, uY: uY)
            _statistics.gpuOperations += 1
        } else {
            result = forward2DCPUInt32WithOrigin(
                image: image, width: width, height: height, uX: uX, uY: uY)
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    public func inverse2DInt32(
        subbands: J2KMetalDWTSubbandsInt32,
        backend: J2KMetalDWTBackend = .auto
    ) async throws -> [Int32] {
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

        let result: [Int32]
        if effective == .gpu {
            result = try await inverse2DGPUInt32(subbands: subbands)
            _statistics.gpuOperations += 1
        } else {
            result = inverse2DCPUInt32(subbands: subbands)
            _statistics.cpuOperations += 1
        }

        _statistics.totalProcessingTime += currentTime() - startTime
        return result
    }

    // MARK: - v10.20-research Phase 2 — BATCHED inverse 5/3 Int

    /// Performs N parallel inverse 2D 5/3 Int transforms in one Metal
    /// command buffer. The batch's `subbandsBatch[i]` produces the
    /// returned `[Int32]` at index `i`. **All slices in the batch
    /// MUST have identical dimensions** (originalWidth, originalHeight,
    /// llWidth, llHeight) — JP3D's slice-stack codec guarantees this
    /// (every slice in a tile shares header.tileWidth × tileHeight),
    /// and this method throws `J2KError.invalidParameter` on mixed
    /// dimensions so the caller cannot silently produce wrong output.
    ///
    /// Why batched: per-slice GPU dispatch overhead × N slices
    /// regressed JP3D decode in the naive forced-per-slice routing
    /// (`V10_19_JP3D_GPU_IDWT_CLOSED.md`). One dispatch over N slices
    /// amortises that overhead across the volume; the new batched
    /// kernels `j2k_dwt_inverse_53_{horizontal,vertical}_int_tiled_batched`
    /// use a Z grid dimension where `tgid.z = slice index`, with
    /// per-slice stride offsets passed as constants.
    ///
    /// Bit-exact: each output slice is byte-identical to what
    /// `inverse2DInt32(subbands: subbandsBatch[i], backend: .metal)`
    /// would produce. Parity test:
    /// `V10_20_BatchedInverseInt32ParityTests`.
    ///
    /// **Single-slice batches collapse to current behaviour** — a
    /// batch of 1 dispatches the same kernel with `gridDepth = 1`,
    /// equivalent to the existing tiled path.
    public func inverseBatched2DInt32(
        subbandsBatch: [J2KMetalDWTSubbandsInt32]
    ) async throws -> [[Int32]] {
        guard !subbandsBatch.isEmpty else { return [] }

        // Uniform-dimension guard. JP3D slice-stack guarantees this;
        // exposing the SPI more generally would require fall-through
        // to serial dispatch for non-uniform batches (not implemented).
        let head = subbandsBatch[0]
        for (i, s) in subbandsBatch.enumerated() {
            guard s.originalWidth == head.originalWidth,
                  s.originalHeight == head.originalHeight,
                  s.llWidth == head.llWidth,
                  s.llHeight == head.llHeight else {
                throw J2KError.invalidParameter(
                    "inverseBatched2DInt32: slice \(i) dimensions "
                    + "\(s.originalWidth)x\(s.originalHeight) / "
                    + "ll=\(s.llWidth)x\(s.llHeight) do not match batch "
                    + "head \(head.originalWidth)x\(head.originalHeight) / "
                    + "ll=\(head.llWidth)x\(head.llHeight). All slices "
                    + "in a batch must share identical dimensions.")
            }
        }

        let width = head.originalWidth
        let height = head.originalHeight
        guard width >= 2, height >= 2 else {
            throw J2KError.invalidParameter(
                "Subband dimensions must produce at least 2×2 output")
        }

        let nSlices = subbandsBatch.count
        let startTime = currentTime()
        _statistics.totalOperations += 1

        // Currently batched path is GPU-only. CPU fallback would
        // collapse to the serial loop — exposed as a future-work
        // option if needed; not needed for the JP3D use case.
        let result = try await inverseBatched2DGPUInt32(subbandsBatch: subbandsBatch)
        _statistics.gpuOperations += 1
        _statistics.totalProcessingTime += currentTime() - startTime
        _ = nSlices
        return result
    }

    private func inverseBatched2DGPUInt32(
        subbandsBatch: [J2KMetalDWTSubbandsInt32]
    ) async throws -> [[Int32]] {
        try await ensureInitialized()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let head = subbandsBatch[0]
        let width = head.originalWidth
        let height = head.originalHeight
        let bands = BandGeometry(width: width, height: height,
                                 llW: head.llWidth, llH: head.llHeight)
        let llH = bands.llH
        let halfHH = bands.halfHH
        let nSlices = subbandsBatch.count

        // Per-slice band element counts. The H pass produces colLow
        // (width × llH) and colHigh (width × halfHH); V pass produces
        // the final output (width × height).
        let llCount = max(head.ll.count, 1)
        let lhCount = max(head.lh.count, 1)
        let hlCount = max(head.hl.count, 1)
        let hhCount = max(head.hh.count, 1)
        let colLowCount = width * llH
        let colHighCount = max(width * halfHH, 1)
        let outputCount = width * height

        let stride32 = MemoryLayout<Int32>.stride

        func makeBuffer(_ size: Int) throws -> any MTLBuffer {
            guard let buf = device.makeBuffer(length: max(size, 1),
                                              options: .storageModeShared) else {
                throw J2KError.internalError("Failed to allocate Metal buffer")
            }
            return buf
        }

        // Allocate ONE batched buffer per band, sized N × per-slice size.
        // Layout: slice s's data starts at s * sliceStride.
        let llBuffer = try makeBuffer(nSlices * llCount * stride32)
        let lhBuffer = try makeBuffer(nSlices * lhCount * stride32)
        let hlBuffer = try makeBuffer(nSlices * hlCount * stride32)
        let hhBuffer = try makeBuffer(nSlices * hhCount * stride32)
        let colLowBuffer = try makeBuffer(nSlices * colLowCount * stride32)
        let colHighBuffer = try makeBuffer(nSlices * colHighCount * stride32)
        let outputBuffer = try makeBuffer(nSlices * outputCount * stride32)

        // Copy each slice's coefficients into the corresponding Z stride.
        for (s, sub) in subbandsBatch.enumerated() {
            if !sub.ll.isEmpty {
                sub.ll.withUnsafeBytes { src in
                    let dst = llBuffer.contents() + s * llCount * stride32
                    dst.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }
            if !sub.lh.isEmpty {
                sub.lh.withUnsafeBytes { src in
                    let dst = lhBuffer.contents() + s * lhCount * stride32
                    dst.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }
            if !sub.hl.isEmpty {
                sub.hl.withUnsafeBytes { src in
                    let dst = hlBuffer.contents() + s * hlCount * stride32
                    dst.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }
            if !sub.hh.isEmpty {
                sub.hh.withUnsafeBytes { src in
                    let dst = hhBuffer.contents() + s * hhCount * stride32
                    dst.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }
        }

        let horizontalPSO = try await shaderLibrary.computePipeline(for: .dwtInverse53HorizontalIntTiledBatched)
        let verticalPSO   = try await shaderLibrary.computePipeline(for: .dwtInverse53VerticalIntTiledBatched)

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create batched-iDWT command buffer")
        }

        // H pass — combine LL+HL into colLow, LH+HH into colHigh.
        // We dispatch the batched horizontal kernel twice (once per
        // band pair), with N parallel slices each time. Same shape
        // as the v10.3 tiled pair, just with Z grid extension.
        let halfWidth = (width + 1) / 2
        let halfWidthH = width / 2

        // Pass A: LL (ll lowpass) + HL (hl highpass) → colLow
        var widthVar = UInt32(width)
        var heightVarLowH = UInt32(llH)   // process llH rows
        var sliceStrideLowA = UInt32(llCount)
        var sliceStrideHighA = UInt32(hlCount)
        var sliceStrideOutA = UInt32(colLowCount)
        if let encA = cb.makeComputeCommandEncoder() {
            encA.setComputePipelineState(horizontalPSO)
            encA.setBuffer(llBuffer, offset: 0, index: 0)
            encA.setBuffer(hlBuffer, offset: 0, index: 1)
            encA.setBuffer(colLowBuffer, offset: 0, index: 2)
            encA.setBytes(&widthVar,        length: MemoryLayout<UInt32>.size, index: 3)
            encA.setBytes(&heightVarLowH,   length: MemoryLayout<UInt32>.size, index: 4)
            encA.setBytes(&sliceStrideLowA, length: MemoryLayout<UInt32>.size, index: 5)
            encA.setBytes(&sliceStrideHighA,length: MemoryLayout<UInt32>.size, index: 6)
            encA.setBytes(&sliceStrideOutA, length: MemoryLayout<UInt32>.size, index: 7)
            let tgPerGridX = (halfWidth + 31) / 32
            let tgPerGridY = (llH + 7) / 8
            encA.dispatchThreadgroups(
                MTLSize(width: tgPerGridX, height: tgPerGridY, depth: nSlices),
                threadsPerThreadgroup: MTLSize(width: 32, height: 8, depth: 1))
            encA.endEncoding()
            _ = halfWidthH
        }

        // Pass B: LH (lh lowpass) + HH (hh highpass) → colHigh
        var heightVarHalfHH = UInt32(halfHH)
        var sliceStrideLowB = UInt32(lhCount)
        var sliceStrideHighB = UInt32(hhCount)
        var sliceStrideOutB = UInt32(colHighCount)
        if halfHH > 0, let encB = cb.makeComputeCommandEncoder() {
            encB.setComputePipelineState(horizontalPSO)
            encB.setBuffer(lhBuffer, offset: 0, index: 0)
            encB.setBuffer(hhBuffer, offset: 0, index: 1)
            encB.setBuffer(colHighBuffer, offset: 0, index: 2)
            encB.setBytes(&widthVar,        length: MemoryLayout<UInt32>.size, index: 3)
            encB.setBytes(&heightVarHalfHH, length: MemoryLayout<UInt32>.size, index: 4)
            encB.setBytes(&sliceStrideLowB, length: MemoryLayout<UInt32>.size, index: 5)
            encB.setBytes(&sliceStrideHighB,length: MemoryLayout<UInt32>.size, index: 6)
            encB.setBytes(&sliceStrideOutB, length: MemoryLayout<UInt32>.size, index: 7)
            let tgPerGridX = (halfWidth + 31) / 32
            let tgPerGridY = (halfHH + 7) / 8
            encB.dispatchThreadgroups(
                MTLSize(width: tgPerGridX, height: tgPerGridY, depth: nSlices),
                threadsPerThreadgroup: MTLSize(width: 32, height: 8, depth: 1))
            encB.endEncoding()
        }

        // V pass: colLow + colHigh → final output.
        var heightVarFinal = UInt32(height)
        var sliceStrideLowC = UInt32(colLowCount)
        var sliceStrideHighC = UInt32(colHighCount)
        var sliceStrideOutC = UInt32(outputCount)
        if let encC = cb.makeComputeCommandEncoder() {
            encC.setComputePipelineState(verticalPSO)
            encC.setBuffer(colLowBuffer, offset: 0, index: 0)
            encC.setBuffer(colHighBuffer, offset: 0, index: 1)
            encC.setBuffer(outputBuffer, offset: 0, index: 2)
            encC.setBytes(&widthVar,        length: MemoryLayout<UInt32>.size, index: 3)
            encC.setBytes(&heightVarFinal,  length: MemoryLayout<UInt32>.size, index: 4)
            encC.setBytes(&sliceStrideLowC, length: MemoryLayout<UInt32>.size, index: 5)
            encC.setBytes(&sliceStrideHighC,length: MemoryLayout<UInt32>.size, index: 6)
            encC.setBytes(&sliceStrideOutC, length: MemoryLayout<UInt32>.size, index: 7)
            let tgPerGridX = (width + 31) / 32
            let tgPerGridY = ((height + 1) / 2 + 7) / 8
            encC.dispatchThreadgroups(
                MTLSize(width: tgPerGridX, height: tgPerGridY, depth: nSlices),
                threadsPerThreadgroup: MTLSize(width: 32, height: 8, depth: 1))
            encC.endEncoding()
        }

        cb.commit()
        await cb.completed()
        if cb.status == .error {
            throw J2KError.internalError(
                "Batched inverse 5/3 GPU dispatch failed: \(cb.error?.localizedDescription ?? "(no description)")")
        }

        // Read back per-slice output slices. readInt32Array doesn't
        // take a byte offset; copy directly from the typed pointer.
        var results: [[Int32]] = []
        results.reserveCapacity(nSlices)
        let basePtr = outputBuffer.contents().assumingMemoryBound(to: Int32.self)
        J2KMetalUMACounters.incrementContents()
        for s in 0..<nSlices {
            let sliceStart = basePtr + s * outputCount
            let slice = [Int32](unsafeUninitializedCapacity: outputCount) { buf, count in
                buf.baseAddress!.update(from: sliceStart, count: outputCount)
                count = outputCount
            }
            J2KMetalUMACounters.incrementMemcpy()
            results.append(slice)
        }
        return results
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

        // Scaling (ISO/IEC 15444-1 Annex F.4.1.1)
        // v5.21.0 fix: lowpass /= K, highpass *= K. Pre-v5.21 had
        // this inverted, matching the equally-inverted GPU forward
        // and inverse — self-consistent but spec-violating.
        for i in 0..<halfN { even[i] /= K }
        for i in 0..<halfH { odd[i] *= K }

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

        // v5.21.0 fix: undo the J2KCodec encoder's spec-compliant
        // forward scaling (lowpass /= K, highpass *= K per ISO/IEC
        // 15444-1 Annex F.4.1.1). Pre-v5.21 J2KMetalDWT used the
        // OPPOSITE direction here AND in the GPU kernels, so the
        // module was self-consistent but produced K⁴-scaled
        // garbage when paired with J2KCodec-encoded codestreams.
        // Test: J2KGPULossy97DivergenceTests measured ~19k LSB
        // average error in 16-bit space pre-fix.
        var even = lowpass.map { $0 * K }
        var odd  = highpass.map { $0 / K }

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

        // Allocate buffers directly to avoid actor boundary crossing
        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1),
                options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let inputBuffer = try makeBuffer(size: signal.count * MemoryLayout<Float>.stride)
        let lowBuffer = try makeBuffer(size: halfWidth * MemoryLayout<Float>.stride)
        let highBuffer = try makeBuffer(size: max(halfWidthH, 1) * MemoryLayout<Float>.stride)

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

        // Buffers released via ARC when they go out of scope

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

        // Allocate buffers directly to avoid actor boundary crossing
        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1),
                options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let lowBuffer = try makeBuffer(size: halfWidth * MemoryLayout<Float>.stride)
        let highBuffer = try makeBuffer(size: max(halfWidthH, 1) * MemoryLayout<Float>.stride)
        let outputBuffer = try makeBuffer(size: outputLength * MemoryLayout<Float>.stride)

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

        // Buffers released via ARC when they go out of scope

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

        // Allocate all buffers directly to avoid repeated actor boundary crossings
        // which can cause thread pool exhaustion after MTLCommandBuffer.completed()
        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1),
                options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let inputBuffer = try makeBuffer(size: data.count * MemoryLayout<Float>.stride)
        let hLowBuffer = try makeBuffer(size: halfW * height * MemoryLayout<Float>.stride)
        let hHighBuffer = try makeBuffer(size: max(halfWH * height, 1) * MemoryLayout<Float>.stride)
        let llBuffer = try makeBuffer(size: halfW * halfH * MemoryLayout<Float>.stride)
        let lhBuffer = try makeBuffer(size: max(halfW * halfHH, 1) * MemoryLayout<Float>.stride)
        let hlBuffer = try makeBuffer(size: max(halfWH * halfH, 1) * MemoryLayout<Float>.stride)
        let hhBuffer = try makeBuffer(size: max(halfWH * halfHH, 1) * MemoryLayout<Float>.stride)

        // Get both pipelines upfront (single actor boundary crossing each)
        let hPipeline = try await shaderLibrary.computePipeline(
            for: horizontalForwardShaderFunction()
        )
        let vPipeline = try await shaderLibrary.computePipeline(
            for: verticalForwardShaderFunction()
        )

        // Copy input
        data.withUnsafeBytes { src in
            inputBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        // Step 1: Horizontal forward DWT
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

        // Step 2 & 3: Vertical DWT on lowpass → LL, LH AND highpass → HL, HH
        guard let cb2 = queue.makeCommandBuffer(),
              let enc2 = cb2.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        // Encode vertical DWT on lowpass columns → LL, LH
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

        // Encode vertical DWT on highpass columns → HL, HH (in same command buffer)
        if halfWH > 0 {
            enc2.setBuffer(hHighBuffer, offset: 0, index: 0)
            enc2.setBuffer(hlBuffer, offset: 0, index: 1)
            enc2.setBuffer(hhBuffer, offset: 0, index: 2)
            var halfWHVal = UInt32(halfWH)
            enc2.setBytes(&halfWHVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc2.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)

            let vThreads2 = MTLSize(width: halfWH, height: 1, depth: 1)
            let vThreadgroup2 = MTLSize(width: min(halfWH, 64), height: 1, depth: 1)
            enc2.dispatchThreads(vThreads2, threadsPerThreadgroup: vThreadgroup2)
        }

        enc2.endEncoding()
        cb2.commit()
        await cb2.completed()

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

        // Buffers are allocated directly (not from pool), so they are
        // released automatically when they go out of scope via ARC.

        return J2KMetalDWTSubbands(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: halfW, llHeight: halfH,
            originalWidth: width, originalHeight: height
        )
    }

    private func readFloatArray(from buffer: MTLBuffer, elementCount: Int) -> [Float] {
        guard elementCount > 0 else { return [] }
        var result = [Float](repeating: 0, count: elementCount)
        let ptr = buffer.contents()
        result.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(
                start: ptr,
                count: elementCount * MemoryLayout<Float>.stride
            ))
        }
        return result
    }

    private func inverse2DGPU(
        subbands: J2KMetalDWTSubbands
    ) async throws -> [Float] {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let width = subbands.originalWidth
        let height = subbands.originalHeight
        let halfW = subbands.llWidth
        let halfWH = width / 2

        // Allocate all buffers directly to avoid actor boundary crossing after cb.completed()
        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1),
                options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let llBuffer = try makeBuffer(size: subbands.ll.count * MemoryLayout<Float>.stride)
        let lhBuffer = try makeBuffer(size: max(subbands.lh.count, 1) * MemoryLayout<Float>.stride)
        let hlBuffer = try makeBuffer(size: max(subbands.hl.count, 1) * MemoryLayout<Float>.stride)
        let hhBuffer = try makeBuffer(size: max(subbands.hh.count, 1) * MemoryLayout<Float>.stride)
        let hLowBuffer = try makeBuffer(size: halfW * height * MemoryLayout<Float>.stride)
        let hHighBuffer = try makeBuffer(size: max(halfWH * height, 1) * MemoryLayout<Float>.stride)
        let outputBuffer = try makeBuffer(size: width * height * MemoryLayout<Float>.stride)

        // Get both pipelines upfront
        let vPipeline = try await shaderLibrary.computePipeline(
            for: verticalInverseShaderFunction()
        )
        let hPipeline = try await shaderLibrary.computePipeline(
            for: horizontalInverseShaderFunction()
        )

        // Copy subband data to GPU
        subbands.ll.withUnsafeBytes { src in
            llBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        if !subbands.lh.isEmpty {
            subbands.lh.withUnsafeBytes { src in
                lhBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }
        if !subbands.hl.isEmpty {
            subbands.hl.withUnsafeBytes { src in
                hlBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }
        if !subbands.hh.isEmpty {
            subbands.hh.withUnsafeBytes { src in
                hhBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }

        // Step 1: Inverse vertical DWT — LL + LH → hLow, HL + HH → hHigh
        guard let cb1 = queue.makeCommandBuffer(),
              let enc1 = cb1.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        // Inverse vertical on LL + LH → hLow
        enc1.setComputePipelineState(vPipeline)
        enc1.setBuffer(llBuffer, offset: 0, index: 0)
        enc1.setBuffer(lhBuffer, offset: 0, index: 1)
        enc1.setBuffer(hLowBuffer, offset: 0, index: 2)
        var halfWVal = UInt32(halfW)
        var hVal = UInt32(height)
        enc1.setBytes(&halfWVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc1.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)

        let vThreads1 = MTLSize(width: halfW, height: 1, depth: 1)
        let vThreadgroup1 = MTLSize(width: min(halfW, 64), height: 1, depth: 1)
        enc1.dispatchThreads(vThreads1, threadsPerThreadgroup: vThreadgroup1)

        // Inverse vertical on HL + HH → hHigh
        if halfWH > 0 {
            enc1.setBuffer(hlBuffer, offset: 0, index: 0)
            enc1.setBuffer(hhBuffer, offset: 0, index: 1)
            enc1.setBuffer(hHighBuffer, offset: 0, index: 2)
            var halfWHVal = UInt32(halfWH)
            enc1.setBytes(&halfWHVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc1.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)

            let vThreads2 = MTLSize(width: halfWH, height: 1, depth: 1)
            let vThreadgroup2 = MTLSize(width: min(halfWH, 64), height: 1, depth: 1)
            enc1.dispatchThreads(vThreads2, threadsPerThreadgroup: vThreadgroup2)
        }

        enc1.endEncoding()
        cb1.commit()
        await cb1.completed()

        // Step 2: Inverse horizontal DWT — hLow + hHigh → output
        guard let cb2 = queue.makeCommandBuffer(),
              let enc2 = cb2.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        enc2.setComputePipelineState(hPipeline)
        enc2.setBuffer(hLowBuffer, offset: 0, index: 0)
        enc2.setBuffer(hHighBuffer, offset: 0, index: 1)
        enc2.setBuffer(outputBuffer, offset: 0, index: 2)
        var wVal = UInt32(width)
        enc2.setBytes(&wVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc2.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)

        let hThreads = MTLSize(width: 1, height: height, depth: 1)
        let hThreadgroup = MTLSize(width: 1, height: min(height, 64), depth: 1)
        enc2.dispatchThreads(hThreads, threadsPerThreadgroup: hThreadgroup)
        enc2.endEncoding()
        cb2.commit()
        await cb2.completed()

        // Read result
        let result = readFloatArray(from: outputBuffer, elementCount: width * height)

        return result
    }

    // MARK: - Bit-exact Reversible 5/3 (Int32) GPU/CPU paths

    private func inverse2DGPUInt32(
        subbands: J2KMetalDWTSubbandsInt32
    ) async throws -> [Int32] {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let width = subbands.originalWidth
        let height = subbands.originalHeight
        // Canvas-anchored band geometry — see `BandGeometry`. The
        // horizontal pass derives its own widths, so only the heights
        // are consumed here; `halfHH = height − llH`, never `height / 2`.
        let bands = BandGeometry(width: width, height: height,
                                 llW: subbands.llWidth, llH: subbands.llHeight)
        let llH = bands.llH
        let halfHH = bands.halfHH

        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1),
                options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let stride32 = MemoryLayout<Int32>.stride
        let llBuffer = try makeBuffer(size: subbands.ll.count * stride32)
        let lhBuffer = try makeBuffer(size: max(subbands.lh.count, 1) * stride32)
        let hlBuffer = try makeBuffer(size: max(subbands.hl.count, 1) * stride32)
        let hhBuffer = try makeBuffer(size: max(subbands.hh.count, 1) * stride32)
        let colLowBuffer = try makeBuffer(size: width * llH * stride32)
        let colHighBuffer = try makeBuffer(size: max(width * halfHH, 1) * stride32)
        let outputBuffer = try makeBuffer(size: width * height * stride32)

        subbands.ll.withUnsafeBytes { src in
            llBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        if !subbands.lh.isEmpty {
            subbands.lh.withUnsafeBytes { src in
                lhBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }
        if !subbands.hl.isEmpty {
            subbands.hl.withUnsafeBytes { src in
                hlBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }
        if !subbands.hh.isEmpty {
            subbands.hh.withUnsafeBytes { src in
                hhBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }

        // v5.7.0: encode both passes (horizontal + vertical) into a
        // single command buffer via the new
        // `encodeInverse2DInt32(into:...)` chainable API. Two separate
        // compute encoders within one cb give an implicit memory
        // barrier between them — vertical reads colLow/colHigh that
        // horizontal writes, so the dependency is honoured. One
        // commit + one await per inverse2D call instead of v5.6.0's
        // two of each.
        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create command buffer")
        }
        try await encodeInverse2DInt32(
            into: cb,
            ll: llBuffer, lh: lhBuffer, hl: hlBuffer, hh: hhBuffer,
            colLow: colLowBuffer, colHigh: colHighBuffer,
            output: outputBuffer,
            originalWidth: width, originalHeight: height,
            llHeight: llH,
            tileOriginX: subbands.tileOriginX,
            tileOriginY: subbands.tileOriginY)
        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Inverse 5/3 GPU dispatch failed: \(cb.error?.localizedDescription ?? "(no description)")")
        }

        return readInt32Array(from: outputBuffer, elementCount: width * height)
    }

    /// Encode the bit-exact reversible 5/3 inverse 2D transform
    /// into an existing command buffer, using caller-supplied input
    /// (LL/LH/HL/HH) and output buffers. Two compute encoders are
    /// added (horizontal then vertical); the implicit memory barrier
    /// between encoders ensures vertical sees horizontal's writes
    /// without an explicit commit / wait.
    ///
    /// Caller is responsible for buffer allocation + uploads + the
    /// final `cb.commit() + await cb.completed()` + readback. Used
    /// by the v5.7.0 fused HT-cleanup → DWT path so the entire
    /// per-tile inverse DWT (across multiple decomposition levels)
    /// can stay in one command buffer with no intermediate readback.
    /// **v10.3 Phase 2-1** — env-gated routing for the 2D-thread-layout
    /// inverse 5/3 Int kernels. Default OFF; set
    /// `J2K_METAL_IDWT_2D=1` to opt in. Bit-exact equivalent of the
    /// scalar path per `V10_3_MetalIDWTInverse532DParityTests`.
    nonisolated(unsafe) public static var inverse53Int2DLayoutEnabled: Bool = {
        ProcessInfo.processInfo.environment["J2K_METAL_IDWT_2D"] == "1"
    }()

    /// **v10.3 Phase 2-2-tiled — DEFAULT-ON 2026-05-15**. Threadgroup-
    /// memory tiled inverse 5/3 Int kernels: step 1 + step 2 in one
    /// dispatch per pass via threadgroup memory + barrier, closing the
    /// kernel-boundary cost that Phase 2-1's split-step regressed on
    /// large fixtures.
    ///
    /// Phase 2-2-tiled gate results (M2 release, v10.3-research):
    /// - `V10_3_MetalIDWTInverse53TiledParityTests`: 4/4 PASS (bit-exact)
    /// - `J2KStrictCrossCodecValidationTests` with env on: 3/3 PASS
    /// - Microbench: 1.27-6.44× speedup across substitute corpus; DX
    ///   2544 +1.49× (-6.28 ms), MG 3520 +1.50× (-33.34 ms)
    /// - Substitute A/B `.auto` row: MG −17.18 ms, DX 2544 neutral,
    ///   PX −3.38 ms, no regressions ≥3 ms
    ///
    /// **Opt-out:** set `J2K_METAL_IDWT_TILED=0` to fall back to scalar
    /// (or `J2K_METAL_IDWT_2D=1` for Phase 2-1's 2D-layout path).
    ///
    /// Takes precedence over `inverse53Int2DLayoutEnabled` when both
    /// are set.
    nonisolated(unsafe) public static var inverse53IntTiledEnabled: Bool = {
        // Default ON unless explicit opt-out.
        ProcessInfo.processInfo.environment["J2K_METAL_IDWT_TILED"] != "0"
    }()

    /// v10.5 Phase 2-3-fused — opt-in gate for the single-kernel
    /// H+V fused inverse 5/3 Int dispatch. Default **OFF**; set
    /// `J2K_METAL_IDWT_FUSED=1` to enable.
    ///
    /// The fused kernel collapses the v10.3 Phase 2-2-tiled pair
    /// (`*_horizontal_int_tiled` + `*_vertical_int_tiled`) into one
    /// dispatch per IDWT level. It eliminates the colLow/colHigh
    /// device-memory round-trip (~2× DRAM saving per level) and
    /// drops the per-level encoder overhead from 3 dispatches to 1.
    ///
    /// Bit-exact equivalent of the tiled pair (`V10_5_MetalIDWTInverse53FusedParityTests`:
    /// 3/3 PASS across small / odd / medical corpus dimensions).
    /// Takes precedence over `inverse53IntTiledEnabled` when both
    /// are set; available only for even-origin (no tile-origin
    /// canvas adjustment).
    ///
    /// **Why default OFF** (per `V10_5_METAL_IDWT_FUSED_FINDING.md`
    /// and the 10-trial variance bench
    /// `V10_5_MetalIDWTInverse53FusedVarianceTests`):
    ///   - MG small (16.8 MP) — median +4.68 ms, 70% positive (RELIABLE WIN)
    ///   - MG mid (16.8 MP) — median +2.64 ms, 70% positive
    ///   - MG large (16.8 MP) — median +7.67 ms BUT 50% positive,
    ///     std 8.27 ms (high run-to-run variance, coin-flip per decode)
    ///   - DX / PX / XA / CT — wash (no win, no regression) at the
    ///     per-level scale where the bandwidth lever doesn't apply
    ///
    /// The lever is gated by `inverse53IntFusedPixelThreshold` so
    /// that even when opt-in is set, only ≥12 MP per-level passes
    /// take the fused path. Below threshold stays on the v10.3
    /// Phase 2-2-tiled pair where it has consistent win/wash
    /// telemetry.
    ///
    /// **v10.3.0 (2026-05-20): default flipped from OFF to ON.** Paired
    /// with the `_gpuHTEntropyEnabled` flag flip (default ON → OFF in
    /// v10.3.0). With the GPU HT entropy regression eliminated, the
    /// remaining MG-class wall budget is dominated by IDWT, where the
    /// fused-kernel +2.6 to +4.7 ms median improvement holds. The
    /// 12 MP pixel-threshold gate confines the fused path to MG-class
    /// fixtures only — DX/PX/XA/CT stay on the v10.1.0 Phase 2-2-tiled
    /// pair where they have consistent win/wash telemetry.
    ///
    /// **Opt-out via `J2K_METAL_IDWT_FUSED=0`** for diagnostic A/B,
    /// cross-silicon re-measurement (M3+/A-series L2 / DRAM curves
    /// differ), or production rollback.
    nonisolated(unsafe) public static var inverse53IntFusedEnabled: Bool = {
        // Default ON unless explicit opt-out.
        ProcessInfo.processInfo.environment["J2K_METAL_IDWT_FUSED"] != "0"
    }()

    /// v10.5 Phase 2-3-fused — per-level pixel-count threshold for
    /// the fused IDWT dispatch. Defaults to **12 000 000** (12 MP),
    /// the boundary the variance bench established: above 12 MP
    /// (MG class) the fused path has a positive median lift; below
    /// 12 MP (DX 7.7 MP / PX 3.7 MP / XA 1 MP / CT 0.26 MP) the
    /// lever doesn't apply and the path was wash or marginally
    /// regressed.
    ///
    /// This mirrors `_gpuInverse53PixelThreshold = 4_000_000` —
    /// per-level pixel-count gate inside the GPU dispatch.
    ///
    /// Mutable so tests / diagnostics can lower the threshold to
    /// force the fused path on smaller fixtures for A/B work.
    nonisolated(unsafe) public static var inverse53IntFusedPixelThreshold: Int = 12_000_000

    public func encodeInverse2DInt32(
        into cb: any MTLCommandBuffer,
        ll: any MTLBuffer,
        lh: any MTLBuffer,
        hl: any MTLBuffer,
        hh: any MTLBuffer,
        colLow: any MTLBuffer,
        colHigh: any MTLBuffer,
        output: any MTLBuffer,
        originalWidth: Int,
        originalHeight: Int,
        llHeight: Int,
        tileOriginX: Int = 0,
        tileOriginY: Int = 0
    ) async throws {
        // **v8.3 fix**: see `inverse2DInt32MultiLevelFused`.
        let halfHH = originalHeight - llHeight

        // v7.1.0 H2.2 — select even-vs-odd kernel based on band
        // canvas origin parity per pass. Even origin (the historical
        // default) keeps the existing kernels. Odd origin selects
        // the parity-aware kernel from PR #346 (ISO 15444-1 Annex
        // F.4.1.1 — different boundary mirror, flipped interleave).
        let hOddOrigin = (tileOriginX & 1) == 1
        let vOddOrigin = (tileOriginY & 1) == 1

        // v10.5 Phase 2-3-fused: single-kernel H+V dispatch. Takes
        // precedence over the tiled pair when both are opt-in.
        // Available only for the even-origin path (no canvas-origin
        // parity branch) AND when this per-level pixel count is at
        // or above `inverse53IntFusedPixelThreshold` (12 MP default
        // — the boundary the variance bench established for the
        // fused-vs-tiled crossover; below threshold, the tiled pair
        // is at least as fast).
        let levelPixelCount = originalWidth * originalHeight
        let useFused = Self.inverse53IntFusedEnabled
            && !hOddOrigin && !vOddOrigin
            && levelPixelCount >= Self.inverse53IntFusedPixelThreshold
        if useFused {
            try await encodeInverse2DInt32_Fused(
                into: cb,
                ll: ll, lh: lh, hl: hl, hh: hh,
                output: output,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                llHeight: llHeight, halfHH: halfHH)
            return
        }

        // v10.3 Phase 2-2-tiled: threadgroup-memory tiled kernels.
        // Takes precedence over 2D-layout when both are set. Available
        // only for even-origin path.
        let useTiled = Self.inverse53IntTiledEnabled && !hOddOrigin && !vOddOrigin
        if useTiled {
            try await encodeInverse2DInt32_Tiled(
                into: cb,
                ll: ll, lh: lh, hl: hl, hh: hh,
                colLow: colLow, colHigh: colHigh, output: output,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                llHeight: llHeight, halfHH: halfHH)
            return
        }

        // v10.3 Phase 2-1: 2D-layout kernels available only for the
        // even-origin (production-default) path; odd-origin keeps the
        // parity-aware scalar kernels unchanged.
        let use2D = Self.inverse53Int2DLayoutEnabled && !hOddOrigin && !vOddOrigin

        if use2D {
            try await encodeInverse2DInt32_2DLayout(
                into: cb,
                ll: ll, lh: lh, hl: hl, hh: hh,
                colLow: colLow, colHigh: colHigh, output: output,
                originalWidth: originalWidth,
                originalHeight: originalHeight,
                llHeight: llHeight, halfHH: halfHH)
            return
        }

        let hPipeline = try await shaderLibrary.computePipeline(
            for: hOddOrigin ? .dwtInverse53HorizontalIntOdd
                            : .dwtInverse53HorizontalInt)
        let vPipeline = try await shaderLibrary.computePipeline(
            for: vOddOrigin ? .dwtInverse53VerticalIntOdd
                            : .dwtInverse53VerticalInt)

        // Pass 1: horizontal inverse. Two dispatches (LL+HL → colLow,
        // LH+HH → colHigh) into one encoder.
        guard let enc1 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create horizontal compute encoder")
        }
        enc1.setComputePipelineState(hPipeline)
        var widthVal = UInt32(originalWidth)

        enc1.setBuffer(ll, offset: 0, index: 0)
        enc1.setBuffer(hl, offset: 0, index: 1)
        enc1.setBuffer(colLow, offset: 0, index: 2)
        var llHVal = UInt32(llHeight)
        enc1.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc1.setBytes(&llHVal, length: MemoryLayout<UInt32>.stride, index: 4)
        enc1.dispatchThreads(
            MTLSize(width: 1, height: llHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: min(llHeight, 64), depth: 1))

        if halfHH > 0 {
            enc1.setBuffer(lh, offset: 0, index: 0)
            enc1.setBuffer(hh, offset: 0, index: 1)
            enc1.setBuffer(colHigh, offset: 0, index: 2)
            var halfHHVal = UInt32(halfHH)
            enc1.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc1.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 4)
            enc1.dispatchThreads(
                MTLSize(width: 1, height: halfHH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: min(halfHH, 64), depth: 1))
        }
        enc1.endEncoding()

        // Pass 2: vertical inverse. Reads colLow + colHigh, writes
        // output. New encoder ⇒ implicit memory barrier from pass 1.
        guard let enc2 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create vertical compute encoder")
        }
        enc2.setComputePipelineState(vPipeline)
        enc2.setBuffer(colLow, offset: 0, index: 0)
        enc2.setBuffer(colHigh, offset: 0, index: 1)
        enc2.setBuffer(output, offset: 0, index: 2)
        var hVal = UInt32(originalHeight)
        enc2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc2.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)
        enc2.dispatchThreads(
            MTLSize(width: originalWidth, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(originalWidth, 64), height: 1, depth: 1))
        enc2.endEncoding()
    }

    /// v10.3 Phase 2-1: 2D-thread-layout dispatch of the inverse 5/3
    /// integer kernels. Splits each pass into two encoder dispatches
    /// (step 1: undo update; step 2: undo predict) to expose massive
    /// per-sample parallelism. Bit-exact equivalent of the scalar path.
    private func encodeInverse2DInt32_2DLayout(
        into cb: any MTLCommandBuffer,
        ll: any MTLBuffer,
        lh: any MTLBuffer,
        hl: any MTLBuffer,
        hh: any MTLBuffer,
        colLow: any MTLBuffer,
        colHigh: any MTLBuffer,
        output: any MTLBuffer,
        originalWidth: Int,
        originalHeight: Int,
        llHeight: Int,
        halfHH: Int
    ) async throws {
        // ---------------- Horizontal pass ----------------
        // LL+HL → colLow (each row has `width` outputs, `llHeight` rows).
        // LH+HH → colHigh (each row has `width` outputs, `halfHH` rows).
        let hPipe1 = try await shaderLibrary.computePipeline(
            for: .dwtInverse53HorizontalInt2DStep1)
        let hPipe2 = try await shaderLibrary.computePipeline(
            for: .dwtInverse53HorizontalInt2DStep2)

        var widthVal = UInt32(originalWidth)
        let halfWidth = (originalWidth + 1) / 2
        let halfWidthH = originalWidth / 2

        // -- Step 1 for both band-pairs in one encoder --
        guard let encH1 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create H step1 encoder")
        }
        encH1.setComputePipelineState(hPipe1)
        // LL+HL → colLow (rows = llHeight)
        encH1.setBuffer(ll, offset: 0, index: 0)
        encH1.setBuffer(hl, offset: 0, index: 1)
        encH1.setBuffer(colLow, offset: 0, index: 2)
        var llHVal = UInt32(llHeight)
        encH1.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
        encH1.setBytes(&llHVal, length: MemoryLayout<UInt32>.stride, index: 4)
        let tgWidth1 = min(halfWidth, 32)
        let tgHeight1 = min(llHeight, 8)
        encH1.dispatchThreads(
            MTLSize(width: halfWidth, height: llHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tgWidth1, height: tgHeight1, depth: 1))

        if halfHH > 0 {
            // LH+HH → colHigh (rows = halfHH)
            encH1.setBuffer(lh, offset: 0, index: 0)
            encH1.setBuffer(hh, offset: 0, index: 1)
            encH1.setBuffer(colHigh, offset: 0, index: 2)
            var halfHHVal = UInt32(halfHH)
            encH1.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            encH1.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 4)
            let tgHeight1b = min(halfHH, 8)
            encH1.dispatchThreads(
                MTLSize(width: halfWidth, height: halfHH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgWidth1, height: tgHeight1b, depth: 1))
        }
        encH1.endEncoding()

        // -- Step 2 in a SEPARATE encoder (memory barrier) --
        if halfWidthH > 0 {
            guard let encH2 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError("Failed to create H step2 encoder")
            }
            encH2.setComputePipelineState(hPipe2)
            // LL+HL pair → colLow
            encH2.setBuffer(hl, offset: 0, index: 0)
            encH2.setBuffer(colLow, offset: 0, index: 1)
            encH2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 2)
            encH2.setBytes(&llHVal, length: MemoryLayout<UInt32>.stride, index: 3)
            let tgWidth2 = min(halfWidthH, 32)
            let tgHeight2 = min(llHeight, 8)
            encH2.dispatchThreads(
                MTLSize(width: halfWidthH, height: llHeight, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgWidth2, height: tgHeight2, depth: 1))

            if halfHH > 0 {
                encH2.setBuffer(hh, offset: 0, index: 0)
                encH2.setBuffer(colHigh, offset: 0, index: 1)
                var halfHHVal = UInt32(halfHH)
                encH2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 2)
                encH2.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 3)
                let tgHeight2b = min(halfHH, 8)
                encH2.dispatchThreads(
                    MTLSize(width: halfWidthH, height: halfHH, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: tgWidth2, height: tgHeight2b, depth: 1))
            }
            encH2.endEncoding()
        }

        // ---------------- Vertical pass ----------------
        // colLow + colHigh → output. width columns × height rows.
        let vPipe1 = try await shaderLibrary.computePipeline(
            for: .dwtInverse53VerticalInt2DStep1)
        let vPipe2 = try await shaderLibrary.computePipeline(
            for: .dwtInverse53VerticalInt2DStep2)

        var hVal = UInt32(originalHeight)
        let halfHeight = (originalHeight + 1) / 2
        let halfHeightH = originalHeight / 2

        guard let encV1 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create V step1 encoder")
        }
        encV1.setComputePipelineState(vPipe1)
        encV1.setBuffer(colLow, offset: 0, index: 0)
        encV1.setBuffer(colHigh, offset: 0, index: 1)
        encV1.setBuffer(output, offset: 0, index: 2)
        encV1.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
        encV1.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)
        let tgVw1 = min(originalWidth, 32)
        let tgVh1 = min(halfHeight, 8)
        encV1.dispatchThreads(
            MTLSize(width: originalWidth, height: halfHeight, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tgVw1, height: tgVh1, depth: 1))
        encV1.endEncoding()

        if halfHeightH > 0 {
            guard let encV2 = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError("Failed to create V step2 encoder")
            }
            encV2.setComputePipelineState(vPipe2)
            encV2.setBuffer(colHigh, offset: 0, index: 0)
            encV2.setBuffer(output, offset: 0, index: 1)
            encV2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 2)
            encV2.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 3)
            let tgVw2 = min(originalWidth, 32)
            let tgVh2 = min(halfHeightH, 8)
            encV2.dispatchThreads(
                MTLSize(width: originalWidth, height: halfHeightH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgVw2, height: tgVh2, depth: 1))
            encV2.endEncoding()
        }
    }

    /// v10.3 Phase 2-2-tiled — threadgroup-memory tiled dispatch.
    /// One encoder per pass (vs Phase 2-1's two); step 1 + step 2
    /// happen inside a single kernel via threadgroup memory.
    ///
    /// Tile geometry matches the kernel constants:
    /// - Horizontal: 32 cols × 8 rows per threadgroup → 64 output
    ///   samples per row × 8 rows = 512 output samples per tg.
    /// - Vertical: 32 cols × 8 row-pairs per threadgroup → 32 cols ×
    ///   16 output rows = 512 output samples per tg.
    private func encodeInverse2DInt32_Tiled(
        into cb: any MTLCommandBuffer,
        ll: any MTLBuffer,
        lh: any MTLBuffer,
        hl: any MTLBuffer,
        hh: any MTLBuffer,
        colLow: any MTLBuffer,
        colHigh: any MTLBuffer,
        output: any MTLBuffer,
        originalWidth: Int,
        originalHeight: Int,
        llHeight: Int,
        halfHH: Int
    ) async throws {
        let hKernel = try await shaderLibrary.computePipeline(for: .dwtInverse53HorizontalIntTiled)
        let vKernel = try await shaderLibrary.computePipeline(for: .dwtInverse53VerticalIntTiled)

        var widthVal = UInt32(originalWidth)
        let halfWidth = (originalWidth + 1) / 2

        // ----- Pass 1: horizontal inverse, LL + HL → colLow -----
        // Grid: halfWidth threads along x, llHeight along y.
        // Threadgroup: (32, 8). Each threadgroup writes 64 output
        // samples × 8 rows = 512 outputs.
        do {
            guard let enc = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError("Failed to create tiled h-enc LL+HL")
            }
            enc.setComputePipelineState(hKernel)
            enc.setBuffer(ll, offset: 0, index: 0)
            enc.setBuffer(hl, offset: 0, index: 1)
            enc.setBuffer(colLow, offset: 0, index: 2)
            var llHVal = UInt32(llHeight)
            enc.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc.setBytes(&llHVal, length: MemoryLayout<UInt32>.stride, index: 4)
            let tgX = 32
            let tgY = min(llHeight, 8)
            let gridX = max(halfWidth, 1)
            let gridY = max(llHeight, 1)
            enc.dispatchThreads(
                MTLSize(width: gridX, height: gridY, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgX, height: tgY, depth: 1))
            enc.endEncoding()
        }
        if halfHH > 0 {
            guard let enc = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError("Failed to create tiled h-enc LH+HH")
            }
            enc.setComputePipelineState(hKernel)
            enc.setBuffer(lh, offset: 0, index: 0)
            enc.setBuffer(hh, offset: 0, index: 1)
            enc.setBuffer(colHigh, offset: 0, index: 2)
            var halfHHVal = UInt32(halfHH)
            enc.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 4)
            let tgX = 32
            let tgY = min(halfHH, 8)
            enc.dispatchThreads(
                MTLSize(width: max(halfWidth, 1), height: halfHH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgX, height: tgY, depth: 1))
            enc.endEncoding()
        }

        // ----- Pass 2: vertical inverse, colLow + colHigh → output -----
        do {
            guard let enc = cb.makeComputeCommandEncoder() else {
                throw J2KError.internalError("Failed to create tiled v-enc")
            }
            enc.setComputePipelineState(vKernel)
            enc.setBuffer(colLow, offset: 0, index: 0)
            enc.setBuffer(colHigh, offset: 0, index: 1)
            enc.setBuffer(output, offset: 0, index: 2)
            var hVal = UInt32(originalHeight)
            enc.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
            enc.setBytes(&hVal, length: MemoryLayout<UInt32>.stride, index: 4)
            let halfHeight = (originalHeight + 1) / 2
            let tgX = min(originalWidth, 32)
            let tgY = min(halfHeight, 8)
            enc.dispatchThreads(
                MTLSize(width: originalWidth, height: max(halfHeight, 1), depth: 1),
                threadsPerThreadgroup: MTLSize(width: tgX, height: tgY, depth: 1))
            enc.endEncoding()
        }
    }

    /// v10.5 Phase 2-3-fused — single-kernel H+V inverse 5/3 Int.
    ///
    /// Collapses the v10.3 Phase 2-2-tiled pair into one dispatch,
    /// holding the H-pass output in threadgroup memory across the
    /// V pass. Eliminates the colLow/colHigh device round-trip;
    /// 3 kernel dispatches per level → 1.
    ///
    /// Threadgroup geometry: (32, 10). Each tg produces a 32-col ×
    /// 16-row output tile; rows lid.y == 0 and lid.y == 9 are halo
    /// rows that only contribute to the V-pass halo (their output
    /// is not written).
    private func encodeInverse2DInt32_Fused(
        into cb: any MTLCommandBuffer,
        ll: any MTLBuffer,
        lh: any MTLBuffer,
        hl: any MTLBuffer,
        hh: any MTLBuffer,
        output: any MTLBuffer,
        originalWidth: Int,
        originalHeight: Int,
        llHeight: Int,
        halfHH: Int
    ) async throws {
        let kernel = try await shaderLibrary.computePipeline(for: .dwtInverse53FusedIntTiled)
        guard let enc = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create fused IDWT encoder")
        }
        enc.setComputePipelineState(kernel)
        enc.setBuffer(ll, offset: 0, index: 0)
        enc.setBuffer(hl, offset: 0, index: 1)
        enc.setBuffer(lh, offset: 0, index: 2)
        enc.setBuffer(hh, offset: 0, index: 3)
        enc.setBuffer(output, offset: 0, index: 4)

        var widthVal = UInt32(originalWidth)
        var heightVal = UInt32(originalHeight)
        var llWVal = UInt32((originalWidth + 1) / 2)
        var llHVal = UInt32(llHeight)
        var halfHHVal = UInt32(halfHH)
        enc.setBytes(&widthVal,   length: MemoryLayout<UInt32>.stride, index: 5)
        enc.setBytes(&heightVal,  length: MemoryLayout<UInt32>.stride, index: 6)
        enc.setBytes(&llWVal,     length: MemoryLayout<UInt32>.stride, index: 7)
        enc.setBytes(&llHVal,     length: MemoryLayout<UInt32>.stride, index: 8)
        enc.setBytes(&halfHHVal,  length: MemoryLayout<UInt32>.stride, index: 9)

        // Grid: thread.x covers output cols (0..width). thread.y covers
        // input low-band rows with halo: 1 halo + 8 body + 1 halo per tg.
        //
        // Number of row-tiles = ⌈llHeight / 8⌉ (each body covers 8 input
        // low-band rows). gridY = numRowTiles × tgY.
        let tgX = 32
        let tgY = 10  // 8 body rows + 2 halo rows (lid.y == 0, lid.y == 9)
        let gridX = max(originalWidth, 1)
        let tgRowsBody = tgY - 2              // 8 body input rows per tile
        let numRowTiles = max(1, (llHeight + tgRowsBody - 1) / tgRowsBody)
        let gridY = numRowTiles * tgY
        enc.dispatchThreads(
            MTLSize(width: gridX, height: gridY, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tgX, height: tgY, depth: 1))
        enc.endEncoding()
    }

    private func readInt32Array(from buffer: MTLBuffer, elementCount: Int) -> [Int32] {
        guard elementCount > 0 else { return [] }
        let ptr = buffer.contents()
        J2KMetalUMACounters.incrementContents()
        J2KMetalUMACounters.incrementMemcpy()
        // v6-alpha5 phase 7 — skip the implicit zero-init in
        // `Array(repeating: 0, count:)` since the next operation
        // overwrites every element via `update(from:count:)`.
        // For DX 6.4 MP single-tile encode, the cumulative readback
        // across 5 levels × 4 bands ≈ 6.4 M Int32 = 25 MB; the
        // wasted bzero is ~1–2 ms of pure CPU time on Apple M2's
        // ~12 GB/s memory bandwidth.
        return [Int32](unsafeUninitializedCapacity: elementCount) { buf, count in
            buf.baseAddress!.update(
                from: ptr.assumingMemoryBound(to: Int32.self),
                count: elementCount)
            count = elementCount
        }
    }

    /// Bit-exact 1D inverse 5/3 reversible transform on `Int32` subbands with
    /// JPEG 2000 symmetric boundary extension. Matches `J2KDWT1D.inverseTransform53`
    /// in the J2KCodec module — duplicated here so J2KMetal stays free of any
    /// J2KCodec dependency.
    private func inverse1D53Int(lowpass: [Int32], highpass: [Int32]) -> [Int32] {
        let lpSize = lowpass.count
        let hpSize = highpass.count
        if hpSize == 0 { return lowpass }
        let n = lpSize + hpSize
        var even = lowpass

        // Step 1 (undo update). Symmetric: hp[-1] = hp[0], hp[hpSize] = hp[hpSize-1].
        for i in 0..<lpSize {
            let left  = (i > 0) ? highpass[i - 1] : highpass[0]
            let right = (i < hpSize) ? highpass[i] : highpass[hpSize - 1]
            even[i] = lowpass[i] &- ((left &+ right &+ 2) >> 2)
        }

        var odd = [Int32](repeating: 0, count: hpSize)
        // Step 2 (undo predict). Symmetric: even[lpSize] = even[lpSize-1].
        for i in 0..<hpSize {
            let left  = even[i]
            let right = (i + 1 < lpSize) ? even[i + 1] : even[lpSize - 1]
            odd[i] = highpass[i] &+ ((left &+ right) >> 1)
        }

        var result = [Int32](repeating: 0, count: n)
        for i in 0..<lpSize { result[2 * i] = even[i] }
        for i in 0..<hpSize { result[2 * i + 1] = odd[i] }
        return result
    }

    /// **v7.1.0 H2.2** — odd-origin parity-aware 1D inverse 5/3.
    /// Mirrors `J2KDWT1DOptimized.inverseTransform53OddOriginSymmetric`
    /// (J2KCodec) — replicated here because J2KMetal can't import
    /// J2KCodec. Three differences vs even-origin:
    ///   - Step 1 (undo update on L): right mirror only
    ///   - Step 2 (undo predict on H): three regions (left, interior,
    ///     right tail when n odd)
    ///   - Interleave is flipped: x[2i] = H, x[2i+1] = L
    private func inverse1D53IntOddOrigin(lowpass: [Int32], highpass: [Int32]) -> [Int32] {
        let lowCount = lowpass.count
        let highCount = highpass.count
        let n = lowCount + highCount
        if lowCount == 0 { return highpass }

        var L = lowpass
        var H = highpass

        // Step 1: undo update on L. L[i] -= ((H[i] + H[i+1] + 2) >> 2)
        // with right mirror H[i+1] → H[highCount - 1] when i+1 ≥ highCount.
        for i in 0..<lowCount {
            let left = H[i]
            let right = (i + 1 < highCount) ? H[i + 1] : H[highCount - 1]
            L[i] = L[i] &- ((left &+ right &+ 2) >> 2)
        }

        // Step 2: undo predict on H.
        if highCount > 0 {
            H[0] = H[0] &+ L[0]
        }
        let interiorEnd = min(highCount, lowCount)
        for i in 1..<interiorEnd {
            H[i] = H[i] &+ ((L[i - 1] &+ L[i]) >> 1)
        }
        if highCount > lowCount {
            H[lowCount] = H[lowCount] &+ L[lowCount - 1]
        }

        // Interleave (odd-origin): x[2i] = H[i], x[2i+1] = L[i]
        var result = [Int32](repeating: 0, count: n)
        for i in 0..<lowCount { result[2 * i + 1] = L[i] }
        for i in 0..<highCount { result[2 * i] = H[i] }
        return result
    }

    private func inverse2DCPUInt32(subbands: J2KMetalDWTSubbandsInt32) -> [Int32] {
        // Per JPEG 2000 spec (ISO 15444-1 Annex F): inverse 2D applies
        // horizontal pass first (per row: LL+HL → colLow, LH+HH → colHigh),
        // then vertical pass (per column: colLow+colHigh → final output).
        // Identical sequencing to `inverse2DGPUInt32` above and to the CPU
        // optimiser at `J2KDWT2DOptimizer.inverseTransform2DOptimized`.
        //
        // **v7.1.0 H2.2** — selects even-vs-odd 1D inverse per axis
        // based on band canvas origin parity.
        let width = subbands.originalWidth
        let height = subbands.originalHeight
        // Canvas-anchored band geometry — see `BandGeometry`. `halfHH`
        // / `halfWH` are `N − ll`, never `N / 2` (that mistake shipped
        // the v10.3.0–v10.9.0 multi-tile IDWT decode bug).
        let bands = BandGeometry(width: width, height: height,
                                 llW: subbands.llWidth, llH: subbands.llHeight)
        let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH
        let hOddOrigin = (subbands.tileOriginX & 1) == 1
        let vOddOrigin = (subbands.tileOriginY & 1) == 1

        @inline(__always)
        func inverse1DH(lowpass: [Int32], highpass: [Int32]) -> [Int32] {
            return hOddOrigin
                ? inverse1D53IntOddOrigin(lowpass: lowpass, highpass: highpass)
                : inverse1D53Int(lowpass: lowpass, highpass: highpass)
        }
        @inline(__always)
        func inverse1DV(lowpass: [Int32], highpass: [Int32]) -> [Int32] {
            return vOddOrigin
                ? inverse1D53IntOddOrigin(lowpass: lowpass, highpass: highpass)
                : inverse1D53Int(lowpass: lowpass, highpass: highpass)
        }

        // Step 1: horizontal pass
        var colLow  = [Int32](repeating: 0, count: width * llH)
        var colHigh = [Int32](repeating: 0, count: max(width, 1) * halfHH)

        for y in 0..<llH {
            let lpRow = Array(subbands.ll[(y * llW)..<(y * llW + llW)])
            let hpRow: [Int32]
            if subbands.hl.isEmpty || halfWH == 0 {
                hpRow = []
            } else {
                hpRow = Array(subbands.hl[(y * halfWH)..<(y * halfWH + halfWH)])
            }
            let merged = inverse1DH(lowpass: lpRow, highpass: hpRow)
            for x in 0..<min(width, merged.count) {
                colLow[y * width + x] = merged[x]
            }
        }

        if halfHH > 0 {
            for y in 0..<halfHH {
                let lpRow: [Int32]
                if subbands.lh.isEmpty {
                    lpRow = [Int32](repeating: 0, count: llW)
                } else {
                    lpRow = Array(subbands.lh[(y * llW)..<(y * llW + llW)])
                }
                let hpRow: [Int32]
                if subbands.hh.isEmpty || halfWH == 0 {
                    hpRow = []
                } else {
                    hpRow = Array(subbands.hh[(y * halfWH)..<(y * halfWH + halfWH)])
                }
                let merged = inverse1DH(lowpass: lpRow, highpass: hpRow)
                for x in 0..<min(width, merged.count) {
                    colHigh[y * width + x] = merged[x]
                }
            }
        }

        // Step 2: vertical pass — for each column x, merge colLow[*][x] (lowpass)
        // and colHigh[*][x] (highpass) into the final column.
        var result = [Int32](repeating: 0, count: width * height)
        for x in 0..<width {
            var lpCol = [Int32](repeating: 0, count: llH)
            for y in 0..<llH { lpCol[y] = colLow[y * width + x] }
            var hpCol: [Int32] = []
            if halfHH > 0 {
                hpCol = [Int32](repeating: 0, count: halfHH)
                for y in 0..<halfHH { hpCol[y] = colHigh[y * width + x] }
            }
            let merged = inverse1DV(lowpass: lpCol, highpass: hpCol)
            for y in 0..<min(height, merged.count) {
                result[y * width + x] = merged[y]
            }
        }

        return result
    }

    // MARK: - v6-alpha5 Phase 0 — forward 5/3 INT (GPU + CPU)

    /// Bit-exact 1D forward 5/3 reversible transform on Int32 with
    /// JPEG 2000 symmetric extension. Locally duplicated here so
    /// J2KMetal stays free of any J2KCodec dependency. Exact match
    /// for `AcceleratedDWT2D.forward53_1D(...)` in J2KAcceleratedEncoder.
    private func forward1D53Int(signal: [Int32]) -> (lowpass: [Int32], highpass: [Int32]) {
        let n = signal.count
        let lpSize = (n + 1) / 2
        let hpSize = n / 2
        var lp = [Int32](repeating: 0, count: lpSize)
        var hp = [Int32](repeating: 0, count: hpSize)
        // Predict: hp[i] = signal[2i+1] - ((signal[2i] + signal[2i+2]) >> 1)
        for i in 0..<hpSize {
            let left = signal[2 * i]
            let right = (2 * i + 2 < n) ? signal[2 * i + 2] : signal[2 * i]
            hp[i] = signal[2 * i + 1] &- ((left &+ right) >> 1)
        }
        // Update: lp[i] = signal[2i] + ((hp[i-1] + hp[i] + 2) >> 2)
        for i in 0..<lpSize {
            let left  = (i > 0) ? hp[i - 1] : (hpSize > 0 ? hp[0] : 0)
            let right = (i < hpSize) ? hp[i] : (hpSize > 0 ? hp[hpSize - 1] : 0)
            lp[i] = signal[2 * i] &+ ((left &+ right &+ 2) >> 2)
        }
        return (lp, hp)
    }

    /// CPU reference forward 2D 5/3 INT — vertical first, then
    /// horizontal, matching the encoder's spec order. Sequencing is
    /// the inverse (mirror) of `inverse2DCPUInt32`.
    private func forward2DCPUInt32(image: [Int32], width: Int, height: Int) -> J2KMetalDWTSubbandsInt32 {
        let bands = BandGeometry(width: width, height: height, originX: 0, originY: 0)
        let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH

        // Step 1 (vertical forward on columns): each column → low + high rows.
        var vLow  = [Int32](repeating: 0, count: width * llH)
        var vHigh = [Int32](repeating: 0, count: max(width, 1) * halfHH)
        for x in 0..<width {
            var col = [Int32](repeating: 0, count: height)
            for y in 0..<height { col[y] = image[y * width + x] }
            let (lp, hp) = forward1D53Int(signal: col)
            for y in 0..<llH    { vLow[y * width + x] = lp[y] }
            for y in 0..<halfHH { vHigh[y * width + x] = hp[y] }
        }

        // Step 2 (horizontal forward on rows of vLow / vHigh).
        var ll = [Int32](repeating: 0, count: llW * llH)
        var hl = [Int32](repeating: 0, count: max(halfWH, 1) * llH)
        var lh = [Int32](repeating: 0, count: llW * halfHH)
        var hh = [Int32](repeating: 0, count: max(halfWH, 1) * halfHH)
        for y in 0..<llH {
            let row = Array(vLow[(y * width)..<(y * width + width)])
            let (lp, hp) = forward1D53Int(signal: row)
            for x in 0..<llW    { ll[y * llW    + x] = lp[x] }
            for x in 0..<halfWH { hl[y * halfWH + x] = hp[x] }
        }
        for y in 0..<halfHH {
            let row = Array(vHigh[(y * width)..<(y * width + width)])
            let (lp, hp) = forward1D53Int(signal: row)
            for x in 0..<llW    { lh[y * llW    + x] = lp[x] }
            for x in 0..<halfWH { hh[y * halfWH + x] = hp[x] }
        }

        return J2KMetalDWTSubbandsInt32(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: llW, llHeight: llH,
            originalWidth: width, originalHeight: height)
    }

    /// GPU forward 2D 5/3 INT — dispatches the new
    /// `j2k_dwt_forward_53_*_int` kernels. Single command buffer,
    /// vertical then horizontal (mirror of `inverse2DGPUInt32`'s
    /// horizontal-then-vertical schedule).
    private func forward2DGPUInt32(
        image: [Int32], width: Int, height: Int
    ) async throws -> J2KMetalDWTSubbandsInt32 {
        try await ensureInitialized()

        let queue = try await metalDevice.commandQueue()
        let device = queue.device

        let bands = BandGeometry(width: width, height: height, originX: 0, originY: 0)
        let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH

        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1),
                options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let stride32 = MemoryLayout<Int32>.stride
        let inputBuffer  = try makeBuffer(size: image.count * stride32)
        let vLowBuffer   = try makeBuffer(size: width * llH * stride32)
        let vHighBuffer  = try makeBuffer(size: max(width * halfHH, 1) * stride32)
        let llBuffer     = try makeBuffer(size: llW * llH * stride32)
        let hlBuffer     = try makeBuffer(size: max(halfWH * llH, 1) * stride32)
        let lhBuffer     = try makeBuffer(size: max(llW * halfHH, 1) * stride32)
        let hhBuffer     = try makeBuffer(size: max(halfWH * halfHH, 1) * stride32)

        image.withUnsafeBytes { src in
            inputBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        let vPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53VerticalInt)
        let hPipeline = try await shaderLibrary.computePipeline(
            for: .dwtForward53HorizontalInt)

        // Pass 1: vertical forward — input → vLow + vHigh.
        guard let enc1 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create vertical compute encoder")
        }
        enc1.setComputePipelineState(vPipeline)
        enc1.setBuffer(inputBuffer, offset: 0, index: 0)
        enc1.setBuffer(vLowBuffer,  offset: 0, index: 1)
        enc1.setBuffer(vHighBuffer, offset: 0, index: 2)
        var widthVal  = UInt32(width)
        var heightVal = UInt32(height)
        enc1.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
        enc1.setBytes(&heightVal, length: MemoryLayout<UInt32>.stride, index: 4)
        enc1.dispatchThreads(
            MTLSize(width: width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(width, 64), height: 1, depth: 1))
        enc1.endEncoding()

        // Pass 2: horizontal forward — vLow rows → LL + HL,
        // vHigh rows → LH + HH. New encoder ⇒ implicit memory barrier.
        guard let enc2 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create horizontal compute encoder")
        }
        enc2.setComputePipelineState(hPipeline)

        // 2a: vLow rows → LL (low cols) + HL (high cols).
        enc2.setBuffer(vLowBuffer, offset: 0, index: 0)
        enc2.setBuffer(llBuffer,   offset: 0, index: 1)
        enc2.setBuffer(hlBuffer,   offset: 0, index: 2)
        var llHVal = UInt32(llH)
        enc2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc2.setBytes(&llHVal,   length: MemoryLayout<UInt32>.stride, index: 4)
        enc2.dispatchThreads(
            MTLSize(width: 1, height: llH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: min(llH, 64), depth: 1))

        // 2b: vHigh rows → LH (low cols) + HH (high cols).
        if halfHH > 0 {
            enc2.setBuffer(vHighBuffer, offset: 0, index: 0)
            enc2.setBuffer(lhBuffer,    offset: 0, index: 1)
            enc2.setBuffer(hhBuffer,    offset: 0, index: 2)
            var halfHHVal = UInt32(halfHH)
            enc2.setBytes(&widthVal,    length: MemoryLayout<UInt32>.stride, index: 3)
            enc2.setBytes(&halfHHVal,   length: MemoryLayout<UInt32>.stride, index: 4)
            enc2.dispatchThreads(
                MTLSize(width: 1, height: halfHH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: min(halfHH, 64), depth: 1))
        }
        enc2.endEncoding()

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Forward 5/3 INT GPU dispatch failed: \(cb.error?.localizedDescription ?? "(no description)")")
        }

        let ll = readInt32Array(from: llBuffer, elementCount: llW * llH)
        let hl = readInt32Array(from: hlBuffer, elementCount: halfWH * llH)
        let lh = readInt32Array(from: lhBuffer, elementCount: llW * halfHH)
        let hh = readInt32Array(from: hhBuffer, elementCount: halfWH * halfHH)

        return J2KMetalDWTSubbandsInt32(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: llW, llHeight: llH,
            originalWidth: width, originalHeight: height)
    }

    // MARK: - v6-alpha5 Phase 4 — parity-aware forward 5/3 INT

    /// Bit-exact 1D forward 5/3 with `uOrigin` for odd-origin parity.
    /// Mirrors the CPU `forward53_1D(...uOrigin:workspace:)` reference.
    private func forward1D53IntOddOrigin(signal: [Int32]) -> (lowpass: [Int32], highpass: [Int32]) {
        let n = signal.count
        let lowCount  = n / 2          // floor(n/2) — swap vs even-origin
        let highCount = n - lowCount   // ceil(n/2)
        var lp = [Int32](repeating: 0, count: lowCount)
        var hp = [Int32](repeating: 0, count: highCount)

        // Gather: L from local-odd, H from local-even.
        for i in 0..<lowCount  { lp[i] = signal[i &* 2 &+ 1] }
        for i in 0..<highCount { hp[i] = signal[i &* 2] }

        // Predict: H[0] left mirror, interior, H[lowCount] right mirror (n odd).
        if highCount > 0 {
            hp[0] = hp[0] &- lp[0]
        }
        let predictInteriorEnd = min(highCount, lowCount)
        for i in 1..<predictInteriorEnd {
            hp[i] = hp[i] &- ((lp[i &- 1] &+ lp[i]) >> 1)
        }
        if highCount > lowCount {
            hp[lowCount] = hp[lowCount] &- lp[lowCount - 1]
        }

        // Update: no left mirror, right mirror at i+1 >= highCount.
        for i in 0..<lowCount {
            let leftH  = hp[i]
            let rightH = (i &+ 1 < highCount) ? hp[i &+ 1] : hp[highCount &- 1]
            lp[i] = lp[i] &+ ((leftH &+ rightH &+ 2) >> 2)
        }
        return (lp, hp)
    }

    /// CPU reference parity-aware forward 2D 5/3 INT — vertical first
    /// then horizontal, picking the even/odd 1D variant per axis.
    private func forward2DCPUInt32WithOrigin(
        image: [Int32], width: Int, height: Int, uX: Int, uY: Int
    ) -> J2KMetalDWTSubbandsInt32 {
        // Both even → existing fast path. Bit-identical.
        if (uX & 1) == 0 && (uY & 1) == 0 {
            return forward2DCPUInt32(image: image, width: width, height: height)
        }

        let bands = BandGeometry(width: width, height: height, originX: uX, originY: uY)
        let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH

        // Step 1 (vertical forward) — pick parity per uY.
        let yOdd = (uY & 1) == 1
        var vLow  = [Int32](repeating: 0, count: width * llH)
        var vHigh = [Int32](repeating: 0, count: max(width, 1) * halfHH)
        for x in 0..<width {
            var col = [Int32](repeating: 0, count: height)
            for y in 0..<height { col[y] = image[y * width + x] }
            let (lp, hp): ([Int32], [Int32]) = yOdd
                ? forward1D53IntOddOrigin(signal: col)
                : forward1D53Int(signal: col)
            for y in 0..<llH    { vLow[y * width + x]  = lp[y] }
            for y in 0..<halfHH { vHigh[y * width + x] = hp[y] }
        }

        // Step 2 (horizontal forward) — pick parity per uX.
        let xOdd = (uX & 1) == 1
        var ll = [Int32](repeating: 0, count: llW * llH)
        var hl = [Int32](repeating: 0, count: max(halfWH, 1) * llH)
        var lh = [Int32](repeating: 0, count: llW * halfHH)
        var hh = [Int32](repeating: 0, count: max(halfWH, 1) * halfHH)
        for y in 0..<llH {
            let row = Array(vLow[(y * width)..<(y * width + width)])
            let (lp, hp): ([Int32], [Int32]) = xOdd
                ? forward1D53IntOddOrigin(signal: row)
                : forward1D53Int(signal: row)
            for x in 0..<llW    { ll[y * llW    + x] = lp[x] }
            for x in 0..<halfWH { hl[y * halfWH + x] = hp[x] }
        }
        for y in 0..<halfHH {
            let row = Array(vHigh[(y * width)..<(y * width + width)])
            let (lp, hp): ([Int32], [Int32]) = xOdd
                ? forward1D53IntOddOrigin(signal: row)
                : forward1D53Int(signal: row)
            for x in 0..<llW    { lh[y * llW    + x] = lp[x] }
            for x in 0..<halfWH { hh[y * halfWH + x] = hp[x] }
        }

        return J2KMetalDWTSubbandsInt32(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: llW, llHeight: llH,
            originalWidth: width, originalHeight: height)
    }

    /// GPU parity-aware forward 2D 5/3 INT. Picks even or odd kernel
    /// per axis, sizes intermediate buffers per parity-aware band
    /// counts.
    private func forward2DGPUInt32WithOrigin(
        image: [Int32], width: Int, height: Int, uX: Int, uY: Int
    ) async throws -> J2KMetalDWTSubbandsInt32 {
        // Both even → existing fast path. Bit-identical.
        if (uX & 1) == 0 && (uY & 1) == 0 {
            return try await forward2DGPUInt32(image: image, width: width, height: height)
        }

        try await ensureInitialized()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        let stride32 = MemoryLayout<Int32>.stride

        let bands = BandGeometry(width: width, height: height, originX: uX, originY: uY)
        let llW = bands.llW, llH = bands.llH, halfWH = bands.halfWH, halfHH = bands.halfHH

        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1), options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let inputBuffer = try makeBuffer(size: image.count * stride32)
        let vLowBuffer  = try makeBuffer(size: width * llH * stride32)
        let vHighBuffer = try makeBuffer(size: max(width * halfHH, 1) * stride32)
        let llBuffer    = try makeBuffer(size: llW * llH * stride32)
        let hlBuffer    = try makeBuffer(size: max(halfWH * llH, 1) * stride32)
        let lhBuffer    = try makeBuffer(size: max(llW * halfHH, 1) * stride32)
        let hhBuffer    = try makeBuffer(size: max(halfWH * halfHH, 1) * stride32)

        image.withUnsafeBytes { src in
            inputBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create command buffer")
        }

        let yOdd = (uY & 1) == 1
        let xOdd = (uX & 1) == 1
        let vPipeline = try await shaderLibrary.computePipeline(
            for: yOdd ? .dwtForward53VerticalIntOdd : .dwtForward53VerticalInt)
        let hPipeline = try await shaderLibrary.computePipeline(
            for: xOdd ? .dwtForward53HorizontalIntOdd : .dwtForward53HorizontalInt)

        // Pass 1: vertical forward.
        guard let enc1 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create vertical compute encoder")
        }
        enc1.setComputePipelineState(vPipeline)
        enc1.setBuffer(inputBuffer, offset: 0, index: 0)
        enc1.setBuffer(vLowBuffer,  offset: 0, index: 1)
        enc1.setBuffer(vHighBuffer, offset: 0, index: 2)
        var widthVal  = UInt32(width)
        var heightVal = UInt32(height)
        enc1.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
        enc1.setBytes(&heightVal, length: MemoryLayout<UInt32>.stride, index: 4)
        enc1.dispatchThreads(
            MTLSize(width: width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(width, 64), height: 1, depth: 1))
        enc1.endEncoding()

        // Pass 2: horizontal forward — vLow → LL + HL, vHigh → LH + HH.
        guard let enc2 = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create horizontal compute encoder")
        }
        enc2.setComputePipelineState(hPipeline)
        enc2.setBuffer(vLowBuffer, offset: 0, index: 0)
        enc2.setBuffer(llBuffer,   offset: 0, index: 1)
        enc2.setBuffer(hlBuffer,   offset: 0, index: 2)
        var llHVal = UInt32(llH)
        enc2.setBytes(&widthVal, length: MemoryLayout<UInt32>.stride, index: 3)
        enc2.setBytes(&llHVal,   length: MemoryLayout<UInt32>.stride, index: 4)
        enc2.dispatchThreads(
            MTLSize(width: 1, height: llH, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: min(llH, 64), depth: 1))

        if halfHH > 0 {
            enc2.setBuffer(vHighBuffer, offset: 0, index: 0)
            enc2.setBuffer(lhBuffer,    offset: 0, index: 1)
            enc2.setBuffer(hhBuffer,    offset: 0, index: 2)
            var halfHHVal = UInt32(halfHH)
            enc2.setBytes(&widthVal,  length: MemoryLayout<UInt32>.stride, index: 3)
            enc2.setBytes(&halfHHVal, length: MemoryLayout<UInt32>.stride, index: 4)
            enc2.dispatchThreads(
                MTLSize(width: 1, height: halfHH, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: min(halfHH, 64), depth: 1))
        }
        enc2.endEncoding()

        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "Forward 5/3 INT GPU (parity-aware) dispatch failed: \(cb.error?.localizedDescription ?? "(no description)")")
        }

        let ll = readInt32Array(from: llBuffer, elementCount: llW * llH)
        let hl = readInt32Array(from: hlBuffer, elementCount: halfWH * llH)
        let lh = readInt32Array(from: lhBuffer, elementCount: llW * halfHH)
        let hh = readInt32Array(from: hhBuffer, elementCount: halfWH * halfHH)

        return J2KMetalDWTSubbandsInt32(
            ll: ll, lh: lh, hl: hl, hh: hh,
            llWidth: llW, llHeight: llH,
            originalWidth: width, originalHeight: height)
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

    private func inverse2DGPUInt32(
        subbands: J2KMetalDWTSubbandsInt32
    ) async throws -> [Int32] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
