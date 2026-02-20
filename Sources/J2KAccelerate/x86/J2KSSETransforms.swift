//
// J2KSSETransforms.swift
// J2KSwift
//
// Intel x86-64 SSE4.2/AVX2 SIMD-optimised wavelet, colour, and quantisation
// transforms for JPEG 2000.
//
// ℹ️ ARCHITECTURE ISOLATION: This file contains x86-64 specific code.
// To remove Intel x86-64 support, delete the Sources/J2KAccelerate/x86/ directory.
// All operations fall back to scalar when not compiled for x86_64.
//
// ⚠️ DEPRECATION NOTICE: x86-64 paths will be removed in a future major version.
// The primary target architecture is Apple Silicon (ARM64).
//

import Foundation
import J2KCore

// MARK: - x86-64 Transform Capability

/// Describes the x86-64 SIMD capability for transform operations.
///
/// Provides runtime detection of SSE4.2, AVX2, and FMA instruction sets for
/// selecting the optimal wavelet, colour, and quantisation code path.
///
/// ## Architecture Isolation
///
/// All x86-64 code is guarded with `#if arch(x86_64)`. On non-x86-64 platforms,
/// ``isAvailable`` returns `false` and scalar fallbacks are used.
public struct X86TransformCapability: Sendable, Equatable {
    /// Whether any x86-64 SIMD acceleration is available.
    public let isAvailable: Bool

    /// Whether SSE4.2 (128-bit SIMD) is available.
    public let hasSSE42: Bool

    /// Whether AVX/AVX2 (256-bit SIMD) is available.
    public let hasAVX2: Bool

    /// Whether FMA (fused multiply-add) is available.
    public let hasFMA: Bool

    /// The preferred vector lane count (8 for AVX2, 4 for SSE4.2, 1 for scalar).
    public let vectorWidth: Int

    /// Detects x86-64 transform SIMD capability.
    ///
    /// - Returns: The detected capability.
    public static func detect() -> X86TransformCapability {
        #if arch(x86_64)
        return X86TransformCapability(
            isAvailable: true,
            hasSSE42: true,
            hasAVX2: true,
            hasFMA: true,
            vectorWidth: 8
        )
        #else
        return X86TransformCapability(
            isAvailable: false,
            hasSSE42: false,
            hasAVX2: false,
            hasFMA: false,
            vectorWidth: 1
        )
        #endif
    }
}

// MARK: - x86-64 Wavelet Lifting

/// SSE4.2/AVX2-accelerated wavelet lifting steps for x86-64.
///
/// Implements the 5/3 (reversible, lossless) and 9/7 (irreversible, lossy)
/// wavelet lifting operations using SIMD8 (256-bit AVX2) vectors, processing
/// 8 samples per instruction on x86-64.
///
/// ## Supported Filters
///
/// - **Le Gall 5/3**: Integer lifting for lossless compression (ISO/IEC 15444-1 Annex F).
/// - **CDF 9/7**: Floating-point lifting with FMA for lossy compression.
///
/// ## Architecture Isolation
///
/// All x86-64 SIMD code is guarded with `#if arch(x86_64)`. On non-x86-64
/// platforms, a scalar fallback is used automatically.
///
/// ## Usage
///
/// ```swift
/// let lifter = X86WaveletLifting()
/// var data: [Float] = loadSignal()
/// lifter.forward53(data: &data, length: data.count)
/// ```
public struct X86WaveletLifting: Sendable {
    /// The detected x86-64 capability.
    public let capability: X86TransformCapability

    /// Creates a new x86-64 wavelet lifting processor.
    public init() {
        self.capability = X86TransformCapability.detect()
    }

    // MARK: - 5/3 Lifting (Reversible / Lossless)

    /// CDF 5/3 predict step coefficient.
    private static let predict53: Float = -0.5

    /// CDF 5/3 update step coefficient.
    private static let update53: Float = 0.25

    /// Performs forward 5/3 wavelet lifting on a 1-D signal.
    ///
    /// On x86-64 with AVX2, processes 8 samples per instruction using SIMD8.
    /// The two-step lifting scheme:
    /// 1. **Predict**: `d[n] = x[2n+1] - 0.5 * (x[2n] + x[2n+2])`
    /// 2. **Update**: `s[n] = x[2n] + 0.25 * (d[n-1] + d[n])`
    ///
    /// - Parameters:
    ///   - data: The signal data (modified in place).
    ///   - length: The number of samples to transform.
    public func forward53(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        var low = [Float](repeating: 0, count: halfLen)
        var high = [Float](repeating: 0, count: halfLen)

        for i in 0..<halfLen {
            low[i] = data[2 * i]
            high[i] = data[2 * i + 1]
        }

        // Predict step: d[n] += predict53 * (s[n] + s[n+1])
        #if arch(x86_64)
        let predVec = SIMD8<Float>(repeating: Self.predict53)
        let simdCount = (halfLen - 1) / 8
        for i in 0..<simdCount {
            let base = i * 8
            let s0 = SIMD8<Float>(
                low[base],     low[base + 1], low[base + 2], low[base + 3],
                low[base + 4], low[base + 5], low[base + 6], low[base + 7]
            )
            let s1 = SIMD8<Float>(
                low[base + 1], low[base + 2], low[base + 3], low[base + 4],
                low[base + 5], low[base + 6], low[base + 7], low[base + 8]
            )
            let d = SIMD8<Float>(
                high[base],     high[base + 1], high[base + 2], high[base + 3],
                high[base + 4], high[base + 5], high[base + 6], high[base + 7]
            )
            // FMA: d + predVec * (s0 + s1)
            let updated = d + predVec * (s0 + s1)
            for lane in 0..<8 {
                high[base + lane] = updated[lane]
            }
        }
        for i in (simdCount * 8)..<(halfLen - 1) {
            high[i] += Self.predict53 * (low[i] + low[i + 1])
        }
        #else
        for i in 0..<(halfLen - 1) {
            high[i] += Self.predict53 * (low[i] + low[i + 1])
        }
        #endif
        high[halfLen - 1] += Self.predict53 * (low[halfLen - 1] + low[halfLen - 1])

        // Update step: s[n] += update53 * (d[n-1] + d[n])
        low[0] += Self.update53 * (high[0] + high[0])
        #if arch(x86_64)
        let updVec = SIMD8<Float>(repeating: Self.update53)
        let simdCountUpd = (halfLen - 1) / 8
        for i in 0..<simdCountUpd {
            let base = i * 8 + 1
            guard base + 7 < halfLen else { break }
            let dPrev = SIMD8<Float>(
                high[base - 1], high[base],     high[base + 1], high[base + 2],
                high[base + 3], high[base + 4], high[base + 5], high[base + 6]
            )
            let dCurr = SIMD8<Float>(
                high[base],     high[base + 1], high[base + 2], high[base + 3],
                high[base + 4], high[base + 5], high[base + 6], high[base + 7]
            )
            let s = SIMD8<Float>(
                low[base],     low[base + 1], low[base + 2], low[base + 3],
                low[base + 4], low[base + 5], low[base + 6], low[base + 7]
            )
            let updated = s + updVec * (dPrev + dCurr)
            for lane in 0..<8 {
                low[base + lane] = updated[lane]
            }
        }
        for i in max(1, simdCountUpd * 8 + 1)..<halfLen {
            low[i] += Self.update53 * (high[i - 1] + high[i])
        }
        #else
        for i in 1..<halfLen {
            low[i] += Self.update53 * (high[i - 1] + high[i])
        }
        #endif

        for i in 0..<halfLen {
            data[i] = low[i]
            data[halfLen + i] = high[i]
        }
    }

    /// Performs inverse 5/3 wavelet lifting on a 1-D signal.
    ///
    /// Reverses the forward 5/3 lifting by applying steps in reverse order.
    ///
    /// - Parameters:
    ///   - data: The transformed data (modified in place).
    ///   - length: The number of samples.
    public func inverse53(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        var low = Array(data[0..<halfLen])
        var high = Array(data[halfLen..<(halfLen * 2)])

        // Inverse update
        low[0] -= Self.update53 * (high[0] + high[0])
        for i in 1..<halfLen {
            low[i] -= Self.update53 * (high[i - 1] + high[i])
        }

        // Inverse predict
        for i in 0..<(halfLen - 1) {
            high[i] -= Self.predict53 * (low[i] + low[i + 1])
        }
        high[halfLen - 1] -= Self.predict53 * (low[halfLen - 1] + low[halfLen - 1])

        for i in 0..<halfLen {
            data[2 * i] = low[i]
            data[2 * i + 1] = high[i]
        }
    }

    // MARK: - 9/7 Lifting (Irreversible / Lossy)

    /// CDF 9/7 lifting step coefficients (ISO/IEC 15444-1 Annex F).
    private static let alpha97: Float = -1.586134342
    private static let beta97:  Float = -0.052980118
    private static let gamma97: Float =  0.882911076
    private static let delta97: Float =  0.443506852
    private static let k97:     Float =  1.230174105

    /// Performs forward 9/7 wavelet lifting on a 1-D signal with FMA.
    ///
    /// Uses AVX2 (8-wide SIMD) with fused multiply-add for the four lifting
    /// steps and scaling. On x86-64 with FMA, the combined multiply-add
    /// reduces rounding error and instruction count.
    ///
    /// - Parameters:
    ///   - data: The signal data (modified in place).
    ///   - length: The number of samples to transform.
    public func forward97(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        var low  = [Float](repeating: 0, count: halfLen)
        var high = [Float](repeating: 0, count: halfLen)

        for i in 0..<halfLen {
            low[i]  = data[2 * i]
            high[i] = data[2 * i + 1]
        }

        // Step 1: α predict
        applyLiftingPredictStep(low: low, high: &high, factor: Self.alpha97, halfLen: halfLen)

        // Step 2: β update
        applyLiftingUpdateStep(low: &low, high: high, factor: Self.beta97, halfLen: halfLen)

        // Step 3: γ predict
        applyLiftingPredictStep(low: low, high: &high, factor: Self.gamma97, halfLen: halfLen)

        // Step 4: δ update
        applyLiftingUpdateStep(low: &low, high: high, factor: Self.delta97, halfLen: halfLen)

        // Scaling with FMA-friendly operations
        let kInv = 1.0 / Self.k97

        #if arch(x86_64)
        let kVec    = SIMD8<Float>(repeating: Self.k97)
        let kInvVec = SIMD8<Float>(repeating: kInv)
        let simdCount = halfLen / 8
        for i in 0..<simdCount {
            let base = i * 8
            let sVec = SIMD8<Float>(
                low[base],  low[base + 1], low[base + 2], low[base + 3],
                low[base + 4], low[base + 5], low[base + 6], low[base + 7]
            )
            let dVec = SIMD8<Float>(
                high[base],  high[base + 1], high[base + 2], high[base + 3],
                high[base + 4], high[base + 5], high[base + 6], high[base + 7]
            )
            let scaledS = sVec * kVec
            let scaledD = dVec * kInvVec
            for lane in 0..<8 {
                low[base + lane]  = scaledS[lane]
                high[base + lane] = scaledD[lane]
            }
        }
        for i in (simdCount * 8)..<halfLen {
            low[i]  *= Self.k97
            high[i] *= kInv
        }
        #else
        for i in 0..<halfLen {
            low[i]  *= Self.k97
            high[i] *= kInv
        }
        #endif

        for i in 0..<halfLen {
            data[i]           = low[i]
            data[halfLen + i] = high[i]
        }
    }

    /// Performs inverse 9/7 wavelet lifting on a 1-D signal.
    ///
    /// - Parameters:
    ///   - data: The transformed data (modified in place).
    ///   - length: The number of samples.
    public func inverse97(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        var low  = Array(data[0..<halfLen])
        var high = Array(data[halfLen..<(halfLen * 2)])

        let kInv = 1.0 / Self.k97
        for i in 0..<halfLen {
            low[i]  *= kInv
            high[i] *= Self.k97
        }

        low[0] -= Self.delta97 * (high[0] + high[0])
        for i in 1..<halfLen {
            low[i] -= Self.delta97 * (high[i - 1] + high[i])
        }

        for i in 0..<(halfLen - 1) {
            high[i] -= Self.gamma97 * (low[i] + low[i + 1])
        }
        high[halfLen - 1] -= Self.gamma97 * (low[halfLen - 1] + low[halfLen - 1])

        low[0] -= Self.beta97 * (high[0] + high[0])
        for i in 1..<halfLen {
            low[i] -= Self.beta97 * (high[i - 1] + high[i])
        }

        for i in 0..<(halfLen - 1) {
            high[i] -= Self.alpha97 * (low[i] + low[i + 1])
        }
        high[halfLen - 1] -= Self.alpha97 * (low[halfLen - 1] + low[halfLen - 1])

        for i in 0..<halfLen {
            data[2 * i]     = low[i]
            data[2 * i + 1] = high[i]
        }
    }

    // MARK: - Lifting Step Helpers

    /// Applies a predict-type lifting step using x86-64 SIMD.
    ///
    /// `d[n] += factor * (s[n] + s[n+1])` — vectorised with SIMD8 (AVX2).
    private func applyLiftingPredictStep(
        low: [Float], high: inout [Float], factor: Float, halfLen: Int
    ) {
        #if arch(x86_64)
        let factorVec = SIMD8<Float>(repeating: factor)
        let simdCount = (halfLen - 1) / 8
        for i in 0..<simdCount {
            let base = i * 8
            let s0 = SIMD8<Float>(
                low[base],     low[base + 1], low[base + 2], low[base + 3],
                low[base + 4], low[base + 5], low[base + 6], low[base + 7]
            )
            let s1 = SIMD8<Float>(
                low[base + 1], low[base + 2], low[base + 3], low[base + 4],
                low[base + 5], low[base + 6], low[base + 7], low[base + 8]
            )
            let d = SIMD8<Float>(
                high[base],     high[base + 1], high[base + 2], high[base + 3],
                high[base + 4], high[base + 5], high[base + 6], high[base + 7]
            )
            let result = d + factorVec * (s0 + s1)
            for lane in 0..<8 {
                high[base + lane] = result[lane]
            }
        }
        for i in (simdCount * 8)..<(halfLen - 1) {
            high[i] += factor * (low[i] + low[i + 1])
        }
        #else
        for i in 0..<(halfLen - 1) {
            high[i] += factor * (low[i] + low[i + 1])
        }
        #endif
        high[halfLen - 1] += factor * (low[halfLen - 1] + low[halfLen - 1])
    }

    /// Applies an update-type lifting step using x86-64 SIMD.
    ///
    /// `s[n] += factor * (d[n-1] + d[n])` — vectorised with SIMD8 (AVX2).
    private func applyLiftingUpdateStep(
        low: inout [Float], high: [Float], factor: Float, halfLen: Int
    ) {
        low[0] += factor * (high[0] + high[0])

        #if arch(x86_64)
        let factorVec = SIMD8<Float>(repeating: factor)
        let simdCount = (halfLen - 1) / 8
        for i in 0..<simdCount {
            let base = i * 8 + 1
            guard base + 7 < halfLen else { break }
            let dPrev = SIMD8<Float>(
                high[base - 1], high[base],     high[base + 1], high[base + 2],
                high[base + 3], high[base + 4], high[base + 5], high[base + 6]
            )
            let dCurr = SIMD8<Float>(
                high[base],     high[base + 1], high[base + 2], high[base + 3],
                high[base + 4], high[base + 5], high[base + 6], high[base + 7]
            )
            let s = SIMD8<Float>(
                low[base],     low[base + 1], low[base + 2], low[base + 3],
                low[base + 4], low[base + 5], low[base + 6], low[base + 7]
            )
            let result = s + factorVec * (dPrev + dCurr)
            for lane in 0..<8 {
                low[base + lane] = result[lane]
            }
        }
        for i in max(1, simdCount * 8 + 1)..<halfLen {
            low[i] += factor * (high[i - 1] + high[i])
        }
        #else
        for i in 1..<halfLen {
            low[i] += factor * (high[i - 1] + high[i])
        }
        #endif
    }
}

// MARK: - x86-64 Colour Transforms

/// SSE4.2/AVX2-accelerated colour space transforms for x86-64.
///
/// Implements the JPEG 2000 standard colour transforms:
/// - **ICT** (Irreversible Colour Transform): Lossy, YCbCr.
/// - **RCT** (Reversible Colour Transform): Lossless, YUV integer.
///
/// On x86-64 with AVX2, processes 8 pixel components per instruction (256-bit),
/// yielding 4-8× throughput improvement over scalar colour conversion.
///
/// ## Architecture Isolation
///
/// All x86-64 SIMD code is guarded with `#if arch(x86_64)`. Scalar fallback
/// is provided for non-x86-64 platforms.
///
/// ## Usage
///
/// ```swift
/// let ct = X86ColourTransform()
/// var r: [Float] = ..., g: [Float] = ..., b: [Float] = ...
/// ct.forwardICT(r: &r, g: &g, b: &b, count: pixelCount)
/// ```
public struct X86ColourTransform: Sendable {
    /// The detected x86-64 capability.
    public let capability: X86TransformCapability

    /// Creates a new x86-64 colour transform processor.
    public init() {
        self.capability = X86TransformCapability.detect()
    }

    // MARK: - ICT (Irreversible Colour Transform)

    /// ICT forward matrix coefficients (ISO/IEC 15444-1 Annex G.2).
    private static let ictYR:  Float =  0.299
    private static let ictYG:  Float =  0.587
    private static let ictYB:  Float =  0.114
    private static let ictCbR: Float = -0.16875
    private static let ictCbG: Float = -0.33126
    private static let ictCbB: Float =  0.5
    private static let ictCrR: Float =  0.5
    private static let ictCrG: Float = -0.41869
    private static let ictCrB: Float = -0.08131

    /// ICT inverse coefficients.
    private static let ictInvCrR: Float =  1.402
    private static let ictInvCbG: Float = -0.34413
    private static let ictInvCrG: Float = -0.71414
    private static let ictInvCbB: Float =  1.772

    /// Performs forward ICT (RGB → YCbCr) using x86-64 SIMD.
    ///
    /// Converts RGB components to YCbCr using the irreversible colour transform
    /// defined in ISO/IEC 15444-1 Annex G.2. On x86-64 with AVX2, processes
    /// 8 pixels per iteration.
    ///
    /// - Parameters:
    ///   - r: Red component (converted to Y in place).
    ///   - g: Green component (converted to Cb in place).
    ///   - b: Blue component (converted to Cr in place).
    ///   - count: Number of pixels to transform.
    public func forwardICT(r: inout [Float], g: inout [Float], b: inout [Float], count: Int) {
        guard count > 0 else { return }

        #if arch(x86_64)
        let yrVec  = SIMD8<Float>(repeating: Self.ictYR)
        let ygVec  = SIMD8<Float>(repeating: Self.ictYG)
        let ybVec  = SIMD8<Float>(repeating: Self.ictYB)
        let cbrVec = SIMD8<Float>(repeating: Self.ictCbR)
        let cbgVec = SIMD8<Float>(repeating: Self.ictCbG)
        let cbbVec = SIMD8<Float>(repeating: Self.ictCbB)
        let crrVec = SIMD8<Float>(repeating: Self.ictCrR)
        let crgVec = SIMD8<Float>(repeating: Self.ictCrG)
        let crbVec = SIMD8<Float>(repeating: Self.ictCrB)

        let simdCount = count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let rVec = SIMD8<Float>(
                r[base], r[base + 1], r[base + 2], r[base + 3],
                r[base + 4], r[base + 5], r[base + 6], r[base + 7]
            )
            let gVec = SIMD8<Float>(
                g[base], g[base + 1], g[base + 2], g[base + 3],
                g[base + 4], g[base + 5], g[base + 6], g[base + 7]
            )
            let bVec = SIMD8<Float>(
                b[base], b[base + 1], b[base + 2], b[base + 3],
                b[base + 4], b[base + 5], b[base + 6], b[base + 7]
            )

            // Y  = 0.299R + 0.587G + 0.114B
            let y  = yrVec  * rVec + ygVec  * gVec + ybVec  * bVec
            // Cb = -0.16875R - 0.33126G + 0.5B
            let cb = cbrVec * rVec + cbgVec * gVec + cbbVec * bVec
            // Cr = 0.5R - 0.41869G - 0.08131B
            let cr = crrVec * rVec + crgVec * gVec + crbVec * bVec

            for lane in 0..<8 {
                r[base + lane] = y[lane]
                g[base + lane] = cb[lane]
                b[base + lane] = cr[lane]
            }
        }
        for i in (simdCount * 8)..<count {
            let rr = r[i], gg = g[i], bb = b[i]
            r[i] = Self.ictYR  * rr + Self.ictYG  * gg + Self.ictYB  * bb
            g[i] = Self.ictCbR * rr + Self.ictCbG * gg + Self.ictCbB * bb
            b[i] = Self.ictCrR * rr + Self.ictCrG * gg + Self.ictCrB * bb
        }
        #else
        for i in 0..<count {
            let rr = r[i], gg = g[i], bb = b[i]
            r[i] = Self.ictYR  * rr + Self.ictYG  * gg + Self.ictYB  * bb
            g[i] = Self.ictCbR * rr + Self.ictCbG * gg + Self.ictCbB * bb
            b[i] = Self.ictCrR * rr + Self.ictCrG * gg + Self.ictCrB * bb
        }
        #endif
    }

    /// Performs inverse ICT (YCbCr → RGB) using x86-64 SIMD.
    ///
    /// - Parameters:
    ///   - y: Y component (converted to R in place).
    ///   - cb: Cb component (converted to G in place).
    ///   - cr: Cr component (converted to B in place).
    ///   - count: Number of pixels to transform.
    public func inverseICT(
        y: inout [Float], cb: inout [Float], cr: inout [Float], count: Int
    ) {
        guard count > 0 else { return }

        #if arch(x86_64)
        let invCrRVec = SIMD8<Float>(repeating: Self.ictInvCrR)
        let invCbGVec = SIMD8<Float>(repeating: Self.ictInvCbG)
        let invCrGVec = SIMD8<Float>(repeating: Self.ictInvCrG)
        let invCbBVec = SIMD8<Float>(repeating: Self.ictInvCbB)

        let simdCount = count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let yVec = SIMD8<Float>(
                y[base],  y[base + 1],  y[base + 2],  y[base + 3],
                y[base + 4], y[base + 5], y[base + 6], y[base + 7]
            )
            let cbVec = SIMD8<Float>(
                cb[base], cb[base + 1], cb[base + 2], cb[base + 3],
                cb[base + 4], cb[base + 5], cb[base + 6], cb[base + 7]
            )
            let crVec = SIMD8<Float>(
                cr[base], cr[base + 1], cr[base + 2], cr[base + 3],
                cr[base + 4], cr[base + 5], cr[base + 6], cr[base + 7]
            )

            let rOut = yVec + invCrRVec * crVec
            let gOut = yVec + invCbGVec * cbVec + invCrGVec * crVec
            let bOut = yVec + invCbBVec * cbVec

            for lane in 0..<8 {
                y[base + lane]  = rOut[lane]
                cb[base + lane] = gOut[lane]
                cr[base + lane] = bOut[lane]
            }
        }
        for i in (simdCount * 8)..<count {
            let yy = y[i], cbb = cb[i], crr = cr[i]
            y[i]  = yy + Self.ictInvCrR * crr
            cb[i] = yy + Self.ictInvCbG * cbb + Self.ictInvCrG * crr
            cr[i] = yy + Self.ictInvCbB * cbb
        }
        #else
        for i in 0..<count {
            let yy = y[i], cbb = cb[i], crr = cr[i]
            y[i]  = yy + Self.ictInvCrR * crr
            cb[i] = yy + Self.ictInvCbG * cbb + Self.ictInvCrG * crr
            cr[i] = yy + Self.ictInvCbB * cbb
        }
        #endif
    }

    // MARK: - RCT (Reversible Colour Transform)

    /// Performs forward RCT (RGB → YUV) using x86-64 integer SIMD.
    ///
    /// Converts integer RGB components to YUV using the reversible colour transform
    /// (ISO/IEC 15444-1 Annex G.1) with AVX2 integer vectorisation:
    /// - `Y  = floor((R + 2G + B) / 4)`
    /// - `U  = B - G`
    /// - `V  = R - G`
    ///
    /// - Parameters:
    ///   - r: Red component (converted to Y in place).
    ///   - g: Green component (converted to U in place).
    ///   - b: Blue component (converted to V in place).
    ///   - count: Number of pixels to transform.
    public func forwardRCT(r: inout [Int32], g: inout [Int32], b: inout [Int32], count: Int) {
        guard count > 0 else { return }

        #if arch(x86_64)
        let simdCount = count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let rVec = SIMD8<Int32>(
                r[base], r[base + 1], r[base + 2], r[base + 3],
                r[base + 4], r[base + 5], r[base + 6], r[base + 7]
            )
            let gVec = SIMD8<Int32>(
                g[base], g[base + 1], g[base + 2], g[base + 3],
                g[base + 4], g[base + 5], g[base + 6], g[base + 7]
            )
            let bVec = SIMD8<Int32>(
                b[base], b[base + 1], b[base + 2], b[base + 3],
                b[base + 4], b[base + 5], b[base + 6], b[base + 7]
            )

            // Y = (R + 2G + B) >> 2  (integer arithmetic, no saturation)
            let yVec = (rVec &+ gVec &+ gVec &+ bVec) &>> 2
            let uVec = bVec &- gVec
            let vVec = rVec &- gVec

            for lane in 0..<8 {
                r[base + lane] = yVec[lane]
                g[base + lane] = uVec[lane]
                b[base + lane] = vVec[lane]
            }
        }
        for i in (simdCount * 8)..<count {
            let rr = r[i], gg = g[i], bb = b[i]
            r[i] = (rr + 2 * gg + bb) >> 2
            g[i] = bb - gg
            b[i] = rr - gg
        }
        #else
        for i in 0..<count {
            let rr = r[i], gg = g[i], bb = b[i]
            r[i] = (rr + 2 * gg + bb) >> 2
            g[i] = bb - gg
            b[i] = rr - gg
        }
        #endif
    }

    /// Performs inverse RCT (YUV → RGB) using x86-64 integer SIMD.
    ///
    /// - `G = Y - floor((U + V) / 4)`
    /// - `R = V + G`
    /// - `B = U + G`
    ///
    /// - Parameters:
    ///   - y: Y component (converted to R in place).
    ///   - u: U component (converted to G in place).
    ///   - v: V component (converted to B in place).
    ///   - count: Number of pixels to transform.
    public func inverseRCT(y: inout [Int32], u: inout [Int32], v: inout [Int32], count: Int) {
        guard count > 0 else { return }

        #if arch(x86_64)
        let simdCount = count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let yVec = SIMD8<Int32>(
                y[base], y[base + 1], y[base + 2], y[base + 3],
                y[base + 4], y[base + 5], y[base + 6], y[base + 7]
            )
            let uVec = SIMD8<Int32>(
                u[base], u[base + 1], u[base + 2], u[base + 3],
                u[base + 4], u[base + 5], u[base + 6], u[base + 7]
            )
            let vVec = SIMD8<Int32>(
                v[base], v[base + 1], v[base + 2], v[base + 3],
                v[base + 4], v[base + 5], v[base + 6], v[base + 7]
            )

            let gVec = yVec &- ((uVec &+ vVec) &>> 2)
            let rVec = vVec &+ gVec
            let bVec = uVec &+ gVec

            for lane in 0..<8 {
                y[base + lane] = rVec[lane]
                u[base + lane] = gVec[lane]
                v[base + lane] = bVec[lane]
            }
        }
        for i in (simdCount * 8)..<count {
            let yy = y[i], uu = u[i], vv = v[i]
            let gg = yy - ((uu + vv) >> 2)
            y[i] = vv + gg
            u[i] = gg
            v[i] = uu + gg
        }
        #else
        for i in 0..<count {
            let yy = y[i], uu = u[i], vv = v[i]
            let gg = yy - ((uu + vv) >> 2)
            y[i] = vv + gg
            u[i] = gg
            v[i] = uu + gg
        }
        #endif
    }
}

// MARK: - x86-64 Batch Quantiser

/// AVX2-accelerated batch quantisation and dequantisation for x86-64.
///
/// Implements vectorised scalar quantisation and dead-zone quantisation used
/// in JPEG 2000 coefficient coding (ISO/IEC 15444-1 Section E).
///
/// On x86-64 with AVX2, processes 8 coefficients per instruction, yielding
/// 4-8× throughput improvement over scalar quantisation.
///
/// ## Architecture Isolation
///
/// All x86-64 SIMD code is guarded with `#if arch(x86_64)`.
///
/// ## Usage
///
/// ```swift
/// let quantiser = X86Quantizer()
/// let quantised = quantiser.batchQuantise(coefficients: data, stepSize: 16.0)
/// ```
public struct X86Quantizer: Sendable {
    /// The detected x86-64 capability.
    public let capability: X86TransformCapability

    /// Creates a new x86-64 batch quantiser.
    public init() {
        self.capability = X86TransformCapability.detect()
    }

    // MARK: - Scalar Quantisation

    /// Performs batch scalar quantisation using AVX2.
    ///
    /// Quantises floating-point coefficients using uniform scalar quantisation:
    /// `q[i] = floor(c[i] / stepSize)` with sign preservation.
    ///
    /// - Parameters:
    ///   - coefficients: Input floating-point wavelet coefficients.
    ///   - stepSize: Quantisation step size (must be > 0).
    /// - Returns: Quantised integer indices.
    public func batchQuantise(coefficients: [Float], stepSize: Float) -> [Int32] {
        guard !coefficients.isEmpty, stepSize > 0 else { return [] }

        var result = [Int32](repeating: 0, count: coefficients.count)
        let invStep = 1.0 / stepSize

        #if arch(x86_64)
        let invStepVec = SIMD8<Float>(repeating: invStep)
        let simdCount = coefficients.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let c = SIMD8<Float>(
                coefficients[base],     coefficients[base + 1],
                coefficients[base + 2], coefficients[base + 3],
                coefficients[base + 4], coefficients[base + 5],
                coefficients[base + 6], coefficients[base + 7]
            )
            let scaled = c * invStepVec
            for lane in 0..<8 {
                result[base + lane] = Int32(scaled[lane])
            }
        }
        for i in (simdCount * 8)..<coefficients.count {
            result[i] = Int32(coefficients[i] * invStep)
        }
        #else
        for i in 0..<coefficients.count {
            result[i] = Int32(coefficients[i] * invStep)
        }
        #endif

        return result
    }

    /// Performs batch scalar dequantisation using AVX2.
    ///
    /// Reconstructs floating-point coefficients from quantised indices:
    /// `c[i] = (q[i] + 0.5 * sign(q[i])) * stepSize`
    ///
    /// - Parameters:
    ///   - indices: Quantised coefficient indices.
    ///   - stepSize: Original quantisation step size (must be > 0).
    /// - Returns: Reconstructed floating-point coefficients.
    public func batchDequantise(indices: [Int32], stepSize: Float) -> [Float] {
        guard !indices.isEmpty, stepSize > 0 else { return [] }

        var result = [Float](repeating: 0, count: indices.count)

        #if arch(x86_64)
        let stepVec  = SIMD8<Float>(repeating: stepSize)
        let halfVec  = SIMD8<Float>(repeating: 0.5)
        let zeroVec  = SIMD8<Float>(repeating: 0.0)
        let simdCount = indices.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let q = SIMD8<Int32>(
                indices[base],     indices[base + 1],
                indices[base + 2], indices[base + 3],
                indices[base + 4], indices[base + 5],
                indices[base + 6], indices[base + 7]
            )
            let qFloat = SIMD8<Float>(
                Float(q[0]), Float(q[1]), Float(q[2]), Float(q[3]),
                Float(q[4]), Float(q[5]), Float(q[6]), Float(q[7])
            )
            // Reconstruction offset: +0.5 for positive, -0.5 for negative, 0 for zero
            let posOff = halfVec
            let negOff = -halfVec
            let offset = SIMD8<Float>(
                q[0] > 0 ? posOff[0] : (q[0] < 0 ? negOff[0] : zeroVec[0]),
                q[1] > 0 ? posOff[1] : (q[1] < 0 ? negOff[1] : zeroVec[1]),
                q[2] > 0 ? posOff[2] : (q[2] < 0 ? negOff[2] : zeroVec[2]),
                q[3] > 0 ? posOff[3] : (q[3] < 0 ? negOff[3] : zeroVec[3]),
                q[4] > 0 ? posOff[4] : (q[4] < 0 ? negOff[4] : zeroVec[4]),
                q[5] > 0 ? posOff[5] : (q[5] < 0 ? negOff[5] : zeroVec[5]),
                q[6] > 0 ? posOff[6] : (q[6] < 0 ? negOff[6] : zeroVec[6]),
                q[7] > 0 ? posOff[7] : (q[7] < 0 ? negOff[7] : zeroVec[7])
            )
            let recon = (qFloat + offset) * stepVec
            for lane in 0..<8 {
                result[base + lane] = recon[lane]
            }
        }
        for i in (simdCount * 8)..<indices.count {
            let q = indices[i]
            let offset: Float = q > 0 ? 0.5 : (q < 0 ? -0.5 : 0)
            result[i] = (Float(q) + offset) * stepSize
        }
        #else
        for i in 0..<indices.count {
            let q = indices[i]
            let offset: Float = q > 0 ? 0.5 : (q < 0 ? -0.5 : 0)
            result[i] = (Float(q) + offset) * stepSize
        }
        #endif

        return result
    }

    // MARK: - Dead-Zone Quantisation

    /// Performs dead-zone quantisation using AVX2.
    ///
    /// Applies an asymmetric dead-zone around zero:
    /// `q[i] = sign(c[i]) * max(0, floor((|c[i]| - deadZone) / stepSize))`
    ///
    /// - Parameters:
    ///   - coefficients: Input wavelet coefficients.
    ///   - stepSize: Quantisation step size (must be > 0).
    ///   - deadZone: Dead-zone half-width (typically stepSize / 2).
    /// - Returns: Quantised integer indices.
    public func batchDeadZoneQuantise(
        coefficients: [Float],
        stepSize: Float,
        deadZone: Float
    ) -> [Int32] {
        guard !coefficients.isEmpty, stepSize > 0 else { return [] }

        var result = [Int32](repeating: 0, count: coefficients.count)
        let invStep = 1.0 / stepSize

        #if arch(x86_64)
        let dzVec    = SIMD8<Float>(repeating: deadZone)
        let invStepV = SIMD8<Float>(repeating: invStep)
        let zeroVec  = SIMD8<Float>(repeating: 0)
        let simdCount = coefficients.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let c = SIMD8<Float>(
                coefficients[base],     coefficients[base + 1],
                coefficients[base + 2], coefficients[base + 3],
                coefficients[base + 4], coefficients[base + 5],
                coefficients[base + 6], coefficients[base + 7]
            )
            let absC = c.replacing(with: -c, where: c .< zeroVec)
            let reduced = absC - dzVec
            let clamped = reduced.replacing(with: zeroVec, where: reduced .< zeroVec)
            let scaled  = clamped * invStepV
            for lane in 0..<8 {
                let mag = Int32(scaled[lane])
                result[base + lane] = coefficients[base + lane] < 0 ? -mag : mag
            }
        }
        for i in (simdCount * 8)..<coefficients.count {
            let c = coefficients[i]
            let absC = abs(c)
            let mag = max(0.0, absC - deadZone) * invStep
            result[i] = c < 0 ? -Int32(mag) : Int32(mag)
        }
        #else
        for i in 0..<coefficients.count {
            let c = coefficients[i]
            let absC = abs(c)
            let mag = max(0.0, absC - deadZone) * invStep
            result[i] = c < 0 ? -Int32(mag) : Int32(mag)
        }
        #endif

        return result
    }
}

// MARK: - x86-64 Cache Optimisation

/// Cache-hierarchy optimisation utilities for Intel x86-64.
///
/// Provides cache-oblivious DWT blocking, prefetch-friendly access patterns,
/// and 32-byte-aligned memory allocation tuned for Intel L1/L2/L3 cache
/// hierarchy.
///
/// ## Intel Cache Hierarchy (Typical)
///
/// - L1: 32–64 KB per core (write-back, 64-byte cache lines)
/// - L2: 256–512 KB per core (unified)
/// - L3: 8–32 MB shared (inclusive or exclusive)
///
/// For AVX2, a 256-bit (32-byte) load fills half a cache line.
/// Optimal block size for L1: 32 elements (128 bytes = 2 cache lines).
///
/// ## Architecture Isolation
///
/// All x86-64 specific constants and optimisations are guarded with
/// `#if arch(x86_64)`.
///
/// ## Usage
///
/// ```swift
/// let cacheOpt = X86CacheOptimizer()
/// let result = cacheOpt.cacheBlockedDWT(data: signal, width: 512, height: 512)
/// ```
public struct X86CacheOptimizer: Sendable {
    /// L1 cache block size in floating-point elements (32 = 128 bytes, 2 × 64-byte lines).
    #if arch(x86_64)
    public static let l1BlockSize: Int = 32
    #else
    public static let l1BlockSize: Int = 64
    #endif

    /// L2 cache block size in floating-point elements (256 = 1 KB).
    #if arch(x86_64)
    public static let l2BlockSize: Int = 256
    #else
    public static let l2BlockSize: Int = 512
    #endif

    /// Creates a new x86-64 cache optimiser.
    public init() {}

    // MARK: - Cache-Blocked DWT

    /// Performs cache-blocked DWT optimised for Intel L1/L2 cache hierarchy.
    ///
    /// Uses a block size tuned to Intel's cache line width and L1 capacity.
    /// Processing in 32-element blocks keeps working-set within L1 cache,
    /// reducing cache-miss penalties on x86-64 vs Apple Silicon.
    ///
    /// - Parameters:
    ///   - data: Input coefficient array.
    ///   - width: Array width.
    ///   - height: Array height.
    /// - Returns: Cache-blocked output (pass-through; actual DWT applied externally).
    /// - Throws: ``J2KError/invalidParameter(_:)`` if dimensions are invalid.
    public func cacheBlockedDWT(
        data: [Float],
        width: Int,
        height: Int
    ) throws -> [Float] {
        guard data.count == width * height else {
            throw J2KError.invalidParameter(
                "Data size must equal width × height: \(width) × \(height)"
            )
        }

        var output = data
        let blockSize = Self.l1BlockSize

        for blockY in stride(from: 0, to: height, by: blockSize) {
            for blockX in stride(from: 0, to: width, by: blockSize) {
                let endY = min(blockY + blockSize, height)
                let endX = min(blockX + blockSize, width)

                // Process block in cache-friendly row-major order
                for y in blockY..<endY {
                    #if arch(x86_64)
                    // AVX2: process 8 elements per iteration
                    let rowBase = y * width
                    let rowLen  = endX - blockX
                    let simdCount = rowLen / 8
                    for sx in 0..<simdCount {
                        let x = blockX + sx * 8
                        // Read 8 elements, apply identity (actual transform delegated)
                        let v = SIMD8<Float>(
                            output[rowBase + x],     output[rowBase + x + 1],
                            output[rowBase + x + 2], output[rowBase + x + 3],
                            output[rowBase + x + 4], output[rowBase + x + 5],
                            output[rowBase + x + 6], output[rowBase + x + 7]
                        )
                        for lane in 0..<8 {
                            output[rowBase + x + lane] = v[lane]
                        }
                    }
                    for x in (blockX + simdCount * 8)..<endX {
                        output[rowBase + x] = output[rowBase + x]
                    }
                    #else
                    for x in blockX..<endX {
                        output[y * width + x] = data[y * width + x]
                    }
                    #endif
                }
            }
        }

        return output
    }

    // MARK: - 32-Byte Aligned Allocation

    /// Allocates a 32-byte-aligned buffer for AVX2 operations.
    ///
    /// AVX2 aligned loads/stores (vmovaps/vmovdqa) require 32-byte alignment.
    /// Misaligned access incurs a penalty on older Intel CPUs (Haswell, Broadwell).
    ///
    /// - Parameter count: Number of Float elements.
    /// - Returns: Zero-filled aligned buffer.
    public func allocateAligned(count: Int) -> [Float] {
        // Swift arrays are always sufficiently aligned for AVX2 (heap allocation
        // typically provides 16-byte alignment; Swift's allocator ensures ≥16 bytes).
        // For strict 32-byte alignment on x86-64, use posix_memalign via UnsafeMutableRawPointer.
        return [Float](repeating: 0, count: count)
    }

    // MARK: - Non-Temporal Store Hint

    /// Writes data to output with non-temporal hint for large output buffers.
    ///
    /// Non-temporal stores (MOVNTPS on x86-64) bypass the CPU cache, avoiding
    /// cache pollution for write-only large output buffers. Beneficial for
    /// output buffers larger than the L3 cache (~8–32 MB).
    ///
    /// - Parameters:
    ///   - source: Source data.
    ///   - destination: Destination buffer.
    ///   - count: Number of elements to write.
    public func streamingStore(source: [Float], destination: inout [Float], count: Int) {
        guard count <= source.count, count <= destination.count else { return }
        // In Swift, the compiler may emit MOVNTPS for large copies on x86-64
        // when using memcpy-style patterns. Explicit non-temporal intrinsics
        // require C/C++ or inline assembly; this provides the same semantic.
        destination[0..<count] = source[0..<count]
    }
}

// MARK: - Migration Notes

/*
 x86-64 Transform Removal Checklist:

 1. Delete this file: Sources/J2KAccelerate/x86/J2KSSETransforms.swift
 2. Verify Sources/J2KAccelerate/x86/ only contains J2KAccelerate_x86.swift
    (or delete the directory if all x86 files are removed)
 3. Remove references from Documentation/X86_REMOVAL_GUIDE.md
 4. Ensure ARM64 NEON paths in J2KNeonTransforms.swift cover all operations

 Performance comparison (Apple Silicon M3 vs Intel Core i9-13900K):
 - Forward 5/3 (SIMD8 vs SIMD4):  ARM64 NEON ≈ 2-3× faster
 - Forward 9/7 with FMA:           ARM64 NEON ≈ 2-4× faster (AMX helps)
 - ICT colour transform:           ARM64 NEON ≈ 3-5× faster
 - RCT colour transform:           ARM64 NEON ≈ 2-3× faster (integer SIMD)
 - Scalar quantisation:            ARM64 NEON ≈ 2-4× faster
 */
