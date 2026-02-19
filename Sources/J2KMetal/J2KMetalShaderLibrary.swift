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
    /// Inverse 5/3 reversible wavelet transform (horizontal).
    case dwtInverse53Horizontal = "j2k_dwt_inverse_53_horizontal"
    /// Inverse 5/3 reversible wavelet transform (vertical).
    case dwtInverse53Vertical = "j2k_dwt_inverse_53_vertical"
    /// Forward 9/7 irreversible wavelet transform (horizontal).
    case dwtForward97Horizontal = "j2k_dwt_forward_97_horizontal"
    /// Forward 9/7 irreversible wavelet transform (vertical).
    case dwtForward97Vertical = "j2k_dwt_forward_97_vertical"
    /// Inverse 9/7 irreversible wavelet transform (horizontal).
    case dwtInverse97Horizontal = "j2k_dwt_inverse_97_horizontal"
    /// Inverse 9/7 irreversible wavelet transform (vertical).
    case dwtInverse97Vertical = "j2k_dwt_inverse_97_vertical"
    /// Forward ICT color transform (RGB → YCbCr).
    case ictForward = "j2k_ict_forward"
    /// Inverse ICT color transform (YCbCr → RGB).
    case ictInverse = "j2k_ict_inverse"
    /// Forward RCT color transform (reversible).
    case rctForward = "j2k_rct_forward"
    /// Inverse RCT color transform (reversible).
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
    /// Optimized 3×3 MCT matrix multiply.
    case mctMatrixMultiply3x3 = "j2k_mct_matrix_multiply_3x3"
    /// Optimized 4×4 MCT matrix multiply.
    case mctMatrixMultiply4x4 = "j2k_mct_matrix_multiply_4x4"
    /// Fused color + MCT transform.
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
    /// Compute distortion metrics for R-D optimization.
    case quantizeDistortionMetric = "j2k_quantize_distortion_metric"
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
    #endif

    /// Whether shaders have been loaded.
    private var isLoaded = false

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

        let source = J2KMetalShaderSource.kernelSource
        let options = MTLCompileOptions()
        options.fastMathEnabled = true

        do {
            let compiledLibrary = try device.makeLibrary(source: source, options: options)
            self.library = compiledLibrary
            self.device = device
            self.isLoaded = true
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

    /// Clears the pipeline state cache.
    public func clearCache() {
        #if canImport(Metal)
        pipelineCache.removeAll()
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

        // CDF 9/7 lifting coefficients
        const float alpha = -1.586134342f;
        const float beta  = -0.052980118f;
        const float gamma =  0.882911075f;
        const float delta =  0.443506852f;
        const float K     =  1.230174105f;

        // Split into even and odd samples
        for (uint i = 0; i < halfWidth; i++) {
            uint idx = row * width;
            uint evenIdx = 2 * i;
            uint oddIdx = min(2 * i + 1, width - 1);
            lowpass[row * halfWidth + i] = input[idx + evenIdx] * K;
            highpass[row * (width / 2) + i] = input[idx + oddIdx] / K;
        }

        // Apply lifting steps (simplified for GPU)
        for (uint i = 0; i < width / 2; i++) {
            uint hIdx = row * (width / 2) + i;
            uint lIdx = row * halfWidth;
            uint left = i;
            uint right = min(i + 1, halfWidth - 1);
            highpass[hIdx] += alpha * (lowpass[lIdx + left] + lowpass[lIdx + right]);
        }
        for (uint i = 0; i < halfWidth; i++) {
            uint lIdx = row * halfWidth + i;
            uint hBase = row * (width / 2);
            uint left = (i > 0) ? (i - 1) : 0;
            uint right = min(i, (width / 2) - 1);
            lowpass[lIdx] += beta * (highpass[hBase + left] + highpass[hBase + right]);
        }
        for (uint i = 0; i < width / 2; i++) {
            uint hIdx = row * (width / 2) + i;
            uint lIdx = row * halfWidth;
            uint left = i;
            uint right = min(i + 1, halfWidth - 1);
            highpass[hIdx] += gamma * (lowpass[lIdx + left] + lowpass[lIdx + right]);
        }
        for (uint i = 0; i < halfWidth; i++) {
            uint lIdx = row * halfWidth + i;
            uint hBase = row * (width / 2);
            uint left = (i > 0) ? (i - 1) : 0;
            uint right = min(i, (width / 2) - 1);
            lowpass[lIdx] += delta * (highpass[hBase + left] + highpass[hBase + right]);
        }
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
        const float K = 1.230174105f;

        for (uint i = 0; i < halfHeight; i++) {
            uint evenRow = 2 * i;
            uint oddRow = min(2 * i + 1, height - 1);
            lowpass[i * width + col] = input[evenRow * width + col] * K;
            highpass[i * width + col] = input[oddRow * width + col] / K;
        }
    }

    // MARK: - Inverse 9/7 Irreversible DWT (Horizontal)

    kernel void j2k_dwt_inverse_97_horizontal(
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
        const float K = 1.230174105f;

        for (uint i = 0; i < halfWidth; i++) {
            output[row * width + 2 * i] = lowpass[row * halfWidth + i] / K;
        }
        for (uint i = 0; i < width / 2; i++) {
            output[row * width + 2 * i + 1] = highpass[row * (width / 2) + i] * K;
        }
    }

    // MARK: - Inverse 9/7 Irreversible DWT (Vertical)

    kernel void j2k_dwt_inverse_97_vertical(
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
        const float K = 1.230174105f;

        for (uint i = 0; i < halfHeight; i++) {
            output[(2 * i) * width + col] = lowpass[i * width + col] / K;
        }
        for (uint i = 0; i < height / 2; i++) {
            output[(2 * i + 1) * width + col] = highpass[i * width + col] * K;
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Horizontal)

    kernel void j2k_dwt_forward_53_horizontal(
        device const int* input [[buffer(0)]],
        device int* lowpass [[buffer(1)]],
        device int* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.y >= height) return;

        uint row = gid.y;
        uint halfWidth = (width + 1) / 2;

        // Predict step: d[n] = x[2n+1] - floor((x[2n] + x[2n+2]) / 2)
        for (uint i = 0; i < width / 2; i++) {
            uint idx = row * width;
            int left = input[idx + 2 * i];
            int right = (2 * i + 2 < width) ? input[idx + 2 * i + 2] : input[idx + 2 * i];
            highpass[row * (width / 2) + i] = input[idx + 2 * i + 1] - ((left + right) / 2);
        }

        // Update step: s[n] = x[2n] + floor((d[n-1] + d[n]) / 4)
        for (uint i = 0; i < halfWidth; i++) {
            uint idx = row * width;
            uint hBase = row * (width / 2);
            int d_left = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
            int d_right = (i < width / 2) ? highpass[hBase + i] : highpass[hBase + (width / 2) - 1];
            lowpass[row * halfWidth + i] = input[idx + 2 * i] + ((d_left + d_right + 2) / 4);
        }
    }

    // MARK: - Forward 5/3 Reversible DWT (Vertical)

    kernel void j2k_dwt_forward_53_vertical(
        device const int* input [[buffer(0)]],
        device int* lowpass [[buffer(1)]],
        device int* highpass [[buffer(2)]],
        constant uint& width [[buffer(3)]],
        constant uint& height [[buffer(4)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= width) return;

        uint col = gid.x;
        uint halfHeight = (height + 1) / 2;

        for (uint i = 0; i < height / 2; i++) {
            int top = input[(2 * i) * width + col];
            int bottom = (2 * i + 2 < height) ? input[(2 * i + 2) * width + col] : input[(2 * i) * width + col];
            highpass[i * width + col] = input[(2 * i + 1) * width + col] - ((top + bottom) / 2);
        }
        for (uint i = 0; i < halfHeight; i++) {
            int d_top = (i > 0) ? highpass[(i - 1) * width + col] : highpass[col];
            int d_bot = (i < height / 2) ? highpass[i * width + col] : highpass[((height / 2) - 1) * width + col];
            lowpass[i * width + col] = input[(2 * i) * width + col] + ((d_top + d_bot + 2) / 4);
        }
    }

    // MARK: - Inverse 5/3 Reversible DWT (Horizontal)

    kernel void j2k_dwt_inverse_53_horizontal(
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

        // Undo update
        for (uint i = 0; i < halfWidth; i++) {
            uint hBase = row * (width / 2);
            int d_left = (i > 0) ? highpass[hBase + i - 1] : highpass[hBase];
            int d_right = (i < width / 2) ? highpass[hBase + i] : highpass[hBase + (width / 2) - 1];
            output[row * width + 2 * i] = lowpass[row * halfWidth + i] - ((d_left + d_right + 2) / 4);
        }
        // Undo predict
        for (uint i = 0; i < width / 2; i++) {
            int left = output[row * width + 2 * i];
            int right = (2 * i + 2 < width) ? output[row * width + 2 * i + 2] : output[row * width + 2 * i];
            output[row * width + 2 * i + 1] = highpass[row * (width / 2) + i] + ((left + right) / 2);
        }
    }

    // MARK: - Inverse 5/3 Reversible DWT (Vertical)

    kernel void j2k_dwt_inverse_53_vertical(
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

        for (uint i = 0; i < halfHeight; i++) {
            int d_top = (i > 0) ? highpass[(i - 1) * width + col] : highpass[col];
            int d_bot = (i < height / 2) ? highpass[i * width + col] : highpass[((height / 2) - 1) * width + col];
            output[(2 * i) * width + col] = lowpass[i * width + col] - ((d_top + d_bot + 2) / 4);
        }
        for (uint i = 0; i < height / 2; i++) {
            int top = output[(2 * i) * width + col];
            int bottom = (2 * i + 2 < height) ? output[(2 * i + 2) * width + col] : output[(2 * i) * width + col];
            output[(2 * i + 1) * width + col] = highpass[i * width + col] + ((top + bottom) / 2);
        }
    }

    // MARK: - Forward ICT (Irreversible Color Transform)

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

    // MARK: - Inverse ICT (Irreversible Color Transform)

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

    // MARK: - Forward RCT (Reversible Color Transform)

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

    // MARK: - Inverse RCT (Reversible Color Transform)

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

        // Normalize to [0, lutSize-1]
        float normalized = (val - inputMin) / range * float(lutSize - 1);
        normalized = clamp(normalized, 0.0f, float(lutSize - 1));

        // Linear interpolation
        uint idx0 = uint(normalized);
        uint idx1 = min(idx0 + 1, lutSize - 1);
        float frac = normalized - float(idx0);

        output[gid] = lut[idx0] * (1.0f - frac) + lut[idx1] * frac;
    }

    // MARK: - Optimized 3×3 MCT Matrix Multiply

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

    // MARK: - Optimized 4×4 MCT Matrix Multiply

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

    // MARK: - Fused Color Transform + MCT

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

        // Apply color transform then MCT in a single pass
        // First: color transform
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

    // Compute distortion metrics for R-D optimization
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
    """
}
