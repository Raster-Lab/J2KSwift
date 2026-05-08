// V730Phase1aMagSgnMicrobench.swift
//
// v7.3.0 Phase 1a — standalone microbench for `HTMagSgnDecoderConformant.read`.
// Decouples the inner-loop timing from the full pipeline noise.
// Establishes the baseline cost-per-call at realistic bit widths
// (the Phase 0 probe measured average width ≈ 14 bits on DX) so
// Phase 1b's SIMD port has a quantitative speedup target.
//
// Methodology:
//
//   1. Build a synthetic MagSgn byte stream with realistic
//      `0xFF` density (~0.4 % of bytes — matches the DX 4x4 corpus
//      sample where ~5 in 1024 bytes are 0xFF triggering unstuff).
//      Buffer size is large enough that the decoder doesn't run off
//      the end during the timed loop.
//   2. Time `read(count: w)` invocations in a tight loop for each
//      width w in {3, 7, 14, 32}. Each width gets `iterations` calls
//      so the loop amortises Swift call overhead.
//   3. Report median-of-5 wall ns/call.
//
// Phase 0 finding: DX has 1.95 M MagSgn reads × 14.28 bits avg →
// ~28 MB of bit-reads per decode. Phase 1b's NEON refill port aims
// for ~4× speedup on the per-call cost; this test is the gate.

import XCTest
@testable import J2KCodec

final class V730Phase1aMagSgnMicrobench: XCTestCase {

    /// Build a MagSgn-shape byte buffer of `byteCount` bytes. ~1 in
    /// 256 bytes is `0xFF` so the unstuff path fires at realistic
    /// density.
    private func makeMagSgnBytes(byteCount: Int, seed: UInt64) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        var out = [UInt8]()
        out.reserveCapacity(byteCount)
        var lastWasFF = false
        for _ in 0..<byteCount {
            var b = UInt8(truncatingIfNeeded: rng.next() & 0xFF)
            // Per the MagSgn convention: if the previous byte was
            // `0xFF`, the next byte's high bit is reserved as a 0
            // stuff bit. Producing a corpus-shape stream means we
            // mask that bit off rather than letting it be random
            // (otherwise the decoder produces undefined bits).
            if lastWasFF { b &= 0x7F }
            out.append(b)
            lastWasFF = (b == 0xFF)
        }
        return out
    }

    /// Time `read(count:)` in a tight loop. Returns ns per call.
    /// Refreshes the decoder when it would run off the end of the
    /// stream (re-initialises with the same byte buffer).
    private func benchRead(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
        // The buffer must hold at least `iterations × bitsPerCall / 8`
        // bytes so the decoder never refills past the end during
        // measurement. We re-initialise periodically just in case.
        let bytesNeededPerIteration = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, bytes.count / bytesNeededPerIteration)

        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        var sink: UInt64 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            let v = dec.read(count: bitsPerCall)
            sink &+= UInt64(v)
            i &+= 1
            if i % resetEvery == 0 {
                dec = HTMagSgnDecoderConformant(bytes: bytes)
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        // Anti-DCE: ensure `sink` participates in observable program
        // state so the optimiser doesn't elide the read calls.
        XCTAssertNotEqual(sink, UInt64.max - 1) // unlikely sentinel
        return Double(dt) / Double(iterations)
    }

    func testMagSgnReadThroughput_PerWidth() throws {
        // 4 MB of MagSgn bytes — enough that even at w=3 the decoder
        // doesn't refill from end-of-stream during the timed loop.
        let bytes = makeMagSgnBytes(byteCount: 4 * 1024 * 1024, seed: 0xC0FFEE_C0FFEE)
        let runs = 5
        let iterations = 200_000

        struct Cell {
            let label: String
            let bitsPerCall: Int
            let median: Double
        }
        let widths: [(String, Int)] = [
            ("3 bits  (sparse)",    3),
            ("7 bits  (typical-VLC-cwd)", 7),
            ("14 bits (DX corpus avg)", 14),
            ("32 bits (max width)",  32),
        ]

        print("=== v7.3.0 Phase 1a — HTMagSgnDecoderConformant.read microbench ===")
        print("Buffer: \(bytes.count) bytes, iterations: \(iterations) per cell, n = \(runs)")
        print()
        print("| width             | ns/call (median) | M reads/sec | bits/sec |")
        print("|---|---:|---:|---:|")

        var rows: [Cell] = []
        for (label, w) in widths {
            var samples: [Double] = []
            for _ in 0..<runs {
                samples.append(benchRead(
                    bytes: bytes, bitsPerCall: w, iterations: iterations))
            }
            samples.sort()
            let median = samples[runs / 2]
            rows.append(Cell(label: label, bitsPerCall: w, median: median))

            let mReadsPerSec = 1e9 / median / 1_000_000
            let bitsPerSec = 1e9 / median * Double(w) / 1_000_000_000  // Gb/s
            print(String(format: "| %@ | %.2f | %.2f | %.2f Gbit/s |",
                label, median, mReadsPerSec, bitsPerSec))
        }

        // Cross-reference with Phase 0 finding: DX decode = 1.947 M
        // MagSgn reads × ~14 bits avg. At the 14-bit row's ns/call,
        // total wall in MagSgn alone = ns/call × 1.947 M / 1e6 ms.
        let dxRow = rows.first(where: { $0.bitsPerCall == 14 })!
        let dxTotalReadCalls = 1_947_335.0
        let dxMagsgnMs = dxRow.median * dxTotalReadCalls / 1_000_000.0
        print()
        print(String(format: "Extrapolation: DX 4x4 has 1 947 335 MagSgn reads at avg 14.28 bits."))
        print(String(format: "At %.2f ns/call, that's %.2f ms of pure MagSgn `read` work per decode.",
            dxRow.median, dxMagsgnMs))
        print(String(format: "(DX total decode wall is ~60 ms, so MagSgn read is ~%.0f%% of total wall.)",
            dxMagsgnMs / 60.0 * 100))
    }
}

// MARK: - Deterministic RNG

/// Tiny SplitMix64 — deterministic, no Foundation `arc4random` /
/// `Random` system-seed dependency. Used so the microbench's input
/// data is bit-identical run-to-run.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
