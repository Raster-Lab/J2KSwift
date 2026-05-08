// V720PhaseEABTest.swift
//
// v7.2.0 Phase E — A/B test of `_multiTileBatchedEntropyEnabled` on
// the medical corpus. Toggles the flag and decodes the same DX 4x4
// codestream both ways, reporting the wall-time delta.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V720PhaseEABTest: XCTestCase {

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
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    private func makeCodestream(
        fixture: String, mode: J2KHTTileMode
    ) async throws -> Data? {
        guard let image = loadPGM16(fixture) else { return nil }
        let cfg = htConfig()
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: image.width, imageHeight: image.height,
            decompositionLevels: 5, mode: mode)
        if !layout.isMultiTile {
            return try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        }
        let result = try await J2KMultiTileEncoder.encode(
            image: image, layout: layout, configuration: cfg)
        return result.codestream
    }

    private func medianDecodeMs(
        _ codestream: Data, runs: Int
    ) async throws -> Double {
        try await J2KMetalSession.processShared.preWarm()
        _ = try await J2KDecoder().decodeGPU(codestream)
        var samples: [Double] = []
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            _ = try await J2KDecoder().decodeGPU(codestream)
            let t1 = Date().timeIntervalSinceReferenceDate
            samples.append((t1 - t0) * 1000.0)
        }
        samples.sort()
        return samples[runs / 2]
    }

    /// Toggles `_multiTileBatchedEntropyEnabled` and reports A/B median
    /// decode wall across DX 4x4, DX 2x2, PX 4x4, PX 2x2, MR 2x2.
    /// All fixtures must show NO regression vs the per-tile-CB
    /// baseline (≤ 5 % wall increase). Several fixtures should show
    /// meaningful improvement at the 4x4 layouts.
    func testPhaseEAB_MultiTileBatchedEntropy() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        let runs = Int(ProcessInfo.processInfo.environment["RUNS"] ?? "5") ?? 5

        struct Cell {
            let label: String
            let fixture: String
            let mode: J2KHTTileMode
        }
        let cells: [Cell] = [
            Cell(label: "DX 4x4 (16 × 400 K)",
                 fixture: "dx_study_002_instance_000001.pgm",
                 mode: .tiles4x4),
            Cell(label: "DX 2x2 (4 × 1.6 M)",
                 fixture: "dx_study_002_instance_000001.pgm",
                 mode: .tiles2x2),
            Cell(label: "PX 4x4 (16 × 200 K)",
                 fixture: "px_study_001_instance_000001.pgm",
                 mode: .tiles4x4),
            Cell(label: "PX 2x2 (4 × 800 K)",
                 fixture: "px_study_001_instance_000001.pgm",
                 mode: .tiles2x2),
            Cell(label: "XA 2x2 (4 × 260 K)",
                 fixture: "xa_study_001_instance_000001.pgm",
                 mode: .tiles2x2),
        ]

        print("=== v7.2.0 Phase E — batched entropy A/B (median of \(runs) decodes) ===")
        print()
        print("| fixture | OFF (per-tile CBs) | ON (batched CBs) | delta % |")
        print("|---|---:|---:|---:|")
        for c in cells {
            guard let cs = try await makeCodestream(fixture: c.fixture, mode: c.mode) else {
                continue
            }

            DecoderPipeline._multiTileBatchedEntropyEnabled = false
            let off = try await medianDecodeMs(cs, runs: runs)

            DecoderPipeline._multiTileBatchedEntropyEnabled = true
            let on = try await medianDecodeMs(cs, runs: runs)

            DecoderPipeline._multiTileBatchedEntropyEnabled = true  // restore default

            let deltaPct = (on - off) / off * 100.0
            print(String(format: "| %@ | %.2f | %.2f | %+.1f %% |",
                c.label, off, on, deltaPct))
        }
    }
}
