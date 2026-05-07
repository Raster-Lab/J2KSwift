// MultiTileDecodeGPUDefaultOnTests.swift
//
// v6.3.0 work item E1.2 — production-default routing widened to
// multi-tile after E1.1 (#321) fixed the canvas-anchored codeblock
// partition mis-alignment in `decodeTilePayloadGPU`. The v6.2.0
// narrow `&& !metadata.isMultiTile` guard is dropped; multi-tile
// fixtures that meet the pixel threshold now route through the GPU
// path on `decode(_:)`.
//
// Validates two invariants that protect production users:
//
//   1. **Decoded pixel data byte-identical** between gate-on
//      (production now, including multi-tile) and forced-off
//      (legacy CPU multi-tile) across every multi-tile cell. The
//      lossless decode contract holds whether the codestream is
//      single- or multi-tile.
//
//   2. **Wall-time A/B** printed per cell so the PR has the
//      empirical wins on this host. Multi-tile per-tile dispatch
//      pays GPU command-buffer overhead per tile, so the curve may
//      differ from single-tile (where we measured +37–46 % on M2 in
//      v6.2.0). The A/B is the data the v6.3.0 release notes use.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MultiTileDecodeGPUDefaultOnTests: XCTestCase {

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

    private struct CorpusFixture {
        let label: String
        let filename: String
    }

    // Same multi-tile fixture set as MultiTileDecodeGPUInvestigationTests
    // and HTTileParityMatrixTests so the data lines up across reports.
    private static let fixtures: [CorpusFixture] = [
        CorpusFixture(label: "MR 886²",      filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",     filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316", filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288", filename: "dx_study_002_instance_000001.pgm"),
    ]

    private func htConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    /// Save and restore the gate state.
    private func decode(codestream: Data, gateOn: Bool) async throws -> J2KImage {
        let prevInv = DecoderPipeline._gpuInverse53Enabled
        let prevHT = DecoderPipeline._gpuHTEntropyEnabled
        defer {
            DecoderPipeline._gpuInverse53Enabled = prevInv
            DecoderPipeline._gpuHTEntropyEnabled = prevHT
        }
        DecoderPipeline._gpuInverse53Enabled = gateOn
        DecoderPipeline._gpuHTEntropyEnabled = gateOn
        return try await J2KDecoder().decode(codestream)
    }

    // MARK: - Bit-exact pixel contract on multi-tile

    /// **Decoded pixel contract on multi-tile**: J2KImage pixel data
    /// byte-identical between default-on (post-E1.2 production) and
    /// forced-off (legacy CPU multi-tile) across every fixture × mode.
    /// E1.1 (#321) closed the codeblock-partition mis-alignment; this
    /// test pins it across the full multi-tile pipeline at default-on.
    func testMultiTileDefaultOn_DecodedPixelsIdentical_VsForcedOff() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let modes: [(label: String, mode: J2KHTTileMode)] = [
            ("2x2",     .tiles2x2),
            ("4x4",     .tiles4x4),
            ("strips4", .strips4),
        ]

        for fix in Self.fixtures {
            guard let image = loadPGM16(fix.filename) else {
                print("[skip] \(fix.label) — fixture not present")
                continue
            }
            let cfg = htConfig()

            for (modeLabel, mode) in modes {
                let layout = J2KEncodeTilePlanner.plan(
                    imageWidth: image.width, imageHeight: image.height,
                    decompositionLevels: 5, mode: mode)
                guard layout.isMultiTile else { continue }

                let codestream = try await J2KMultiTileEncoder.encode(
                    image: image, layout: layout, configuration: cfg).codestream

                let cpuImage = try await decode(codestream: codestream, gateOn: false)
                let gpuImage = try await decode(codestream: codestream, gateOn: true)

                let cpuData = cpuImage.components[0].data
                let gpuData = gpuImage.components[0].data
                XCTAssertEqual(cpuData.count, gpuData.count,
                    "[\(fix.label) \(modeLabel)] byte count mismatch")
                XCTAssertEqual(cpuData, gpuData,
                    "[\(fix.label) \(modeLabel)] decoded pixels diverged GPU vs CPU")
            }
        }
    }

    // MARK: - Wall-time A/B

    /// Wall-time A/B per (fixture, mode) cell: decode the multi-tile
    /// codestream once with the gate ON (post-E1.2 production —
    /// multi-tile through GPU) and once with the gate OFF (legacy
    /// CPU multi-tile). Prints the table; non-asserting because
    /// per-host wall time varies, the diagnostic value is the
    /// printed report.
    func testMultiTileDefaultOn_WallTimeAB_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let modes: [(label: String, mode: J2KHTTileMode)] = [
            ("2x2",     .tiles2x2),
            ("4x4",     .tiles4x4),
            ("strips4", .strips4),
        ]

        struct Row {
            let fixture: String
            let mode: String
            let cols: Int
            let rows: Int
            let pixels: Int
            let bytes: Int
            let cpuMs: Double
            let gpuMs: Double
            let speedup: Double
        }

        var rows: [Row] = []

        for fix in Self.fixtures {
            guard let image = loadPGM16(fix.filename) else { continue }
            let cfg = htConfig()

            for (modeLabel, mode) in modes {
                let layout = J2KEncodeTilePlanner.plan(
                    imageWidth: image.width, imageHeight: image.height,
                    decompositionLevels: 5, mode: mode)
                guard layout.isMultiTile else { continue }

                let codestream = try await J2KMultiTileEncoder.encode(
                    image: image, layout: layout, configuration: cfg).codestream

                // Warm: one decode each side (sets up shared session, JIT).
                _ = try await decode(codestream: codestream, gateOn: false)
                _ = try await decode(codestream: codestream, gateOn: true)

                // Measure: 5 iterations each side, take min.
                let n = 5
                var cpuMin = Double.greatestFiniteMagnitude
                var gpuMin = Double.greatestFiniteMagnitude
                for _ in 0..<n {
                    let t0 = DispatchTime.now()
                    _ = try await decode(codestream: codestream, gateOn: false)
                    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
                    cpuMin = min(cpuMin, dt)
                }
                for _ in 0..<n {
                    let t0 = DispatchTime.now()
                    _ = try await decode(codestream: codestream, gateOn: true)
                    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
                    gpuMin = min(gpuMin, dt)
                }

                rows.append(Row(
                    fixture: fix.label, mode: modeLabel,
                    cols: layout.cols, rows: layout.rows,
                    pixels: image.width * image.height,
                    bytes: codestream.count,
                    cpuMs: cpuMin, gpuMs: gpuMin,
                    speedup: cpuMin / gpuMin))
            }
        }

        let processor = String(cString: getProcessorName())

        print()
        print("=== v6.3.0 E1.2 — multi-tile decode A/B (CPU vs GPU multi-tile) ===")
        print("Processor: \(processor)")
        print("Image: HT-conformant lossless 5/3 reversible, n=5 per cell, min-of-N")
        print("Both gates default ON post-E1.2; gate-off forces legacy CPU multi-tile.")
        print()
        print("| fixture | mode | grid | px | bytes | CPU ms | GPU ms | CPU/GPU× |")
        print("|---|---|---|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %@ | %d×%d | %d | %d | %.1f | %.1f | %.2f× |",
                r.fixture, r.mode, r.cols, r.rows, r.pixels, r.bytes,
                r.cpuMs, r.gpuMs, r.speedup))
        }
        let wins = rows.filter { $0.speedup > 1.05 }.count
        let neutral = rows.filter { $0.speedup >= 0.95 && $0.speedup <= 1.05 }.count
        let losses = rows.filter { $0.speedup < 0.95 }.count
        print()
        print("Summary: \(wins) wins (>5%) · \(neutral) neutral (±5%) · \(losses) regressions (<5%) of \(rows.count) cells")
    }

    private func getProcessorName() -> [CChar] {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
        return name
    }
}
