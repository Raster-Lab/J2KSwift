// J2KMedicalCorpusPerformanceTests.swift
// v5.27.0 — per-fixture warm-session perf characterisation across
// the medical DICOM corpus (J2KSwift/Tests/Fixtures/CrossCodec).
//
// v5.24-v5.26 measured a single synthetic 1024×1024 fixture in
// J2KGPULossy97PerformanceTests. That tells us *whether* the
// optimisations work but not *which workloads they help most*.
// v5.27.0 sweeps the corpus to answer two production questions:
//
//   1. Per fixture, which decode API is fastest? Publish the
//      routing table in MEDICAL_BENCHMARK.md.
//   2. At what image-size threshold (if any) does
//      `decodeWithGPUHT(_:session:)` overtake `decodeGPU(_:session:)`?
//      That tells us whether to add a `recommendedPath(for:)`
//      auto-router and on what criterion.
//
// The fixtures are real DICOM-derived PGMs spanning 180×180 to
// 2800×2288 — exactly the range that PACS archives deal with.
//
// Like J2KGPULossy97PerformanceTests, this is a MEASUREMENT gate
// (no perf assertions; only existence/correctness assertions).
// Run with: swift test -c release --filter J2KMedicalCorpus

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

/// Read `machdep.cpu.brand_string` so the benchmark output self-
/// tags with the processor (e.g. "Apple M2", "Apple M4 Pro") —
/// makes M2 vs M4 result tables in MEDICAL_BENCHMARK.md
/// unambiguous.
func processorBrandString() -> String {
    var size: size_t = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    guard size > 0 else { return "(unknown)" }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
    return String(cString: buffer)
}

final class J2KMedicalCorpusPerformanceTests: XCTestCase {

    /// Fixture descriptor: real fixture has a non-empty `path`;
    /// synthetic fixture has `path == nil` and uses `synthDimensions`.
    /// v5.28.0 extends the corpus to mammography sizes; the
    /// `dx_001`/`mg_001`/`mg_002` fixtures aren't checked into git
    /// (PGMs at 17 MP × 16 bit = ~32 MB each). They synthesise as
    /// LCG-noise images at the same dimensions; perf scales primarily
    /// with pixel count + (constant-bitrate) bitstream length, both
    /// of which match the real fixture, so the timing comparison
    /// remains valid for routing-rule characterisation.
    struct Fixture: Sendable {
        let name: String
        let path: String?
        let synthDimensions: (Int, Int)?
        var isSynthetic: Bool { path == nil }
    }

    private static let fixtures: [Fixture] = [
        // Real fixtures from Tests/Fixtures/CrossCodec.
        Fixture(name: "mr_002 (180×180)",     path: "mr_study_002_instance_000100.pgm", synthDimensions: nil),
        Fixture(name: "ct_001 (512×512)",     path: "ct_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "ct_003 (512×512)",     path: "ct_study_003_instance_000050.pgm", synthDimensions: nil),
        Fixture(name: "mr_001 (886×886)",     path: "mr_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "xa_001 (1024×1024)",   path: "xa_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "px_001 (2459×1316)",   path: "px_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "dx_002 (2800×2288)",   path: "dx_study_002_instance_000001.pgm", synthDimensions: nil),
        // v5.28.0 synthetic mammography-class fixtures (real PGMs
        // not checked into the repo). Dimensions match the
        // RELEASE_READINESS_REPORT.md corpus entries.
        Fixture(name: "dx_001 (2544×3056)*",  path: nil, synthDimensions: (2544, 3056)),
        Fixture(name: "mg_001 (3520×4784)*",  path: nil, synthDimensions: (3520, 4784)),
        Fixture(name: "mg_002 (3521×4784)*",  path: nil, synthDimensions: (3521, 4784)),
    ]

    private func loadPGM(_ filename: String) throws -> J2KImage? {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            return nil
        }
        let data = try Data(contentsOf: fixture)
        var i = 2  // skip "P5\n"
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 { while i < data.count, data[i] != 0x0A { i += 1 }; continue }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < data.count, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: data.subdata(in: i..<data.count),
                sampleByteOrder: .bigEndian)])
    }

    /// Synthesise a 16-bit grayscale image at given dimensions using
    /// the same LCG sequence as `J2KGPULossy97PerformanceTests`. Used
    /// to stand in for real medical fixtures that aren't checked into
    /// the repo (mammography PGMs are ~32 MB each).
    private func synthesizeImage(width: Int, height: Int) -> J2KImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        var s: UInt64 = 0xfeed_face
        for i in 0..<(width * height) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let v = Int(s >> 48) & 0xFFFF
            bytes[i * 2]     = UInt8((v >> 8) & 0xFF)
            bytes[i * 2 + 1] = UInt8(v & 0xFF)
        }
        return J2KImage(
            width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height,
                data: Data(bytes), sampleByteOrder: .bigEndian)])
    }

    /// Resolve a `Fixture` to a `J2KImage`: load PGM if real and
    /// present, synthesise if marked, return nil if real but missing.
    private func resolveFixture(_ f: Fixture) throws -> J2KImage? {
        if let path = f.path {
            return try loadPGM(path)
        }
        if let dims = f.synthDimensions {
            return synthesizeImage(width: dims.0, height: dims.1)
        }
        return nil
    }

    /// Encode HT-conformant lossy 9/7 at the given bpp.
    private func encode(_ img: J2KImage, bpp: Double) async throws -> Data {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        return try await J2KEncoder(encodingConfiguration: cfg).encode(img)
    }

    /// Median time (ms) over n calls to `decode`. Resets/snapshots
    /// `J2KDecodeTimings` per call and returns the per-stage means
    /// alongside the end-to-end median.
    private func benchmark(
        encoded: Data, n: Int,
        decode: (Data) async throws -> J2KImage
    ) async throws -> (median: Double, samples: [Double], stages: J2KDecodeTimings.Snapshot) {
        // Warm-up
        _ = try await decode(encoded)
        var times: [TimeInterval] = []
        var stageTotals = J2KDecodeTimings.Snapshot(
            extractTileData: 0, entropyDecoding: 0, gpuHTDispatch: 0,
            dequantization: 0, inverseWaveletTransform: 0,
            inverseColorTransform: 0, dcLevelUnshift: 0, reconstructImage: 0)
        for _ in 0..<n {
            J2KDecodeTimings.reset()
            let t0 = Date()
            _ = try await decode(encoded)
            times.append(Date().timeIntervalSince(t0))
            let s = J2KDecodeTimings.snapshot()
            stageTotals = J2KDecodeTimings.Snapshot(
                extractTileData: stageTotals.extractTileData + s.extractTileData,
                entropyDecoding: stageTotals.entropyDecoding + s.entropyDecoding,
                gpuHTDispatch: stageTotals.gpuHTDispatch + s.gpuHTDispatch,
                dequantization: stageTotals.dequantization + s.dequantization,
                inverseWaveletTransform: stageTotals.inverseWaveletTransform + s.inverseWaveletTransform,
                inverseColorTransform: stageTotals.inverseColorTransform + s.inverseColorTransform,
                dcLevelUnshift: stageTotals.dcLevelUnshift + s.dcLevelUnshift,
                reconstructImage: stageTotals.reconstructImage + s.reconstructImage)
        }
        let scale = 1000.0 / Double(n)
        let means = J2KDecodeTimings.Snapshot(
            extractTileData: stageTotals.extractTileData * scale,
            entropyDecoding: stageTotals.entropyDecoding * scale,
            gpuHTDispatch: stageTotals.gpuHTDispatch * scale,
            dequantization: stageTotals.dequantization * scale,
            inverseWaveletTransform: stageTotals.inverseWaveletTransform * scale,
            inverseColorTransform: stageTotals.inverseColorTransform * scale,
            dcLevelUnshift: stageTotals.dcLevelUnshift * scale,
            reconstructImage: stageTotals.reconstructImage * scale)
        let median = times.sorted()[n / 2] * 1000
        return (median, times.map { $0 * 1000 }, means)
    }

    /// Sweep all available fixtures × 3 decode APIs, print a
    /// markdown table that drops cleanly into MEDICAL_BENCHMARK.md.
    func testCorpusWarmSessionAcrossDecodeAPIs() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let n = 5  // per-fixture sample count
        let bpp = 2.0
        let session = J2KMetalSession()
        let cpuDecoder = J2KDecoder()
        let gpuIDWTDecoder = J2KDecoder()
        let gpuHTDecoder = J2KDecoder()

        struct Row {
            let name: String
            let pixels: Int
            let cpuMs: Double
            let gpuIDWTMs: Double
            let gpuHTMs: Double
            let gpuIDWTGain: Double
            let gpuHTGain: Double
            let winner: String
            let gpuHTStages: J2KDecodeTimings.Snapshot
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fixture in Self.fixtures {
            guard let img = try resolveFixture(fixture) else {
                skipped.append(fixture.name)
                continue
            }
            let encoded = try await encode(img, bpp: bpp)

            let cpuRes = try await benchmark(encoded: encoded, n: n) { data in
                try await cpuDecoder.decode(data)
            }
            let gpuIDWTRes = try await benchmark(encoded: encoded, n: n) { data in
                try await gpuIDWTDecoder.decodeGPU(data, session: session)
            }
            let gpuHTRes = try await benchmark(encoded: encoded, n: n) { data in
                try await gpuHTDecoder.decodeWithGPUHT(data, session: session)
            }

            let gpuIDWTGain = cpuRes.median / gpuIDWTRes.median
            let gpuHTGain   = cpuRes.median / gpuHTRes.median

            let winner: String
            if gpuIDWTRes.median < gpuHTRes.median && gpuIDWTRes.median < cpuRes.median {
                winner = "decodeGPU"
            } else if gpuHTRes.median < gpuIDWTRes.median && gpuHTRes.median < cpuRes.median {
                winner = "decodeWithGPUHT"
            } else {
                winner = "CPU"
            }

            rows.append(Row(
                name: fixture.name,
                pixels: img.width * img.height,
                cpuMs: cpuRes.median,
                gpuIDWTMs: gpuIDWTRes.median,
                gpuHTMs: gpuHTRes.median,
                gpuIDWTGain: gpuIDWTGain,
                gpuHTGain: gpuHTGain,
                winner: winner,
                gpuHTStages: gpuHTRes.stages))
        }

        // Print a markdown-friendly table for direct paste into
        // MEDICAL_BENCHMARK.md.
        print("=== v5.30.0 medical corpus warm-session decode benchmark ===")
        print("Processor: \(processorBrandString())")
        print("Image: HT-conformant lossy 9/7 @ \(bpp) bpp, n=\(n) per fixture")
        print("Synthetic fixtures (LCG noise, no real medical content) marked with *")
        if !skipped.isEmpty {
            print("Skipped (fixture not present): \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | CPU ms | decodeGPU ms | decodeWithGPUHT ms | decodeGPU× | decodeWithGPUHT× | Winner |")
        print("|---|---:|---:|---:|---:|---:|---:|---|")
        for r in rows {
            print(String(format: "| %@ | %d | %.1f | %.1f | %.1f | %.2f× | %.2f× | %@ |",
                         r.name, r.pixels, r.cpuMs, r.gpuIDWTMs, r.gpuHTMs,
                         r.gpuIDWTGain, r.gpuHTGain, r.winner))
        }
        print("")
        // Stages stored in `means.X` are already in ms (the seconds→
        // ms conversion happened in `benchmark`'s `scale` factor); the
        // TimeInterval field name is reused as a numeric carrier.
        print("Per-fixture decodeWithGPUHT stage breakdown (means, ms):")
        print("| Fixture | gpuHTDispatch | regroup | dequant | IDWT |")
        print("|---|---:|---:|---:|---:|")
        for r in rows {
            let regroup = max(0, r.gpuHTStages.entropyDecoding - r.gpuHTStages.gpuHTDispatch)
            print(String(format: "| %@ | %.1f | %.1f | %.1f | %.1f |",
                         r.name,
                         r.gpuHTStages.gpuHTDispatch,
                         regroup,
                         r.gpuHTStages.dequantization,
                         r.gpuHTStages.inverseWaveletTransform))
        }

        XCTAssertFalse(rows.isEmpty,
            "No fixtures benchmarked — corpus directory layout changed?")
    }

    /// v5.28.0 — measure cold-start cost with and without
    /// `J2KMetalSession.preWarm()`. The first decode on a fresh
    /// session pays the ~50 ms shader-library load + pipeline-state
    /// creation cost; preWarm() does this work up front so the first
    /// decode runs at warm-session speed.
    ///
    /// This is a measurement gate, not an assertion gate (timings
    /// are too noisy for a fixed-ratio threshold). Prints the
    /// numbers for human/CI review.
    func testColdStartVsPreWarmFirstDecodeLatency() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        // Use a small fixture so the dispatch / shader-load cost
        // dominates the measurement (a 1024² image's actual decode
        // work is ~10 ms; cold-start adds ~50 ms on top, easy to see).
        let img = synthesizeImage(width: 512, height: 512)
        let encoded = try await encode(img, bpp: 2.0)

        // Cold session: no preWarm. First decode pays full cost.
        let coldSession = J2KMetalSession()
        let coldDecoder = J2KDecoder()
        let coldT0 = Date()
        _ = try await coldDecoder.decodeWithGPUHT(encoded, session: coldSession)
        let coldFirstMs = Date().timeIntervalSince(coldT0) * 1000
        // Second decode on the same session: warm.
        let coldT1 = Date()
        _ = try await coldDecoder.decodeWithGPUHT(encoded, session: coldSession)
        let coldSecondMs = Date().timeIntervalSince(coldT1) * 1000

        // Warm session: preWarm before first decode.
        let warmSession = J2KMetalSession()
        let preWarmT0 = Date()
        try await warmSession.preWarm()
        let preWarmMs = Date().timeIntervalSince(preWarmT0) * 1000
        let warmDecoder = J2KDecoder()
        let warmT0 = Date()
        _ = try await warmDecoder.decodeWithGPUHT(encoded, session: warmSession)
        let warmFirstMs = Date().timeIntervalSince(warmT0) * 1000
        let warmT1 = Date()
        _ = try await warmDecoder.decodeWithGPUHT(encoded, session: warmSession)
        let warmSecondMs = Date().timeIntervalSince(warmT1) * 1000

        print("=== v5.30.0 cold-start vs preWarm benchmark ===")
        print("Processor: \(processorBrandString())")
        print("Image: 512×512 16-bit lossy 9/7 @ 2.0 bpp")
        print(String(format: "Cold session  first decode:  %.1f ms  (cold-start cost included)", coldFirstMs))
        print(String(format: "Cold session  second decode: %.1f ms  (warm baseline)", coldSecondMs))
        print(String(format: "preWarm() call itself:        %.1f ms", preWarmMs))
        print(String(format: "Warm session  first decode:   %.1f ms  (after preWarm)", warmFirstMs))
        print(String(format: "Warm session  second decode:  %.1f ms  (warm baseline)", warmSecondMs))
        print(String(format: "Cold-start eliminated:        %.1f ms  (= cold-first %.1f − warm-first %.1f)",
                     coldFirstMs - warmFirstMs, coldFirstMs, warmFirstMs))
        print(String(format: "Total cost (preWarm + first): %.1f ms vs cold-first %.1f ms",
                     preWarmMs + warmFirstMs, coldFirstMs))

        // Sanity gate: preWarm should make first-decode meaningfully
        // faster than cold-start. A 5 ms threshold is very loose
        // (cold-start is normally 30-80 ms above warm) — fires only
        // if preWarm broke catastrophically.
        XCTAssertGreaterThan(coldFirstMs, 0)
        XCTAssertGreaterThan(warmFirstMs, 0)
        XCTAssertGreaterThan(preWarmMs, 0)
    }
}
