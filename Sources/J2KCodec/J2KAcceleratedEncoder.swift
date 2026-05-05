//
// J2KAcceleratedEncoder.swift
// J2KSwift
//
// Hardware-accelerated encoder pipeline optimizations.
// Uses vDSP/Accelerate on Apple, SIMD fallback on Linux/x86.
//

import Foundation
import J2KCore

#if canImport(Dispatch)
import Dispatch
#endif

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

    private static let alpha: Float = -1.586134342
    private static let beta: Float  = -0.05298011854
    private static let gamma: Float =  0.8829110762
    private static let delta: Float =  0.4435068522
    private static let K: Float     =  1.230174105

    /// Reusable workspace for 1D DWT to eliminate per-call heap allocations.
    ///
    /// Allocates even/odd buffers once and reuses them across all 1D transforms
    /// within a 2D DWT level. For a 1024×1024 image, this eliminates ~20K heap
    /// allocations per decomposition level.
    ///
    /// Uses Float (not Double) for 2× SIMD throughput and 2× cache efficiency.
    /// Float32's 23-bit mantissa is sufficient for 16-bit images through 5+ DWT levels.
    final class DWTWorkspace: @unchecked Sendable {
        var even: UnsafeMutableBufferPointer<Float>
        var odd: UnsafeMutableBufferPointer<Float>
        #if canImport(Accelerate)
        /// Scratch buffer for vDSP sum computation: even[i] + even[i+1] or odd shifted
        var sumBuf: UnsafeMutableBufferPointer<Float>
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
    final class DWTWorkspace53: @unchecked Sendable {
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

    /// Forward 1D CDF 9/7 lifting on a contiguous Float buffer (in-place, interleaved).
    ///
    /// Splits even/odd, applies 4 lifting steps, scales, then writes
    /// lowpass coefficients first followed by highpass.
    @inline(__always)
    static func forward97_1D(
        _ input: UnsafePointer<Float>,
        _ output: UnsafeMutablePointer<Float>,
        count n: Int
    ) {
        guard n >= 2 else {
            if n == 1 { output[0] = input[0] }
            return
        }

        let lowCount  = (n + 1) / 2
        let highCount = n / 2

        // Split into even (lowpass) and odd (highpass)
        var even = [Float](repeating: 0, count: lowCount)
        var odd  = [Float](repeating: 0, count: highCount)

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
            vDSP_vsmul(buf.baseAddress!, 1, &invK, buf.baseAddress!, 1, vDSP_Length(lowCount))
        }
        odd.withUnsafeMutableBufferPointer { buf in
            vDSP_vsmul(buf.baseAddress!, 1, &kVal, buf.baseAddress!, 1, vDSP_Length(highCount))
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
        _ input: UnsafePointer<Float>,
        _ output: UnsafeMutablePointer<Float>,
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

        // Deinterleave input → even/odd using BLAS gather (vld2 NEON under the hood)
        #if canImport(Accelerate)
        cblas_scopy(Int32(lowCount),  input,     2, evenPtr, 1)
        cblas_scopy(Int32(highCount), input + 1, 2, oddPtr,  1)
        #else
        for i in 0..<lowCount  { evenPtr[i] = input[i &* 2] }
        for i in 0..<highCount { oddPtr[i]  = input[i &* 2 &+ 1] }
        #endif

        // 4 lifting steps with vDSP vectorization
        #if canImport(Accelerate)
        // For small signals (< 32 samples), scalar lifting is faster than
        // 10 vDSP function calls (~200ns overhead each). At 5 DWT levels,
        // the deepest subbands have n=8..16 where this saves ~1.5μs/call.
        if n < 32 {
            liftPredictRaw(oddPtr, evenPtr, coeff: alpha, oddCount: highCount, evenCount: lowCount)
            liftUpdateRaw(evenPtr, oddPtr, coeff: beta, evenCount: lowCount, oddCount: highCount)
            liftPredictRaw(oddPtr, evenPtr, coeff: gamma, oddCount: highCount, evenCount: lowCount)
            liftUpdateRaw(evenPtr, oddPtr, coeff: delta, evenCount: lowCount, oddCount: highCount)

            // Fuse scale + output write: eliminates separate in-place scale + memcpy
            let invK: Float = 1.0 / K
            for i in 0..<lowCount  { output[i] = evenPtr[i] * invK }
            for i in 0..<highCount { output[lowCount &+ i] = oddPtr[i] * K }
            return
        } else {
        let scratchPtr = ws.sumBuf.baseAddress!

        // Predict 1: odd[i] += alpha * (even[i] + even[i+1])
        if highCount > 1 {
            // Interior: sum = even[0..<highCount-1] + even[1..<highCount]
            vDSP_vadd(evenPtr, 1, evenPtr + 1, 1, scratchPtr, 1, vDSP_Length(highCount - 1))
            // odd[0..<highCount-1] += alpha * sum
            var a = alpha
            vDSP_vsma(scratchPtr, 1, &a, oddPtr, 1, oddPtr, 1, vDSP_Length(highCount - 1))
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
                vDSP_vadd(oddPtr, 1, oddPtr + 1, 1, scratchPtr, 1, vDSP_Length(interiorCount))
                var b = beta
                vDSP_vsma(scratchPtr, 1, &b, evenPtr + 1, 1, evenPtr + 1, 1, vDSP_Length(interiorCount))
            }
        }
        // Boundaries
        do {
            let right0: Float = highCount > 0 ? oddPtr[0] : 0.0
            evenPtr[0] += beta * (right0 + right0) // odd[-1] mirrors to odd[0]
            if lowCount > 1 {
                let leftN: Float = highCount > 0 ? oddPtr[min(lowCount - 2, highCount - 1)] : 0.0
                let rightN: Float = highCount > 0 ? oddPtr[min(lowCount - 1, highCount - 1)] : 0.0
                evenPtr[lowCount - 1] += beta * (leftN + rightN)
            }
        }

        // Predict 2: odd[i] += gamma * (even[i] + even[i+1])
        if highCount > 1 {
            vDSP_vadd(evenPtr, 1, evenPtr + 1, 1, scratchPtr, 1, vDSP_Length(highCount - 1))
            var g = gamma
            vDSP_vsma(scratchPtr, 1, &g, oddPtr, 1, oddPtr, 1, vDSP_Length(highCount - 1))
        }
        if highCount > 0 {
            let rightIdx = min(highCount, lowCount - 1)
            oddPtr[highCount - 1] += gamma * (evenPtr[highCount - 1] + evenPtr[rightIdx])
        }

        // Update 2: even[i] += delta * (odd[i-1] + odd[i])
        if lowCount > 2 {
            let interiorCount = min(lowCount - 2, highCount - 1)
            if interiorCount > 0 {
                vDSP_vadd(oddPtr, 1, oddPtr + 1, 1, scratchPtr, 1, vDSP_Length(interiorCount))
                var d = delta
                vDSP_vsma(scratchPtr, 1, &d, evenPtr + 1, 1, evenPtr + 1, 1, vDSP_Length(interiorCount))
            }
        }
        do {
            let right0: Float = highCount > 0 ? oddPtr[0] : 0.0
            evenPtr[0] += delta * (right0 + right0)
            if lowCount > 1 {
                let leftN: Float = highCount > 0 ? oddPtr[min(lowCount - 2, highCount - 1)] : 0.0
                let rightN: Float = highCount > 0 ? oddPtr[min(lowCount - 1, highCount - 1)] : 0.0
                evenPtr[lowCount - 1] += delta * (leftN + rightN)
            }
        }

        // Fuse scale + output write: vDSP_vsmul reads from workspace, writes to output
        var invK: Float = 1.0 / K
        var kVal = K
        vDSP_vsmul(evenPtr, 1, &invK, output, 1, vDSP_Length(lowCount))
        vDSP_vsmul(oddPtr, 1, &kVal, output + lowCount, 1, vDSP_Length(highCount))

        } // end else (n >= 32 vDSP path)
        #else
        // Scalar fallback: identical to existing lifting
        liftPredictRaw(oddPtr, evenPtr, coeff: alpha, oddCount: highCount, evenCount: lowCount)
        liftUpdateRaw(evenPtr, oddPtr, coeff: beta, evenCount: lowCount, oddCount: highCount)
        liftPredictRaw(oddPtr, evenPtr, coeff: gamma, oddCount: highCount, evenCount: lowCount)
        liftUpdateRaw(evenPtr, oddPtr, coeff: delta, evenCount: lowCount, oddCount: highCount)

        // Fuse scale + output write: eliminates separate in-place scale + memcpy
        let invK: Float = 1.0 / K
        for i in 0..<lowCount  { output[i] = evenPtr[i] * invK }
        for i in 0..<highCount { output[lowCount + i] = oddPtr[i] * K }
        #endif
    }

    /// Raw pointer predict step (non-Accelerate fallback).
    @inline(__always)
    private static func liftPredictRaw(
        _ odd: UnsafeMutablePointer<Float>,
        _ even: UnsafePointer<Float>,
        coeff: Float, oddCount: Int, evenCount: Int
    ) {
        for i in 0..<oddCount {
            let right = (i + 1 < evenCount) ? even[i + 1] : even[evenCount - 1]
            odd[i] += coeff * (even[i] + right)
        }
    }

    /// Raw pointer update step (non-Accelerate fallback).
    @inline(__always)
    private static func liftUpdateRaw(
        _ even: UnsafeMutablePointer<Float>,
        _ odd: UnsafePointer<Float>,
        coeff: Float, evenCount: Int, oddCount: Int
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
        _ odd: inout [Float], _ even: [Float],
        coeff: Float, oddCount: Int, evenCount: Int
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
        _ even: inout [Float], _ odd: [Float],
        coeff: Float, evenCount: Int, oddCount: Int
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
        data: [Float], width: Int, height: Int
    ) async -> (ll: [Float], lh: [Float], hl: [Float], hh: [Float],
          llW: Int, llH: Int, lhW: Int, lhH: Int,
          hlW: Int, hlH: Int, hhW: Int, hhH: Int)
    {
        let colLowH  = (height + 1) / 2
        let colHighH = height / 2
        let rowLowW  = (width + 1) / 2
        let rowHighW = width / 2

        // --- Column pass (vertical): strip-mined with column-major layout ---
        // Transpose strips of adjacent columns into column-major format so
        // each column's data is contiguous in memory. This eliminates the
        // stride-N scatter/gather pattern that causes L1 cache misses.
        //
        // For images ≥ 256 pixels wide, parallelize across column strips:
        // each strip operates on disjoint memory, so no synchronization needed.
        var colResult = [Float](repeating: 0, count: width * height)
        let colStripWidth = 8
        let numStrips = (width + colStripWidth - 1) / colStripWidth
        // Use parallel column pass only when there is enough work to amortise
        // GCD dispatch overhead (~50 µs) and stripWorkspaces allocation.
        // Threshold: at least 8 strips (width ≥ 64) and height > 32.
        let useParallelColumns = numStrips >= 8 && height > 32

        #if canImport(Dispatch)
        if useParallelColumns {
            data.withUnsafeBufferPointer { srcBuf in
                colResult.withUnsafeMutableBufferPointer { dBuf in
                    let src = srcBuf.baseAddress!
                    let dst = dBuf.baseAddress!
                    let stripBufSize = colStripWidth * height
                    let allStripIn = UnsafeMutablePointer<Float>.allocate(capacity: numStrips * stripBufSize)
                    let allStripOut = UnsafeMutablePointer<Float>.allocate(capacity: numStrips * stripBufSize)
                    let stripWorkspaces = (0..<numStrips).map { _ in DWTWorkspace(maxSignalLength: height) }
                    defer {
                        allStripIn.deallocate()
                        allStripOut.deallocate()
                    }

                    DispatchQueue.concurrentPerform(iterations: numStrips) { stripIdx in
                        let ws = stripWorkspaces[stripIdx]
                        let colStrip = stripIdx * colStripWidth
                        let cols = min(colStripWidth, width - colStrip)
                        let stripIn = allStripIn + stripIdx * stripBufSize
                        let stripOut = allStripOut + stripIdx * stripBufSize

                        for row in 0..<height {
                            let srcRow = src + row * width + colStrip
                            for c in 0..<cols {
                                stripIn[c * height + row] = srcRow[c]
                            }
                        }

                        for c in 0..<cols {
                            forward97_1D(stripIn + c * height, stripOut + c * height, count: height, workspace: ws)
                        }

                        for row in 0..<height {
                            let dstRow = dst + row * width + colStrip
                            for c in 0..<cols {
                                dstRow[c] = stripOut[c * height + row]
                            }
                        }
                    }
                }
            }
        } else {
            let colWs = DWTWorkspace(maxSignalLength: height)
            data.withUnsafeBufferPointer { srcBuf in
                colResult.withUnsafeMutableBufferPointer { dBuf in
                    let src = srcBuf.baseAddress!
                    let dst = dBuf.baseAddress!
                    let stripBufSize = colStripWidth * height
                    let stripIn = UnsafeMutablePointer<Float>.allocate(capacity: stripBufSize)
                    let stripOut = UnsafeMutablePointer<Float>.allocate(capacity: stripBufSize)
                    defer {
                        stripIn.deallocate()
                        stripOut.deallocate()
                    }

                    for colStrip in stride(from: 0, to: width, by: colStripWidth) {
                        let cols = min(colStripWidth, width - colStrip)

                        for row in 0..<height {
                            let srcRow = src + row * width + colStrip
                            for c in 0..<cols {
                                stripIn[c * height + row] = srcRow[c]
                            }
                        }

                        for c in 0..<cols {
                            forward97_1D(stripIn + c * height, stripOut + c * height, count: height, workspace: colWs)
                        }

                        for row in 0..<height {
                            let dstRow = dst + row * width + colStrip
                            for c in 0..<cols {
                                dstRow[c] = stripOut[c * height + row]
                            }
                        }
                    }
                }
            }
        }
        #else
        let colWs = DWTWorkspace(maxSignalLength: height)
        data.withUnsafeBufferPointer { srcBuf in
            colResult.withUnsafeMutableBufferPointer { dBuf in
                let src = srcBuf.baseAddress!
                let dst = dBuf.baseAddress!
                let stripBufSize = colStripWidth * height
                let stripIn = UnsafeMutablePointer<Float>.allocate(capacity: stripBufSize)
                let stripOut = UnsafeMutablePointer<Float>.allocate(capacity: stripBufSize)
                let colOut = UnsafeMutablePointer<Float>.allocate(capacity: height)
                defer {
                    stripIn.deallocate()
                    stripOut.deallocate()
                    colOut.deallocate()
                }

                for colStrip in stride(from: 0, to: width, by: colStripWidth) {
                    let cols = min(colStripWidth, width - colStrip)

                    for row in 0..<height {
                        let srcRow = src + row * width + colStrip
                        for c in 0..<cols {
                            stripIn[c * height + row] = srcRow[c]
                        }
                    }

                    for c in 0..<cols {
                        forward97_1D(stripIn + c * height, colOut, count: height, workspace: colWs)
                        memcpy(stripOut + c * height, colOut, height * MemoryLayout<Float>.size)
                    }

                    for row in 0..<height {
                        let dstRow = dst + row * width + colStrip
                        for c in 0..<cols {
                            dstRow[c] = stripOut[c * height + row]
                        }
                    }
                }
            }
        }
        #endif

        // --- Row pass (horizontal): workspace-based 1D DWT ---
        let llH = colLowH
        let lhH = colHighH
        let hlH = colLowH
        let hhH = colHighH

        var ll = [Float](repeating: 0, count: rowLowW * colLowH)
        var hl = [Float](repeating: 0, count: rowHighW * colLowH)
        var lh = [Float](repeating: 0, count: rowLowW * colHighH)
        var hh = [Float](repeating: 0, count: rowHighW * colHighH)
        let totalRows = colLowH + colHighH
        let useParallelRows = width >= 128 && totalRows >= 128

        colResult.withUnsafeBufferPointer { srcBuf in
            let src = srcBuf.baseAddress!

            #if canImport(Dispatch)
            if useParallelRows {
                ll.withUnsafeMutableBufferPointer { llBuf in
                    hl.withUnsafeMutableBufferPointer { hlBuf in
                        lh.withUnsafeMutableBufferPointer { lhBuf in
                            hh.withUnsafeMutableBufferPointer { hhBuf in
                                let llPtr = llBuf.baseAddress!
                                let hlPtr = hlBuf.baseAddress!
                                let lhPtr = lhBuf.baseAddress!
                                let hhPtr = hhBuf.baseAddress!
                                let coreCount = ProcessInfo.processInfo.activeProcessorCount
                                let chunkCount = max(1, min(totalRows, coreCount * 2))
                                let chunkSize = max(1, (totalRows + chunkCount - 1) / chunkCount)

                                DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
                                    let startRow = chunkIndex * chunkSize
                                    let endRow = min(startRow + chunkSize, totalRows)
                                    guard startRow < endRow else { return }

                                    let localWs = DWTWorkspace(maxSignalLength: width)
                                    var rowOut = [Float](repeating: 0, count: width)
                                    rowOut.withUnsafeMutableBufferPointer { outBuf in
                                        let outPtr = outBuf.baseAddress!
                                        for srcRow in startRow..<endRow {
                                            forward97_1D(src + srcRow * width, outPtr, count: width, workspace: localWs)
                                            if srcRow < colLowH {
                                                memcpy(llPtr + srcRow * rowLowW, outPtr, rowLowW * MemoryLayout<Float>.size)
                                                memcpy(hlPtr + srcRow * rowHighW, outPtr + rowLowW, rowHighW * MemoryLayout<Float>.size)
                                            } else {
                                                let dstRow = srcRow - colLowH
                                                memcpy(lhPtr + dstRow * rowLowW, outPtr, rowLowW * MemoryLayout<Float>.size)
                                                memcpy(hhPtr + dstRow * rowHighW, outPtr + rowLowW, rowHighW * MemoryLayout<Float>.size)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                let rowWs = DWTWorkspace(maxSignalLength: width)
                var rowOut = [Float](repeating: 0, count: width)

                // Process low-column rows → LL, HL using memcpy for contiguous scatter
                for row in 0..<colLowH {
                    rowOut.withUnsafeMutableBufferPointer { outBuf in
                        forward97_1D(src + row * width, outBuf.baseAddress!, count: width, workspace: rowWs)
                    }
                    rowOut.withUnsafeBufferPointer { roBuf in
                        ll.withUnsafeMutableBufferPointer { llBuf in
                            memcpy(llBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Float>.size)
                        }
                        hl.withUnsafeMutableBufferPointer { hlBuf in
                            memcpy(hlBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Float>.size)
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
                            memcpy(lhBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Float>.size)
                        }
                        hh.withUnsafeMutableBufferPointer { hhBuf in
                            memcpy(hhBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Float>.size)
                        }
                    }
                }
            }
            #else
            let rowWs = DWTWorkspace(maxSignalLength: width)
            var rowOut = [Float](repeating: 0, count: width)

            // Process low-column rows → LL, HL using memcpy for contiguous scatter
            for row in 0..<colLowH {
                rowOut.withUnsafeMutableBufferPointer { outBuf in
                    forward97_1D(src + row * width, outBuf.baseAddress!, count: width, workspace: rowWs)
                }
                rowOut.withUnsafeBufferPointer { roBuf in
                    ll.withUnsafeMutableBufferPointer { llBuf in
                        memcpy(llBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Float>.size)
                    }
                    hl.withUnsafeMutableBufferPointer { hlBuf in
                        memcpy(hlBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Float>.size)
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
                        memcpy(lhBuf.baseAddress! + row * rowLowW, roBuf.baseAddress!, rowLowW * MemoryLayout<Float>.size)
                    }
                    hh.withUnsafeMutableBufferPointer { hhBuf in
                        memcpy(hhBuf.baseAddress! + row * rowHighW, roBuf.baseAddress! + rowLowW, rowHighW * MemoryLayout<Float>.size)
                    }
                }
            }
            #endif
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
        let lh: [Float]
        let hl: [Float]
        let hh: [Float]
        let lhW: Int, lhH: Int
        let hlW: Int, hlH: Int
        let hhW: Int, hhH: Int
    }

    struct DecompositionResult {
        let levels: [LevelResult]
        let coarsestLL: [Float]
        let llW: Int
        let llH: Int
    }

    static func forwardDecomposition(
        data: [Float], width: Int, height: Int, levels: Int
    ) async -> DecompositionResult {
        var currentData = data
        var currentW = width
        var currentH = height
        var levelResults: [LevelResult] = []

        for _ in 0..<levels {
            guard currentW >= 2 && currentH >= 2 else { break }

            let r = await forward2D(data: currentData, width: currentW, height: currentH)

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

    /// v6-alpha3 — parity-aware forward 1D 5/3 reversible DWT.
    ///
    /// Same arithmetic as the workspace variant below, generalised
    /// over the **tile-component image-coordinate origin** in this
    /// axis (`u`). The JPEG 2000 5/3 reversible DWT places
    /// low-pass samples at image-even positions and high-pass at
    /// image-odd; for tiles whose image-coordinate origin has odd
    /// parity, the local-index-to-band mapping flips and the
    /// symmetric-extension boundary cases reflect over a different
    /// axis. This is the "tile-component-origin parity" gotcha that
    /// made v5.39 M4's wrap-and-stitch multi-tile path fail external
    /// cross-decode for tile origins that aren't aligned to
    /// `2^decompositionLevels`.
    ///
    /// When `u == 0` (or any even `u`) the output is bit-identical
    /// to the no-origin overload — this is verified by
    /// `Tests/J2KCodecTests/HTDWTParityAwarenessTests.swift`.
    ///
    /// **Reference**: ISO/IEC 15444-1 Annex F.4.4 (1-D forward DWT)
    /// and F.4.8.1.2 (5/3 reversible filter). Symmetric whole-sample
    /// mirror reflection at tile boundaries (mirror axis at the
    /// boundary sample, not at half-step offset).
    static func forward53_1D(
        _ input: UnsafePointer<Int32>,
        _ output: UnsafeMutablePointer<Int32>,
        count n: Int,
        uOrigin u: Int,
        workspace ws: DWTWorkspace53
    ) {
        guard n >= 2 else {
            if n == 1 { output[0] = input[0] }
            return
        }
        // Even-origin path is bit-identical to the no-origin
        // overload, so just route to it. This both saves code and
        // guarantees zero regression on single-tile encodes.
        if (u & 1) == 0 {
            forward53_1D(input, output, count: n, workspace: ws)
            return
        }

        // Odd-origin path. Image-coord parity flips local-vs-band
        // mapping:
        //   local even index → image-odd position → H band source
        //   local odd index  → image-even position → L band source
        // and the band counts swap relative to the even-origin case:
        //   lowCount  = floor(n/2)   (was ceil(n/2))
        //   highCount = ceil(n/2)    (was floor(n/2))
        let lowCount  = n / 2
        let highCount = n - lowCount
        let evenPtr = ws.even.baseAddress!  // L band coefficients
        let oddPtr  = ws.odd.baseAddress!   // H band coefficients

        // Gather: L from local-odd, H from local-even.
        for i in 0..<lowCount  { evenPtr[i] = input[i &* 2 &+ 1] }
        for i in 0..<highCount { oddPtr[i]  = input[i &* 2] }

        // Predict (compute H from L neighbours):
        //   H_band[i] = X_image[2k+1] - (X_image[2k] + X_image[2k+2]) / 2
        // For odd origin, H_band[0] is the left-most sample in the
        // tile (image-odd at position u). Its left neighbour
        // X_image[u-1] mirrors to X_image[u+1] (= L_band[0]); right
        // neighbour X_image[u+1] is also L_band[0]. So H_band[0]
        // uses L_band[0] for BOTH neighbours.
        // H_band[i] for 1 ≤ i < lowCount uses L_band[i-1] and L_band[i].
        // H_band[lowCount] (only when highCount > lowCount, i.e.,
        // n is odd) is at the right edge: both neighbours mirror to
        // L_band[lowCount-1].
        if highCount > 0 {
            // Left mirror: H[0] -= L[0] (≡ -((L[0]+L[0]) >> 1))
            oddPtr[0] = oddPtr[0] &- evenPtr[0]
        }
        let predictInteriorEnd = min(highCount, lowCount)
        for i in 1..<predictInteriorEnd {
            oddPtr[i] = oddPtr[i] &- ((evenPtr[i &- 1] &+ evenPtr[i]) >> 1)
        }
        if highCount > lowCount {
            // Right mirror at tile edge — n odd, oddOrigin.
            oddPtr[lowCount] = oddPtr[lowCount] &- evenPtr[lowCount - 1]
        }

        // Update (compute L from H neighbours):
        //   L_band[i] = X_image[2k] + (H_left + H_right + 2) / 4
        // For odd origin, L_band[0] is at image position u+1; its
        // left H neighbour is at image u (= H_band[0]) and right H
        // neighbour at image u+2 (= H_band[1]). Both exist (no left
        // mirror at i=0!) — that's the qualitative difference from
        // the even-origin case.
        // For L_band[i] generally, neighbours are H_band[i] (left)
        // and H_band[i+1] (right). Right boundary mirror when
        // i+1 ≥ highCount: oddPtr[highCount-1].
        for i in 0..<lowCount {
            let leftH  = oddPtr[i]
            let rightH = (i &+ 1 < highCount) ? oddPtr[i &+ 1] : oddPtr[highCount &- 1]
            evenPtr[i] = evenPtr[i] &+ ((leftH &+ rightH &+ 2) >> 2)
        }

        memcpy(output, evenPtr, lowCount * MemoryLayout<Int32>.size)
        memcpy(output + lowCount, oddPtr, highCount * MemoryLayout<Int32>.size)
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

        // v5.38 M5: split the lifting loops into a branchless bulk
        // body + a tiny scalar tail. The bulk body has no per-iter
        // conditional (predictable stride access on contiguous Int32
        // pointers), which lets LLVM's loop vectoriser emit NEON
        // vaddq_s32/vshrq_n_s32 sequences. Boundary cases fall into
        // the post-bulk scalar handlers.
        //
        // For predict (`d[n] = odd[n] - (even[n] + even[n+1]) >> 1`)
        // the conditional `i + 1 < lowCount` is true for every
        // `i in 0..<highCount` except the last index when
        // `highCount == lowCount` (i.e., when `n` is even).

        // Predict bulk: rightmost safe i is the largest where
        // i+1 < lowCount, i.e., i < lowCount - 1. So predictBulk =
        // min(highCount, lowCount - 1) = highCount when n is odd,
        // highCount - 1 when n is even.
        let predictBulk = min(highCount, lowCount - 1)
        for i in 0..<predictBulk {
            oddPtr[i] = oddPtr[i] &- ((evenPtr[i] &+ evenPtr[i &+ 1]) >> 1)
        }
        if predictBulk < highCount {
            let i = predictBulk
            oddPtr[i] = oddPtr[i] &- ((evenPtr[i] &+ evenPtr[lowCount - 1]) >> 1)
        }

        // Update: `s[n] = even[n] + (d[n-1] + d[n] + 2) >> 2`.
        // Both ends have boundary conditions:
        //   i == 0: left = oddPtr[0] (mirror)
        //   i == lowCount-1: right = oddPtr[highCount-1] when
        //                    i >= highCount; otherwise oddPtr[i].
        // The interior is i in 1..<min(highCount, lowCount). With
        // `n` even (highCount == lowCount), interior is 1..<highCount;
        // i == lowCount-1 == highCount-1 is the right boundary.
        // With `n` odd (lowCount == highCount + 1), interior is
        // 1..<highCount; i == lowCount-1 is the right boundary.
        if lowCount > 0 {
            evenPtr[0] = evenPtr[0] &+ ((oddPtr[0] &+ oddPtr[0] &+ 2) >> 2)
        }
        let updateBulkEnd = min(lowCount, highCount)
        for i in 1..<updateBulkEnd {
            evenPtr[i] = evenPtr[i] &+ ((oddPtr[i &- 1] &+ oddPtr[i] &+ 2) >> 2)
        }
        // Tail when lowCount > highCount (n odd) — i == lowCount-1
        // uses oddPtr[highCount-1] for the right value.
        if updateBulkEnd < lowCount {
            let i = lowCount - 1
            let left = (i > 0) ? oddPtr[i &- 1] : oddPtr[0]
            evenPtr[i] = evenPtr[i] &+ ((left &+ oddPtr[highCount - 1] &+ 2) >> 2)
        }

        memcpy(output, evenPtr, lowCount * MemoryLayout<Int32>.size)
        memcpy(output + lowCount, oddPtr, highCount * MemoryLayout<Int32>.size)
    }

    /// Forward 2D 5/3 on flat Int32 buffer using preallocated workspaces.
    static func forward2D_53(
        data: [Int32], width: Int, height: Int
    ) async -> (ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32],
          llW: Int, llH: Int, lhW: Int, lhH: Int,
          hlW: Int, hlH: Int, hhW: Int, hhH: Int)
    {
        let colLowH  = (height + 1) / 2
        let colHighH = height / 2
        let rowLowW  = (width + 1) / 2
        let rowHighW = width / 2

        // Preallocate row workspace
        let rowWs = DWTWorkspace53(maxSignalLength: width)

        var colResult = [Int32](repeating: 0, count: width * height)
        let colStripWidth = 8
        let numStrips = (width + colStripWidth - 1) / colStripWidth
        // Use parallel column pass only when there is enough work to amortise
        // task dispatch overhead and per-strip workspace allocations.
        // Threshold: at least 8 strips (width ≥ 64) and height > 32.
        // This prevents the parallel path from activating for fine decomposition
        // levels (e.g. 32×32 at level 3 of a 256×256 image) where overhead
        // dominates the actual wavelet work.
        let useParallelColumns = numStrips >= 8 && height > 32

        if useParallelColumns {
            // Allocate source copy and destination buffer for pointer-based parallel access
            let srcBuf = UnsafeMutablePointer<Int32>.allocate(capacity: width * height)
            let dstBuf = UnsafeMutablePointer<Int32>.allocate(capacity: width * height)
            data.withUnsafeBufferPointer { buf in
                srcBuf.initialize(from: buf.baseAddress!, count: width * height)
            }
            defer {
                srcBuf.deallocate()
                dstBuf.deallocate()
            }

            // Pre-allocate all strip buffers to avoid per-strip heap allocations.
            let stripBufSize = colStripWidth * height
            let allStripIn = UnsafeMutablePointer<Int32>.allocate(capacity: numStrips * stripBufSize)
            let allStripOut = UnsafeMutablePointer<Int32>.allocate(capacity: numStrips * stripBufSize)
            let stripWorkspaces = (0..<numStrips).map { _ in DWTWorkspace53(maxSignalLength: height) }
            defer {
                allStripIn.deallocate()
                allStripOut.deallocate()
            }

            // Parallel column pass: each strip indexes into pre-allocated buffers
            let safeSrc = SendablePointer(srcBuf)
            let safeDst = SendablePointer(dstBuf)
            let safeStripIn = SendablePointer(allStripIn)
            let safeStripOut = SendablePointer(allStripOut)
            await withTaskGroup(of: Void.self) { group in
                for stripIdx in 0..<numStrips {
                    let ws = stripWorkspaces[stripIdx]
                    group.addTask { @Sendable in
                        let src = safeSrc.pointer
                        let dst = safeDst.pointer
                        let allStripIn = safeStripIn.pointer
                        let allStripOut = safeStripOut.pointer
                        let colStrip = stripIdx * colStripWidth
                        let cols = min(colStripWidth, width - colStrip)
                        let stripIn = allStripIn + stripIdx * stripBufSize
                        let stripOut = allStripOut + stripIdx * stripBufSize

                        for row in 0..<height {
                            let srcRow = src + row * width + colStrip
                            for c in 0..<cols {
                                stripIn[c * height + row] = srcRow[c]
                            }
                        }

                        for c in 0..<cols {
                            forward53_1D(stripIn + c * height, stripOut + c * height, count: height, workspace: ws)
                        }

                        for row in 0..<height {
                            let dstRow = dst + row * width + colStrip
                            for c in 0..<cols {
                                dstRow[c] = stripOut[c * height + row]
                            }
                        }
                    }
                }
            }

            // Copy results back to colResult
            colResult.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.initialize(from: dstBuf, count: width * height)
            }
        } else {
            // Sequential path for small images
            let colWs = DWTWorkspace53(maxSignalLength: height)
            data.withUnsafeBufferPointer { srcBuf in
                colResult.withUnsafeMutableBufferPointer { dstBuf in
                    let src = srcBuf.baseAddress!
                    let dst = dstBuf.baseAddress!
                    let stripBufSize = colStripWidth * height
                    let stripIn = UnsafeMutablePointer<Int32>.allocate(capacity: stripBufSize)
                    let stripOut = UnsafeMutablePointer<Int32>.allocate(capacity: stripBufSize)
                    defer {
                        stripIn.deallocate()
                        stripOut.deallocate()
                    }

                    for colStrip in stride(from: 0, to: width, by: colStripWidth) {
                        let cols = min(colStripWidth, width - colStrip)

                        for row in 0..<height {
                            let srcRow = src + row * width + colStrip
                            for c in 0..<cols {
                                stripIn[c * height + row] = srcRow[c]
                            }
                        }

                        for c in 0..<cols {
                            forward53_1D(stripIn + c * height, stripOut + c * height, count: height, workspace: colWs)
                        }

                        for row in 0..<height {
                            let dstRow = dst + row * width + colStrip
                            for c in 0..<cols {
                                dstRow[c] = stripOut[c * height + row]
                            }
                        }
                    }
                }
            }
        }

        var ll = [Int32](repeating: 0, count: rowLowW * colLowH)
        var hl = [Int32](repeating: 0, count: rowHighW * colLowH)
        var lh = [Int32](repeating: 0, count: rowLowW * colHighH)
        var hh = [Int32](repeating: 0, count: rowHighW * colHighH)

        // v5.39 M2: row-pass after the column pass is independent
        // per row (each row's forward 1D 5/3 only reads its own row of
        // `colResult` and writes its own row of ll/hl/lh/hh). Default
        // path stays sequential — bit-identical to v5.38. The
        // `dwt-row-parallel` opt-in mode dispatches the row work
        // across `maxConcurrency` worker tasks, each with its own
        // workspace, halving the wall-clock cost of this stage on
        // large fixtures (DX DWT ~32 ms → ~16 ms target).
        let useRowParallel = EncoderPipeline._htParallelMode == .dwtRowParallel

        if useRowParallel {
            // Pre-allocate per-task workspaces sized for the row pass
            // (workspace length = width). Tasks pick a workspace by
            // chunk index.
            let maxConcurrency = ProcessInfo.processInfo.processorCount
            let chunkLow = max(1, (colLowH + maxConcurrency - 1) / maxConcurrency)
            let chunkHigh = max(1, (colHighH + maxConcurrency - 1) / maxConcurrency)
            let lowChunks = stride(from: 0, to: colLowH, by: chunkLow).map {
                $0..<min($0 + chunkLow, colLowH)
            }
            let highChunks = stride(from: 0, to: colHighH, by: chunkHigh).map {
                $0..<min($0 + chunkHigh, colHighH)
            }

            // Each task needs its own (workspace, rowOut). They are
            // disjoint outputs (different row ranges) so no
            // synchronisation is needed beyond the pointer wrappers.
            let srcBuf = UnsafeMutablePointer<Int32>.allocate(capacity: width * height)
            let llBuf  = UnsafeMutablePointer<Int32>.allocate(capacity: rowLowW * colLowH)
            let hlBuf  = UnsafeMutablePointer<Int32>.allocate(capacity: rowHighW * colLowH)
            let lhBuf  = UnsafeMutablePointer<Int32>.allocate(capacity: rowLowW * colHighH)
            let hhBuf  = UnsafeMutablePointer<Int32>.allocate(capacity: rowHighW * colHighH)
            colResult.withUnsafeBufferPointer { src in
                srcBuf.initialize(from: src.baseAddress!, count: width * height)
            }
            defer {
                srcBuf.deallocate(); llBuf.deallocate(); hlBuf.deallocate()
                lhBuf.deallocate(); hhBuf.deallocate()
            }
            let safeSrc = SendablePointer(srcBuf)
            let safeLl  = SendablePointer(llBuf)
            let safeHl  = SendablePointer(hlBuf)
            let safeLh  = SendablePointer(lhBuf)
            let safeHh  = SendablePointer(hhBuf)

            await withTaskGroup(of: Void.self) { group in
                for range in lowChunks {
                    group.addTask { @Sendable in
                        let ws = DWTWorkspace53(maxSignalLength: width)
                        let rowOut = UnsafeMutablePointer<Int32>.allocate(capacity: width)
                        defer { rowOut.deallocate() }
                        let s = safeSrc.pointer
                        let l = safeLl.pointer
                        let h = safeHl.pointer
                        for row in range {
                            forward53_1D(s + row * width, rowOut, count: width, workspace: ws)
                            memcpy(l + row * rowLowW,  rowOut,             rowLowW * MemoryLayout<Int32>.size)
                            memcpy(h + row * rowHighW, rowOut + rowLowW,   rowHighW * MemoryLayout<Int32>.size)
                        }
                    }
                }
                for range in highChunks {
                    group.addTask { @Sendable in
                        let ws = DWTWorkspace53(maxSignalLength: width)
                        let rowOut = UnsafeMutablePointer<Int32>.allocate(capacity: width)
                        defer { rowOut.deallocate() }
                        let s = safeSrc.pointer
                        let lh = safeLh.pointer
                        let hh = safeHh.pointer
                        for row in range {
                            let srcRow = colLowH + row
                            forward53_1D(s + srcRow * width, rowOut, count: width, workspace: ws)
                            memcpy(lh + row * rowLowW,  rowOut,             rowLowW * MemoryLayout<Int32>.size)
                            memcpy(hh + row * rowHighW, rowOut + rowLowW,   rowHighW * MemoryLayout<Int32>.size)
                        }
                    }
                }
            }

            ll.withUnsafeMutableBufferPointer { $0.baseAddress!.initialize(from: llBuf, count: rowLowW * colLowH) }
            hl.withUnsafeMutableBufferPointer { $0.baseAddress!.initialize(from: hlBuf, count: rowHighW * colLowH) }
            lh.withUnsafeMutableBufferPointer { $0.baseAddress!.initialize(from: lhBuf, count: rowLowW * colHighH) }
            hh.withUnsafeMutableBufferPointer { $0.baseAddress!.initialize(from: hhBuf, count: rowHighW * colHighH) }
        } else {
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
    ) async -> Int32DecompositionResult {
        var currentData = data
        var currentW = width
        var currentH = height
        var levelResults: [Int32LevelResult] = []

        for _ in 0..<levels {
            guard currentW >= 2 && currentH >= 2 else { break }
            let r = await forward2D_53(data: currentData, width: currentW, height: currentH)
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
            return j2kClampedInt32(sign * mag.rounded(.down))
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
            return sign &* j2kClampedInt32(mag.rounded(.down))
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
