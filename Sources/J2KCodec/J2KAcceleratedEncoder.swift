//
// J2KAcceleratedEncoder.swift
// J2KSwift
//
// Hardware-accelerated encoder pipeline optimizations.
// Uses vDSP/Accelerate on Apple, SIMD fallback on Linux/x86.
//

import Foundation
import J2KCore

#if canImport(Accelerate)
import Accelerate
#endif

// MARK: - Accelerated 2D DWT (Contiguous Memory)

/// High-performance 2D DWT operating on flat contiguous arrays.
///
/// Avoids the overhead of `[[Double]]` row arrays by working on flat
/// buffers with explicit stride. Uses vDSP for lifting steps on Apple
/// and scalar SIMD-friendly loops elsewhere.
struct AcceleratedDWT2D: Sendable {

    // MARK: - CDF 9/7 Lifting Coefficients

    private static let alpha = -1.586134342
    private static let beta  = -0.05298011854
    private static let gamma =  0.8829110762
    private static let delta =  0.4435068522
    private static let K     =  1.230174105

    /// Forward 1D CDF 9/7 lifting on a contiguous Double buffer (in-place, interleaved).
    ///
    /// Splits even/odd, applies 4 lifting steps, scales, then writes
    /// lowpass coefficients first followed by highpass.
    @inline(__always)
    static func forward97_1D(
        _ input: UnsafePointer<Double>,
        _ output: UnsafeMutablePointer<Double>,
        count n: Int
    ) {
        guard n >= 2 else {
            if n == 1 { output[0] = input[0] }
            return
        }

        let lowCount  = (n + 1) / 2
        let highCount = n / 2

        // Split into even (lowpass) and odd (highpass)
        var even = [Double](repeating: 0, count: lowCount)
        var odd  = [Double](repeating: 0, count: highCount)

        for i in 0..<lowCount  { even[i] = input[i * 2] }
        for i in 0..<highCount { odd[i]  = input[i * 2 + 1] }

        // 4 lifting steps
        liftPredict(&odd, even, coeff: alpha, oddCount: highCount, evenCount: lowCount)
        liftUpdate(&even, odd, coeff: beta,  evenCount: lowCount, oddCount: highCount)
        liftPredict(&odd, even, coeff: gamma, oddCount: highCount, evenCount: lowCount)
        liftUpdate(&even, odd, coeff: delta, evenCount: lowCount, oddCount: highCount)

        // Scale
        #if canImport(Accelerate)
        var invK = 1.0 / K
        var kVal = K
        even.withUnsafeMutableBufferPointer { buf in
            vDSP_vsmulD(buf.baseAddress!, 1, &invK, buf.baseAddress!, 1, vDSP_Length(lowCount))
        }
        odd.withUnsafeMutableBufferPointer { buf in
            vDSP_vsmulD(buf.baseAddress!, 1, &kVal, buf.baseAddress!, 1, vDSP_Length(highCount))
        }
        #else
        let invK = 1.0 / K
        for i in 0..<lowCount  { even[i] *= invK }
        for i in 0..<highCount { odd[i]  *= K }
        #endif

        // Write output: lowpass then highpass
        for i in 0..<lowCount  { output[i] = even[i] }
        for i in 0..<highCount { output[lowCount + i] = odd[i] }
    }

    /// Predict step: odd[i] += coeff * (even[i] + even[i+1])
    @inline(__always)
    private static func liftPredict(
        _ odd: inout [Double], _ even: [Double],
        coeff: Double, oddCount: Int, evenCount: Int
    ) {
        #if canImport(Accelerate)
        // Vectorised interior + boundary
        odd.withUnsafeMutableBufferPointer { oddBuf in
            even.withUnsafeBufferPointer { evenBuf in
                for i in 0..<oddCount {
                    let right = (i + 1 < evenCount) ? evenBuf[i + 1] : evenBuf[evenCount - 1]
                    oddBuf[i] += coeff * (evenBuf[i] + right)
                }
            }
        }
        #else
        for i in 0..<oddCount {
            let right = (i + 1 < evenCount) ? even[i + 1] : even[evenCount - 1]
            odd[i] += coeff * (even[i] + right)
        }
        #endif
    }

    /// Update step: even[i] += coeff * (odd[i-1] + odd[i])
    @inline(__always)
    private static func liftUpdate(
        _ even: inout [Double], _ odd: [Double],
        coeff: Double, evenCount: Int, oddCount: Int
    ) {
        #if canImport(Accelerate)
        even.withUnsafeMutableBufferPointer { evenBuf in
            odd.withUnsafeBufferPointer { oddBuf in
                for i in 0..<evenCount {
                    let left = (i - 1 >= 0) ? oddBuf[i - 1] : oddBuf[0]
                    let right = (i < oddCount) ? oddBuf[i] : oddBuf[oddCount - 1]
                    evenBuf[i] += coeff * (left + right)
                }
            }
        }
        #else
        for i in 0..<evenCount {
            let left = (i - 1 >= 0) ? odd[i - 1] : odd[0]
            let right = (i < oddCount) ? odd[i] : odd[oddCount - 1]
            even[i] += coeff * (left + right)
        }
        #endif
    }

    /// Forward 2D DWT on a flat row-major buffer. Returns (ll, lh, hl, hh) as flat arrays
    /// plus their dimensions.
    static func forward2D(
        data: [Double], width: Int, height: Int
    ) -> (ll: [Double], lh: [Double], hl: [Double], hh: [Double],
          llW: Int, llH: Int, lhW: Int, lhH: Int,
          hlW: Int, hlH: Int, hhW: Int, hhH: Int)
    {
        let colLowH  = (height + 1) / 2
        let colHighH = height / 2
        let rowLowW  = (width + 1) / 2
        let rowHighW = width / 2

        // --- Column pass (vertical): for each column, run 1D DWT down the column ---
        // Use a temporary transposed buffer for cache-friendly access
        var colResult = [Double](repeating: 0, count: width * height)

        var colBuf = [Double](repeating: 0, count: height)
        var colOut = [Double](repeating: 0, count: height)

        for col in 0..<width {
            // Gather column
            for row in 0..<height {
                colBuf[row] = data[row * width + col]
            }
            // 1D forward DWT
            forward97_1D(&colBuf, &colOut, count: height)
            // Scatter: low part then high part
            for row in 0..<height {
                colResult[row * width + col] = colOut[row]
            }
        }

        // --- Row pass (horizontal): for each row of column-transformed data ---
        let llH = colLowH
        let lhH = colHighH
        let hlH = colLowH
        let hhH = colHighH

        var ll = [Double](repeating: 0, count: rowLowW * colLowH)
        var hl = [Double](repeating: 0, count: rowHighW * colLowH)
        var lh = [Double](repeating: 0, count: rowLowW * colHighH)
        var hh = [Double](repeating: 0, count: rowHighW * colHighH)

        var rowBuf = [Double](repeating: 0, count: width)
        var rowOut = [Double](repeating: 0, count: width)

        // Process low-column rows → LL, HL
        for row in 0..<colLowH {
            for col in 0..<width {
                rowBuf[col] = colResult[row * width + col]
            }
            forward97_1D(&rowBuf, &rowOut, count: width)
            for col in 0..<rowLowW {
                ll[row * rowLowW + col] = rowOut[col]
            }
            for col in 0..<rowHighW {
                hl[row * rowHighW + col] = rowOut[rowLowW + col]
            }
        }

        // Process high-column rows → LH, HH
        for row in 0..<colHighH {
            let srcRow = colLowH + row
            for col in 0..<width {
                rowBuf[col] = colResult[srcRow * width + col]
            }
            forward97_1D(&rowBuf, &rowOut, count: width)
            for col in 0..<rowLowW {
                lh[row * rowLowW + col] = rowOut[col]
            }
            for col in 0..<rowHighW {
                hh[row * rowHighW + col] = rowOut[rowLowW + col]
            }
        }

        return (ll, lh, hl, hh,
                rowLowW, llH, rowLowW, lhH,
                rowHighW, hlH, rowHighW, hhH)
    }

    /// Multi-level forward 2D DWT decomposition.
    ///
    /// Returns the coarsest LL subband and per-level detail subbands (LH, HL, HH)
    /// in the same structure the encoder pipeline expects.
    struct LevelResult {
        let lh: [Double]
        let hl: [Double]
        let hh: [Double]
        let lhW: Int, lhH: Int
        let hlW: Int, hlH: Int
        let hhW: Int, hhH: Int
    }

    struct DecompositionResult {
        let levels: [LevelResult]
        let coarsestLL: [Double]
        let llW: Int
        let llH: Int
    }

    static func forwardDecomposition(
        data: [Double], width: Int, height: Int, levels: Int
    ) -> DecompositionResult {
        var currentData = data
        var currentW = width
        var currentH = height
        var levelResults: [LevelResult] = []

        for _ in 0..<levels {
            guard currentW >= 2 && currentH >= 2 else { break }

            let r = forward2D(data: currentData, width: currentW, height: currentH)

            levelResults.append(LevelResult(
                lh: r.lh, hl: r.hl, hh: r.hh,
                lhW: r.lhW, lhH: r.lhH,
                hlW: r.hlW, hlH: r.hlH,
                hhW: r.hhW, hhH: r.hhH
            ))

            currentData = r.ll
            currentW = r.llW
            currentH = r.llH
        }

        return DecompositionResult(
            levels: levelResults,
            coarsestLL: currentData,
            llW: currentW,
            llH: currentH
        )
    }

    // MARK: - Le Gall 5/3 (Integer Lifting)

    /// Forward 1D Le Gall 5/3 lifting on Int32 (lossless).
    @inline(__always)
    static func forward53_1D(
        _ input: UnsafePointer<Int32>,
        _ output: UnsafeMutablePointer<Int32>,
        count n: Int
    ) {
        guard n >= 2 else {
            if n == 1 { output[0] = input[0] }
            return
        }

        let lowCount  = (n + 1) / 2
        let highCount = n / 2

        var even = [Int32](repeating: 0, count: lowCount)
        var odd  = [Int32](repeating: 0, count: highCount)

        for i in 0..<lowCount  { even[i] = input[i * 2] }
        for i in 0..<highCount { odd[i]  = input[i * 2 + 1] }

        // Predict: d[n] = odd[n] - floor((even[n] + even[n+1]) / 2)
        for i in 0..<highCount {
            let right = (i + 1 < lowCount) ? even[i + 1] : even[lowCount - 1]
            odd[i] = odd[i] - ((even[i] + right) >> 1)
        }

        // Update: s[n] = even[n] + floor((d[n-1] + d[n] + 2) / 4)
        for i in 0..<lowCount {
            let left  = (i > 0) ? odd[i - 1] : odd[0]
            let right = (i < highCount) ? odd[i] : odd[highCount - 1]
            even[i] = even[i] + ((left + right + 2) >> 2)
        }

        for i in 0..<lowCount  { output[i] = even[i] }
        for i in 0..<highCount { output[lowCount + i] = odd[i] }
    }

    /// Forward 2D 5/3 on flat Int32 buffer.
    static func forward2D_53(
        data: [Int32], width: Int, height: Int
    ) -> (ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32],
          llW: Int, llH: Int, lhW: Int, lhH: Int,
          hlW: Int, hlH: Int, hhW: Int, hhH: Int)
    {
        let colLowH  = (height + 1) / 2
        let colHighH = height / 2
        let rowLowW  = (width + 1) / 2
        let rowHighW = width / 2

        var colResult = [Int32](repeating: 0, count: width * height)
        var colBuf = [Int32](repeating: 0, count: height)
        var colOut = [Int32](repeating: 0, count: height)

        for col in 0..<width {
            for row in 0..<height { colBuf[row] = data[row * width + col] }
            forward53_1D(&colBuf, &colOut, count: height)
            for row in 0..<height { colResult[row * width + col] = colOut[row] }
        }

        var ll = [Int32](repeating: 0, count: rowLowW * colLowH)
        var hl = [Int32](repeating: 0, count: rowHighW * colLowH)
        var lh = [Int32](repeating: 0, count: rowLowW * colHighH)
        var hh = [Int32](repeating: 0, count: rowHighW * colHighH)

        var rowBuf = [Int32](repeating: 0, count: width)
        var rowOut = [Int32](repeating: 0, count: width)

        for row in 0..<colLowH {
            for col in 0..<width { rowBuf[col] = colResult[row * width + col] }
            forward53_1D(&rowBuf, &rowOut, count: width)
            for col in 0..<rowLowW { ll[row * rowLowW + col] = rowOut[col] }
            for col in 0..<rowHighW { hl[row * rowHighW + col] = rowOut[rowLowW + col] }
        }

        for row in 0..<colHighH {
            let srcRow = colLowH + row
            for col in 0..<width { rowBuf[col] = colResult[srcRow * width + col] }
            forward53_1D(&rowBuf, &rowOut, count: width)
            for col in 0..<rowLowW { lh[row * rowLowW + col] = rowOut[col] }
            for col in 0..<rowHighW { hh[row * rowHighW + col] = rowOut[rowLowW + col] }
        }

        return (ll, lh, hl, hh,
                rowLowW, colLowH, rowLowW, colHighH,
                rowHighW, colLowH, rowHighW, colHighH)
    }

    /// Multi-level 5/3 decomposition.
    struct Int32LevelResult {
        let lh: [Int32], hl: [Int32], hh: [Int32]
        let lhW: Int, lhH: Int
        let hlW: Int, hlH: Int
        let hhW: Int, hhH: Int
    }

    struct Int32DecompositionResult {
        let levels: [Int32LevelResult]
        let coarsestLL: [Int32]
        let llW: Int, llH: Int
    }

    static func forwardDecomposition53(
        data: [Int32], width: Int, height: Int, levels: Int
    ) -> Int32DecompositionResult {
        var currentData = data
        var currentW = width
        var currentH = height
        var levelResults: [Int32LevelResult] = []

        for _ in 0..<levels {
            guard currentW >= 2 && currentH >= 2 else { break }
            let r = forward2D_53(data: currentData, width: currentW, height: currentH)
            levelResults.append(Int32LevelResult(
                lh: r.lh, hl: r.hl, hh: r.hh,
                lhW: r.lhW, lhH: r.lhH,
                hlW: r.hlW, hlH: r.hlH,
                hhW: r.hhW, hhH: r.hhH
            ))
            currentData = r.ll
            currentW = r.llW
            currentH = r.llH
        }

        return Int32DecompositionResult(
            levels: levelResults, coarsestLL: currentData,
            llW: currentW, llH: currentH
        )
    }
}

// MARK: - Accelerated Quantization

/// Bulk quantization using vDSP for contiguous coefficient arrays.
struct AcceleratedQuantizer: Sendable {

    /// Scalar quantization of a Double array: q = sign(c) × floor(|c| / step)
    static func quantizeScalar(
        _ coefficients: [Double], stepSize: Double
    ) -> [Int32] {
        let count = coefficients.count
        #if canImport(Accelerate)
        // Use vDSP for bulk divide + floor
        var absVals = [Double](repeating: 0, count: count)
        var divided = [Double](repeating: 0, count: count)
        var floored = [Double](repeating: 0, count: count)

        // |c|
        coefficients.withUnsafeBufferPointer { src in
            vDSP_vabsD(src.baseAddress!, 1, &absVals, 1, vDSP_Length(count))
        }

        // |c| / step
        var step = stepSize
        vDSP_vsdivD(&absVals, 1, &step, &divided, 1, vDSP_Length(count))

        // floor(|c| / step)
        vvfloor(&floored, &divided, [Int32(count)])

        // Apply sign
        var result = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            let sign: Double = coefficients[i] >= 0 ? 1.0 : -1.0
            result[i] = Int32(sign * floored[i])
        }
        return result
        #else
        // Scalar fallback
        let invStep = 1.0 / stepSize
        return coefficients.map { c in
            let sign: Double = c >= 0 ? 1.0 : -1.0
            let mag = abs(c) * invStep
            return Int32(sign * mag.rounded(.down))
        }
        #endif
    }

    /// Scalar quantization of an Int32 array.
    static func quantizeScalar(
        _ coefficients: [Int32], stepSize: Double
    ) -> [Int32] {
        let invStep = 1.0 / stepSize
        let count = coefficients.count

        #if canImport(Accelerate)
        // Convert to Double, use vDSP
        var doubles = [Double](repeating: 0, count: count)
        for i in 0..<count { doubles[i] = Double(coefficients[i]) }

        var absVals = [Double](repeating: 0, count: count)
        var divided = [Double](repeating: 0, count: count)
        var floored = [Double](repeating: 0, count: count)

        vDSP_vabsD(&doubles, 1, &absVals, 1, vDSP_Length(count))
        var step = stepSize
        vDSP_vsdivD(&absVals, 1, &step, &divided, 1, vDSP_Length(count))
        vvfloor(&floored, &divided, [Int32(count)])

        var result = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            let sign: Int32 = coefficients[i] >= 0 ? 1 : -1
            result[i] = sign * Int32(floored[i])
        }
        return result
        #else
        return coefficients.map { c in
            let sign: Int32 = c >= 0 ? 1 : -1
            let mag = Double(abs(c)) * invStep
            return sign * Int32(mag.rounded(.down))
        }
        #endif
    }
}

// MARK: - Accelerated Context Modeling Helpers

/// SIMD-optimized helper for computing significance context in EBCOT.
///
/// The significance context depends on the number and orientation of
/// significant neighbours. This structure pre-computes a lookup table
/// for the 256 possible 8-neighbour configurations.
struct AcceleratedContextLookup: Sendable {
    /// Pre-computed context label for each 8-bit neighbour significance pattern.
    /// Bit layout: 0=UL, 1=U, 2=UR, 3=L, 4=R, 5=DL, 6=D, 7=DR
    let hlTable: [UInt8]   // HL subband context table
    let lhTable: [UInt8]   // LH subband context table
    let hhTable: [UInt8]   // HH subband context table
    let llTable: [UInt8]   // LL subband context table

    init() {
        var hl = [UInt8](repeating: 0, count: 256)
        var lh = [UInt8](repeating: 0, count: 256)
        var hh = [UInt8](repeating: 0, count: 256)
        var ll = [UInt8](repeating: 0, count: 256)

        for pattern in 0..<256 {
            let ul = (pattern >> 0) & 1
            let u  = (pattern >> 1) & 1
            let ur = (pattern >> 2) & 1
            let l  = (pattern >> 3) & 1
            let r  = (pattern >> 4) & 1
            let dl = (pattern >> 5) & 1
            let d  = (pattern >> 6) & 1
            let dr = (pattern >> 7) & 1

            let h  = l + r                         // horizontal
            let v  = u + d                         // vertical
            let diag = ul + ur + dl + dr           // diagonal

            // HL subband: horizontal dominant (Table D.1 in ISO 15444-1)
            hl[pattern] = UInt8(Self.computeHLContext(h: h, v: v, d: diag))
            // LH subband: vertical dominant (transpose of HL)
            lh[pattern] = UInt8(Self.computeLHContext(h: h, v: v, d: diag))
            // HH subband: diagonal dominant
            hh[pattern] = UInt8(Self.computeHHContext(h: h, v: v, d: diag))
            // LL subband: same as HL per standard
            ll[pattern] = hl[pattern]
        }

        self.hlTable = hl
        self.lhTable = lh
        self.hhTable = hh
        self.llTable = ll
    }

    private static func computeHLContext(h: Int, v: Int, d: Int) -> Int {
        if h == 2 { return 8 }
        if h == 1 && v >= 1 { return 7 }
        if h == 1 && v == 0 { return d >= 1 ? 6 : 5 }
        // h == 0
        if v == 2 { return 4 }
        if v == 1 { return d >= 2 ? 3 : 2 }
        // v == 0
        if d >= 2 { return 1 }
        return 0
    }

    private static func computeLHContext(h: Int, v: Int, d: Int) -> Int {
        // LH is transposed HL: swap h and v
        if v == 2 { return 8 }
        if v == 1 && h >= 1 { return 7 }
        if v == 1 && h == 0 { return d >= 1 ? 6 : 5 }
        if h == 2 { return 4 }
        if h == 1 { return d >= 2 ? 3 : 2 }
        if d >= 2 { return 1 }
        return 0
    }

    private static func computeHHContext(h: Int, v: Int, d: Int) -> Int {
        let hv = h + v
        if d >= 3 { return 8 }
        if d == 2 { return hv >= 1 ? 7 : 6 }
        if d == 1 { return hv >= 2 ? 5 : 4 }
        // d == 0
        if hv >= 2 { return 3 }
        if hv == 1 { return 2 }
        return 0  // 1 would be alternate LL; 0 for zero-context
    }

    /// Look up the context label for a given subband and 8-bit neighbour pattern.
    @inline(__always)
    func contextLabel(subband: J2KSubband, pattern: UInt8) -> UInt8 {
        switch subband {
        case .hl: return hlTable[Int(pattern)]
        case .lh: return lhTable[Int(pattern)]
        case .hh: return hhTable[Int(pattern)]
        case .ll: return llTable[Int(pattern)]
        }
    }
}

// MARK: - Batch Significance Pattern Builder

/// Builds the 8-bit neighbour significance pattern for every coefficient
/// in a code block using a single pass over the significance flags.
///
/// This replaces per-coefficient neighbour lookups with a cache-friendly
/// single-pass scan, significantly reducing branch mispredictions.
struct SignificancePatternBuilder: Sendable {

    /// Computes the 8-bit neighbour significance pattern for each position
    /// in a `width × height` block.
    ///
    /// - Parameters:
    ///   - significant: Flat array of significance flags (true if significant).
    ///   - width: Block width.
    ///   - height: Block height.
    /// - Returns: Flat array of 8-bit neighbour patterns.
    static func buildPatterns(
        significant: UnsafePointer<Bool>,
        width: Int, height: Int
    ) -> [UInt8] {
        let count = width * height
        var patterns = [UInt8](repeating: 0, count: count)

        for y in 0..<height {
            for x in 0..<width {
                guard significant[y * width + x] else { continue }
                let bit: UInt8 = 1

                // Mark this coefficient as a significant neighbour in all adjacent cells
                // Bit layout: 0=UL, 1=U, 2=UR, 3=L, 4=R, 5=DL, 6=D, 7=DR
                if y > 0 {
                    if x > 0          { patterns[(y-1)*width + (x-1)] |= (bit << 7) }  // I am DR of (y-1,x-1)
                                        patterns[(y-1)*width + x]     |= (bit << 6)    // I am D of (y-1,x)
                    if x < width - 1  { patterns[(y-1)*width + (x+1)] |= (bit << 5) }  // I am DL of (y-1,x+1)
                }
                if x > 0             { patterns[y*width + (x-1)]     |= (bit << 4) }  // I am R of (y,x-1)
                if x < width - 1     { patterns[y*width + (x+1)]     |= (bit << 3) }  // I am L of (y,x+1)
                if y < height - 1 {
                    if x > 0          { patterns[(y+1)*width + (x-1)] |= (bit << 2) }  // I am UR of (y+1,x-1)
                                        patterns[(y+1)*width + x]     |= (bit << 1)    // I am U of (y+1,x)
                    if x < width - 1  { patterns[(y+1)*width + (x+1)] |= (bit << 0) }  // I am UL of (y+1,x+1)
                }
            }
        }

        return patterns
    }
}

// MARK: - Performance Timing

/// Simple high-resolution timer for benchmarking pipeline stages.
struct PipelineTimer: Sendable {
    struct StageTime: Sendable {
        let stage: String
        let seconds: Double
    }

    private let stages: [StageTime]

    init() { stages = [] }
    private init(stages: [StageTime]) { self.stages = stages }

    func adding(stage: String, seconds: Double) -> PipelineTimer {
        PipelineTimer(stages: stages + [StageTime(stage: stage, seconds: seconds)])
    }

    var totalSeconds: Double { stages.reduce(0) { $0 + $1.seconds } }

    func summary() -> String {
        let total = totalSeconds
        return stages.map { s in
            let pct = total > 0 ? (s.seconds / total * 100) : 0
            return String(format: "  %-24s %8.3f ms (%5.1f%%)", s.stage, s.seconds * 1000, pct)
        }.joined(separator: "\n")
    }
}

/// Returns high-resolution time in seconds.
@inline(__always)
func highResolutionTime() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
}
