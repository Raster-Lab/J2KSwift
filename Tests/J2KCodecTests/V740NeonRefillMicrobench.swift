// V740NeonRefillMicrobench.swift
//
// v7.4 NEON refill microbench — scalar vs batched A/B at the
// `HTMagSgnDecoderConformant.read` level. Reuses Phase 1a's
// methodology: synthetic byte stream with realistic 0xFF density,
// timed loops over read(count:) at each width.

import XCTest
@testable import J2KCodec

final class V740NeonRefillMicrobench: XCTestCase {

    private func makeMagSgnBytes(byteCount: Int, seed: UInt64) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        var out = [UInt8]()
        out.reserveCapacity(byteCount)
        var lastWasFF = false
        for _ in 0..<byteCount {
            var b = UInt8(truncatingIfNeeded: rng.next() & 0xFF)
            if lastWasFF { b &= 0x7F }
            out.append(b)
            lastWasFF = (b == 0xFF)
        }
        return out
    }

    private func benchRead(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
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
        XCTAssertNotEqual(sink, UInt64.max - 1)
        return Double(dt) / Double(iterations)
    }

    func testRefill_ScalarVsBatched_PerWidth() throws {
        let bytes = makeMagSgnBytes(byteCount: 4 * 1024 * 1024, seed: 0xC0FFEE_C0FFEE)
        let runs = 5
        let iterations = 200_000

        let widths: [(String, Int)] = [
            ("3 bits  (sparse)",         3),
            ("7 bits  (typical-VLC)",    7),
            ("14 bits (DX corpus avg)", 14),
            ("32 bits (max width)",     32),
        ]

        let prev = HTMagSgnDecoderConformant.neonRefillEnabled
        defer { HTMagSgnDecoderConformant.neonRefillEnabled = prev }

        print("=== v7.4 MagSgn refill microbench (median of \(runs)) ===")
        print("Buffer: \(bytes.count) bytes; iterations: \(iterations) per cell")
        print()
        print("| width | scalar ns/call | batched ns/call | batched Δ | speedup |")
        print("|---|---:|---:|---:|---:|")

        for (label, w) in widths {
            HTMagSgnDecoderConformant.neonRefillEnabled = false
            var scalarSamples: [Double] = []
            for _ in 0..<runs {
                scalarSamples.append(benchRead(bytes: bytes, bitsPerCall: w, iterations: iterations))
            }
            scalarSamples.sort()
            let scalar = scalarSamples[runs / 2]

            HTMagSgnDecoderConformant.neonRefillEnabled = true
            var batchedSamples: [Double] = []
            for _ in 0..<runs {
                batchedSamples.append(benchRead(bytes: bytes, bitsPerCall: w, iterations: iterations))
            }
            batchedSamples.sort()
            let batched = batchedSamples[runs / 2]

            let delta = (batched - scalar) / scalar * 100.0
            let speedup = scalar / batched
            print(String(format: "| %@ | %.2f | %.2f | %+.1f %% | %.2f× |",
                label, scalar, batched, delta, speedup))
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
