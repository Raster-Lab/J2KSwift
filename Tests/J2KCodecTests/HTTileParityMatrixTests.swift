// HTTileParityMatrixTests.swift
// v6-alpha2 — parity matrix for the M4 multi-tile cross-decode bug.
//
// M4 (parked) found that the wrap-and-stitch multi-tile path produces
// codestreams that J2KSwift roundtrips losslessly but external HT
// decoders (OpenJPH / Grok / Kakadu) reconstruct with wrong pixels
// for every tile with index ≥ 1. M4's hypothesis: JPEG 2000 5/3
// reversible DWT lifting has a parity-of-tile-origin gotcha — when
// tile k's image-coordinate origin has odd x or y, the DWT lifting
// step's starting parity flips relative to standalone-image encode.
//
// This test isolates that hypothesis empirically by enumerating
// (fixture, tile-mode) combinations whose tile-origin parities are
// known a priori, encoding via the M4 multi-tile path, and running
// each through `kdu_expand` and comparing pixels. Predictions:
//   - All-EVEN-origin tiles cross-decode bit-exact.
//   - ANY-ODD-origin tiles cross-decode with wrong pixels.
//
// SCOPE: HT lossless only. Profile-only — no perf assertions, just
// structured cross-decode results and per-tile-origin parity.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTTileParityMatrixTests: XCTestCase {

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true, htj2kBlockFormat: .conformant)
    }

    /// Compute the per-tile origin grid given (image dims, tile mode).
    /// Returns array of (col, row, originX, originY, tileW, tileH).
    private static func tileOrigins(
        imageW: Int, imageH: Int, mode: J2KHTTileMode
    ) -> [(col: Int, row: Int, x: Int, y: Int, w: Int, h: Int)] {
        let (cols, rows): (Int, Int)
        switch mode {
        case .single:    (cols, rows) = (1, 1)
        case .tiles2x2:  (cols, rows) = (2, 2)
        case .tiles4x4:  (cols, rows) = (4, 4)
        case .strips4:   (cols, rows) = (1, 4)
        case .auto:      (cols, rows) = (2, 2)
        }
        let tileW = (imageW + cols - 1) / cols
        let tileH = (imageH + rows - 1) / rows
        var out: [(Int, Int, Int, Int, Int, Int)] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let x = c * tileW
                let y = r * tileH
                let w = min(tileW, imageW - x)
                let h = min(tileH, imageH - y)
                out.append((c, r, x, y, w, h))
            }
        }
        return out
    }

    private static func parityLabel(_ origins: [(col: Int, row: Int, x: Int, y: Int, w: Int, h: Int)]) -> String {
        let allEven = origins.allSatisfy { $0.x % 2 == 0 && $0.y % 2 == 0 }
        let anyOdd = origins.contains { $0.x % 2 == 1 || $0.y % 2 == 1 }
        if origins.count == 1 { return "single" }
        if allEven { return "ALL-EVEN" }
        if anyOdd  { return "ANY-ODD"  }
        return "mixed"
    }

    /// For each (fixture, mode), report:
    ///   - tile origin parities
    ///   - self-roundtrip MAE
    ///   - cross-decode result via OpenJPH, Grok, Kakadu (max abs diff)
    /// Prints a comprehensive parity matrix table.
    func testTileParityMatrixOnLargeFixtures() async throws {
        let fixtures = CrossCodecTooling.medicalCorpus.filter {
            ["MR", "XA", "PX", "DX"].contains($0.modality)
        }
        // Modes that produce multi-tile (skip 'single' and 'auto' — auto duplicates 2x2).
        let modes: [(label: String, mode: J2KHTTileMode)] = [
            ("2x2",     .tiles2x2),
            ("4x4",     .tiles4x4),
            ("strips4", .strips4),
        ]
        let codecs: [CrossCodecTooling.Codec] = [.openjph, .grok, .kakadu]

        struct Row: Sendable {
            let fixture: String
            let shape: String
            let mode: String
            let tileOrigins: [(col: Int, row: Int, x: Int, y: Int, w: Int, h: Int)]
            let parityLabel: String
            let bytesOut: Int
            let selfRoundTripMaxDiff: Int  // 0 = bit-exact
            let crossDecodeMaxDiff: [String: Int]  // codec name → max abs diff (-1 = decoder failed)
        }
        var rows: [Row] = []

        let scratchDir = NSTemporaryDirectory() + "v6alpha2_parity/"
        try? FileManager.default.createDirectory(
            atPath: scratchDir, withIntermediateDirectories: true)

        for fixture in fixtures {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }
            let cfg = htConfig()
            let encoder = J2KEncoder(encodingConfiguration: cfg)

            for (modeLabel, mode) in modes {
                let origins = Self.tileOrigins(imageW: img.width, imageH: img.height, mode: mode)
                let parity = Self.parityLabel(origins)

                let layout = J2KEncodeTilePlanner.plan(
                    imageWidth: img.width, imageHeight: img.height,
                    decompositionLevels: 5, mode: mode)
                guard layout.isMultiTile else { continue }

                let result = try await J2KMultiTileEncoder.encode(
                    image: img, layout: layout, configuration: cfg)

                // Self-roundtrip
                let decoder = J2KDecoder()
                let decoded = try await decoder.decode(result.codestream)
                let selfMaxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decoded)

                // Write codestream to tmpfile for external decoders
                let stem = "\(fixture.modality)_\(fixture.labelHint.replacingOccurrences(of: "×", with: "x"))_\(modeLabel)"
                let codeStreamPath = scratchDir + stem + ".j2k"
                try result.codestream.write(to: URL(fileURLWithPath: codeStreamPath))

                var crossMaxDiff: [String: Int] = [:]
                for codec in codecs {
                    let outPath = scratchDir + stem + "_\(codec).pgm"
                    let dec = try CrossCodecTooling.decompressLossless(
                        codec, input: codeStreamPath, output: outPath)
                    if dec.status != 0 {
                        crossMaxDiff[codec.rawValue] = -1
                    } else if let crossImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: outPath)) {
                        crossMaxDiff[codec.rawValue] = CrossCodecTooling.maxAbsPixelDiff(img, crossImg)
                    } else {
                        crossMaxDiff[codec.rawValue] = -1
                    }
                }

                rows.append(Row(
                    fixture: fixture.modality,
                    shape: fixture.labelHint,
                    mode: modeLabel,
                    tileOrigins: origins,
                    parityLabel: parity,
                    bytesOut: result.codestream.count,
                    selfRoundTripMaxDiff: selfMaxDiff,
                    crossDecodeMaxDiff: crossMaxDiff))
            }
        }

        if rows.isEmpty { throw XCTSkip("no large fixtures present") }

        // Pretty-print the parity matrix.
        print("\n=== v6-alpha2 — tile parity matrix ===")
        print("(Self-RT max diff = 0 means bit-exact; cross-decode max diff > 0 = decoder mismatch)")
        print()
        print("| Modality | Shape | Mode | Cols×Rows | Tile origins | Parity | Self RT diff | OpenJPH diff | Grok diff | Kakadu diff |")
        print("|---|---|---|---|---|---|---:|---:|---:|---:|")
        for r in rows {
            let layout = "\(r.tileOrigins.map{ $0.col }.max()! + 1)×\(r.tileOrigins.map{ $0.row }.max()! + 1)"
            // Show distinct origin x and y values
            let xs = Array(Set(r.tileOrigins.map { $0.x })).sorted()
            let ys = Array(Set(r.tileOrigins.map { $0.y })).sorted()
            let originsStr = "(x:\(xs.map(String.init).joined(separator: ",")) y:\(ys.map(String.init).joined(separator: ",")))"
            let oj = r.crossDecodeMaxDiff["openjph"] ?? -1
            let gk = r.crossDecodeMaxDiff["grok"] ?? -1
            let kd = r.crossDecodeMaxDiff["kakadu"] ?? -1
            print(String(format: "| %@ | %@ | %@ | %@ | %@ | %@ | %d | %@ | %@ | %@ |",
                r.fixture, r.shape, r.mode, layout, originsStr, r.parityLabel,
                r.selfRoundTripMaxDiff,
                oj == -1 ? "FAIL" : "\(oj)",
                gk == -1 ? "FAIL" : "\(gk)",
                kd == -1 ? "FAIL" : "\(kd)"))
        }

        // Headline summary: do all-even-origin cells pass cross-decode?
        print("\n=== v6-alpha2 — parity hypothesis check ===")
        let allEvenRows = rows.filter { $0.parityLabel == "ALL-EVEN" }
        let anyOddRows  = rows.filter { $0.parityLabel == "ANY-ODD" }
        print("ALL-EVEN cells: \(allEvenRows.count) — cross-decode pass count (max diff = 0):")
        for codec in ["openjph", "grok", "kakadu"] {
            let n = allEvenRows.filter { ($0.crossDecodeMaxDiff[codec] ?? -1) == 0 }.count
            print("  \(codec): \(n)/\(allEvenRows.count)")
        }
        print("ANY-ODD cells: \(anyOddRows.count) — cross-decode pass count (max diff = 0):")
        for codec in ["openjph", "grok", "kakadu"] {
            let n = anyOddRows.filter { ($0.crossDecodeMaxDiff[codec] ?? -1) == 0 }.count
            print("  \(codec): \(n)/\(anyOddRows.count)")
        }
    }
}
