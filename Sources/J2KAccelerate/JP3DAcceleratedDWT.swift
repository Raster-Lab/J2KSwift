//
// JP3DAcceleratedDWT.swift
// J2KSwift
//
// JP3DAcceleratedDWT.swift
// J2KSwift
//
// Accelerate-framework-optimized 3D DWT operations for JP3D (Week 214-217).
//

import Foundation
import J2KCore

#if canImport(Accelerate)
import Accelerate
#endif

/// Accelerate-framework-optimized 3D DWT operations.
///
/// Provides vDSP-based 1D filtering along X, Y, and Z axes for volumetric data.
/// Used internally by `JP3DWaveletTransform` on Apple platforms.
///
/// Both the 5/3 reversible (lossless) lifting filter and the 9/7 CDF irreversible
/// (lossy) lifting filter are supported. The axis-sweep functions decompose a flat
/// `z-y-x` ordered `[Float]` volume one axis at a time, matching the approach used
/// in JPEG 2000 Part 10 (JP3D).
///
/// ## Coordinate convention
///
/// Data is stored in row-major `z-y-x` order:
/// ```
/// index(x, y, z) = z * width * height + y * width + x
/// ```
///
/// ## Example
///
/// ```swift
/// // One-level 3D DWT using 5/3 filter
/// let volume: [Float] = ...  // width*height*depth elements
/// let (lowX, highX) = JP3DAcceleratedDWT.forwardX(
///     data: volume, width: 64, height: 64, depth: 32, filter: 0)
/// ```
public struct JP3DAcceleratedDWT: Sendable {
    // MARK: - Availability

    /// `true` when the Accelerate framework is available on the current platform.
    ///
    /// The lifting steps themselves are pure Swift; on Apple platforms the 9/7
    /// scaling step additionally uses `vDSP.multiply` for vectorised float
    /// multiplication.
    public static var isAvailable: Bool {
        #if canImport(Accelerate)
        return true
        #else
        return false
        #endif
    }

    // MARK: - 5/3 Reversible lifting (Float)

    /// Forward 5/3 reversible lifting transform along a 1-D signal.
    ///
    /// Implements the ISO 15444-1 Annex F.3.1 predict/update lifting scheme with
    /// symmetric boundary extension.
    ///
    /// - Parameter signal: Input samples. Must not be empty.
    /// - Returns: `(lowpass, highpass)` subbands where
    ///   `lowpass.count == (signal.count + 1) / 2` and
    ///   `highpass.count == signal.count / 2`.
    public static func forward53(signal: [Float]) -> (lowpass: [Float], highpass: [Float]) {
        let n = signal.count
        guard n > 1 else { return (lowpass: signal, highpass: []) }

        let nL = (n + 1) / 2
        let nH = n / 2
        var low  = [Float](repeating: 0, count: nL)
        var high = [Float](repeating: 0, count: nH)

        // Helper: symmetric boundary read
        func x(_ i: Int) -> Float {
            if i < 0 { return signal[min(-i, n - 1)] }
            if i >= n { return signal[max(2 * (n - 1) - i, 0)] }
            return signal[i]
        }

        // Predict step: H[k] = x[2k+1] - floor((x[2k] + x[2k+2]) / 2)
        for k in 0 ..< nH {
            let pred = (x(2 * k) + x(2 * k + 2)) * 0.5
            high[k] = x(2 * k + 1) - pred.rounded(.down)
        }

        // Update step: L[k] = x[2k] + floor((H[k-1] + H[k] + 2) / 4)
        func h(_ k: Int) -> Float {
            if k < 0 { return high[0] }
            if k >= nH { return high[nH - 1] }
            return high[k]
        }
        for k in 0 ..< nL {
            let upd = (h(k - 1) + h(k) + 2.0) * 0.25
            low[k] = x(2 * k) + upd.rounded(.down)
        }

        return (lowpass: low, highpass: high)
    }

    /// Inverse 5/3 reversible lifting transform.
    ///
    /// Reconstructs the original signal from its lowpass and highpass subbands.
    /// The inverse of ``forward53(signal:)``.
    ///
    /// - Parameters:
    ///   - lowpass: Lowpass subband.
    ///   - highpass: Highpass subband.
    /// - Returns: Reconstructed signal of length `lowpass.count + highpass.count`.
    public static func inverse53(lowpass: [Float], highpass: [Float]) -> [Float] {
        let nL = lowpass.count
        let nH = highpass.count
        let n  = nL + nH
        guard n > 0 else { return [] }
        guard nH > 0 else { return lowpass }

        var out = [Float](repeating: 0, count: n)

        func h(_ k: Int) -> Float {
            if k < 0 { return highpass[0] }
            if k >= nH { return highpass[nH - 1] }
            return highpass[k]
        }

        // Undo update: x[2k] = L[k] - floor((H[k-1] + H[k] + 2) / 4)
        for k in 0 ..< nL {
            let upd = (h(k - 1) + h(k) + 2.0) * 0.25
            out[2 * k] = lowpass[k] - upd.rounded(.down)
        }

        // Undo predict: x[2k+1] = H[k] + floor((x[2k] + x[2k+2]) / 2)
        func ev(_ i: Int) -> Float {
            if i < 0 { return out[0] }
            if i >= n { return out[n - 1] }
            return out[i]
        }
        for k in 0 ..< nH {
            let pred = (ev(2 * k) + ev(2 * k + 2)) * 0.5
            out[2 * k + 1] = highpass[k] + pred.rounded(.down)
        }

        return out
    }

    // MARK: - 9/7 Irreversible CDF lifting (Float)

    // CDF 9/7 lifting constants (Cohen–Daubechies–Feauveau)
    private static let alpha97: Float = -1.586_134_342
    private static let beta97: Float = -0.052_980_118
    private static let gamma97: Float = 0.882_911_075
    private static let delta97: Float = 0.443_506_852
    private static let K97: Float = 1.149_604_398   // subband scaling factor

    /// Forward 9/7 CDF lifting transform along a 1-D signal.
    ///
    /// Implements the four-step lifting factorisation of the CDF 9/7 biorthogonal
    /// wavelet as specified in ISO 15444-1 Annex F.3.2.  On Apple platforms the
    /// final subband scaling step uses `vDSP.multiply` for vectorised throughput.
    ///
    /// - Parameter signal: Input samples.
    /// - Returns: `(lowpass, highpass)` subbands.
    public static func forward97(signal: [Float]) -> (lowpass: [Float], highpass: [Float]) {
        let n = signal.count
        guard n > 1 else { return (lowpass: signal, highpass: []) }

        var buf = signal  // work in-place on a mutable copy

        // Symmetric boundary helper (whole-sample symmetric, JPEG 2000 convention)
        func s(_ i: Int) -> Float {
            var idx = i
            if idx < 0 { idx = -idx }
            if idx >= n { idx = 2 * (n - 1) - idx }
            idx = max(0, min(n - 1, idx))
            return buf[idx]
        }

        // Step 1 – alpha (predict odd)
        for i in stride(from: 1, to: n - 1, by: 2) {
            buf[i] += alpha97 * (s(i - 1) + s(i + 1))
        }
        if n.isMultiple(of: 2) { buf[n - 1] += alpha97 * 2.0 * s(n - 2) }

        // Step 2 – beta (update even)
        for i in stride(from: 2, to: n - 1, by: 2) {
            buf[i] += beta97 * (s(i - 1) + s(i + 1))
        }
        buf[0] += beta97 * 2.0 * s(1)

        // Step 3 – gamma (predict odd)
        for i in stride(from: 1, to: n - 1, by: 2) {
            buf[i] += gamma97 * (s(i - 1) + s(i + 1))
        }
        if n.isMultiple(of: 2) { buf[n - 1] += gamma97 * 2.0 * s(n - 2) }

        // Step 4 – delta (update even)
        for i in stride(from: 2, to: n - 1, by: 2) {
            buf[i] += delta97 * (s(i - 1) + s(i + 1))
        }
        buf[0] += delta97 * 2.0 * s(1)

        // Subband scaling: even (low) × K, odd (high) × 1/K
        let invK: Float = 1.0 / K97
        let nL = (n + 1) / 2
        let nH = n / 2
        var low  = [Float](repeating: 0, count: nL)
        var high = [Float](repeating: 0, count: nH)

        for k in 0 ..< nL { low[k]  = buf[2 * k] }
        for k in 0 ..< nH { high[k] = buf[2 * k + 1] }

        #if canImport(Accelerate)
        low  = vDSP.multiply(K97, low)
        high = vDSP.multiply(invK, high)
        #else
        low  = low.map { $0 * K97 }
        high = high.map { $0 * invK }
        #endif

        return (lowpass: low, highpass: high)
    }

    /// Inverse 9/7 CDF lifting transform.
    ///
    /// Reconstructs the original signal from its lowpass and highpass subbands.
    /// The inverse of ``forward97(signal:)``.
    ///
    /// - Parameters:
    ///   - lowpass: Lowpass subband.
    ///   - highpass: Highpass subband.
    /// - Returns: Reconstructed signal of length `lowpass.count + highpass.count`.
    public static func inverse97(lowpass: [Float], highpass: [Float]) -> [Float] {
        let nL = lowpass.count
        let nH = highpass.count
        let n  = nL + nH
        guard n > 0 else { return [] }
        guard nH > 0 else { return lowpass }

        let invK: Float = 1.0 / K97

        // Undo subband scaling
        var scaledLow  = lowpass
        var scaledHigh = highpass

        #if canImport(Accelerate)
        scaledLow  = vDSP.multiply(invK, scaledLow)
        scaledHigh = vDSP.multiply(K97, scaledHigh)
        #else
        scaledLow  = scaledLow.map { $0 * invK }
        scaledHigh = scaledHigh.map { $0 * K97 }
        #endif

        // Reassemble interleaved buffer
        var buf = [Float](repeating: 0, count: n)
        for k in 0 ..< nL { buf[2 * k]     = scaledLow[k] }
        for k in 0 ..< nH { buf[2 * k + 1] = scaledHigh[k] }

        func s(_ i: Int) -> Float {
            var idx = i
            if idx < 0 { idx = -idx }
            if idx >= n { idx = 2 * (n - 1) - idx }
            idx = max(0, min(n - 1, idx))
            return buf[idx]
        }

        // Undo step 4 – delta
        for i in stride(from: 2, to: n - 1, by: 2) {
            buf[i] -= delta97 * (s(i - 1) + s(i + 1))
        }
        buf[0] -= delta97 * 2.0 * s(1)

        // Undo step 3 – gamma
        for i in stride(from: 1, to: n - 1, by: 2) {
            buf[i] -= gamma97 * (s(i - 1) + s(i + 1))
        }
        if n.isMultiple(of: 2) { buf[n - 1] -= gamma97 * 2.0 * s(n - 2) }

        // Undo step 2 – beta
        for i in stride(from: 2, to: n - 1, by: 2) {
            buf[i] -= beta97 * (s(i - 1) + s(i + 1))
        }
        buf[0] -= beta97 * 2.0 * s(1)

        // Undo step 1 – alpha
        for i in stride(from: 1, to: n - 1, by: 2) {
            buf[i] -= alpha97 * (s(i - 1) + s(i + 1))
        }
        if n.isMultiple(of: 2) { buf[n - 1] -= alpha97 * 2.0 * s(n - 2) }

        return buf
    }

    // MARK: - Private helpers

    /// Choose and apply the requested 1-D forward DWT.
    private static func forward1D(_ signal: [Float], filter: Int) -> (lowpass: [Float], highpass: [Float]) {
        filter == 0 ? forward53(signal: signal) : forward97(signal: signal)
    }

    /// Choose and apply the requested 1-D inverse DWT.
    private static func inverse1D(low: [Float], high: [Float], filter: Int) -> [Float] {
        filter == 0 ? inverse53(lowpass: low, highpass: high) : inverse97(lowpass: low, highpass: high)
    }

    // MARK: - Forward axis sweeps

    /// Apply forward 1-D DWT along the **X axis** (rows) of a 3-D volume.
    ///
    /// Processes every row (a vector of `width` samples) independently and
    /// returns two volumes whose column counts are `(width+1)/2` and `width/2`.
    ///
    /// - Parameters:
    ///   - data: Flat `[Float]` array in `z-y-x` order,
    ///     length `width * height * depth`.
    ///   - width: Number of columns (X dimension).
    ///   - height: Number of rows (Y dimension).
    ///   - depth: Number of slices (Z dimension).
    ///   - filter: `0` = 5/3 reversible, `1` = 9/7 irreversible.
    /// - Returns: `(low, high)` where each is a flat volume in `z-y-x` order with
    ///   column counts `wL = (width+1)/2` and `wH = width/2`.
    public static func forwardX(
        data: [Float],
        width: Int, height: Int, depth: Int,
        filter: Int
    ) -> (low: [Float], high: [Float]) {
        let wL = (width + 1) / 2
        let wH = width / 2
        var low  = [Float](repeating: 0, count: wL * height * depth)
        var high = [Float](repeating: 0, count: wH * height * depth)

        for z in 0 ..< depth {
            for y in 0 ..< height {
                let srcBase = z * height * width + y * width
                let row = Array(data[srcBase ..< srcBase + width])
                let (lRow, hRow) = forward1D(row, filter: filter)

                let dstBaseL = z * height * wL + y * wL
                let dstBaseH = z * height * wH + y * wH
                for i in 0 ..< wL { low[dstBaseL + i]  = lRow[i] }
                for i in 0 ..< wH { high[dstBaseH + i] = hRow[i] }
            }
        }
        return (low: low, high: high)
    }

    /// Apply forward 1-D DWT along the **Y axis** (columns) of a 3-D volume.
    ///
    /// Processes every column (a vector of `height` samples) independently and
    /// returns two volumes whose row counts are `(height+1)/2` and `height/2`.
    ///
    /// - Parameters:
    ///   - data: Flat `[Float]` array in `z-y-x` order,
    ///     length `width * height * depth`.
    ///   - width: X dimension.
    ///   - height: Y dimension.
    ///   - depth: Z dimension.
    ///   - filter: `0` = 5/3, `1` = 9/7.
    /// - Returns: `(low, high)` with row counts `hL = (height+1)/2` and `hH = height/2`.
    public static func forwardY(
        data: [Float],
        width: Int, height: Int, depth: Int,
        filter: Int
    ) -> (low: [Float], high: [Float]) {
        let hL = (height + 1) / 2
        let hH = height / 2
        var low  = [Float](repeating: 0, count: width * hL * depth)
        var high = [Float](repeating: 0, count: width * hH * depth)

        for z in 0 ..< depth {
            for x in 0 ..< width {
                var col = [Float](repeating: 0, count: height)
                for y in 0 ..< height {
                    col[y] = data[z * height * width + y * width + x]
                }
                let (lCol, hCol) = forward1D(col, filter: filter)

                for y in 0 ..< hL { low[z * hL * width + y * width + x] = lCol[y] }
                for y in 0 ..< hH { high[z * hH * width + y * width + x] = hCol[y] }
            }
        }
        return (low: low, high: high)
    }

    /// Apply forward 1-D DWT along the **Z axis** (slices) of a 3-D volume.
    ///
    /// Processes every per-pixel time/depth signal (a vector of `depth` samples)
    /// independently and returns two volumes whose slice counts are
    /// `(depth+1)/2` and `depth/2`.
    ///
    /// - Parameters:
    ///   - data: Flat `[Float]` array in `z-y-x` order,
    ///     length `width * height * depth`.
    ///   - width: X dimension.
    ///   - height: Y dimension.
    ///   - depth: Z dimension.
    ///   - filter: `0` = 5/3, `1` = 9/7.
    /// - Returns: `(low, high)` with slice counts `dL = (depth+1)/2` and `dH = depth/2`.
    public static func forwardZ(
        data: [Float],
        width: Int, height: Int, depth: Int,
        filter: Int
    ) -> (low: [Float], high: [Float]) {
        let dL = (depth + 1) / 2
        let dH = depth / 2
        var low  = [Float](repeating: 0, count: width * height * dL)
        var high = [Float](repeating: 0, count: width * height * dH)

        for y in 0 ..< height {
            for x in 0 ..< width {
                var vec = [Float](repeating: 0, count: depth)
                for z in 0 ..< depth {
                    vec[z] = data[z * height * width + y * width + x]
                }
                let (lVec, hVec) = forward1D(vec, filter: filter)

                for z in 0 ..< dL { low[z * height * width + y * width + x] = lVec[z] }
                for z in 0 ..< dH { high[z * height * width + y * width + x] = hVec[z] }
            }
        }
        return (low: low, high: high)
    }

    // MARK: - Inverse axis sweeps

    /// Apply inverse 1-D DWT along the **X axis** of a 3-D volume.
    ///
    /// Reconstructs a volume whose X dimension is `origWidth` from its
    /// lowpass (column count `(origWidth+1)/2`) and highpass (column count
    /// `origWidth/2`) sub-volumes.
    ///
    /// - Parameters:
    ///   - low: Lowpass sub-volume in `z-y-x` order.
    ///   - high: Highpass sub-volume in `z-y-x` order.
    ///   - origWidth: X dimension of the reconstructed volume.
    ///   - height: Y dimension.
    ///   - depth: Z dimension.
    ///   - filter: `0` = 5/3, `1` = 9/7.
    /// - Returns: Reconstructed volume in `z-y-x` order.
    public static func inverseX(
        low: [Float], high: [Float],
        origWidth: Int, height: Int, depth: Int,
        filter: Int
    ) -> [Float] {
        let wL = (origWidth + 1) / 2
        let wH = origWidth / 2
        var out = [Float](repeating: 0, count: origWidth * height * depth)

        for z in 0 ..< depth {
            for y in 0 ..< height {
                let lBase = z * height * wL + y * wL
                let hBase = z * height * wH + y * wH
                let lRow = Array(low[lBase ..< lBase + wL])
                let hRow = Array(high[hBase ..< hBase + wH])
                let row  = inverse1D(low: lRow, high: hRow, filter: filter)

                let dstBase = z * height * origWidth + y * origWidth
                for i in 0 ..< origWidth { out[dstBase + i] = row[i] }
            }
        }
        return out
    }

    /// Apply inverse 1-D DWT along the **Y axis** of a 3-D volume.
    ///
    /// - Parameters:
    ///   - low: Lowpass sub-volume in `z-y-x` order (row count `(origHeight+1)/2`).
    ///   - high: Highpass sub-volume in `z-y-x` order (row count `origHeight/2`).
    ///   - width: X dimension.
    ///   - origHeight: Y dimension of the reconstructed volume.
    ///   - depth: Z dimension.
    ///   - filter: `0` = 5/3, `1` = 9/7.
    /// - Returns: Reconstructed volume in `z-y-x` order.
    public static func inverseY(
        low: [Float], high: [Float],
        width: Int, origHeight: Int, depth: Int,
        filter: Int
    ) -> [Float] {
        let hL = (origHeight + 1) / 2
        let hH = origHeight / 2
        var out = [Float](repeating: 0, count: width * origHeight * depth)

        for z in 0 ..< depth {
            for x in 0 ..< width {
                var lCol = [Float](repeating: 0, count: hL)
                var hCol = [Float](repeating: 0, count: hH)
                for y in 0 ..< hL { lCol[y] = low[z * hL * width + y * width + x] }
                for y in 0 ..< hH { hCol[y] = high[z * hH * width + y * width + x] }
                let col = inverse1D(low: lCol, high: hCol, filter: filter)

                for y in 0 ..< origHeight {
                    out[z * origHeight * width + y * width + x] = col[y]
                }
            }
        }
        return out
    }

    /// Apply inverse 1-D DWT along the **Z axis** of a 3-D volume.
    ///
    /// - Parameters:
    ///   - low: Lowpass sub-volume in `z-y-x` order (slice count `(origDepth+1)/2`).
    ///   - high: Highpass sub-volume in `z-y-x` order (slice count `origDepth/2`).
    ///   - width: X dimension.
    ///   - height: Y dimension.
    ///   - origDepth: Z dimension of the reconstructed volume.
    ///   - filter: `0` = 5/3, `1` = 9/7.
    /// - Returns: Reconstructed volume in `z-y-x` order.
    public static func inverseZ(
        low: [Float], high: [Float],
        width: Int, height: Int, origDepth: Int,
        filter: Int
    ) -> [Float] {
        let dL = (origDepth + 1) / 2
        let dH = origDepth / 2
        var out = [Float](repeating: 0, count: width * height * origDepth)

        for y in 0 ..< height {
            for x in 0 ..< width {
                var lVec = [Float](repeating: 0, count: dL)
                var hVec = [Float](repeating: 0, count: dH)
                for z in 0 ..< dL { lVec[z] = low[z * height * width + y * width + x] }
                for z in 0 ..< dH { hVec[z] = high[z * height * width + y * width + x] }
                let vec = inverse1D(low: lVec, high: hVec, filter: filter)

                for z in 0 ..< origDepth {
                    out[z * height * width + y * width + x] = vec[z]
                }
            }
        }
        return out
    }
}
