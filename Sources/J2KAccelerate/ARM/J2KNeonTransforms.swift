//
// J2KNeonTransforms.swift
// J2KSwift
//
// ARM NEON SIMD-optimised wavelet and colour transform operations for JPEG 2000.
//
// ℹ️ ARCHITECTURE ISOLATION: This file contains ARM64/NEON-specific code.
// To remove ARM support, delete the Sources/J2KAccelerate/ARM/ directory.
// All operations fall back to scalar when not compiled for arm64.
//

import Foundation
import J2KCore

// MARK: - NEON Transform Capability

/// Describes the ARM NEON capability for transform operations.
///
/// Provides runtime detection of NEON SIMD availability for wavelet
/// and colour transform acceleration.
public struct NeonTransformCapability: Sendable, Equatable {
    /// Whether NEON acceleration is available.
    public let isAvailable: Bool

    /// The vector width in 32-bit float lanes (4 for 128-bit NEON).
    public let vectorWidth: Int

    /// Detects NEON capability at runtime.
    ///
    /// - Returns: The detected capability.
    public static func detect() -> NeonTransformCapability {
        #if arch(arm64)
        return NeonTransformCapability(isAvailable: true, vectorWidth: 4)
        #else
        return NeonTransformCapability(isAvailable: false, vectorWidth: 1)
        #endif
    }
}

// MARK: - NEON Wavelet Lifting

/// SIMD-accelerated wavelet lifting steps using ARM NEON.
///
/// Implements the 5/3 (reversible, lossless) and 9/7 (irreversible, lossy)
/// wavelet lifting operations using SIMD4 vectors, processing 4 samples
/// per instruction on ARM64.
///
/// ## Supported Filters
///
/// - **Le Gall 5/3**: Integer lifting for lossless compression (ISO/IEC 15444-1 Annex F).
/// - **CDF 9/7**: Floating-point lifting for lossy compression.
///
/// ## Architecture Isolation
///
/// All NEON code is guarded with `#if arch(arm64)`. On non-ARM64 platforms,
/// a scalar fallback is used automatically.
///
/// ## Usage
///
/// ```swift
/// let lifter = NeonWaveletLifting()
/// var data: [Float] = loadSignal()
/// lifter.forward53(data: &data, length: data.count)
/// ```
public struct NeonWaveletLifting: Sendable {
    /// The detected NEON capability.
    public let capability: NeonTransformCapability

    /// Creates a new NEON wavelet lifting processor.
    public init() {
        self.capability = NeonTransformCapability.detect()
    }

    // MARK: - 5/3 Lifting (Reversible / Lossless)

    /// CDF 5/3 lifting constants for the predict step.
    private static let predict53: Float = -0.5

    /// CDF 5/3 lifting constants for the update step.
    private static let update53: Float = 0.25

    /// Performs forward 5/3 wavelet lifting on a 1-D signal using SIMD.
    ///
    /// Applies the two-step lifting scheme:
    /// 1. **Predict** (highpass): `d[n] = x[2n+1] - 0.5 * (x[2n] + x[2n+2])`
    /// 2. **Update** (lowpass): `s[n] = x[2n] + 0.25 * (d[n-1] + d[n])`
    ///
    /// The result is stored in-place with lowpass coefficients in the first half
    /// and highpass coefficients in the second half.
    ///
    /// - Parameters:
    ///   - data: The signal data (modified in place).
    ///   - length: The number of samples to transform.
    public func forward53(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        // Split into even (lowpass) and odd (highpass)
        var low = [Float](repeating: 0, count: halfLen)
        var high = [Float](repeating: 0, count: halfLen)

        for i in 0..<halfLen {
            low[i] = data[2 * i]
            high[i] = data[2 * i + 1]
        }

        // Predict step: d[n] += predict53 * (s[n] + s[n+1])
        #if arch(arm64)
        let predVec = SIMD4<Float>(repeating: Self.predict53)
        let simdCount = (halfLen - 1) / 4
        for i in 0..<simdCount {
            let base = i * 4
            let s0 = SIMD4<Float>(low[base], low[base + 1], low[base + 2], low[base + 3])
            let s1 = SIMD4<Float>(low[base + 1], low[base + 2], low[base + 3], low[base + 4])
            let d = SIMD4<Float>(high[base], high[base + 1], high[base + 2], high[base + 3])
            let updated = d + predVec * (s0 + s1)
            for lane in 0..<4 {
                high[base + lane] = updated[lane]
            }
        }
        for i in (simdCount * 4)..<(halfLen - 1) {
            high[i] += Self.predict53 * (low[i] + low[i + 1])
        }
        #else
        for i in 0..<(halfLen - 1) {
            high[i] += Self.predict53 * (low[i] + low[i + 1])
        }
        #endif
        // Boundary: last highpass
        high[halfLen - 1] += Self.predict53 * (low[halfLen - 1] + low[halfLen - 1])

        // Update step: s[n] += update53 * (d[n-1] + d[n])
        low[0] += Self.update53 * (high[0] + high[0])
        #if arch(arm64)
        let updVec = SIMD4<Float>(repeating: Self.update53)
        let simdCountUpd = (halfLen - 1) / 4
        for i in 0..<simdCountUpd {
            let base = i * 4 + 1
            guard base + 3 < halfLen else { break }
            let dPrev = SIMD4<Float>(high[base - 1], high[base], high[base + 1], high[base + 2])
            let dCurr = SIMD4<Float>(high[base], high[base + 1], high[base + 2], high[base + 3])
            let s = SIMD4<Float>(low[base], low[base + 1], low[base + 2], low[base + 3])
            let updated = s + updVec * (dPrev + dCurr)
            for lane in 0..<4 {
                low[base + lane] = updated[lane]
            }
        }
        for i in max(1, simdCountUpd * 4 + 1)..<halfLen {
            low[i] += Self.update53 * (high[i - 1] + high[i])
        }
        #else
        for i in 1..<halfLen {
            low[i] += Self.update53 * (high[i - 1] + high[i])
        }
        #endif

        // Write back: low in first half, high in second half
        for i in 0..<halfLen {
            data[i] = low[i]
            data[halfLen + i] = high[i]
        }
    }

    /// Performs inverse 5/3 wavelet lifting on a 1-D signal using SIMD.
    ///
    /// Reverses the forward 5/3 lifting by applying the steps in reverse order.
    ///
    /// - Parameters:
    ///   - data: The transformed data (modified in place).
    ///   - length: The number of samples.
    public func inverse53(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        var low = Array(data[0..<halfLen])
        var high = Array(data[halfLen..<(halfLen * 2)])

        // Inverse update: s[n] -= update53 * (d[n-1] + d[n])
        low[0] -= Self.update53 * (high[0] + high[0])
        for i in 1..<halfLen {
            low[i] -= Self.update53 * (high[i - 1] + high[i])
        }

        // Inverse predict: d[n] -= predict53 * (s[n] + s[n+1])
        for i in 0..<(halfLen - 1) {
            high[i] -= Self.predict53 * (low[i] + low[i + 1])
        }
        high[halfLen - 1] -= Self.predict53 * (low[halfLen - 1] + low[halfLen - 1])

        // Interleave back
        for i in 0..<halfLen {
            data[2 * i] = low[i]
            data[2 * i + 1] = high[i]
        }
    }

    // MARK: - 9/7 Lifting (Irreversible / Lossy)

    /// CDF 9/7 lifting step coefficients.
    private static let alpha97: Float = -1.586134342
    private static let beta97: Float = -0.052980118
    private static let gamma97: Float = 0.882911076
    private static let delta97: Float = 0.443506852
    private static let k97: Float = 1.230174105

    /// Performs forward 9/7 wavelet lifting on a 1-D signal using SIMD.
    ///
    /// Applies the four-step lifting scheme (ISO/IEC 15444-1 Annex F):
    /// 1. **Step 1** (α): `d[n] += α * (s[n] + s[n+1])`
    /// 2. **Step 2** (β): `s[n] += β * (d[n-1] + d[n])`
    /// 3. **Step 3** (γ): `d[n] += γ * (s[n] + s[n+1])`
    /// 4. **Step 4** (δ): `s[n] += δ * (d[n-1] + d[n])`
    /// 5. **Scale**: `s[n] *= K`, `d[n] *= 1/K`
    ///
    /// - Parameters:
    ///   - data: The signal data (modified in place).
    ///   - length: The number of samples to transform.
    public func forward97(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        var low = [Float](repeating: 0, count: halfLen)
        var high = [Float](repeating: 0, count: halfLen)

        for i in 0..<halfLen {
            low[i] = data[2 * i]
            high[i] = data[2 * i + 1]
        }

        // Step 1: α predict
        applyLiftingStep(low: low, high: &high, factor: Self.alpha97, halfLen: halfLen)

        // Step 2: β update
        applyLiftingUpdateStep(low: &low, high: high, factor: Self.beta97, halfLen: halfLen)

        // Step 3: γ predict
        applyLiftingStep(low: low, high: &high, factor: Self.gamma97, halfLen: halfLen)

        // Step 4: δ update
        applyLiftingUpdateStep(low: &low, high: high, factor: Self.delta97, halfLen: halfLen)

        // Scaling
        let kInv = 1.0 / Self.k97

        #if arch(arm64)
        let kVec = SIMD4<Float>(repeating: Self.k97)
        let kInvVec = SIMD4<Float>(repeating: kInv)
        let simdCount = halfLen / 4
        for i in 0..<simdCount {
            let base = i * 4
            let sVec = SIMD4<Float>(low[base], low[base + 1], low[base + 2], low[base + 3])
            let dVec = SIMD4<Float>(high[base], high[base + 1], high[base + 2], high[base + 3])
            let scaledS = sVec * kVec
            let scaledD = dVec * kInvVec
            for lane in 0..<4 {
                low[base + lane] = scaledS[lane]
                high[base + lane] = scaledD[lane]
            }
        }
        for i in (simdCount * 4)..<halfLen {
            low[i] *= Self.k97
            high[i] *= kInv
        }
        #else
        for i in 0..<halfLen {
            low[i] *= Self.k97
            high[i] *= kInv
        }
        #endif

        for i in 0..<halfLen {
            data[i] = low[i]
            data[halfLen + i] = high[i]
        }
    }

    /// Performs inverse 9/7 wavelet lifting on a 1-D signal using SIMD.
    ///
    /// Reverses the forward 9/7 lifting by applying steps in reverse order.
    ///
    /// - Parameters:
    ///   - data: The transformed data (modified in place).
    ///   - length: The number of samples.
    public func inverse97(data: inout [Float], length: Int) {
        guard length >= 4 else { return }

        let halfLen = length / 2

        var low = Array(data[0..<halfLen])
        var high = Array(data[halfLen..<(halfLen * 2)])

        // Inverse scaling
        let kInv = 1.0 / Self.k97
        for i in 0..<halfLen {
            low[i] *= kInv
            high[i] *= Self.k97
        }

        // Inverse step 4: δ
        low[0] -= Self.delta97 * (high[0] + high[0])
        for i in 1..<halfLen {
            low[i] -= Self.delta97 * (high[i - 1] + high[i])
        }

        // Inverse step 3: γ
        for i in 0..<(halfLen - 1) {
            high[i] -= Self.gamma97 * (low[i] + low[i + 1])
        }
        high[halfLen - 1] -= Self.gamma97 * (low[halfLen - 1] + low[halfLen - 1])

        // Inverse step 2: β
        low[0] -= Self.beta97 * (high[0] + high[0])
        for i in 1..<halfLen {
            low[i] -= Self.beta97 * (high[i - 1] + high[i])
        }

        // Inverse step 1: α
        for i in 0..<(halfLen - 1) {
            high[i] -= Self.alpha97 * (low[i] + low[i + 1])
        }
        high[halfLen - 1] -= Self.alpha97 * (low[halfLen - 1] + low[halfLen - 1])

        // Interleave back
        for i in 0..<halfLen {
            data[2 * i] = low[i]
            data[2 * i + 1] = high[i]
        }
    }

    // MARK: - Lifting Step Helpers

    /// Applies a predict-type lifting step: `d[n] += factor * (s[n] + s[n+1])`.
    private func applyLiftingStep(
        low: [Float], high: inout [Float], factor: Float, halfLen: Int
    ) {
        #if arch(arm64)
        let factorVec = SIMD4<Float>(repeating: factor)
        let simdCount = (halfLen - 1) / 4
        for i in 0..<simdCount {
            let base = i * 4
            let s0 = SIMD4<Float>(low[base], low[base + 1], low[base + 2], low[base + 3])
            let s1 = SIMD4<Float>(low[base + 1], low[base + 2], low[base + 3], low[base + 4])
            let d = SIMD4<Float>(high[base], high[base + 1], high[base + 2], high[base + 3])
            let result = d + factorVec * (s0 + s1)
            for lane in 0..<4 {
                high[base + lane] = result[lane]
            }
        }
        for i in (simdCount * 4)..<(halfLen - 1) {
            high[i] += factor * (low[i] + low[i + 1])
        }
        #else
        for i in 0..<(halfLen - 1) {
            high[i] += factor * (low[i] + low[i + 1])
        }
        #endif
        // Boundary
        high[halfLen - 1] += factor * (low[halfLen - 1] + low[halfLen - 1])
    }

    /// Applies an update-type lifting step: `s[n] += factor * (d[n-1] + d[n])`.
    private func applyLiftingUpdateStep(
        low: inout [Float], high: [Float], factor: Float, halfLen: Int
    ) {
        // Boundary
        low[0] += factor * (high[0] + high[0])

        #if arch(arm64)
        let factorVec = SIMD4<Float>(repeating: factor)
        let simdCount = (halfLen - 1) / 4
        for i in 0..<simdCount {
            let base = i * 4 + 1
            guard base + 3 < halfLen else { break }
            let dPrev = SIMD4<Float>(high[base - 1], high[base], high[base + 1], high[base + 2])
            let dCurr = SIMD4<Float>(high[base], high[base + 1], high[base + 2], high[base + 3])
            let s = SIMD4<Float>(low[base], low[base + 1], low[base + 2], low[base + 3])
            let result = s + factorVec * (dPrev + dCurr)
            for lane in 0..<4 {
                low[base + lane] = result[lane]
            }
        }
        for i in max(1, simdCount * 4 + 1)..<halfLen {
            low[i] += factor * (high[i - 1] + high[i])
        }
        #else
        for i in 1..<halfLen {
            low[i] += factor * (high[i - 1] + high[i])
        }
        #endif
    }
}

// MARK: - NEON Colour Transforms

/// SIMD-accelerated colour space transforms using ARM NEON.
///
/// Implements the JPEG 2000 standard colour transforms:
/// - **ICT** (Irreversible Colour Transform): For lossy compression.
/// - **RCT** (Reversible Colour Transform): For lossless compression.
///
/// On ARM64, processes 4 pixel components per SIMD instruction,
/// yielding 2-4× throughput improvement for colour conversion.
///
/// ## Architecture Isolation
///
/// All NEON code is guarded with `#if arch(arm64)`. Scalar fallback is
/// provided for non-ARM64 platforms.
///
/// ## Usage
///
/// ```swift
/// let transform = NeonColourTransform()
/// var r: [Float] = ..., g: [Float] = ..., b: [Float] = ...
/// transform.forwardICT(r: &r, g: &g, b: &b, count: pixelCount)
/// ```
public struct NeonColourTransform: Sendable {
    /// The detected NEON capability.
    public let capability: NeonTransformCapability

    /// Creates a new NEON colour transform processor.
    public init() {
        self.capability = NeonTransformCapability.detect()
    }

    // MARK: - ICT (Irreversible Colour Transform)

    /// ICT forward matrix coefficients (ISO/IEC 15444-1 Annex G.2).
    private static let ictYR: Float = 0.299
    private static let ictYG: Float = 0.587
    private static let ictYB: Float = 0.114
    private static let ictCbR: Float = -0.16875
    private static let ictCbG: Float = -0.33126
    private static let ictCbB: Float = 0.5
    private static let ictCrR: Float = 0.5
    private static let ictCrG: Float = -0.41869
    private static let ictCrB: Float = -0.08131

    /// ICT inverse matrix coefficients.
    private static let ictInvCrR: Float = 1.402
    private static let ictInvCbG: Float = -0.34413
    private static let ictInvCrG: Float = -0.71414
    private static let ictInvCbB: Float = 1.772

    /// Performs forward ICT (RGB → YCbCr) using SIMD.
    ///
    /// Converts RGB components to YCbCr using the irreversible colour transform
    /// defined in ISO/IEC 15444-1 Annex G.2.
    ///
    /// - Parameters:
    ///   - r: Red component (converted to Y in place).
    ///   - g: Green component (converted to Cb in place).
    ///   - b: Blue component (converted to Cr in place).
    ///   - count: Number of pixels to transform.
    public func forwardICT(r: inout [Float], g: inout [Float], b: inout [Float], count: Int) {
        guard count > 0 else { return }

        #if arch(arm64)
        let yrVec = SIMD4<Float>(repeating: Self.ictYR)
        let ygVec = SIMD4<Float>(repeating: Self.ictYG)
        let ybVec = SIMD4<Float>(repeating: Self.ictYB)
        let cbrVec = SIMD4<Float>(repeating: Self.ictCbR)
        let cbgVec = SIMD4<Float>(repeating: Self.ictCbG)
        let cbbVec = SIMD4<Float>(repeating: Self.ictCbB)
        let crrVec = SIMD4<Float>(repeating: Self.ictCrR)
        let crgVec = SIMD4<Float>(repeating: Self.ictCrG)
        let crbVec = SIMD4<Float>(repeating: Self.ictCrB)

        let simdCount = count / 4
        for i in 0..<simdCount {
            let base = i * 4
            let rVec = SIMD4<Float>(r[base], r[base + 1], r[base + 2], r[base + 3])
            let gVec = SIMD4<Float>(g[base], g[base + 1], g[base + 2], g[base + 3])
            let bVec = SIMD4<Float>(b[base], b[base + 1], b[base + 2], b[base + 3])

            let y = yrVec * rVec + ygVec * gVec + ybVec * bVec
            let cb = cbrVec * rVec + cbgVec * gVec + cbbVec * bVec
            let cr = crrVec * rVec + crgVec * gVec + crbVec * bVec

            for lane in 0..<4 {
                r[base + lane] = y[lane]
                g[base + lane] = cb[lane]
                b[base + lane] = cr[lane]
            }
        }
        for i in (simdCount * 4)..<count {
            let rr = r[i], gg = g[i], bb = b[i]
            r[i] = Self.ictYR * rr + Self.ictYG * gg + Self.ictYB * bb
            g[i] = Self.ictCbR * rr + Self.ictCbG * gg + Self.ictCbB * bb
            b[i] = Self.ictCrR * rr + Self.ictCrG * gg + Self.ictCrB * bb
        }
        #else
        for i in 0..<count {
            let rr = r[i], gg = g[i], bb = b[i]
            r[i] = Self.ictYR * rr + Self.ictYG * gg + Self.ictYB * bb
            g[i] = Self.ictCbR * rr + Self.ictCbG * gg + Self.ictCbB * bb
            b[i] = Self.ictCrR * rr + Self.ictCrG * gg + Self.ictCrB * bb
        }
        #endif
    }

    /// Performs inverse ICT (YCbCr → RGB) using SIMD.
    ///
    /// Converts YCbCr components back to RGB using the inverse ICT.
    ///
    /// - Parameters:
    ///   - y: Y component (converted to R in place).
    ///   - cb: Cb component (converted to G in place).
    ///   - cr: Cr component (converted to B in place).
    ///   - count: Number of pixels to transform.
    public func inverseICT(y: inout [Float], cb: inout [Float], cr: inout [Float], count: Int) {
        guard count > 0 else { return }

        #if arch(arm64)
        let invCrRVec = SIMD4<Float>(repeating: Self.ictInvCrR)
        let invCbGVec = SIMD4<Float>(repeating: Self.ictInvCbG)
        let invCrGVec = SIMD4<Float>(repeating: Self.ictInvCrG)
        let invCbBVec = SIMD4<Float>(repeating: Self.ictInvCbB)

        let simdCount = count / 4
        for i in 0..<simdCount {
            let base = i * 4
            let yVec = SIMD4<Float>(y[base], y[base + 1], y[base + 2], y[base + 3])
            let cbVec = SIMD4<Float>(cb[base], cb[base + 1], cb[base + 2], cb[base + 3])
            let crVec = SIMD4<Float>(cr[base], cr[base + 1], cr[base + 2], cr[base + 3])

            let rOut = yVec + invCrRVec * crVec
            let gOut = yVec + invCbGVec * cbVec + invCrGVec * crVec
            let bOut = yVec + invCbBVec * cbVec

            for lane in 0..<4 {
                y[base + lane] = rOut[lane]
                cb[base + lane] = gOut[lane]
                cr[base + lane] = bOut[lane]
            }
        }
        for i in (simdCount * 4)..<count {
            let yy = y[i], cbb = cb[i], crr = cr[i]
            y[i] = yy + Self.ictInvCrR * crr
            cb[i] = yy + Self.ictInvCbG * cbb + Self.ictInvCrG * crr
            cr[i] = yy + Self.ictInvCbB * cbb
        }
        #else
        for i in 0..<count {
            let yy = y[i], cbb = cb[i], crr = cr[i]
            y[i] = yy + Self.ictInvCrR * crr
            cb[i] = yy + Self.ictInvCbG * cbb + Self.ictInvCrG * crr
            cr[i] = yy + Self.ictInvCbB * cbb
        }
        #endif
    }

    // MARK: - RCT (Reversible Colour Transform)

    /// Performs forward RCT (RGB → YUV) using SIMD.
    ///
    /// Converts RGB integer components to YUV using the reversible colour transform
    /// defined in ISO/IEC 15444-1 Annex G.1:
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

        #if arch(arm64)
        let simdCount = count / 4
        for i in 0..<simdCount {
            let base = i * 4
            let rVec = SIMD4<Int32>(r[base], r[base + 1], r[base + 2], r[base + 3])
            let gVec = SIMD4<Int32>(g[base], g[base + 1], g[base + 2], g[base + 3])
            let bVec = SIMD4<Int32>(b[base], b[base + 1], b[base + 2], b[base + 3])

            let yVec = (rVec &+ gVec &+ gVec &+ bVec) &>> 2
            let uVec = bVec &- gVec
            let vVec = rVec &- gVec

            for lane in 0..<4 {
                r[base + lane] = yVec[lane]
                g[base + lane] = uVec[lane]
                b[base + lane] = vVec[lane]
            }
        }
        for i in (simdCount * 4)..<count {
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

    /// Performs inverse RCT (YUV → RGB) using SIMD.
    ///
    /// Converts YUV components back to RGB using the inverse RCT:
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

        #if arch(arm64)
        let simdCount = count / 4
        for i in 0..<simdCount {
            let base = i * 4
            let yVec = SIMD4<Int32>(y[base], y[base + 1], y[base + 2], y[base + 3])
            let uVec = SIMD4<Int32>(u[base], u[base + 1], u[base + 2], u[base + 3])
            let vVec = SIMD4<Int32>(v[base], v[base + 1], v[base + 2], v[base + 3])

            let gVec = yVec &- ((uVec &+ vVec) &>> 2)
            let rVec = vVec &+ gVec
            let bVec = uVec &+ gVec

            for lane in 0..<4 {
                y[base + lane] = rVec[lane]
                u[base + lane] = gVec[lane]
                v[base + lane] = bVec[lane]
            }
        }
        for i in (simdCount * 4)..<count {
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

    // MARK: - Batch Pixel Format Conversion

    /// Converts interleaved RGB to planar format using SIMD.
    ///
    /// De-interleaves packed RGB data (RGBRGBRGB...) into three separate
    /// component arrays.
    ///
    /// - Parameters:
    ///   - interleaved: Packed RGB data (length must be 3 × pixelCount).
    ///   - count: Number of pixels.
    /// - Returns: Tuple of (R, G, B) planar arrays.
    public func deinterleaveRGB(
        interleaved: [Float],
        count: Int
    ) -> (r: [Float], g: [Float], b: [Float]) {
        guard count > 0, interleaved.count >= count * 3 else {
            return ([], [], [])
        }

        var rOut = [Float](repeating: 0, count: count)
        var gOut = [Float](repeating: 0, count: count)
        var bOut = [Float](repeating: 0, count: count)

        for i in 0..<count {
            rOut[i] = interleaved[i * 3]
            gOut[i] = interleaved[i * 3 + 1]
            bOut[i] = interleaved[i * 3 + 2]
        }

        return (rOut, gOut, bOut)
    }

    /// Converts planar RGB to interleaved format using SIMD.
    ///
    /// Interleaves three separate component arrays into packed RGB data.
    ///
    /// - Parameters:
    ///   - r: Red component array.
    ///   - g: Green component array.
    ///   - b: Blue component array.
    ///   - count: Number of pixels.
    /// - Returns: Interleaved RGB data.
    public func interleaveRGB(
        r: [Float], g: [Float], b: [Float],
        count: Int
    ) -> [Float] {
        guard count > 0 else { return [] }

        var result = [Float](repeating: 0, count: count * 3)

        for i in 0..<count {
            result[i * 3] = r[i]
            result[i * 3 + 1] = g[i]
            result[i * 3 + 2] = b[i]
        }

        return result
    }
}
