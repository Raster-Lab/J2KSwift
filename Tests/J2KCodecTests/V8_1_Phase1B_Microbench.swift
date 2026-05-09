// V8_1_Phase1B_Microbench.swift
//
// v8.1 Phase 1B microbench. Operates on the PRODUCTION
// `HTMagSgnDecoderConformant` struct with `swarRefill8Enabled`
// toggled, vs the v7.4-default behaviour. The Phase 1A bench
// measured a prototype struct; Phase 1B re-measures the
// integrated production struct to confirm that the field-cached
// flag pattern + 128-bit accumulator preserves the prototype's
// 1.37× speedup at corpus density.
//
// If the production numbers match Phase 1A's prototype within
// ±10 %, Phase 2 is justified. If they don't (i.e. the flag-cached
// branch costs significantly more than the prototype's
// unconditional shift), the win is smaller and Phase 3 may not
// clear ≥ 3 ms DX.

import XCTest
@testable import J2KCodec

final class V8_1_Phase1B_Microbench: XCTestCase {

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
                b = UInt8(truncatingIfNeeded: rng.next() & 0x7F)
                lastWasFF = false
            } else if rng.next() < threshold {
                b = 0xFF
                lastWasFF = true
            } else {
                b = UInt8(truncatingIfNeeded: rng.next() & 0xFF)
                if b == 0xFF { b = 0xFE }
                lastWasFF = false
            }
            out.append(b)
        }
        return out
    }

    private func benchAt(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int,
        useSwar8: Bool
    ) -> Double {
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        defer { HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8 }
        HTMagSgnDecoderConformant.swarRefill8Enabled = useSwar8

        let bytesNeeded = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, bytes.count / bytesNeeded / 2)
        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        var sink: UInt64 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            sink &+= UInt64(dec.read(count: bitsPerCall))
            i &+= 1
            if i % resetEvery == 0 {
                dec = HTMagSgnDecoderConformant(bytes: bytes)
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt64.max - 1)
        return Double(dt) / Double(iterations)
    }

    func testProductionFlagToggle_FFDensitySweep_14bit() {
        let runs = 5
        let iterations = 200_000
        let byteCount = 4 * 1024 * 1024
        let densities: [Double] = [0.0, 0.004, 0.01, 0.05, 0.10, 0.25]

        print("=== v8.1 Phase 1B production-integrate FF-density sweep (median of \(runs)) ===")
        print("Buffer: \(byteCount) bytes; iterations: \(iterations) per cell; 14-bit reads")
        print()
        print("| target FF % | flag-OFF ns | flag-ON ns | Δ | speedup |")
        print("|---|---:|---:|---:|---:|")

        for density in densities {
            let bytes = makeBytes(
                byteCount: byteCount, ffProbability: density, seed: 0xC0FFEE_C0FFEE)

            var offSamples: [Double] = []
            for _ in 0..<runs {
                offSamples.append(benchAt(
                    bytes: bytes, bitsPerCall: 14, iterations: iterations,
                    useSwar8: false))
            }
            offSamples.sort()
            let off = offSamples[runs / 2]

            var onSamples: [Double] = []
            for _ in 0..<runs {
                onSamples.append(benchAt(
                    bytes: bytes, bitsPerCall: 14, iterations: iterations,
                    useSwar8: true))
            }
            onSamples.sort()
            let on = onSamples[runs / 2]

            let delta = (on - off) / off * 100.0
            let speedup = off / on
            print(String(format: "| %.1f | %.2f | %.2f | %+.1f %% | %.2fx |",
                density * 100.0, off, on, delta, speedup))
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
