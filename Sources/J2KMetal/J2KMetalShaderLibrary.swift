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
    """
}
