//
// J2KDWT1DOptimized.swift
// J2KSwift
//
// J2KDWT1DOptimized.swift
// J2KSwift
//
// Optimised lossless decoding path for reversible 5/3 filter
//

import Foundation
import J2KCore

#if canImport(Accelerate)
import Accelerate
#endif

/// A wrapper around `UnsafeMutablePointer` that conforms to `Sendable`.
///
/// Used to pass raw pointers into structured concurrency task closures
/// for known-disjoint parallel access patterns (e.g., chunked column/row
/// DWT lifting where each task operates on a non-overlapping slice).
///
/// - Important: Callers must guarantee disjoint access across tasks.
struct SendablePointer<T>: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<T>
    init(_ pointer: UnsafeMutablePointer<T>) {
        self.pointer = pointer
    }
}

/// Optimised 1D DWT operations for lossless (reversible 5/3) decoding.
///
/// This module provides optimised implementations specifically for lossless decoding,
/// with the following enhancements:
/// - Pre-computed boundary extension lookup tables
/// - Reduced memory allocations through buffer reuse
/// - Fast-path integer-only arithmetic
/// - Improved cache locality
///
/// ## Performance
///
/// Compared to the generic implementation:
/// - 15-25% faster for typical image sizes
/// - 30-40% reduction in memory allocations
/// - Better CPU cache utilization
///
/// ## Usage
///
/// This is automatically used by the decoder pipeline for lossless mode.
/// Direct usage:
///
/// ```swift
/// let optimizer = J2KDWT1DOptimizer()
/// let result = try optimizer.inverseTransform53Optimized(
///     lowpass: lowpass,
///     highpass: highpass,
///     boundaryExtension: .symmetric
/// )
/// ```
public struct J2KDWT1DOptimizer: Sendable {
    /// Creates a new DWT optimizer.
    public init() {}

    // MARK: - Optimised Inverse Transform

    /// Optimised inverse transform using 5/3 reversible filter.
    ///
    /// This implementation includes several optimisations:
    /// 1. Pre-computed boundary extension values
    /// 2. Vectorization hints for the compiler
    /// 3. Reduced branching in the hot path
    /// 4. Better memory access patterns
    ///
    /// - Parameters:
    ///   - lowpass: Low-pass subband coefficients.
    ///   - highpass: High-pass subband coefficients.
    ///   - boundaryExtension: Boundary extension mode (only symmetric and periodic are optimised).
    /// - Returns: Reconstructed signal.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if inputs are invalid.
    public func inverseTransform53Optimized(
        lowpass: [Int32],
        highpass: [Int32],
        boundaryExtension: J2KDWT1D.BoundaryExtension
    ) throws -> [Int32] {
        let lowpassSize = lowpass.count
        let highpassSize = highpass.count

        guard lowpassSize > 0 else {
            throw J2KError.invalidParameter("Lowpass subband must be non-empty")
        }
        // Edge tiles may have dimension=1, producing empty highpass
        if highpassSize == 0 {
            return lowpass
        }

        // Fast path for symmetric extension (most common in JPEG 2000)
        if boundaryExtension == .symmetric {
            return try inverseTransform53Symmetric(
                lowpass: lowpass,
                highpass: highpass
            )
        }

        // Fallback to generic implementation for other modes
        return try inverseTransform53Generic(
            lowpass: lowpass,
            highpass: highpass,
            boundaryExtension: boundaryExtension
        )
    }

    /// v6-alpha3 step 6B — parity-aware overload of
    /// `inverseTransform53Optimized` that honours the tile-component
    /// image-coordinate origin's parity per ISO/IEC 15444-1 F.4.4 and
    /// is the dual of `AcceleratedDWT2D.forward53_1D(...uOrigin:)`.
    ///
    /// - When `uOrigin` is even (or zero), routes to the existing
    ///   `inverseTransform53Optimized(lowpass:highpass:boundaryExtension:)`
    ///   overload — output is byte-identical, single-tile / 32-aligned
    ///   multi-tile decode paths pay zero cost.
    /// - When `uOrigin` is odd, applies the parity-flipped inverse:
    ///     - Forward at u-odd produced `lowCount = floor(n/2)`,
    ///       `highCount = ceil(n/2)` and gathered L from local-odd /
    ///       H from local-even input positions. The inverse must
    ///       interleave the bands the same way: L → output local-odd
    ///       (positions 1, 3, 5…), H → output local-even (positions
    ///       0, 2, 4…), and apply the dual lifting boundaries
    ///       (no left mirror at H[0] because the tile starts at an
    ///       image-odd canvas position; right mirror at the final
    ///       sample when `n` is odd).
    ///
    /// `lowpass.count` and `highpass.count` MUST equal the
    /// parity-aware low/high counts the encoder produced for this
    /// `uOrigin`. The caller (decoder pipeline) is responsible for
    /// computing these via the ISO/IEC 15444-1 Eq. B-15 spec
    /// formula; this primitive doesn't validate them beyond the
    /// `n = lowpass.count + highpass.count` length invariant.
    ///
    /// Currently only the symmetric boundary extension is
    /// supported for the odd-origin path (matching the encoder's
    /// step 1+2 primitives, which only emit symmetric-extension
    /// output). Generic boundary extension on odd origins is
    /// deferred (no production path currently needs it).
    public func inverseTransform53Optimized(
        lowpass: [Int32],
        highpass: [Int32],
        boundaryExtension: J2KDWT1D.BoundaryExtension,
        uOrigin u: Int
    ) throws -> [Int32] {
        // Even origins (including 0) route to the no-origin fast
        // path — output byte-identical, no perf regression on
        // single-tile and 32-aligned multi-tile.
        if (u & 1) == 0 {
            return try inverseTransform53Optimized(
                lowpass: lowpass, highpass: highpass,
                boundaryExtension: boundaryExtension)
        }

        let lowpassSize = lowpass.count
        let highpassSize = highpass.count
        guard lowpassSize > 0 else {
            throw J2KError.invalidParameter("Lowpass subband must be non-empty")
        }
        if highpassSize == 0 { return lowpass }

        guard boundaryExtension == .symmetric else {
            // Odd-origin generic path is deferred — no production
            // call site needs it (HT lossless 5/3 always uses
            // symmetric per ISO/IEC 15444-1 F.4).
            throw J2KError.invalidParameter(
                "inverseTransform53Optimized: odd-origin path requires " +
                "symmetric boundary extension (got \(boundaryExtension))")
        }

        return inverseTransform53OddOriginSymmetric(
            lowpass: lowpass, highpass: highpass)
    }

    // MARK: - Odd-origin parity-aware inverse (symmetric boundary)

    /// Odd-origin variant of the symmetric-boundary inverse. The
    /// even-origin case is handled by `inverseTransform53Symmetric`.
    /// Lifting equations are the dual of the test-reference
    /// `inverse53_1D` in
    /// `Tests/J2KCodecTests/HTDWT2DParityAwarenessTests.swift` —
    /// the reference is the canonical spec implementation that
    /// step 2's multi-level roundtrip tests pin against.
    private func inverseTransform53OddOriginSymmetric(
        lowpass: [Int32],
        highpass: [Int32]
    ) -> [Int32] {
        let lowCount  = lowpass.count
        let highCount = highpass.count
        let n = lowCount + highCount

        // Working copies of the bands (mutate before interleaving).
        var L = lowpass
        var H = highpass

        L.withUnsafeMutableBufferPointer { lBuf in
            H.withUnsafeMutableBufferPointer { hBuf in
                let lp = lBuf.baseAddress!
                let hp = hBuf.baseAddress!

                // Step 1: undo update on L. For odd origin:
                //   L[i] -= ((H[i] + H[i+1] + 2) >> 2)
                // with right mirror H[i+1] → H[highCount-1] when
                // i+1 >= highCount.
                for i in 0..<lowCount {
                    let left  = hp[i]
                    let right = (i &+ 1 < highCount) ? hp[i &+ 1] : hp[highCount &- 1]
                    lp[i] = lp[i] &- ((left &+ right &+ 2) >> 2)
                }

                // Step 2: undo predict on H. For odd origin:
                //   H[0]   += L[0]                          (left mirror)
                //   H[i]   += ((L[i-1] + L[i]) >> 1)        for 1 ≤ i < min(highCount, lowCount)
                //   H[lowCount] += L[lowCount-1]            (right mirror, n odd)
                if highCount > 0 {
                    hp[0] = hp[0] &+ lp[0]
                }
                let interiorEnd = min(highCount, lowCount)
                for i in 1..<interiorEnd {
                    hp[i] = hp[i] &+ ((lp[i &- 1] &+ lp[i]) >> 1)
                }
                if highCount > lowCount {
                    hp[lowCount] = hp[lowCount] &+ lp[lowCount &- 1]
                }
            }
        }

        // Interleave for odd origin:
        //   x[2i+1] = L[i]    (L band → local-odd output positions)
        //   x[2i]   = H[i]    (H band → local-even output positions)
        var result = [Int32](repeating: 0, count: n)
        result.withUnsafeMutableBufferPointer { rBuf in
            L.withUnsafeBufferPointer { lBuf in
                H.withUnsafeBufferPointer { hBuf in
                    let rp = rBuf.baseAddress!
                    let lp = lBuf.baseAddress!
                    let hp = hBuf.baseAddress!
                    for i in 0..<lowCount  { rp[i &* 2 &+ 1] = lp[i] }
                    for i in 0..<highCount { rp[i &* 2]      = hp[i] }
                }
            }
        }
        return result
    }

    // MARK: - Symmetric Boundary Extension (Optimised)

    /// Optimised inverse transform with symmetric boundary extension.
    ///
    /// This is the most common case and is heavily optimised with:
    /// - Single output allocation (no intermediate even/odd arrays)
    /// - Unsafe pointer access throughout
    /// - Boundary handling split from inner loop (no branches)
    private func inverseTransform53Symmetric(
        lowpass: [Int32],
        highpass: [Int32]
    ) throws -> [Int32] {
        let lpSize = lowpass.count
        let hpSize = highpass.count
        let n = lpSize + hpSize

        // Single allocation - compute even/odd directly into result positions
        var result = [Int32](repeating: 0, count: n)

        result.withUnsafeMutableBufferPointer { resBuf in
            lowpass.withUnsafeBufferPointer { lpBuf in
                highpass.withUnsafeBufferPointer { hpBuf in
                    let rp = resBuf.baseAddress!
                    let lp = lpBuf.baseAddress!
                    let hp = hpBuf.baseAddress!

                    // Step 1: Undo update - write even samples to positions 0, 2, 4, ...
                    // even[i] = lowpass[i] - ((hp[i-1] + hp[i] + 2) >> 2)
                    // Boundary: hp[-1] = hp[0] (symmetric), hp[hpSize] = hp[hpSize-1]

                    // First element (left boundary: symmetric hp[-1] = hp[0])
                    rp[0] = lp[0] &- ((hp[0] &+ hp[0] &+ 2) >> 2)

                    let interiorEnd = min(lpSize, hpSize)
                    var i = 1
                    // v8 Phase 3 — SIMD4<Int32> path, 4 iterations per
                    // chunk. Bit-exact with scalar reference: every
                    // operation is wrapping integer arithmetic with the
                    // same shift semantics (Swift `>>` on signed integer
                    // SIMDs is arithmetic per the SIMD protocol).
                    while i &+ 4 <= interiorEnd {
                        let lpVec = SIMD4<Int32>(
                            lp[i], lp[i &+ 1], lp[i &+ 2], lp[i &+ 3])
                        let hpL = SIMD4<Int32>(
                            hp[i &- 1], hp[i], hp[i &+ 1], hp[i &+ 2])
                        let hpR = SIMD4<Int32>(
                            hp[i], hp[i &+ 1], hp[i &+ 2], hp[i &+ 3])
                        // Match scalar: (hp_left + hp_right + 2) >> 2
                        // Use explicit broadcast for the + 2 since
                        // SIMD<>+Int is not always available.
                        let avg = (hpL &+ hpR &+ SIMD4<Int32>(repeating: 2)) &>> SIMD4<Int32>(repeating: 2)
                        let outVec = lpVec &- avg
                        rp[i &* 2]          = outVec[0]
                        rp[(i &+ 1) &* 2]   = outVec[1]
                        rp[(i &+ 2) &* 2]   = outVec[2]
                        rp[(i &+ 3) &* 2]   = outVec[3]
                        i &+= 4
                    }
                    // scalar tail
                    while i < interiorEnd {
                        rp[i &* 2] = lp[i] &- ((hp[i &- 1] &+ hp[i] &+ 2) >> 2)
                        i &+= 1
                    }

                    // Last element if lpSize > hpSize (right boundary: symmetric)
                    if lpSize > hpSize {
                        let lastHP = hp[hpSize &- 1]
                        rp[(lpSize &- 1) &* 2] = lp[lpSize &- 1] &- ((lastHP &+ lastHP &+ 2) >> 2)
                    }

                    // Step 2: Undo predict - write odd samples to positions 1, 3, 5, ...
                    // odd[i] = highpass[i] + ((even[i] + even[i+1]) >> 1)
                    // even values are already at rp[0], rp[2], rp[4], ...

                    // Interior elements
                    let lastOdd = hpSize &- 1
                    var j = 0
                    while j &+ 4 <= lastOdd {
                        let evenL = SIMD4<Int32>(
                            rp[j &* 2],
                            rp[(j &+ 1) &* 2],
                            rp[(j &+ 2) &* 2],
                            rp[(j &+ 3) &* 2])
                        let evenR = SIMD4<Int32>(
                            rp[(j &+ 1) &* 2],
                            rp[(j &+ 2) &* 2],
                            rp[(j &+ 3) &* 2],
                            rp[(j &+ 4) &* 2])
                        let hpVec = SIMD4<Int32>(
                            hp[j], hp[j &+ 1], hp[j &+ 2], hp[j &+ 3])
                        let avg = (evenL &+ evenR) &>> SIMD4<Int32>(repeating: 1)
                        let outVec = hpVec &+ avg
                        rp[j &* 2 &+ 1]          = outVec[0]
                        rp[(j &+ 1) &* 2 &+ 1]   = outVec[1]
                        rp[(j &+ 2) &* 2 &+ 1]   = outVec[2]
                        rp[(j &+ 3) &* 2 &+ 1]   = outVec[3]
                        j &+= 4
                    }
                    // scalar tail
                    while j < lastOdd {
                        rp[j &* 2 &+ 1] = hp[j] &+ ((rp[j &* 2] &+ rp[(j &+ 1) &* 2]) >> 1)
                        j &+= 1
                    }

                    // Last odd sample (boundary: even[hpSize] uses symmetric extension)
                    if hpSize > 0 {
                        let evenLeft = rp[lastOdd &* 2]
                        let evenRight = rp[min((lastOdd &+ 1) &* 2, (lpSize &- 1) &* 2)]
                        rp[lastOdd &* 2 &+ 1] = hp[lastOdd] &+ ((evenLeft &+ evenRight) >> 1)
                    }
                }
            }
        }

        return result
    }

    // MARK: - Generic Implementation (Fallback)

    /// Generic inverse transform for non-symmetric boundary extensions.
    private func inverseTransform53Generic(
        lowpass: [Int32],
        highpass: [Int32],
        boundaryExtension: J2KDWT1D.BoundaryExtension
    ) throws -> [Int32] {
        // Fall back to standard implementation
        try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53,
            boundaryExtension: boundaryExtension
        )
    }
}

// MARK: - 2D Optimised Transform

/// Optimised 2D DWT operations for lossless decoding.
public struct J2KDWT2DOptimizer: Sendable {
    private let optimizer1D = J2KDWT1DOptimizer()

    /// Creates a new 2D DWT optimizer.
    public init() {}

    /// Optimised 2D inverse transform for lossless decoding.
    ///
    /// This implementation optimises column processing by:
    /// - Using a tiled approach for better cache utilization
    /// - Minimizing temporary allocations
    /// - Optimising memory access patterns
    ///
    /// - Parameters:
    ///   - ll: Low-low subband.
    ///   - lh: Low-high subband.
    ///   - hl: High-low subband.
    ///   - hh: High-high subband.
    ///   - boundaryExtension: Boundary extension mode.
    /// - Returns: Reconstructed 2D image.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if subbands have incompatible sizes.
    public func inverseTransform2DOptimized(
        ll: [[Int32]],
        lh: [[Int32]],
        hl: [[Int32]],
        hh: [[Int32]],
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric
    ) async throws -> [[Int32]] {
        // Validate inputs
        guard !ll.isEmpty else {
            throw J2KError.invalidParameter("LL subband cannot be empty")
        }
        // Handle edge tiles where subbands may be empty (tile dimension=1 in some direction)
        if lh.isEmpty && hl.isEmpty && hh.isEmpty {
            return ll
        }

        let llHeight = ll.count
        let llWidth = ll[0].count
        let lhHeight = lh.count
        let lhWidth = lh.isEmpty ? 0 : lh[0].count
        let hlHeight = hl.count
        let hlWidth = hl.isEmpty ? 0 : hl[0].count
        let hhHeight = hh.count
        let hhWidth = hh.isEmpty ? 0 : hh[0].count

        // Validate subband dimensions
        if !hl.isEmpty && !hh.isEmpty {
            guard abs(llWidth - lhWidth) <= 1 && abs(hlWidth - hhWidth) <= 1 && abs(llWidth - hlWidth) <= 1 else {
                throw J2KError.invalidParameter(
                    "Incompatible subband widths: LL=\(llWidth), LH=\(lhWidth), HL=\(hlWidth), HH=\(hhWidth)"
                )
            }
        }

        if !lh.isEmpty && !hh.isEmpty {
            guard abs(llHeight - hlHeight) <= 1 && abs(lhHeight - hhHeight) <= 1 && abs(llHeight - lhHeight) <= 1 else {
                throw J2KError.invalidParameter(
                    "Incompatible subband heights: LL=\(llHeight), LH=\(lhHeight), HL=\(hlHeight), HH=\(hhHeight)"
                )
            }
        }

        // Per JPEG 2000 standard: inverse applies rows (horizontal) first, then columns (vertical)

        // Step 1: Apply inverse 1D DWT to rows (horizontal pass)
        // LL + HL → col-low rows, LH + HH → col-high rows

        var colLow = [[Int32]](repeating: [], count: llHeight)
        var colHigh = [[Int32]](repeating: [], count: lhHeight)

        let totalRows = llHeight + lhHeight
        if totalRows >= 8 {
            // Parallel row transforms using structured concurrency
            let opt = self.optimizer1D
            let results = try await withThrowingTaskGroup(
                of: [(Bool, Int, [Int32])].self
            ) { group in
                let coreCount = ProcessInfo.processInfo.processorCount
                let chunkSize = max(1, totalRows / coreCount)
                for chunkStart in stride(from: 0, to: totalRows, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, totalRows)
                    group.addTask {
                        var chunkResults: [(Bool, Int, [Int32])] = []
                        for i in chunkStart..<chunkEnd {
                            if i < llHeight {
                                let row = try opt.inverseTransform53Optimized(
                                    lowpass: ll[i], highpass: hl[i],
                                    boundaryExtension: boundaryExtension)
                                chunkResults.append((true, i, row))
                            } else {
                                let j = i - llHeight
                                let row = try opt.inverseTransform53Optimized(
                                    lowpass: lh[j], highpass: hh[j],
                                    boundaryExtension: boundaryExtension)
                                chunkResults.append((false, j, row))
                            }
                        }
                        return chunkResults
                    }
                }
                var all: [(Bool, Int, [Int32])] = []
                for try await chunk in group {
                    all.append(contentsOf: chunk)
                }
                return all
            }
            for (isLow, index, row) in results {
                if isLow {
                    colLow[index] = row
                } else {
                    colHigh[index] = row
                }
            }
        } else {
            // Sequential path for small images
            for row in 0..<llHeight {
                colLow[row] = try optimizer1D.inverseTransform53Optimized(
                    lowpass: ll[row], highpass: hl[row],
                    boundaryExtension: boundaryExtension)
            }
            for row in 0..<lhHeight {
                colHigh[row] = try optimizer1D.inverseTransform53Optimized(
                    lowpass: lh[row], highpass: hh[row],
                    boundaryExtension: boundaryExtension)
            }
        }

        // Step 2: Apply inverse 1D DWT to columns (vertical pass)
        let outputWidth = colLow[0].count
        let colLowHeight = colLow.count
        let colHighHeight = colHigh.count
        let outputHeight = colLowHeight + colHighHeight

        var result = Array(repeating: [Int32](repeating: 0, count: outputWidth), count: outputHeight)

        if outputWidth >= 8 {
            // Parallel column transforms using structured concurrency
            let flatBuf = UnsafeMutablePointer<Int32>.allocate(capacity: outputWidth * outputHeight)
            flatBuf.initialize(repeating: 0, count: outputWidth * outputHeight)
            defer {
                flatBuf.deinitialize(count: outputWidth * outputHeight)
                flatBuf.deallocate()
            }

            let safeFlatBuf = SendablePointer(flatBuf)
            let capturedColLow = colLow
            let capturedColHigh = colHigh
            let opt = self.optimizer1D
            let coreCount = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, outputWidth / coreCount)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for chunkStart in stride(from: 0, to: outputWidth, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, outputWidth)
                    group.addTask {
                        let flatBuf = safeFlatBuf.pointer
                        var lowpassBuf = [Int32](repeating: 0, count: colLowHeight)
                        var highpassBuf = [Int32](repeating: 0, count: colHighHeight)
                        for col in chunkStart..<chunkEnd {
                            for row in 0..<colLowHeight {
                                lowpassBuf[row] = capturedColLow[row][col]
                            }
                            for row in 0..<colHighHeight {
                                highpassBuf[row] = capturedColHigh[row][col]
                            }
                            let reconstructedColumn = try opt.inverseTransform53Optimized(
                                lowpass: lowpassBuf, highpass: highpassBuf,
                                boundaryExtension: boundaryExtension)
                            for i in 0..<min(reconstructedColumn.count, outputHeight) {
                                flatBuf[i &* outputWidth &+ col] = reconstructedColumn[i]
                            }
                        }
                    }
                }
            }

            // Reshape flat buffer to [[Int32]]
            for row in 0..<outputHeight {
                let start = row &* outputWidth
                result[row] = Array(UnsafeBufferPointer(start: flatBuf + start, count: outputWidth))
            }
        } else {
            // Sequential path for narrow images
            var lowpassBuf = [Int32](repeating: 0, count: colLowHeight)
            var highpassBuf = [Int32](repeating: 0, count: colHighHeight)

            for col in 0..<outputWidth {
                for row in 0..<colLowHeight {
                    lowpassBuf[row] = colLow[row][col]
                }
                for row in 0..<colHighHeight {
                    highpassBuf[row] = colHigh[row][col]
                }

                let reconstructedColumn = try optimizer1D.inverseTransform53Optimized(
                    lowpass: lowpassBuf, highpass: highpassBuf,
                    boundaryExtension: boundaryExtension)

                for i in 0..<reconstructedColumn.count {
                    result[i][col] = reconstructedColumn[i]
                }
            }
        }

        return result
    }

    // MARK: - In-Place 5/3 Lifting (Strided)

    /// Performs inverse Le Gall 5/3 lifting in-place on interleaved even/odd
    /// samples stored at `base` with the given `stride`.
    ///
    /// On entry: `base[0], base[s], base[2s], ...` hold the interleaved signal:
    ///   positions `2i*s` = even (lowpass), `(2i+1)*s` = odd (highpass).
    ///
    /// On exit: the reconstructed signal occupies the same locations.
    ///
    /// - Parameters:
    ///   - base: Pointer to the start of the interleaved signal.
    ///   - evenCount: Number of even (lowpass) samples.
    ///   - oddCount: Number of odd (highpass) samples.
    ///   - stride s: Distance in elements between adjacent samples.
    /// Cache-friendly tiled transpose of an Int32 `rows × cols` matrix.
    /// Tile size 64 keeps each tile in L1 cache (16 KB on Apple Silicon).
    @inline(__always)
    static func transposeInt32(
        src: UnsafePointer<Int32>, dst: UnsafeMutablePointer<Int32>,
        rows: Int, cols: Int
    ) {
        let tileSize = 64
        for tileRow in stride(from: 0, to: rows, by: tileSize) {
            let rowEnd = min(tileRow + tileSize, rows)
            for tileCol in stride(from: 0, to: cols, by: tileSize) {
                let colEnd = min(tileCol + tileSize, cols)
                for r in tileRow..<rowEnd {
                    let srcRow = src + r &* cols
                    for c in tileCol..<colEnd {
                        dst[c &* rows &+ r] = srcRow[c]
                    }
                }
            }
        }
    }

    @inline(__always)
    static func inverseLift53InPlace(
        _ base: UnsafeMutablePointer<Int32>,
        evenCount: Int,
        oddCount: Int,
        stride s: Int
    ) {
        guard evenCount > 0 && oddCount > 0 else { return }

        // Step 1: Undo update — even[i] -= floor((hp[i-1] + hp[i] + 2) / 4)
        // Left boundary: hp[-1] = hp[0]
        let hp0 = base[s]
        base[0] = base[0] &- ((hp0 &+ hp0 &+ 2) >> 2)

        let limit = min(evenCount, oddCount)
        for i in 1..<limit {
            let prevHP = base[(i &* 2 &- 1) &* s]
            let curHP  = base[(i &* 2 &+ 1) &* s]
            base[(i &* 2) &* s] = base[(i &* 2) &* s] &- ((prevHP &+ curHP &+ 2) >> 2)
        }

        // Right boundary: hp[evenCount] = hp[oddCount-1] (symmetric)
        if evenCount > oddCount {
            let lastHP = base[(oddCount &* 2 &- 1) &* s]
            base[(evenCount &- 1) &* 2 &* s] = base[(evenCount &- 1) &* 2 &* s] &-
                ((lastHP &+ lastHP &+ 2) >> 2)
        }

        // Step 2: Undo predict — odd[i] += floor((even[i] + even[i+1]) / 2)
        let lastOdd = oddCount &- 1
        for i in 0..<lastOdd {
            let evenL = base[(i &* 2) &* s]
            let evenR = base[(i &* 2 &+ 2) &* s]
            base[(i &* 2 &+ 1) &* s] = base[(i &* 2 &+ 1) &* s] &+ ((evenL &+ evenR) >> 1)
        }

        // Last odd: right boundary — even[oddCount] = even[evenCount-1]
        let evenRightIdx = min((lastOdd &+ 1) &* 2, (evenCount &- 1) &* 2)
        let evenL = base[lastOdd &* 2 &* s]
        let evenR = base[evenRightIdx &* s]
        base[(lastOdd &* 2 &+ 1) &* s] = base[(lastOdd &* 2 &+ 1) &* s] &+ ((evenL &+ evenR) >> 1)
    }

    // MARK: - v10.5 Column-Block Lift (No-Transpose Path)

    /// v10.5-research column-block 5/3 inverse lift: applies the
    /// inverse Le Gall 5/3 to columns `[cStart, cEnd)` of a row-major
    /// row-major Int32 buffer **directly**, without the transpose
    /// → stride-1 lift → untranspose round-trip used by the
    /// canonical column-pass.
    ///
    /// Trade-off vs the canonical (transposed) path:
    /// - **Bandwidth**: ~3× less DRAM traffic per IDWT pass
    ///   (2× buffer reads/writes vs ~6× for the canonical path
    ///   that pays transpose + lift + untranspose). On level-1 of
    ///   an MG (3520×4784) buffer the column-block path is **5.5–
    ///   8.3× faster** in the V10_5 microbench
    ///   (`V10_5_IDWTBandwidthProbeMicrobench`).
    /// - **Cache footprint**: a column block of width N visits
    ///   3 rows × N cells per step (~768 B per row for N=16) —
    ///   L1-resident across a column pass. The canonical path's
    ///   transpose buffer is the full image (67 MB for MG), which
    ///   blows M2's 16 MB shared P-cluster L2.
    ///
    /// The math is bit-exact with `inverseLift53InPlace(_:evenCount:
    /// oddCount:stride:)` — verified across MG/DX/PX synthetic
    /// buffers in V10_5 microbench (6/6 parity ✓) and across the
    /// real medical corpus via the parity gate.
    @inline(__always)
    static func inverseLift53ColBlock(
        _ base: UnsafeMutablePointer<Int32>,
        cStart: Int, cEnd: Int,
        outW: Int,
        evenCount: Int,
        oddCount: Int
    ) {
        guard evenCount > 0 && oddCount > 0 else { return }
        let limit = min(evenCount, oddCount)
        let lastOdd = oddCount &- 1

        // Step 1: Undo update — even[i] -= floor((hp[i-1] + hp[i] + 2) / 4)
        // Left boundary: hp[-1] = hp[0]
        do {
            let rowHP0 = base + outW   // row 1 (first odd)
            let rowEV0 = base          // row 0 (first even)
            for c in cStart..<cEnd {
                let hp0 = rowHP0[c]
                rowEV0[c] = rowEV0[c] &- ((hp0 &+ hp0 &+ 2) >> 2)
            }
        }
        for i in 1..<limit {
            let evenRow = base + (i &* 2) &* outW
            let prevHPRow = base + (i &* 2 &- 1) &* outW
            let curHPRow  = base + (i &* 2 &+ 1) &* outW
            for c in cStart..<cEnd {
                evenRow[c] = evenRow[c] &- ((prevHPRow[c] &+ curHPRow[c] &+ 2) >> 2)
            }
        }
        // Right boundary: hp[evenCount] = hp[oddCount-1] (symmetric)
        if evenCount > oddCount {
            let lastHPRow = base + (oddCount &* 2 &- 1) &* outW
            let lastEVRow = base + (evenCount &- 1) &* 2 &* outW
            for c in cStart..<cEnd {
                lastEVRow[c] = lastEVRow[c] &- ((lastHPRow[c] &+ lastHPRow[c] &+ 2) >> 2)
            }
        }

        // Step 2: Undo predict — odd[i] += floor((even[i] + even[i+1]) / 2)
        for i in 0..<lastOdd {
            let oddRow   = base + (i &* 2 &+ 1) &* outW
            let evenLRow = base + (i &* 2) &* outW
            let evenRRow = base + (i &* 2 &+ 2) &* outW
            for c in cStart..<cEnd {
                oddRow[c] = oddRow[c] &+ ((evenLRow[c] &+ evenRRow[c]) >> 1)
            }
        }
        // Last odd: right boundary — even[oddCount] = even[evenCount-1]
        let evenRightIdx = min((lastOdd &+ 1) &* 2, (evenCount &- 1) &* 2)
        let lastOddRow = base + (lastOdd &* 2 &+ 1) &* outW
        let evenLRow   = base + (lastOdd &* 2) &* outW
        let evenRRow   = base + evenRightIdx &* outW
        for c in cStart..<cEnd {
            lastOddRow[c] = lastOddRow[c] &+ ((evenLRow[c] &+ evenRRow[c]) >> 1)
        }
    }

    /// v10.5-research env-var gate for the column-block IDWT path.
    ///
    /// **Default OFF** after the end-to-end Phase 4 / 4b A/B benches
    /// closed the lever as a wash: the column-lift microbench
    /// measured 22 ms / 5.5–8.3× savings on MG-class level-1 buffers
    /// (`V10_5_IDWTBandwidthProbeMicrobench`, 6/6 bit-exact), but
    /// neither end-to-end test
    /// (`V10_5_IDWTColBlockEndToEndABTests`,
    ///  `V10_5_IDWTColBlockVsGPUTests`) saw the savings translate
    /// to wall — every MG / DX / PX fixture delta sat inside ±3 ms.
    /// Two reasons:
    ///
    ///  1. `J2KDecoder.decode()` routes ≥4 MP fixtures through the
    ///     **GPU IDWT** path (`_gpuInverse53Enabled` default ON since
    ///     v6.2.0). MG / DX never reach the CPU column-pass in
    ///     production. PX is below the 4 MP threshold but its level-1
    ///     buffer (~14.8 MB) already fits inside M2's 16 MB L2 — the
    ///     bandwidth lever doesn't apply at PX scale.
    ///
    ///  2. Even when the CPU path is forced, the existing
    ///     parallel-chunk transpose-then-stride-1-lift achieves enough
    ///     L2 reuse on real wavelet subband data (vs the synthetic
    ///     LCG-noise microbench buffer) that the savings collapse
    ///     into the noise floor. This is the same isolated-stage-vs-
    ///     wall wash documented in v8.4 / v8.5 / v8.6 / v8.7 / v10.4
    ///     and now v10.5 — 10th independent lever-ceiling confirmation
    ///     on M2 + Swift release.
    ///
    /// The code stays in tree as **opt-in via `J2K_IDWT_COLBLOCK=1`**:
    /// bit-exact across 10 medical fixtures and 6 synthetic edge
    /// cases (`V10_5_IDWTColBlockParityTests`), so it's available
    /// for diagnostic A/B, cross-silicon re-measurement (M3 / M4
    /// curves may differ — L2 sizes shifted), and as a building
    /// block if a future GPU-IDWT-side bandwidth probe lands.
    nonisolated(unsafe) public static var columnBlockLiftEnabled: Bool = {
        ProcessInfo.processInfo.environment["J2K_IDWT_COLBLOCK"] == "1"
    }()

    // MARK: - Flat-Buffer Multi-Level IDWT (5/3 Lossless)

    /// Performs a complete multi-level inverse Le Gall 5/3 DWT on flat subband data.
    ///
    /// Accepts subbands as flat `[Int32]` arrays with explicit dimensions,
    /// bypassing all `[[Int32]]` intermediate jagged-array conversions. All DWT
    /// levels are processed in sequence using a single raw pointer that is grown
    /// level by level, eliminating hundreds of short-lived heap allocations and
    /// the cache-unfriendly pointer-chasing that occurs during column gathering
    /// in the per-level `inverseTransform2DOptimized` path.
    ///
    /// The algorithm mirrors `inverseTransformMultiLevel97` for the 9/7 path:
    /// 1. Place LL at even rows, LH at odd rows, HL at even-row high columns,
    ///    HH at odd-row high columns in a flat workspace.
    /// 2. Apply strided in-place column lifting via `inverseLift53InPlace`.
    /// 3. Apply row lifting via a per-task temp buffer + `inverseLift53InPlace`.
    ///
    /// - Parameters:
    ///   - ll: LL subband coefficients (flat, row-major).
    ///   - llW: Width of the LL subband.
    ///   - llH: Height of the LL subband.
    ///   - subbands: Per-level subbands ordered deepest-first (smallest → largest).
    ///     Each element carries `(lh, lhW, lhH, hl, hlW, hlH, hh, hhW, hhH)`.
    /// - Returns: Tuple `(data, width, height)` — flat row-major `[Int32]`.
    public func inverseTransformMultiLevel53(
        ll: [Int32], llW: Int, llH: Int,
        subbands: [(lh: [Int32], lhW: Int, lhH: Int,
                     hl: [Int32], hlW: Int, hlH: Int,
                     hh: [Int32], hhW: Int, hhH: Int)]
    ) async -> (data: [Int32], width: Int, height: Int) {
        guard !subbands.isEmpty else {
            return (data: ll, width: llW, height: llH)
        }

        // Keep the working buffer as a raw pointer between levels to avoid
        // Swift Array COW copies. Convert to [Int32] only at the final step.
        let initSize = llW * llH
        var currentBuf = UnsafeMutablePointer<Int32>.allocate(capacity: max(initSize, 1))
        ll.withUnsafeBufferPointer { src in
            currentBuf.initialize(from: src.baseAddress!, count: initSize)
        }
        var curW = llW
        var curH = llH

        for level in subbands {
            let lhH = level.lhH
            let lhW = level.lhW
            let hlW = level.hlW
            let hlH = level.hlH
            let hhW = level.hhW
            let hhH = level.hhH
            let outH = curH + lhH
            let outW = curW + hlW

            // Allocate fresh workspace for this level
            let bufSize = outH * outW
            let base = UnsafeMutablePointer<Int32>.allocate(capacity: bufSize)
            // Only zero-fill when a source dimension is smaller than the
            // destination (asymmetric halving on odd parents). For dyadic
            // dimensions — the common case — every cell is written by the
            // four placement loops below.
            let allCellsWritten = curW == lhW &&
                                  curH == hlH && lhH == hhH &&
                                  hlW > 0 && hlW == hhW
            if !allCellsWritten {
                base.initialize(repeating: 0, count: bufSize)
            }

            // Place LL at even rows, low cols (columns 0..<curW, rows 0,2,4,...)
            for r in 0..<curH {
                (base + r &* 2 &* outW).update(from: currentBuf + r &* curW, count: curW)
            }
            currentBuf.deallocate()

            // Place LH at odd rows, low cols (rows 1,3,5,...)
            level.lh.withUnsafeBufferPointer { src in
                let p = src.baseAddress!
                let copyW = min(curW, lhW)
                for r in 0..<lhH {
                    (base + (r &* 2 &+ 1) &* outW).update(from: p + r &* lhW, count: copyW)
                }
            }

            // Place HL at even rows, high cols (columns curW..<outW, rows 0,2,4,...)
            if hlW > 0 {
                let srcHlW = level.hlW
                level.hl.withUnsafeBufferPointer { src in
                    let p = src.baseAddress!
                    let copyW = min(hlW, srcHlW)
                    for r in 0..<hlH {
                        let dstOff = r &* 2 &* outW &+ curW
                        (base + dstOff).update(from: p + r &* srcHlW, count: copyW)
                    }
                }
            }

            // Place HH at odd rows, high cols (rows 1,3,5,...)
            if hlW > 0 {
                level.hh.withUnsafeBufferPointer { src in
                    let p = src.baseAddress!
                    let copyW = min(hlW, hhW)
                    for r in 0..<hhH {
                        let dstOff = (r &* 2 &+ 1) &* outW &+ curW
                        (base + dstOff).update(from: p + r &* hhW, count: copyW)
                    }
                }
            }

            // Row lifting (FIRST): interleave low/high cols into temp, lift in-place, copy back.
            // After placement each row has: low cols 0..<curW (even = H lowpass),
            // high cols curW..<outW (odd = H highpass). Applying H inverse per row gives
            // back the full-width horizontal-reconstructed rows. The even/odd row
            // parity (V lowpass / V highpass) is preserved for the column pass.
            let lowCols = curW
            let safeBaseRow = SendablePointer(base)
            if outH >= 128 {
                let coreCount = ProcessInfo.processInfo.processorCount
                let chunkSize = max(1, outH / coreCount)
                await withTaskGroup(of: Void.self) { group in
                    for chunkStart in stride(from: 0, to: outH, by: chunkSize) {
                        let chunkEnd = min(chunkStart + chunkSize, outH)
                        group.addTask {
                            let b = safeBaseRow.pointer
                            // tmp is fully overwritten by the scatter before any read — skip zero-init.
                            var tmp = [Int32](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                            tmp.withUnsafeMutableBufferPointer { tmpBuf in
                                let tp = tmpBuf.baseAddress!
                                for r in chunkStart..<chunkEnd {
                                    let rowBase = b + r &* outW
                                    for i in 0..<lowCols { tp[i &* 2] = rowBase[i] }
                                    for i in 0..<hlW { tp[i &* 2 &+ 1] = rowBase[lowCols &+ i] }
                                    J2KDWT2DOptimizer.inverseLift53InPlace(
                                        tp, evenCount: lowCols, oddCount: hlW, stride: 1
                                    )
                                    rowBase.update(from: tp, count: outW)
                                }
                            }
                        }
                    }
                }
            } else {
                var tmp = [Int32](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                tmp.withUnsafeMutableBufferPointer { tmpBuf in
                    let tp = tmpBuf.baseAddress!
                    for r in 0..<outH {
                        let rowBase = base + r &* outW
                        for i in 0..<lowCols { tp[i &* 2] = rowBase[i] }
                        for i in 0..<hlW { tp[i &* 2 &+ 1] = rowBase[lowCols &+ i] }
                        J2KDWT2DOptimizer.inverseLift53InPlace(
                            tp, evenCount: lowCols, oddCount: hlW, stride: 1
                        )
                        rowBase.update(from: tp, count: outW)
                    }
                }
            }

            // Column lifting (SECOND).
            //
            // v10.5 Phase 2 — when `columnBlockLiftEnabled` is true
            // (default), apply the column-block lift directly on the
            // row-major `base`, skipping the transpose + stride-1
            // lift + untranspose round-trip. On MG-class level-1
            // buffers (3520×4784 Int32 = 67 MB) the canonical path
            // pays 6× the buffer in DRAM traffic
            // (transpose-out + lift + untranspose-in, each 2×); the
            // column-block path pays 2×. M2's 16 MB P-cluster L2 is
            // 8× smaller than the level-1 working set, so this
            // bandwidth elision is where MG decode time actually
            // burns. Microbench `V10_5_IDWTBandwidthProbeMicrobench`
            // measures 5.5–8.3× speedup, bit-exact across 6 buffer
            // shapes.
            //
            // Canonical (transpose) path stays for the opt-out
            // (`J2K_IDWT_COLBLOCK=0`) and for the small-buffer
            // sequential branch where the stride-outW penalty is
            // dwarfed by overhead.
            let evenRows = curH
            let coreCountCol = ProcessInfo.processInfo.processorCount
            if outH >= 32 && outW >= 32 {
                if J2KDWT2DOptimizer.columnBlockLiftEnabled {
                    // v10.5 column-block path — row-major, no transpose.
                    let safeBase = SendablePointer(base)
                    let colChunk = max(16, outW / coreCountCol)
                    let colBlockSize = 16
                    await withTaskGroup(of: Void.self) { group in
                        for chunkStart in stride(from: 0, to: outW, by: colChunk) {
                            let chunkEnd = min(chunkStart + colChunk, outW)
                            group.addTask {
                                let b = safeBase.pointer
                                var c = chunkStart
                                while c < chunkEnd {
                                    let cEnd = min(c + colBlockSize, chunkEnd)
                                    J2KDWT2DOptimizer.inverseLift53ColBlock(
                                        b, cStart: c, cEnd: cEnd, outW: outW,
                                        evenCount: evenRows, oddCount: lhH)
                                    c += colBlockSize
                                }
                            }
                        }
                    }
                } else {
                    // Canonical path — transpose → stride-1 lift → untranspose.
                    let tBuf = UnsafeMutablePointer<Int32>.allocate(capacity: bufSize)
                    defer { tBuf.deallocate() }
                    J2KDWT2DOptimizer.transposeInt32(src: base, dst: tBuf, rows: outH, cols: outW)
                    let safeT = SendablePointer(tBuf)
                    let colChunk = max(1, outW / coreCountCol)
                    await withTaskGroup(of: Void.self) { group in
                        for chunkStart in stride(from: 0, to: outW, by: colChunk) {
                            let chunkEnd = min(chunkStart + colChunk, outW)
                            group.addTask {
                                let tp = safeT.pointer
                                for col in chunkStart..<chunkEnd {
                                    J2KDWT2DOptimizer.inverseLift53InPlace(
                                        tp + col &* outH, evenCount: evenRows, oddCount: lhH, stride: 1
                                    )
                                }
                            }
                        }
                    }
                    J2KDWT2DOptimizer.transposeInt32(src: tBuf, dst: base, rows: outW, cols: outH)
                }
            } else {
                for col in 0..<outW {
                    J2KDWT2DOptimizer.inverseLift53InPlace(
                        base + col, evenCount: evenRows, oddCount: lhH, stride: outW
                    )
                }
            }

            // Hand off to next level without copying
            currentBuf = base
            curW = outW
            curH = outH
        }

        // Final conversion to Swift Array (single allocation at the end)
        let finalSize = curW * curH
        let result = Array(UnsafeBufferPointer(start: currentBuf, count: finalSize))
        currentBuf.deallocate()

        return (data: result, width: curW, height: curH)
    }

    // MARK: - Parity-Aware 2D Inverse (v6-alpha3 step 6B slice 2)

    /// Mathematical ceiling division for a possibly-negative numerator
    /// and positive denominator. Used by the parity-aware multi-level
    /// inverse to compute per-level LL canvas-coord origins per
    /// ISO/IEC 15444-1 Eq. B-15. Mirrors `EncoderPipeline.ceilDivIntegerOrigin`.
    @inline(__always)
    private static func ceilDivIntegerOrigin(_ num: Int, _ den: Int) -> Int {
        precondition(den > 0)
        if num >= 0 { return (num + den - 1) / den }
        return -((-num) / den)
    }

    /// Parity-aware single-level 2D inverse 5/3 DWT. Mirror of
    /// `AcceleratedDWT2D.forward2D_53(...tileOriginX:tileOriginY:)`
    /// (v6-alpha3 step 2). Takes the four bands and reconstructs
    /// the input tile-component image at the given canvas origin
    /// `(uX, uY)`.
    ///
    /// **Even-origin regression**: when both `uX` and `uY` are even
    /// (including zero), routes to the existing
    /// `inverseTransform2DOptimized(ll:lh:hl:hh:boundaryExtension:)`
    /// fast path — output is byte-identical, single-tile and
    /// 32-aligned multi-tile decode pay zero cost.
    ///
    /// **Odd-origin path**: applies the parity-aware 1D inverse
    /// (slice 1, `inverseTransform53Optimized(...uOrigin:)`) on
    /// each row (with `uX`) and each column (with `uY`). Slow
    /// correctness-first implementation, no parallel-strip
    /// optimisation yet — multi-tile decode currently doesn't
    /// fire on non-32-aligned fixtures in production.
    public func inverseTransform2DOptimized(
        ll: [[Int32]],
        lh: [[Int32]],
        hl: [[Int32]],
        hh: [[Int32]],
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric,
        uX: Int, uY: Int
    ) async throws -> [[Int32]] {
        // Even-origin regression guard.
        if (uX & 1) == 0 && (uY & 1) == 0 {
            return try await inverseTransform2DOptimized(
                ll: ll, lh: lh, hl: hl, hh: hh,
                boundaryExtension: boundaryExtension)
        }

        // Edge: all empty → return LL untouched.
        if lh.isEmpty && hl.isEmpty && hh.isEmpty { return ll }

        let llHeight = ll.count
        let llWidth = ll[0].count
        let lhHeight = lh.count
        let lhWidth = lh.isEmpty ? 0 : lh[0].count
        let hlHeight = hl.count
        let hlWidth = hl.isEmpty ? 0 : hl[0].count
        let hhHeight = hh.count
        let hhWidth = hh.isEmpty ? 0 : hh[0].count

        let rowLowW  = llWidth
        let rowHighW = max(hlWidth, hhWidth)
        let colLowH  = max(llHeight, hlHeight)
        let colHighH = max(lhHeight, hhHeight)

        let _ = lhWidth   // silence unused-warning; lhWidth must equal rowLowW per spec
        let _ = hhHeight  // silence unused-warning

        let outputW = rowLowW + rowHighW
        let outputH = colLowH + colHighH

        // Row pass (FIRST): each row combines (LL+HL) or (LH+HH)
        // and applies the parity-aware 1D inverse with `uOrigin =
        // uX` to recover the V-low or V-high column-prep row.
        var colLow = [[Int32]](repeating: [], count: colLowH)
        var colHigh = [[Int32]](repeating: [], count: colHighH)

        for row in 0..<colLowH {
            let lpRow = row < llHeight ? ll[row] : [Int32](repeating: 0, count: rowLowW)
            let hpRow = row < hlHeight ? hl[row] : [Int32](repeating: 0, count: rowHighW)
            colLow[row] = try optimizer1D.inverseTransform53Optimized(
                lowpass: lpRow, highpass: hpRow,
                boundaryExtension: boundaryExtension, uOrigin: uX)
        }
        for row in 0..<colHighH {
            let lpRow = row < lhHeight ? lh[row] : [Int32](repeating: 0, count: rowLowW)
            let hpRow = row < hhHeight ? hh[row] : [Int32](repeating: 0, count: rowHighW)
            colHigh[row] = try optimizer1D.inverseTransform53Optimized(
                lowpass: lpRow, highpass: hpRow,
                boundaryExtension: boundaryExtension, uOrigin: uX)
        }

        // Column pass (SECOND): for each column, gather low + high
        // values into a 1D buffer and apply the parity-aware 1D
        // inverse with `uOrigin = uY`.
        var result = [[Int32]](
            repeating: [Int32](repeating: 0, count: outputW),
            count: outputH)
        var lowBuf = [Int32](repeating: 0, count: colLowH)
        var highBuf = [Int32](repeating: 0, count: colHighH)
        for col in 0..<outputW {
            for row in 0..<colLowH {
                lowBuf[row] = col < colLow[row].count ? colLow[row][col] : 0
            }
            for row in 0..<colHighH {
                highBuf[row] = col < colHigh[row].count ? colHigh[row][col] : 0
            }
            let column = try optimizer1D.inverseTransform53Optimized(
                lowpass: lowBuf, highpass: highBuf,
                boundaryExtension: boundaryExtension, uOrigin: uY)
            for row in 0..<min(column.count, outputH) {
                result[row][col] = column[row]
            }
        }

        return result
    }

    /// Parity-aware multi-level 2D inverse 5/3 DWT. Mirror of
    /// `AcceleratedDWT2D.forwardDecomposition53(...tileOriginX:tileOriginY:)`
    /// (v6-alpha3 step 2). Iterates from deepest decomposition
    /// level to shallowest, applying the parity-aware single-level
    /// 2D inverse at each step with the spec-correct LL canvas
    /// origin per ISO/IEC 15444-1 Eq. B-15.
    ///
    /// **Regression-safe**: when both starting origins are zero,
    /// every level's origin stays at (0, 0) (since `ceil(0/n) == 0`),
    /// so the parity-aware single-level inverse routes to the
    /// existing optimised fast path at every level — the multi-
    /// level output is byte-identical to the no-origin overload.
    /// Single-tile and 32-aligned multi-tile decode are zero-cost.
    ///
    /// `subbands` must be ordered DEEPEST-FIRST (matching the
    /// no-origin overload's input contract). The deepest LL is
    /// passed separately as `ll`/`llW`/`llH`.
    public func inverseTransformMultiLevel53(
        ll: [Int32], llW: Int, llH: Int,
        subbands: [(lh: [Int32], lhW: Int, lhH: Int,
                     hl: [Int32], hlW: Int, hlH: Int,
                     hh: [Int32], hhW: Int, hhH: Int)],
        tileOriginX tcx0: Int,
        tileOriginY tcy0: Int
    ) async throws -> (data: [Int32], width: Int, height: Int) {
        // Origin (0, 0) → existing fast path. Byte-identical output.
        if tcx0 == 0 && tcy0 == 0 {
            let r = await inverseTransformMultiLevel53(
                ll: ll, llW: llW, llH: llH, subbands: subbands)
            return r
        }

        guard !subbands.isEmpty else {
            return (data: ll, width: llW, height: llH)
        }

        let totalLevels = subbands.count

        // Convert flat LL → jagged for the slow parity-aware path.
        func flatToJagged(_ flat: [Int32], w: Int, h: Int) -> [[Int32]] {
            (0..<h).map { r in
                Array(flat[(r * w)..<(r * w + w)])
            }
        }
        func jaggedToFlat(_ jagged: [[Int32]]) -> (flat: [Int32], w: Int, h: Int) {
            let h = jagged.count
            let w = h > 0 ? jagged[0].count : 0
            var flat = [Int32](repeating: 0, count: w * h)
            for (r, row) in jagged.enumerated() {
                for (c, v) in row.enumerated() where c < w {
                    flat[r * w + c] = v
                }
            }
            return (flat, w, h)
        }

        var currentLL: [[Int32]] = flatToJagged(ll, w: llW, h: llH)

        // Iterate deepest first. At iteration k we invert
        // decomposition level (totalLevels - k); the produced LL
        // sits at canvas coordinates ceil(tcx0 / 2^(totalLevels - k - 1)).
        for (k, level) in subbands.enumerated() {
            let outputDepth = totalLevels - k - 1
            let denom = 1 << outputDepth
            let curUX = Self.ceilDivIntegerOrigin(tcx0, denom)
            let curUY = Self.ceilDivIntegerOrigin(tcy0, denom)

            let lh2D = flatToJagged(level.lh, w: level.lhW, h: level.lhH)
            let hl2D = flatToJagged(level.hl, w: level.hlW, h: level.hlH)
            let hh2D = flatToJagged(level.hh, w: level.hhW, h: level.hhH)

            currentLL = try await inverseTransform2DOptimized(
                ll: currentLL, lh: lh2D, hl: hl2D, hh: hh2D,
                boundaryExtension: .symmetric,
                uX: curUX, uY: curUY)
        }

        let (flat, w, h) = jaggedToFlat(currentLL)
        return (data: flat, width: w, height: h)
    }
}

// MARK: - 2D Optimised Transform (9/7 Irreversible)

/// Optimised 2D DWT operations for lossy (irreversible 9/7) decoding.
///
/// Uses flat contiguous buffers and in-place lifting to minimize heap
/// allocations and maximize cache locality. The column pass operates
/// directly on strided memory (no per-column temp arrays), and the row
/// pass processes contiguous memory for L1/L2 cache efficiency.
public struct J2KDWT2DOptimizer97: Sendable {
    /// Creates a new 9/7 DWT optimizer.
    public init() {}

    // MARK: - CDF 9/7 Lifting Constants

    private static let alpha = -1.586134342
    private static let beta  = -0.05298011854
    private static let gamma =  0.8829110762
    private static let delta =  0.4435068522
    private static let k     =  1.230174105
    private static let invK  =  1.0 / 1.230174105

    // MARK: - In-Place 1D Lifting (Strided)

    /// Performs inverse CDF 9/7 lifting in-place on interleaved even/odd
    /// samples stored at `base` with the given `stride`.
    ///
    /// On entry, `base[0], base[stride], base[2*stride], ...` hold the
    /// interleaved result of the vertical (or horizontal) pass:
    ///   positions 0,2,4,... = even (lowpass), 1,3,5,... = odd (highpass).
    ///
    /// On exit, the reconstructed signal is in the same locations.
    @inline(__always)
    private static func inverseLift97InPlace(
        _ base: UnsafeMutablePointer<Double>,
        evenCount: Int,
        oddCount: Int,
        stride s: Int,
        externalScratch: UnsafeMutablePointer<Double>
    ) {
        let n = evenCount + oddCount
        guard n > 1, oddCount > 0 else { return }
        #if canImport(Accelerate)
        if s == 1 && n >= 32 {
            var kVal = k; var iKVal = invK
            vDSP_vsmulD(base, 2, &kVal, base, 2, vDSP_Length(evenCount))
            vDSP_vsmulD(base + 1, 2, &iKVal, base + 1, 2, vDSP_Length(oddCount))
            let scratch = externalScratch
            // Undo update 2
            base[0] -= delta * 2.0 * base[1]
            if evenCount > 2 {
                let interiorCount = min(evenCount - 2, oddCount - 1)
                if interiorCount > 0 {
                    vDSP_vaddD(base + 1, 2, base + 3, 2, scratch, 1, vDSP_Length(interiorCount))
                    var d = -delta
                    vDSP_vsmaD(scratch, 1, &d, base + 2, 2, base + 2, 2, vDSP_Length(interiorCount))
                }
            }
            if evenCount > 1 {
                let i = evenCount - 1
                let leftOdd = base[(i * 2) - 1]
                let rightIdx = i * 2 + 1
                let rightOdd = rightIdx < n ? base[rightIdx] : base[(n - 1) | 1]
                base[i * 2] -= delta * (leftOdd + rightOdd)
            }
            // Undo predict 2
            if oddCount > 1 {
                let interiorCount = oddCount - 1
                vDSP_vaddD(base, 2, base + 2, 2, scratch, 1, vDSP_Length(interiorCount))
                var g = -gamma
                vDSP_vsmaD(scratch, 1, &g, base + 1, 2, base + 1, 2, vDSP_Length(interiorCount))
            }
            do {
                let i = oddCount - 1
                let leftEven = base[i * 2]
                let rightIdx = (i + 1) * 2
                let rightEven = rightIdx < n ? base[rightIdx] : base[(n - 1) & ~1]
                base[i * 2 + 1] -= gamma * (leftEven + rightEven)
            }
            // Undo update 1
            base[0] -= beta * 2.0 * base[1]
            if evenCount > 2 {
                let interiorCount = min(evenCount - 2, oddCount - 1)
                if interiorCount > 0 {
                    vDSP_vaddD(base + 1, 2, base + 3, 2, scratch, 1, vDSP_Length(interiorCount))
                    var b = -beta
                    vDSP_vsmaD(scratch, 1, &b, base + 2, 2, base + 2, 2, vDSP_Length(interiorCount))
                }
            }
            if evenCount > 1 {
                let i = evenCount - 1
                let leftOdd = base[(i * 2) - 1]
                let rightIdx = i * 2 + 1
                let rightOdd = rightIdx < n ? base[rightIdx] : base[(n - 1) | 1]
                base[i * 2] -= beta * (leftOdd + rightOdd)
            }
            // Undo predict 1
            if oddCount > 1 {
                let interiorCount = oddCount - 1
                vDSP_vaddD(base, 2, base + 2, 2, scratch, 1, vDSP_Length(interiorCount))
                var a = -alpha
                vDSP_vsmaD(scratch, 1, &a, base + 1, 2, base + 1, 2, vDSP_Length(interiorCount))
            }
            do {
                let i = oddCount - 1
                let leftEven = base[i * 2]
                let rightIdx = (i + 1) * 2
                let rightEven = rightIdx < n ? base[rightIdx] : base[(n - 1) & ~1]
                base[i * 2 + 1] -= alpha * (leftEven + rightEven)
            }
            return
        }
        #endif
        // Scalar fallback (strided or small)
        for i in 0..<evenCount { base[i &* 2 &* s] *= k }
        for i in 0..<oddCount  { base[(i &* 2 &+ 1) &* s] *= invK }
        base[0] -= delta * 2.0 * base[s]
        for i in 1..<evenCount {
            let leftOdd  = base[((i &* 2) &- 1) &* s]
            let rightIdx = i &* 2 &+ 1
            let rightOdd = rightIdx < n ? base[rightIdx &* s] : base[((n &- 1) | 1) &* s]
            base[i &* 2 &* s] -= delta * (leftOdd + rightOdd)
        }
        for i in 0..<oddCount {
            let leftEven  = base[i &* 2 &* s]
            let rightIdx  = (i &+ 1) &* 2
            let rightEven = rightIdx < n ? base[rightIdx &* s] : base[((n &- 1) & ~1) &* s]
            base[(i &* 2 &+ 1) &* s] -= gamma * (leftEven + rightEven)
        }
        base[0] -= beta * 2.0 * base[s]
        for i in 1..<evenCount {
            let leftOdd  = base[((i &* 2) &- 1) &* s]
            let rightIdx = i &* 2 &+ 1
            let rightOdd = rightIdx < n ? base[rightIdx &* s] : base[((n &- 1) | 1) &* s]
            base[i &* 2 &* s] -= beta * (leftOdd + rightOdd)
        }
        for i in 0..<oddCount {
            let leftEven  = base[i &* 2 &* s]
            let rightIdx  = (i &+ 1) &* 2
            let rightEven = rightIdx < n ? base[rightIdx &* s] : base[((n &- 1) & ~1) &* s]
            base[(i &* 2 &+ 1) &* s] -= alpha * (leftEven + rightEven)
        }
    }

    /// Convenience overload: allocates its own scratch for one-off calls (stride≠1 or small n).
    @inline(__always)
    private static func inverseLift97InPlace(
        _ base: UnsafeMutablePointer<Double>,
        evenCount: Int,
        oddCount: Int,
        stride s: Int
    ) {
        let n = evenCount + oddCount
        guard n > 1, oddCount > 0 else { return }
        if s == 1 && n >= 32 {
            // vDSP path: allocate scratch for this one-off call
            let scratch = UnsafeMutablePointer<Double>.allocate(capacity: n)
            defer { scratch.deallocate() }
            inverseLift97InPlace(base, evenCount: evenCount, oddCount: oddCount, stride: s,
                                 externalScratch: scratch)
        } else {
            // Scalar path: externalScratch is unused — pass base as harmless non-nil dummy
            inverseLift97InPlace(base, evenCount: evenCount, oddCount: oddCount, stride: s,
                                 externalScratch: base)
        }
    }

    // MARK: - Float Precision Constants

    private static let alphaF: Float = -1.586134342
    private static let betaF: Float  = -0.05298011854
    private static let gammaF: Float =  0.8829110762
    private static let deltaF: Float =  0.4435068522
    private static let kF: Float     =  1.230174105
    private static let invKF: Float  =  1.0 / 1.230174105

    // MARK: - In-Place 1D Lifting (Float, Stride=1, vDSP)

    /// Performs inverse CDF 9/7 lifting in-place on interleaved even/odd
    /// samples stored contiguously (stride=1). Uses vDSP for vectorized
    /// operations when available, providing ~2× throughput vs Double.
    /// Float variant with caller-supplied scratch (avoids per-call malloc for column loops).
    @inline(__always)
    private static func inverseLift97InPlaceFloat(
        _ base: UnsafeMutablePointer<Float>,
        evenCount: Int,
        oddCount: Int,
        stride s: Int,
        externalScratch: UnsafeMutablePointer<Float>
    ) {
        let n = evenCount + oddCount
        guard n > 1, oddCount > 0 else { return }
        #if canImport(Accelerate)
        if s == 1 && n >= 32 {
            var kVal = kF; var iKVal = invKF
            vDSP_vsmul(base, 2, &kVal, base, 2, vDSP_Length(evenCount))
            vDSP_vsmul(base + 1, 2, &iKVal, base + 1, 2, vDSP_Length(oddCount))
            let scratch = externalScratch
            base[0] -= deltaF * 2.0 * base[1]
            if evenCount > 2 {
                let ic = min(evenCount - 2, oddCount - 1)
                if ic > 0 {
                    vDSP_vadd(base + 1, 2, base + 3, 2, scratch, 1, vDSP_Length(ic))
                    var d = -deltaF; vDSP_vsma(scratch, 1, &d, base + 2, 2, base + 2, 2, vDSP_Length(ic))
                }
            }
            if evenCount > 1 {
                let i = evenCount - 1
                base[i*2] -= deltaF * (base[(i*2)-1] + (i*2+1 < n ? base[i*2+1] : base[(n-1)|1]))
            }
            if oddCount > 1 {
                let ic = oddCount - 1
                vDSP_vadd(base, 2, base + 2, 2, scratch, 1, vDSP_Length(ic))
                var g = -gammaF; vDSP_vsma(scratch, 1, &g, base + 1, 2, base + 1, 2, vDSP_Length(ic))
            }
            do {
                let i = oddCount - 1
                base[i*2+1] -= gammaF * (base[i*2] + ((i+1)*2 < n ? base[(i+1)*2] : base[(n-1) & ~1]))
            }
            base[0] -= betaF * 2.0 * base[1]
            if evenCount > 2 {
                let ic = min(evenCount - 2, oddCount - 1)
                if ic > 0 {
                    vDSP_vadd(base + 1, 2, base + 3, 2, scratch, 1, vDSP_Length(ic))
                    var b = -betaF; vDSP_vsma(scratch, 1, &b, base + 2, 2, base + 2, 2, vDSP_Length(ic))
                }
            }
            if evenCount > 1 {
                let i = evenCount - 1
                base[i*2] -= betaF * (base[(i*2)-1] + (i*2+1 < n ? base[i*2+1] : base[(n-1)|1]))
            }
            if oddCount > 1 {
                let ic = oddCount - 1
                vDSP_vadd(base, 2, base + 2, 2, scratch, 1, vDSP_Length(ic))
                var a = -alphaF; vDSP_vsma(scratch, 1, &a, base + 1, 2, base + 1, 2, vDSP_Length(ic))
            }
            do {
                let i = oddCount - 1
                base[i*2+1] -= alphaF * (base[i*2] + ((i+1)*2 < n ? base[(i+1)*2] : base[(n-1) & ~1]))
            }
            return
        }
        #endif
        for i in 0..<evenCount { base[i &* 2 &* s] *= kF }
        for i in 0..<oddCount  { base[(i &* 2 &+ 1) &* s] *= invKF }
        base[0] -= deltaF * 2.0 * base[s]
        for i in 1..<evenCount {
            let lo = base[((i*2)-1)*s]; let ri = i*2+1
            base[i*2*s] -= deltaF * (lo + (ri < n ? base[ri*s] : base[((n-1)|1)*s]))
        }
        for i in 0..<oddCount {
            let le = base[i*2*s]; let ri = (i+1)*2
            base[(i*2+1)*s] -= gammaF * (le + (ri < n ? base[ri*s] : base[((n-1) & ~1)*s]))
        }
        base[0] -= betaF * 2.0 * base[s]
        for i in 1..<evenCount {
            let lo = base[((i*2)-1)*s]; let ri = i*2+1
            base[i*2*s] -= betaF * (lo + (ri < n ? base[ri*s] : base[((n-1)|1)*s]))
        }
        for i in 0..<oddCount {
            let le = base[i*2*s]; let ri = (i+1)*2
            base[(i*2+1)*s] -= alphaF * (le + (ri < n ? base[ri*s] : base[((n-1) & ~1)*s]))
        }
    }

    @inline(__always)
    private static func inverseLift97InPlaceFloat(
        _ base: UnsafeMutablePointer<Float>,
        evenCount: Int,
        oddCount: Int,
        stride s: Int
    ) {
        let n = evenCount + oddCount
        guard n > 1, oddCount > 0 else { return }
        if s == 1 && n >= 32 {
            let scratch = UnsafeMutablePointer<Float>.allocate(capacity: n)
            defer { scratch.deallocate() }
            inverseLift97InPlaceFloat(base, evenCount: evenCount, oddCount: oddCount, stride: s,
                                      externalScratch: scratch)
            return
        }
        // Scalar/small path — externalScratch unused; pass base as harmless dummy
        inverseLift97InPlaceFloat(base, evenCount: evenCount, oddCount: oddCount, stride: s,
                                  externalScratch: base)
    }

    /// Separated-array inverse CDF 9/7 lifting (stride-1 vDSP — fully NEON vectorized).
    ///
    /// Operates on **pre-separated** low-frequency (`even`) and high-frequency (`odd`)
    /// arrays, avoiding the stride-2 gather/scatter pattern of the interleaved variant.
    /// All vDSP operations run at stride-1, enabling 4-wide NEON SIMD throughout.
    ///
    /// - Parameters:
    ///   - even: Low-pass samples (in-place). After return: even-indexed output.
    ///   - evenCount: Number of low-pass samples.
    ///   - odd: High-pass samples (in-place). After return: odd-indexed output.
    ///   - oddCount: Number of high-pass samples.
    ///   - scratch: Caller-provided temporary buffer of at least `evenCount + oddCount` Floats
    ///     (the scalar fallback for small n uses it as an interleave buffer).
    @inline(__always)
    private static func inverseLift97SeparatedInPlaceFloat(
        even: UnsafeMutablePointer<Float>, evenCount: Int,
        odd:  UnsafeMutablePointer<Float>, oddCount:  Int,
        scratch: UnsafeMutablePointer<Float>
    ) {
        guard evenCount > 0, oddCount > 0 else { return }

        #if canImport(Accelerate)
        if evenCount + oddCount >= 32 {
            // Undo scaling: all stride-1
            var kVal  = kF
            var iKVal = invKF
            vDSP_vsmul(even, 1, &kVal,  even, 1, vDSP_Length(evenCount))
            vDSP_vsmul(odd,  1, &iKVal, odd,  1, vDSP_Length(oddCount))

            // Undo update 2: even[i] -= delta * (odd[i-1] + odd[i])
            even[0] -= deltaF * 2.0 * odd[0]
            let iu2 = min(evenCount - 2, oddCount - 1)
            if iu2 > 0 {
                vDSP_vadd(odd, 1, odd + 1, 1, scratch, 1, vDSP_Length(iu2))
                var nd = -deltaF
                vDSP_vsma(scratch, 1, &nd, even + 1, 1, even + 1, 1, vDSP_Length(iu2))
            }
            if evenCount > 1 {
                let j = evenCount - 1
                even[j] -= deltaF * (odd[j - 1] + (j < oddCount ? odd[j] : odd[oddCount - 1]))
            }

            // Undo predict 2: odd[i] -= gamma * (even[i] + even[i+1])
            let ip2 = oddCount - 1
            if ip2 > 0 {
                vDSP_vadd(even, 1, even + 1, 1, scratch, 1, vDSP_Length(ip2))
                var ng = -gammaF
                vDSP_vsma(scratch, 1, &ng, odd, 1, odd, 1, vDSP_Length(ip2))
            }
            do {
                let i = oddCount - 1
                odd[i] -= gammaF * (even[i] + (i + 1 < evenCount ? even[i + 1] : even[evenCount - 1]))
            }

            // Undo update 1: even[i] -= beta * (odd[i-1] + odd[i])
            even[0] -= betaF * 2.0 * odd[0]
            let iu1 = min(evenCount - 2, oddCount - 1)
            if iu1 > 0 {
                vDSP_vadd(odd, 1, odd + 1, 1, scratch, 1, vDSP_Length(iu1))
                var nb = -betaF
                vDSP_vsma(scratch, 1, &nb, even + 1, 1, even + 1, 1, vDSP_Length(iu1))
            }
            if evenCount > 1 {
                let j = evenCount - 1
                even[j] -= betaF * (odd[j - 1] + (j < oddCount ? odd[j] : odd[oddCount - 1]))
            }

            // Undo predict 1: odd[i] -= alpha * (even[i] + even[i+1])
            let ip1 = oddCount - 1
            if ip1 > 0 {
                vDSP_vadd(even, 1, even + 1, 1, scratch, 1, vDSP_Length(ip1))
                var na = -alphaF
                vDSP_vsma(scratch, 1, &na, odd, 1, odd, 1, vDSP_Length(ip1))
            }
            do {
                let i = oddCount - 1
                odd[i] -= alphaF * (even[i] + (i + 1 < evenCount ? even[i + 1] : even[evenCount - 1]))
            }
            return
        }
        #endif

        // Scalar fallback for small n: delegate to the interleaved function via scratch
        let scrI = scratch    // reuse scratch as interleave buffer (needs even+odd elements)
        for i in 0..<evenCount { scrI[i &* 2]     = even[i] }
        for i in 0..<oddCount  { scrI[i &* 2 + 1] = odd[i]  }
        inverseLift97InPlaceFloat(scrI, evenCount: evenCount, oddCount: oddCount, stride: 1)
        for i in 0..<evenCount { even[i] = scrI[i &* 2]     }
        for i in 0..<oddCount  { odd[i]  = scrI[i &* 2 + 1] }
    }

    // MARK: - 2D Inverse Transform (Flat Buffer)

    /// Optimised 2D inverse transform for lossy decoding with CDF 9/7.
    ///
    /// Uses a single flat buffer for the entire reconstruction, with in-place
    /// lifting for both column and row passes. This eliminates the per-column
    /// and per-row temporary array allocations that dominated the previous
    /// implementation's overhead for multi-component images.
    ///
    /// - Parameters:
    ///   - ll: Low-low subband (Double precision).
    ///   - lh: Low-high subband (Double precision).
    ///   - hl: High-low subband (Double precision).
    ///   - hh: High-high subband (Double precision).
    ///   - boundaryExtension: Boundary extension mode.
    /// - Returns: Reconstructed 2D image in Double precision.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if subbands are invalid.
    public func inverseTransform2DOptimized97(
        ll: [[Double]],
        lh: [[Double]],
        hl: [[Double]],
        hh: [[Double]],
        boundaryExtension: J2KDWT1D.BoundaryExtension = .symmetric
    ) async throws -> [[Double]] {
        guard !ll.isEmpty else {
            throw J2KError.invalidParameter("LL subband cannot be empty")
        }
        if lh.isEmpty && hl.isEmpty && hh.isEmpty {
            return ll
        }

        let llH = ll.count
        let llW = ll[0].count
        let lhH = lh.count
        let hlW = hl.isEmpty ? 0 : hl[0].count
        let outH = llH + lhH
        let outW = llW + hlW

        // Use manually allocated buffer for shared mutable access across tasks.
        let bufSize = outH * outW
        let base = UnsafeMutablePointer<Double>.allocate(capacity: bufSize)
        base.initialize(repeating: 0.0, count: bufSize)
        defer {
            base.deinitialize(count: bufSize)
            base.deallocate()
        }

        // --- Step 1: Column IDWT ---
        // Place subbands into the flat buffer with even/odd interleaving:
        //   Even rows (0,2,4,...) come from LL/HL (low-freq vertical)
        //   Odd rows  (1,3,5,...) come from LH/HH (high-freq vertical)

        // Place LL (even rows, low-freq cols)
        for r in 0..<llH {
            let dstRow = r &* 2 &* outW
            for c in 0..<llW { base[dstRow &+ c] = ll[r][c] }
        }
        // Place LH (odd rows, low-freq cols)
        for r in 0..<lhH {
            let dstRow = (r &* 2 &+ 1) &* outW
            for c in 0..<min(llW, lh[r].count) { base[dstRow &+ c] = lh[r][c] }
        }
        // Place HL (even rows, high-freq cols)
        if hlW > 0 {
            let hlH = hl.count
            for r in 0..<hlH {
                let dstRow = r &* 2 &* outW + llW
                for c in 0..<min(hlW, hl[r].count) { base[dstRow &+ c] = hl[r][c] }
            }
        }
        // Place HH (odd rows, high-freq cols)
        if hlW > 0 {
            let hhH = hh.count
            for r in 0..<hhH {
                let dstRow = (r &* 2 &+ 1) &* outW + llW
                for c in 0..<min(hlW, hh[r].count) { base[dstRow &+ c] = hh[r][c] }
            }
        }

        // Column lifting: process each column in-place using stride = outW.
        let colCount = outW
        if colCount >= 8 {
            let safeBase = SendablePointer(base)
            let coreCount = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, colCount / coreCount)
            await withTaskGroup(of: Void.self) { group in
                for chunkStart in stride(from: 0, to: colCount, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, colCount)
                    group.addTask {
                        let base = safeBase.pointer
                        for col in chunkStart..<chunkEnd {
                            Self.inverseLift97InPlace(
                                base + col,
                                evenCount: llH,
                                oddCount: lhH,
                                stride: outW
                            )
                        }
                    }
                }
            }
        } else {
            for col in 0..<colCount {
                Self.inverseLift97InPlace(
                    base + col,
                    evenCount: llH,
                    oddCount: lhH,
                    stride: outW
                )
            }
        }

        // --- Step 2: Row IDWT ---
        // Each row now has [low-freq cols | high-freq cols].
        // Interleave and lift in-place.
        if outH >= 8 {
            let safeBase = SendablePointer(base)
            let coreCount = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, outH / coreCount)
            await withTaskGroup(of: Void.self) { group in
                for chunkStart in stride(from: 0, to: outH, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, outH)
                    group.addTask {
                        let base = safeBase.pointer
                        var tmp = [Double](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                        let rowScratch = UnsafeMutablePointer<Double>.allocate(capacity: outW)
                        defer { rowScratch.deallocate() }
                        tmp.withUnsafeMutableBufferPointer { tmpBuf in
                            let tp = tmpBuf.baseAddress!
                            for r in chunkStart..<chunkEnd {
                                let rowBase = base + r &* outW
                                cblas_dcopy(Int32(llW), rowBase, 1, tp, 2)
                                cblas_dcopy(Int32(hlW), rowBase + llW, 1, tp + 1, 2)
                                Self.inverseLift97InPlace(tp, evenCount: llW, oddCount: hlW,
                                                          stride: 1, externalScratch: rowScratch)
                                rowBase.update(from: tp, count: outW)
                            }
                        }
                    }
                }
            }
        } else {
            var tmp = [Double](unsafeUninitializedCapacity: outW) { _, s in s = outW }
            let rowScratch = UnsafeMutablePointer<Double>.allocate(capacity: outW)
            defer { rowScratch.deallocate() }
            tmp.withUnsafeMutableBufferPointer { tmpBuf in
                let tp = tmpBuf.baseAddress!
                for r in 0..<outH {
                    let rowBase = base + r &* outW
                    cblas_dcopy(Int32(llW), rowBase, 1, tp, 2)
                    cblas_dcopy(Int32(hlW), rowBase + llW, 1, tp + 1, 2)
                    Self.inverseLift97InPlace(tp, evenCount: llW, oddCount: hlW,
                                              stride: 1, externalScratch: rowScratch)
                    rowBase.update(from: tp, count: outW)
                }
            }
        }

        // Convert flat buffer back to [[Double]]
        var result = [[Double]](repeating: [], count: outH)
        for r in 0..<outH {
            result[r] = Array(UnsafeBufferPointer(start: base + r &* outW, count: outW))
        }
        return result
    }

    // MARK: - Flat-Buffer Multi-Level IDWT

    /// Performs a complete multi-level inverse CDF 9/7 DWT on flat subband data.
    ///
    /// Accepts subbands as flat `[Double]` arrays with explicit dimensions,
    /// avoiding all `[[Double]]` intermediate conversions. Performs all DWT
    /// levels in sequence, returning the final reconstructed image as a flat
    /// `[Double]` array in row-major order.
    ///
    /// - Parameters:
    ///   - ll: LL subband coefficients (flat, row-major).
    ///   - llW: Width of the LL subband.
    ///   - llH: Height of the LL subband.
    ///   - subbands: Array of (lh, hl, hh) subbands per level, ordered from
    ///     deepest level (smallest) to level 1 (largest). Each element is
    ///     `(lh: [Double], lhW: Int, lhH: Int, hl: [Double], hlW: Int, hlH: Int, hh: [Double], hhW: Int, hhH: Int)`.
    /// - Returns: Reconstructed image as flat `[Double]` array in row-major order,
    ///   along with the output width and height.
    public func inverseTransformMultiLevel97(
        ll: [Double], llW: Int, llH: Int,
        subbands: [(lh: [Double], lhW: Int, lhH: Int,
                     hl: [Double], hlW: Int, hlH: Int,
                     hh: [Double], hhW: Int, hhH: Int)]
    ) async -> (data: [Double], width: Int, height: Int) {
        guard !subbands.isEmpty else {
            return (data: ll, width: llW, height: llH)
        }

        // Keep LL in a raw pointer between levels to avoid intermediate
        // Swift Array copies. Only convert back to [Double] at the end.
        let initSize = llW * llH
        var currentBuf = UnsafeMutablePointer<Double>.allocate(capacity: initSize)
        ll.withUnsafeBufferPointer { src in
            currentBuf.initialize(from: src.baseAddress!, count: initSize)
        }
        var curW = llW
        var curH = llH
        let coreCount97 = ProcessInfo.processInfo.processorCount

        for level in subbands {
            let lhH = level.lhH
            let hlW = level.hlW
            let outH = curH + lhH
            let outW = curW + hlW

            // Allocate shared flat buffer for cross-task access
            let bufSize = outH * outW
            let base = UnsafeMutablePointer<Double>.allocate(capacity: bufSize)
            memset(base, 0, bufSize &* MemoryLayout<Double>.size)

            // Place LL (even rows, low-freq cols) from currentBuf — contiguous row copy
            for r in 0..<curH {
                memcpy(base + r * 2 * outW, currentBuf + r * curW,
                       curW &* MemoryLayout<Double>.size)
            }

            // Free previous buffer now that LL data has been placed
            currentBuf.deallocate()

            // Place LH (odd rows, low-freq cols)
            let lhW = level.lhW
            level.lh.withUnsafeBufferPointer { lhBuf in
                for r in 0..<lhH {
                    let count = min(curW, lhW)
                    memcpy(base + (r * 2 + 1) * outW, lhBuf.baseAddress! + r * lhW,
                           count &* MemoryLayout<Double>.size)
                }
            }

            // Place HL (even rows, high-freq cols)
            if hlW > 0 {
                let hlH = level.hlH
                let srcHlW = level.hlW
                level.hl.withUnsafeBufferPointer { hlBuf in
                    for r in 0..<hlH {
                        let count = min(hlW, srcHlW)
                        memcpy(base + r * 2 * outW + curW, hlBuf.baseAddress! + r * srcHlW,
                               count &* MemoryLayout<Double>.size)
                    }
                }
            }

            // Place HH (odd rows, high-freq cols)
            if hlW > 0 {
                let hhW = level.hhW
                let hhH = level.hhH
                level.hh.withUnsafeBufferPointer { hhBuf in
                    for r in 0..<hhH {
                        let count = min(hlW, hhW)
                        memcpy(base + (r * 2 + 1) * outW + curW, hhBuf.baseAddress! + r * hhW,
                               count &* MemoryLayout<Double>.size)
                    }
                }
            }

            // Column lifting via transpose: converts stride=outW to stride=1,
            // enabling the vDSP NEON fast path for all column lifting passes.
            let colCount = outW
            let evenCount = curH
            if outH >= 32 && colCount >= 8 {
                // Transpose outH×outW → outW×outH so columns become contiguous rows.
                let tBuf = UnsafeMutablePointer<Double>.allocate(capacity: bufSize)
                vDSP_mtransD(base, 1, tBuf, 1, vDSP_Length(outH), vDSP_Length(outW))
                let safeT = SendablePointer(tBuf)
                let chunkSizeT = max(1, colCount / coreCount97)
                await withTaskGroup(of: Void.self) { group in
                    for chunkStart in stride(from: 0, to: colCount, by: chunkSizeT) {
                        let chunkEnd = min(chunkStart + chunkSizeT, colCount)
                        group.addTask {
                            let tp = safeT.pointer
                            // One scratch buffer per task, reused across all columns in chunk.
                            let colScratch = UnsafeMutablePointer<Double>.allocate(capacity: outH)
                            defer { colScratch.deallocate() }
                            for col in chunkStart..<chunkEnd {
                                Self.inverseLift97InPlace(
                                    tp + col &* outH,
                                    evenCount: evenCount,
                                    oddCount: lhH,
                                    stride: 1,
                                    externalScratch: colScratch
                                )
                            }
                        }
                    }
                }
                vDSP_mtransD(tBuf, 1, base, 1, vDSP_Length(outW), vDSP_Length(outH))
                tBuf.deallocate()
            } else {
                for col in 0..<colCount {
                    Self.inverseLift97InPlace(
                        base + col,
                        evenCount: evenCount,
                        oddCount: lhH,
                        stride: outW
                    )
                }
            }

            // Row lifting
            let lowCount = curW
            if outH >= 8 {
                let safeBase = SendablePointer(base)
                let chunkSize = max(1, outH / coreCount97)
                await withTaskGroup(of: Void.self) { group in
                    for chunkStart in stride(from: 0, to: outH, by: chunkSize) {
                        let chunkEnd = min(chunkStart + chunkSize, outH)
                        group.addTask {
                            let base = safeBase.pointer
                            // Allocate tmp (interleave buffer) and rowScratch once per task.
                            // tmp is fully overwritten by cblas_dcopy before any read — skip zero-init.
                            var tmp = [Double](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                            let rowScratch = UnsafeMutablePointer<Double>.allocate(capacity: outW)
                            defer { rowScratch.deallocate() }
                            tmp.withUnsafeMutableBufferPointer { tmpBuf in
                                let tp = tmpBuf.baseAddress!
                                for r in chunkStart..<chunkEnd {
                                    let rowBase = base + r &* outW
                                    cblas_dcopy(Int32(lowCount), rowBase, 1, tp, 2)
                                    cblas_dcopy(Int32(hlW), rowBase + lowCount, 1, tp + 1, 2)
                                    Self.inverseLift97InPlace(tp, evenCount: lowCount, oddCount: hlW,
                                                              stride: 1, externalScratch: rowScratch)
                                    rowBase.update(from: tp, count: outW)
                                }
                            }
                        }
                    }
                }
            } else {
                var tmp = [Double](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                let rowScratch = UnsafeMutablePointer<Double>.allocate(capacity: outW)
                defer { rowScratch.deallocate() }
                tmp.withUnsafeMutableBufferPointer { tmpBuf in
                    let tp = tmpBuf.baseAddress!
                    for r in 0..<outH {
                        let rowBase = base + r &* outW
                        cblas_dcopy(Int32(lowCount), rowBase, 1, tp, 2)
                        cblas_dcopy(Int32(hlW), rowBase + lowCount, 1, tp + 1, 2)
                        Self.inverseLift97InPlace(tp, evenCount: lowCount, oddCount: hlW,
                                                  stride: 1, externalScratch: rowScratch)
                        rowBase.update(from: tp, count: outW)
                    }
                }
            }

            // Keep raw buffer for next level (no Array copy)
            currentBuf = base
            curW = outW
            curH = outH
        }

        // Convert final buffer to [Double] only at the end
        let finalSize = curW * curH
        let result = Array(UnsafeBufferPointer(start: currentBuf, count: finalSize))
        currentBuf.deallocate()

        return (data: result, width: curW, height: curH)
    }

    // MARK: - Float-Precision Multi-Level IDWT (Optimised)

    /// Performs a complete multi-level inverse CDF 9/7 DWT using Float precision.
    ///
    /// Float32 provides 2× SIMD throughput and 2× cache efficiency compared to
    /// Double, while providing sufficient precision for 16-bit images through 5+
    /// DWT levels. This implementation also eliminates intermediate Swift Array
    /// copies between levels by keeping data in raw pointer buffers.
    ///
    /// - Parameters:
    ///   - ll: LL subband coefficients (flat, row-major, Double).
    ///   - llW: Width of the LL subband.
    ///   - llH: Height of the LL subband.
    ///   - subbands: Per-level subbands ordered deepest to shallowest.
    /// - Returns: Reconstructed image as flat `[Double]` array with width/height.
    public func inverseTransformMultiLevel97Float(
        ll: [Double], llW: Int, llH: Int,
        subbands: [(lh: [Double], lhW: Int, lhH: Int,
                     hl: [Double], hlW: Int, hlH: Int,
                     hh: [Double], hhW: Int, hhH: Int)]
    ) async -> (data: [Double], width: Int, height: Int) {
        guard !subbands.isEmpty else {
            return (data: ll, width: llW, height: llH)
        }

        // Convert initial LL to Float and keep in raw buffer to avoid
        // intermediate Array copies between DWT levels.
        let initSize = llW * llH
        var currentBuf = UnsafeMutablePointer<Float>.allocate(capacity: initSize)
        ll.withUnsafeBufferPointer { src in
            vDSP_vdpsp(src.baseAddress!, 1, currentBuf, 1, vDSP_Length(initSize))
        }
        var currentBufSize = initSize
        var curW = llW
        var curH = llH
        let coreCountF = ProcessInfo.processInfo.processorCount

        for level in subbands {
            let lhH = level.lhH
            let lhW = level.lhW
            let hlW = level.hlW
            let hlH = level.hlH
            let hhW = level.hhW
            let hhH = level.hhH
            let outH = curH + lhH
            let outW = curW + hlW
            let bufSize = outH * outW

            let base = UnsafeMutablePointer<Float>.allocate(capacity: bufSize)
            // Skip the bufSize-wide memset when every output position will be
            // written by the four placement loops below — the common case for
            // dyadic dimensions. Only zero-fill when a source dimension is
            // smaller than the destination (asymmetric halving on odd parents).
            let allCellsWritten = curW == lhW &&
                                  curH == hlH && lhH == hhH &&
                                  hlW > 0 && hlW == hhW
            if !allCellsWritten {
                memset(base, 0, bufSize &* MemoryLayout<Float>.size)
            }

            // Place LL (even rows, low-freq cols) from currentBuf using memcpy per row
            for r in 0..<curH {
                (base + r &* 2 &* outW).initialize(from: currentBuf + r &* curW, count: curW)
            }

            // Free previous buffer
            currentBuf.deallocate()

            // Place LH (odd rows, low-freq cols) — vectorised Double→Float conversion
            level.lh.withUnsafeBufferPointer { src in
                for r in 0..<lhH {
                    let count = min(curW, lhW)
                    let dst = base + (r * 2 + 1) * outW
                    vDSP_vdpsp(src.baseAddress! + r * lhW, 1, dst, 1, vDSP_Length(count))
                }
            }

            // Place HL (even rows, high-freq cols) — vectorised Double→Float conversion
            if hlW > 0 {
                let srcHlW = level.hlW
                level.hl.withUnsafeBufferPointer { src in
                    for r in 0..<hlH {
                        let count = min(hlW, srcHlW)
                        let dst = base + r * 2 * outW + curW
                        vDSP_vdpsp(src.baseAddress! + r * srcHlW, 1, dst, 1, vDSP_Length(count))
                    }
                }
            }

            // Place HH (odd rows, high-freq cols) — vectorised Double→Float conversion
            if hlW > 0 {
                level.hh.withUnsafeBufferPointer { src in
                    for r in 0..<hhH {
                        let count = min(hlW, hhW)
                        let dst = base + (r * 2 + 1) * outW + curW
                        vDSP_vdpsp(src.baseAddress! + r * hhW, 1, dst, 1, vDSP_Length(count))
                    }
                }
            }

            // Column lifting via transpose: stride=outW → stride=1 for vDSP NEON path.
            //
            // Three-way dispatch tuned on Med-512 lossy (where IDWT overhead vs
            // OpenJPEG was the dominant deficit):
            //  • ≥256: parallel transpose + task-group column lifts. Big enough
            //    that task-spawn overhead is amortised by the stride-1 NEON win.
            //  • ≥64 but <256: serial transpose + stride-1 lifts (still NEON-
            //    friendly, but no task-group overhead). Sweet spot for 64–128
            //    levels of small images.
            //  • <64: direct stride-outW scalar lifts — fastest for tiny levels
            //    where any transpose is pure waste.
            let colCount = outW
            let evenCount = curH
            if outH >= 256 && colCount >= 64 {
                let tBuf = UnsafeMutablePointer<Float>.allocate(capacity: bufSize)
                vDSP_mtrans(base, 1, tBuf, 1, vDSP_Length(outH), vDSP_Length(outW))
                let safeT = SendablePointer(tBuf)
                let chunkSizeT = max(1, colCount / coreCountF)
                await withTaskGroup(of: Void.self) { group in
                    for chunkStart in stride(from: 0, to: colCount, by: chunkSizeT) {
                        let chunkEnd = min(chunkStart + chunkSizeT, colCount)
                        group.addTask {
                            let tp = safeT.pointer
                            let colScratch = UnsafeMutablePointer<Float>.allocate(capacity: outH)
                            defer { colScratch.deallocate() }
                            for col in chunkStart..<chunkEnd {
                                Self.inverseLift97InPlaceFloat(
                                    tp + col &* outH,
                                    evenCount: evenCount,
                                    oddCount: lhH,
                                    stride: 1,
                                    externalScratch: colScratch
                                )
                            }
                        }
                    }
                }
                vDSP_mtrans(tBuf, 1, base, 1, vDSP_Length(outW), vDSP_Length(outH))
                tBuf.deallocate()
            } else if outH >= 64 && colCount >= 16 {
                let tBuf = UnsafeMutablePointer<Float>.allocate(capacity: bufSize)
                defer { tBuf.deallocate() }
                vDSP_mtrans(base, 1, tBuf, 1, vDSP_Length(outH), vDSP_Length(outW))
                let colScratch = UnsafeMutablePointer<Float>.allocate(capacity: outH)
                defer { colScratch.deallocate() }
                for col in 0..<colCount {
                    Self.inverseLift97InPlaceFloat(
                        tBuf + col &* outH,
                        evenCount: evenCount,
                        oddCount: lhH,
                        stride: 1,
                        externalScratch: colScratch
                    )
                }
                vDSP_mtrans(tBuf, 1, base, 1, vDSP_Length(outW), vDSP_Length(outH))
            } else {
                for col in 0..<colCount {
                    Self.inverseLift97InPlaceFloat(
                        base + col,
                        evenCount: evenCount,
                        oddCount: lhH,
                        stride: outW
                    )
                }
            }

            // Row lifting — mirror the column threshold: only parallel dispatch
            // when there's enough work per core to amortise task-spawn cost.
            let lowCount = curW
            if outH >= 256 {
                let safeBase = SendablePointer(base)
                let chunkSize = max(1, outH / coreCountF)
                await withTaskGroup(of: Void.self) { group in
                    for chunkStart in stride(from: 0, to: outH, by: chunkSize) {
                        let chunkEnd = min(chunkStart + chunkSize, outH)
                        group.addTask {
                            let base = safeBase.pointer
                            // tmp and scrBuf are fully overwritten before any read — skip zero-init.
                            // scrBuf must hold the full interleaved row (evenCount + oddCount == outW)
                            // because the scalar-path lifter uses it as an interleave buffer.
                            var tmp    = [Float](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                            var scrBuf = [Float](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                            tmp.withUnsafeMutableBufferPointer { tmpBuf in
                                scrBuf.withUnsafeMutableBufferPointer { scBuf in
                                    let tp = tmpBuf.baseAddress!
                                    let sc = scBuf.baseAddress!
                                    for r in chunkStart..<chunkEnd {
                                        let rowBase = base + r &* outW
                                        Self.inverseLift97SeparatedInPlaceFloat(
                                            even: rowBase, evenCount: lowCount,
                                            odd: rowBase + lowCount, oddCount: hlW,
                                            scratch: sc)
                                        cblas_scopy(Int32(lowCount), rowBase, 1, tp, 2)
                                        cblas_scopy(Int32(hlW), rowBase + lowCount, 1, tp + 1, 2)
                                        rowBase.update(from: tp, count: outW)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                // scrBuf must hold the full interleaved row (evenCount + oddCount == outW)
                // because the scalar-path lifter uses it as an interleave buffer.
                var tmp    = [Float](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                var scrBuf = [Float](unsafeUninitializedCapacity: outW) { _, s in s = outW }
                tmp.withUnsafeMutableBufferPointer { tmpBuf in
                    scrBuf.withUnsafeMutableBufferPointer { scBuf in
                        let tp = tmpBuf.baseAddress!
                        let sc = scBuf.baseAddress!
                        for r in 0..<outH {
                            let rowBase = base + r &* outW
                            Self.inverseLift97SeparatedInPlaceFloat(
                                even: rowBase, evenCount: lowCount,
                                odd: rowBase + lowCount, oddCount: hlW,
                                scratch: sc)
                            cblas_scopy(Int32(lowCount), rowBase, 1, tp, 2)
                            cblas_scopy(Int32(hlW), rowBase + lowCount, 1, tp + 1, 2)
                            rowBase.update(from: tp, count: outW)
                        }
                    }
                }
            }

            // Keep raw buffer for next level (no Array copy)
            currentBuf = base
            currentBufSize = bufSize
            curW = outW
            curH = outH
        }

        // Convert final Float buffer to [Double] for pipeline compatibility.
        // All elements written by vDSP_vspdp before any read — skip zero-init.
        var result = [Double](unsafeUninitializedCapacity: currentBufSize) { _, s in s = currentBufSize }
        #if canImport(Accelerate)
        vDSP_vspdp(currentBuf, 1, &result, 1, vDSP_Length(currentBufSize))
        #else
        for i in 0..<currentBufSize { result[i] = Double(currentBuf[i]) }
        #endif
        currentBuf.deallocate()

        return (data: result, width: curW, height: curH)
    }
}
