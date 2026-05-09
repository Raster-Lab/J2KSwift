// V8_1_PrefixScanPhase0Bench.swift
//
// v8.1 Phase 0 — measurement-first characterisation of the
// existing v7.4 SWAR-batched MagSgn refill across a controlled
// FF-density sweep. Pure measurement: no production-code changes,
// no prototype variants, no algorithmic redesign yet.
//
// Goal: produce the data that will decide whether v8.1's
// "bit-parallel prefix-scan on chained-unstuff state" workstream
// has a measurable lever to attack.
//
// The v7.4 release-notes claim says the SWAR fast-path hits ~99 %
// of batches at corpus-typical FF density (~0.4 %). This bench
// verifies that empirically and quantifies how the per-call cost
// degrades as FF density rises — which directly bounds the upper
// limit of any slow-path improvement.
//
// Three measurement axes:
//   (1) FF density: 0 % (no FFs at all), 0.4 % (corpus typical),
//       1 %, 5 %, 10 %, 25 %. The FF-boundary stuff bit makes
//       50 %+ unrepresentable in a valid stream.
//   (2) Read width: 3, 7, 14, 32 bits — same as v7.4 microbench
//       so the scalar-vs-batched ratio is comparable to the v7.4
//       baseline at density 0.4 %.
//   (3) Variant: scalar reference vs v7.4 SWAR-batched.
//
// Decision rule for whether v8.1 Phase 1 (prototype implementation)
// is justified:
//   - If batched perf degrades by < 5 % from density 0 % to 10 %,
//     the chained-unstuff state is already cheap; further work is
//     unlikely to clear v7.4's ≥ 3 ms DX A/B threshold. Document
//     the wash and redirect.
//   - If batched perf degrades by ≥ 20 % at density ≥ 5 %, the
//     slow-path cost is meaningful; Phase 1 should prototype either
//     (a) wider SWAR batches (8/16 byte, with 128-bit accumulator)
//     or (b) NEON prefix-scan slow path.
//   - In between: marginal; weigh against the measurement-wash
//     risk before Phase 1.

import XCTest
@testable import J2KCodec

final class V8_1_PrefixScanPhase0Bench: XCTestCase {

    /// Generates a byte stream with a controlled probability that
    /// any given byte is 0xFF. The stuff-bit constraint
    /// ("the byte after a 0xFF must have its high bit cleared")
    /// is enforced so the stream is a valid MagSgn encoding.
    private func makeBytes(
        byteCount: Int,
        ffProbability: Double,
        seed: UInt64
    ) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        var out = [UInt8]()
        out.reserveCapacity(byteCount)
        let threshold = UInt64(Double(UInt64.max) * ffProbability)
        var lastWasFF = false
        for _ in 0..<byteCount {
            var b: UInt8
            if lastWasFF {
                // Stuff-bit: high bit must be 0 → not 0xFF.
                b = UInt8(truncatingIfNeeded: rng.next() & 0x7F)
                lastWasFF = false
            } else if rng.next() < threshold {
                b = 0xFF
                lastWasFF = true
            } else {
                b = UInt8(truncatingIfNeeded: rng.next() & 0xFF)
                if b == 0xFF { b = 0xFE }   // keep density honest
                lastWasFF = false
            }
            out.append(b)
        }
        return out
    }

    /// Counts the actual realised FF density of a generated stream
    /// — what we ASKED for vs what the stuff-bit constraint LET
    /// us deliver. Reported in the table for ground truth.
    private func realisedFFDensity(_ bytes: [UInt8]) -> Double {
        var ffs = 0
        for b in bytes where b == 0xFF { ffs += 1 }
        return Double(ffs) / Double(bytes.count)
    }

    private func benchRead(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
        let bytesNeededPerIteration = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, bytes.count / bytesNeededPerIteration / 2)
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
        XCTAssertNotEqual(sink, UInt64.max - 1)
        return Double(dt) / Double(iterations)
    }

    /// Per-density A/B at fixed read width = 14 bits (DX corpus
    /// average). This is the headline cell — the "does v8.1 have
    /// a lever" decision rests on the slope here.
    func testRefill_FFDensitySweep_14bitReads() throws {
        let runs = 5
        let iterations = 200_000
        let byteCount = 4 * 1024 * 1024
        let densities: [Double] = [0.0, 0.004, 0.01, 0.05, 0.10, 0.25]

        let prev = HTMagSgnDecoderConformant.neonRefillEnabled
        defer { HTMagSgnDecoderConformant.neonRefillEnabled = prev }

        print("=== v8.1 Phase 0 — FF-density sweep at 14-bit reads (median of \(runs)) ===")
        print("Buffer: \(byteCount) bytes; iterations: \(iterations) per cell")
        print("Read width: 14 bits (DX corpus average per V740NeonRefillMicrobench)")
        print()
        print("| target FF % | realised FF % | scalar ns/call | batched ns/call | speedup | batched Δ vs density-0 |")
        print("|---|---:|---:|---:|---:|---:|")

        var batchedAtZero: Double? = nil
        for target in densities {
            let bytes = makeBytes(
                byteCount: byteCount,
                ffProbability: target,
                seed: 0xC0FFEE_C0FFEE)
            let realised = realisedFFDensity(bytes)

            HTMagSgnDecoderConformant.neonRefillEnabled = false
            var scalarSamples: [Double] = []
            for _ in 0..<runs {
                scalarSamples.append(
                    benchRead(bytes: bytes, bitsPerCall: 14, iterations: iterations))
            }
            scalarSamples.sort()
            let scalar = scalarSamples[runs / 2]

            HTMagSgnDecoderConformant.neonRefillEnabled = true
            var batchedSamples: [Double] = []
            for _ in 0..<runs {
                batchedSamples.append(
                    benchRead(bytes: bytes, bitsPerCall: 14, iterations: iterations))
            }
            batchedSamples.sort()
            let batched = batchedSamples[runs / 2]

            if batchedAtZero == nil { batchedAtZero = batched }
            let speedup = scalar / batched
            let degradation = (batched - (batchedAtZero ?? batched))
                / (batchedAtZero ?? 1.0) * 100.0

            print(String(format: "| %.1f | %.3f | %.2f | %.2f | %.2fx | %+.1f %% |",
                target * 100.0, realised * 100.0,
                scalar, batched, speedup, degradation))
        }
    }

    /// Width sweep at corpus-typical density (0.4 %). Confirms the
    /// v7.4 microbench numbers against the v8.1 baseline machine.
    /// Anchor for the FF-density sweep above.
    func testRefill_WidthSweep_AtCorpusDensity() throws {
        let runs = 5
        let iterations = 200_000
        let byteCount = 4 * 1024 * 1024
        let bytes = makeBytes(
            byteCount: byteCount, ffProbability: 0.004, seed: 0xC0FFEE_C0FFEE)
        let realised = realisedFFDensity(bytes)

        let widths: [(String, Int)] = [
            ("3 bits",       3),
            ("7 bits",       7),
            ("14 bits",     14),
            ("32 bits",     32),
        ]

        let prev = HTMagSgnDecoderConformant.neonRefillEnabled
        defer { HTMagSgnDecoderConformant.neonRefillEnabled = prev }

        print("=== v8.1 Phase 0 — width sweep at corpus FF density (median of \(runs)) ===")
        print("Buffer: \(byteCount) bytes; realised FF density: \(String(format: "%.3f %%", realised * 100))")
        print("Iterations: \(iterations) per cell")
        print()
        print("| width | scalar ns | batched ns | speedup |")
        print("|---|---:|---:|---:|")

        for (label, w) in widths {
            HTMagSgnDecoderConformant.neonRefillEnabled = false
            var scalarSamples: [Double] = []
            for _ in 0..<runs {
                scalarSamples.append(
                    benchRead(bytes: bytes, bitsPerCall: w, iterations: iterations))
            }
            scalarSamples.sort()
            let scalar = scalarSamples[runs / 2]

            HTMagSgnDecoderConformant.neonRefillEnabled = true
            var batchedSamples: [Double] = []
            for _ in 0..<runs {
                batchedSamples.append(
                    benchRead(bytes: bytes, bitsPerCall: w, iterations: iterations))
            }
            batchedSamples.sort()
            let batched = batchedSamples[runs / 2]

            let speedup = scalar / batched
            print(String(format: "| %@ | %.2f | %.2f | %.2fx |",
                label, scalar, batched, speedup))
        }
    }
}

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
