//
// J2KMetalShaderLibrary.swift
// J2KSwift
//
// J2KMetalShaderLibrary.swift
// J2KSwift
//
// Metal shader compilation, loading, and pipeline management.
//

import Foundation
import J2KCore

#if canImport(Metal)
import Metal
#endif

// MARK: - Shader Function Name

/// Well-known shader function names for JPEG 2000 GPU operations.
///
/// These constants identify the Metal compute kernel functions used
/// for various JPEG 2000 processing stages.
public enum J2KMetalShaderFunction: String, Sendable, CaseIterable {
    /// Forward 5/3 reversible wavelet transform (horizontal).
    case dwtForward53Horizontal = "j2k_dwt_forward_53_horizontal"
    /// Forward 5/3 reversible wavelet transform (vertical).
    case dwtForward53Vertical = "j2k_dwt_forward_53_vertical"
    /// Forward 5/3 reversible wavelet transform (horizontal, integer / bit-exact).
    /// Lossless-only pivot — phase 0. Mirrors the existing inverse-INT kernel
    /// and produces bit-exact output against the CPU `forward53_1D` reference.
    case dwtForward53HorizontalInt = "j2k_dwt_forward_53_horizontal_int"
    /// Forward 5/3 reversible wavelet transform (vertical, integer / bit-exact).
    case dwtForward53VerticalInt = "j2k_dwt_forward_53_vertical_int"
    /// Forward 5/3 reversible wavelet transform (horizontal, integer / odd origin).
    /// v6-alpha5 phase 4 — parity-aware variant for tile-component image-coord
    /// origin parity == 1 in this axis. Bit-exact match for the CPU reference
    /// `forward53_1D(...uOrigin: <odd>)`.
    case dwtForward53HorizontalIntOdd = "j2k_dwt_forward_53_horizontal_int_odd"
    /// Forward 5/3 reversible wavelet transform (vertical, integer / odd origin).
    case dwtForward53VerticalIntOdd = "j2k_dwt_forward_53_vertical_int_odd"
    /// Inverse 5/3 reversible wavelet transform (horizontal).
    case dwtInverse53Horizontal = "j2k_dwt_inverse_53_horizontal"
    /// Inverse 5/3 reversible wavelet transform (vertical).
    case dwtInverse53Vertical = "j2k_dwt_inverse_53_vertical"
    /// Inverse 5/3 reversible wavelet transform (horizontal, integer / bit-exact).
    case dwtInverse53HorizontalInt = "j2k_dwt_inverse_53_horizontal_int"
    /// Inverse 5/3 reversible wavelet transform (vertical, integer / bit-exact).
    case dwtInverse53VerticalInt = "j2k_dwt_inverse_53_vertical_int"
    /// Forward 9/7 irreversible wavelet transform (horizontal).
    case dwtForward97Horizontal = "j2k_dwt_forward_97_horizontal"
    /// Forward 9/7 irreversible wavelet transform (vertical).
    case dwtForward97Vertical = "j2k_dwt_forward_97_vertical"
    /// Inverse 9/7 irreversible wavelet transform (horizontal).
    case dwtInverse97Horizontal = "j2k_dwt_inverse_97_horizontal"
    /// Inverse 9/7 irreversible wavelet transform (vertical).
    case dwtInverse97Vertical = "j2k_dwt_inverse_97_vertical"
    /// Forward ICT colour transform (RGB → YCbCr).
    case ictForward = "j2k_ict_forward"
    /// Inverse ICT colour transform (YCbCr → RGB).
    case ictInverse = "j2k_ict_inverse"
    /// Forward RCT colour transform (reversible).
    case rctForward = "j2k_rct_forward"
    /// Inverse RCT colour transform (reversible).
    case rctInverse = "j2k_rct_inverse"
    /// General N×N matrix-vector multiplication for MCT.
    case mctMatrixMultiply = "j2k_mct_matrix_multiply"
    /// Quantization (scalar deadzone).
    case quantize = "j2k_quantize"
    /// Dequantization (scalar deadzone).
    case dequantize = "j2k_dequantize"
    /// Forward arbitrary wavelet transform (horizontal) using generic convolution.
    case dwtForwardArbitraryHorizontal = "j2k_dwt_forward_arbitrary_horizontal"
    /// Inverse arbitrary wavelet transform (horizontal) using generic convolution.
    case dwtInverseArbitraryHorizontal = "j2k_dwt_inverse_arbitrary_horizontal"
    /// Forward arbitrary wavelet transform (vertical) using generic convolution.
    case dwtForwardArbitraryVertical = "j2k_dwt_forward_arbitrary_vertical"
    /// Inverse arbitrary wavelet transform (vertical) using generic convolution.
    case dwtInverseArbitraryVertical = "j2k_dwt_inverse_arbitrary_vertical"
    /// Forward lifting scheme DWT (horizontal) with configurable lifting steps.
    case dwtForwardLiftingHorizontal = "j2k_dwt_forward_lifting_horizontal"
    /// Inverse lifting scheme DWT (horizontal) with configurable lifting steps.
    case dwtInverseLiftingHorizontal = "j2k_dwt_inverse_lifting_horizontal"
    /// Forward lifting scheme DWT (vertical) with configurable lifting steps.
    case dwtForwardLiftingVertical = "j2k_dwt_forward_lifting_vertical"
    /// Inverse lifting scheme DWT (vertical) with configurable lifting steps.
    case dwtInverseLiftingVertical = "j2k_dwt_inverse_lifting_vertical"
    /// Parametric non-linear transform (gamma, log, exp).
    case nltParametric = "j2k_nlt_parametric"
    /// LUT-based non-linear transform.
    case nltLUT = "j2k_nlt_lut"
    /// Optimised 3×3 MCT matrix multiply.
    case mctMatrixMultiply3x3 = "j2k_mct_matrix_multiply_3x3"
    /// Optimised 4×4 MCT matrix multiply.
    case mctMatrixMultiply4x4 = "j2k_mct_matrix_multiply_4x4"
    /// Fused colour + MCT transform.
    case colorMCTFused = "j2k_color_mct_fused"
    /// Perceptual Quantizer (SMPTE ST 2084).
    case nltPQ = "j2k_nlt_pq"
    /// Hybrid Log-Gamma (ITU-R BT.2100).
    case nltHLG = "j2k_nlt_hlg"

    // MARK: - ROI Shaders
    /// Generate ROI mask from rectangular region.
    case roiMaskGenerate = "j2k_roi_mask_generate"
    /// Apply MaxShift coefficient scaling for ROI.
    case roiCoefficientScale = "j2k_roi_coefficient_scale"
    /// Blend multiple ROI masks with priority.
    case roiMaskBlend = "j2k_roi_mask_blend"
    /// Apply feathering/smooth transitions to ROI boundaries.
    case roiFeathering = "j2k_roi_feathering"
    /// Map spatial ROI to wavelet domain coefficients.
    case roiWaveletMapping = "j2k_roi_wavelet_mapping"

    // MARK: - Quantization Shaders
    /// Scalar quantization with uniform step size.
    case quantizeScalar = "j2k_quantize_scalar"
    /// Dead-zone quantization with enlarged zero bin.
    case quantizeDeadzone = "j2k_quantize_deadzone"
    /// Dequantization (scalar mode).
    case dequantizeScalar = "j2k_dequantize_scalar"
    /// Dequantization (dead-zone mode).
    case dequantizeDeadzone = "j2k_dequantize_deadzone"
    /// Apply visual frequency weighting to quantization step sizes.
    case quantizeVisualWeighting = "j2k_quantize_visual_weighting"
    /// Perceptual quantization based on quality metrics.
    case quantizePerceptual = "j2k_quantize_perceptual"
    /// Parallel trellis state evaluation for TCQ.
    case quantizeTrellisEvaluate = "j2k_quantize_trellis_evaluate"
    /// Compute distortion metrics for R-D optimisation.
    case quantizeDistortionMetric = "j2k_quantize_distortion_metric"

    // MARK: - HTJ2K Decode Prototype Shaders
    /// Dispatch-cost probe — copies per-codeblock input to output and
    /// touches each byte once. Used to measure the fixed Metal launch
    /// overhead vs CPU work for a 1-thread-per-codeblock layout.
    /// Not a real decoder; first-light prototype only.
    case htDispatchProbe = "j2k_ht_dispatch_probe"
    /// Symmetric encode-side dispatch-cost probe (v6-alpha6 phase 0.5).
    /// Models the read+write traffic shape of an eventual GPU HT
    /// forward entropy encoder: walks per-block coefficients once
    /// (per-sample classification + payload extraction synthetic),
    /// writes ~half the sample count's worth of bytes. Empirical
    /// gate to v6-alpha6 phase 1 (approach B vs E pivot).
    case htForwardDispatchProbe = "j2k_ht_forward_dispatch_probe"
    /// Per-sample classifier (v6-alpha6 phase 1, approach B).
    /// Per-sample work mirrors `sampleInfo` in HTBlockEncoderConformant —
    /// emits a UInt64 tuple `(sig:1, eQ:7, payload:32)` per sample.
    /// CPU-side encoder consumes the tuple stream and emits the
    /// inherently-serial MagSgn / MEL / VLC byte streams.
    case htForwardClassifySamples = "j2k_ht_forward_classify_samples"
    /// Inclusive prefix-sum over a UInt32 array (v7.1.0 I1.1, Pass 2 of
    /// approach C). Single-threadgroup two-level scan: simd_prefix
    /// within each warp, then a top-level scan over per-warp totals.
    /// Handles N up to `threadgroup_size` (1024 on M2). Used to convert
    /// per-block byte counts → per-block byte offsets for the GPU
    /// byte-write pass.
    case prefixSumInclusiveUInt32 = "j2k_prefix_sum_inclusive_uint32"
    /// v7.1.0 I1.2 — Pass 3 MagSgn-only byte-write spike. One
    /// threadgroup per block; one thread does the inherently-serial
    /// bit-emit (with inline FF-stuffing) into a `device` byte buffer
    /// at a per-block offset. Bit-exact with `HTMagSgnEncoderConformant`.
    case htMagSgnEmitBlock = "j2k_ht_magsgn_emit_block"
    /// v7.1.0 I1.2b — Pass 3 MagSgn batched byte-write. Same per-
    /// block bit-emit as `htMagSgnEmitBlock` but dispatched as one
    /// threadgroup per block; the GPU schedules many block-emits
    /// concurrently. This is the production shape of Pass 3.
    case htMagSgnEmitBlocksBatched = "j2k_ht_magsgn_emit_blocks_batched"
    /// v7.1.0 I1.2c — Pass 3 MEL batched byte-write. MSB-first bit
    /// packing with the same FF-stuffing rule as MagSgn but **no
    /// terminate rollback or pad-drops-FF** semantics. One thread-
    /// group per block; same 4-byte-alignment requirement as I1.2b.
    /// Bit-exact with `HTForwardBitEmitterConformant`.
    case htMelEmitBlocksBatched = "j2k_ht_mel_emit_blocks_batched"
    /// v7.1.0 I1.2d — Pass 3 VLC batched byte-write (reverse bit-
    /// stream). LSB-first within each byte; the byte SEQUENCE is
    /// built in reverse and flipped in-place at the end. Reverse
    /// FF-stuffing on `> 0x8F` bytes with deferred-stuff release
    /// when the would-be stuff byte's low 7 bits != 0x7F. Bit-exact
    /// with `HTReverseBitEmitterConformant`.
    case htVlcEmitBlocksBatched = "j2k_ht_vlc_emit_blocks_batched"
    /// MagSgn forward bit reader — port of `HTMagSgnDecoderConformant.read`
    /// to MSL. Each thread decodes one codeblock's MagSgn stream given a
    /// per-sample widths array. Bit-exact with the CPU reference.
    case htMagsgnDecode = "j2k_ht_magsgn_decode"
    /// Full HT cleanup-pass decoder — combines MEL run-length + VLC
    /// table lookup + UVLC + MagSgn into one kernel. Bit-exact with
    /// `HTBlockDecoderConformant.decode`. Phase-2 prototype.
    case htCleanupDecode = "j2k_ht_cleanup_decode"
    /// Per-sample dequantisation: converts the HT cleanup kernel's
    /// UInt32 OpenJPH sign-magnitude output to the pipeline's Int32
    /// integer-magnitude convention. v5.6.0; intended to be chained
    /// in the same command buffer as `htCleanupDecode` so the
    /// CPU-side per-sample shift+sign loop in `J2KGPUHTDispatch`
    /// goes away.
    case htDequant = "j2k_ht_dequant"
    /// Subband scatter: takes the dequantised codeblock-output
    /// buffer and a per-block placement descriptor, writes each
    /// codeblock's Int32 samples into the right (x, y) position
    /// within a per-subband 2D output buffer. Replaces the CPU-side
    /// `getSubbandAsInt32` loop in J2KDecoderPipeline. v5.7.0
    /// foundation for HT cleanup → DWT command-buffer fusion.
    case subbandScatter = "j2k_subband_scatter"
    /// v5.26.0 Float scatter + HTJ2K conformant dequant. Mirror of
    /// `subbandScatter` for the 9/7 lossy fused-from-codeblocks
    /// path; reads Int32 codeblocks, applies dequantisation
    /// (`(coeff ± 0.5) * stepSize`), writes Float to per-subband 2D
    /// buffers. Only used when `useGPUHT && useConformant && 9/7`.
    case subbandScatterFloatDequant = "j2k_subband_scatter_float_dequant"
}

// MARK: - Shader Library Configuration

/// Configuration for shader library loading and caching.
public struct J2KMetalShaderLibraryConfiguration: Sendable {
    /// Whether to cache compiled pipeline states.
    public var enablePipelineCache: Bool

    /// Maximum number of cached pipeline states.
    public var maxCachedPipelines: Int

    /// Creates a new shader library configuration.
    ///
    /// - Parameters:
    ///   - enablePipelineCache: Whether to cache pipelines. Defaults to `true`.
    ///   - maxCachedPipelines: Maximum cached pipelines. Defaults to `32`.
    public init(
        enablePipelineCache: Bool = true,
        maxCachedPipelines: Int = 32
    ) {
        self.enablePipelineCache = enablePipelineCache
        self.maxCachedPipelines = maxCachedPipelines
    }

    /// Default shader library configuration.
    public static let `default` = J2KMetalShaderLibraryConfiguration()
}

// MARK: - Shader Library

/// Manages Metal shader compilation, loading, and compute pipeline creation.
///
/// `J2KMetalShaderLibrary` provides loading of Metal shader functions and
/// creation of compute pipeline states. Pipeline states are cached for
/// efficient reuse across operations.
///
/// ## Usage
///
/// ```swift
/// let library = J2KMetalShaderLibrary()
///
/// // Load shaders from source
/// try await library.loadShaders(device: metalDevice)
///
/// // Get a compute pipeline for a specific function
/// let pipeline = try await library.computePipeline(
///     for: .dwtForward97Horizontal
/// )
/// ```
///
/// ## Shader Loading
///
/// Shaders can be loaded from:
/// - Source code strings (runtime compilation)
/// - Pre-compiled Metal libraries (.metallib files)
/// - The default Metal library bundled with the app
public actor J2KMetalShaderLibrary {
    /// Whether Metal shader compilation is available on this platform.
    public static var isAvailable: Bool {
        #if canImport(Metal)
        return true
        #else
        return false
        #endif
    }

    /// The library configuration.
    public let configuration: J2KMetalShaderLibraryConfiguration

    #if canImport(Metal)
    /// The compiled Metal library.
    private var library: (any MTLLibrary)?

    /// Cached compute pipeline states keyed by function name.
    private var pipelineCache: [String: any MTLComputePipelineState] = [:]

    /// The device used for shader compilation.
    private var device: (any MTLDevice)?

    /// Cached HT-cleanup VLC tables. Tables are deterministic spec data
    /// (1024 UInt16 entries each), so we upload once and reuse the
    /// MTLBuffers across every cleanup-decode call.
    private var vlcTable0Buffer: (any MTLBuffer)?
    private var vlcTable1Buffer: (any MTLBuffer)?
    #endif

    /// Whether shaders have been loaded.
    private var isLoaded = false

    /// v5.15: which path produced the loaded MTLLibrary. Used by
    /// `J2KMetalLibraryLoadPathTests` to assert the bundled
    /// `default.metallib` is being picked up (and that we're not
    /// silently falling back to the source-compile path on
    /// production builds). `nil` until `loadShaders` returns.
    public enum LoadPath: String, Sendable {
        case metallib  // loaded the bundled default.metallib
        case sourceCompile  // fell back to compiling J2KMetalShaderSource.kernelSource
    }
    public private(set) var loadPath: LoadPath?

    /// Creates a new shader library with the given configuration.
    ///
    /// - Parameter configuration: The library configuration. Defaults to `.default`.
    public init(
        configuration: J2KMetalShaderLibraryConfiguration = .default
    ) {
        self.configuration = configuration
    }

    #if canImport(Metal)
    /// Loads Metal shaders from source code for the given device.
    ///
    /// Compiles the built-in JPEG 2000 shader source code into a Metal library.
    /// This method is safe to call multiple times; subsequent calls are no-ops.
    ///
    /// - Parameter device: The Metal device to compile shaders for.
    /// - Throws: ``J2KError/internalError(_:)`` if shader compilation fails.
    public func loadShaders(device: any MTLDevice) throws {
        guard !isLoaded else { return }

        // v5.6.0: prefer the SwiftPM-bundled `default.metallib`
        // (compiled from J2KShaders.metal at build time) — loading
        // it skips the ~50 ms MSL source-compile cost on every
        // process startup. Fall back to source-compiling the inline
        // string if the bundled library can't be loaded (e.g.
        // contexts where Bundle.module isn't available).
        if let compiledLibrary = try? device.makeDefaultLibrary(bundle: .module) {
            self.library = compiledLibrary
            self.device = device
            self.isLoaded = true
            self.loadPath = .metallib
            return
        }

        let source = J2KMetalShaderSource.kernelSource
        let options = MTLCompileOptions()
        options.fastMathEnabled = true

        do {
            let compiledLibrary = try device.makeLibrary(source: source, options: options)
            self.library = compiledLibrary
            self.device = device
            self.isLoaded = true
            self.loadPath = .sourceCompile
        } catch {
            throw J2KError.internalError("Metal shader compilation failed: \(error.localizedDescription)")
        }
    }

    /// Loads Metal shaders from a pre-compiled library file.
    ///
    /// - Parameters:
    ///   - device: The Metal device.
    ///   - url: The URL of the .metallib file.
    /// - Throws: ``J2KError/internalError(_:)`` if loading fails.
    public func loadCompiledLibrary(device: any MTLDevice, url: URL) throws {
        do {
            let compiledLibrary = try device.makeLibrary(URL: url)
            self.library = compiledLibrary
            self.device = device
            self.isLoaded = true
        } catch {
            throw J2KError.internalError("Failed to load Metal library: \(error.localizedDescription)")
        }
    }
    #endif

    /// Validates that shaders are loaded and ready for pipeline creation.
    ///
    /// - Throws: ``J2KError/internalError(_:)`` if shaders are not loaded.
    public func validateLoaded() throws {
        #if canImport(Metal)
        guard isLoaded, library != nil else {
            throw J2KError.internalError("Shaders not loaded. Call loadShaders() first.")
        }
        #else
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
        #endif
    }

    #if canImport(Metal)
    /// Returns a compute pipeline state for the specified shader function.
    ///
    /// Pipeline states are cached for reuse if caching is enabled.
    ///
    /// - Parameter function: The shader function to create a pipeline for.
    /// - Returns: A compute pipeline state.
    /// - Throws: ``J2KError/internalError(_:)`` if the pipeline cannot be created.
    public func computePipeline(
        for function: J2KMetalShaderFunction
    ) throws -> any MTLComputePipelineState {
        guard isLoaded, let library else {
            throw J2KError.internalError("Shaders not loaded. Call loadShaders() first.")
        }

        let functionName = function.rawValue

        // Check cache
        if configuration.enablePipelineCache,
           let cached = pipelineCache[functionName] {
            return cached
        }

        // Create pipeline
        guard let mtlFunction = library.makeFunction(name: functionName) else {
            throw J2KError.internalError(
                "Metal function '\(functionName)' not found in library"
            )
        }

        do {
            let pipeline = try device!.makeComputePipelineState(function: mtlFunction)

            // Cache the pipeline
            if configuration.enablePipelineCache {
                if pipelineCache.count >= configuration.maxCachedPipelines {
                    // Evict oldest entry
                    pipelineCache.removeValue(forKey: pipelineCache.keys.first!)
                }
                pipelineCache[functionName] = pipeline
            }

            return pipeline
        } catch {
            throw J2KError.internalError(
                "Failed to create compute pipeline for '\(functionName)': \(error.localizedDescription)"
            )
        }
    }
    #endif

    #if canImport(Metal)
    /// Returns lazily-uploaded VLC table buffers for the HT cleanup decoder.
    ///
    /// The two 1024-entry tables are deterministic spec data, identical
    /// across every call. The first invocation uploads them into Metal
    /// buffers; subsequent invocations return the cached buffers without
    /// re-allocating or re-copying.
    ///
    /// - Parameters:
    ///   - device: The Metal device to allocate buffers from on first call.
    ///   - vlc0: The 1024-entry VLC decoder table 0.
    ///   - vlc1: The 1024-entry VLC decoder table 1.
    /// - Returns: A tuple of (vlc0, vlc1) `MTLBuffer`s.
    /// - Throws: ``J2KError/internalError(_:)`` if buffer allocation fails.
    public func vlcTableBuffers(
        device: any MTLDevice,
        vlc0: [UInt16],
        vlc1: [UInt16]
    ) throws -> (vlc0: any MTLBuffer, vlc1: any MTLBuffer) {
        precondition(vlc0.count == 1024, "vlc0 must have 1024 entries")
        precondition(vlc1.count == 1024, "vlc1 must have 1024 entries")

        if let v0 = vlcTable0Buffer, let v1 = vlcTable1Buffer {
            return (v0, v1)
        }

        let byteCount = 1024 * MemoryLayout<UInt16>.stride
        guard let v0 = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let v1 = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
            throw J2KError.internalError("Failed to allocate VLC table buffers")
        }
        vlc0.withUnsafeBytes { src in
            v0.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        vlc1.withUnsafeBytes { src in
            v1.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        self.vlcTable0Buffer = v0
        self.vlcTable1Buffer = v1
        return (v0, v1)
    }
    #endif

    /// Returns the list of available shader function names in the loaded library.
    ///
    /// - Returns: Array of function names, or empty if no library is loaded.
    public func availableFunctions() -> [String] {
        #if canImport(Metal)
        return library?.functionNames ?? []
        #else
        return []
        #endif
    }

    /// Checks whether a specific shader function is available.
    ///
    /// - Parameter function: The shader function to check.
    /// - Returns: `true` if the function exists in the loaded library.
    public func hasFunction(_ function: J2KMetalShaderFunction) -> Bool {
        #if canImport(Metal)
        guard let library else { return false }
        return library.functionNames.contains(function.rawValue)
        #else
        return false
        #endif
    }

    /// Clears the pipeline state and VLC table caches.
    public func clearCache() {
        #if canImport(Metal)
        pipelineCache.removeAll()
        vlcTable0Buffer = nil
        vlcTable1Buffer = nil
        #endif
    }

    /// Returns the number of cached pipeline states.
    ///
    /// - Returns: The count of cached pipelines.
    public func cachedPipelineCount() -> Int {
        #if canImport(Metal)
        return pipelineCache.count
        #else
        return 0
        #endif
    }
}

// MARK: - Shader Source Code

/// Contains the Metal shader source code for JPEG 2000 operations.
///
/// These kernels implement the core compute operations that benefit from
/// GPU parallelism. Each kernel is designed for maximum occupancy and
/// minimal memory bandwidth usage.
enum J2KMetalShaderSource {
    /// The complete Metal shader source for JPEG 2000 operations.
    static let kernelSource: String = """
    #include <metal_stdlib>
    using namespace metal;

    // MARK: - Forward 9/7 Irreversible DWT (Horizontal)

    kernel void j2k_dwt_forward_97_horizontal(
        device const float* input [[buffer(0)]],
        device float* lowpass [[buffer(1)]],
        device float* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;
        uint halfWidthH = width / 2;

        // CDF 9/7 lifting coefficients
        const float alpha = -1.586134342f;
        const float beta  = -0.052980118f;
        const float gamma =  0.882911075f;
        const float delta =  0.443506852f;
        const float K     =  1.230174105f;

        uint idx = row * width;
        uint lBase = row * halfWidth;
        uint hBase = row * halfWidthH;

        // Step 1: Split into even and odd samples (no scaling yet)
        for (uint i = 0; i < halfWidth; i++) {
            lowpass[lBase + i] = input[idx + min(2 * i, width - 1)];
        }
        for (uint i = 0; i < halfWidthH; i++) {
            highpass[hBase + i] = input[idx + 2 * i + 1];
        }

        // Step 2: Predict 1 — d[i] += alpha * (s[i] + s[i+1])
        for (uint i = 0; i < halfWidthH; i++) {
            highpass[hBase + i] += alpha * (lowpass[lBase + i] + lowpass[lBase + min(i + 1, halfWidth - 1)]);
        }
        // Step 3: Update 1 — s[i] += beta * (d[i-1] + d[i])
        for (uint i = 0; i < halfWidth; i++) {
            float dLeft  = highpass[hBase + ((i > 0) ? (i - 1) : 0)];
            float dRight = highpass[hBase + min(i, halfWidthH - 1)];
            lowpass[lBase + i] += beta * (dLeft + dRight);
        }
        // Step 4: Predict 2 — d[i] += gamma * (s[i] + s[i+1])
        for (uint i = 0; i < halfWidthH; i++) {
            highpass[hBase + i] += gamma * (lowpass[lBase + i] + lowpass[lBase + min(i + 1, halfWidth - 1)]);
        }
        // Step 5: Update 2 — s[i] += delta * (d[i-1] + d[i])
        for (uint i = 0; i < halfWidth; i++) {
            float dLeft  = highpass[hBase + ((i > 0) ? (i - 1) : 0)];
            float dRight = highpass[hBase + min(i, halfWidthH - 1)];
            lowpass[lBase + i] += delta * (dLeft + dRight);
        }

        // Step 6: Scale (ISO/IEC 15444-1 Annex F.4.1.1)
        // v5.21.0 fix: lowpass /= K, highpass *= K (was inverted pre-v5.21).
        for (uint i = 0; i < halfWidth; i++) { lowpass[lBase + i] /= K; }
        for (uint i = 0; i < halfWidthH; i++) { highpass[hBase + i] *= K; }
    }

    // MARK: - Forward 9/7 Irreversible DWT (Vertical)

    kernel void j2k_dwt_forward_97_vertical(
        device const float* input [[buffer(0)]],
        device float* lowpass [[buffer(1)]],
        device float* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;
        uint halfHeightH = height / 2;

        const float alpha = -1.586134342f;
        const float beta  = -0.052980118f;
        const float gamma =  0.882911075f;
        const float delta =  0.443506852f;
        const float K     =  1.230174105f;

        // Step 1: Split into even and odd rows
        for (uint i = 0; i < halfHeight; i++) {
            lowpass[i * width + col] = input[min(2 * i, height - 1) * width + col];
        }
        for (uint i = 0; i < halfHeightH; i++) {
            highpass[i * width + col] = input[(2 * i + 1) * width + col];
        }

        // Step 2: Predict 1
        for (uint i = 0; i < halfHeightH; i++) {
            highpass[i * width + col] += alpha * (lowpass[i * width + col] + lowpass[min(i + 1, halfHeight - 1) * width + col]);
        }
        // Step 3: Update 1
        for (uint i = 0; i < halfHeight; i++) {
            float dTop = highpass[((i > 0) ? (i - 1) : 0) * width + col];
            float dBot = highpass[min(i, halfHeightH - 1) * width + col];
            lowpass[i * width + col] += beta * (dTop + dBot);
        }
        // Step 4: Predict 2
        for (uint i = 0; i < halfHeightH; i++) {
            highpass[i * width + col] += gamma * (lowpass[i * width + col] + lowpass[min(i + 1, halfHeight - 1) * width + col]);
        }
        // Step 5: Update 2
        for (uint i = 0; i < halfHeight; i++) {
            float dTop = highpass[((i > 0) ? (i - 1) : 0) * width + col];
            float dBot = highpass[min(i, halfHeightH - 1) * width + col];
            lowpass[i * width + col] += delta * (dTop + dBot);
        }

        // Step 6: Scale (ISO/IEC 15444-1 Annex F.4.1.1)
        // v5.21.0 fix: lowpass /= K, highpass *= K (was inverted pre-v5.21).
        for (uint i = 0; i < halfHeight; i++) { lowpass[i * width + col] /= K; }
        for (uint i = 0; i < halfHeightH; i++) { highpass[i * width + col] *= K; }
    }

    // MARK: - Inverse 9/7 Irreversible DWT (Horizontal)

    kernel void j2k_dwt_inverse_97_horizontal(
        device const float* lowpassIn [[buffer(0)]],
        device const float* highpassIn [[buffer(1)]],
        device float* output [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;
        uint halfWidthH = width / 2;

        const float alpha = -1.586134342f;
        const float beta  = -0.052980118f;
        const float gamma =  0.882911075f;
        const float delta =  0.443506852f;
        const float K     =  1.230174105f;

        uint lBase = row * halfWidth;
        uint hBase = row * halfWidthH;

        // Use output buffer as scratch for even/odd reconstruction.
        // Undo scaling — inverse of forward step 6 (which divides
        // lowpass by K and multiplies highpass by K per ISO/IEC
        // 15444-1 Annex F.4.1.1). v5.21.0 fix: pre-v5.21 the GPU
        // had both forward and inverse scaling inverted vs spec —
        // self-consistent but incompatible with CPU-encoded output.
        for (uint i = 0; i < halfWidth; i++) {
            output[row * width + 2 * i] = lowpassIn[lBase + i] * K;
        }
        for (uint i = 0; i < halfWidthH; i++) {
            output[row * width + 2 * i + 1] = highpassIn[hBase + i] / K;
        }

        // We need even/odd arrays for lifting; re-extract them from output
        // Use local-scope arrays via output reinterpretation
        // For correctness, work with even[] and odd[] in output positions
        // even = output[2*i], odd = output[2*i+1]

        // Undo update 2: s[i] -= delta * (d[i-1] + d[i])
        for (uint i = 0; i < halfWidth; i++) {
            float dLeft  = output[row * width + 2 * ((i > 0) ? (i - 1) : 0) + 1];
            float dRight = (i < halfWidthH) ? output[row * width + 2 * i + 1]
                           : output[row * width + 2 * max(int(halfWidthH) - 1, 0) + 1];
            output[row * width + 2 * i] -= delta * (dLeft + dRight);
        }
        // Undo predict 2: d[i] -= gamma * (s[i] + s[i+1])
        for (uint i = 0; i < halfWidthH; i++) {
            float sLeft  = output[row * width + 2 * i];
            float sRight = output[row * width + 2 * min(i + 1, halfWidth - 1)];
            output[row * width + 2 * i + 1] -= gamma * (sLeft + sRight);
        }
        // Undo update 1: s[i] -= beta * (d[i-1] + d[i])
        for (uint i = 0; i < halfWidth; i++) {
            float dLeft  = output[row * width + 2 * ((i > 0) ? (i - 1) : 0) + 1];
            float dRight = (i < halfWidthH) ? output[row * width + 2 * i + 1]
                           : output[row * width + 2 * max(int(halfWidthH) - 1, 0) + 1];
            output[row * width + 2 * i] -= beta * (dLeft + dRight);
        }
        // Undo predict 1: d[i] -= alpha * (s[i] + s[i+1])
        for (uint i = 0; i < halfWidthH; i++) {
            float sLeft  = output[row * width + 2 * i];
            float sRight = output[row * width + 2 * min(i + 1, halfWidth - 1)];
            output[row * width + 2 * i + 1] -= alpha * (sLeft + sRight);
        }
    }

    // MARK: - Inverse 9/7 Irreversible DWT (Vertical)

    kernel void j2k_dwt_inverse_97_vertical(
        device const float* lowpassIn [[buffer(0)]],
        device const float* highpassIn [[buffer(1)]],
        device float* output [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;
        uint halfHeightH = height / 2;

        const float alpha = -1.586134342f;
        const float beta  = -0.052980118f;
        const float gamma =  0.882911075f;
        const float delta =  0.443506852f;
        const float K     =  1.230174105f;

        // Undo scaling and interleave into output. v5.21.0 fix:
        // see horizontal-inverse comment above; pre-v5.21 had both
        // forward and inverse scaling inverted vs ISO/IEC 15444-1.
        for (uint i = 0; i < halfHeight; i++) {
            output[(2 * i) * width + col] = lowpassIn[i * width + col] * K;
        }
        for (uint i = 0; i < halfHeightH; i++) {
            output[(2 * i + 1) * width + col] = highpassIn[i * width + col] / K;
        }

        // Undo update 2
        for (uint i = 0; i < halfHeight; i++) {
            float dTop = output[(2 * ((i > 0) ? (i - 1) : 0) + 1) * width + col];
            float dBot = (i < halfHeightH) ? output[(2 * i + 1) * width + col]
                         : output[(2 * max(int(halfHeightH) - 1, 0) + 1) * width + col];
            output[(2 * i) * width + col] -= delta * (dTop + dBot);
        }
        // Undo predict 2
        for (uint i = 0; i < halfHeightH; i++) {
            float sTop = output[(2 * i) * width + col];
            float sBot = output[(2 * min(i + 1, halfHeight - 1)) * width + col];
            output[(2 * i + 1) * width + col] -= gamma * (sTop + sBot);
        }
        // Undo update 1
        for (uint i = 0; i < halfHeight; i++) {
            float dTop = output[(2 * ((i > 0) ? (i - 1) : 0) + 1) * width + col];
            float dBot = (i < halfHeightH) ? output[(2 * i + 1) * width + col]
                         : output[(2 * max(int(halfHeightH) - 1, 0) + 1) * width + col];
            output[(2 * i) * width + col] -= beta * (dTop + dBot);
        }
        // Undo predict 1
        for (uint i = 0; i < halfHeightH; i++) {
            float sTop = output[(2 * i) * width + col];
            float sBot = output[(2 * min(i + 1, halfHeight - 1)) * width + col];
            output[(2 * i + 1) * width + col] -= alpha * (sTop + sBot);
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Horizontal)

    kernel void j2k_dwt_forward_53_horizontal(
        device const float* input [[buffer(0)]],
        device float* lowpass [[buffer(1)]],
        device float* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;
        uint halfWidthH = width / 2;

        uint idx = row * width;
        uint lBase = row * halfWidth;
        uint hBase = row * halfWidthH;

        // Predict step: d[n] = x[2n+1] - (x[2n] + x[2n+2]) / 2
        for (uint i = 0; i < halfWidthH; i++) {
            float left = input[idx + 2 * i];
            float right = (2 * i + 2 < width) ? input[idx + 2 * i + 2] : input[idx + 2 * i];
            highpass[hBase + i] = input[idx + 2 * i + 1] - (left + right) / 2.0f;
        }

        // Update step: s[n] = x[2n] + (d[n-1] + d[n] + 2) / 4
        for (uint i = 0; i < halfWidth; i++) {
            float d_left = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
            float d_right = (i < halfWidthH) ? highpass[hBase + i] : highpass[hBase + max(int(halfWidthH) - 1, 0)];
            lowpass[lBase + i] = input[idx + 2 * i] + (d_left + d_right + 2.0f) / 4.0f;
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Vertical)

    kernel void j2k_dwt_forward_53_vertical(
        device const float* input [[buffer(0)]],
        device float* lowpass [[buffer(1)]],
        device float* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;
        uint halfHeightH = height / 2;

        // Predict step
        for (uint i = 0; i < halfHeightH; i++) {
            float top = input[(2 * i) * width + col];
            float bottom = (2 * i + 2 < height) ? input[(2 * i + 2) * width + col] : input[(2 * i) * width + col];
            highpass[i * width + col] = input[(2 * i + 1) * width + col] - (top + bottom) / 2.0f;
        }
        // Update step
        for (uint i = 0; i < halfHeight; i++) {
            float d_top = (i > 0) ? highpass[(i - 1) * width + col] : highpass[col];
            float d_bot = (i < halfHeightH) ? highpass[i * width + col] : highpass[max(int(halfHeightH) - 1, 0) * width + col];
            lowpass[i * width + col] = input[(2 * i) * width + col] + (d_top + d_bot + 2.0f) / 4.0f;
        }
    }

    // MARK: - Inverse 5/3 Reversible DWT (Horizontal)

    kernel void j2k_dwt_inverse_53_horizontal(
        device const float* lowpass [[buffer(0)]],
        device const float* highpass [[buffer(1)]],
        device float* output [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;
        uint halfWidthH = width / 2;

        uint lBase = row * halfWidth;
        uint hBase = row * halfWidthH;
        uint oBase = row * width;

        // Undo update: x[2n] = s[n] - (d[n-1] + d[n] + 2) / 4
        for (uint i = 0; i < halfWidth; i++) {
            float d_left = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
            float d_right = (i < halfWidthH) ? highpass[hBase + i] : highpass[hBase + max(int(halfWidthH) - 1, 0)];
            output[oBase + 2 * i] = lowpass[lBase + i] - (d_left + d_right + 2.0f) / 4.0f;
        }
        // Undo predict: x[2n+1] = d[n] + (x[2n] + x[2n+2]) / 2
        for (uint i = 0; i < halfWidthH; i++) {
            float left = output[oBase + 2 * i];
            float right = (2 * i + 2 < width) ? output[oBase + 2 * i + 2] : output[oBase + 2 * i];
            output[oBase + 2 * i + 1] = highpass[hBase + i] + (left + right) / 2.0f;
        }
    }

    // MARK: - Inverse 5/3 Reversible DWT (Vertical)

    kernel void j2k_dwt_inverse_53_vertical(
        device const float* lowpass [[buffer(0)]],
        device const float* highpass [[buffer(1)]],
        device float* output [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;
        uint halfHeightH = height / 2;

        // Undo update
        for (uint i = 0; i < halfHeight; i++) {
            float d_top = (i > 0) ? highpass[(i - 1) * width + col] : highpass[col];
            float d_bot = (i < halfHeightH) ? highpass[i * width + col] : highpass[max(int(halfHeightH) - 1, 0) * width + col];
            output[(2 * i) * width + col] = lowpass[i * width + col] - (d_top + d_bot + 2.0f) / 4.0f;
        }
        // Undo predict
        for (uint i = 0; i < halfHeightH; i++) {
            float top = output[(2 * i) * width + col];
            float bottom = (2 * i + 2 < height) ? output[(2 * i + 2) * width + col] : output[(2 * i) * width + col];
            output[(2 * i + 1) * width + col] = highpass[i * width + col] + (top + bottom) / 2.0f;
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Horizontal, integer / bit-exact)
    //
    // Lossless-only pivot — Phase 0. Bit-exact match for the CPU reference
    // `AcceleratedDWT2D.forward53_1D(_:_:count:workspace:)`:
    //   highpass[i] = X[2i+1] - ((X[2i] + X[2i+2]) >> 1)        // predict
    //   lowpass[i]  = X[2i]  + ((H[i-1] + H[i] + 2) >> 2)       // update
    // Whole-sample symmetric mirror at both boundaries.

    kernel void j2k_dwt_forward_53_horizontal_int(
        device const int* input [[buffer(0)]],
        device int* lowpass [[buffer(1)]],
        device int* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth  = (width + 1) / 2;
        uint halfWidthH = width / 2;

        uint idx   = row * width;
        uint lBase = row * halfWidth;
        uint hBase = row * halfWidthH;

        if (halfWidthH == 0) {
            if (halfWidth > 0) {
                lowpass[lBase] = input[idx];
            }
            return;
        }

        for (uint i = 0; i < halfWidthH; i++) {
            int xLeft  = input[idx + 2 * i];
            int xRight = (2 * i + 2 < width)
                ? input[idx + 2 * i + 2]
                : input[idx + 2 * i];
            highpass[hBase + i] =
                input[idx + 2 * i + 1] - ((xLeft + xRight) >> 1);
        }

        for (uint i = 0; i < halfWidth; i++) {
            int dLeft  = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
            int dRight = (i < halfWidthH)
                ? highpass[hBase + i]
                : highpass[hBase + halfWidthH - 1];
            lowpass[lBase + i] =
                input[idx + 2 * i] + ((dLeft + dRight + 2) >> 2);
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Vertical, integer / bit-exact)

    kernel void j2k_dwt_forward_53_vertical_int(
        device const int* input [[buffer(0)]],
        device int* lowpass [[buffer(1)]],
        device int* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight  = (height + 1) / 2;
        uint halfHeightH = height / 2;

        if (halfHeightH == 0) {
            if (halfHeight > 0) {
                lowpass[col] = input[col];
            }
            return;
        }

        for (uint i = 0; i < halfHeightH; i++) {
            int xTop = input[(2 * i) * width + col];
            int xBot = (2 * i + 2 < height)
                ? input[(2 * i + 2) * width + col]
                : input[(2 * i) * width + col];
            highpass[i * width + col] =
                input[(2 * i + 1) * width + col] - ((xTop + xBot) >> 1);
        }

        for (uint i = 0; i < halfHeight; i++) {
            int dTop = (i > 0)
                ? highpass[(i - 1) * width + col]
                : highpass[col];
            int dBot = (i < halfHeightH)
                ? highpass[i * width + col]
                : highpass[(halfHeightH - 1) * width + col];
            lowpass[i * width + col] =
                input[(2 * i) * width + col] + ((dTop + dBot + 2) >> 2);
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Horizontal, integer / odd origin)
    //
    // v6-alpha5 phase 4 — bit-exact match for the CPU reference
    // `AcceleratedDWT2D.forward53_1D(...uOrigin: odd)`.

    kernel void j2k_dwt_forward_53_horizontal_int_odd(
        device const int* input [[buffer(0)]],
        device int* lowpass [[buffer(1)]],
        device int* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint lowCount  = width / 2;
        uint highCount = width - lowCount;

        uint idx   = row * width;
        uint lBase = row * lowCount;
        uint hBase = row * highCount;

        if (lowCount == 0) {
            if (highCount > 0) {
                highpass[hBase] = input[idx];
            }
            return;
        }

        if (highCount > 0) {
            highpass[hBase] = input[idx] - input[idx + 1];
        }
        uint predictInteriorEnd = min(highCount, lowCount);
        for (uint i = 1; i < predictInteriorEnd; i++) {
            int lLeft  = input[idx + 2 * (i - 1) + 1];
            int lRight = input[idx + 2 * i + 1];
            highpass[hBase + i] = input[idx + 2 * i] - ((lLeft + lRight) >> 1);
        }
        if (highCount > lowCount) {
            int lLast = input[idx + 2 * (lowCount - 1) + 1];
            highpass[hBase + lowCount] = input[idx + 2 * lowCount] - lLast;
        }

        for (uint i = 0; i < lowCount; i++) {
            int hLeft  = highpass[hBase + i];
            int hRight = (i + 1 < highCount)
                ? highpass[hBase + i + 1]
                : highpass[hBase + highCount - 1];
            lowpass[lBase + i] = input[idx + 2 * i + 1] + ((hLeft + hRight + 2) >> 2);
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Vertical, integer / odd origin)

    kernel void j2k_dwt_forward_53_vertical_int_odd(
        device const int* input [[buffer(0)]],
        device int* lowpass [[buffer(1)]],
        device int* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint lowCount  = height / 2;
        uint highCount = height - lowCount;

        if (lowCount == 0) {
            if (highCount > 0) {
                highpass[col] = input[col];
            }
            return;
        }

        if (highCount > 0) {
            highpass[col] = input[col] - input[width + col];
        }
        uint predictInteriorEnd = min(highCount, lowCount);
        for (uint i = 1; i < predictInteriorEnd; i++) {
            int lTop = input[(2 * (i - 1) + 1) * width + col];
            int lBot = input[(2 * i + 1) * width + col];
            highpass[i * width + col] =
                input[(2 * i) * width + col] - ((lTop + lBot) >> 1);
        }
        if (highCount > lowCount) {
            int lLast = input[(2 * (lowCount - 1) + 1) * width + col];
            highpass[lowCount * width + col] =
                input[(2 * lowCount) * width + col] - lLast;
        }

        for (uint i = 0; i < lowCount; i++) {
            int hTop = highpass[i * width + col];
            int hBot = (i + 1 < highCount)
                ? highpass[(i + 1) * width + col]
                : highpass[(highCount - 1) * width + col];
            lowpass[i * width + col] =
                input[(2 * i + 1) * width + col] + ((hTop + hBot + 2) >> 2);
        }
    }

    // MARK: - Inverse 5/3 Reversible DWT (Horizontal, integer / bit-exact)
    //
    // Bit-exact match for J2KDWT1D.inverseTransform53 (symmetric extension):
    //   even[i] = lowpass[i] - ((hp[i-1] + hp[i] + 2) >> 2)
    //   odd[i]  = highpass[i] + ((even[i] + even[i+1]) >> 1)
    // Floor-divide via arithmetic right shift on signed int matches Swift's
    // `>> 2` / `>> 1` on Int32 (both perform sign-preserving shift).

    kernel void j2k_dwt_inverse_53_horizontal_int(
        device const int* lowpass [[buffer(0)]],
        device const int* highpass [[buffer(1)]],
        device int* output [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;
        uint halfWidthH = width / 2;

        uint lBase = row * halfWidth;
        uint hBase = row * halfWidthH;
        uint oBase = row * width;

        // Edge tile with no highpass samples → output equals lowpass.
        if (halfWidthH == 0) {
            for (uint i = 0; i < halfWidth; i++) {
                output[oBase + 2 * i] = lowpass[lBase + i];
            }
            return;
        }

        // Step 1 (undo update). Symmetric: hp[-1] = hp[0], hp[halfWidthH] = hp[halfWidthH-1].
        for (uint i = 0; i < halfWidth; i++) {
            int dLeft  = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
            int dRight = (i < halfWidthH)
                ? highpass[hBase + i]
                : highpass[hBase + halfWidthH - 1];
            output[oBase + 2 * i] = lowpass[lBase + i] - ((dLeft + dRight + 2) >> 2);
        }

        // Step 2 (undo predict). Symmetric: even[halfWidth] = even[halfWidth-1].
        for (uint i = 0; i < halfWidthH; i++) {
            int eLeft  = output[oBase + 2 * i];
            int eRight = (2 * i + 2 < width)
                ? output[oBase + 2 * i + 2]
                : output[oBase + 2 * i];
            output[oBase + 2 * i + 1] = highpass[hBase + i] + ((eLeft + eRight) >> 1);
        }
    }

    // MARK: - Inverse 5/3 Reversible DWT (Vertical, integer / bit-exact)

    kernel void j2k_dwt_inverse_53_vertical_int(
        device const int* lowpass [[buffer(0)]],
        device const int* highpass [[buffer(1)]],
        device int* output [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;
        uint halfHeightH = height / 2;

        // Edge tile with no highpass rows → copy lowpass rows into even slots.
        if (halfHeightH == 0) {
            for (uint i = 0; i < halfHeight; i++) {
                output[(2 * i) * width + col] = lowpass[i * width + col];
            }
            return;
        }

        // Step 1 (undo update). Symmetric column boundaries.
        for (uint i = 0; i < halfHeight; i++) {
            int dTop = (i > 0)
                ? highpass[(i - 1) * width + col]
                : highpass[col];
            int dBot = (i < halfHeightH)
                ? highpass[i * width + col]
                : highpass[(halfHeightH - 1) * width + col];
            output[(2 * i) * width + col] = lowpass[i * width + col] - ((dTop + dBot + 2) >> 2);
        }

        // Step 2 (undo predict).
        for (uint i = 0; i < halfHeightH; i++) {
            int eTop = output[(2 * i) * width + col];
            int eBot = (2 * i + 2 < height)
                ? output[(2 * i + 2) * width + col]
                : output[(2 * i) * width + col];
            output[(2 * i + 1) * width + col] = highpass[i * width + col] + ((eTop + eBot) >> 1);
        }
    }

    // MARK: - Forward ICT (Irreversible Colour Transform)

    kernel void j2k_ict_forward(
        device const float* r [[buffer(0)]],
        device const float* g [[buffer(1)]],
        device const float* b [[buffer(2)]],
        device float* y [[buffer(3)]],
        device float* cb [[buffer(4)]],
        device float* cr [[buffer(5)]],
        constant uint& count [[buffer(6)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float rv = r[gid];
        float gv = g[gid];
        float bv = b[gid];

        y[gid]  =  0.299f   * rv + 0.587f   * gv + 0.114f   * bv;
        cb[gid] = -0.16875f * rv - 0.33126f * gv + 0.5f     * bv;
        cr[gid] =  0.5f     * rv - 0.41869f * gv - 0.08131f * bv;
    }

    // MARK: - Inverse ICT (Irreversible Colour Transform)

    kernel void j2k_ict_inverse(
        device const float* y [[buffer(0)]],
        device const float* cb [[buffer(1)]],
        device const float* cr [[buffer(2)]],
        device float* r [[buffer(3)]],
        device float* g [[buffer(4)]],
        device float* b [[buffer(5)]],
        constant uint& count [[buffer(6)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float yv  = y[gid];
        float cbv = cb[gid];
        float crv = cr[gid];

        r[gid] = yv + 1.402f   * crv;
        g[gid] = yv - 0.34413f * cbv - 0.71414f * crv;
        b[gid] = yv + 1.772f   * cbv;
    }

    // MARK: - Forward RCT (Reversible Colour Transform)

    kernel void j2k_rct_forward(
        device const int* r [[buffer(0)]],
        device const int* g [[buffer(1)]],
        device const int* b [[buffer(2)]],
        device int* y [[buffer(3)]],
        device int* u [[buffer(4)]],
        device int* v [[buffer(5)]],
        constant uint& count [[buffer(6)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        int rv = r[gid];
        int gv = g[gid];
        int bv = b[gid];

        y[gid] = (rv + 2 * gv + bv) >> 2;
        u[gid] = bv - gv;
        v[gid] = rv - gv;
    }

    // MARK: - Inverse RCT (Reversible Colour Transform)

    kernel void j2k_rct_inverse(
        device const int* y [[buffer(0)]],
        device const int* u [[buffer(1)]],
        device const int* v [[buffer(2)]],
        device int* r [[buffer(3)]],
        device int* g [[buffer(4)]],
        device int* b [[buffer(5)]],
        constant uint& count [[buffer(6)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        int yv = y[gid];
        int uv = u[gid];
        int vv = v[gid];

        g[gid] = yv - ((uv + vv) >> 2);
        r[gid] = vv + g[gid];
        b[gid] = uv + g[gid];
    }

    // MARK: - MCT Matrix Multiply

    kernel void j2k_mct_matrix_multiply(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        device const float* matrix [[buffer(2)]],
        constant uint& componentCount [[buffer(3)]],
        constant uint& sampleCount [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= sampleCount) return;

        for (uint c = 0; c < componentCount; c++) {
            float sum = 0.0f;
            for (uint k = 0; k < componentCount; k++) {
                sum += matrix[c * componentCount + k] * input[k * sampleCount + gid];
            }
            output[c * sampleCount + gid] = sum;
        }
    }

    // MARK: - Scalar Quantization

    kernel void j2k_quantize(
        device const float* input [[buffer(0)]],
        device int* output [[buffer(1)]],
        constant float& stepSize [[buffer(2)]],
        constant float& deadzone [[buffer(3)]],
        constant uint& count [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float val = input[gid];
        float sign = (val >= 0.0f) ? 1.0f : -1.0f;
        float absVal = abs(val);

        if (absVal < deadzone * stepSize) {
            output[gid] = 0;
        } else {
            output[gid] = int(sign * floor(absVal / stepSize));
        }
    }

    // MARK: - Scalar Dequantization

    kernel void j2k_dequantize(
        device const int* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant float& stepSize [[buffer(2)]],
        constant uint& count [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        int val = input[gid];
        if (val == 0) {
            output[gid] = 0.0f;
        } else {
            float sign = (val > 0) ? 1.0f : -1.0f;
            output[gid] = sign * (float(abs(val)) + 0.5f) * stepSize;
        }
    }

    // MARK: - Forward Arbitrary Wavelet (Horizontal) - Generic Convolution

    kernel void j2k_dwt_forward_arbitrary_horizontal(
        device const float* input [[buffer(0)]],
        device float* lowpass [[buffer(1)]],
        device float* highpass [[buffer(2)]],
        device const float* analysisLow [[buffer(3)]],
        device const float* analysisHigh [[buffer(4)]],
        constant uint& width [[buffer(5)]],
        constant uint& height [[buffer(6)]],
        constant uint& filterLowLen [[buffer(7)]],
        constant uint& filterHighLen [[buffer(8)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;
        uint halfLow = filterLowLen / 2;
        uint halfHigh = filterHighLen / 2;

        // Lowpass: downsample by 2, convolve with analysis lowpass filter
        for (uint i = 0; i < halfWidth; i++) {
            float sum = 0.0f;
            int center = int(2 * i);
            for (uint k = 0; k < filterLowLen; k++) {
                int srcIdx = center + int(k) - int(halfLow);
                // Symmetric boundary extension
                if (srcIdx < 0) srcIdx = -srcIdx;
                if (srcIdx >= int(width)) srcIdx = 2 * int(width) - srcIdx - 2;
                sum += input[row * width + uint(srcIdx)] * analysisLow[k];
            }
            lowpass[row * halfWidth + i] = sum;
        }

        // Highpass: downsample by 2, convolve with analysis highpass filter
        uint halfWidthH = width / 2;
        for (uint i = 0; i < halfWidthH; i++) {
            float sum = 0.0f;
            int center = int(2 * i + 1);
            for (uint k = 0; k < filterHighLen; k++) {
                int srcIdx = center + int(k) - int(halfHigh);
                if (srcIdx < 0) srcIdx = -srcIdx;
                if (srcIdx >= int(width)) srcIdx = 2 * int(width) - srcIdx - 2;
                sum += input[row * width + uint(srcIdx)] * analysisHigh[k];
            }
            highpass[row * halfWidthH + i] = sum;
        }
    }

    // MARK: - Inverse Arbitrary Wavelet (Horizontal) - Generic Convolution

    kernel void j2k_dwt_inverse_arbitrary_horizontal(
        device const float* lowpass [[buffer(0)]],
        device const float* highpass [[buffer(1)]],
        device float* output [[buffer(2)]],
        device const float* synthesisLow [[buffer(3)]],
        device const float* synthesisHigh [[buffer(4)]],
        constant uint& width [[buffer(5)]],
        constant uint& height [[buffer(6)]],
        constant uint& filterLowLen [[buffer(7)]],
        constant uint& filterHighLen [[buffer(8)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;
        uint halfWidthH = width / 2;

        // Upsample and convolve: interleave lowpass and highpass contributions
        for (uint n = 0; n < width; n++) {
            float sum = 0.0f;
            // Lowpass contribution (upsampled at even positions)
            for (uint k = 0; k < filterLowLen; k++) {
                int idx = int(n) - int(k);
                if (idx >= 0 && idx % 2 == 0) {
                    uint j = uint(idx) / 2;
                    if (j < halfWidth) {
                        sum += lowpass[row * halfWidth + j] * synthesisLow[k];
                    }
                }
            }
            // Highpass contribution (upsampled at odd positions)
            for (uint k = 0; k < filterHighLen; k++) {
                int idx = int(n) - int(k);
                if (idx >= 0 && (idx % 2 == 1)) {
                    uint j = uint(idx) / 2;
                    if (j < halfWidthH) {
                        sum += highpass[row * halfWidthH + j] * synthesisHigh[k];
                    }
                }
            }
            output[row * width + n] = sum;
        }
    }

    // MARK: - Forward Arbitrary Wavelet (Vertical) - Generic Convolution

    kernel void j2k_dwt_forward_arbitrary_vertical(
        device const float* input [[buffer(0)]],
        device float* lowpass [[buffer(1)]],
        device float* highpass [[buffer(2)]],
        device const float* analysisLow [[buffer(3)]],
        device const float* analysisHigh [[buffer(4)]],
        constant uint& width [[buffer(5)]],
        constant uint& height [[buffer(6)]],
        constant uint& filterLowLen [[buffer(7)]],
        constant uint& filterHighLen [[buffer(8)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;
        uint halfLow = filterLowLen / 2;
        uint halfHigh = filterHighLen / 2;

        // Lowpass: downsample by 2, convolve vertically
        for (uint i = 0; i < halfHeight; i++) {
            float sum = 0.0f;
            int center = int(2 * i);
            for (uint k = 0; k < filterLowLen; k++) {
                int srcRow = center + int(k) - int(halfLow);
                if (srcRow < 0) srcRow = -srcRow;
                if (srcRow >= int(height)) srcRow = 2 * int(height) - srcRow - 2;
                sum += input[uint(srcRow) * width + col] * analysisLow[k];
            }
            lowpass[i * width + col] = sum;
        }

        // Highpass
        uint halfHeightH = height / 2;
        for (uint i = 0; i < halfHeightH; i++) {
            float sum = 0.0f;
            int center = int(2 * i + 1);
            for (uint k = 0; k < filterHighLen; k++) {
                int srcRow = center + int(k) - int(halfHigh);
                if (srcRow < 0) srcRow = -srcRow;
                if (srcRow >= int(height)) srcRow = 2 * int(height) - srcRow - 2;
                sum += input[uint(srcRow) * width + col] * analysisHigh[k];
            }
            highpass[i * width + col] = sum;
        }
    }

    // MARK: - Inverse Arbitrary Wavelet (Vertical) - Generic Convolution

    kernel void j2k_dwt_inverse_arbitrary_vertical(
        device const float* lowpass [[buffer(0)]],
        device const float* highpass [[buffer(1)]],
        device float* output [[buffer(2)]],
        device const float* synthesisLow [[buffer(3)]],
        device const float* synthesisHigh [[buffer(4)]],
        constant uint& width [[buffer(5)]],
        constant uint& height [[buffer(6)]],
        constant uint& filterLowLen [[buffer(7)]],
        constant uint& filterHighLen [[buffer(8)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;
        uint halfHeightH = height / 2;

        for (uint n = 0; n < height; n++) {
            float sum = 0.0f;
            for (uint k = 0; k < filterLowLen; k++) {
                int idx = int(n) - int(k);
                if (idx >= 0 && idx % 2 == 0) {
                    uint j = uint(idx) / 2;
                    if (j < halfHeight) {
                        sum += lowpass[j * width + col] * synthesisLow[k];
                    }
                }
            }
            for (uint k = 0; k < filterHighLen; k++) {
                int idx = int(n) - int(k);
                if (idx >= 0 && (idx % 2 == 1)) {
                    uint j = uint(idx) / 2;
                    if (j < halfHeightH) {
                        sum += highpass[j * width + col] * synthesisHigh[k];
                    }
                }
            }
            output[n * width + col] = sum;
        }
    }

    // MARK: - Forward Lifting Scheme DWT (Horizontal)

    kernel void j2k_dwt_forward_lifting_horizontal(
        device float* data [[buffer(0)]],
        device const float* liftingCoeffs [[buffer(1)]],
        constant uint& width [[buffer(2)]],
        constant uint& height [[buffer(3)]],
        constant uint& numSteps [[buffer(4)]],
        constant float& finalScaleL [[buffer(5)]],
        constant float& finalScaleH [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;

        // Apply lifting steps in-place
        // Even indices = lowpass, Odd indices = highpass
        for (uint step = 0; step < numSteps; step++) {
            float coeff = liftingCoeffs[step];
            bool updateOdd = (step % 2 == 0); // Predict then Update alternation

            if (updateOdd) {
                // Update odd (highpass) samples using even (lowpass) neighbors
                for (uint i = 0; i < width / 2; i++) {
                    uint oddIdx = row * width + 2 * i + 1;
                    uint leftEven = row * width + 2 * i;
                    uint rightEven = (2 * i + 2 < width)
                        ? row * width + 2 * i + 2
                        : row * width + 2 * i;
                    data[oddIdx] += coeff * (data[leftEven] + data[rightEven]);
                }
            } else {
                // Update even (lowpass) samples using odd (highpass) neighbors
                for (uint i = 0; i < halfWidth; i++) {
                    uint evenIdx = row * width + 2 * i;
                    uint leftOdd = (i > 0)
                        ? row * width + 2 * i - 1
                        : row * width + 1;
                    uint rightOdd = (2 * i + 1 < width)
                        ? row * width + 2 * i + 1
                        : row * width + width - 2;
                    data[evenIdx] += coeff * (data[leftOdd] + data[rightOdd]);
                }
            }
        }

        // Apply final scaling
        for (uint i = 0; i < halfWidth; i++) {
            data[row * width + 2 * i] *= finalScaleL;
        }
        for (uint i = 0; i < width / 2; i++) {
            data[row * width + 2 * i + 1] *= finalScaleH;
        }
    }

    // MARK: - Inverse Lifting Scheme DWT (Horizontal)

    kernel void j2k_dwt_inverse_lifting_horizontal(
        device float* data [[buffer(0)]],
        device const float* liftingCoeffs [[buffer(1)]],
        constant uint& width [[buffer(2)]],
        constant uint& height [[buffer(3)]],
        constant uint& numSteps [[buffer(4)]],
        constant float& finalScaleL [[buffer(5)]],
        constant float& finalScaleH [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;

        // Undo final scaling
        for (uint i = 0; i < halfWidth; i++) {
            data[row * width + 2 * i] /= finalScaleL;
        }
        for (uint i = 0; i < width / 2; i++) {
            data[row * width + 2 * i + 1] /= finalScaleH;
        }

        // Apply lifting steps in reverse order with negated coefficients
        for (int step = int(numSteps) - 1; step >= 0; step--) {
            float coeff = -liftingCoeffs[step];
            bool updateOdd = (step % 2 == 0);

            if (updateOdd) {
                for (uint i = 0; i < width / 2; i++) {
                    uint oddIdx = row * width + 2 * i + 1;
                    uint leftEven = row * width + 2 * i;
                    uint rightEven = (2 * i + 2 < width)
                        ? row * width + 2 * i + 2
                        : row * width + 2 * i;
                    data[oddIdx] += coeff * (data[leftEven] + data[rightEven]);
                }
            } else {
                for (uint i = 0; i < halfWidth; i++) {
                    uint evenIdx = row * width + 2 * i;
                    uint leftOdd = (i > 0)
                        ? row * width + 2 * i - 1
                        : row * width + 1;
                    uint rightOdd = (2 * i + 1 < width)
                        ? row * width + 2 * i + 1
                        : row * width + width - 2;
                    data[evenIdx] += coeff * (data[leftOdd] + data[rightOdd]);
                }
            }
        }
    }

    // MARK: - Forward Lifting Scheme DWT (Vertical)

    kernel void j2k_dwt_forward_lifting_vertical(
        device float* data [[buffer(0)]],
        device const float* liftingCoeffs [[buffer(1)]],
        constant uint& width [[buffer(2)]],
        constant uint& height [[buffer(3)]],
        constant uint& numSteps [[buffer(4)]],
        constant float& finalScaleL [[buffer(5)]],
        constant float& finalScaleH [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;

        for (uint step = 0; step < numSteps; step++) {
            float coeff = liftingCoeffs[step];
            bool updateOdd = (step % 2 == 0);

            if (updateOdd) {
                for (uint i = 0; i < height / 2; i++) {
                    uint oddIdx = (2 * i + 1) * width + col;
                    uint topEven = (2 * i) * width + col;
                    uint botEven = (2 * i + 2 < height)
                        ? (2 * i + 2) * width + col
                        : (2 * i) * width + col;
                    data[oddIdx] += coeff * (data[topEven] + data[botEven]);
                }
            } else {
                for (uint i = 0; i < halfHeight; i++) {
                    uint evenIdx = (2 * i) * width + col;
                    uint topOdd = (i > 0)
                        ? (2 * i - 1) * width + col
                        : width + col;
                    uint botOdd = (2 * i + 1 < height)
                        ? (2 * i + 1) * width + col
                        : (height - 2) * width + col;
                    data[evenIdx] += coeff * (data[topOdd] + data[botOdd]);
                }
            }
        }

        for (uint i = 0; i < halfHeight; i++) {
            data[(2 * i) * width + col] *= finalScaleL;
        }
        for (uint i = 0; i < height / 2; i++) {
            data[(2 * i + 1) * width + col] *= finalScaleH;
        }
    }

    // MARK: - Inverse Lifting Scheme DWT (Vertical)

    kernel void j2k_dwt_inverse_lifting_vertical(
        device float* data [[buffer(0)]],
        device const float* liftingCoeffs [[buffer(1)]],
        constant uint& width [[buffer(2)]],
        constant uint& height [[buffer(3)]],
        constant uint& numSteps [[buffer(4)]],
        constant float& finalScaleL [[buffer(5)]],
        constant float& finalScaleH [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;

        // Undo final scaling
        for (uint i = 0; i < halfHeight; i++) {
            data[(2 * i) * width + col] /= finalScaleL;
        }
        for (uint i = 0; i < height / 2; i++) {
            data[(2 * i + 1) * width + col] /= finalScaleH;
        }

        for (int step = int(numSteps) - 1; step >= 0; step--) {
            float coeff = -liftingCoeffs[step];
            bool updateOdd = (step % 2 == 0);

            if (updateOdd) {
                for (uint i = 0; i < height / 2; i++) {
                    uint oddIdx = (2 * i + 1) * width + col;
                    uint topEven = (2 * i) * width + col;
                    uint botEven = (2 * i + 2 < height)
                        ? (2 * i + 2) * width + col
                        : (2 * i) * width + col;
                    data[oddIdx] += coeff * (data[topEven] + data[botEven]);
                }
            } else {
                for (uint i = 0; i < halfHeight; i++) {
                    uint evenIdx = (2 * i) * width + col;
                    uint topOdd = (i > 0)
                        ? (2 * i - 1) * width + col
                        : width + col;
                    uint botOdd = (2 * i + 1 < height)
                        ? (2 * i + 1) * width + col
                        : (height - 2) * width + col;
                    data[evenIdx] += coeff * (data[topOdd] + data[botOdd]);
                }
            }
        }
    }

    // MARK: - Parametric Non-Linear Transform

    kernel void j2k_nlt_parametric(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant uint& count [[buffer(2)]],
        constant uint& transformType [[buffer(3)]],
        constant float& param1 [[buffer(4)]],
        constant float& param2 [[buffer(5)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float val = input[gid];

        // transformType: 0=gamma, 1=log, 2=exp
        if (transformType == 0) {
            // Gamma correction: output = sign(val) * |val|^param1
            float sign = (val >= 0.0f) ? 1.0f : -1.0f;
            output[gid] = sign * pow(abs(val), param1);
        } else if (transformType == 1) {
            // Logarithmic: output = param1 * log(1 + param2 * |val|) * sign(val)
            float sign = (val >= 0.0f) ? 1.0f : -1.0f;
            output[gid] = sign * param1 * log(1.0f + param2 * abs(val));
        } else {
            // Exponential: output = param1 * (exp(param2 * |val|) - 1) * sign(val)
            float sign = (val >= 0.0f) ? 1.0f : -1.0f;
            output[gid] = sign * param1 * (exp(param2 * abs(val)) - 1.0f);
        }
    }

    // MARK: - LUT-Based Non-Linear Transform

    kernel void j2k_nlt_lut(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        device const float* lut [[buffer(2)]],
        constant uint& count [[buffer(3)]],
        constant uint& lutSize [[buffer(4)]],
        constant float& inputMin [[buffer(5)]],
        constant float& inputMax [[buffer(6)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float val = input[gid];
        float range = inputMax - inputMin;
        if (range <= 0.0f) {
            output[gid] = lut[0];
            return;
        }

        // Normalise to [0, lutSize-1]
        float normalized = (val - inputMin) / range * float(lutSize - 1);
        normalized = clamp(normalized, 0.0f, float(lutSize - 1));

        // Linear interpolation
        uint idx0 = uint(normalized);
        uint idx1 = min(idx0 + 1, lutSize - 1);
        float frac = normalized - float(idx0);

        output[gid] = lut[idx0] * (1.0f - frac) + lut[idx1] * frac;
    }

    // MARK: - Optimised 3×3 MCT Matrix Multiply

    kernel void j2k_mct_matrix_multiply_3x3(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant float* matrix [[buffer(2)]],
        constant uint& sampleCount [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= sampleCount) return;

        float c0 = input[gid];
        float c1 = input[sampleCount + gid];
        float c2 = input[2 * sampleCount + gid];

        output[gid]                  = matrix[0] * c0 + matrix[1] * c1 + matrix[2] * c2;
        output[sampleCount + gid]    = matrix[3] * c0 + matrix[4] * c1 + matrix[5] * c2;
        output[2 * sampleCount + gid] = matrix[6] * c0 + matrix[7] * c1 + matrix[8] * c2;
    }

    // MARK: - Optimised 4×4 MCT Matrix Multiply

    kernel void j2k_mct_matrix_multiply_4x4(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant float* matrix [[buffer(2)]],
        constant uint& sampleCount [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= sampleCount) return;

        float c0 = input[gid];
        float c1 = input[sampleCount + gid];
        float c2 = input[2 * sampleCount + gid];
        float c3 = input[3 * sampleCount + gid];

        output[gid]                  = matrix[0]  * c0 + matrix[1]  * c1 + matrix[2]  * c2 + matrix[3]  * c3;
        output[sampleCount + gid]    = matrix[4]  * c0 + matrix[5]  * c1 + matrix[6]  * c2 + matrix[7]  * c3;
        output[2 * sampleCount + gid] = matrix[8]  * c0 + matrix[9]  * c1 + matrix[10] * c2 + matrix[11] * c3;
        output[3 * sampleCount + gid] = matrix[12] * c0 + matrix[13] * c1 + matrix[14] * c2 + matrix[15] * c3;
    }

    // MARK: - Fused Colour Transform + MCT

    kernel void j2k_color_mct_fused(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant float* colorMatrix [[buffer(2)]],
        constant float* mctMatrix [[buffer(3)]],
        constant uint& componentCount [[buffer(4)]],
        constant uint& sampleCount [[buffer(5)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= sampleCount) return;

        // Apply colour transform then MCT in a single pass
        // First: colour transform
        float temp[16]; // Max 16 components
        for (uint c = 0; c < componentCount && c < 16; c++) {
            float sum = 0.0f;
            for (uint k = 0; k < componentCount; k++) {
                sum += colorMatrix[c * componentCount + k] * input[k * sampleCount + gid];
            }
            temp[c] = sum;
        }

        // Second: MCT
        for (uint c = 0; c < componentCount && c < 16; c++) {
            float sum = 0.0f;
            for (uint k = 0; k < componentCount; k++) {
                sum += mctMatrix[c * componentCount + k] * temp[k];
            }
            output[c * sampleCount + gid] = sum;
        }
    }

    // MARK: - Perceptual Quantizer (PQ) - SMPTE ST 2084

    kernel void j2k_nlt_pq(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant uint& count [[buffer(2)]],
        constant uint& inverse [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        // PQ constants (SMPTE ST 2084)
        const float m1 = 0.1593017578125f;
        const float m2 = 78.84375f;
        const float c1 = 0.8359375f;
        const float c2 = 18.8515625f;
        const float c3 = 18.6875f;

        float val = input[gid];

        if (inverse == 0) {
            // Forward PQ: linear to PQ
            float y = clamp(val, 0.0f, 1.0f);
            float ym1 = pow(y, m1);
            output[gid] = pow((c1 + c2 * ym1) / (1.0f + c3 * ym1), m2);
        } else {
            // Inverse PQ: PQ to linear
            float n = clamp(val, 0.0f, 1.0f);
            float nm2 = pow(n, 1.0f / m2);
            float num = max(nm2 - c1, 0.0f);
            float den = c2 - c3 * nm2;
            output[gid] = pow(num / max(den, 1e-10f), 1.0f / m1);
        }
    }

    // MARK: - Hybrid Log-Gamma (HLG) - ITU-R BT.2100

    kernel void j2k_nlt_hlg(
        device const float* input [[buffer(0)]],
        device float* output [[buffer(1)]],
        constant uint& count [[buffer(2)]],
        constant uint& inverse [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        // HLG constants
        const float a = 0.17883277f;
        const float b = 0.28466892f;  // 1 - 4*a
        const float c = 0.55991073f;  // 0.5 - a*ln(4*a)

        float val = input[gid];

        if (inverse == 0) {
            // Forward HLG: linear to HLG
            float e = clamp(val, 0.0f, 1.0f);
            if (e <= 1.0f / 12.0f) {
                output[gid] = sqrt(3.0f * e);
            } else {
                output[gid] = a * log(12.0f * e - b) + c;
            }
        } else {
            // Inverse HLG: HLG to linear
            float ep = clamp(val, 0.0f, 1.0f);
            if (ep <= 0.5f) {
                output[gid] = ep * ep / 3.0f;
            } else {
                output[gid] = (exp((ep - c) / a) + b) / 12.0f;
            }
        }
    }

    // MARK: - Region of Interest (ROI) Shaders

    // Generate ROI mask from rectangular bounds
    kernel void j2k_roi_mask_generate(
        device bool* mask [[buffer(0)]],
        constant uint& width [[buffer(1)]],
        constant uint& height [[buffer(2)]],
        constant uint& roiX [[buffer(3)]],
        constant uint& roiY [[buffer(4)]],
        constant uint& roiWidth [[buffer(5)]],
        constant uint& roiHeight [[buffer(6)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width || gid.y >= height) return;

        uint x = gid.x;
        uint y = gid.y;

        // Check if pixel is inside ROI rectangle
        bool insideX = (x >= roiX) && (x < roiX + roiWidth);
        bool insideY = (y >= roiY) && (y < roiY + roiHeight);

        mask[y * width + x] = insideX && insideY;
    }

    // Apply MaxShift coefficient scaling for ROI
    kernel void j2k_roi_coefficient_scale(
        device const int* input [[buffer(0)]],
        device const bool* mask [[buffer(1)]],
        device int* output [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        constant uint& shift [[buffer(5)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width || gid.y >= height) return;

        uint idx = gid.y * width + gid.x;
        int coeff = input[idx];

        // Apply bit-shift only if mask is set
        if (mask[idx]) {
            // Preserve sign and shift magnitude
            if (coeff >= 0) {
                output[idx] = coeff << shift;
            } else {
                output[idx] = -((-coeff) << shift);
            }
        } else {
            output[idx] = coeff;
        }
    }

    // Blend multiple ROI masks with priority
    kernel void j2k_roi_mask_blend(
        device const bool* mask1 [[buffer(0)]],
        device const bool* mask2 [[buffer(1)]],
        device const uint* priority1 [[buffer(2)]],
        device const uint* priority2 [[buffer(3)]],
        device bool* output [[buffer(4)]],
        device uint* outputPriority [[buffer(5)]],
        constant uint& count [[buffer(6)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        bool m1 = mask1[gid];
        bool m2 = mask2[gid];
        uint p1 = priority1[0];
        uint p2 = priority2[0];

        // Higher priority wins, or combine if equal
        if (m1 && m2) {
            if (p1 >= p2) {
                output[gid] = true;
                outputPriority[gid] = p1;
            } else {
                output[gid] = true;
                outputPriority[gid] = p2;
            }
        } else if (m1) {
            output[gid] = true;
            outputPriority[gid] = p1;
        } else if (m2) {
            output[gid] = true;
            outputPriority[gid] = p2;
        } else {
            output[gid] = false;
            outputPriority[gid] = 0;
        }
    }

    // Apply feathering/smooth transitions to ROI boundaries
    kernel void j2k_roi_feathering(
        device const bool* mask [[buffer(0)]],
        device float* scalingMap [[buffer(1)]],
        constant uint& width [[buffer(2)]],
        constant uint& height [[buffer(3)]],
        constant float& featherWidth [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width || gid.y >= height) return;

        uint idx = gid.y * width + gid.x;

        // If inside ROI, full scaling
        if (mask[idx]) {
            scalingMap[idx] = 1.0f;
            return;
        }

        // Find minimum distance to ROI boundary
        float minDist = featherWidth + 1.0f;
        int searchRadius = (int)ceil(featherWidth);

        for (int dy = -searchRadius; dy <= searchRadius; dy++) {
            for (int dx = -searchRadius; dx <= searchRadius; dx++) {
                int nx = (int)gid.x + dx;
                int ny = (int)gid.y + dy;

                if (nx >= 0 && nx < (int)width && ny >= 0 && ny < (int)height) {
                    if (mask[ny * width + nx]) {
                        float dist = sqrt((float)(dx * dx + dy * dy));
                        minDist = min(minDist, dist);
                    }
                }
            }
        }

        // Apply smooth falloff based on distance
        if (minDist <= featherWidth) {
            scalingMap[idx] = 1.0f - (minDist / featherWidth);
        } else {
            scalingMap[idx] = 0.0f;
        }
    }

    // Map spatial ROI to wavelet domain coefficients
    kernel void j2k_roi_wavelet_mapping(
        device const bool* spatialMask [[buffer(0)]],
        device bool* waveletMask [[buffer(1)]],
        constant uint& spatialWidth [[buffer(2)]],
        constant uint& spatialHeight [[buffer(3)]],
        constant uint& waveletWidth [[buffer(4)]],
        constant uint& waveletHeight [[buffer(5)]],
        constant uint& decompositionLevel [[buffer(6)]],
        constant uint& subbandType [[buffer(7)]],  // 0=LL, 1=LH, 2=HL, 3=HH
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= waveletWidth || gid.y >= waveletHeight) return;

        uint waveletIdx = gid.y * waveletWidth + gid.x;

        // Scale factor for this decomposition level
        uint scaleFactor = 1u << decompositionLevel;

        // Map wavelet coefficient to spatial region
        uint spatialX = gid.x * scaleFactor;
        uint spatialY = gid.y * scaleFactor;

        // Apply subband offset (for LH, HL, HH subbands)
        if (subbandType == 1 || subbandType == 3) {  // LH or HH
            spatialX += scaleFactor / 2;
        }
        if (subbandType == 2 || subbandType == 3) {  // HL or HH
            spatialY += scaleFactor / 2;
        }

        // Check if any pixel in the corresponding spatial region is in ROI
        bool inROI = false;
        for (uint dy = 0; dy < scaleFactor && !inROI; dy++) {
            for (uint dx = 0; dx < scaleFactor && !inROI; dx++) {
                uint sx = spatialX + dx;
                uint sy = spatialY + dy;
                if (sx < spatialWidth && sy < spatialHeight) {
                    if (spatialMask[sy * spatialWidth + sx]) {
                        inROI = true;
                    }
                }
            }
        }

        waveletMask[waveletIdx] = inROI;
    }

    // MARK: - Quantization Shaders

    // Scalar quantization with uniform step size
    kernel void j2k_quantize_scalar(
        device const float* coefficients [[buffer(0)]],
        device int* indices [[buffer(1)]],
        constant float& stepSize [[buffer(2)]],
        constant uint& count [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float c = coefficients[gid];
        float absC = fabs(c);
        int sign = (c >= 0.0f) ? 1 : -1;

        // q = sign(c) × floor(|c| / Δ)
        int q = (int)floor(absC / stepSize);
        indices[gid] = sign * q;
    }

    // Dead-zone quantization with enlarged zero bin
    kernel void j2k_quantize_deadzone(
        device const float* coefficients [[buffer(0)]],
        device int* indices [[buffer(1)]],
        constant float& stepSize [[buffer(2)]],
        constant float& deadzoneWidth [[buffer(3)]],
        constant uint& count [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float c = coefficients[gid];
        float absC = fabs(c);
        float threshold = stepSize * deadzoneWidth * 0.5f;

        if (absC <= threshold) {
            indices[gid] = 0;
        } else {
            int sign = (c >= 0.0f) ? 1 : -1;
            // q = sign(c) × floor((|c| - t) / Δ) + 1
            int q = (int)floor((absC - threshold) / stepSize) + 1;
            indices[gid] = sign * q;
        }
    }

    // Dequantization (scalar mode)
    kernel void j2k_dequantize_scalar(
        device const int* indices [[buffer(0)]],
        device float* coefficients [[buffer(1)]],
        constant float& stepSize [[buffer(2)]],
        constant uint& count [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        int q = indices[gid];
        if (q == 0) {
            coefficients[gid] = 0.0f;
        } else {
            int sign = (q >= 0) ? 1 : -1;
            int absQ = abs(q);
            // c' = (q + 0.5 × sign(q)) × Δ (midpoint reconstruction)
            coefficients[gid] = (float)(sign * absQ + 0.5f * sign) * stepSize;
        }
    }

    // Dequantization (dead-zone mode)
    kernel void j2k_dequantize_deadzone(
        device const int* indices [[buffer(0)]],
        device float* coefficients [[buffer(1)]],
        constant float& stepSize [[buffer(2)]],
        constant float& deadzoneWidth [[buffer(3)]],
        constant uint& count [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        int q = indices[gid];
        float threshold = stepSize * deadzoneWidth * 0.5f;

        if (q == 0) {
            coefficients[gid] = 0.0f;
        } else {
            int sign = (q >= 0) ? 1 : -1;
            int absQ = abs(q);
            // c' = sign(q) × ((|q| - 0.5) × Δ + threshold)
            coefficients[gid] = (float)sign * ((float)(absQ - 0.5f) * stepSize + threshold);
        }
    }

    // Apply visual frequency weighting to quantization step sizes
    kernel void j2k_quantize_visual_weighting(
        device const float* baseStepSizes [[buffer(0)]],
        device const float* visualWeights [[buffer(1)]],
        device float* adjustedStepSizes [[buffer(2)]],
        constant uint& count [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        // Apply perceptual weighting: Δ' = Δ × W
        // Lower weight = higher quality (smaller step size)
        float weight = max(visualWeights[gid], 0.1f);  // Clamp minimum weight
        adjustedStepSizes[gid] = baseStepSizes[gid] * weight;
    }

    // Perceptual quantization based on quality metrics
    kernel void j2k_quantize_perceptual(
        device const float* coefficients [[buffer(0)]],
        device const float* perceptualWeights [[buffer(1)]],
        device int* indices [[buffer(2)]],
        constant float& baseStepSize [[buffer(3)]],
        constant uint& count [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float c = coefficients[gid];
        float weight = perceptualWeights[gid];
        float stepSize = baseStepSize * weight;

        float absC = fabs(c);
        int sign = (c >= 0.0f) ? 1 : -1;
        int q = (int)floor(absC / stepSize);
        indices[gid] = sign * q;
    }

    // Parallel trellis state evaluation for TCQ
    kernel void j2k_quantize_trellis_evaluate(
        device const float* coefficients [[buffer(0)]],
        device const float* pathMetrics [[buffer(1)]],
        device float* newMetrics [[buffer(2)]],
        device int* decisions [[buffer(3)]],
        constant float& stepSize [[buffer(4)]],
        constant uint& numStates [[buffer(5)]],
        constant uint& coeffIndex [[buffer(6)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= numStates) return;

        // Each thread evaluates one state transition
        float coeff = coefficients[coeffIndex];
        float bestMetric = INFINITY;
        int bestDecision = 0;

        // Evaluate all possible transitions to this state
        for (uint prevState = 0; prevState < numStates; prevState++) {
            // Compute reconstruction value for this transition
            float reconstruction = (float)((int)prevState - (int)numStates / 2) * stepSize;

            // Compute distortion
            float distortion = (coeff - reconstruction) * (coeff - reconstruction);

            // Compute accumulated metric
            float metric = pathMetrics[prevState] + distortion;

            if (metric < bestMetric) {
                bestMetric = metric;
                bestDecision = (int)prevState;
            }
        }

        newMetrics[gid] = bestMetric;
        decisions[gid * 256 + coeffIndex] = bestDecision;  // Store decision path
    }

    // Compute distortion metrics for R-D optimisation
    kernel void j2k_quantize_distortion_metric(
        device const float* original [[buffer(0)]],
        device const float* reconstructed [[buffer(1)]],
        device float* distortions [[buffer(2)]],
        constant uint& count [[buffer(3)]],
        constant uint& metric [[buffer(4)]],  // 0=MSE, 1=MAE, 2=PSNR
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= count) return;

        float orig = original[gid];
        float recon = reconstructed[gid];
        float diff = orig - recon;

        switch (metric) {
            case 0:  // MSE (Mean Squared Error)
                distortions[gid] = diff * diff;
                break;
            case 1:  // MAE (Mean Absolute Error)
                distortions[gid] = fabs(diff);
                break;
            case 2:  // Squared difference for PSNR calculation
                distortions[gid] = diff * diff;
                break;
            default:
                distortions[gid] = diff * diff;
        }
    }

    // MARK: - HTJ2K Decode Prototype: dispatch-cost probe
    //
    // Layout the eventual real decoder will use, exercised here with
    // trivial work so we can measure the actual GPU launch + memory
    // marshaling overhead at varying codeblock counts. Each thread
    // handles one codeblock — the same architecture a full HT decoder
    // would use (per-codeblock state is independent, the parallelism
    // unit is the codeblock).
    //
    // Inputs:
    //   blocks       — array of CodeBlockDescriptor, one per codeblock
    //   codestream   — single concatenated byte pool covering all blocks
    //   output       — single Int32 pool covering all decoded samples
    //   blockCount   — number of codeblocks to process
    //
    // Per-block work: walk the codeblock's bytes once, sum into a
    // checksum, and write `width × height` Int32 values to the output
    // region. Substitutes for the eventual MQ-free HT decode workload.

    struct GPUHTBlockDescriptor {
        uint dataOffset;    // byte offset into codestream pool
        uint dataLength;
        uint outputOffset;  // sample offset into output pool
        ushort width;
        ushort height;
    };

    kernel void j2k_ht_dispatch_probe(
        device const GPUHTBlockDescriptor* blocks  [[buffer(0)]],
        device const uchar*                codestream [[buffer(1)]],
        device int*                        output  [[buffer(2)]],
        constant uint&                     blockCount [[buffer(3)]],
        uint tid [[thread_position_in_grid]]
    ) {
        if (tid >= blockCount) return;
        GPUHTBlockDescriptor desc = blocks[tid];

        // Touch every input byte once — models the per-block bit-stream
        // walk an HT decoder would do. The accumulator stays in a
        // register so the optimizer cannot eliminate the loop.
        uint checksum = 0;
        for (uint i = 0; i < desc.dataLength; i++) {
            checksum = checksum * 1103515245u + uint(codestream[desc.dataOffset + i]);
        }

        // Write width × height Int32 outputs — models the eventual
        // coefficient write traffic.
        uint sampleCount = uint(desc.width) * uint(desc.height);
        device int* myOut = output + desc.outputOffset;
        int v = int(checksum & 0x0FFFu);   // bounded magnitude
        for (uint i = 0; i < sampleCount; i++) {
            myOut[i] = ((i & 1u) == 0u) ? v : -v;
        }
    }

    // MARK: - HTJ2K Forward Encode Prototype: dispatch-cost probe (v6-alpha6 phase 0.5)
    //
    // Symmetric to `j2k_ht_dispatch_probe` (decoder side) but for the
    // **encode** direction. See J2KShaders.metal for the canonical
    // documentation; this inline copy stays bit-identical for the
    // source-compile fallback path (no `default.metallib`).

    struct GPUHTForwardBlockDescriptor {
        uint coeffOffset;
        uint outputOffset;
        uint outputCapacity;
        ushort width;
        ushort height;
    };

    kernel void j2k_ht_forward_dispatch_probe(
        device const GPUHTForwardBlockDescriptor* blocks       [[buffer(0)]],
        device const uint*                        coefficients [[buffer(1)]],
        device uchar*                             output       [[buffer(2)]],
        constant uint&                            blockCount   [[buffer(3)]],
        uint tid [[thread_position_in_grid]]
    ) {
        if (tid >= blockCount) return;
        GPUHTForwardBlockDescriptor desc = blocks[tid];

        uint sampleCount = uint(desc.width) * uint(desc.height);

        uint accumulator = 0u;
        device const uint* myCoeffs = coefficients + desc.coeffOffset;
        for (uint i = 0; i < sampleCount; i++) {
            uint v = myCoeffs[i];
            uint mag = v & 0x7FFFFFFFu;
            uint isSig = (mag != 0u) ? 1u : 0u;
            uint leadingZeros = (mag == 0u) ? 32u : clz(mag);
            accumulator = accumulator * 31u + isSig + (leadingZeros << 1);
        }

        uint outBytes = sampleCount >> 1;
        if (outBytes > desc.outputCapacity) {
            outBytes = desc.outputCapacity;
        }
        device uchar* myOut = output + desc.outputOffset;
        uchar payload = uchar(accumulator & 0xFFu);
        for (uint i = 0; i < outBytes; i++) {
            myOut[i] = payload;
        }
    }

    // MARK: - HTJ2K Forward Encode: per-sample classifier (v6-alpha6 phase 1)
    //
    // See J2KShaders.metal for the canonical documentation; this
    // inline copy stays bit-identical for the source-compile fallback
    // path (no `default.metallib`).

    struct GPUHTForwardClassifyDescriptor {
        uint coeffOffset;
        uint tupleOffset;
        uint sampleCount;
        uint p;
    };

    kernel void j2k_ht_forward_classify_samples(
        device const GPUHTForwardClassifyDescriptor* blocks       [[buffer(0)]],
        device const uint*                           coefficients [[buffer(1)]],
        device ulong*                                tuples       [[buffer(2)]],
        constant uint&                               blockCount   [[buffer(3)]],
        uint tid [[thread_position_in_grid]]
    ) {
        if (tid >= blockCount) return;
        GPUHTForwardClassifyDescriptor desc = blocks[tid];

        device const uint*  myCoeffs = coefficients + desc.coeffOffset;
        device ulong*       myTuples = tuples       + desc.tupleOffset;
        uint p = desc.p;

        for (uint i = 0; i < desc.sampleCount; i++) {
            uint t = myCoeffs[i];

            uint val = ((t << 1) >> p) & ~1u;

            ulong tuple;
            if (val == 0u) {
                tuple = 0;
            } else {
                uint valM1 = val - 1u;
                uint eQ = 32u - clz(valM1);
                uint sign = (t >> 31) & 1u;
                uint payload = (valM1 - 1u) + sign;
                tuple = (1uL << 63)
                      | ((ulong(eQ) & 0x7Fu) << 56)
                      | ulong(payload);
            }
            myTuples[i] = tuple;
        }
    }

    // MARK: - HTJ2K MagSgn forward bit reader (Phase 1)
    //
    // Per-codeblock MagSgn descriptor: layout matches the Swift
    // `J2KMetalHTMagSgnBlockDescriptor` struct field-for-field.
    struct GPUHTMagSgnDescriptor {
        uint dataOffset;     // byte offset into codestream pool
        uint dataLength;     // bytes available in this block
        uint widthsOffset;   // sample offset into widths pool (1 byte/sample)
        uint outputOffset;   // sample offset into output pool (1 uint/sample)
        uint sampleCount;    // number of samples to decode for this block
    };

    // MagSgn reader state — kept in registers for the duration of one
    // codeblock decode. Mirrors `HTMagSgnDecoderConformant`'s fields:
    //   - tmp:        bit buffer (LSB-first consumption)
    //   - bits:       valid bits in tmp
    //   - readIndex:  byte position relative to dataOffset
    //   - unstuff:    next byte's high bit is reserved (because previous == 0xFF)
    struct HTMagSgnState {
        ulong tmp;
        int   bits;
        int   readIndex;
        bool  unstuff;
    };

    // Refill the bit buffer so at least 32 bits are available, with
    // FF-stuff handling. `byteCount` is dataLength; reads past the end
    // synthesise 0xFF (matches CPU's post-EOF padding convention).
    inline void htMagSgnRefill(thread HTMagSgnState* s,
                               device const uchar* bytes,
                               uint byteCount)
    {
        while (s->bits <= 32) {
            uchar b;
            if ((uint)s->readIndex < byteCount) {
                b = bytes[s->readIndex];
                s->readIndex += 1;
            } else {
                b = 0xFF;
            }
            int  dBits = s->unstuff ? 7 : 8;
            uchar mask = s->unstuff ? (uchar)0x7F : (uchar)0xFF;
            ulong value = (ulong)(b & mask);
            s->tmp |= value << s->bits;
            s->bits += dBits;
            s->unstuff = (b == 0xFF);
        }
    }

    // Read `count` bits LSB-first. Mirrors `HTMagSgnDecoderConformant.read`.
    inline uint htMagSgnRead(thread HTMagSgnState* s,
                             device const uchar* bytes,
                             uint byteCount,
                             int count)
    {
        if (s->bits < count) {
            htMagSgnRefill(s, bytes, byteCount);
        }
        ulong mask = (count >= 64) ? (ulong)~(ulong)0 : (((ulong)1 << count) - 1);
        uint v = (uint)(s->tmp & mask);
        s->tmp >>= count;
        s->bits -= count;
        return v;
    }

    // Decode `desc.sampleCount` MagSgn samples for a single codeblock.
    // The widths array stores one byte per sample — the bit width to
    // consume from the MagSgn stream for that sample's reconstruction.
    // Output is one uint per sample (matches CPU's `[UInt32]` output).
    kernel void j2k_ht_magsgn_decode(
        device const GPUHTMagSgnDescriptor* blocks  [[buffer(0)]],
        device const uchar*                  codestream [[buffer(1)]],
        device const uchar*                  widths     [[buffer(2)]],
        device uint*                         output     [[buffer(3)]],
        constant uint&                       blockCount [[buffer(4)]],
        uint tid [[thread_position_in_grid]]
    ) {
        if (tid >= blockCount) return;
        GPUHTMagSgnDescriptor desc = blocks[tid];
        device const uchar* myBytes  = codestream + desc.dataOffset;
        device const uchar* myWidths = widths + desc.widthsOffset;
        device       uint*  myOut    = output + desc.outputOffset;

        HTMagSgnState s;
        s.tmp = 0;
        s.bits = 0;
        s.readIndex = 0;
        s.unstuff = false;

        for (uint i = 0; i < desc.sampleCount; i++) {
            int w = int(myWidths[i]);
            myOut[i] = htMagSgnRead(&s, myBytes, desc.dataLength, w);
        }
    }

    // MARK: - HTJ2K Cleanup-pass decoder (Phase 2)
    //
    // Per-codeblock descriptor for the full cleanup-pass kernel.
    // Field layout matches `J2KMetalHTCleanupBlockDescriptor` in
    // Swift exactly. All UInt32 fields → unambiguous 4-byte
    // alignment, stride 32 bytes.
    struct GPUHTCleanupDescriptor {
        uint magsgnOffset;
        uint magsgnLength;
        uint melVlcOffset;
        uint melVlcLength;       // == scup
        uint outputOffset;       // sample offset (uint per sample)
        uint width;
        uint height;
        uint missingMSBs;
    };

    // MEL state. Mirrors HTMELDecoderConformant — MSB-first bit buffer
    // top-aligned, `bits` is the number of valid bits, `state` indexes
    // the MEL exponent table.
    struct HTMELState {
        ulong tmp;
        int   bits;
        int   readIndex;
        bool  unstuff;
        int   state;
    };

    constant int melExp[13] = {0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5};

    inline void htMELRefill(thread HTMELState* s,
                            device const uchar* bytes, uint byteCount)
    {
        while (s->bits <= 32) {
            uchar b;
            if ((uint)s->readIndex < byteCount) {
                b = bytes[s->readIndex];
                s->readIndex += 1;
            } else {
                b = 0xFF;
            }
            int  dBits = s->unstuff ? 7 : 8;
            ulong value = (ulong)b & (((ulong)1 << dBits) - 1);
            s->tmp |= value << (64 - s->bits - dBits);
            s->bits += dBits;
            s->unstuff = (b == 0xFF);
        }
    }

    inline int htMELNextRun(thread HTMELState* s,
                            device const uchar* bytes, uint byteCount)
    {
        if (s->bits < 6) htMELRefill(s, bytes, byteCount);
        int eval = melExp[s->state];
        int run;
        if ((s->tmp & ((ulong)1 << 63)) != 0) {
            run = (1 << eval) - 1;
            s->state = min(12, s->state + 1);
            s->tmp <<= 1;
            s->bits -= 1;
            run <<= 1;             // low bit 0 → no terminator
        } else {
            int r = 0;
            if (eval > 0) {
                r = (int)((s->tmp >> (63 - eval)) & (ulong)((1 << eval) - 1));
            }
            s->state = max(0, s->state - 1);
            s->tmp <<= (eval + 1);
            s->bits -= (eval + 1);
            run = (r << 1) + 1;    // low bit 1 → terminator
        }
        return run;
    }

    inline bool htMELNextEvent(thread int* run,
                               thread HTMELState* s,
                               device const uchar* bytes, uint byteCount)
    {
        *run -= 2;
        bool isOne = (*run == -1);
        if (*run < 0) *run = htMELNextRun(s, bytes, byteCount);
        return isOne;
    }

    // VLC reverse reader. Reads from the END of the mel/vlc segment
    // backwards, LSB-first into `tmp`. Mirrors `VLCReverseReader`.
    struct VLCReverseState {
        ulong tmp;
        int   bits;
        int   byteIdx;        // counts down toward -1
        bool  unstuff;
    };

    inline void vlcReverseInit(thread VLCReverseState* s,
                               device const uchar* bytes, int scup)
    {
        s->tmp = 0;
        s->bits = 0;
        s->byteIdx = scup - 2;
        s->unstuff = false;
        if (s->byteIdx >= 0) {
            uchar b = bytes[s->byteIdx];
            ulong highNibble = (ulong)(b >> 4);
            ulong t = ((highNibble & 0x7) == 0x7) ? (ulong)1 : (ulong)0;
            ulong val = highNibble & ((ulong)0xF >> t);
            s->tmp = val;
            s->bits = (int)(4 - t);
            s->unstuff = val > 0x8;
            s->byteIdx -= 1;
        }
    }

    inline void vlcReverseRefill(thread VLCReverseState* s,
                                 device const uchar* bytes)
    {
        while (s->bits <= 32) {
            uchar b;
            if (s->byteIdx >= 0) {
                b = bytes[s->byteIdx];
                s->byteIdx -= 1;
            } else {
                b = 0;
            }
            int t = (s->unstuff && (((int)b) & 0x7F) == 0x7F) ? 1 : 0;
            int dBits = 8 - t;
            uchar mask = (t == 1) ? (uchar)0x7F : (uchar)0xFF;
            ulong value = (ulong)(b & mask);
            s->tmp |= value << s->bits;
            s->bits += dBits;
            s->unstuff = (b > 0x8F);
        }
    }

    inline ulong vlcReversePeek(thread VLCReverseState* s,
                                device const uchar* bytes,
                                int maxBits)
    {
        if (s->bits < maxBits) vlcReverseRefill(s, bytes);
        ulong m = (maxBits >= 64) ? (ulong)~(ulong)0 : (((ulong)1 << maxBits) - 1);
        return s->tmp & m;
    }

    inline ulong vlcReverseRead(thread VLCReverseState* s,
                                device const uchar* bytes,
                                int count)
    {
        if (s->bits < count) vlcReverseRefill(s, bytes);
        ulong m = (count >= 64) ? (ulong)~(ulong)0 : (((ulong)1 << count) - 1);
        ulong v = s->tmp & m;
        s->tmp >>= count;
        s->bits -= count;
        return v;
    }

    // VLC table lookup — same packed layout as the CPU side:
    //   bits  0-2: cwd_len
    //   bit   3:   u_off
    //   bits  4-7: rho
    //   bits  8-11: e_1
    //   bits 12-15: e_k
    inline void htLookupVLC(constant ushort* tbl, int c_q, int bits,
                            thread int* rho, thread int* u_off,
                            thread int* cwd_len, thread int* e_k,
                            thread int* e_1)
    {
        int idx = (c_q << 7) | (bits & 0x7F);
        int entry = (int)tbl[idx];
        *cwd_len = entry & 0x7;
        *u_off   = (entry >> 3) & 0x1;
        *rho     = (entry >> 4) & 0xF;
        *e_1     = (entry >> 8) & 0xF;
        *e_k     = (entry >> 12) & 0xF;
    }

    // Unary prefix: 1→1, 01→2, 001→3, 000→4.
    inline int htReadPrefix(thread VLCReverseState* s, device const uchar* bytes)
    {
        int b0 = (int)vlcReverseRead(s, bytes, 1);
        if (b0 == 1) return 1;
        int b1 = (int)vlcReverseRead(s, bytes, 1);
        if (b1 == 1) return 2;
        int b2 = (int)vlcReverseRead(s, bytes, 1);
        if (b2 == 1) return 3;
        return 4;
    }

    inline int htDecodeFromPrefix(int len,
                                  thread VLCReverseState* s,
                                  device const uchar* bytes)
    {
        if (len == 3) {
            int suf = (int)vlcReverseRead(s, bytes, 1);
            return 3 + suf;
        }
        if (len == 4) {
            int suf = (int)vlcReverseRead(s, bytes, 5);
            if (suf < 28) return 5 + suf;
            int ext = (int)vlcReverseRead(s, bytes, 4);
            return 33 + (suf - 28) + 4 * ext;
        }
        return len;
    }

    // Initial-row UVLC pair — mirrors decodeUVLCPairInitial.
    inline void htDecodeUVLCPairInitial(int u_off0, int u_off1,
                                        thread int* u0_out, thread int* u1_out,
                                        thread VLCReverseState* vs,
                                        device const uchar* mvBytes,
                                        thread int* melRun,
                                        thread HTMELState* ms,
                                        device const uchar* mvBytesForMEL,
                                        uint mvByteCount)
    {
        if (u_off0 == 0 && u_off1 == 0) { *u0_out = 0; *u1_out = 0; return; }
        if (u_off0 == 1 && u_off1 == 1) {
            bool melEvent = htMELNextEvent(melRun, ms, mvBytesForMEL, mvByteCount);
            if (melEvent) {
                int p0 = htReadPrefix(vs, mvBytes);
                int p1 = htReadPrefix(vs, mvBytes);
                int s0 = htDecodeFromPrefix(p0, vs, mvBytes);
                int s1 = htDecodeFromPrefix(p1, vs, mvBytes);
                *u0_out = s0 + 2; *u1_out = s1 + 2; return;
            }
            int p0 = htReadPrefix(vs, mvBytes);
            if (p0 >= 3) {
                int bit = (int)vlcReverseRead(vs, mvBytes, 1);
                int u0v = htDecodeFromPrefix(p0, vs, mvBytes);
                *u0_out = u0v; *u1_out = bit + 1; return;
            }
            int p1 = htReadPrefix(vs, mvBytes);
            int u0v = htDecodeFromPrefix(p0, vs, mvBytes);
            int u1v = htDecodeFromPrefix(p1, vs, mvBytes);
            *u0_out = u0v; *u1_out = u1v; return;
        }
        *u0_out = (u_off0 != 0) ? htDecodeFromPrefix(htReadPrefix(vs, mvBytes), vs, mvBytes) : 0;
        *u1_out = (u_off1 != 0) ? htDecodeFromPrefix(htReadPrefix(vs, mvBytes), vs, mvBytes) : 0;
    }

    // Subsequent-row UVLC: encoder writes pre0, pre1, suf0, suf1 in
    // that order unconditionally — read both prefixes first.
    inline void htDecodeUVLCPairSubsequent(int u_off0, int u_off1,
                                           thread int* u0_out, thread int* u1_out,
                                           thread VLCReverseState* vs,
                                           device const uchar* mvBytes)
    {
        int len0 = (u_off0 != 0) ? htReadPrefix(vs, mvBytes) : 0;
        int len1 = (u_off1 != 0) ? htReadPrefix(vs, mvBytes) : 0;
        *u0_out = (u_off0 != 0) ? htDecodeFromPrefix(len0, vs, mvBytes) : 0;
        *u1_out = (u_off1 != 0) ? htDecodeFromPrefix(len1, vs, mvBytes) : 0;
    }

    // Read MagSgn bits per significant sample of the quad and place
    // reconstructed sign-magnitude UInt32 coefficients into `coefs`.
    inline void htReadQuadSamples(int baseX, int baseY,
                                  int rho, int Uq, int e_k, int e_1, uint p,
                                  uint width, uint height,
                                  thread HTMagSgnState* ms,
                                  device const uchar* msBytes,
                                  uint msByteCount,
                                  device uint* coefs)
    {
        // (col, row) = [(0,0), (0,1), (1,0), (1,1)] indexed by i = 2*col+row.
        for (int i = 0; i < 4; i++) {
            int bit = (rho >> i) & 1;
            if (bit == 0) continue;
            int eBit = (e_k >> i) & 1;
            int e1Bit = (e_1 >> i) & 1;
            int m = Uq - eBit;
            uint payload = htMagSgnRead(ms, msBytes, msByteCount, m);
            uint sign = payload & 1;
            uint mask = (m >= 32) ? (uint)~(uint)0 : (((uint)1 << m) - 1);
            uint v_n = payload & mask;
            v_n |= ((uint)e1Bit) << m;
            v_n |= 1;
            int dx = (i >> 1) & 1;     // (i / 2) % 2
            int dy = i & 1;            // i % 2
            int xi = baseX + dx;
            int yi = baseY + dy;
            if ((uint)xi >= width || (uint)yi >= height) continue;
            uint coef = (v_n + 2) << (p - 1);
            if (sign != 0) coef |= 0x80000000u;
            coefs[yi * width + xi] = coef;
        }
    }

    // Recover the per-quad e_q values from the reconstructed coefs.
    // Returns 4 ints packed (eQ0, eQ1, eQ2, eQ3).
    inline void htRecoverEQ(int rho, int baseX, int baseY,
                            uint p, uint width, uint height,
                            device const uint* coefs,
                            thread int* outEQ0, thread int* outEQ1,
                            thread int* outEQ2, thread int* outEQ3)
    {
        *outEQ0 = 0; *outEQ1 = 0; *outEQ2 = 0; *outEQ3 = 0;
        for (int i = 0; i < 4; i++) {
            if (((rho >> i) & 1) == 0) continue;
            int dx = (i >> 1) & 1;
            int dy = i & 1;
            int xi = baseX + dx;
            int yi = baseY + dy;
            if ((uint)xi >= width || (uint)yi >= height) continue;
            uint mag = coefs[yi * width + xi] & 0x7FFFFFFFu;
            uint v_n = (mag >> (p - 1)) - 2u;
            uint twoMuMinusOne = v_n | 1u;
            int eQ = 32 - clz(twoMuMinusOne);
            if (i == 0) *outEQ0 = eQ;
            else if (i == 1) *outEQ1 = eQ;
            else if (i == 2) *outEQ2 = eQ;
            else *outEQ3 = eQ;
        }
    }

    // Initial row decoder — uses VLC table 0 with implicit kappa=1.
    inline void htDecodeInitialRow(uint width, uint height, uint p,
                                   thread HTMagSgnState* ms,
                                   device const uchar* msBytes, uint msByteCount,
                                   thread VLCReverseState* vs,
                                   device const uchar* mvBytes,
                                   uint mvByteCount,
                                   thread HTMELState* mel,
                                   thread int* melRun,
                                   thread uchar* eVal, thread uchar* cxVal,
                                   constant ushort* vlcTbl0,
                                   device uint* coefs)
    {
        int lep = 0;
        int lcxp = 0;
        int c_q0 = 0;
        int x = 0;
        while ((uint)x < width) {
            int rho0 = 0;
            int u_off0 = 0; int cwd_len0 = 0; int e_k0 = 0; int e_1_0 = 0;
            if (c_q0 == 0) {
                if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                    int head = (int)vlcReversePeek(vs, mvBytes, 7);
                    htLookupVLC(vlcTbl0, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
                    (void)vlcReverseRead(vs, mvBytes, cwd_len0);
                }
            } else {
                int head = (int)vlcReversePeek(vs, mvBytes, 7);
                htLookupVLC(vlcTbl0, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
                (void)vlcReverseRead(vs, mvBytes, cwd_len0);
            }

            int rho1 = 0;
            int u_off1 = 0; int cwd_len1 = 0; int e_k1 = 0; int e_1_1 = 0;
            if ((uint)(x + 2) < width) {
                int c_q1 = (rho0 >> 1) | (rho0 & 1);
                if (c_q1 == 0) {
                    if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                        int head = (int)vlcReversePeek(vs, mvBytes, 7);
                        htLookupVLC(vlcTbl0, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                        (void)vlcReverseRead(vs, mvBytes, cwd_len1);
                    }
                } else {
                    int head = (int)vlcReversePeek(vs, mvBytes, 7);
                    htLookupVLC(vlcTbl0, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                    (void)vlcReverseRead(vs, mvBytes, cwd_len1);
                }
            }

            int u0 = 0, u1 = 0;
            htDecodeUVLCPairInitial(rho0 != 0 ? u_off0 : 0,
                                    rho1 != 0 ? u_off1 : 0,
                                    &u0, &u1,
                                    vs, mvBytes,
                                    melRun, mel, mvBytes, mvByteCount);
            int Uq0 = u0 + 1, Uq1 = u1 + 1;

            htReadQuadSamples(x, 0, rho0, Uq0, e_k0, e_1_0, p, width, height, ms, msBytes, msByteCount, coefs);
            if ((uint)(x + 2) < width) {
                htReadQuadSamples(x + 2, 0, rho1, Uq1, e_k1, e_1_1, p, width, height, ms, msBytes, msByteCount, coefs);
            }

            int eQ0_0, eQ0_1, eQ0_2, eQ0_3;
            htRecoverEQ(rho0, x, 0, p, width, height, coefs, &eQ0_0, &eQ0_1, &eQ0_2, &eQ0_3);
            eVal[lep] = max(eVal[lep], (uchar)eQ0_1); lep += 1;
            eVal[lep] = (uchar)eQ0_3;
            cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho0 & 2) >> 1)); lcxp += 1;
            cxVal[lcxp] = (uchar)((rho0 & 8) >> 3);
            if ((uint)(x + 2) < width) {
                int eQ1_0, eQ1_1, eQ1_2, eQ1_3;
                htRecoverEQ(rho1, x + 2, 0, p, width, height, coefs, &eQ1_0, &eQ1_1, &eQ1_2, &eQ1_3);
                eVal[lep] = max(eVal[lep], (uchar)eQ1_1); lep += 1;
                eVal[lep] = (uchar)eQ1_3;
                cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho1 & 2) >> 1)); lcxp += 1;
                cxVal[lcxp] = (uchar)((rho1 & 8) >> 3);
            }

            c_q0 = (rho1 >> 1) | (rho1 & 1);
            x += 4;
        }
        // Sentinel — eVal capacity is at least lep + 2 by construction.
        eVal[lep + 1] = 0;
    }

    // Subsequent row decoder — uses VLC table 1 with kappa from maxE.
    inline void htDecodeSubsequentRow(int y, uint width, uint height, uint p,
                                      thread HTMagSgnState* ms,
                                      device const uchar* msBytes, uint msByteCount,
                                      thread VLCReverseState* vs,
                                      device const uchar* mvBytes,
                                      uint mvByteCount,
                                      thread HTMELState* mel,
                                      thread int* melRun,
                                      thread uchar* eVal, thread uchar* cxVal,
                                      constant ushort* vlcTbl1,
                                      device uint* coefs)
    {
        int lep = 0;
        int lcxp = 0;
        int maxE = max((int)eVal[0], (int)eVal[1]) - 1;
        eVal[0] = 0;
        int c_q0 = (int)cxVal[0] + ((int)cxVal[1] << 2);
        cxVal[0] = 0;
        int x = 0;
        while ((uint)x < width) {
            int rho0 = 0;
            int u_off0 = 0; int cwd_len0 = 0; int e_k0 = 0; int e_1_0 = 0;
            if (c_q0 == 0) {
                if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                    int head = (int)vlcReversePeek(vs, mvBytes, 7);
                    htLookupVLC(vlcTbl1, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
                    (void)vlcReverseRead(vs, mvBytes, cwd_len0);
                }
            } else {
                int head = (int)vlcReversePeek(vs, mvBytes, 7);
                htLookupVLC(vlcTbl1, c_q0, head, &rho0, &u_off0, &cwd_len0, &e_k0, &e_1_0);
                (void)vlcReverseRead(vs, mvBytes, cwd_len0);
            }
            int kappaA = ((rho0 & (rho0 - 1)) != 0) ? max(1, maxE) : 1;

            // Advance lcxp partially to discover c_q1's source slot.
            cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho0 & 2) >> 1)); lcxp += 1;
            int c_q1 = (int)cxVal[lcxp] + ((int)cxVal[lcxp + 1] << 2);
            cxVal[lcxp] = (uchar)((rho0 & 8) >> 3);

            int rho1 = 0;
            int u_off1 = 0; int cwd_len1 = 0; int e_k1 = 0; int e_1_1 = 0;
            if ((uint)(x + 2) < width) {
                c_q1 |= ((rho0 & 4) >> 1) | ((rho0 & 8) >> 2);
                if (c_q1 == 0) {
                    if (htMELNextEvent(melRun, mel, mvBytes, mvByteCount)) {
                        int head = (int)vlcReversePeek(vs, mvBytes, 7);
                        htLookupVLC(vlcTbl1, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                        (void)vlcReverseRead(vs, mvBytes, cwd_len1);
                    }
                } else {
                    int head = (int)vlcReversePeek(vs, mvBytes, 7);
                    htLookupVLC(vlcTbl1, c_q1, head, &rho1, &u_off1, &cwd_len1, &e_k1, &e_1_1);
                    (void)vlcReverseRead(vs, mvBytes, cwd_len1);
                }
                cxVal[lcxp] = (uchar)(cxVal[lcxp] | (uchar)((rho1 & 2) >> 1)); lcxp += 1;
                c_q0 = (int)cxVal[lcxp] + ((int)cxVal[lcxp + 1] << 2);
                cxVal[lcxp] = (uchar)((rho1 & 8) >> 3);
            }

            int u0 = 0, u1 = 0;
            htDecodeUVLCPairSubsequent(rho0 != 0 ? u_off0 : 0,
                                       rho1 != 0 ? u_off1 : 0,
                                       &u0, &u1, vs, mvBytes);

            int Uq0 = u0 + kappaA;
            htReadQuadSamples(x, y, rho0, Uq0, e_k0, e_1_0, p, width, height, ms, msBytes, msByteCount, coefs);

            int eQ0_0, eQ0_1, eQ0_2, eQ0_3;
            htRecoverEQ(rho0, x, y, p, width, height, coefs, &eQ0_0, &eQ0_1, &eQ0_2, &eQ0_3);
            eVal[lep] = max(eVal[lep], (uchar)eQ0_1); lep += 1;
            int maxEAfterQ0 = max((int)eVal[lep], (int)eVal[lep + 1]) - 1;
            eVal[lep] = (uchar)eQ0_3;

            int kappaB = 1;
            if ((uint)(x + 2) < width) {
                kappaB = ((rho1 & (rho1 - 1)) != 0) ? max(1, maxEAfterQ0) : 1;
                int Uq1 = u1 + kappaB;
                htReadQuadSamples(x + 2, y, rho1, Uq1, e_k1, e_1_1, p, width, height, ms, msBytes, msByteCount, coefs);

                int eQ1_0, eQ1_1, eQ1_2, eQ1_3;
                htRecoverEQ(rho1, x + 2, y, p, width, height, coefs, &eQ1_0, &eQ1_1, &eQ1_2, &eQ1_3);
                eVal[lep] = max(eVal[lep], (uchar)eQ1_1); lep += 1;
                maxE = max((int)eVal[lep], (int)eVal[lep + 1]) - 1;
                eVal[lep] = (uchar)eQ1_3;
            } else {
                maxE = maxEAfterQ0;
            }

            c_q0 |= ((rho1 & 4) >> 1) | ((rho1 & 8) >> 2);
            x += 4;
        }
    }

    // Top-level cleanup-pass kernel. One thread per codeblock.
    // VLC tables are passed in `[[buffer(N)]]`; on Apple GPUs they
    // land in unified memory but get cached aggressively after the
    // first lookup.
    kernel void j2k_ht_cleanup_decode(
        device const GPUHTCleanupDescriptor* blocks      [[buffer(0)]],
        device const uchar*                  codestream  [[buffer(1)]],
        constant ushort*                     vlcTbl0     [[buffer(2)]],
        constant ushort*                     vlcTbl1     [[buffer(3)]],
        device uint*                         output      [[buffer(4)]],
        constant uint&                       blockCount  [[buffer(5)]],
        uint tid [[thread_position_in_grid]]
    ) {
        if (tid >= blockCount) return;
        GPUHTCleanupDescriptor desc = blocks[tid];

        uint width  = desc.width;
        uint height = desc.height;
        uint p      = (uint)(30 - (int)desc.missingMSBs);

        device const uchar* msBytes = codestream + desc.magsgnOffset;
        device const uchar* mvBytes = codestream + desc.melVlcOffset;
        device       uint*  myCoefs = output + desc.outputOffset;

        // Zero the output region — readQuadSamples only writes
        // significant samples; insignificant ones stay 0.
        uint sampleCount = width * height;
        for (uint i = 0; i < sampleCount; i++) myCoefs[i] = 0;

        // State init.
        HTMagSgnState ms; ms.tmp = 0; ms.bits = 0; ms.readIndex = 0; ms.unstuff = false;
        HTMELState mel; mel.tmp = 0; mel.bits = 0; mel.readIndex = 0; mel.unstuff = false; mel.state = 0;
        VLCReverseState vs; vlcReverseInit(&vs, mvBytes, (int)desc.melVlcLength);
        int melRun = htMELNextRun(&mel, mvBytes, desc.melVlcLength);

        // Per-row scratch — at most ((width + 3)/4)*2 + 2 entries.
        // For width <= 64 (typical codeblock max), 34 fits.
        uchar eVal[34];
        uchar cxVal[34];
        for (int i = 0; i < 34; i++) { eVal[i] = 0; cxVal[i] = 0; }

        htDecodeInitialRow(width, height, p, &ms, msBytes, desc.magsgnLength,
                           &vs, mvBytes, desc.melVlcLength,
                           &mel, &melRun, eVal, cxVal, vlcTbl0, myCoefs);

        for (int y = 2; (uint)y < height; y += 2) {
            htDecodeSubsequentRow(y, width, height, p, &ms, msBytes, desc.magsgnLength,
                                  &vs, mvBytes, desc.melVlcLength,
                                  &mel, &melRun, eVal, cxVal, vlcTbl1, myCoefs);
        }
    }

    // MARK: - HT dequantisation
    //
    // Per-sample conversion of the HT cleanup kernel's UInt32
    // OpenJPH sign-magnitude output to Int32 integer-magnitude.
    // Mirrors the CPU dequant in J2KHTConformantDispatch.swift:
    //
    //   shift = 30 - missingMSBs
    //   sign  = (uint & 0x80000000) != 0
    //   mag   = (uint & 0x7FFFFFFF) >> shift
    //   out   = sign ? -mag : mag
    //
    // Dispatch grid: (maxSamplesPerBlock, blockCount). Each thread
    // handles one sample of one block. Bounds-checked against the
    // block's own width × height since blocks have varying sizes.

    kernel void j2k_ht_dequant(
        device const GPUHTCleanupDescriptor* blocks      [[buffer(0)]],
        device const uint*                   sgnMag      [[buffer(1)]],
        device int*                          output      [[buffer(2)]],
        constant uint&                       blockCount  [[buffer(3)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint blockIdx = gid.y;
        if (blockIdx >= blockCount) return;
        GPUHTCleanupDescriptor desc = blocks[blockIdx];
        uint sampleCount = desc.width * desc.height;
        uint sampleIdx = gid.x;
        if (sampleIdx >= sampleCount) return;

        uint outOffset = desc.outputOffset + sampleIdx;
        uint val = sgnMag[outOffset];
        uint shift = (uint)(30 - (int)desc.missingMSBs);
        bool isNeg = (val & 0x80000000u) != 0;
        int mag = (int)((val & 0x7FFFFFFFu) >> shift);
        output[outOffset] = isNeg ? -mag : mag;
    }

    // MARK: - Subband scatter (v5.7.0)
    //
    // Per-codeblock placement metadata. One descriptor per
    // codeblock per scatter dispatch. The kernel reads
    // `blockWidth × blockHeight` Int32 samples starting at
    // `codeblockOffset` and writes them into the destination
    // subband buffer at (subbandX + col, subbandY + row), respecting
    // `subbandStride` as the row pitch. `targetSubband` selects
    // which of the 4 bound buffers (LL/LH/HL/HH) to write to.
    //
    // Layout matches the J2KMetalSubbandScatterDescriptor Swift
    // struct field-for-field; @frozen on the Swift side locks the
    // order so release-mode optimisation can't reorder.

    struct GPUScatterDescriptor {
        uint codeblockOffset;     // Int32 offset into the source codeblock buffer
        uint blockWidth;          // codeblock width in samples
        uint blockHeight;         // codeblock height in samples
        uint subbandX;            // x position of this block within its target subband
        uint subbandY;            // y position
        uint subbandStride;       // row pitch of the target subband buffer (= subband width)
        uint targetSubband;       // 0=LL, 1=LH, 2=HL, 3=HH
        uint _pad;                // align to 32 bytes for stride consistency
    };

    kernel void j2k_subband_scatter(
        device const GPUScatterDescriptor* descs        [[buffer(0)]],
        device const int*                  codeblocks   [[buffer(1)]],
        device int*                        llOut        [[buffer(2)]],
        device int*                        lhOut        [[buffer(3)]],
        device int*                        hlOut        [[buffer(4)]],
        device int*                        hhOut        [[buffer(5)]],
        constant uint&                     descCount    [[buffer(6)]],
        uint3 gid [[thread_position_in_grid]]
    ) {
        uint blockIdx = gid.z;
        if (blockIdx >= descCount) return;
        GPUScatterDescriptor d = descs[blockIdx];
        uint col = gid.x;
        uint row = gid.y;
        if (col >= d.blockWidth || row >= d.blockHeight) return;

        uint srcIdx = d.codeblockOffset + row * d.blockWidth + col;
        uint dstX = d.subbandX + col;
        uint dstY = d.subbandY + row;
        uint dstIdx = dstY * d.subbandStride + dstX;
        int value = codeblocks[srcIdx];

        // Branchless dispatch on target subband. Each thread writes
        // to exactly one buffer; the others are untouched. The
        // unbound branches are dead code paths chosen at compile
        // time per dispatched grid cell — no warp divergence, since
        // all threads of the same block share the same
        // d.targetSubband.
        if (d.targetSubband == 0) llOut[dstIdx] = value;
        else if (d.targetSubband == 1) lhOut[dstIdx] = value;
        else if (d.targetSubband == 2) hlOut[dstIdx] = value;
        else hhOut[dstIdx] = value;
    }

    // MARK: - Subband scatter + dequant (Float, v5.26.0)
    //
    // Mirror of j2k_subband_scatter for the 9/7 lossy fused-from-
    // codeblocks path: reads Int32 codeblocks, applies HTJ2K
    // conformant cleanup-only dequantisation, writes Float to the
    // per-subband 2D buffers.

    struct GPUScatterDescriptorFloat {
        uint  codeblockOffset;
        uint  blockWidth;
        uint  blockHeight;
        uint  subbandX;
        uint  subbandY;
        uint  subbandStride;
        uint  targetSubband;
        float stepSize;
    };

    kernel void j2k_subband_scatter_float_dequant(
        device const GPUScatterDescriptorFloat* descs        [[buffer(0)]],
        device const int*                       codeblocks   [[buffer(1)]],
        device float*                           llOut        [[buffer(2)]],
        device float*                           lhOut        [[buffer(3)]],
        device float*                           hlOut        [[buffer(4)]],
        device float*                           hhOut        [[buffer(5)]],
        constant uint&                          descCount    [[buffer(6)]],
        uint3 gid [[thread_position_in_grid]]
    ) {
        uint blockIdx = gid.z;
        if (blockIdx >= descCount) return;
        GPUScatterDescriptorFloat d = descs[blockIdx];
        uint col = gid.x;
        uint row = gid.y;
        if (col >= d.blockWidth || row >= d.blockHeight) return;

        uint srcIdx = d.codeblockOffset + row * d.blockWidth + col;
        uint dstX = d.subbandX + col;
        uint dstY = d.subbandY + row;
        uint dstIdx = dstY * d.subbandStride + dstX;
        int coeff = codeblocks[srcIdx];

        float value;
        if (coeff == 0) {
            value = 0.0f;
        } else if (coeff > 0) {
            value = (float(coeff) + 0.5f) * d.stepSize;
        } else {
            value = (float(coeff) - 0.5f) * d.stepSize;
        }

        if (d.targetSubband == 0) llOut[dstIdx] = value;
        else if (d.targetSubband == 1) lhOut[dstIdx] = value;
        else if (d.targetSubband == 2) hlOut[dstIdx] = value;
        else hhOut[dstIdx] = value;
    }

    // MARK: - v7.1.0 I1.1 — inclusive prefix-sum (Pass 2 of approach C)
    //
    // Single-threadgroup two-level scan. simd_prefix_inclusive_sum
    // within each warp; the last lane of each warp publishes its
    // total to threadgroup memory; warp 0 then exclusive-scans those
    // totals; finally each thread adds its warp's prefix back to the
    // intra-warp prefix to get the global inclusive scan.
    //
    // Mirrors the source kept in Sources/J2KMetal/J2KShaders.metal —
    // duplicated here for the inline source-compile fallback path
    // (taken when the bundled default.metallib can't be loaded).

    kernel void j2k_prefix_sum_inclusive_uint32(
        device const uint* input  [[buffer(0)]],
        device       uint* output [[buffer(1)]],
        constant     uint& n      [[buffer(2)]],
        uint tid       [[thread_position_in_threadgroup]],
        uint sg_id     [[simdgroup_index_in_threadgroup]],
        uint sg_lane   [[thread_index_in_simdgroup]],
        uint sg_size   [[threads_per_simdgroup]],
        uint tg_size   [[threads_per_threadgroup]]
    ) {
        uint v = (tid < n) ? input[tid] : 0u;
        uint psum = simd_prefix_inclusive_sum(v);
        threadgroup uint sg_totals[32];
        if (sg_lane == sg_size - 1u) sg_totals[sg_id] = psum;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        uint num_warps = (tg_size + sg_size - 1u) / sg_size;
        if (sg_id == 0u) {
            uint t = (sg_lane < num_warps) ? sg_totals[sg_lane] : 0u;
            uint pt = simd_prefix_exclusive_sum(t);
            if (sg_lane < num_warps) sg_totals[sg_lane] = pt;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        psum += sg_totals[sg_id];
        if (tid < n) output[tid] = psum;
    }

    // MARK: - v7.1.0 I1.2 — Pass 3 MagSgn byte-write (single-block spike)
    //
    // Per-block serial bit-emitter. One threadgroup per block; thread 0
    // does the inherently-serial work, the rest of the warp idles.
    // Inline FF-stuffing matches HTMagSgnEncoderConformant byte-for-byte.
    //
    // Mirrors the source kept in Sources/J2KMetal/J2KShaders.metal —
    // duplicated here for the inline source-compile fallback path.

    kernel void j2k_ht_magsgn_emit_block(
        device const uint2* items         [[buffer(0)]],
        constant     uint&  itemCount     [[buffer(1)]],
        device       uchar* output        [[buffer(2)]],
        constant     uint&  outputOffset  [[buffer(3)]],
        device       uint*  byteCountOut  [[buffer(4)]],
        uint tid                          [[thread_position_in_threadgroup]]
    ) {
        if (tid != 0u) return;
        uint tmp = 0u;
        uint usedBits = 0u;
        uint maxBits = 8u;
        uint byteIdx = 0u;
        for (uint i = 0u; i < itemCount; ++i) {
            uint cwd = items[i].x;
            uint len = items[i].y;
            while (len > 0u) {
                uint take = min(maxBits - usedBits, len);
                uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
                tmp |= (cwd & mask) << usedBits;
                usedBits += take;
                cwd >>= take;
                len -= take;
                if (usedBits >= maxBits) {
                    uint b = tmp & 0xFFu;
                    output[outputOffset + byteIdx] = (uchar)b;
                    byteIdx += 1u;
                    maxBits = (b == 0xFFu) ? 7u : 8u;
                    tmp = 0u;
                    usedBits = 0u;
                }
            }
        }
        if (usedBits != 0u) {
            uint padBits = maxBits - usedBits;
            uint padMask = (padBits >= 32u) ? 0xFFFFFFFFu : ((1u << padBits) - 1u);
            tmp |= padMask << usedBits;
            uint b = tmp & 0xFFu;
            if (b != 0xFFu) {
                output[outputOffset + byteIdx] = (uchar)b;
                byteIdx += 1u;
            }
        } else if (maxBits == 7u) {
            byteIdx -= 1u;
        }
        *byteCountOut = byteIdx;
    }

    // MARK: - v7.1.0 I1.2b — Pass 3 MagSgn batched byte-write (multi-block dispatch)
    //
    // Inline source-compile fallback duplicate of the kernel kept in
    // Sources/J2KMetal/J2KShaders.metal. One threadgroup per block;
    // ~2,300 blocks per DX 2x2 tile run concurrently on Apple M2.

    kernel void j2k_ht_magsgn_emit_blocks_batched(
        device const uint2* items                [[buffer(0)]],
        device const uint2* blockDescriptors     [[buffer(1)]],
        device const uint*  outputOffsets        [[buffer(2)]],
        device       uchar* output               [[buffer(3)]],
        device       uint*  byteCountsOut        [[buffer(4)]],
        constant     uint&  blockCount           [[buffer(5)]],
        uint tid                                 [[thread_position_in_threadgroup]],
        uint tgIdx                               [[threadgroup_position_in_grid]]
    ) {
        if (tgIdx >= blockCount) return;
        if (tid != 0u) return;
        const uint2 desc = blockDescriptors[tgIdx];
        const uint itemStart = desc.x;
        const uint itemCount = desc.y;
        const uint outputOffset = outputOffsets[tgIdx];
        uint tmp = 0u;
        uint usedBits = 0u;
        uint maxBits = 8u;
        uint byteIdx = 0u;
        for (uint i = 0u; i < itemCount; ++i) {
            uint cwd = items[itemStart + i].x;
            uint len = items[itemStart + i].y;
            while (len > 0u) {
                uint take = min(maxBits - usedBits, len);
                uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
                tmp |= (cwd & mask) << usedBits;
                usedBits += take;
                cwd >>= take;
                len -= take;
                if (usedBits >= maxBits) {
                    uint b = tmp & 0xFFu;
                    output[outputOffset + byteIdx] = (uchar)b;
                    byteIdx += 1u;
                    maxBits = (b == 0xFFu) ? 7u : 8u;
                    tmp = 0u;
                    usedBits = 0u;
                }
            }
        }
        if (usedBits != 0u) {
            uint padBits = maxBits - usedBits;
            uint padMask = (padBits >= 32u) ? 0xFFFFFFFFu : ((1u << padBits) - 1u);
            tmp |= padMask << usedBits;
            uint b = tmp & 0xFFu;
            if (b != 0xFFu) {
                output[outputOffset + byteIdx] = (uchar)b;
                byteIdx += 1u;
            }
        } else if (maxBits == 7u) {
            byteIdx -= 1u;
        }
        byteCountsOut[tgIdx] = byteIdx;
    }

    // MARK: - v7.1.0 I1.2c — Pass 3 MEL batched byte-write
    //
    // MSB-first bit packer with FF-stuff but no rollback / no FF-drop
    // on terminate (vs MagSgn's LSB-first packer with both). Inline
    // source-compile fallback duplicate.

    kernel void j2k_ht_mel_emit_blocks_batched(
        device const uint2* items                [[buffer(0)]],
        device const uint2* blockDescriptors     [[buffer(1)]],
        device const uint*  outputOffsets        [[buffer(2)]],
        device       uchar* output               [[buffer(3)]],
        device       uint*  byteCountsOut        [[buffer(4)]],
        constant     uint&  blockCount           [[buffer(5)]],
        uint tid                                 [[thread_position_in_threadgroup]],
        uint tgIdx                               [[threadgroup_position_in_grid]]
    ) {
        if (tgIdx >= blockCount) return;
        if (tid != 0u) return;
        const uint2 desc = blockDescriptors[tgIdx];
        const uint itemStart = desc.x;
        const uint itemCount = desc.y;
        const uint outputOffset = outputOffsets[tgIdx];
        uint tmp = 0u;
        uint remainingBits = 8u;
        uint byteIdx = 0u;
        for (uint i = 0u; i < itemCount; ++i) {
            uint cwd = items[itemStart + i].x;
            uint c   = items[itemStart + i].y;
            while (c > 0u) {
                c -= 1u;
                uint bit = (cwd >> c) & 1u;
                tmp = (tmp << 1) | bit;
                remainingBits -= 1u;
                if (remainingBits == 0u) {
                    uint b = tmp & 0xFFu;
                    output[outputOffset + byteIdx] = (uchar)b;
                    byteIdx += 1u;
                    remainingBits = (b == 0xFFu) ? 7u : 8u;
                    tmp = 0u;
                }
            }
        }
        if (remainingBits != 8u) {
            tmp <<= remainingBits;
            output[outputOffset + byteIdx] = (uchar)(tmp & 0xFFu);
            byteIdx += 1u;
        }
        byteCountsOut[tgIdx] = byteIdx;
    }

    // MARK: - v7.1.0 I1.2d — Pass 3 VLC batched byte-write (reverse stream)
    //
    // LSB-first within each byte; bytes built forward in emit order,
    // then reversed in-place at end. `lastGreaterThan8F` reverse-stuff
    // rule with the deferred-stuff release when low-7 bits != 0x7F.

    kernel void j2k_ht_vlc_emit_blocks_batched(
        device const uint2* items                [[buffer(0)]],
        device const uint2* blockDescriptors     [[buffer(1)]],
        device const uint*  outputOffsets        [[buffer(2)]],
        device       uchar* output               [[buffer(3)]],
        device       uint*  byteCountsOut        [[buffer(4)]],
        constant     uint&  blockCount           [[buffer(5)]],
        uint tid                                 [[thread_position_in_threadgroup]],
        uint tgIdx                               [[threadgroup_position_in_grid]]
    ) {
        if (tgIdx >= blockCount) return;
        if (tid != 0u) return;
        const uint2 desc = blockDescriptors[tgIdx];
        const uint itemStart = desc.x;
        const uint itemCount = desc.y;
        const uint outputOffset = outputOffsets[tgIdx];
        output[outputOffset + 0u] = (uchar)0xFFu;
        uint byteIdx = 1u;
        uint tmp = 0x0Fu;
        uint usedBits = 4u;
        bool lastGreaterThan8F = true;
        for (uint i = 0u; i < itemCount; ++i) {
            uint cwd = items[itemStart + i].x;
            uint len = items[itemStart + i].y;
            while (len > 0u) {
                uint stuffPenalty = lastGreaterThan8F ? 1u : 0u;
                uint availBits = 8u - stuffPenalty - usedBits;
                uint take = min(availBits, len);
                if (take > 0u) {
                    uint mask = (take >= 32u) ? 0xFFFFFFFFu : ((1u << take) - 1u);
                    tmp |= (cwd & mask) << usedBits;
                    usedBits += take;
                    cwd >>= take;
                    len -= take;
                }
                uint remainingAfter = availBits - take;
                if (remainingAfter == 0u) {
                    if (lastGreaterThan8F && tmp != 0x7Fu) {
                        lastGreaterThan8F = false;
                        continue;
                    }
                    output[outputOffset + byteIdx] = (uchar)(tmp & 0xFFu);
                    byteIdx += 1u;
                    lastGreaterThan8F = (tmp > 0x8Fu);
                    tmp = 0u;
                    usedBits = 0u;
                }
            }
        }
        if (usedBits > 0u) {
            output[outputOffset + byteIdx] = (uchar)(tmp & 0xFFu);
            byteIdx += 1u;
        }
        for (uint i = 0u; i < byteIdx / 2u; ++i) {
            uchar a = output[outputOffset + i];
            uchar b = output[outputOffset + byteIdx - 1u - i];
            output[outputOffset + i] = b;
            output[outputOffset + byteIdx - 1u - i] = a;
        }
        byteCountsOut[tgIdx] = byteIdx;
    }
    """
}
