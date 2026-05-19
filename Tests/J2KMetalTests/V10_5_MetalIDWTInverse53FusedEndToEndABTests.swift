// V10_5_MetalIDWTInverse53FusedEndToEndABTests.swift
//
// v10.5-research Phase 6 — end-to-end warm A/B for the fused H+V
// inverse 5/3 Int Metal kernel vs the v10.3 Phase 2-2-tiled pair.
// Decodes the real MG / DX / PX medical-real corpus with the
// `inverse53IntFusedEnabled` flag toggled OFF then ON; median of
// 7 timed runs + 2 warmups per (fixture × path).
//
// Acceptance gate (v7.4 discipline): default-on requires ≥3 ms wall
// improvement on at least one MG/DX/PX fixture AND no ≥3 ms regression
// on any fixture.
//
// Run with:
//   swift test -c release --filter V10_5_MetalIDWTInverse53FusedEndToEndABTests

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_5_MetalIDWTInverse53FusedEndToEndABTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "MG small 3516×4784",  filename: "medical-real/mg_real_small_3516x4784.pgm"),
        Fixture(label: "MG mid 3518×4784",    filename: "medical-real/mg_real_mid_3518x4784.pgm"),
        Fixture(label: "MG large 3521×4784",  filename: "medical-real/mg_real_large_3521x4784.pgm"),
        Fixture(label: "DX 2800×2288",        filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX small 2224×2798",  filename: "medical-real/dx_real_small_2224x2798.pgm"),
        Fixture(label: "DX large 2544×3056",  filename: "medical-real/dx_real_large_2544x3056.pgm"),
        Fixture(label: "PX 2459×1316",        filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX mid 2793×1316",    filename: "medical-real/px_real_mid_2793x1316.pgm"),
        Fixture(label: "PX large 2812×1316",  filename: "medical-real/px_real_large_2812x1316.pgm"),
        // Regression checks at smaller sizes.
        Fixture(label: "XA 1024²",            filename: "xa_study_001_instance_000001.pgm"),
        Fixture(label: "CT 512²",             filename: "ct_study_001_instance_000001.pgm"),
    ]

    private func loadPGM16(_ filename: String) throws -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path) else { return nil }
        let raw = try Data(contentsOf: here)
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
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

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func bench(
        decoder: J2KDecoder, codestream: Data, n: Int, warmups: Int
    ) async throws -> Double {
        for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
        var times: [Double] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try await decoder.decode(codestream)
            times.append(Date().timeIntervalSince(t0) * 1000)
        }
        return times.sorted()[n / 2]
    }

    func testFusedEndToEndAB_MedicalCorpus() async throws {
        let n = 7
        let warmups = 2
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        struct Row {
            let label: String
            let pixels: Int
            let tiledMs: Double
            let fusedMs: Double
            let delta: Double
            let pct: Double
        }

        var rows: [Row] = []
        var skipped: [String] = []

        let prevThreshold = J2KMetalDWT.inverse53IntFusedPixelThreshold
        defer { J2KMetalDWT.inverse53IntFusedPixelThreshold = prevThreshold }
        // Lower threshold to 0 so the fused path actually runs at all
        // sizes; otherwise production's 12 MP gate would silently
        // route smaller fixtures back through tiled and the A/B
        // would compare tiled-vs-tiled on those rows.
        J2KMetalDWT.inverse53IntFusedPixelThreshold = 0

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }
            let codestream = try await encoder.encode(image)

            // Tiled — v10.3 Phase 2-2-tiled default-on path.
            J2KMetalDWT.inverse53IntTiledEnabled = true
            J2KMetalDWT.inverse53IntFusedEnabled = false
            let tiledMs = try await bench(
                decoder: decoder, codestream: codestream,
                n: n, warmups: warmups)

            // Fused — v10.5 Phase 2-3-fused single-kernel path.
            J2KMetalDWT.inverse53IntTiledEnabled = false
            J2KMetalDWT.inverse53IntFusedEnabled = true
            let fusedMs = try await bench(
                decoder: decoder, codestream: codestream,
                n: n, warmups: warmups)

            let delta = tiledMs - fusedMs
            let pct = 100 * delta / tiledMs
            rows.append(Row(
                label: fix.label, pixels: image.width * image.height,
                tiledMs: tiledMs, fusedMs: fusedMs,
                delta: delta, pct: pct))
        }

        // Restore tiled default-on.
        J2KMetalDWT.inverse53IntTiledEnabled = true
        J2KMetalDWT.inverse53IntFusedEnabled = false

        print("=== v10.5 Phase 2-3-fused IDWT end-to-end A/B (M2 release, in-proc) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Runs: \(n)")
        if !skipped.isEmpty {
            print("Skipped: \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | tiled ms | fused ms | Δ ms | Δ % |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.2f | %+5.1f%% |",
                         r.label, r.pixels,
                         r.tiledMs, r.fusedMs, r.delta, r.pct))
        }
        print("")
        print("Acceptance gate (v7.4): ≥3 ms wall lift on at least one MG/DX/PX,")
        print("                        AND no fixture regresses by ≥3 ms.")

        XCTAssertFalse(rows.isEmpty, "No fixtures benched")
    }
}
#endif
