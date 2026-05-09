// v8 Phase 6.2 — gated to macOS: depends on CrossCodecTooling (uses Process(), unavailable on iOS).
#if os(macOS)
// HTBottleneckDiagnosisTests.swift
// v5.39 M3 — large-fixture HT performance bottleneck diagnosis.
//
// Goal: identify the real source of Kakadu's large-fixture HT
// advantage before implementing another optimisation. M1 (SIMD)
// produced no measurable speedup; M2 (DWT row-parallel) gained
// 8-16% on the DWT stage but only 4-8% on total — both miss the
// promotion bar. Either we have a structural ceiling we can't
// approach with local optimisation, or the entropy/scheduler is
// hiding a bigger lever.
//
// Diagnostic methodology — `M3` is profile-only:
//   1. Per-stage breakdown via existing `J2KEncodeTimings`
//      (preprocess / DWT / entropy / codestream) at maxThreads
//      ∈ {1,2,4,8}. The encoder's per-block parallel path only
//      gates entropy; the rest are CPU-saturating regardless of
//      maxThreads, which gives us an Amdahl's-law fingerprint
//      for each fixture.
//   2. Memory pressure via Mach `task_info()` resident-memory
//      delta around encode. Peak RSS over an encode run shows
//      whether transient buffer churn is bandwidth-bottlenecked.
//   3. Block-count / chunk-distribution math derived from the
//      fixture geometry — the encoder splits `totalBlocks` into
//      `chunks = totalBlocks / maxConcurrency`, so chunk-level
//      load balance is deterministic given the fixture.
//   4. Mode-combination matrix. Run baseline / SIMD-on /
//      DWT-parallel-on / both-on per fixture, so M1 and M2 can be
//      measured WITH and WITHOUT each other (composability check).
//   5. Output-bytes-per-block distribution from a single warm
//      encode — exposes whether work is uniform (chunk balance OK)
//      or heavily skewed (chunk M gets all the "fat" HH blocks
//      while chunk N gets sparse LL only).
//
// This file does NOT modify any production code. Sub-stage
// instrumentation (DWT row vs column, HT MEL/VLC/MagSgn split,
// per-worker actual timings) requires hot-path code changes which
// v5.39 M3 declines to take — the existing high-level breakdown
// plus block-level distribution analysis is enough to localise
// the bottleneck and decide M4's direction.
//
// SCOPE: HT lossless only. Default production path unchanged.
// Run via:
//   swift test -c release --filter HTBottleneckDiagnosisTests
//   J2K_HT_SIMD=1 swift test -c release --filter HTBottleneckDiagnosisTests
//   J2K_HT_PARALLEL_MODE=dwt-row-parallel swift test … (etc.)

import XCTest
import Darwin
@testable import J2KCore
@testable import J2KCodec

final class HTBottleneckDiagnosisTests: XCTestCase {

    private func htConfig(maxThreads: Int) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            bitrateMode: .lossless,
            maxThreads: maxThreads,
            useHTJ2K: true,
            useReversibleFilter: true,
            enableParallelCodeBlocks: maxThreads != 1,
            htj2kBlockFormat: .conformant)
        return cfg
    }

    private static func median(_ samples: [Double]) -> Double {
        precondition(!samples.isEmpty)
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// Resident set size in bytes via Mach `task_info`. Matches
    /// what Activity Monitor reports as "Memory" for the test
    /// process. Used as a coarse memory-pressure proxy.
    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.resident_size : 0
    }

    /// Compute block count (per-band sum) + chunk distribution
    /// given fixture dimensions. Mirrors the encoder's chunk split:
    /// `totalBlocks / maxConcurrency` blocks per chunk. Returns
    /// (totalBlocks, blocksPerChunk[]) for later balance analysis.
    private static func chunkDistribution(
        width: Int, height: Int,
        decomposition: Int = 5,
        cbWidth: Int = 64, cbHeight: Int = 64,
        maxConcurrency: Int
    ) -> (total: Int, perChunk: [Int]) {
        var total = 0
        for r in 0...decomposition {
            let scale = 1 << (decomposition - r)
            let bandW = (width + scale - 1) / scale
            let bandH = (height + scale - 1) / scale
            let blocksX = (bandW + cbWidth - 1) / cbWidth
            let blocksY = (bandH + cbHeight - 1) / cbHeight
            let bands = (r == 0) ? 1 : 3
            total += blocksX * blocksY * bands
        }
        let chunkSize = max(1, total / maxConcurrency)
        var perChunk: [Int] = []
        var idx = 0
        while idx < total {
            let end = min(idx + chunkSize, total)
            perChunk.append(end - idx)
            idx = end
        }
        return (total, perChunk)
    }

    /// One observation per (fixture, mode, threads).
    private struct Row {
        let fixture: String
        let shape: String
        let pixels: Int
        let totalBlocks: Int
        let mode: String
        let threads: Int
        let preprocessMs: Double
        let dwtMs: Double
        let entropyMs: Double
        let codestreamMs: Double
        let stageSumMs: Double  // sum of measured stages
        let totalMs: Double     // wall-clock encode
        let unaccountedMs: Double  // total - stageSum (scheduling, IPC, accounting)
        let outputBytes: Int
        let peakRSSDeltaBytes: Int64
        let chunkCount: Int
        let chunkSizes: [Int]   // blocks per chunk
    }

    /// Active mode label derived from process env vars. The encoder
    /// reads these once at startup (cached static let), so a single
    /// test invocation observes one (SIMD, parallel-DWT) combo.
    /// To measure the matrix, run this test 4× with different env
    /// var combinations.
    private static var activeMode: String {
        let simd = ProcessInfo.processInfo.environment["J2K_HT_SIMD"]
            .map { ["1","true","yes"].contains($0.lowercased()) } ?? false
        let parMode = ProcessInfo.processInfo.environment["J2K_HT_PARALLEL_MODE"] ?? "baseline"
        let pdwt = parMode.lowercased() == "dwt-row-parallel"
        switch (simd, pdwt) {
        case (false, false): return "baseline"
        case (true,  false): return "SIMD-on"
        case (false, true ): return "DWTpar-on"
        case (true,  true ): return "both-on"
        }
    }

    /// Comprehensive M3 diagnostic. For each large medical fixture
    /// and each thread count, measure (preprocess, DWT, entropy,
    /// codestream, total, output bytes, peak RSS delta, chunk
    /// distribution) under the active env-var mode.
    func testHTBottleneckDiagnosisOnLargeFixtures() async throws {
        let largeFixtures = CrossCodecTooling.medicalCorpus.filter {
            ["MR", "XA", "PX", "DX"].contains($0.modality)
        }
        let threadCounts = [1, 2, 4, 8]
        let runs = 5
        let mode = Self.activeMode

        var rows: [Row] = []

        for fixture in largeFixtures {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }

            for tc in threadCounts {
                let cfg = htConfig(maxThreads: tc)
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                _ = try await encoder.encode(img)  // warm-up

                var preMs:  [Double] = []
                var dwtMs:  [Double] = []
                var entMs:  [Double] = []
                var cstMs:  [Double] = []
                var totMs:  [Double] = []
                var rssDelta: [Int64] = []
                var lastBytes: Int = 0

                for _ in 0..<runs {
                    let rssBefore = Self.residentMemoryBytes()
                    J2KEncodeTimings.reset()
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let bytes = try await encoder.encode(img)
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                    let snap = J2KEncodeTimings.snapshot()
                    let rssAfter = Self.residentMemoryBytes()

                    preMs.append(snap.preprocessing * 1000.0)
                    dwtMs.append(snap.waveletTransform * 1000.0)
                    entMs.append(snap.entropyCoding * 1000.0)
                    cstMs.append(snap.codestreamGeneration * 1000.0)
                    totMs.append(dt)
                    rssDelta.append(Int64(rssAfter) - Int64(rssBefore))
                    lastBytes = bytes.count
                }

                let pre = Self.median(preMs)
                let dwt = Self.median(dwtMs)
                let ent = Self.median(entMs)
                let cst = Self.median(cstMs)
                let tot = Self.median(totMs)
                let stageSum = pre + dwt + ent + cst
                let chunks = Self.chunkDistribution(
                    width: img.width, height: img.height,
                    maxConcurrency: tc)

                rows.append(Row(
                    fixture: fixture.modality,
                    shape: fixture.labelHint,
                    pixels: img.width * img.height,
                    totalBlocks: chunks.total,
                    mode: mode,
                    threads: tc,
                    preprocessMs: pre,
                    dwtMs: dwt,
                    entropyMs: ent,
                    codestreamMs: cst,
                    stageSumMs: stageSum,
                    totalMs: tot,
                    unaccountedMs: max(0, tot - stageSum),
                    outputBytes: lastBytes,
                    peakRSSDeltaBytes: rssDelta.max() ?? 0,
                    chunkCount: chunks.perChunk.count,
                    chunkSizes: chunks.perChunk))
            }
        }

        if rows.isEmpty { throw XCTSkip("large-fixture corpus not present") }

        // ─── Stage-breakdown table ────────────────────────────────
        print("\n=== v5.39 M3 — stage breakdown (median of \(runs) runs, mode=\(mode)) ===")
        print("| Modality | Shape | Blocks | Threads | Pre | DWT | Entropy | Codestream | StageSum | Wall | Unacc. | Bytes |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %@ | %d | %d | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %d |",
                r.fixture, r.shape, r.totalBlocks, r.threads,
                r.preprocessMs, r.dwtMs, r.entropyMs, r.codestreamMs,
                r.stageSumMs, r.totalMs, r.unaccountedMs, r.outputBytes))
        }

        // ─── Per-stage scaling table (1 thr → 8 thr) ──────────────
        print("\n=== v5.39 M3 — per-stage scaling, 1→8 threads (mode=\(mode)) ===")
        print("| Modality | Shape | Stage | 1 thr | 2 thr | 4 thr | 8 thr | Speedup 8/1 | Eff |")
        print("|---|---|---|---:|---:|---:|---:|---:|---:|")
        let stageGetters: [(String, (Row)->Double)] = [
            ("Preprocess", { $0.preprocessMs }),
            ("DWT",        { $0.dwtMs }),
            ("Entropy",    { $0.entropyMs }),
            ("Codestream", { $0.codestreamMs }),
            ("StageSum",   { $0.stageSumMs }),
            ("Wall",       { $0.totalMs }),
            ("Unacc.",     { $0.unaccountedMs }),
        ]
        let fixtureKeys = Array(Set(rows.map { "\($0.fixture)|\($0.shape)" })).sorted()
        for fk in fixtureKeys {
            let parts = fk.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (mod, shape) = (parts[0], parts[1])
            let frows = rows.filter { $0.fixture == mod && $0.shape == shape }
                .sorted { $0.threads < $1.threads }
            for (sname, getter) in stageGetters {
                let vals: [Int: Double] = Dictionary(uniqueKeysWithValues:
                    frows.map { ($0.threads, getter($0)) })
                let v1 = vals[1] ?? 0, v2 = vals[2] ?? 0
                let v4 = vals[4] ?? 0, v8 = vals[8] ?? 0
                let speedup = v1 / max(v8, 0.001)
                let eff = speedup / 8.0
                print(String(format: "| %@ | %@ | %@ | %.2f | %.2f | %.2f | %.2f | %.2f× | %.2f |",
                    mod, shape, sname, v1, v2, v4, v8, speedup, eff))
            }
        }

        // ─── Chunk-balance analysis ───────────────────────────────
        print("\n=== v5.39 M3 — chunk distribution (block-count load balance) ===")
        print("| Modality | Shape | Total Blocks | Threads | Chunks | Min | Max | Mean | Max/Min |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows where r.threads > 1 {
            let s = r.chunkSizes
            let mn = s.min() ?? 0, mx = s.max() ?? 0
            let mean = s.reduce(0,+) / max(1, s.count)
            let ratio = mn > 0 ? Double(mx) / Double(mn) : Double.nan
            print(String(format: "| %@ | %@ | %d | %d | %d | %d | %d | %d | %.2f× |",
                r.fixture, r.shape, r.totalBlocks, r.threads,
                s.count, mn, mx, mean, ratio))
        }

        // ─── Memory-pressure delta ────────────────────────────────
        print("\n=== v5.39 M3 — peak RSS delta around encode (mode=\(mode)) ===")
        print("| Modality | Shape | Threads | RSS Δ MiB | Bytes-out MiB |")
        print("|---|---|---:|---:|---:|")
        for r in rows where r.threads == 8 {
            let rssMiB = Double(r.peakRSSDeltaBytes) / (1024.0 * 1024.0)
            let outMiB = Double(r.outputBytes) / (1024.0 * 1024.0)
            print(String(format: "| %@ | %@ | %d | %.2f | %.2f |",
                r.fixture, r.shape, r.threads, rssMiB, outMiB))
        }

        // ─── Amdahl decomposition (8-thr Wall vs 1-thr stage sum) ─
        print("\n=== v5.39 M3 — Amdahl decomposition (parallel fraction by fixture, mode=\(mode)) ===")
        print("(serial fraction = 1 - (1 - 1/S) / (1 - 1/N), S = speedup at N=8)")
        print("| Modality | Shape | 1 thr Wall | 8 thr Wall | Speedup | Parallel% | Serial ms (1thr) |")
        print("|---|---|---:|---:|---:|---:|---:|")
        for fk in fixtureKeys {
            let parts = fk.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (mod, shape) = (parts[0], parts[1])
            let frows = rows.filter { $0.fixture == mod && $0.shape == shape }
            guard let r1 = frows.first(where: { $0.threads == 1 }),
                  let r8 = frows.first(where: { $0.threads == 8 }) else { continue }
            let s = r1.totalMs / max(r8.totalMs, 0.001)
            // Amdahl: 1/S = (1-P) + P/N → solve for P with N=8
            // P = (1 - 1/S) / (1 - 1/N)
            let n = 8.0
            let p = (1.0 - 1.0/s) / (1.0 - 1.0/n)
            let serialFrac = 1.0 - p
            let serialMs = serialFrac * r1.totalMs
            print(String(format: "| %@ | %@ | %.2f | %.2f | %.2f× | %.1f%% | %.2f |",
                mod, shape, r1.totalMs, r8.totalMs, s, p * 100, serialMs))
        }
    }
}

#endif // os(macOS)
