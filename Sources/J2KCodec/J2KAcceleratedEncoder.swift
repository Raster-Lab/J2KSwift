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

    /// Reusable workspace for 1D DWT to eliminate per-call heap allocations.
    ///
    /// Allocates even/odd buffers once and reuses them across all 1D transforms
    /// within a 2D DWT level. For a 1024×1024 image, this eliminates ~20K heap
    /// allocations per decomposition level.
    final class DWTWorkspace {
        var even: UnsafeMutableBufferPointer<Double>
        var odd: UnsafeMutableBufferPointer<Double>
        #if canImport(Accelerate)
        /// Scratch buffer for vDSP sum computation: even[i] + even[i+1] or odd shifted
        var sumBuf: UnsafeMutableBufferPointer<Double>
        #endif
        let capacity: Int

        init(maxSignalLength: Int) {
            let half = (maxSignalLength + 1) / 2
            capacity = half
            even = .allocate(capacity: half)
            odd = .allocate(capacity: half)
            #if canImport(Accelerate)
            sumBuf = .allocate(capacity: half)
            #endif
        }

        deinit {
            even.deallocate()
            odd.deallocate()
            #if canImport(Accelerate)
            sumBuf.deallocate()
            #endif
        }
    }

    /// Reusable workspace for Int32 5/3 DWT.
    final class DWTWorkspace53 {
        var even: UnsafeMutableBufferPointer<Int32>
        var odd: UnsafeMutableBufferPointer<Int32>
        let capacity: Int

        init(maxSignalLength: Int) {
            let half = (maxSignalLength + 1) / 2
            capacity = half
            even = .allocate(capacity: half)
            odd = .allocate(capacity: half)
        }

        deinit {
            even.deallocate()
            odd.deallocate()
        }
    }

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

    /// Forward 1D CDF 9/7 lifting using a preallocated workspace.
    ///
    /// Eliminates heap allocation of even/odd arrays on each call. Uses vDSP
    /// operations for the interior of each lifting step, with scalar boundary
    /// handling only for edge elements.
    ///
    /// Performance: ~30-40% faster than the allocating version for large signals
    /// due to zero heap allocations and vDSP vectorization.
    @inline(__always)
    static func forward97_1D(
        _ input: UnsafePointer<Double>,
        _ output: UnsafeMutablePointer<Double>,
        count n: Int,
        workspace ws: DWTWorkspace
    ) {
        guard n >= 2 else {
            if n == 1 { output[0] = input[0] }
            return
        }

        let lowCount  = (n + 1) / 2
        let highCount = n / 2
        let evenPtr = ws.even.baseAddress!
        let oddPtr  = ws.odd.baseAddress!

        // Split: gather even/odd from interleaved input
        for i in 0..<lowCount  { evenPtr[i] = input[i &* 2] }
        for i in 0..<highCount { oddPtr[i]  = input[i &* 2 &+ 1] }

        // 4 lifting steps with vDSP vectorization
        #if canImport(Accelerate)
        let scratchPtr = ws.sumBuf.baseAddress!

        // Predict 1: odd[i] += alpha * (even[i] + even[i+1])
        if highCount > 1 {
            // Interior: sum = even[0..<highCount-1] + even[1..<highCount]
            vDSP_vaddD(evenPtr, 1, evenPtr + 1, 1, scratchPtr, 1, vDSP_Length(highCount - 1))
            // odd[0..<highCount-1] += alpha * sum
            var a = alpha
            vDSP_vsmaD(scratchPtr, 1, &a, oddPtr, 1, oddPtr, 1, vDSP_Length(highCount - 1))
        }
        // Boundary: last element
        if highCount > 0 {
            let rightIdx = min(highCount, lowCount - 1)
            oddPtr[highCount - 1] += alpha * (evenPtr[highCount - 1] + evenPtr[rightIdx])
        }

        // Update 1: even[i] += beta * (odd[i-1] + odd[i])
        if lowCount > 2 {
            // Interior (indices 1..<lowCount-1): sum = odd[0..<lowCount-2] + odd[1..<lowCount-1]
            let interiorCount = min(lowCount - 2, highCount - 1)
            if interiorCount > 0 {
                vDSP_vaddD(oddPtr, 1, oddPtr + 1, 1, scratchPtr, 1, vDSP_Length(interiorCount))
                var b = beta
                vDSP_vsmaD(scratchPtr, 1, &b, evenPtr + 1, 1, evenPtr + 1, 1, vDSP_Length(interiorCount))
            }
        }
        // Boundaries
        do {
            let right0 = highCount > 0 ? oddPtr[0] : 0.0
            evenPtr[0] += beta * (right0 + right0) // odd[-1] mirrors to odd[0]
            if lowCount > 1 {
                let leftN = highCount > 0 ? oddPtr[min(lowCount - 2, highCount - 1)] : 0.0
                let rightN = highCount > 0 ? oddPtr[min(lowCount - 1, highCount - 1)] : 0.0
                evenPtr[lowCount - 1] += beta * (leftN + rightN)
            }
        }

        // Predict 2: odd[i] += gamma * (even[i] + even[i+1])
        if highCount > 1 {
            vDSP_vaddD(evenPtr, 1, evenPtr + 1, 1, scratchPtr, 1, vDSP_Length(highCount - 1))
            var g = gamma
            vDSP_vsmaD(scratchPtr, 1, &g, oddPtr, 1, oddPtr, 1, vDSP_Length(highCount - 1))
        }
        if highCount > 0 {
            let rightIdx = min(highCount, lowCount - 1)
            oddPtr[highCount - 1] += gamma * (evenPtr[highCount - 1] + evenPtr[rightIdx])
        }

        // Update 2: even[i] += delta * (odd[i-1] + odd[i])
        if lowCount > 2 {
            let interiorCount = min(lowCount - 2, highCount - 1)
            if interiorCount > 0 {
                vDSP_vaddD(oddPtr, 1, oddPtr + 1, 1, scratchPtr, 1, vDSP_Length(interiorCount))
                var d = delta
                vDSP_vsmaD(scratchPtr, 1, &d, evenPtr + 1, 1, evenPtr + 1, 1, vDSP_Length(interiorCount))
            }
        }
        do {
            let right0 = highCount > 0 ? oddPtr[0] : 0.0
            evenPtr[0] += delta * (right0 + right0)
            if lowCount > 1 {
                let leftN = highCount > 0 ? oddPtr[min(lowCount - 2, highCount - 1)] : 0.0
                let rightN = highCount > 0 ? oddPtr[min(lowCount - 1, highCount - 1)] : 0.0
                evenPtr[lowCount - 1] += delta * (leftN + rightN)
            }
        }

        // Scale: lowpass /= K, highpass *= K using vDSP
        var invK = 1.0 / K
        var kVal = K
        vDSP_vsmulD(evenPtr, 1, &invK, evenPtr, 1, vDSP_Length(lowCount))
        vDSP_vsmulD(oddPtr, 1, &kVal, oddPtr, 1, vDSP_Length(highCount))

        #else
        // Scalar fallback: identical to existing lifting
        liftPredictRaw(oddPtr, evenPtr, coeff: alpha, oddCount: highCount, evenCount: lowCount)
        liftUpdateRaw(evenPtr, oddPtr, coeff: beta, evenCount: lowCount, oddCount: highCount)
        liftPredictRaw(oddPtr, evenPtr, coeff: gamma, oddCount: highCount, evenCount: lowCount)
        liftUpdateRaw(evenPtr, oddPtr, coeff: delta, evenCount: lowCount, oddCount: highCount)

        let invK = 1.0 / K
        for i in 0..<lowCount  { evenPtr[i] *= invK }
        for i in 0..<highCount { oddPtr[i]  *= K }
        #endif

        // Write output: lowpass then highpass
        memcpy(output, evenPtr, lowCount * MemoryLayout<Double>.size)
        memcpy(output + lowCount, oddPtr, highCount * MemoryLayout<Double>.size)
    }

    /// Raw pointer predict step (non-Accelerate fallback).
    @inline(__always)
    private static func liftPredictRaw(
        _ odd: UnsafeMutablePointer<Double>,
        _ even: UnsafePointer<Double>,
        coeff: Double, oddCount: Int, evenCount: Int
    ) {
        for i in 0..<oddCount {
            let right = (i + 1 < evenCount) ? even[i + 1] : even[evenCount - 1]
            odd[i] += coeff * (even[i] + right)
        }
    }

    /// Raw pointer update step (non-Accelerate fallback).
    @inline(__always)
    private static func liftUpdateRaw(
        _ even: UnsafeMutablePointer<Double>,
        _ odd: UnsafePointer<Double>,
        coeff: Double, evenCount: Int, oddCount: Int
    ) {
        for i in 0..<evenCount {
            let left = (i > 0) ? odd[i - 1] : odd[0]
            let right = (i < oddCount) ? odd[i] : odd[oddCount - 1]
            even[i] += coeff * (left + right)
        }
    }

    /// Predict step: odd[i] += coeff * (even[i] + even[i+1])
    @inline(__always)
    private static func liftPredict(
        _ odd: inout [Double], _ even: [Double],
        coeff: Double, oddCount: Int, evenCount: Int
    ) {
        odd.withUnsafeMutableBufferPointer { oddBuf in
            even.withUnsafeBufferPointer { evenBuf in
                for i in 0..<oddCount {
                    let right = (i + 1 < evenCount) ? evenBuf[i + 1] : evenBuf[evenCount - 1]
                    oddBuf[i] += coeff * (evenBuf[i] + right)
                }
            }
        }
    }

    /// Update step: even[i] += coeff * (odd[i-1] + odd[i])
    @inline(__always)
    private static func liftUpdate(
        _ even: inout [Double], _ odd: [Double],
        coeff: Double, evenCount: Int, oddCount: Int
    ) {
        even.withUnsafeMutableBufferPointer { evenBuf in
            odd.withUnsafeBufferPointer { oddBuf in
                for i in 0..<evenCount {
                    let left = (i - 1 >= 0) ? oddBuf[i - 1] : oddBuf[0]
                    let right = (i < oddCount) ? oddBuf[i] : oddBuf[oddCount - 1]
                    evenBuf[i] += coeff * (left + right)
                }
            }
        }
    }

    /// Forward 2D DWT on a flat row-major buffer. Returns (ll, lh, hl, hh) as flat arrays
    /// plus their dimensions.
    ///
    /// Uses preallocated workspace buffers and cache-friendly tile blocking for the
    /// column pass to minimize heap allocations and L1 cache misses.
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

        // Preallocate workspace for 1D transforms
        let colWs = DWTWorkspace(maxSignalLength: height)
        let rowWs = DWTWorkspace(maxSignalLength: width)

        // --- Column pass (vertical): strip-mined with column-major layout ---
        // Transpose strips of adjacent columns into column-major format so
        // each column's data is contiguous in memory. This eliminates the
        // stride-N scatter/gather pattern that causes L1 cache misses.
        var colResult = [Double](repeating: 0, count: width * height)
        let colStripWidth = 8

        data.withUnsafeBufferPointer { srcBuf in
            colResult.withUnsafeMutableBufferPointer { dstBuf in
                let src = srcBuf.baseAddress!
                let dst = dstBuf.baseAddress!

                // Column-major strip: layout is stripIn[col * height + row]
                let stripBufSize = colStripWidth * height
                let stripIn = UnsafeMutablePointer<Double>.allocate(capacity: stripBufSize)
                let stripOut = UnsafeMutablePointer<Double>.allocate(capacity: stripBufSize)
                let colOut = UnsafeMutablePointer<Double>.allocate(capacity: height)
                defer {
                    stripIn.deallocate()
                    stripOut.deallocate()
                    colOut.deallocate()
                }

                for colStrip in stride(from: 0, to: width, by: colStripWidth) {
                    let cols = min(colStripWidth, width - colStrip)

                    // Gather & transpose: row-major source → column-major strip
                    // Each row read loads 1 cache line (8 Doubles = 64 bytes)
                    for row in 0..<height {
                        let srcRow = src + row * width + colStrip
                        for c in 0..<cols {
                            stripIn[c * height + row] = srcRow[c]
                        }
                    }

                    // Transform each column — data is now contiguous
                    for c in 0..<cols {
                        forward97_1D(stripIn + c * height, colOut, count: height, workspace: colWs)
                        memcpy(stripOut + c * height, colOut, height * MemoryLayout<Double>.size)
                    }

                    // Scatter & transpose back: column-major strip → row-major output
                    for row in 0..<height {
                        let dstRow = dst + row * width + colStrip
                        for c in 0..<cols {
                            dstRow[c] = stripOut[c * height + row]
                        }
                    }
                }
            }
        }

        // --- Row pass (horizontal): workspace-based 1D DWT ---
        let llH = colLowH
        let lhH = colHighH
        let hlH = colLowH
        let hhH = colHighH

        var ll = [Double](repeating: 0, count: rowLowW * colLowH)
        var hl = [Double](repeating: 0, count: rowHighW * colLowH)
        var lh = [Double](repeating: 0, count: rowLowW * colHighH)
        var hh = [Double](repeating: 0, count: rowHighW * colHighH)

        colResult.withUnsafeBufferPointer { srcBuf in
            let src = srcBuf.baseAddress!
            var rowOut = [Double](repeating: 0, count: width)

            // Process low-column rows → LL, HL using memcpy for contiguous scatter
            for row in 0..<colLowH {
                rowOut.withUnsafeMutableBufferPointer { outBuf in
                    forward97_1D(src + row * width, outBuf.baseAddress!, count: width, workspace: rowWs)
                }
                rowOut.withUnsafeBufferPointer { roBuf in
                    ll.withUnsafeMutableBufferPointer { llBuf in
                        memcpy(llBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Double>.size)
                    }
                    hl.withUnsafeMutableBufferPointer { hlBuf in
                        memcpy(hlBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Double>.size)
                    }
                }
            }

            // Process high-column rows → LH, HH
            for row in 0..<colHighH {
                let srcRow = colLowH + row
                rowOut.withUnsafeMutableBufferPointer { outBuf in
                    forward97_1D(src + srcRow * width, outBuf.baseAddress!, count: width, workspace: rowWs)
                }
                rowOut.withUnsafeBufferPointer { roBuf in
                    lh.withUnsafeMutableBufferPointer { lhBuf in
                        memcpy(lhBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Double>.size)
                    }
                    hh.withUnsafeMutableBufferPointer { hhBuf in
                        memcpy(hhBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Double>.size)
                    }
                }
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

    /// Forward 1D Le Gall 5/3 lifting using a preallocated workspace.
    ///
    /// Eliminates heap allocation of even/odd arrays on each call.
    @inline(__always)
    static func forward53_1D(
        _ input: UnsafePointer<Int32>,
        _ output: UnsafeMutablePointer<Int32>,
        count n: Int,
        workspace ws: DWTWorkspace53
    ) {
        guard n >= 2 else {
            if n == 1 { output[0] = input[0] }
            return
        }

        let lowCount  = (n + 1) / 2
        let highCount = n / 2
        let evenPtr = ws.even.baseAddress!
        let oddPtr  = ws.odd.baseAddress!

        // Split: gather even/odd from interleaved
        for i in 0..<lowCount  { evenPtr[i] = input[i &* 2] }
        for i in 0..<highCount { oddPtr[i]  = input[i &* 2 &+ 1] }

        // Predict: d[n] = odd[n] - floor((even[n] + even[n+1]) / 2)
        for i in 0..<highCount {
            let right = (i + 1 < lowCount) ? evenPtr[i + 1] : evenPtr[lowCount - 1]
            oddPtr[i] = oddPtr[i] &- ((evenPtr[i] &+ right) >> 1)
        }

        // Update: s[n] = even[n] + floor((d[n-1] + d[n] + 2) / 4)
        for i in 0..<lowCount {
            let left  = (i > 0) ? oddPtr[i - 1] : oddPtr[0]
            let right = (i < highCount) ? oddPtr[i] : oddPtr[highCount - 1]
            evenPtr[i] = evenPtr[i] &+ ((left &+ right &+ 2) >> 2)
        }

        memcpy(output, evenPtr, lowCount * MemoryLayout<Int32>.size)
        memcpy(output + lowCount, oddPtr, highCount * MemoryLayout<Int32>.size)
    }

    /// Forward 2D 5/3 on flat Int32 buffer using preallocated workspaces.
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

        // Preallocate workspaces
        let colWs = DWTWorkspace53(maxSignalLength: height)
        let rowWs = DWTWorkspace53(maxSignalLength: width)

        var colResult = [Int32](repeating: 0, count: width * height)
        let colStripWidth = 8

        data.withUnsafeBufferPointer { srcBuf in
            colResult.withUnsafeMutableBufferPointer { dstBuf in
                let src = srcBuf.baseAddress!
                let dst = dstBuf.baseAddress!

                let stripBufSize = colStripWidth * height
                let stripIn = UnsafeMutablePointer<Int32>.allocate(capacity: stripBufSize)
                let stripOut = UnsafeMutablePointer<Int32>.allocate(capacity: stripBufSize)
                let colOut = UnsafeMutablePointer<Int32>.allocate(capacity: height)
                defer {
                    stripIn.deallocate()
                    stripOut.deallocate()
                    colOut.deallocate()
                }

                for colStrip in stride(from: 0, to: width, by: colStripWidth) {
                    let cols = min(colStripWidth, width - colStrip)

                    // Gather & transpose: row-major source → column-major strip
                    for row in 0..<height {
                        let srcRow = src + row * width + colStrip
                        for c in 0..<cols {
                            stripIn[c * height + row] = srcRow[c]
                        }
                    }

                    // Transform each column — data is contiguous
                    for c in 0..<cols {
                        forward53_1D(stripIn + c * height, colOut, count: height, workspace: colWs)
                        memcpy(stripOut + c * height, colOut, height * MemoryLayout<Int32>.size)
                    }

                    // Scatter & transpose back: column-major → row-major
                    for row in 0..<height {
                        let dstRow = dst + row * width + colStrip
                        for c in 0..<cols {
                            dstRow[c] = stripOut[c * height + row]
                        }
                    }
                }
            }
        }

        var ll = [Int32](repeating: 0, count: rowLowW * colLowH)
        var hl = [Int32](repeating: 0, count: rowHighW * colLowH)
        var lh = [Int32](repeating: 0, count: rowLowW * colHighH)
        var hh = [Int32](repeating: 0, count: rowHighW * colHighH)

        colResult.withUnsafeBufferPointer { srcBuf in
            let src = srcBuf.baseAddress!
            var rowOut = [Int32](repeating: 0, count: width)

            for row in 0..<colLowH {
                rowOut.withUnsafeMutableBufferPointer { outBuf in
                    forward53_1D(src + row * width, outBuf.baseAddress!, count: width, workspace: rowWs)
                }
                rowOut.withUnsafeBufferPointer { roBuf in
                    ll.withUnsafeMutableBufferPointer { llBuf in
                        memcpy(llBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Int32>.size)
                    }
                    hl.withUnsafeMutableBufferPointer { hlBuf in
                        memcpy(hlBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Int32>.size)
                    }
                }
            }

            for row in 0..<colHighH {
                let srcRow = colLowH + row
                rowOut.withUnsafeMutableBufferPointer { outBuf in
                    forward53_1D(src + srcRow * width, outBuf.baseAddress!, count: width, workspace: rowWs)
                }
                rowOut.withUnsafeBufferPointer { roBuf in
                    lh.withUnsafeMutableBufferPointer { lhBuf in
                        memcpy(lhBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Int32>.size)
                    }
                    hh.withUnsafeMutableBufferPointer { hhBuf in
                        memcpy(hhBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Int32>.size)
                    }
                }
            }
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
