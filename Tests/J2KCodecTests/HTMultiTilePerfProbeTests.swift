// v8 Phase 6.2 — gated to macOS: depends on CrossCodecTooling (uses Process(), unavailable on iOS).
#if os(macOS)
// HTMultiTilePerfProbeTests.swift
// v5.39 M4 / v6-alpha1 — multi-tile prototype perf probe.
//
// Measures wall-time for each tile mode (single / 2x2 / 4x4 /
// strips4 / auto) on the large medical fixtures. **Diagnostic
// only**: the prototype passes self-roundtrip for every mode but
// FAILS external cross-decode for tiles ≥ 1 (tile 0 always
// correct, tiles 1+ produce decoder-divergent pixels). Perf
// numbers below therefore indicate the architectural ceiling of
// the wrap-and-stitch path, not a viable production path. They
// ARE useful for deciding whether the architectural work to fix
// the stitcher is worth pursuing.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTMultiTilePerfProbeTests: XCTestCase {

    private func htConfig(maxThreads: Int = 8) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: maxThreads, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true, htj2kBlockFormat: .conformant)
        return cfg
    }

    private static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// Per-mode wall-time table. NOT a correctness gate — runs
    /// regardless of cross-decode validity.
    func testMultiTilePerfProbeOnLargeFixtures() async throws {
        let largeFixtures = CrossCodecTooling.medicalCorpus.filter {
            ["MR", "XA", "PX", "DX"].contains($0.modality)
        }
        let modes: [(label: String, mode: J2KHTTileMode)] = [
            ("single",  .single),
            ("2x2",     .tiles2x2),
            ("4x4",     .tiles4x4),
            ("strips4", .strips4),
        ]
        let runs = 5

        struct Cell {
            let modality: String
            let label: String
            let pixels: Int
            let mode: String
            let cols: Int
            let rows: Int
            let medianMs: Double
            let bytesOut: Int
            let observations: [J2KTileWorkObservation]
        }
        var cells: [Cell] = []

        for fixture in largeFixtures {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }

            for (modeLabel, mode) in modes {
                let cfg = htConfig()
                let layout = J2KEncodeTilePlanner.plan(
                    imageWidth: img.width, imageHeight: img.height,
                    decompositionLevels: cfg.decompositionLevels,
                    mode: mode)
                let encoder = J2KEncoder(encodingConfiguration: cfg)

                // Warm-up
                if mode == .single {
                    _ = try await encoder._singleTileEncode(img)
                } else {
                    _ = try await J2KMultiTileEncoder.encode(
                        image: img, layout: layout, configuration: cfg)
                }

                var samples: [Double] = []
                var lastBytes = 0
                var lastObs: [J2KTileWorkObservation] = []
                for _ in 0..<runs {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    if mode == .single {
                        let bytes = try await encoder._singleTileEncode(img)
                        lastBytes = bytes.count
                        lastObs = []
                    } else {
                        let result = try await J2KMultiTileEncoder.encode(
                            image: img, layout: layout, configuration: cfg)
                        lastBytes = result.codestream.count
                        lastObs = result.observations
                    }
                    samples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
                }

                cells.append(Cell(
                    modality: fixture.modality,
                    label: fixture.labelHint,
                    pixels: img.width * img.height,
                    mode: modeLabel,
                    cols: layout.cols, rows: layout.rows,
                    medianMs: Self.median(samples),
                    bytesOut: lastBytes,
                    observations: lastObs))
            }
        }

        if cells.isEmpty { throw XCTSkip("large-fixture corpus not present") }

        // Per-mode comparison table.
        print("\n=== v5.39 M4 — multi-tile perf probe (median of \(runs)) ===")
        print("(SELF-ROUNDTRIP correct for every mode; EXTERNAL cross-decode")
        print(" CURRENTLY FAILS for tile_index ≥ 1 — these numbers describe the")
        print(" architectural ceiling of the wrap-and-stitch path, NOT a viable")
        print(" production path.)")
        print()
        print("| Modality | Shape | Mode | cols×rows | Wall ms | Bytes | KB |")
        print("|---|---|---|---|---:|---:|---:|")
        for c in cells {
            print(String(format: "| %@ | %@ | %@ | %d×%d | %.2f | %d | %.1f |",
                c.modality, c.label, c.mode, c.cols, c.rows,
                c.medianMs, c.bytesOut, Double(c.bytesOut) / 1024.0))
        }

        // Speedup table: for each fixture, single → multi-tile.
        print("\n=== v5.39 M4 — speedup vs single-tile baseline (median of \(runs)) ===")
        print("| Modality | Shape | single | 2x2 | 4x4 | strips4 |")
        print("|---|---|---:|---:|---:|---:|")
        let fixtureKeys = Array(Set(cells.map { "\($0.modality)|\($0.label)" })).sorted()
        for fk in fixtureKeys {
            let parts = fk.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (mod, shape) = (parts[0], parts[1])
            let frow = cells.filter { $0.modality == mod && $0.label == shape }
            let single = frow.first(where: { $0.mode == "single" })?.medianMs ?? 0
            func ratio(_ name: String) -> String {
                guard let m = frow.first(where: { $0.mode == name }) else { return "—" }
                let speedup = single / max(m.medianMs, 0.001)
                let pct = (single - m.medianMs) / max(single, 0.001) * 100
                return String(format: "%.2f ms (%.2f×, %+.0f%%)", m.medianMs, speedup, pct)
            }
            print(String(format: "| %@ | %@ | %.2f ms | %@ | %@ | %@ |",
                mod, shape, single, ratio("2x2"), ratio("4x4"), ratio("strips4")))
        }

        // Per-tile load-balance table (for multi-tile modes).
        print("\n=== v5.39 M4 — per-tile load balance (median run, mode=2x2) ===")
        print("| Modality | Shape | Tile | Pixels | Bytes | Encode ms |")
        print("|---|---|---:|---:|---:|---:|")
        for c in cells where c.mode == "2x2" {
            for o in c.observations {
                print(String(format: "| %@ | %@ | %d | %d | %d | %.2f |",
                    c.modality, c.label, o.tileIndex, o.pixels, o.tileBytes, o.encodeMs))
            }
        }
    }
}

#endif // os(macOS)
