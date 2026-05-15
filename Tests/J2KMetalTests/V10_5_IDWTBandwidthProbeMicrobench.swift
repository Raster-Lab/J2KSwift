// V10_5_IDWTBandwidthProbeMicrobench.swift
//
// v10.5-research — Phase 0 microbench for the M2-residual MG/DX gap.
//
// Question: at the largest decomposition level on MG-class buffers
// (3520×4784 Int32 ≈ 67 MB), does the current `inverseTransform2DOptimized`
// column-lift path pay a memory-bandwidth tax that a stride-outW
// column-block lift could elide?
//
// Production path per level (`inverseTransformMultiLevel53`):
//   1. transpose `base` (outH × outW) → `tBuf` (outW × outH)   → 2 × 67 MB
//   2. parallel column-block lift on `tBuf` (stride=1)         → 2 × 67 MB
//   3. untranspose `tBuf` → `base`                              → 2 × 67 MB
//   Total: ~6 × 67 MB = 402 MB per IDWT pass on level-1 of MG.
//
// Probe path (this file): keep `base` row-major, lift columns directly
// with stride=outW, but block N adjacent columns together so each row
// touch is cache-line-friendly (N × 4 bytes per row × outH rows fits in
// L2). Total: ~2 × 67 MB = 134 MB. 3× less DRAM traffic.
//
// Trade-off: strided lifting touches `prev_odd / cur_even / next_odd`
// rows three times per `i` step. With column-block traversal, the
// three rows are reused across N cols → L1 hit. Without blocking,
// each col would re-load the same rows.
//
// This is a probe — no production wiring yet. If the microbench shows
// ≥3 ms savings on a single MG-class IDWT pass, we'll integrate the
// path behind a `J2K_IDWT_COLBLOCK=1` flag and run the warm bench.

import Foundation
import XCTest
@testable import J2KCodec
@testable import J2KCore

final class V10_5_IDWTBandwidthProbeMicrobench: XCTestCase {

    /// Marker — column-block lift in row-major order, no transpose.
    ///
    /// Mirrors `J2KDWT2DOptimizer.inverseLift53InPlace` math step-for-
    /// step, but processes N adjacent columns together while walking
    /// rows top-to-bottom. Each row visit reads/writes N cells (stride
    /// 1 within the block) — a 64-byte cache line covers 16 Int32s,
    /// so N=16 is the natural minimum for cache-line efficiency.
    ///
    /// `base` is laid out row-major with `outW` cells per row and
    /// `outH = 2*evenCount` (or +1 odd-parity) rows. Columns
    /// [cStart, cEnd) are lifted in-place using the same 5/3 inverse
    /// filter math as `inverseLift53InPlace`.
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
            let rowHP0 = base + outW         // row 1 (odd)
            let rowEV0 = base                // row 0 (even)
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
            let oddRow = base + (i &* 2 &+ 1) &* outW
            let evenLRow = base + (i &* 2) &* outW
            let evenRRow = base + (i &* 2 &+ 2) &* outW
            for c in cStart..<cEnd {
                oddRow[c] = oddRow[c] &+ ((evenLRow[c] &+ evenRRow[c]) >> 1)
            }
        }
        // Last odd: right boundary — even[oddCount] = even[evenCount-1]
        let evenRightIdx = min((lastOdd &+ 1) &* 2, (evenCount &- 1) &* 2)
        let lastOddRow = base + (lastOdd &* 2 &+ 1) &* outW
        let evenLRow = base + (lastOdd &* 2) &* outW
        let evenRRow = base + evenRightIdx &* outW
        for c in cStart..<cEnd {
            lastOddRow[c] = lastOddRow[c] &+ ((evenLRow[c] &+ evenRRow[c]) >> 1)
        }
    }

    /// Reference path — exact replica of production
    /// `inverseTransformMultiLevel53` column-lift sub-block (transpose
    /// + parallel column lift + untranspose), inlined so we can A/B
    /// just the inner section.
    static func referenceColLift_TransposeAndLift(
        _ base: UnsafeMutablePointer<Int32>,
        outH: Int, outW: Int,
        evenRows: Int, oddRows: Int
    ) async {
        let bufSize = outH &* outW
        let tBuf = UnsafeMutablePointer<Int32>.allocate(capacity: bufSize)
        defer { tBuf.deallocate() }
        J2KDWT2DOptimizer.transposeInt32(src: base, dst: tBuf, rows: outH, cols: outW)
        let safeT = SendablePointer(tBuf)
        let coreCount = ProcessInfo.processInfo.processorCount
        let colChunk = max(1, outW / coreCount)
        await withTaskGroup(of: Void.self) { group in
            for chunkStart in stride(from: 0, to: outW, by: colChunk) {
                let chunkEnd = min(chunkStart + colChunk, outW)
                group.addTask {
                    let tp = safeT.pointer
                    for col in chunkStart..<chunkEnd {
                        J2KDWT2DOptimizer.inverseLift53InPlace(
                            tp + col &* outH, evenCount: evenRows, oddCount: oddRows, stride: 1
                        )
                    }
                }
            }
        }
        J2KDWT2DOptimizer.transposeInt32(src: tBuf, dst: base, rows: outW, cols: outH)
    }

    /// Probe path — parallel column-block lift directly on row-major
    /// `base`, no transpose. Each task processes a contiguous range
    /// of columns; column-block N within each task is 16 cells
    /// (one Int32 cache line).
    static func probeColLift_RowMajorBlock(
        _ base: UnsafeMutablePointer<Int32>,
        outH: Int, outW: Int,
        evenRows: Int, oddRows: Int,
        colBlockSize: Int = 16
    ) async {
        let safeBase = SendablePointer(base)
        let coreCount = ProcessInfo.processInfo.processorCount
        let colChunk = max(colBlockSize, outW / coreCount)
        await withTaskGroup(of: Void.self) { group in
            for chunkStart in stride(from: 0, to: outW, by: colChunk) {
                let chunkEnd = min(chunkStart + colChunk, outW)
                group.addTask {
                    let b = safeBase.pointer
                    var c = chunkStart
                    while c < chunkEnd {
                        let cEnd = min(c + colBlockSize, chunkEnd)
                        inverseLift53ColBlock(
                            b, cStart: c, cEnd: cEnd, outW: outW,
                            evenCount: evenRows, oddCount: oddRows)
                        c += colBlockSize
                    }
                }
            }
        }
    }

    /// Fill a buffer with a deterministic Int32 pattern matching
    /// what the IDWT placement stage hands to the column-lift pass:
    /// alternating low/high rows × low/high columns.
    private static func fillSyntheticBuffer(
        _ p: UnsafeMutablePointer<Int32>,
        outH: Int, outW: Int
    ) {
        var s: UInt64 = 0xfeed_face_dead_beef
        for r in 0..<outH {
            for c in 0..<outW {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                p[r &* outW &+ c] = Int32(truncatingIfNeeded: s >> 32)
            }
        }
    }

    /// Time both paths on synthetic MG/DX/PX-class buffers.
    /// Verifies bit-exact equivalence first, then takes the median
    /// of N runs per path.
    func testColumnLiftMicrobench_MG_DX_PX_Scaffolds() async throws {
        // (outH, outW, label) — these match the level-1 (largest)
        // pass of an MG/DX/PX inverse 5/3 with 5 decomposition levels.
        let cases: [(Int, Int, String)] = [
            (4784, 3520, "MG-class 3520×4784 (level-1)"),
            (4784, 3518, "MG-mid 3518×4784 (level-1)"),
            (3056, 2544, "DX-large 2544×3056 (level-1)"),
            (2288, 2800, "DX-mid 2800×2288 (level-1)"),
            (1316, 2812, "PX-large 2812×1316 (level-1)"),
            // Plus a "level-2" sanity check — quarter size buffer.
            (2392, 1760, "MG level-2 1760×2392"),
        ]

        let n = 7
        let warmups = 2

        print("=== v10.5 IDWT column-lift microbench (M2 release) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Runs: \(n)")
        print("")
        print("| Buffer | bytes | prod ms (median) | probe ms (median) | Δ ms | speedup | parity |")
        print("|---|---:|---:|---:|---:|---:|---|")

        for (outH, outW, label) in cases {
            let evenRows = outH / 2 + (outH & 1)
            let oddRows = outH / 2
            let bufSize = outH * outW
            let bytes = bufSize * MemoryLayout<Int32>.size

            // Allocate reference + probe buffers.
            let baseProd = UnsafeMutablePointer<Int32>.allocate(capacity: bufSize)
            let baseProbe = UnsafeMutablePointer<Int32>.allocate(capacity: bufSize)
            defer {
                baseProd.deallocate()
                baseProbe.deallocate()
            }

            // Same synthetic data in both.
            Self.fillSyntheticBuffer(baseProd, outH: outH, outW: outW)
            for i in 0..<bufSize { baseProbe[i] = baseProd[i] }

            // Parity — run one pass through each and compare.
            await Self.referenceColLift_TransposeAndLift(
                baseProd, outH: outH, outW: outW,
                evenRows: evenRows, oddRows: oddRows)
            await Self.probeColLift_RowMajorBlock(
                baseProbe, outH: outH, outW: outW,
                evenRows: evenRows, oddRows: oddRows)
            var firstMismatch = -1
            for i in 0..<bufSize where baseProd[i] != baseProbe[i] {
                firstMismatch = i
                break
            }
            let parityOK = firstMismatch < 0

            // Warm-ups.
            for _ in 0..<warmups {
                Self.fillSyntheticBuffer(baseProd, outH: outH, outW: outW)
                await Self.referenceColLift_TransposeAndLift(
                    baseProd, outH: outH, outW: outW,
                    evenRows: evenRows, oddRows: oddRows)
                Self.fillSyntheticBuffer(baseProbe, outH: outH, outW: outW)
                await Self.probeColLift_RowMajorBlock(
                    baseProbe, outH: outH, outW: outW,
                    evenRows: evenRows, oddRows: oddRows)
            }

            // Timed runs.
            var prodTimes: [Double] = []
            var probeTimes: [Double] = []
            for _ in 0..<n {
                Self.fillSyntheticBuffer(baseProd, outH: outH, outW: outW)
                let t0 = Date()
                await Self.referenceColLift_TransposeAndLift(
                    baseProd, outH: outH, outW: outW,
                    evenRows: evenRows, oddRows: oddRows)
                prodTimes.append(Date().timeIntervalSince(t0) * 1000)

                Self.fillSyntheticBuffer(baseProbe, outH: outH, outW: outW)
                let t1 = Date()
                await Self.probeColLift_RowMajorBlock(
                    baseProbe, outH: outH, outW: outW,
                    evenRows: evenRows, oddRows: oddRows)
                probeTimes.append(Date().timeIntervalSince(t1) * 1000)
            }
            let prodMed = prodTimes.sorted()[n / 2]
            let probeMed = probeTimes.sorted()[n / 2]
            let delta = prodMed - probeMed
            let speedup = prodMed / probeMed

            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.2f | %.2f× | %@ |",
                         label, bytes, prodMed, probeMed, delta, speedup,
                         parityOK ? "✓" : "✗ at \(firstMismatch)"))
            XCTAssertTrue(parityOK,
                "Probe column-lift result diverged from production at index \(firstMismatch) for \(label)")
        }

        print("")
        print("Reading:")
        print("  prod = current `inverseTransformMultiLevel53` column-lift path")
        print("         (transpose 67 MB → tBuf, parallel stride-1 lift, untranspose).")
        print("  probe = parallel multi-col block lift in row-major order, no transpose.")
        print("  ≥3 ms savings on MG/DX would be a v7.4-style acceptance gate.")
        print("  Bandwidth math: prod ≈ 6× buffer, probe ≈ 2× buffer per pass.")
    }
}
