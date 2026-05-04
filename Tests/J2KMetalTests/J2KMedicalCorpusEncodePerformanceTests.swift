// J2KMedicalCorpusEncodePerformanceTests.swift
// v5.29.0 — per-fixture warm-session encode performance across the
// medical DICOM corpus, mirroring the decode-side
// `J2KMedicalCorpusPerformanceTests`.
//
// Decode work plateaued at v5.28.0 (4.6× speedup on mammography via
// `decodeWithGPUHT(_:session:)`). Encode is the next lever:
// J2KSwift HTJ2K encode is ~25% slower than OpenJPH per the
// release-readiness report, the reverse situation from decode. This
// benchmark + the v5.29.0 stage timings tell us *where* encode
// spends its time so we can pick the first concrete optimisation.
//
// Compares CPU `encode(_:)` vs GPU `encodeGPU(_:)` on each fixture
// and breaks total time down by stage:
//   - preprocessing
//   - colorTransform
//   - waveletTransform
//   - quantization
//   - entropyCoding   ← expected dominant on HT
//   - rateControl
//   - codestreamGeneration
//
// Like the decode benchmark this is a MEASUREMENT gate — no perf
// assertions; correctness is covered elsewhere. Run with:
//   swift test -c release --filter J2KMedicalCorpusEncode

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

private func encProcessorBrandString() -> String {
    var size: size_t = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    guard size > 0 else { return "(unknown)" }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
    return String(cString: buffer)
}

final class J2KMedicalCorpusEncodePerformanceTests: XCTestCase {

    /// Reuse the same fixture set as the decode-side corpus
    /// benchmark — synthetic mammography fixtures inline below
    /// since the type isn't shared across test classes.
    private struct Fixture: Sendable {
        let name: String
        let path: String?
        let synthDimensions: (Int, Int)?
    }

    private static let fixtures: [Fixture] = [
        Fixture(name: "mr_002 (180×180)",     path: "mr_study_002_instance_000100.pgm", synthDimensions: nil),
        Fixture(name: "ct_001 (512×512)",     path: "ct_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "ct_003 (512×512)",     path: "ct_study_003_instance_000050.pgm", synthDimensions: nil),
        Fixture(name: "mr_001 (886×886)",     path: "mr_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "xa_001 (1024×1024)",   path: "xa_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "px_001 (2459×1316)",   path: "px_study_001_instance_000001.pgm", synthDimensions: nil),
        Fixture(name: "dx_002 (2800×2288)",   path: "dx_study_002_instance_000001.pgm", synthDimensions: nil),
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
        guard FileManager.default.fileExists(atPath: fixture.path) else { return nil }
        let data = try Data(contentsOf: fixture)
        var i = 2
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

    private func resolveFixture(_ f: Fixture) throws -> J2KImage? {
        if let path = f.path { return try loadPGM(path) }
        if let dims = f.synthDimensions { return synthesizeImage(width: dims.0, height: dims.1) }
        return nil
    }

    private func makeConfig(bpp: Double) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        return cfg
    }

    /// Median over n encode calls + per-stage means via
    /// `J2KEncodeTimings`.
    private func benchmark(
        image: J2KImage, n: Int,
        encode: (J2KImage) async throws -> Data
    ) async throws -> (median: Double, samples: [Double], stages: J2KEncodeTimings.Snapshot) {
        // Warm-up
        _ = try await encode(image)

        var times: [TimeInterval] = []
        var sumPre: TimeInterval = 0, sumColor: TimeInterval = 0
        var sumDWT: TimeInterval = 0, sumQuant: TimeInterval = 0
        var sumEntropy: TimeInterval = 0, sumRate: TimeInterval = 0
        var sumCS: TimeInterval = 0
        for _ in 0..<n {
            J2KEncodeTimings.reset()
            let t0 = Date()
            _ = try await encode(image)
            times.append(Date().timeIntervalSince(t0))
            let s = J2KEncodeTimings.snapshot()
            sumPre += s.preprocessing
            sumColor += s.colorTransform
            sumDWT += s.waveletTransform
            sumQuant += s.quantization
            sumEntropy += s.entropyCoding
            sumRate += s.rateControl
            sumCS += s.codestreamGeneration
        }
        let scale = 1000.0 / Double(n)
        let means = J2KEncodeTimings.Snapshot(
            preprocessing: sumPre * scale,
            colorTransform: sumColor * scale,
            waveletTransform: sumDWT * scale,
            quantization: sumQuant * scale,
            entropyCoding: sumEntropy * scale,
            rateControl: sumRate * scale,
            codestreamGeneration: sumCS * scale)
        let median = times.sorted()[n / 2] * 1000
        return (median, times.map { $0 * 1000 }, means)
    }

    /// Sweep all fixtures × CPU vs GPU encode + per-stage breakdown.
    /// Prints markdown-friendly tables for paste into
    /// MEDICAL_BENCHMARK.md.
    func testCorpusEncodeAcrossAPIs() async throws {
        let n = 5
        let bpp = 2.0
        let cfg = makeConfig(bpp: bpp)
        let cpuEncoder = J2KEncoder(encodingConfiguration: cfg)
        let gpuEncoder = J2KEncoder(encodingConfiguration: cfg)

        struct Row {
            let name: String
            let pixels: Int
            let cpuMs: Double
            let gpuMs: Double
            let cpuStages: J2KEncodeTimings.Snapshot
            let gpuStages: J2KEncodeTimings.Snapshot
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fixture in Self.fixtures {
            guard let img = try resolveFixture(fixture) else {
                skipped.append(fixture.name)
                continue
            }

            let cpuRes = try await benchmark(image: img, n: n) { image in
                try await cpuEncoder.encode(image)
            }
            let gpuRes: (median: Double, samples: [Double], stages: J2KEncodeTimings.Snapshot)
            if J2KMetalSession.isAvailable {
                gpuRes = try await benchmark(image: img, n: n) { image in
                    try await gpuEncoder.encodeGPU(image)
                }
            } else {
                gpuRes = (cpuRes.median, cpuRes.samples, cpuRes.stages)
            }

            rows.append(Row(
                name: fixture.name,
                pixels: img.width * img.height,
                cpuMs: cpuRes.median,
                gpuMs: gpuRes.median,
                cpuStages: cpuRes.stages,
                gpuStages: gpuRes.stages))
        }

        print("=== v5.30.0 medical corpus warm encode benchmark ===")
        print("Processor: \(encProcessorBrandString())")
        print("Image: HT-conformant lossy 9/7 @ \(bpp) bpp, n=\(n) per fixture")
        print("Synthetic fixtures (LCG noise, no real medical content) marked with *")
        if !skipped.isEmpty {
            print("Skipped (fixture not present): \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | CPU encode ms | GPU encode ms | CPU/GPU× |")
        print("|---|---:|---:|---:|---:|")
        for r in rows {
            let ratio = r.cpuMs / max(r.gpuMs, 0.001)
            print(String(format: "| %@ | %d | %.1f | %.1f | %.2f× |",
                         r.name, r.pixels, r.cpuMs, r.gpuMs, ratio))
        }
        print("")
        // means.X is already in ms (the seconds→ms conversion happened
        // in `benchmark`'s `scale` factor); the TimeInterval field
        // name is reused as a numeric carrier.
        print("Per-fixture CPU encode stage breakdown (means, ms):")
        print("| Fixture | preproc | colour | DWT | quant | entropy | rateCtrl | codestream |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |",
                         r.name,
                         r.cpuStages.preprocessing,
                         r.cpuStages.colorTransform,
                         r.cpuStages.waveletTransform,
                         r.cpuStages.quantization,
                         r.cpuStages.entropyCoding,
                         r.cpuStages.rateControl,
                         r.cpuStages.codestreamGeneration))
        }
        print("")
        print("Per-fixture GPU encode stage breakdown (means, ms):")
        print("| Fixture | preproc | colour | DWT | quant | entropy | rateCtrl | codestream |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f |",
                         r.name,
                         r.gpuStages.preprocessing,
                         r.gpuStages.colorTransform,
                         r.gpuStages.waveletTransform,
                         r.gpuStages.quantization,
                         r.gpuStages.entropyCoding,
                         r.gpuStages.rateControl,
                         r.gpuStages.codestreamGeneration))
        }

        XCTAssertFalse(rows.isEmpty,
            "No fixtures benchmarked — corpus directory layout changed?")
    }
}
