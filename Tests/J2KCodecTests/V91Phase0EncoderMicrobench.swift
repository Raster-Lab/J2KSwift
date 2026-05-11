// V91Phase0EncoderMicrobench.swift
//
// v9.1 Path B Phase 0 — per-engine cost-per-call microbench for the
// HT block-encoder hot path.
//
// Decouples the inner-loop timing from the full pipeline noise.
// Establishes a baseline ns/call for each of the three emission
// engines + processQuad classification, so the corpus call counts
// captured by `J2KHTEntropyEncoderProfile` translate directly to a
// per-stage CPU breakdown:
//
//     per_stage_cpu = count × ns/call
//
// Methodology:
//
//   1. Time each engine's `encode()` in a tight loop with realistic
//      argument distributions (fixture-derived where possible).
//   2. Refresh the engine state periodically so we never run off the
//      end of the in-memory output buffers.
//   3. Report median-of-N wall ns/call.
//
// Targets:
//   - HTMagSgnEncoderConformant.encode(codeword:count:) at width
//     {3, 8, 14, 20} — corpus avg appears to cluster at ~10-14 bits.
//   - HTMELEncoderConformant.encode(eventIsOne:) — binary state
//     machine, 0/1 events.
//   - HTReverseBitEmitterConformant.encode(codeword:count:) at width
//     {3, 5, 8, 12} — VLC quad tuples are 3-12 bits, UVLC pre/suf
//     parts are typically 1-7 bits.
//   - processQuad classification — covered by the existing v8.6
//     forward DWT bench / SIMD probe rather than re-bench-ing here.

import XCTest
@testable import J2KCodec

final class V91Phase0EncoderMicrobench: XCTestCase {

    /// Time HTMagSgnEncoderConformant.encode in a tight loop.
    private func benchMagSgn(
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
        var enc = HTMagSgnEncoderConformant()
        // Pre-grow the output buffer so we don't pay realloc tax in
        // the timed loop. Each call appends ~bitsPerCall/8 bytes;
        // double for safety.
        let _bytesPerCall = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, 1_000_000 / _bytesPerCall)
        let mask: UInt32 = bitsPerCall >= 32 ? ~UInt32(0)
                                             : ((UInt32(1) << bitsPerCall) - 1)
        let codeword: UInt32 = 0x5A5A_5A5A & mask

        // Anti-DCE sink: forces the compiler to keep the encode() side
        // effects observable (the byte buffer growth).
        var sink: UInt32 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            enc.encode(codeword: codeword, count: bitsPerCall)
            sink &+= codeword
            i &+= 1
            if i % resetEvery == 0 {
                enc.reset()
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt32.max - 1)
        return Double(dt) / Double(iterations)
    }

    /// Time HTMELEncoderConformant.encode in a tight loop.
    /// `eventOneRatio` is the fraction of encode calls that pass true
    /// (corpus typical: ~20-40% on lossless 5/3).
    private func benchMEL(
        eventOneRatio: Double,
        iterations: Int
    ) -> Double {
        var enc = HTMELEncoderConformant()
        let resetEvery = 100_000
        // Deterministic event sequence: round-robin based on threshold.
        let oneThreshold = Int(eventOneRatio * 1000)

        var sink: Int = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            let isOne = ((i * 1664525 + 1013904223) & 0x3FF) < oneThreshold
            enc.encode(eventIsOne: isOne)
            sink &+= isOne ? 1 : 0
            i &+= 1
            if i % resetEvery == 0 {
                enc.reset()
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, Int.min)
        return Double(dt) / Double(iterations)
    }

    /// Time HTReverseBitEmitterConformant.encode in a tight loop.
    private func benchReverseVLC(
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
        var enc = HTReverseBitEmitterConformant()
        let _bytesPerCall = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, 1_000_000 / _bytesPerCall)
        let mask: Int = bitsPerCall >= 32 ? Int.max
                                          : ((1 << bitsPerCall) - 1)
        let codeword: Int = 0x5A5A & mask

        var sink: Int = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            enc.encode(codeword: codeword, count: bitsPerCall)
            sink &+= codeword
            i &+= 1
            if i % resetEvery == 0 {
                enc.reset()
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, Int.min)
        return Double(dt) / Double(iterations)
    }

    func testMagSgnEncodeNsPerCall_PerWidth() throws {
        let runs = 5
        let iterations = 200_000
        struct Row { let bits: Int; let nsPerCall: Double }
        var rows: [Row] = []

        for bits in [3, 8, 14, 20] {
            // Warmup.
            _ = benchMagSgn(bitsPerCall: bits, iterations: iterations)

            var samples: [Double] = []
            for _ in 0..<runs {
                samples.append(benchMagSgn(bitsPerCall: bits, iterations: iterations))
            }
            samples.sort()
            rows.append(Row(bits: bits, nsPerCall: samples[runs / 2]))
        }

        print("=== v9.1 Phase 0 — HTMagSgnEncoderConformant.encode ns/call ===")
        print("|  bits/call  |  ns/call  |  M calls/sec  |")
        print("|------------:|----------:|--------------:|")
        for r in rows {
            print(String(format: "| %11d | %9.2f | %13.2f |",
                r.bits, r.nsPerCall, 1000.0 / r.nsPerCall))
        }
    }

    func testMELEncodeNsPerCall() throws {
        let runs = 5
        let iterations = 1_000_000
        struct Row { let oneRatio: Double; let nsPerCall: Double }
        var rows: [Row] = []

        for ratio in [0.1, 0.3, 0.5] {
            _ = benchMEL(eventOneRatio: ratio, iterations: iterations)
            var samples: [Double] = []
            for _ in 0..<runs {
                samples.append(benchMEL(eventOneRatio: ratio, iterations: iterations))
            }
            samples.sort()
            rows.append(Row(oneRatio: ratio, nsPerCall: samples[runs / 2]))
        }

        print("=== v9.1 Phase 0 — HTMELEncoderConformant.encode ns/call ===")
        print("|  one-ratio  |  ns/call  |  M calls/sec  |")
        print("|------------:|----------:|--------------:|")
        for r in rows {
            print(String(format: "| %11.2f | %9.2f | %13.2f |",
                r.oneRatio, r.nsPerCall, 1000.0 / r.nsPerCall))
        }
    }

    func testReverseVLCEncodeNsPerCall_PerWidth() throws {
        let runs = 5
        let iterations = 200_000
        struct Row { let bits: Int; let nsPerCall: Double }
        var rows: [Row] = []

        for bits in [3, 5, 8, 12] {
            _ = benchReverseVLC(bitsPerCall: bits, iterations: iterations)
            var samples: [Double] = []
            for _ in 0..<runs {
                samples.append(benchReverseVLC(bitsPerCall: bits, iterations: iterations))
            }
            samples.sort()
            rows.append(Row(bits: bits, nsPerCall: samples[runs / 2]))
        }

        print("=== v9.1 Phase 0 — HTReverseBitEmitterConformant.encode ns/call ===")
        print("|  bits/call  |  ns/call  |  M calls/sec  |")
        print("|------------:|----------:|--------------:|")
        for r in rows {
            print(String(format: "| %11d | %9.2f | %13.2f |",
                r.bits, r.nsPerCall, 1000.0 / r.nsPerCall))
        }
    }
}
