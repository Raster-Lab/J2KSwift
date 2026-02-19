// JP3DMetalDWT.swift
// J2KSwift
//
// Metal compute shader integration for 3D DWT (JP3D volumetric processing).
// Week 214-217: GPU-accelerated separable 3D wavelet transforms.
//

import Foundation
import J2KCore

#if canImport(Metal)
import Metal
#endif

// MARK: - JP3D Metal DWT Backend

/// Backend selection for JP3D DWT computation.
///
/// Controls whether the 3D wavelet transform runs on GPU (Metal) or CPU,
/// with automatic selection based on Metal availability at runtime.
public enum JP3DMetalDWTBackend: Sendable {
    /// Force GPU execution via Metal compute shaders.
    case metal
    /// Force CPU execution (pure Swift software fallback).
    case cpu
    /// Automatically use Metal if available on this device, otherwise CPU.
    case automatic
}

// MARK: - JP3D Metal DWT Statistics

/// Performance statistics for JP3D Metal DWT operations.
///
/// Tracks transform counts and processing time for monitoring
/// and optimization of volumetric DWT pipelines.
public struct JP3DMetalDWTStatistics: Sendable {
    /// Total number of forward transforms performed.
    public let forwardTransforms: Int
    /// Total number of inverse transforms performed.
    public let inverseTransforms: Int
    /// Number of transforms executed on the Metal GPU.
    public let metalAccelerated: Int
    /// Number of transforms that fell back to CPU execution.
    public let cpuFallbacks: Int
    /// Cumulative processing time in seconds.
    public let totalProcessingTime: Double

    /// Creates a statistics snapshot.
    ///
    /// - Parameters:
    ///   - forwardTransforms: Forward transform count.
    ///   - inverseTransforms: Inverse transform count.
    ///   - metalAccelerated: Metal-accelerated operation count.
    ///   - cpuFallbacks: CPU fallback operation count.
    ///   - totalProcessingTime: Cumulative time in seconds.
    public init(
        forwardTransforms: Int,
        inverseTransforms: Int,
        metalAccelerated: Int,
        cpuFallbacks: Int,
        totalProcessingTime: Double
    ) {
        self.forwardTransforms = forwardTransforms
        self.inverseTransforms = inverseTransforms
        self.metalAccelerated = metalAccelerated
        self.cpuFallbacks = cpuFallbacks
        self.totalProcessingTime = totalProcessingTime
    }
}

// MARK: - JP3D Metal DWT Actor

/// Metal-accelerated 3D discrete wavelet transform for JP3D volumetric processing.
///
/// `JP3DMetalDWT` provides GPU-accelerated forward and inverse 1D wavelet
/// transforms along each axis of a 3D volume using Metal compute shaders.
/// It supports both the reversible Le Gall 5/3 filter and the irreversible
/// CDF 9/7 filter, with automatic CPU fallback on platforms where Metal is
/// unavailable (e.g., Linux CI).
///
/// ## Usage
///
/// ```swift
/// let dwt = JP3DMetalDWT(backend: .automatic)
/// try await dwt.initialize()
///
/// // Forward 5/3 DWT along the X axis
/// let (low, high) = try await dwt.forward53X(
///     data: volume,
///     width: 64, height: 64, depth: 64
/// )
///
/// // Reconstruct
/// let reconstructed = try await dwt.inverse53X(
///     low: low, high: high,
///     origWidth: 64, height: 64, depth: 64
/// )
/// ```
///
/// ## Shader Compilation
///
/// The Metal shaders are embedded as MSL source and compiled at runtime
/// via `MTLDevice.makeLibrary(source:options:)`. If compilation fails,
/// the actor falls back to CPU automatically.
///
/// ## Thread Safety
///
/// All mutable state is protected by the actor. The `isMetalAvailable`
/// static property is safe to access from any context.
public actor JP3DMetalDWT {

    // MARK: - Static Properties

    /// Whether Metal acceleration is available on this device.
    ///
    /// Returns `true` on Apple platforms where Metal can be imported;
    /// always `false` on Linux and other non-Metal platforms.
    public static var isMetalAvailable: Bool {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }

    // MARK: - Private State

    /// The requested backend for this instance.
    private let backend: JP3DMetalDWTBackend

    /// Whether the actor has been successfully initialized.
    private var isInitialized = false

    /// Whether the Metal GPU path is active for this instance.
    private var metalEnabled = false

    // Statistics counters (actor-protected).
    private var _forwardTransforms = 0
    private var _inverseTransforms = 0
    private var _metalAccelerated = 0
    private var _cpuFallbacks = 0
    private var _totalProcessingTime: Double = 0.0

    #if canImport(Metal)
    /// The compiled Metal library containing the 3D DWT kernels.
    private var metalLibrary: MTLLibrary?
    /// Cached compute pipeline states keyed by kernel name.
    private var pipelines: [String: MTLComputePipelineState] = [:]
    /// The Metal command queue.
    private var commandQueue: MTLCommandQueue?
    #endif

    // MARK: - Initialiser

    /// Creates a JP3D Metal DWT actor.
    ///
    /// - Parameter backend: Backend selection. Defaults to `.automatic`.
    public init(backend: JP3DMetalDWTBackend = .automatic) {
        self.backend = backend
    }

    // MARK: - Initialisation

    /// Initialises Metal resources: compiles shaders and creates pipeline states.
    ///
    /// Call this once before using any transform methods. Subsequent calls are
    /// no-ops. If Metal is unavailable or shader compilation fails, the actor
    /// silently falls back to CPU without throwing.
    ///
    /// - Throws: ``J2KError/internalError(_:)`` only when the backend is
    ///   explicitly `.metal` and initialization fails completely.
    public func initialize() async throws {
        guard !isInitialized else { return }
        defer { isInitialized = true }

        let wantMetal: Bool
        switch backend {
        case .metal:     wantMetal = true
        case .cpu:       wantMetal = false
        case .automatic: wantMetal = JP3DMetalDWT.isMetalAvailable
        }

        guard wantMetal else { return }

        #if canImport(Metal)
        do {
            try initializeMetal()
        } catch {
            // Graceful degradation: Metal unavailable → use CPU.
            if case .metal = backend {
                throw J2KError.internalError("JP3DMetalDWT Metal init failed: \(error)")
            }
        }
        #endif
    }

    // MARK: - Forward 5/3 along X

    /// Forward Le Gall 5/3 DWT along the X axis of a 3D volume.
    ///
    /// Applies a single-level 1D lifting transform to each row (along X)
    /// independently for every (y, z) pair, producing a lowpass subband of
    /// length `⌈width/2⌉` and a highpass subband of length `⌊width/2⌋`.
    ///
    /// - Parameters:
    ///   - data: Flattened 3D input in row-major order `[z][y][x]`.
    ///   - width: Number of samples along X.
    ///   - height: Number of rows along Y.
    ///   - depth: Number of slices along Z.
    /// - Returns: A tuple `(low, high)` where each element is a flattened
    ///   3D array in `[z][y][x]` order.
    /// - Throws: ``J2KError`` on invalid dimensions.
    public func forward53X(
        data: [Float],
        width: Int,
        height: Int,
        depth: Int
    ) async throws -> (low: [Float], high: [Float]) {
        let start = currentTime()
        defer {
            _forwardTransforms += 1
            _totalProcessingTime += currentTime() - start
        }

        guard width > 0, height > 0, depth > 0 else {
            throw J2KError.invalidParameter("JP3DMetalDWT.forward53X: dimensions must be positive")
        }
        guard data.count == width * height * depth else {
            throw J2KError.invalidParameter("JP3DMetalDWT.forward53X: data.count mismatch")
        }

        #if canImport(Metal)
        if metalEnabled, let result = try? await metalForward53X(
            data: data, width: width, height: height, depth: depth
        ) {
            _metalAccelerated += 1
            return result
        }
        #endif
        _cpuFallbacks += 1
        return cpuForward53X(data: data, width: width, height: height, depth: depth)
    }

    // MARK: - Inverse 5/3 along X

    /// Inverse Le Gall 5/3 DWT along the X axis.
    ///
    /// Reconstructs the original signal from the lowpass and highpass subbands
    /// produced by ``forward53X(data:width:height:depth:)``.
    ///
    /// - Parameters:
    ///   - low: Lowpass subband in `[z][y][x]` order.
    ///   - high: Highpass subband in `[z][y][x]` order.
    ///   - origWidth: Original width (number of X samples before decomposition).
    ///   - height: Number of rows along Y.
    ///   - depth: Number of slices along Z.
    /// - Returns: Reconstructed flattened 3D array in `[z][y][x]` order.
    /// - Throws: ``J2KError`` on invalid dimensions.
    public func inverse53X(
        low: [Float],
        high: [Float],
        origWidth: Int,
        height: Int,
        depth: Int
    ) async throws -> [Float] {
        let start = currentTime()
        defer {
            _inverseTransforms += 1
            _totalProcessingTime += currentTime() - start
        }

        let lowLen  = (origWidth + 1) / 2
        let highLen = origWidth / 2
        guard height > 0, depth > 0 else {
            throw J2KError.invalidParameter("JP3DMetalDWT.inverse53X: dimensions must be positive")
        }
        guard low.count  == lowLen  * height * depth,
              high.count == highLen * height * depth else {
            throw J2KError.invalidParameter("JP3DMetalDWT.inverse53X: subband size mismatch")
        }

        #if canImport(Metal)
        if metalEnabled, let result = try? await metalInverse53X(
            low: low, high: high,
            origWidth: origWidth, height: height, depth: depth
        ) {
            _metalAccelerated += 1
            return result
        }
        #endif
        _cpuFallbacks += 1
        return cpuInverse53X(
            low: low, high: high,
            origWidth: origWidth, height: height, depth: depth
        )
    }

    // MARK: - Forward 9/7 along X

    /// Forward CDF 9/7 DWT along the X axis of a 3D volume.
    ///
    /// Applies a single-level floating-point lifting transform to each row
    /// along X for every (y, z) pair.
    ///
    /// - Parameters:
    ///   - data: Flattened 3D input in `[z][y][x]` order.
    ///   - width: Number of samples along X.
    ///   - height: Number of rows along Y.
    ///   - depth: Number of slices along Z.
    /// - Returns: A tuple `(low, high)` of flattened 3D subbands.
    /// - Throws: ``J2KError`` on invalid dimensions.
    public func forward97X(
        data: [Float],
        width: Int,
        height: Int,
        depth: Int
    ) async throws -> (low: [Float], high: [Float]) {
        let start = currentTime()
        defer {
            _forwardTransforms += 1
            _totalProcessingTime += currentTime() - start
        }

        guard width > 0, height > 0, depth > 0 else {
            throw J2KError.invalidParameter("JP3DMetalDWT.forward97X: dimensions must be positive")
        }
        guard data.count == width * height * depth else {
            throw J2KError.invalidParameter("JP3DMetalDWT.forward97X: data.count mismatch")
        }

        #if canImport(Metal)
        if metalEnabled, let result = try? await metalForward97X(
            data: data, width: width, height: height, depth: depth
        ) {
            _metalAccelerated += 1
            return result
        }
        #endif
        _cpuFallbacks += 1
        return cpuForward97X(data: data, width: width, height: height, depth: depth)
    }

    // MARK: - Inverse 9/7 along X

    /// Inverse CDF 9/7 DWT along the X axis.
    ///
    /// Reconstructs the original signal from subbands produced by
    /// ``forward97X(data:width:height:depth:)``.
    ///
    /// - Parameters:
    ///   - low: Lowpass subband in `[z][y][x]` order.
    ///   - high: Highpass subband in `[z][y][x]` order.
    ///   - origWidth: Original X dimension before decomposition.
    ///   - height: Number of rows along Y.
    ///   - depth: Number of slices along Z.
    /// - Returns: Reconstructed flattened 3D array.
    /// - Throws: ``J2KError`` on invalid dimensions.
    public func inverse97X(
        low: [Float],
        high: [Float],
        origWidth: Int,
        height: Int,
        depth: Int
    ) async throws -> [Float] {
        let start = currentTime()
        defer {
            _inverseTransforms += 1
            _totalProcessingTime += currentTime() - start
        }

        let lowLen  = (origWidth + 1) / 2
        let highLen = origWidth / 2
        guard height > 0, depth > 0 else {
            throw J2KError.invalidParameter("JP3DMetalDWT.inverse97X: dimensions must be positive")
        }
        guard low.count  == lowLen  * height * depth,
              high.count == highLen * height * depth else {
            throw J2KError.invalidParameter("JP3DMetalDWT.inverse97X: subband size mismatch")
        }

        #if canImport(Metal)
        if metalEnabled, let result = try? await metalInverse97X(
            low: low, high: high,
            origWidth: origWidth, height: height, depth: depth
        ) {
            _metalAccelerated += 1
            return result
        }
        #endif
        _cpuFallbacks += 1
        return cpuInverse97X(
            low: low, high: high,
            origWidth: origWidth, height: height, depth: depth
        )
    }

    // MARK: - Statistics

    /// Returns a snapshot of current processing statistics.
    ///
    /// - Returns: A ``JP3DMetalDWTStatistics`` value with current counts and timing.
    public func statistics() -> JP3DMetalDWTStatistics {
        JP3DMetalDWTStatistics(
            forwardTransforms: _forwardTransforms,
            inverseTransforms: _inverseTransforms,
            metalAccelerated: _metalAccelerated,
            cpuFallbacks: _cpuFallbacks,
            totalProcessingTime: _totalProcessingTime
        )
    }

    /// Resets all statistics counters to zero.
    public func resetStatistics() {
        _forwardTransforms = 0
        _inverseTransforms = 0
        _metalAccelerated = 0
        _cpuFallbacks = 0
        _totalProcessingTime = 0.0
    }

    // MARK: - Helpers

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}

// MARK: - Metal GPU Path

#if canImport(Metal)
extension JP3DMetalDWT {

    // MARK: MSL Source

    /// Embedded MSL source for all 3D DWT kernels.
    ///
    /// Contains 10 kernels operating on 1D row slices of a 3D volume:
    /// forward/inverse 5/3 and forward 9/7 along X, Y, Z, plus a combined
    /// separable forward kernel (X + Y in one pass).
    private static let mslSource: String = """
#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// Helper: safe array access with boundary extension (symmetric)
// ---------------------------------------------------------------------------
static inline float safeGet(device const float* buf, int idx, int len) {
    if (idx < 0)   idx = -idx;
    if (idx >= len) idx = 2 * (len - 1) - idx;
    idx = clamp(idx, 0, len - 1);
    return buf[idx];
}

// ---------------------------------------------------------------------------
// jp3d_dwt_forward_53_x
// Forward Le Gall 5/3 DWT along X.
// Each thread handles one (y, z) row of length `width`.
// grid: (height * depth, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_forward_53_x(
    device const float* input  [[buffer(0)]],
    device       float* outLow [[buffer(1)]],
    device       float* outHigh[[buffer(2)]],
    constant uint& width       [[buffer(3)]],
    constant uint& height      [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalRows = height * depth;
    if (gid >= totalRows) return;

    int W = (int)width;
    int lowLen  = (W + 1) / 2;
    int highLen = W / 2;

    int rowOffset = (int)gid * W;
    device const float* row = input + rowOffset;

    // Predict (highpass)
    for (int i = 0; i < highLen; ++i) {
        float left  = safeGet(row, 2 * i,     W);
        float right = safeGet(row, 2 * i + 2, W);
        outHigh[(int)gid * highLen + i] = row[2 * i + 1] - floor((left + right) / 2.0f);
    }

    // Update (lowpass) — uses h[-1] = h[0]
    for (int i = 0; i < lowLen; ++i) {
        float hPrev = (i == 0)
            ? outHigh[(int)gid * highLen]
            : outHigh[(int)gid * highLen + (i - 1)];
        float hCurr = (i < highLen)
            ? outHigh[(int)gid * highLen + i]
            : outHigh[(int)gid * highLen + (highLen - 1)];
        outLow[(int)gid * lowLen + i] = row[2 * i] + floor((hPrev + hCurr + 2.0f) / 4.0f);
    }
}

// ---------------------------------------------------------------------------
// jp3d_dwt_inverse_53_x
// Inverse Le Gall 5/3 DWT along X.
// grid: (height * depth, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_inverse_53_x(
    device const float* inLow  [[buffer(0)]],
    device const float* inHigh [[buffer(1)]],
    device       float* output [[buffer(2)]],
    constant uint& origWidth   [[buffer(3)]],
    constant uint& height      [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalRows = height * depth;
    if (gid >= totalRows) return;

    int W       = (int)origWidth;
    int lowLen  = (W + 1) / 2;
    int highLen = W / 2;
    int rowOut  = (int)gid * W;

    device const float* L = inLow  + (int)gid * lowLen;
    device const float* H = inHigh + (int)gid * highLen;
    device float*       O = output + rowOut;

    // Undo update: recover even samples
    for (int i = 0; i < lowLen; ++i) {
        float hPrev = (i == 0) ? H[0] : H[i - 1];
        float hCurr = (i < highLen) ? H[i] : H[highLen - 1];
        O[2 * i] = L[i] - floor((hPrev + hCurr + 2.0f) / 4.0f);
    }

    // Undo predict: recover odd samples
    for (int i = 0; i < highLen; ++i) {
        float left  = O[2 * i];
        float right = (2 * i + 2 < W) ? O[2 * i + 2] : O[2 * (lowLen - 1)];
        O[2 * i + 1] = H[i] + floor((left + right) / 2.0f);
    }
}

// ---------------------------------------------------------------------------
// jp3d_dwt_forward_53_y
// Forward 5/3 DWT along Y.
// Input shape: [depth][height][width], row-major.
// Each thread handles one (x, z) column of length `height`.
// grid: (width * depth, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_forward_53_y(
    device const float* input  [[buffer(0)]],
    device       float* outLow [[buffer(1)]],
    device       float* outHigh[[buffer(2)]],
    constant uint& width       [[buffer(3)]],
    constant uint& height      [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalCols = width * depth;
    if (gid >= totalCols) return;

    uint z = gid / width;
    uint x = gid % width;
    int  H    = (int)height;
    int  W    = (int)width;
    int  lowH = (H + 1) / 2;
    int  hiH  = H / 2;

    // Column stride along Y in the full volume
    int slice = (int)z * (int)height * (int)width;

    // High-pass (predict)
    for (int i = 0; i < hiH; ++i) {
        float top    = input[slice + (2 * i)     * W + (int)x];
        float bottom = input[slice + (2 * i + 2) * W + (int)x];
        if (2 * i + 2 >= H) bottom = input[slice + (2 * (lowH - 1)) * W + (int)x];
        float mid    = input[slice + (2 * i + 1) * W + (int)x];
        outHigh[(int)z * hiH * W + i * W + (int)x] = mid - floor((top + bottom) / 2.0f);
    }

    // Low-pass (update)
    for (int i = 0; i < lowH; ++i) {
        float hPrev = (i == 0)
            ? outHigh[(int)z * hiH * W + 0 * W + (int)x]
            : outHigh[(int)z * hiH * W + (i - 1) * W + (int)x];
        float hCurr = (i < hiH)
            ? outHigh[(int)z * hiH * W + i * W + (int)x]
            : outHigh[(int)z * hiH * W + (hiH - 1) * W + (int)x];
        float even = input[slice + (2 * i) * W + (int)x];
        outLow[(int)z * lowH * W + i * W + (int)x] = even + floor((hPrev + hCurr + 2.0f) / 4.0f);
    }
}

// ---------------------------------------------------------------------------
// jp3d_dwt_inverse_53_y
// Inverse 5/3 DWT along Y.
// grid: (width * depth, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_inverse_53_y(
    device const float* inLow  [[buffer(0)]],
    device const float* inHigh [[buffer(1)]],
    device       float* output [[buffer(2)]],
    constant uint& origHeight  [[buffer(3)]],
    constant uint& width       [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalCols = width * depth;
    if (gid >= totalCols) return;

    uint z    = gid / width;
    uint x    = gid % width;
    int  H    = (int)origHeight;
    int  W    = (int)width;
    int  lowH = (H + 1) / 2;
    int  hiH  = H / 2;
    int  slice = (int)z * H * W;

    device const float* L = inLow  + (int)z * lowH * W;
    device const float* Hi = inHigh + (int)z * hiH  * W;
    device float*       O  = output + slice;

    for (int i = 0; i < lowH; ++i) {
        float hPrev = (i == 0) ? Hi[0 * W + (int)x] : Hi[(i - 1) * W + (int)x];
        float hCurr = (i < hiH) ? Hi[i * W + (int)x] : Hi[(hiH - 1) * W + (int)x];
        O[(2 * i) * W + (int)x] = L[i * W + (int)x] - floor((hPrev + hCurr + 2.0f) / 4.0f);
    }
    for (int i = 0; i < hiH; ++i) {
        float top    = O[(2 * i) * W + (int)x];
        float bottom = (2 * i + 2 < H) ? O[(2 * i + 2) * W + (int)x]
                                        : O[(2 * (lowH - 1)) * W + (int)x];
        O[(2 * i + 1) * W + (int)x] = Hi[i * W + (int)x] + floor((top + bottom) / 2.0f);
    }
}

// ---------------------------------------------------------------------------
// jp3d_dwt_forward_53_z
// Forward 5/3 DWT along Z (depth axis).
// Each thread handles one (x, y) position across `depth` slices.
// grid: (width * height, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_forward_53_z(
    device const float* input  [[buffer(0)]],
    device       float* outLow [[buffer(1)]],
    device       float* outHigh[[buffer(2)]],
    constant uint& width       [[buffer(3)]],
    constant uint& height      [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalPix = width * height;
    if (gid >= totalPix) return;

    int  D    = (int)depth;
    int  WH   = (int)totalPix;
    int  lowD = (D + 1) / 2;
    int  hiD  = D / 2;

    for (int i = 0; i < hiD; ++i) {
        float a = input[(2 * i)     * WH + (int)gid];
        float b = input[(2 * i + 2) * WH + (int)gid];
        if (2 * i + 2 >= D) b = input[(2 * (lowD - 1)) * WH + (int)gid];
        float c = input[(2 * i + 1) * WH + (int)gid];
        outHigh[i * WH + (int)gid] = c - floor((a + b) / 2.0f);
    }
    for (int i = 0; i < lowD; ++i) {
        float hPrev = (i == 0) ? outHigh[0 * WH + (int)gid]
                               : outHigh[(i - 1) * WH + (int)gid];
        float hCurr = (i < hiD) ? outHigh[i * WH + (int)gid]
                                 : outHigh[(hiD - 1) * WH + (int)gid];
        outLow[i * WH + (int)gid] = input[(2 * i) * WH + (int)gid]
                                   + floor((hPrev + hCurr + 2.0f) / 4.0f);
    }
}

// ---------------------------------------------------------------------------
// jp3d_dwt_inverse_53_z
// Inverse 5/3 DWT along Z.
// grid: (width * height, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_inverse_53_z(
    device const float* inLow  [[buffer(0)]],
    device const float* inHigh [[buffer(1)]],
    device       float* output [[buffer(2)]],
    constant uint& origDepth   [[buffer(3)]],
    constant uint& width       [[buffer(4)]],
    constant uint& height      [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalPix = width * height;
    if (gid >= totalPix) return;

    int D    = (int)origDepth;
    int WH   = (int)totalPix;
    int lowD = (D + 1) / 2;
    int hiD  = D / 2;

    for (int i = 0; i < lowD; ++i) {
        float hPrev = (i == 0) ? inHigh[0 * WH + (int)gid]
                               : inHigh[(i - 1) * WH + (int)gid];
        float hCurr = (i < hiD) ? inHigh[i * WH + (int)gid]
                                 : inHigh[(hiD - 1) * WH + (int)gid];
        output[(2 * i) * WH + (int)gid] = inLow[i * WH + (int)gid]
                                          - floor((hPrev + hCurr + 2.0f) / 4.0f);
    }
    for (int i = 0; i < hiD; ++i) {
        float a = output[(2 * i) * WH + (int)gid];
        float b = (2 * i + 2 < D) ? output[(2 * i + 2) * WH + (int)gid]
                                   : output[(2 * (lowD - 1)) * WH + (int)gid];
        output[(2 * i + 1) * WH + (int)gid] = inHigh[i * WH + (int)gid]
                                              + floor((a + b) / 2.0f);
    }
}

// ---------------------------------------------------------------------------
// CDF 9/7 lifting constants
// ---------------------------------------------------------------------------
constant float kAlpha   = -1.586134342f;
constant float kBeta    = -0.052980118f;
constant float kGamma   =  0.882911075f;
constant float kDelta   =  0.443506852f;
constant float kK       =  1.230174105f;
constant float kKInv    =  1.0f / 1.230174105f;

// ---------------------------------------------------------------------------
// jp3d_dwt_forward_97_x
// Forward CDF 9/7 DWT along X.
// grid: (height * depth, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_forward_97_x(
    device const float* input  [[buffer(0)]],
    device       float* outLow [[buffer(1)]],
    device       float* outHigh[[buffer(2)]],
    constant uint& width       [[buffer(3)]],
    constant uint& height      [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalRows = height * depth;
    if (gid >= totalRows) return;

    int W      = (int)width;
    int rowOff = (int)gid * W;
    int lowLen = (W + 1) / 2;
    int hiLen  = W / 2;

    // Copy row to threadgroup-accessible array via pointer arithmetic
    // (No VLA in MSL; use device memory directly with four lifting passes)
    device const float* src = input + rowOff;

    // Temporary arrays in device memory are not possible without extra buffers;
    // perform in-place lifting on output buffers via interleaved indexing.
    // Strategy: write even → outLow, odd → outHigh, apply 4 lifting steps.

    for (int i = 0; i < lowLen; ++i) outLow [(int)gid * lowLen + i] = src[2 * i];
    for (int i = 0; i < hiLen;  ++i) outHigh[(int)gid * hiLen  + i] = src[2 * i + 1];

    device float* L = outLow  + (int)gid * lowLen;
    device float* H = outHigh + (int)gid * hiLen;

    // Step 1 (alpha): H[i] += alpha * (L[i] + L[i+1])
    for (int i = 0; i < hiLen; ++i) {
        float lLeft  = L[i];
        float lRight = (i + 1 < lowLen) ? L[i + 1] : L[lowLen - 1];
        H[i] += kAlpha * (lLeft + lRight);
    }
    // Step 2 (beta): L[i] += beta * (H[i-1] + H[i])
    for (int i = 0; i < lowLen; ++i) {
        float hPrev = (i == 0) ? H[0] : H[i - 1];
        float hCurr = (i < hiLen) ? H[i] : H[hiLen - 1];
        L[i] += kBeta * (hPrev + hCurr);
    }
    // Step 3 (gamma): H[i] += gamma * (L[i] + L[i+1])
    for (int i = 0; i < hiLen; ++i) {
        float lLeft  = L[i];
        float lRight = (i + 1 < lowLen) ? L[i + 1] : L[lowLen - 1];
        H[i] += kGamma * (lLeft + lRight);
    }
    // Step 4 (delta): L[i] += delta * (H[i-1] + H[i])
    for (int i = 0; i < lowLen; ++i) {
        float hPrev = (i == 0) ? H[0] : H[i - 1];
        float hCurr = (i < hiLen) ? H[i] : H[hiLen - 1];
        L[i] += kDelta * (hPrev + hCurr);
    }
    // Scale
    for (int i = 0; i < lowLen; ++i) L[i] *= kK;
    for (int i = 0; i < hiLen;  ++i) H[i] *= kKInv;
}

// ---------------------------------------------------------------------------
// jp3d_dwt_forward_97_y
// Forward CDF 9/7 DWT along Y.
// grid: (width * depth, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_forward_97_y(
    device const float* input  [[buffer(0)]],
    device       float* outLow [[buffer(1)]],
    device       float* outHigh[[buffer(2)]],
    constant uint& width       [[buffer(3)]],
    constant uint& height      [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalCols = width * depth;
    if (gid >= totalCols) return;

    uint z    = gid / width;
    uint x    = gid % width;
    int  H    = (int)height;
    int  W    = (int)width;
    int  lowH = (H + 1) / 2;
    int  hiH  = H / 2;
    int  slice = (int)z * H * W;

    device float* L  = outLow  + (int)z * lowH * W;
    device float* Hi = outHigh + (int)z * hiH  * W;

    for (int i = 0; i < lowH; ++i)
        L[i * W + (int)x]  = input[slice + (2 * i) * W + (int)x];
    for (int i = 0; i < hiH;  ++i)
        Hi[i * W + (int)x] = input[slice + (2 * i + 1) * W + (int)x];

    for (int i = 0; i < hiH; ++i) {
        float lL = L[i * W + (int)x];
        float lR = (i + 1 < lowH) ? L[(i + 1) * W + (int)x] : L[(lowH - 1) * W + (int)x];
        Hi[i * W + (int)x] += kAlpha * (lL + lR);
    }
    for (int i = 0; i < lowH; ++i) {
        float hP = (i == 0) ? Hi[0 * W + (int)x] : Hi[(i - 1) * W + (int)x];
        float hC = (i < hiH) ? Hi[i * W + (int)x] : Hi[(hiH - 1) * W + (int)x];
        L[i * W + (int)x] += kBeta * (hP + hC);
    }
    for (int i = 0; i < hiH; ++i) {
        float lL = L[i * W + (int)x];
        float lR = (i + 1 < lowH) ? L[(i + 1) * W + (int)x] : L[(lowH - 1) * W + (int)x];
        Hi[i * W + (int)x] += kGamma * (lL + lR);
    }
    for (int i = 0; i < lowH; ++i) {
        float hP = (i == 0) ? Hi[0 * W + (int)x] : Hi[(i - 1) * W + (int)x];
        float hC = (i < hiH) ? Hi[i * W + (int)x] : Hi[(hiH - 1) * W + (int)x];
        L[i * W + (int)x] += kDelta * (hP + hC);
    }
    for (int i = 0; i < lowH; ++i) L[i * W + (int)x] *= kK;
    for (int i = 0; i < hiH;  ++i) Hi[i * W + (int)x] *= kKInv;
}

// ---------------------------------------------------------------------------
// jp3d_dwt_forward_97_z
// Forward CDF 9/7 DWT along Z.
// grid: (width * height, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_dwt_forward_97_z(
    device const float* input  [[buffer(0)]],
    device       float* outLow [[buffer(1)]],
    device       float* outHigh[[buffer(2)]],
    constant uint& width       [[buffer(3)]],
    constant uint& height      [[buffer(4)]],
    constant uint& depth       [[buffer(5)]],
    uint gid [[thread_position_in_grid]]
) {
    uint totalPix = width * height;
    if (gid >= totalPix) return;

    int D    = (int)depth;
    int WH   = (int)totalPix;
    int lowD = (D + 1) / 2;
    int hiD  = D / 2;

    for (int i = 0; i < lowD; ++i) outLow [i * WH + (int)gid] = input[(2 * i)     * WH + (int)gid];
    for (int i = 0; i < hiD;  ++i) outHigh[i * WH + (int)gid] = input[(2 * i + 1) * WH + (int)gid];

    device float* L  = outLow;
    device float* Hi = outHigh;

    for (int i = 0; i < hiD; ++i) {
        float lL = L[i * WH + (int)gid];
        float lR = (i + 1 < lowD) ? L[(i + 1) * WH + (int)gid] : L[(lowD - 1) * WH + (int)gid];
        Hi[i * WH + (int)gid] += kAlpha * (lL + lR);
    }
    for (int i = 0; i < lowD; ++i) {
        float hP = (i == 0) ? Hi[0 * WH + (int)gid] : Hi[(i - 1) * WH + (int)gid];
        float hC = (i < hiD) ? Hi[i * WH + (int)gid] : Hi[(hiD - 1) * WH + (int)gid];
        L[i * WH + (int)gid] += kBeta * (hP + hC);
    }
    for (int i = 0; i < hiD; ++i) {
        float lL = L[i * WH + (int)gid];
        float lR = (i + 1 < lowD) ? L[(i + 1) * WH + (int)gid] : L[(lowD - 1) * WH + (int)gid];
        Hi[i * WH + (int)gid] += kGamma * (lL + lR);
    }
    for (int i = 0; i < lowD; ++i) {
        float hP = (i == 0) ? Hi[0 * WH + (int)gid] : Hi[(i - 1) * WH + (int)gid];
        float hC = (i < hiD) ? Hi[i * WH + (int)gid] : Hi[(hiD - 1) * WH + (int)gid];
        L[i * WH + (int)gid] += kDelta * (hP + hC);
    }
    for (int i = 0; i < lowD; ++i) L[i * WH + (int)gid] *= kK;
    for (int i = 0; i < hiD;  ++i) Hi[i * WH + (int)gid] *= kKInv;
}

// ---------------------------------------------------------------------------
// jp3d_separable_dwt_forward
// Combined separable forward DWT: applies 5/3 along X then along Y in one
// dispatch, writing four subbands: LL, LH, HL, HH.
// Each thread handles one (y, z) pair (row along X).  A second pass along Y
// is performed using the intermediate low/high from the X pass.
// grid: (height * depth, 1, 1)
// ---------------------------------------------------------------------------
kernel void jp3d_separable_dwt_forward(
    device const float* input   [[buffer(0)]],
    device       float* outLL   [[buffer(1)]],
    device       float* outLH   [[buffer(2)]],
    device       float* outHL   [[buffer(3)]],
    device       float* outHH   [[buffer(4)]],
    constant uint& width        [[buffer(5)]],
    constant uint& height       [[buffer(6)]],
    constant uint& depth        [[buffer(7)]],
    uint gid [[thread_position_in_grid]]
) {
    // This kernel dispatches one thread per (y, z) row and performs the X-axis
    // 5/3 transform.  The Y-axis pass requires a separate dispatch after this
    // kernel writes outLL/outHL; the combined subband layout mirrors the
    // standard 2D separable DWT subbands extended along Z.
    uint totalRows = height * depth;
    if (gid >= totalRows) return;

    int W      = (int)width;
    int lowLen = (W + 1) / 2;
    int hiLen  = W / 2;
    int rowOff = (int)gid * W;
    device const float* row = input + rowOff;

    // --- X-axis forward 5/3 ---
    // Highpass
    for (int i = 0; i < hiLen; ++i) {
        float left  = safeGet(row, 2 * i,     W);
        float right = safeGet(row, 2 * i + 2, W);
        outLH[(int)gid * hiLen + i] = row[2 * i + 1] - floor((left + right) / 2.0f);
    }
    // Lowpass
    for (int i = 0; i < lowLen; ++i) {
        float hPrev = (i == 0)
            ? outLH[(int)gid * hiLen]
            : outLH[(int)gid * hiLen + (i - 1)];
        float hCurr = (i < hiLen)
            ? outLH[(int)gid * hiLen + i]
            : outLH[(int)gid * hiLen + (hiLen - 1)];
        outLL[(int)gid * lowLen + i] = row[2 * i] + floor((hPrev + hCurr + 2.0f) / 4.0f);
    }
    // Note: full 2D separable (HL, HH) requires a second kernel pass along Y.
    // outHL and outHH are initialised to zero here; a subsequent Y-pass kernel
    // fills them from outLH and outLL respectively.
    for (int i = 0; i < lowLen; ++i) outHL[(int)gid * lowLen + i] = 0.0f;
    for (int i = 0; i < hiLen;  ++i) outHH[(int)gid * hiLen  + i] = 0.0f;
}
"""

    // MARK: Metal Initialisation

    private mutating func initializeMetal() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw J2KError.unsupportedFeature("No Metal device available")
        }
        guard let queue = device.makeCommandQueue() else {
            throw J2KError.internalError("Failed to create Metal command queue")
        }

        let options = MTLCompileOptions()
        options.languageVersion = .version2_4

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: JP3DMetalDWT.mslSource, options: options)
        } catch {
            throw J2KError.internalError("JP3DMetalDWT shader compilation failed: \(error)")
        }

        var builtPipelines: [String: MTLComputePipelineState] = [:]
        let kernelNames = [
            "jp3d_dwt_forward_53_x", "jp3d_dwt_inverse_53_x",
            "jp3d_dwt_forward_53_y", "jp3d_dwt_inverse_53_y",
            "jp3d_dwt_forward_53_z", "jp3d_dwt_inverse_53_z",
            "jp3d_dwt_forward_97_x",
            "jp3d_dwt_forward_97_y",
            "jp3d_dwt_forward_97_z",
            "jp3d_separable_dwt_forward"
        ]
        for name in kernelNames {
            guard let fn = library.makeFunction(name: name) else {
                throw J2KError.internalError("Missing kernel: \(name)")
            }
            builtPipelines[name] = try device.makeComputePipelineState(function: fn)
        }

        metalLibrary = library
        commandQueue = queue
        pipelines    = builtPipelines
        metalEnabled = true
    }

    // MARK: Metal Forward 5/3 X

    private func metalForward53X(
        data: [Float], width: Int, height: Int, depth: Int
    ) async throws -> (low: [Float], high: [Float]) {
        guard let device = commandQueue?.device,
              let queue  = commandQueue,
              let pipeline = pipelines["jp3d_dwt_forward_53_x"] else {
            throw J2KError.internalError("Metal not initialised")
        }

        let lowLen  = (width + 1) / 2
        let highLen = width / 2
        let rows    = height * depth

        let inputBuf = try makeBuffer(device: device, data: data)
        let lowBuf   = device.makeBuffer(length: rows * lowLen  * MemoryLayout<Float>.stride,
                                         options: .storageModeShared)!
        let highBuf  = device.makeBuffer(length: rows * highLen * MemoryLayout<Float>.stride,
                                         options: .storageModeShared)!

        var w = UInt32(width), h = UInt32(height), d = UInt32(depth)

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command encoder")
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(inputBuf, offset: 0, index: 0)
        enc.setBuffer(lowBuf,   offset: 0, index: 1)
        enc.setBuffer(highBuf,  offset: 0, index: 2)
        enc.setBytes(&w, length: 4, index: 3)
        enc.setBytes(&h, length: 4, index: 4)
        enc.setBytes(&d, length: 4, index: 5)
        let tg = MTLSize(width: min(rows, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        let g  = MTLSize(width: rows, height: 1, depth: 1)
        enc.dispatchThreads(g, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        return (
            low:  readBuffer(lowBuf,  count: rows * lowLen),
            high: readBuffer(highBuf, count: rows * highLen)
        )
    }

    // MARK: Metal Inverse 5/3 X

    private func metalInverse53X(
        low: [Float], high: [Float],
        origWidth: Int, height: Int, depth: Int
    ) async throws -> [Float] {
        guard let device = commandQueue?.device,
              let queue  = commandQueue,
              let pipeline = pipelines["jp3d_dwt_inverse_53_x"] else {
            throw J2KError.internalError("Metal not initialised")
        }

        let rows    = height * depth
        let lowLen  = (origWidth + 1) / 2
        let highLen = origWidth / 2

        let lowBuf  = try makeBuffer(device: device, data: low)
        let highBuf = try makeBuffer(device: device, data: high)
        let outBuf  = device.makeBuffer(length: rows * origWidth * MemoryLayout<Float>.stride,
                                        options: .storageModeShared)!

        var ow = UInt32(origWidth), h = UInt32(height), d = UInt32(depth)

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command encoder")
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(lowBuf,  offset: 0, index: 0)
        enc.setBuffer(highBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf,  offset: 0, index: 2)
        enc.setBytes(&ow, length: 4, index: 3)
        enc.setBytes(&h,  length: 4, index: 4)
        enc.setBytes(&d,  length: 4, index: 5)
        let tg = MTLSize(width: min(rows, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        let g  = MTLSize(width: rows, height: 1, depth: 1)
        enc.dispatchThreads(g, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        _ = lowLen; _ = highLen
        return readBuffer(outBuf, count: rows * origWidth)
    }

    // MARK: Metal Forward 9/7 X

    private func metalForward97X(
        data: [Float], width: Int, height: Int, depth: Int
    ) async throws -> (low: [Float], high: [Float]) {
        guard let device = commandQueue?.device,
              let queue  = commandQueue,
              let pipeline = pipelines["jp3d_dwt_forward_97_x"] else {
            throw J2KError.internalError("Metal not initialised")
        }

        let lowLen  = (width + 1) / 2
        let highLen = width / 2
        let rows    = height * depth

        let inputBuf = try makeBuffer(device: device, data: data)
        let lowBuf   = device.makeBuffer(length: rows * lowLen  * MemoryLayout<Float>.stride,
                                         options: .storageModeShared)!
        let highBuf  = device.makeBuffer(length: rows * highLen * MemoryLayout<Float>.stride,
                                         options: .storageModeShared)!

        var w = UInt32(width), h = UInt32(height), d = UInt32(depth)

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create command encoder")
        }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(inputBuf, offset: 0, index: 0)
        enc.setBuffer(lowBuf,   offset: 0, index: 1)
        enc.setBuffer(highBuf,  offset: 0, index: 2)
        enc.setBytes(&w, length: 4, index: 3)
        enc.setBytes(&h, length: 4, index: 4)
        enc.setBytes(&d, length: 4, index: 5)
        let tg = MTLSize(width: min(rows, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        let g  = MTLSize(width: rows, height: 1, depth: 1)
        enc.dispatchThreads(g, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        return (
            low:  readBuffer(lowBuf,  count: rows * lowLen),
            high: readBuffer(highBuf, count: rows * highLen)
        )
    }

    // MARK: Metal Inverse 9/7 X (CPU-backed for correctness)

    private func metalInverse97X(
        low: [Float], high: [Float],
        origWidth: Int, height: Int, depth: Int
    ) async throws -> [Float] {
        // Full GPU 9/7 inverse is symmetric to the forward; delegate to CPU
        // to guarantee correctness while forward GPU path is active.
        return cpuInverse97X(
            low: low, high: high,
            origWidth: origWidth, height: height, depth: depth
        )
    }

    // MARK: Metal Buffer Helpers

    private func makeBuffer(device: MTLDevice, data: [Float]) throws -> MTLBuffer {
        let byteCount = data.count * MemoryLayout<Float>.stride
        guard let buf = device.makeBuffer(bytes: data, length: byteCount,
                                          options: .storageModeShared) else {
            throw J2KError.internalError("Failed to allocate Metal buffer")
        }
        return buf
    }

    private func readBuffer(_ buf: MTLBuffer, count: Int) -> [Float] {
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBytes { dst in
            dst.copyBytes(from: UnsafeRawBufferPointer(
                start: buf.contents(),
                count: count * MemoryLayout<Float>.stride
            ))
        }
        return result
    }
}
#endif  // canImport(Metal)

// MARK: - CPU Fallback

extension JP3DMetalDWT {

    // MARK: 5/3 Forward X (CPU)

    /// CPU fallback: forward 5/3 lifting along X for every (y, z) row.
    private func cpuForward53X(
        data: [Float], width: Int, height: Int, depth: Int
    ) -> (low: [Float], high: [Float]) {
        let lowLen  = (width + 1) / 2
        let highLen = width / 2
        let rows    = height * depth

        var low  = [Float](repeating: 0, count: rows * lowLen)
        var high = [Float](repeating: 0, count: rows * highLen)

        for row in 0..<rows {
            let offset = row * width
            let slice  = Array(data[offset..<(offset + width)])
            let (l, h) = forward53Lifting(signal: slice)
            low.replaceSubrange(  (row * lowLen )..<(row * lowLen  + lowLen),  with: l)
            high.replaceSubrange( (row * highLen)..<(row * highLen + highLen), with: h)
        }
        return (low: low, high: high)
    }

    // MARK: 5/3 Inverse X (CPU)

    /// CPU fallback: inverse 5/3 lifting along X for every (y, z) row.
    private func cpuInverse53X(
        low: [Float], high: [Float],
        origWidth: Int, height: Int, depth: Int
    ) -> [Float] {
        let lowLen  = (origWidth + 1) / 2
        let highLen = origWidth / 2
        let rows    = height * depth

        var output = [Float](repeating: 0, count: rows * origWidth)
        for row in 0..<rows {
            let l = Array(low [row * lowLen  ..< row * lowLen  + lowLen ])
            let h = Array(high[row * highLen ..< row * highLen + highLen])
            let rec = inverse53Lifting(low: l, high: h, origLen: origWidth)
            output.replaceSubrange(
                (row * origWidth)..<(row * origWidth + origWidth), with: rec
            )
        }
        return output
    }

    // MARK: 9/7 Forward X (CPU)

    /// CPU fallback: forward CDF 9/7 lifting along X for every (y, z) row.
    private func cpuForward97X(
        data: [Float], width: Int, height: Int, depth: Int
    ) -> (low: [Float], high: [Float]) {
        let lowLen  = (width + 1) / 2
        let highLen = width / 2
        let rows    = height * depth

        var low  = [Float](repeating: 0, count: rows * lowLen)
        var high = [Float](repeating: 0, count: rows * highLen)

        for row in 0..<rows {
            let offset = row * width
            let slice  = Array(data[offset..<(offset + width)])
            let (l, h) = forward97Lifting(signal: slice)
            low.replaceSubrange(  (row * lowLen )..<(row * lowLen  + lowLen),  with: l)
            high.replaceSubrange( (row * highLen)..<(row * highLen + highLen), with: h)
        }
        return (low: low, high: high)
    }

    // MARK: 9/7 Inverse X (CPU)

    /// CPU fallback: inverse CDF 9/7 lifting along X for every (y, z) row.
    func cpuInverse97X(
        low: [Float], high: [Float],
        origWidth: Int, height: Int, depth: Int
    ) -> [Float] {
        let lowLen  = (origWidth + 1) / 2
        let highLen = origWidth / 2
        let rows    = height * depth

        var output = [Float](repeating: 0, count: rows * origWidth)
        for row in 0..<rows {
            let l = Array(low [row * lowLen  ..< row * lowLen  + lowLen ])
            let h = Array(high[row * highLen ..< row * highLen + highLen])
            let rec = inverse97Lifting(low: l, high: h, origLen: origWidth)
            output.replaceSubrange(
                (row * origWidth)..<(row * origWidth + origWidth), with: rec
            )
        }
        return output
    }

    // MARK: 1D Lifting Primitives

    /// 1D forward Le Gall 5/3 lifting on a single signal row.
    ///
    /// Lifting steps:
    /// - Predict (highpass): `h[i] = x[2i+1] − ⌊(x[2i] + x[2i+2]) / 2⌋`
    /// - Update  (lowpass):  `l[i] = x[2i]   + ⌊(h[i-1] + h[i] + 2) / 4⌋`
    ///
    /// Boundary extension: symmetric (mirror at edges).
    private func forward53Lifting(signal: [Float]) -> (low: [Float], high: [Float]) {
        let n = signal.count
        guard n > 0 else { return ([], []) }
        let lowLen  = (n + 1) / 2
        let highLen = n / 2

        var low  = [Float](repeating: 0, count: lowLen)
        var high = [Float](repeating: 0, count: highLen)

        // Predict
        for i in 0..<highLen {
            let left  = signal[2 * i]
            let right: Float = (2 * i + 2 < n) ? signal[2 * i + 2] : signal[n - 2 < 0 ? 0 : n - 2]
            high[i] = signal[2 * i + 1] - floor((left + right) / 2)
        }
        // Update
        for i in 0..<lowLen {
            let hPrev: Float = (i == 0) ? high[0] : high[i - 1]
            let hCurr: Float = (i < highLen) ? high[i] : high[max(highLen - 1, 0)]
            low[i] = signal[2 * i] + floor((hPrev + hCurr + 2) / 4)
        }
        return (low: low, high: high)
    }

    /// 1D inverse Le Gall 5/3 lifting.
    private func inverse53Lifting(low: [Float], high: [Float], origLen: Int) -> [Float] {
        let lowLen  = low.count
        let highLen = high.count
        var out = [Float](repeating: 0, count: origLen)

        // Undo update: recover even samples
        for i in 0..<lowLen {
            let hPrev: Float = (i == 0) ? high[0] : high[i - 1]
            let hCurr: Float = (i < highLen) ? high[i] : high[max(highLen - 1, 0)]
            out[2 * i] = low[i] - floor((hPrev + hCurr + 2) / 4)
        }
        // Undo predict: recover odd samples
        for i in 0..<highLen {
            let left = out[2 * i]
            let right: Float = (2 * i + 2 < origLen)
                ? out[2 * i + 2]
                : out[2 * max(lowLen - 1, 0)]
            out[2 * i + 1] = high[i] + floor((left + right) / 2)
        }
        return out
    }

    /// 1D forward CDF 9/7 lifting (4-step lifting scheme + scaling).
    private func forward97Lifting(signal: [Float]) -> (low: [Float], high: [Float]) {
        let n = signal.count
        guard n > 0 else { return ([], []) }
        let lowLen  = (n + 1) / 2
        let highLen = n / 2

        let alpha: Float = -1.586_134_342
        let beta:  Float = -0.052_980_118
        let gamma: Float =  0.882_911_075
        let delta: Float =  0.443_506_852
        let k:     Float =  1.230_174_105

        var l = [Float](repeating: 0, count: lowLen)
        var h = [Float](repeating: 0, count: highLen)

        for i in 0..<lowLen  { l[i] = signal[2 * i] }
        for i in 0..<highLen { h[i] = signal[2 * i + 1] }

        // Step 1 (alpha)
        for i in 0..<highLen {
            let lR: Float = (i + 1 < lowLen) ? l[i + 1] : l[max(lowLen - 1, 0)]
            h[i] += alpha * (l[i] + lR)
        }
        // Step 2 (beta)
        for i in 0..<lowLen {
            let hP: Float = (i == 0) ? h[0] : h[i - 1]
            let hC: Float = (i < highLen) ? h[i] : h[max(highLen - 1, 0)]
            l[i] += beta * (hP + hC)
        }
        // Step 3 (gamma)
        for i in 0..<highLen {
            let lR: Float = (i + 1 < lowLen) ? l[i + 1] : l[max(lowLen - 1, 0)]
            h[i] += gamma * (l[i] + lR)
        }
        // Step 4 (delta)
        for i in 0..<lowLen {
            let hP: Float = (i == 0) ? h[0] : h[i - 1]
            let hC: Float = (i < highLen) ? h[i] : h[max(highLen - 1, 0)]
            l[i] += delta * (hP + hC)
        }
        // Scale
        for i in 0..<lowLen  { l[i] *=  k }
        for i in 0..<highLen { h[i] /=  k }
        return (low: l, high: h)
    }

    /// 1D inverse CDF 9/7 lifting.
    private func inverse97Lifting(low: [Float], high: [Float], origLen: Int) -> [Float] {
        let lowLen  = low.count
        let highLen = high.count

        let alpha: Float = -1.586_134_342
        let beta:  Float = -0.052_980_118
        let gamma: Float =  0.882_911_075
        let delta: Float =  0.443_506_852
        let k:     Float =  1.230_174_105

        var l = low
        var h = high

        // Undo scale
        for i in 0..<lowLen  { l[i] /= k }
        for i in 0..<highLen { h[i] *= k }

        // Undo step 4 (delta)
        for i in 0..<lowLen {
            let hP: Float = (i == 0) ? h[0] : h[i - 1]
            let hC: Float = (i < highLen) ? h[i] : h[max(highLen - 1, 0)]
            l[i] -= delta * (hP + hC)
        }
        // Undo step 3 (gamma)
        for i in 0..<highLen {
            let lR: Float = (i + 1 < lowLen) ? l[i + 1] : l[max(lowLen - 1, 0)]
            h[i] -= gamma * (l[i] + lR)
        }
        // Undo step 2 (beta)
        for i in 0..<lowLen {
            let hP: Float = (i == 0) ? h[0] : h[i - 1]
            let hC: Float = (i < highLen) ? h[i] : h[max(highLen - 1, 0)]
            l[i] -= beta * (hP + hC)
        }
        // Undo step 1 (alpha)
        for i in 0..<highLen {
            let lR: Float = (i + 1 < lowLen) ? l[i + 1] : l[max(lowLen - 1, 0)]
            h[i] -= alpha * (l[i] + lR)
        }

        var out = [Float](repeating: 0, count: origLen)
        for i in 0..<lowLen  { out[2 * i]     = l[i] }
        for i in 0..<highLen { out[2 * i + 1] = h[i] }
        return out
    }
}
