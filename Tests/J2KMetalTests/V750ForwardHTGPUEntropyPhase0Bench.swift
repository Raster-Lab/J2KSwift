// V750ForwardHTGPUEntropyPhase0Bench.swift
//
// v7.5 Phase 0 — forward HT GPU entropy A/B benchmark with
// dispatch-vs-emit telemetry breakdown.
//
// v7.1.0 shipped GPU forward HT entropy approach C end-to-end
// (correctness gate cleared) but kept it default OFF: the v7.1.0
// release notes explicitly deferred perf optimisation to v7.2.x.
// v7.2 → v7.4 went elsewhere (UMA, decoder hot loops, NEON), so
// the perf gate has never been driven through. v7.5 reopens this
// workstream.
//
// **Phase 0 deliverable**: ground truth — at every corpus scale,
// is the GPU path faster or slower than CPU? If slower, by how
// much, and is dispatch overhead or emit cost the dominant cost?
// This drives Phase 1+ optimisation direction (or a decision to
// close the workstream out).
//
// Distinct from `HTGPUForwardHTEntropyOrchestratorTests`'s
// existing wall-time A/B because:
//   - This bench prints `totalDispatchMs` / `totalEmitMs` per
//     fire as well as the wall delta — the existing test only
//     prints fire counts and ratios.
//   - Median of 5 (vs the existing 3) for tighter noise control.
//   - Honest about the v7.4.0 settled-system measurement
//     discipline carried over from v7.4.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V750ForwardHTGPUEntropyPhase0Bench: XCTestCase {

    private struct CorpusFixture {
        let label: String
        let filename: String
    }

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "MR-small 180²",   filename: "mr_study_002_instance_000100.pgm"),
        CorpusFixture(label: "CT 512²",         filename: "ct_study_001_instance_000001.pgm"),
        CorpusFixture(label: "MR 886²",         filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",        filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316",    filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288",    filename: "dx_study_002_instance_000001.pgm"),
    ]

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 {
                while i < raw.count, raw[i] != 0x0A { i += 1 }
                continue
            }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func encodeWithGate(_ image: J2KImage, gateOn: Bool) async throws -> Data {
        let prevEnabled = EncoderPipeline._gpuForwardHTEntropyEnabled
        let prevThreshold = EncoderPipeline._gpuForwardHTEntropyBlockThreshold
        defer {
            EncoderPipeline._gpuForwardHTEntropyEnabled = prevEnabled
            EncoderPipeline._gpuForwardHTEntropyBlockThreshold = prevThreshold
        }
        EncoderPipeline._gpuForwardHTEntropyEnabled = gateOn
        // Lower threshold to 1 so every fixture exercises the GPU
        // path uniformly.
        EncoderPipeline._gpuForwardHTEntropyBlockThreshold = 1
        return try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)
    }

    func testPhase0_ForwardHTGPU_AB_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        print("=== v7.5 Phase 0 — forward HT GPU entropy A/B (median of 5) ===")
        print("(Threshold lowered to 1 so every fixture exercises GPU path.)")
        print()
        print("| fixture | bytes | CPU ms | GPU ms | Δ ms | Δ % | dispatch ms | emit ms | other ms | fires | blocks/fire |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")

        let runs = 5

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warm-up — both paths.
            _ = try await encodeWithGate(image, gateOn: false)
            _ = try await encodeWithGate(image, gateOn: true)

            // CPU path samples.
            var cpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encodeWithGate(image, gateOn: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            cpuMs.sort()

            // GPU path samples — capture telemetry on each run, then
            // average dispatch/emit ms across runs.
            var gpuMs: [Double] = []
            var dispatchPerRun: [Double] = []
            var emitPerRun: [Double] = []
            var blocksPerFire = 0
            var fires = 0
            var bytes = 0
            for _ in 0..<runs {
                J2KGPUForwardHTEntropyTelemetry.reset()
                let t0 = Date().timeIntervalSinceReferenceDate
                let data = try await encodeWithGate(image, gateOn: true)
                gpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                let snap = J2KGPUForwardHTEntropyTelemetry.snapshot()
                dispatchPerRun.append(snap.totalDispatchMs)
                emitPerRun.append(snap.totalEmitMs)
                blocksPerFire = snap.gpuBlocksClassified / max(1, snap.gpuFireCount)
                fires = snap.gpuFireCount
                bytes = data.count
            }
            gpuMs.sort()

            let cpuMed = cpuMs[runs / 2]
            let gpuMed = gpuMs[runs / 2]
            let dispatchMed = dispatchPerRun.sorted()[runs / 2]
            let emitMed = emitPerRun.sorted()[runs / 2]
            let otherMed = gpuMed - dispatchMed - emitMed
            let dms = cpuMed - gpuMed
            let pct = (dms / cpuMed) * 100.0

            print(String(
                format: "| %@ | %d | %6.2f | %6.2f | %+6.2f | %+5.1f | %6.2f | %6.2f | %6.2f | %d | %d |",
                fix.label, bytes, cpuMed, gpuMed, dms, pct,
                dispatchMed, emitMed, otherMed, fires, blocksPerFire))
        }

        print()
        print("Reading the table:")
        print("  - Δ ms / Δ %     positive  → GPU path faster (would clear gate)")
        print("                   negative  → GPU path slower (current state)")
        print("  - dispatch ms    GPU classifier dispatch wall-time across all fires")
        print("  - emit ms        GPU cleanup-pass emit dispatch wall-time across all fires")
        print("  - other ms       gpuMed − dispatchMs − emitMs")
        print("                     = pre/post host work + coefficient marshalling +")
        print("                       descriptor build + result copy-out + everything else")
        print("                       not on the GPU compute critical path.")
        print("  - fires          one orchestrator fire per (tile × resolution band) hitting")
        print("                   the gate; ~48 for DX 4×4 with 5 levels.")
        print("  - blocks/fire    average codeblocks per fire.")
        print()
        print("v7.5 Phase 0 acceptance criterion (carried from v7.4 staged-NEON discipline):")
        print("  Default flips to ON only when the largest production fixture")
        print("  (DX 2800×2288) shows GPU encode wall ≥ 3 ms faster than CPU encode")
        print("  wall on a settled system. Anything below 3 ms keeps the flag default OFF.")
    }
}
