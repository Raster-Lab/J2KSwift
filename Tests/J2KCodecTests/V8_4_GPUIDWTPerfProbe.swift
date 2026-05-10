// V8_4_GPUIDWTPerfProbe.swift
//
// v8.4 — perf probe for the v8.2 routing fix lift candidate.
// The v8.2 fix forces CPU IDWT when batched-entropy short-circuit
// is active. v8.3 made the GPU multi-tile-per-tile IDWT correct.
// This probe asks: now that GPU IDWT is bug-fixed, does
// LIFTING the v8.2 fix produce a wall-time win on the DX
// 2800×2288 fixture (auto planner = 2x2 = 1.6 M per tile, above
// the 1 MP GPU-IDWT threshold)?
//
// Three legs measured:
//   A. Default (v8.2 fix ON, CPU IDWT)
//   B. v8.2 fix bypassed (GPU IDWT for batched-entropy path)
//   C. _multiTileBatchedEntropyEnabled OFF (per-tile path —
//      goes through fused-from-codeblocks GPU batch already)
//
// If B beats A by ≥ 3 ms, the v8.2 fix should be conditional on
// per-tile-px < threshold, not absolute. If B doesn't beat A,
// the lever-ceiling is confirmed and the v8.2 fix stays.

#if os(macOS)

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class V8_4_GPUIDWTPerfProbe: XCTestCase {

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
        var i = 2
        var f: [Int] = []
        while i < raw.count, f.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var n = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                n = n * 10 + Int(c - 0x30); i += 1
            }
            f.append(n)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(width: f[0], height: f[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: f[0], height: f[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func medianMs(_ runs: Int, _ body: () async throws -> Void) async throws -> Double {
        var s: [Double] = []
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            try await body()
            let t1 = Date().timeIntervalSinceReferenceDate
            s.append((t1 - t0) * 1000.0)
        }
        s.sort()
        return s[runs / 2]
    }

    func testProbe_DX_GPUIDWTLeg() async throws {
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX fixture not present")
        }

        // Encode using auto planner (= 2x2 for DX), HT-conformant lossless.
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let bytes = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        // Warm up.
        await J2KDecoder.preWarm()
        _ = try await J2KDecoder().decode(bytes)
        _ = try await J2KDecoder().decode(bytes)

        let prevBatched = DecoderPipeline._multiTileBatchedEntropyEnabled
        let prevFix = DecoderPipeline._v82_disableIDWTRoutingFix
        defer {
            DecoderPipeline._multiTileBatchedEntropyEnabled = prevBatched
            DecoderPipeline._v82_disableIDWTRoutingFix = prevFix
        }

        let runs = 9   // wider median to dampen variance

        // Leg A: default (batched entropy + CPU IDWT via v8.2 fix).
        DecoderPipeline._multiTileBatchedEntropyEnabled = true
        DecoderPipeline._v82_disableIDWTRoutingFix = false
        let legA = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(bytes)
        }

        // Leg B: batched entropy + GPU IDWT (bypass v8.2 fix).
        DecoderPipeline._multiTileBatchedEntropyEnabled = true
        DecoderPipeline._v82_disableIDWTRoutingFix = true
        let legB = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(bytes)
        }

        // Leg C: per-tile entropy (batched flag OFF) — uses fused-from-
        // codeblocks GPU batch (gpuBatch non-nil) → CPU IDWT per the
        // hasFusedFromCodeblocksPlan gate.
        DecoderPipeline._multiTileBatchedEntropyEnabled = false
        DecoderPipeline._v82_disableIDWTRoutingFix = false
        let legC = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(bytes)
        }

        let deltaBA = legA - legB
        let deltaCA = legA - legC

        print()
        print("=== v8.4 — DX 2800×2288 GPU-IDWT lift probe (median of \(runs)) ===")
        print(String(format: "  Leg A — batched entropy + CPU IDWT (v8.2 fix ON, current default):  %.2f ms", legA))
        print(String(format: "  Leg B — batched entropy + GPU IDWT (v8.2 fix bypassed, v8.3-correct): %.2f ms", legB))
        print(String(format: "  Leg C — per-tile path (no batched, fused-from-codeblocks → CPU IDWT): %.2f ms", legC))
        print()
        print(String(format: "  Δ (A − B) = %+.2f ms — positive means GPU IDWT wins", deltaBA))
        print(String(format: "  Δ (A − C) = %+.2f ms — positive means per-tile path wins", deltaCA))
        print()
        if deltaBA >= 3.0 {
            print("  ⇒ GPU IDWT is ≥ 3 ms faster than CPU IDWT on the batched-entropy path.")
            print("    Refine the v8.2 fix to per-tile-px-conditional (only force CPU < 1 MP/tile).")
        } else if deltaBA <= -3.0 {
            print("  ⇒ CPU IDWT is ≥ 3 ms faster than GPU IDWT on the batched-entropy path.")
            print("    v8.2 fix stays absolute. GPU IDWT lever-ceiling confirmed for DX-class fixtures.")
        } else {
            print("  ⇒ Within ±3 ms — wash. v8.2 fix stays absolute (defensive simplicity wins).")
        }
    }

    /// Probe GPU-HT entropy decode at 16+ MP (mg-class). The
    /// V8Phase5WarmInProcessBenchmark showed GPU-HT 2.4× slower
    /// than CPU on DX (6.4 MP). The trend across fixtures suggests
    /// crossover at ~12-15 MP. Test on a synthetic 16+ MP fixture
    /// to see if GPU-HT entropy wins above the corpus DX size.
    func testProbe_LargeFixture_GPUHTEntropy() async throws {
        let width = 4097
        let height = 4097   // 16,785,409 ≈ 16 M px
        var data = Data(count: width * height * 2)
        var rng: UInt64 = 0xC0FFEE_DEADBEEF
        data.withUnsafeMutableBytes { buf in
            let p = buf.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(width * height) {
                rng &+= 0x9E37_79B9_7F4A_7C15
                var z = rng
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                let v = UInt16((z ^ (z >> 31)) & 0x0FFF)
                p[i * 2 + 0] = UInt8(v >> 8)
                p[i * 2 + 1] = UInt8(v & 0xFF)
            }
        }
        let image = J2KImage(width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height,
                data: data, sampleByteOrder: .bigEndian)])

        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let bytes = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        await J2KDecoder.preWarm()
        // Warmup (each path).
        _ = try await J2KDecoder().decode(bytes)
        _ = try await J2KDecoder().decode(bytes)

        guard let session = (try? await J2KMetalSession.processShared) else {
            throw XCTSkip("Metal session not available")
        }
        let decoder = J2KDecoder()
        // GPU-HT warm-up.
        _ = try await decoder.decodeWithGPUHT(bytes, session: session)
        _ = try await decoder.decodeWithGPUHT(bytes, session: session)

        let runs = 9

        let cpuMs = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(bytes)
        }
        let gpuHtMs = try await medianMs(runs) {
            _ = try await decoder.decodeWithGPUHT(bytes, session: session)
        }

        print()
        print("=== v8.4 — 16-MP fixture (\(width)×\(height) = \(width*height) px) GPU-HT entropy probe (median of \(runs)) ===")
        print(String(format: "  CPU warm decode:    %.2f ms", cpuMs))
        print(String(format: "  GPU-HT warm decode: %.2f ms", gpuHtMs))
        print(String(format: "  Δ (CPU − GPU-HT) = %+.2f ms", cpuMs - gpuHtMs))
        if cpuMs - gpuHtMs >= 5.0 {
            print("  ⇒ GPU-HT entropy WINS at 16+ MP — extend the routing threshold to enable")
            print("    `decodeWithGPUHT` on `decode()` for fixtures ≥ 12-15 MP.")
        } else {
            print("  ⇒ GPU-HT entropy still loses at 16 MP — the per-block GPU cost on M2 doesn't")
            print("    cross over with CPU even at 2.6× the DX size. Lever-ceiling confirmed.")
        }
    }
}

#endif
