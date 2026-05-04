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

final class J2KMedicalCorpusPerformanceTests: XCTestCase {

    /// Fixtures, ordered by total pixel count (small → large).
    private static let fixtures: [(name: String, path: String)] = [
        ("mr_002 (180×180)",     "mr_study_002_instance_000100.pgm"),
        ("ct_001 (512×512)",     "ct_study_001_instance_000001.pgm"),
        ("ct_003 (512×512)",     "ct_study_003_instance_000050.pgm"),
        ("mr_001 (886×886)",     "mr_study_001_instance_000001.pgm"),
        ("xa_001 (1024×1024)",   "xa_study_001_instance_000001.pgm"),
        ("px_001 (2459×1316)",   "px_study_001_instance_000001.pgm"),
        ("dx_002 (2800×2288)",   "dx_study_002_instance_000001.pgm"),
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
            guard let img = try loadPGM(fixture.path) else {
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
        print("=== v5.27.0 medical corpus warm-session benchmark ===")
        print("Image: HT-conformant lossy 9/7 @ \(bpp) bpp, n=\(n) per fixture")
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
}
