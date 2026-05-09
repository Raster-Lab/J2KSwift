// V8Phase5WarmInProcessBenchmark.swift
//
// v8 Phase 5 — measure warm in-process decode walls (after
// `preWarm()`) for both `J2KDecoder.decode` (CPU-default per
// Phase 2) and `decoder.decodeWithGPUHT(_:session:)` (warm GPU
// session, no per-call cold-start tax). Compares against the
// known Kakadu CLI numbers from the user's external eval matrix.
//
// **Goal**: validate the v8 Phase 4 finding's recommendation to
// promote the persistent-Metal-session XPC daemon work to v8.0.x.
// If warm in-process J2KSwift CONSISTENTLY beats Kakadu's CLI
// wall on the corpus, the XPC daemon (which essentially gives
// CLI users the warm-in-process performance via persistent
// session) is justified — its theoretical max win is the
// CLI-vs-warm gap on the dominant fixtures.
//
// If warm in-process J2KSwift does NOT beat Kakadu's CLI wall,
// the XPC daemon won't be enough alone — additional in-process
// compute optimisation is needed regardless of the daemon.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V8Phase5WarmInProcessBenchmark: XCTestCase {

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

    /// Local 2026-05-09 measurement of Kakadu's `kdu_expand` CLI
    /// on the same fixtures, median of 5 (per Phase 1 finding §1).
    /// These are CLI walls — they include Kakadu's own startup
    /// (~13-14 ms per `kdu_expand -version`) plus their decode work.
    private static let kakaduCLIBaselineMs: [String: Double] = [
        "MR-small 180²":   15,
        "CT 512²":         15,
        "MR 886²":         17,
        "XA 1024²":        18,
        "PX 2459×1316":    24,
        "DX 2800×2288":    36,
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
            quality: 1.0, lossless: true, qualityLayers: 1,
            useHTJ2K: true, useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    func testWarmInProcess_VsKakaduCLI_AcrossCorpus() async throws {
        // Pre-warm the GPU session so the GPU path doesn't pay
        // cold-start on the first measurement.
        let session = J2KMetalSession.processShared
        if J2KMetalSession.isAvailable {
            try await session.preWarm()
        }

        // Pre-warm the CPU path too — first decode tends to be a
        // bit slower due to JIT / cache warming.
        if let warm = loadPGM16("mr_study_002_instance_000100.pgm") {
            let cfg = htConfig()
            let bytes = try await J2KEncoder(encodingConfiguration: cfg).encode(warm)
            _ = try await J2KDecoder().decode(bytes)
        }

        print("=== v8 Phase 5 — warm in-process J2KSwift vs Kakadu CLI ===")
        print("(median of 5 warm decodes; Kakadu baseline from eval matrix CLI walls)")
        print()
        print("| fixture | CPU warm (ms) | GPU-HT warm (ms) | best (ms) | Kakadu CLI (ms) | best/Kakadu | result |")
        print("|---|---:|---:|---:|---:|---:|:--|")

        let runs = 5
        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let cfg = htConfig()
            let bytes = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

            // CPU warm samples
            var cpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date()
                _ = try await J2KDecoder().decode(bytes)
                cpuMs.append(Date().timeIntervalSince(t0) * 1000.0)
            }
            cpuMs.sort()
            let cpuMed = cpuMs[runs / 2]

            // GPU-HT warm samples (reuses preWarmed session)
            var gpuMs: [Double] = []
            if J2KMetalSession.isAvailable {
                for _ in 0..<runs {
                    let t0 = Date()
                    _ = try await J2KDecoder().decodeWithGPUHT(bytes, session: session)
                    gpuMs.append(Date().timeIntervalSince(t0) * 1000.0)
                }
                gpuMs.sort()
            }
            let gpuMed = gpuMs.isEmpty ? Double.infinity : gpuMs[runs / 2]

            let bestMed = min(cpuMed, gpuMed)
            let kdu = Self.kakaduCLIBaselineMs[fix.label] ?? 0
            let ratio = bestMed / max(0.001, kdu)
            let result = bestMed <= kdu ? "✓ WIN" : "behind"

            print(String(
                format: "| %@ | %.2f | %.2f | %.2f | %.0f | %.2f× | %@ |",
                fix.label, cpuMed,
                gpuMs.isEmpty ? Double.nan : gpuMed,
                bestMed, kdu, ratio, result))
        }

        print()
        print("Reading the table:")
        print("  - 'CPU warm' is `J2KDecoder.decode` after a single warm-up call.")
        print("  - 'GPU-HT warm' is `decoder.decodeWithGPUHT(_:session:)` against a preWarmed session.")
        print("  - 'Kakadu CLI' is the user's local eval matrix wall, reproduced here as the comparison")
        print("    target. It includes Kakadu's own startup cost (~13 ms per process).")
        print("  - 'best' is min(CPU, GPU-HT) for each fixture.")
        print("  - 'best/Kakadu' = J2KSwift warm wall ÷ Kakadu CLI wall.")
        print("    < 1.0× → J2KSwift WINS in warm mode (XPC daemon would deliver this to CLI users)")
        print("    ≥ 1.0× → J2KSwift behind even in warm mode (XPC daemon alone won't save us)")
        print()
        print("Phase 5 GO/NO-GO criterion: if J2KSwift warm beats Kakadu CLI on ≥ 4 of 6 fixtures,")
        print("the XPC-daemon Phase 6 work is justified. Else, more in-process compute work is")
        print("needed regardless of session-persistence.")
    }
}
