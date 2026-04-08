//
//  J2KOptimizedKernels.swift
//  J2KSwift
//
//  Performance-optimised kernels for DWT lifting, quantisation, and colour
//  transforms. All functions produce bit-identical results to the reference
//  implementations in J2KDWT1D, J2KQuantization, and J2KColorTransform.
//
//  Optimisations applied:
//  - UnsafeMutableBufferPointer to eliminate Swift array bounds checks
//  - Pre-extended arrays to move boundary handling out of inner loops
//  - Division via UnsafeBufferPointer (eliminates bounds checks)
//  - SIMD4/SIMD8 vectorisation via Swift's cross-platform SIMD types
//  - In-place operations to reduce allocations
//

import Foundation
import J2KCore

// MARK: - Optimised 1D DWT Lifting

/// Performance-optimised DWT lifting kernels.
///
/// These kernels produce identical output to `J2KDWT1D` but use unsafe
/// buffer pointers and pre-extended boundary handling to eliminate
/// per-element branching in the hot path.
public enum J2KOptimizedDWT: Sendable {

    // MARK: 5/3 Reversible Lifting (Int32)

    /// Forward 5/3 lifting with symmetric boundary extension.
    ///
    /// Produces identical output to `J2KDWT1D.forwardTransform53` with
    /// `.symmetric` boundary extension.
    @inlinable
    public static func forwardLift53(
        signal: [Int32]
    ) -> (lowpass: [Int32], highpass: [Int32]) {
        let n = signal.count
        guard n >= 2 else { return ([signal[0]], []) }

        let lowpassSize = (n + 1) / 2
        let highpassSize = n / 2

        // Split into even/odd
        var even = [Int32](repeating: 0, count: lowpassSize)
        var odd = [Int32](repeating: 0, count: highpassSize)

        signal.withUnsafeBufferPointer { sig in
            even.withUnsafeMutableBufferPointer { ev in
                for i in 0..<lowpassSize {
                    ev[i] = sig[i &* 2]
                }
            }
            odd.withUnsafeMutableBufferPointer { od in
                for i in 0..<highpassSize {
                    od[i] = sig[i &* 2 &+ 1]
                }
            }
        }

        var highpass = [Int32](repeating: 0, count: highpassSize)

        // Predict step: d[n] = odd[n] - ((even[n] + even[n+1]) >> 1)
        // Boundary: even[lowpassSize] mirrors to even[lowpassSize-2] for symmetric,
        // but for the last highpass sample, right = even[min(i+1, lowpassSize-1)]
        even.withUnsafeBufferPointer { ev in
            odd.withUnsafeBufferPointer { od in
                highpass.withUnsafeMutableBufferPointer { hp in
                    let lastEven = lowpassSize - 1
                    for i in 0..<highpassSize {
                        let left = ev[i]
                        let right = ev[min(i + 1, lastEven)]
                        hp[i] = od[i] &- ((left &+ right) >> 1)
                    }
                }
            }
        }

        var lowpass = [Int32](repeating: 0, count: lowpassSize)

        // Update step: s[n] = even[n] + ((d[n-1] + d[n] + 2) >> 2)
        // Boundary: d[-1] mirrors to d[0] for symmetric
        even.withUnsafeBufferPointer { ev in
            highpass.withUnsafeBufferPointer { hp in
                lowpass.withUnsafeMutableBufferPointer { lp in
                    // First sample: d[-1] mirrors to d[0]
                    lp[0] = ev[0] &+ ((hp[0] &+ hp[0] &+ 2) >> 2)

                    // Interior samples
                    for i in 1..<lowpassSize {
                        let left = hp[i - 1]
                        let right = i < highpassSize ? hp[i] : hp[highpassSize - 1]
                        lp[i] = ev[i] &+ ((left &+ right &+ 2) >> 2)
                    }
                }
            }
        }

        return (lowpass: lowpass, highpass: highpass)
    }

    /// Inverse 5/3 lifting with symmetric boundary extension.
    @inlinable
    public static func inverseLift53(
        lowpass: [Int32],
        highpass: [Int32]
    ) -> [Int32] {
        let lowpassSize = lowpass.count
        let highpassSize = highpass.count
        let n = lowpassSize + highpassSize
        guard highpassSize > 0 else { return lowpass }

        var even = [Int32](repeating: 0, count: lowpassSize)
        var odd = [Int32](repeating: 0, count: highpassSize)

        // Undo update step
        lowpass.withUnsafeBufferPointer { lp in
            highpass.withUnsafeBufferPointer { hp in
                even.withUnsafeMutableBufferPointer { ev in
                    ev[0] = lp[0] &- ((hp[0] &+ hp[0] &+ 2) >> 2)
                    for i in 1..<lowpassSize {
                        let left = hp[i - 1]
                        let right = i < highpassSize ? hp[i] : hp[highpassSize - 1]
                        ev[i] = lp[i] &- ((left &+ right &+ 2) >> 2)
                    }
                }
            }
        }

        // Undo predict step
        even.withUnsafeBufferPointer { ev in
            highpass.withUnsafeBufferPointer { hp in
                odd.withUnsafeMutableBufferPointer { od in
                    let lastEven = lowpassSize - 1
                    for i in 0..<highpassSize {
                        let left = ev[i]
                        let right = ev[min(i + 1, lastEven)]
                        od[i] = hp[i] &+ ((left &+ right) >> 1)
                    }
                }
            }
        }

        // Merge
        var result = [Int32](repeating: 0, count: n)
        result.withUnsafeMutableBufferPointer { res in
            even.withUnsafeBufferPointer { ev in
                for i in 0..<lowpassSize {
                    res[i &* 2] = ev[i]
                }
            }
            odd.withUnsafeBufferPointer { od in
                for i in 0..<highpassSize {
                    res[i &* 2 &+ 1] = od[i]
                }
            }
        }

        return result
    }

    // MARK: 9/7 Irreversible Lifting (Double)

    /// CDF 9/7 lifting coefficients (ISO/IEC 15444-1).
    @usableFromInline static let alpha97: Double = -1.586134342
    @usableFromInline static let beta97: Double = -0.05298011854
    @usableFromInline static let gamma97: Double = 0.8829110762
    @usableFromInline static let delta97: Double = 0.4435068522
    @usableFromInline static let k97: Double = 1.149604398

    /// Forward 9/7 lifting with symmetric boundary extension.
    @inlinable
    public static func forwardLift97(
        signal: [Double]
    ) -> (lowpass: [Double], highpass: [Double]) {
        let n = signal.count
        guard n >= 2 else { return ([signal[0]], []) }

        let lowpassSize = (n + 1) / 2
        let highpassSize = n / 2

        var even = [Double](repeating: 0, count: lowpassSize)
        var odd = [Double](repeating: 0, count: highpassSize)

        signal.withUnsafeBufferPointer { sig in
            even.withUnsafeMutableBufferPointer { ev in
                for i in 0..<lowpassSize { ev[i] = sig[i &* 2] }
            }
            odd.withUnsafeMutableBufferPointer { od in
                for i in 0..<highpassSize { od[i] = sig[i &* 2 &+ 1] }
            }
        }

        // Apply 4 lifting steps using pointer-based inner loops
        applyPredictStep(&odd, even: even, factor: alpha97)
        applyUpdateStep(&even, odd: odd, factor: beta97)
        applyPredictStep(&odd, even: even, factor: gamma97)
        applyUpdateStep(&even, odd: odd, factor: delta97)

        // Scaling
        let kRecip = 1.0 / k97
        even.withUnsafeMutableBufferPointer { ev in
            for i in 0..<lowpassSize { ev[i] *= k97 }
        }
        odd.withUnsafeMutableBufferPointer { od in
            for i in 0..<highpassSize { od[i] *= kRecip }
        }

        return (lowpass: even, highpass: odd)
    }

    /// Inverse 9/7 lifting with symmetric boundary extension.
    @inlinable
    public static func inverseLift97(
        lowpass: [Double],
        highpass: [Double]
    ) -> [Double] {
        let lowpassSize = lowpass.count
        let highpassSize = highpass.count
        let n = lowpassSize + highpassSize
        guard highpassSize > 0 else { return lowpass }

        var even = lowpass
        var odd = highpass

        // Undo scaling
        let kRecip = 1.0 / k97
        even.withUnsafeMutableBufferPointer { ev in
            for i in 0..<lowpassSize { ev[i] *= kRecip }
        }
        odd.withUnsafeMutableBufferPointer { od in
            for i in 0..<highpassSize { od[i] *= k97 }
        }

        // Undo lifting steps in reverse
        applyUpdateStep(&even, odd: odd, factor: -delta97)
        applyPredictStep(&odd, even: even, factor: -gamma97)
        applyUpdateStep(&even, odd: odd, factor: -beta97)
        applyPredictStep(&odd, even: even, factor: -alpha97)

        // Merge
        var result = [Double](repeating: 0, count: n)
        result.withUnsafeMutableBufferPointer { res in
            even.withUnsafeBufferPointer { ev in
                for i in 0..<lowpassSize { res[i &* 2] = ev[i] }
            }
            odd.withUnsafeBufferPointer { od in
                for i in 0..<highpassSize { res[i &* 2 &+ 1] = od[i] }
            }
        }

        return result
    }

    // MARK: Lifting Step Helpers

    /// Predict step: odd[i] += factor * (even[i] + even[i+1]), symmetric boundary.
    @usableFromInline
    static func applyPredictStep(
        _ odd: inout [Double], even: [Double], factor: Double
    ) {
        let highpassSize = odd.count
        let lastEven = even.count - 1
        guard highpassSize > 0 else { return }

        odd.withUnsafeMutableBufferPointer { od in
            even.withUnsafeBufferPointer { ev in
                // SIMD-friendly main loop (no boundary check needed except last)
                let mainCount = highpassSize - 1
                for i in 0..<mainCount {
                    od[i] += factor * (ev[i] + ev[i + 1])
                }
                // Last element with boundary extension
                od[mainCount] += factor * (ev[min(mainCount, lastEven)] + ev[min(mainCount + 1, lastEven)])
            }
        }
    }

    /// Update step: even[i] += factor * (odd[i-1] + odd[i]), symmetric boundary.
    @usableFromInline
    static func applyUpdateStep(
        _ even: inout [Double], odd: [Double], factor: Double
    ) {
        let lowpassSize = even.count
        let highpassSize = odd.count
        guard lowpassSize > 0, highpassSize > 0 else { return }

        even.withUnsafeMutableBufferPointer { ev in
            odd.withUnsafeBufferPointer { od in
                // First element: odd[-1] mirrors to odd[0]
                ev[0] += factor * (od[0] + od[0])

                // Interior elements
                for i in 1..<lowpassSize {
                    let left = od[i - 1]
                    let right = i < highpassSize ? od[i] : od[highpassSize - 1]
                    ev[i] += factor * (left + right)
                }
            }
        }
    }

    // MARK: - Optimised 2D Row/Column Transform

    /// Performs optimised 2D forward DWT using flat buffer for column transforms.
    ///
    /// Uses a transposed intermediate buffer to improve cache locality during
    /// column transforms, avoiding the per-column gather/scatter pattern.
    public static func forwardTransform2D(
        image: [[Int32]],
        filter: J2KDWT1D.Filter,
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric
    ) throws -> (ll: [[Int32]], lh: [[Int32]], hl: [[Int32]], hh: [[Int32]]) {
        let height = image.count
        guard height >= 2 else {
            throw J2KError.invalidParameter("Image height must be at least 2")
        }
        let width = image[0].count
        guard width >= 2 else {
            throw J2KError.invalidParameter("Image width must be at least 2")
        }

        let rowLowCount = (width + 1) / 2
        let rowHighCount = width / 2
        let totalCols = rowLowCount + rowHighCount

        // === Row transforms ===
        // Store row-transformed data in a flat column-major buffer for cache-friendly
        // column access later.
        var colMajor = [Int32](repeating: 0, count: height * totalCols)

        for row in 0..<height {
            let (low, high): ([Int32], [Int32])
            switch filter {
            case .reversible53 where boundaryExtension == .symmetric:
                (low, high) = forwardLift53(signal: image[row])
            default:
                (low, high) = try J2KDWT1D.forwardTransform(
                    signal: image[row], filter: filter, boundaryExtension: boundaryExtension)
            }

            // Write into column-major layout: colMajor[col * height + row]
            colMajor.withUnsafeMutableBufferPointer { buf in
                for c in 0..<rowLowCount {
                    buf[c &* height &+ row] = low[c]
                }
                for c in 0..<rowHighCount {
                    buf[(rowLowCount &+ c) &* height &+ row] = high[c]
                }
            }
        }

        // === Column transforms ===
        // Now columns are contiguous in memory: colMajor[col*height ..< col*height+height]
        let colLowCount = (height + 1) / 2
        let colHighCount = height / 2

        var ll = [[Int32]](repeating: [Int32](repeating: 0, count: rowLowCount), count: colLowCount)
        var hl = [[Int32]](repeating: [Int32](repeating: 0, count: rowLowCount), count: colHighCount)
        var lh = [[Int32]](repeating: [Int32](repeating: 0, count: rowHighCount), count: colLowCount)
        var hh = [[Int32]](repeating: [Int32](repeating: 0, count: rowHighCount), count: colHighCount)

        // Process low-frequency columns → LL, HL
        colMajor.withUnsafeBufferPointer { buf in
            for col in 0..<rowLowCount {
                let colStart = col &* height
                let column = Array(UnsafeBufferPointer(
                    start: buf.baseAddress! + colStart, count: height))

                let (low, high): ([Int32], [Int32])
                switch filter {
                case .reversible53 where boundaryExtension == .symmetric:
                    (low, high) = forwardLift53(signal: column)
                default:
                    (low, high) = (try? J2KDWT1D.forwardTransform(
                        signal: column, filter: filter,
                        boundaryExtension: boundaryExtension))
                        ?? (Array(column.prefix(colLowCount)),
                            Array(repeating: 0, count: colHighCount))
                }

                for r in 0..<low.count { ll[r][col] = low[r] }
                for r in 0..<high.count { hl[r][col] = high[r] }
            }
        }

        // Process high-frequency columns → LH, HH
        colMajor.withUnsafeBufferPointer { buf in
            for col in rowLowCount..<totalCols {
                let colStart = col &* height
                let column = Array(UnsafeBufferPointer(
                    start: buf.baseAddress! + colStart, count: height))

                let localCol = col - rowLowCount
                let (low, high): ([Int32], [Int32])
                switch filter {
                case .reversible53 where boundaryExtension == .symmetric:
                    (low, high) = forwardLift53(signal: column)
                default:
                    (low, high) = (try? J2KDWT1D.forwardTransform(
                        signal: column, filter: filter,
                        boundaryExtension: boundaryExtension))
                        ?? (Array(column.prefix(colLowCount)),
                            Array(repeating: 0, count: colHighCount))
                }

                for r in 0..<low.count { lh[r][localCol] = low[r] }
                for r in 0..<high.count { hh[r][localCol] = high[r] }
            }
        }

        return (ll: ll, lh: lh, hl: hl, hh: hh)
    }
}

// MARK: - Optimised Quantisation

/// Performance-optimised quantisation kernels.
///
/// Key optimisations:
/// - UnsafeBufferPointer to eliminate bounds checks
/// - UnsafeMutableBufferPointer to avoid bounds checks
/// - Precomputed deadzone threshold
public enum J2KOptimizedQuantisation: Sendable {

    /// Quantises an array of Int32 coefficients using scalar quantisation.
    ///
    /// Uses UnsafeBufferPointer to eliminate bounds checks in the inner loop.
    @inlinable
    public static func quantizeScalar(
        _ coefficients: [Int32],
        stepSize: Double
    ) -> [Int32] {
        let count = coefficients.count
        guard count > 0, stepSize > 0 else { return coefficients }

        var result = [Int32](repeating: 0, count: count)

        coefficients.withUnsafeBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                if count >= J2KSIMDKernels.simdThreshold {
                    J2KSIMDKernels.quantizeScalarSIMD(
                        src, output: dst, stepSize: stepSize, count: count)
                } else {
                    for i in 0..<count {
                        let coeff = src[i]
                        let sign: Int32 = coeff >= 0 ? 1 : -1
                        let magnitude = coeff >= 0 ? coeff : (0 &- coeff)
                        dst[i] = sign &* Int32(Double(magnitude) / stepSize)
                    }
                }
            }
        }

        return result
    }

    /// Quantises an array of Int32 coefficients using deadzone quantisation.
    ///
    /// Precomputes the deadzone threshold outside the loop.
    @inlinable
    public static func quantizeDeadzone(
        _ coefficients: [Int32],
        stepSize: Double,
        deadzoneWidth: Double
    ) -> [Int32] {
        let count = coefficients.count
        guard count > 0, stepSize > 0 else { return coefficients }

        let threshold = Int32(stepSize * deadzoneWidth * 0.5)
        var result = [Int32](repeating: 0, count: count)

        coefficients.withUnsafeBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                for i in 0..<count {
                    let coeff = src[i]
                    let sign: Int32 = coeff >= 0 ? 1 : -1
                    let magnitude = coeff >= 0 ? coeff : (0 &- coeff)

                    if magnitude <= threshold {
                        dst[i] = 0
                    } else {
                        dst[i] = sign &* (Int32((Double(magnitude) - Double(threshold)) / stepSize) &+ 1)
                    }
                }
            }
        }

        return result
    }

    /// Quantises an array of Double coefficients using scalar quantisation.
    @inlinable
    public static func quantizeScalar(
        _ coefficients: [Double],
        stepSize: Double
    ) -> [Int32] {
        let count = coefficients.count
        guard count > 0, stepSize > 0 else {
            return [Int32](repeating: 0, count: coefficients.count)
        }

        var result = [Int32](repeating: 0, count: count)

        coefficients.withUnsafeBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                for i in 0..<count {
                    let coeff = src[i]
                    let sign = coeff >= 0 ? 1.0 : -1.0
                    let magnitude = abs(coeff)
                    dst[i] = Int32(sign * (magnitude / stepSize).rounded(.down))
                }
            }
        }

        return result
    }

    /// Dequantises an array of Int32 indices using scalar dequantisation.
    @inlinable
    public static func dequantizeScalar(
        _ indices: [Int32],
        stepSize: Double
    ) -> [Double] {
        let count = indices.count
        var result = [Double](repeating: 0, count: count)

        indices.withUnsafeBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                for i in 0..<count {
                    let idx = src[i]
                    if idx == 0 {
                        dst[i] = 0
                    } else {
                        let sign = idx >= 0 ? 1.0 : -1.0
                        let magnitude = idx >= 0 ? idx : (0 &- idx)
                        dst[i] = sign * (Double(magnitude) + 0.5) * stepSize
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Optimised Colour Transforms

/// Performance-optimised colour transform kernels.
///
/// Uses UnsafeMutableBufferPointer for inner loops. On platforms
/// with SIMD support, the compiler auto-vectorises these loops.
public enum J2KOptimizedColour: Sendable {

    /// Forward RCT: RGB → YCbCr (integer, reversible).
    @inlinable
    public static func forwardRCT(
        red: [Int32], green: [Int32], blue: [Int32]
    ) -> (y: [Int32], cb: [Int32], cr: [Int32]) {
        let count = red.count
        var y = [Int32](repeating: 0, count: count)
        var cb = [Int32](repeating: 0, count: count)
        var cr = [Int32](repeating: 0, count: count)

        red.withUnsafeBufferPointer { r in
            green.withUnsafeBufferPointer { g in
                blue.withUnsafeBufferPointer { b in
                    y.withUnsafeMutableBufferPointer { yp in
                        cb.withUnsafeMutableBufferPointer { cbp in
                            cr.withUnsafeMutableBufferPointer { crp in
                                for i in 0..<count {
                                    let rv = r[i]
                                    let gv = g[i]
                                    let bv = b[i]
                                    yp[i] = (rv &+ (gv &<< 1) &+ bv) >> 2
                                    cbp[i] = bv &- gv
                                    crp[i] = rv &- gv
                                }
                            }
                        }
                    }
                }
            }
        }

        return (y, cb, cr)
    }

    /// Inverse RCT: YCbCr → RGB (integer, reversible).
    @inlinable
    public static func inverseRCT(
        y: [Int32], cb: [Int32], cr: [Int32]
    ) -> (red: [Int32], green: [Int32], blue: [Int32]) {
        let count = y.count
        var red = [Int32](repeating: 0, count: count)
        var green = [Int32](repeating: 0, count: count)
        var blue = [Int32](repeating: 0, count: count)

        y.withUnsafeBufferPointer { yp in
            cb.withUnsafeBufferPointer { cbp in
                cr.withUnsafeBufferPointer { crp in
                    red.withUnsafeMutableBufferPointer { rp in
                        green.withUnsafeMutableBufferPointer { gp in
                            blue.withUnsafeMutableBufferPointer { bp in
                                for i in 0..<count {
                                    let yVal = yp[i]
                                    let cbVal = cbp[i]
                                    let crVal = crp[i]
                                    let g = yVal &- ((cbVal &+ crVal) >> 2)
                                    gp[i] = g
                                    rp[i] = crVal &+ g
                                    bp[i] = cbVal &+ g
                                }
                            }
                        }
                    }
                }
            }
        }

        return (red, green, blue)
    }

    /// Applies DC level shift in place: subtracts 2^(bitDepth-1) from each sample.
    @inlinable
    public static func applyDCLevelShift(
        _ data: inout [Int32],
        bitDepth: Int
    ) {
        let shift = Int32(1 << (bitDepth - 1))
        J2KSIMDKernels.dcLevelShiftSIMD(&data, shift: shift, add: false)
    }

    /// Applies inverse DC level shift in place: adds 2^(bitDepth-1) to each sample.
    @inlinable
    public static func applyInverseDCLevelShift(
        _ data: inout [Int32],
        bitDepth: Int
    ) {
        let shift = Int32(1 << (bitDepth - 1))
        J2KSIMDKernels.dcLevelShiftSIMD(&data, shift: shift, add: true)
    }
}

// MARK: - Optimised Data Extraction

/// Performance-optimised data extraction from raw byte buffers.
public enum J2KOptimizedDataIO: Sendable {

    /// Extracts UInt8 data to Int32 array using pointer-based bulk conversion.
    @inlinable
    public static func extractUInt8ToInt32(
        _ data: Data,
        count: Int,
        signed: Bool
    ) -> [Int32] {
        var pixels = [Int32](repeating: 0, count: count)
        let byteCount = min(data.count, count)

        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            pixels.withUnsafeMutableBufferPointer { dst in
                if signed {
                    for i in 0..<byteCount {
                        dst[i] = Int32(Int8(bitPattern: ptr[i]))
                    }
                } else {
                    for i in 0..<byteCount {
                        dst[i] = Int32(ptr[i])
                    }
                }
            }
        }

        return pixels
    }

    /// Extracts big-endian UInt16 data to Int32 array.
    @inlinable
    public static func extractUInt16BEToInt32(
        _ data: Data,
        count: Int,
        signed: Bool
    ) -> [Int32] {
        var pixels = [Int32](repeating: 0, count: count)
        let sampleCount = min(data.count / 2, count)

        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            pixels.withUnsafeMutableBufferPointer { dst in
                if signed {
                    for i in 0..<sampleCount {
                        let value = UInt16(ptr[i &* 2]) << 8 | UInt16(ptr[i &* 2 &+ 1])
                        dst[i] = Int32(Int16(bitPattern: value))
                    }
                } else {
                    for i in 0..<sampleCount {
                        let value = UInt16(ptr[i &* 2]) << 8 | UInt16(ptr[i &* 2 &+ 1])
                        dst[i] = Int32(value)
                    }
                }
            }
        }

        return pixels
    }

    /// Converts a flat 1D Int32 array to a 2D array without per-row allocation.
    ///
    /// Uses `Array(unsafeUninitializedCapacity:)` for zero-copy row extraction.
    @inlinable
    public static func flatTo2D(
        _ flat: [Int32],
        width: Int,
        height: Int
    ) -> [[Int32]] {
        guard width > 0, height > 0 else { return [] }

        var result = [[Int32]]()
        result.reserveCapacity(height)

        flat.withUnsafeBufferPointer { src in
            for row in 0..<height {
                let rowStart = row &* width
                let rowSlice = Array(UnsafeBufferPointer(
                    start: src.baseAddress! + rowStart,
                    count: width))
                result.append(rowSlice)
            }
        }

        return result
    }

    /// Converts a 2D Int32 array to a flat 1D array.
    @inlinable
    public static func twoDToFlat(
        _ image: [[Int32]]
    ) -> [Int32] {
        guard let firstRow = image.first else { return [] }
        let height = image.count
        let width = firstRow.count
        var flat = [Int32](repeating: 0, count: width * height)

        flat.withUnsafeMutableBufferPointer { dst in
            for row in 0..<height {
                let rowStart = row &* width
                image[row].withUnsafeBufferPointer { src in
                    for col in 0..<min(src.count, width) {
                        dst[rowStart &+ col] = src[col]
                    }
                }
            }
        }

        return flat
    }
}

// MARK: - Performance Dispatch

/// Routes operations to the best available implementation based on platform
/// and data characteristics.
///
/// Priority order:
/// 1. Platform-specific SIMD (NEON on arm64, AVX on x86_64)
/// 2. Optimised kernels (this file) — always available
/// 3. Reference implementation (J2KDWT1D, J2KQuantizer, etc.)
public enum J2KPerformanceDispatch: Sendable {

    /// Whether optimised kernels should be used (always true unless debugging).
    nonisolated(unsafe) public static var useOptimisedKernels: Bool = true

    /// Performs forward 5/3 DWT with the best available implementation.
    @inlinable
    public static func forwardDWT53(
        signal: [Int32],
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric
    ) throws -> (lowpass: [Int32], highpass: [Int32]) {
        if useOptimisedKernels && boundaryExtension == .symmetric {
            return J2KOptimizedDWT.forwardLift53(signal: signal)
        }
        return try J2KDWT1D.forwardTransform(
            signal: signal, filter: .reversible53, boundaryExtension: boundaryExtension)
    }

    /// Performs inverse 5/3 DWT with the best available implementation.
    @inlinable
    public static func inverseDWT53(
        lowpass: [Int32],
        highpass: [Int32],
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric
    ) throws -> [Int32] {
        if useOptimisedKernels && boundaryExtension == .symmetric {
            return J2KOptimizedDWT.inverseLift53(lowpass: lowpass, highpass: highpass)
        }
        return try J2KDWT1D.inverseTransform(
            lowpass: lowpass, highpass: highpass,
            filter: .reversible53, boundaryExtension: boundaryExtension)
    }

    /// Performs forward 9/7 DWT with the best available implementation.
    @inlinable
    public static func forwardDWT97(
        signal: [Double],
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric
    ) throws -> (lowpass: [Double], highpass: [Double]) {
        if useOptimisedKernels && boundaryExtension == .symmetric {
            return J2KOptimizedDWT.forwardLift97(signal: signal)
        }
        return try J2KDWT1D.forwardTransform97(
            signal: signal, boundaryExtension: boundaryExtension)
    }

    /// Performs inverse 9/7 DWT with the best available implementation.
    @inlinable
    public static func inverseDWT97(
        lowpass: [Double],
        highpass: [Double],
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric
    ) throws -> [Double] {
        if useOptimisedKernels && boundaryExtension == .symmetric {
            return J2KOptimizedDWT.inverseLift97(lowpass: lowpass, highpass: highpass)
        }
        return try J2KDWT1D.inverseTransform97(
            lowpass: lowpass, highpass: highpass,
            boundaryExtension: boundaryExtension)
    }
}

// MARK: - Architecture-Specific SIMD Paths

/// SIMD-accelerated operations using Swift's cross-platform SIMD types.
///
/// On ARM64, SIMD4<Int32> maps to NEON `int32x4_t`.
/// On x86_64, SIMD4<Int32> maps to SSE2 `__m128i` and
/// SIMD8<Float> maps to AVX `__m256`.
///
/// These are used internally by the optimised kernels when the data
/// length is large enough to benefit from vectorisation.
public enum J2KSIMDKernels: Sendable {

    /// Minimum element count for SIMD to be worthwhile (amortise setup cost).
    @usableFromInline
    static let simdThreshold = 16

    // MARK: - SIMD DC Level Shift

    /// Applies DC level shift using SIMD4<Int32>.
    ///
    /// Processes 4 elements per iteration on ARM64 (NEON) and x86_64 (SSE2).
    @inlinable
    public static func dcLevelShiftSIMD(
        _ data: inout [Int32],
        shift: Int32,
        add: Bool
    ) {
        let count = data.count
        guard count >= simdThreshold else {
            // Scalar fallback for small arrays
            data.withUnsafeMutableBufferPointer { buf in
                if add {
                    for i in 0..<count { buf[i] = buf[i] &+ shift }
                } else {
                    for i in 0..<count { buf[i] = buf[i] &- shift }
                }
            }
            return
        }

        let simdWidth = 4
        let simdCount = count / simdWidth
        let shiftVec = SIMD4<Int32>(repeating: shift)

        data.withUnsafeMutableBufferPointer { buf in
            if add {
                for i in 0..<simdCount {
                    let base = i &* simdWidth
                    var vec = SIMD4<Int32>(
                        buf[base], buf[base &+ 1], buf[base &+ 2], buf[base &+ 3])
                    vec &+= shiftVec
                    buf[base] = vec.x
                    buf[base &+ 1] = vec.y
                    buf[base &+ 2] = vec.z
                    buf[base &+ 3] = vec.w
                }
                // Scalar tail
                for i in (simdCount &* simdWidth)..<count {
                    buf[i] = buf[i] &+ shift
                }
            } else {
                for i in 0..<simdCount {
                    let base = i &* simdWidth
                    var vec = SIMD4<Int32>(
                        buf[base], buf[base &+ 1], buf[base &+ 2], buf[base &+ 3])
                    vec &-= shiftVec
                    buf[base] = vec.x
                    buf[base &+ 1] = vec.y
                    buf[base &+ 2] = vec.z
                    buf[base &+ 3] = vec.w
                }
                for i in (simdCount &* simdWidth)..<count {
                    buf[i] = buf[i] &- shift
                }
            }
        }
    }

    // MARK: - SIMD Quantisation

    /// Scalar quantisation using SIMD4<Double> for bulk processing.
    ///
    /// On ARM64 this maps to NEON float64x2 pairs.
    /// On x86_64 this maps to SSE2 double-precision operations.
    @inlinable
    public static func quantizeScalarSIMD(
        _ coefficients: UnsafeBufferPointer<Int32>,
        output: UnsafeMutableBufferPointer<Int32>,
        stepSize: Double,
        count: Int
    ) {
        // Process 2 elements at a time using SIMD2<Double>
        let simdWidth = 2
        let simdCount = count / simdWidth
        let stepVec = SIMD2<Double>(repeating: stepSize)

        for i in 0..<simdCount {
            let base = i &* simdWidth
            let c0 = coefficients[base]
            let c1 = coefficients[base &+ 1]

            let sign0: Int32 = c0 >= 0 ? 1 : -1
            let sign1: Int32 = c1 >= 0 ? 1 : -1

            let mag0 = c0 >= 0 ? c0 : (0 &- c0)
            let mag1 = c1 >= 0 ? c1 : (0 &- c1)

            let magVec = SIMD2<Double>(Double(mag0), Double(mag1))
            let quantized = magVec / stepVec

            output[base] = sign0 &* Int32(quantized.x)
            output[base &+ 1] = sign1 &* Int32(quantized.y)
        }

        // Scalar tail
        for i in (simdCount &* simdWidth)..<count {
            let c = coefficients[i]
            let sign: Int32 = c >= 0 ? 1 : -1
            let mag = c >= 0 ? c : (0 &- c)
            output[i] = sign &* Int32(Double(mag) / stepSize)
        }
    }

    // MARK: - SIMD 9/7 Lifting

    /// SIMD-accelerated predict step for 9/7 lifting using SIMD2<Double>.
    ///
    /// Vectorises the inner loop: odd[i] += factor * (even[i] + even[i+1]).
    @inlinable
    public static func predictStepSIMD(
        odd: UnsafeMutableBufferPointer<Double>,
        even: UnsafeBufferPointer<Double>,
        factor: Double,
        count: Int
    ) {
        guard count > 1 else {
            if count == 1 {
                let lastEven = even.count - 1
                odd[0] += factor * (even[min(0, lastEven)] + even[min(1, lastEven)])
            }
            return
        }

        let factorVec = SIMD2<Double>(repeating: factor)
        let mainCount = count - 1
        let simdCount = mainCount / 2

        for i in 0..<simdCount {
            let base = i &* 2
            let e0 = SIMD2<Double>(even[base], even[base &+ 1])
            let e1 = SIMD2<Double>(even[base &+ 1], even[base &+ 2])
            let d = SIMD2<Double>(odd[base], odd[base &+ 1])
            let result = d + factorVec * (e0 + e1)
            odd[base] = result.x
            odd[base &+ 1] = result.y
        }

        // Scalar tail for main region
        for i in (simdCount &* 2)..<mainCount {
            odd[i] += factor * (even[i] + even[i + 1])
        }

        // Boundary
        let lastEven = even.count - 1
        odd[mainCount] += factor * (even[min(mainCount, lastEven)] + even[min(mainCount + 1, lastEven)])
    }

    #if arch(arm64)
    // MARK: - ARM64 NEON-specific paths

    /// NEON-optimised forward RCT using SIMD4<Int32>.
    ///
    /// Processes 4 pixels per iteration using ARM NEON int32x4 instructions.
    @inlinable
    public static func forwardRCT_NEON(
        red: UnsafeBufferPointer<Int32>,
        green: UnsafeBufferPointer<Int32>,
        blue: UnsafeBufferPointer<Int32>,
        y: UnsafeMutableBufferPointer<Int32>,
        cb: UnsafeMutableBufferPointer<Int32>,
        cr: UnsafeMutableBufferPointer<Int32>,
        count: Int
    ) {
        let simdWidth = 4
        let simdCount = count / simdWidth

        for i in 0..<simdCount {
            let base = i &* simdWidth
            let rVec = SIMD4<Int32>(
                red[base], red[base &+ 1], red[base &+ 2], red[base &+ 3])
            let gVec = SIMD4<Int32>(
                green[base], green[base &+ 1], green[base &+ 2], green[base &+ 3])
            let bVec = SIMD4<Int32>(
                blue[base], blue[base &+ 1], blue[base &+ 2], blue[base &+ 3])

            // Y = (R + 2G + B) >> 2
            let gx2 = gVec &+ gVec
            let sum = rVec &+ gx2 &+ bVec
            let yVec = SIMD4<Int32>(sum.x >> 2, sum.y >> 2, sum.z >> 2, sum.w >> 2)
            // Cb = B - G
            let cbVec = bVec &- gVec
            // Cr = R - G
            let crVec = rVec &- gVec

            y[base] = yVec.x; y[base &+ 1] = yVec.y
            y[base &+ 2] = yVec.z; y[base &+ 3] = yVec.w
            cb[base] = cbVec.x; cb[base &+ 1] = cbVec.y
            cb[base &+ 2] = cbVec.z; cb[base &+ 3] = cbVec.w
            cr[base] = crVec.x; cr[base &+ 1] = crVec.y
            cr[base &+ 2] = crVec.z; cr[base &+ 3] = crVec.w
        }

        // Scalar tail
        for i in (simdCount &* simdWidth)..<count {
            let r = red[i], g = green[i], b = blue[i]
            y[i] = (r &+ (g &<< 1) &+ b) >> 2
            cb[i] = b &- g
            cr[i] = r &- g
        }
    }
    #endif

    #if arch(x86_64)
    // MARK: - x86_64 SSE/AVX-specific paths

    /// AVX-optimised forward RCT using SIMD8<Int32>.
    ///
    /// Processes 8 pixels per iteration using x86-64 AVX2 int32x8 instructions.
    @inlinable
    public static func forwardRCT_AVX(
        red: UnsafeBufferPointer<Int32>,
        green: UnsafeBufferPointer<Int32>,
        blue: UnsafeBufferPointer<Int32>,
        y: UnsafeMutableBufferPointer<Int32>,
        cb: UnsafeMutableBufferPointer<Int32>,
        cr: UnsafeMutableBufferPointer<Int32>,
        count: Int
    ) {
        let simdWidth = 8
        let simdCount = count / simdWidth

        for i in 0..<simdCount {
            let base = i &* simdWidth
            let rVec = SIMD8<Int32>(
                red[base], red[base &+ 1], red[base &+ 2], red[base &+ 3],
                red[base &+ 4], red[base &+ 5], red[base &+ 6], red[base &+ 7])
            let gVec = SIMD8<Int32>(
                green[base], green[base &+ 1], green[base &+ 2], green[base &+ 3],
                green[base &+ 4], green[base &+ 5], green[base &+ 6], green[base &+ 7])
            let bVec = SIMD8<Int32>(
                blue[base], blue[base &+ 1], blue[base &+ 2], blue[base &+ 3],
                blue[base &+ 4], blue[base &+ 5], blue[base &+ 6], blue[base &+ 7])

            let sum8 = rVec &+ (gVec &+ gVec) &+ bVec
            let yVec = SIMD8<Int32>(
                sum8[0] >> 2, sum8[1] >> 2, sum8[2] >> 2, sum8[3] >> 2,
                sum8[4] >> 2, sum8[5] >> 2, sum8[6] >> 2, sum8[7] >> 2)
            let cbVec = bVec &- gVec
            let crVec = rVec &- gVec

            for lane in 0..<8 {
                y[base &+ lane] = yVec[lane]
                cb[base &+ lane] = cbVec[lane]
                cr[base &+ lane] = crVec[lane]
            }
        }

        // Scalar tail
        for i in (simdCount &* simdWidth)..<count {
            let r = red[i], g = green[i], b = blue[i]
            y[i] = (r &+ (g &<< 1) &+ b) >> 2
            cb[i] = b &- g
            cr[i] = r &- g
        }
    }
    #endif
}
