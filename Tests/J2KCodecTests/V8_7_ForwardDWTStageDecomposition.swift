// V8_7_ForwardDWTStageDecomposition.swift
//
// v8.7 Phase 0 — decompose the forward 2D 5/3 DWT cost. v8.6 Phase
// 0 measured the inner `forward53_1D` lifting at 0.37 ns/sample,
// which projects to only ~6 ms of the v8.4 stage breakdown's
// 333 ms accumulated DWT CPU. The other ~98% must be elsewhere:
// candidates are the column-pass transpose, the row-pass copy,
// strip dispatch overhead, or the multi-level / multi-tile setup.
//
// This bench measures `forward2D_53Pooled` end-to-end at DX
// dimensions — single-tile, single-level — to anchor a per-call
// cost. Subtracting the projected inner-lifting CPU gives the
// "everything else" budget that an algorithmic redesign could
// attack. Then we measure JUST the transpose loop (the suspected
// dominant cost) in isolation.

#if os(macOS)

import XCTest
@testable import J2KCodec

final class V8_7_ForwardDWTStageDecomposition: XCTestCase {

    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Generate DX-sized signed-Int16-range Int32 input pattern.
    private func makeDXInput(width: Int, height: Int) -> [Int32] {
        var rng = SplitMix64(seed: 0xCAFE_F00D)
        var out = [Int32](repeating: 0, count: width * height)
        for i in 0..<out.count {
            let x = Int32(truncatingIfNeeded: rng.next() & 0xFFFF)
            out[i] = x - 32768
        }
        return out
    }

    @inline(never)
    private func errlog(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }

    /// End-to-end `forward2D_53Pooled` for one DX-shape tile, single
    /// level. Reports per-call wall ns and projects to a 5-level pyramid.
    func testFullForward2DAt_DX_SingleLevel() async {
        // DX 2800x2288 single-level forward 5/3 transform.
        let width = 2800
        let height = 2288
        let data = makeDXInput(width: width, height: height)
        let pool = AcceleratedDWT2D.DWT53ScratchPool(
            maxWidth: width, maxHeight: height)

        // Warm-up (also primes the page-in / first-level allocations).
        _ = await AcceleratedDWT2D.forward2D_53Pooled(
            data: data, width: width, height: height, pool: pool)

        let runs = 5
        var samplesMs: [Double] = []
        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            _ = await AcceleratedDWT2D.forward2D_53Pooled(
                data: data, width: width, height: height, pool: pool)
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samplesMs.append(Double(dt) / 1_000_000.0)
        }
        samplesMs.sort()
        let medianMs = samplesMs[runs / 2]
        let pixels = width * height

        // Per-pixel cost.
        let nsPerPixel = medianMs * 1_000_000.0 / Double(pixels)

        errlog("")
        errlog("=== v8.7 Phase 0 — forward2D_53Pooled cost decomposition ===")
        errlog("DX 2800x2288 single-level (concurrent column pass + scalar row pass):")
        errlog("  median wall:   \(String(format: "%7.2f", medianMs)) ms")
        errlog("  per-pixel:     \(String(format: "%7.2f", nsPerPixel)) ns/pixel (wall)")
        errlog("")

        // 5-level pyramid: each finer level is 1/4 of L0 (halve in
        // each dimension). Total work = L0 * (1 + 1/4 + 1/16 + 1/64 + 1/256)
        //                              = L0 * 341/256 ~= L0 * 1.332
        let pyramidFactor = 1.0 + 0.25 + 0.0625 + 0.015625 + 0.00390625
        let projected5LevelMs = medianMs * pyramidFactor
        errlog("Projection to DX 5-level forward DWT (single tile):")
        errlog("  pyramid factor:    \(String(format: "%.3f", pyramidFactor))x")
        errlog("  projected wall:    \(String(format: "%7.2f", projected5LevelMs)) ms")
        errlog("  v8.4 measured:        27.10 ms (DWT wall)")
        errlog("")
    }

    /// Bench JUST the column-pass transpose-in pattern. The
    /// production code does:
    ///   for row in 0..<height {
    ///     for c in 0..<cols { stripIn[c*height + row] = src[row*width + colStrip + c] }
    ///   }
    /// — a strided write into stripIn (column-major) from a strided
    /// read of src (row-major). Suspected dominant non-lifting cost.
    func testColumnPassTransposeIn_PerByte() {
        let height = 2288
        let stripWidth = 8  // matches DWT53ScratchPool.stripWidth
        let width = stripWidth   // single-strip iso-bench

        let src = UnsafeMutablePointer<Int32>.allocate(capacity: width * height)
        let stripIn = UnsafeMutablePointer<Int32>.allocate(capacity: stripWidth * height)
        defer {
            src.deallocate()
            stripIn.deallocate()
        }
        // Initialise to a deterministic pattern.
        var rng = SplitMix64(seed: 0xDEAD_BEEF)
        for i in 0..<(width * height) {
            src[i] = Int32(truncatingIfNeeded: rng.next() & 0xFFFF) - 32768
        }

        // Warm-up.
        for row in 0..<height {
            for c in 0..<stripWidth {
                stripIn[c * height + row] = src[row * width + c]
            }
        }

        let runs = 5
        let iterations = 50
        var samples: [Double] = []
        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            for _ in 0..<iterations {
                for row in 0..<height {
                    for c in 0..<stripWidth {
                        stripIn[c * height + row] = src[row * width + c]
                    }
                }
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / Double(iterations))
        }
        samples.sort()
        let nsPerCall = samples[runs / 2]
        let cellsPerCall = stripWidth * height
        let nsPerCell = nsPerCall / Double(cellsPerCall)

        errlog("=== v8.7 Phase 0 — column-pass transpose-in per-cell cost ===")
        errlog("8-wide x 2288-tall strip (single strip iso-bench):")
        errlog("  ns/transpose-in call:  \(String(format: "%9.0f", nsPerCall))")
        errlog("  cells per call:        \(cellsPerCall)")
        errlog("  ns/cell:               \(String(format: "%6.2f", nsPerCell))")
        errlog("")

        // Project to DX. DX L0 column pass:
        //   numStrips = ceil(2800/8) = 350
        //   per strip = stripWidth * height = 8 * 2288 = 18304 cells
        //   total cells (column transpose-in only): 350 * 18304 = 6.4M cells
        // Plus transpose-out (stripOut -> dst): another 6.4M cells.
        // 5-level pyramid factor 1.332x = 17M cells across all levels for
        // the column pass alone (in + out).
        let dxL0CellsInOut = 2 * 350 * stripWidth * height  // 12.8M
        let dxAllLevelCells = Double(dxL0CellsInOut) * 1.332
        let projectedAccMs = dxAllLevelCells * nsPerCell / 1_000_000.0
        errlog("Projection to DX 5-level forward DWT (column pass transpose only):")
        errlog("  cells across pyramid:  \(String(format: "%.0fM", dxAllLevelCells / 1_000_000))")
        errlog("  projected acc CPU:     \(String(format: "%6.1f", projectedAccMs)) ms")
        errlog("  v8.4 stage total:      333 ms (acc)")
        errlog("  transpose share:       \(String(format: "%5.1f", projectedAccMs / 333.0 * 100)) %% of DWT stage")
        errlog("")

        // If transpose share is ~30% or more, an algorithmic redesign
        // that eliminates the transpose (e.g. SIMD4 column-major
        // lifting that processes 4 columns in parallel without
        // explicit gather/scatter) could clear the 3 ms wall threshold:
        //   target acc savings: ~30% * 333 ms = ~100 ms acc / 12.3 = 8.1 ms wall.
        let parallelism = 12.3
        let projectedWallMs = projectedAccMs / parallelism
        errlog("If redesign eliminates transpose entirely:")
        errlog("  projected wall savings:  \(String(format: "%4.2f", projectedWallMs)) ms")
        errlog(projectedWallMs >= 3.0
               ? "  => >= 3 ms threshold MET. Phase 1A justified."
               : "  => < 3 ms threshold. Wash; close.")
    }
}

#endif
