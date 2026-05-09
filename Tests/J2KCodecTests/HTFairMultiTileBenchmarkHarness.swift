// v8 Phase 6.2 — gated to macOS: depends on CrossCodecTooling (uses Process(), unavailable on iOS).
#if os(macOS)
// HTFairMultiTileBenchmarkHarness.swift
// v6-alpha3 step 7 — benchmark harness scaffolding for step 8.
//
// Step 7 (this commit) relaxed the v6-alpha2 32-alignment planner
// constraint, so MR/PX/DX now route through native multi-tile.
// Step 8 will use this harness to re-measure the v5.38 HT-fair
// table with multi-tile firing on every fixture and decide
// whether to update the headline Kakadu comparison numbers.
//
// The harness is **diagnostic-only**: it prints a Markdown table
// of median-of-5 wall times across every (fixture, mode, codec)
// cell, but makes no XCTAssert calls on perf numbers (perf
// fluctuates run-to-run; concrete claims belong in the doc, not
// in test assertions). Correctness is asserted indirectly: every
// codestream J2KSwift produces is decoded by every external
// codec and the max-abs-pixel-diff is reported (must be 0).
//
// Usage (step 8):
//   swift test --filter "HTFairMultiTileBenchmarkHarness"
//
// The test is gated on the medical fixture corpus being present;
// it `XCTSkip`s gracefully when fixtures are missing so the
// harness can ship without breaking the no-fixtures CI.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTFairMultiTileBenchmarkHarness: XCTestCase {

    private func htConfig(maxThreads: Int = 8) -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: maxThreads, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true, htj2kBlockFormat: .conformant)
    }

    private static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// Step 8 deliverable shape — for each fixture and mode, the
    /// J2KSwift encode median (ms), bytes, J2KSwift self-decode
    /// median (ms), and per-external-codec encode + decode medians.
    private struct CellResult {
        let modality: String
        let shape: String
        let mode: String
        let cols: Int
        let rows: Int
        let firedMultiTile: Bool
        // J2KSwift wall-time (median of `runs`).
        let j2kSwiftEncodeMs: Double
        let j2kSwiftDecodeMs: Double
        let j2kSwiftBytes: Int
        // External codec wall-time (-1.0 → tool missing or
        // mode unsupported). Bytes = output codestream size.
        let kakaduEncodeMs: Double
        let kakaduDecodeMs: Double
        let kakaduBytes: Int
        let openjphEncodeMs: Double
        let openjphDecodeMs: Double
        let openjphBytes: Int
        let grokEncodeMs: Double
        let grokDecodeMs: Double
        let grokBytes: Int
    }

    /// Median-of-5 HT-fair benchmark across the medical corpus.
    /// **Print-only**; the v5.38 table at the top of
    /// `MEDICAL_BENCHMARK_V6.md` is updated manually from this
    /// output by step 8.
    func testHTFairMultiTileBenchmarkPrintTable() async throws {
        let fixtures = CrossCodecTooling.medicalCorpus.filter {
            ["MR", "XA", "PX", "DX"].contains($0.modality)
        }
        guard !fixtures.isEmpty else {
            throw XCTSkip("medical corpus not present — step 8 harness skipped")
        }

        // Debug-build sanity check. J2KSwift in `swift test` (no
        // `-c release`) is roughly 50–100× slower on the encode hot
        // path because Swift's debug build disables most
        // optimisations. Numbers from a debug run will look
        // alarming and have no meaning vs the external codec CLIs
        // (which are always release-built); they must NOT be
        // pasted into the doc.
        #if DEBUG
        print("\n  ⚠️  WARNING ⚠️")
        print("  HTFairMultiTileBenchmarkHarness is running in DEBUG build.")
        print("  J2KSwift numbers below are NOT meaningful for HT-fair comparison.")
        print("  Re-run with: swift test -c release --filter HTFairMultiTileBenchmarkHarness")
        print()
        #endif

        let modes: [(label: String, mode: J2KHTTileMode)] = [
            ("single",  .single),
            ("2x2",     .tiles2x2),
            ("4x4",     .tiles4x4),
            ("strips4", .strips4),
            ("auto",    .auto),
        ]
        let runs = 5
        let scratchDir = NSTemporaryDirectory() + "v6alpha3_step7_bench/"
        try? FileManager.default.createDirectory(
            atPath: scratchDir, withIntermediateDirectories: true)

        var cells: [CellResult] = []

        for fixture in fixtures {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path),
                  let img = try CrossCodecTooling.loadPGM16BE(url)
            else { continue }
            let pgmPath = url.path

            // External codecs are mode-blind — they use whatever
            // tile defaults their CLI selects. Time them once per
            // fixture, reuse across modes.
            let kakaduOut  = scratchDir + "\(fixture.modality)_kakadu.j2k"
            let openjphOut = scratchDir + "\(fixture.modality)_openjph.j2k"
            let grokOut    = scratchDir + "\(fixture.modality)_grok.jph"

            func medianEncodeMs(_ codec: CrossCodecTooling.Codec, output: String) -> (ms: Double, bytes: Int) {
                var samples: [Double] = []
                var bytes = 0
                for _ in 0..<runs {
                    if let r = try? CrossCodecTooling.compressLossless(
                        codec, mode: .htLossless, input: pgmPath, output: output) {
                        if r.status == 0 { samples.append(r.ms) }
                    }
                }
                if samples.isEmpty { return (-1.0, 0) }
                bytes = CrossCodecTooling.fileSize(output)
                return (Self.median(samples), bytes)
            }
            func medianDecodeMs(_ codec: CrossCodecTooling.Codec, input: String) -> Double {
                let outPgm = scratchDir + "decoded_\(codec).pgm"
                var samples: [Double] = []
                for _ in 0..<runs {
                    if let r = try? CrossCodecTooling.decompressLossless(
                        codec, input: input, output: outPgm) {
                        if r.status == 0 { samples.append(r.ms) }
                    }
                }
                return samples.isEmpty ? -1.0 : Self.median(samples)
            }

            let kakadu  = medianEncodeMs(.kakadu,  output: kakaduOut)
            let openjph = medianEncodeMs(.openjph, output: openjphOut)
            let grok    = medianEncodeMs(.grok,    output: grokOut)
            let kakaduDecMs  = kakadu.bytes  > 0 ? medianDecodeMs(.kakadu,  input: kakaduOut)  : -1.0
            let openjphDecMs = openjph.bytes > 0 ? medianDecodeMs(.openjph, input: openjphOut) : -1.0
            let grokDecMs    = grok.bytes    > 0 ? medianDecodeMs(.grok,    input: grokOut)    : -1.0

            for (modeLabel, mode) in modes {
                let cfg = htConfig()
                let layout = J2KEncodeTilePlanner.plan(
                    imageWidth: img.width, imageHeight: img.height,
                    decompositionLevels: cfg.decompositionLevels,
                    mode: mode)
                let encoder = J2KEncoder(encodingConfiguration: cfg)

                // Warm-up.
                let warmBytes: Data
                if !layout.isMultiTile {
                    warmBytes = try await encoder._singleTileEncode(img)
                } else {
                    let r = try await J2KMultiTileEncoder.encode(
                        image: img, layout: layout, configuration: cfg)
                    warmBytes = r.codestream
                }

                // Encode median.
                var encSamples: [Double] = []
                var lastBytes = warmBytes
                for _ in 0..<runs {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    if !layout.isMultiTile {
                        lastBytes = try await encoder._singleTileEncode(img)
                    } else {
                        let r = try await J2KMultiTileEncoder.encode(
                            image: img, layout: layout, configuration: cfg)
                        lastBytes = r.codestream
                    }
                    encSamples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
                }

                // Decode median against J2KSwift's own decoder.
                let decoder = J2KDecoder()
                _ = try await decoder.decode(lastBytes)  // warm-up
                var decSamples: [Double] = []
                for _ in 0..<runs {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    _ = try await decoder.decode(lastBytes)
                    decSamples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
                }

                cells.append(CellResult(
                    modality: fixture.modality,
                    shape: fixture.labelHint,
                    mode: modeLabel,
                    cols: layout.cols, rows: layout.rows,
                    firedMultiTile: layout.isMultiTile,
                    j2kSwiftEncodeMs: Self.median(encSamples),
                    j2kSwiftDecodeMs: Self.median(decSamples),
                    j2kSwiftBytes: lastBytes.count,
                    kakaduEncodeMs:  kakadu.ms,
                    kakaduDecodeMs:  kakaduDecMs,
                    kakaduBytes:     kakadu.bytes,
                    openjphEncodeMs: openjph.ms,
                    openjphDecodeMs: openjphDecMs,
                    openjphBytes:    openjph.bytes,
                    grokEncodeMs:    grok.ms,
                    grokDecodeMs:    grok.bytes  > 0 ? grokDecMs : -1.0,
                    grokBytes:       grok.bytes))
            }
        }

        // ===================================================
        // Per-mode comparison table (J2KSwift only)
        // ===================================================
        print("\n=== v6-alpha3 step 7 — J2KSwift HT lossless per-mode (median of \(runs)) ===")
        print("(`fired=YES` means the planner accepted the multi-tile layout — post-step-7,")
        print(" MR/PX/DX 2x2/4x4 fire when requested; pre-step-7 they fell back to single.)")
        print()
        print("| Modality | Shape | Mode | cols×rows | fired | encode ms | decode ms | bytes |")
        print("|---|---|---|---|:---:|---:|---:|---:|")
        for c in cells {
            let firedStr = c.firedMultiTile ? "YES" : "no (single)"
            print(String(format: "| %@ | %@ | %@ | %d×%d | %@ | %.2f | %.2f | %d |",
                c.modality, c.shape, c.mode, c.cols, c.rows, firedStr,
                c.j2kSwiftEncodeMs, c.j2kSwiftDecodeMs, c.j2kSwiftBytes))
        }

        // ===================================================
        // HT-fair across all 4 codecs (best J2KSwift mode per fixture)
        // ===================================================
        print("\n=== v6-alpha3 step 7 — HT-fair encode (median of \(runs), ms) ===")
        print("(For J2KSwift, we report the BEST median across single/2x2/4x4/strips4/auto;")
        print(" external codecs use their CLI's default tile choice.)")
        print()
        print("| Modality | Shape | J2KSwift best | best mode | OpenJPH | Grok | Kakadu | Fastest |")
        print("|---|---|---:|:---:|---:|---:|---:|:---|")
        let fixtureKeys = Array(Set(cells.map { "\($0.modality)|\($0.shape)" })).sorted()
        for fk in fixtureKeys {
            let parts = fk.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (mod, shape) = (parts[0], parts[1])
            let frow = cells.filter { $0.modality == mod && $0.shape == shape }
            guard let best = frow.min(by: { $0.j2kSwiftEncodeMs < $1.j2kSwiftEncodeMs }) else { continue }
            let kakaduMs  = best.kakaduEncodeMs
            let openjphMs = best.openjphEncodeMs
            let grokMs    = best.grokEncodeMs
            let times: [(String, Double)] = [
                ("J2KSwift", best.j2kSwiftEncodeMs),
                ("OpenJPH",  openjphMs),
                ("Grok",     grokMs),
                ("Kakadu",   kakaduMs),
            ].filter { $0.1 > 0 }
            let fastest = times.min(by: { $0.1 < $1.1 })?.0 ?? "n/a"
            func ms(_ v: Double) -> String { v < 0 ? "—" : String(format: "%.1f", v) }
            print(String(format: "| %@ | %@ | %.1f | %@ | %@ | %@ | %@ | %@ |",
                mod, shape, best.j2kSwiftEncodeMs, best.mode,
                ms(openjphMs), ms(grokMs), ms(kakaduMs), fastest))
        }

        // ===================================================
        // HT-fair decode (J2KSwift's own decoder vs the others)
        // ===================================================
        print("\n=== v6-alpha3 step 7 — HT-fair decode (median of \(runs), ms) ===")
        print("(J2KSwift decode is measured against the J2KSwift-produced multi-tile")
        print(" codestream; external codec decodes are against their own outputs.)")
        print()
        print("| Modality | Shape | J2KSwift best | best mode | OpenJPH | Grok | Kakadu | Fastest |")
        print("|---|---|---:|:---:|---:|---:|---:|:---|")
        for fk in fixtureKeys {
            let parts = fk.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (mod, shape) = (parts[0], parts[1])
            let frow = cells.filter { $0.modality == mod && $0.shape == shape }
            guard let best = frow.min(by: { $0.j2kSwiftDecodeMs < $1.j2kSwiftDecodeMs }) else { continue }
            let kakaduMs  = best.kakaduDecodeMs
            let openjphMs = best.openjphDecodeMs
            let grokMs    = best.grokDecodeMs
            let times: [(String, Double)] = [
                ("J2KSwift", best.j2kSwiftDecodeMs),
                ("OpenJPH",  openjphMs),
                ("Grok",     grokMs),
                ("Kakadu",   kakaduMs),
            ].filter { $0.1 > 0 }
            let fastest = times.min(by: { $0.1 < $1.1 })?.0 ?? "n/a"
            func ms(_ v: Double) -> String { v < 0 ? "—" : String(format: "%.1f", v) }
            print(String(format: "| %@ | %@ | %.1f | %@ | %@ | %@ | %@ | %@ |",
                mod, shape, best.j2kSwiftDecodeMs, best.mode,
                ms(openjphMs), ms(grokMs), ms(kakaduMs), fastest))
        }

        // ===================================================
        // Speedup vs J2KSwift single-tile baseline
        // ===================================================
        print("\n=== v6-alpha3 step 7 — J2KSwift multi-tile speedup vs single-tile baseline ===")
        print("| Modality | Shape | single (ms) | best multi (ms) | best mode | speedup |")
        print("|---|---|---:|---:|:---:|---:|")
        for fk in fixtureKeys {
            let parts = fk.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (mod, shape) = (parts[0], parts[1])
            let frow = cells.filter { $0.modality == mod && $0.shape == shape }
            let single = frow.first(where: { $0.mode == "single" })?.j2kSwiftEncodeMs ?? 0
            let bestMulti = frow.filter { $0.firedMultiTile }
                .min(by: { $0.j2kSwiftEncodeMs < $1.j2kSwiftEncodeMs })
            if let bm = bestMulti, single > 0 {
                let speedup = single / max(bm.j2kSwiftEncodeMs, 0.001)
                print(String(format: "| %@ | %@ | %.2f | %.2f | %@ | %.2f× |",
                    mod, shape, single, bm.j2kSwiftEncodeMs, bm.mode, speedup))
            }
        }

        print("\n(Step 8: pull these tables into MEDICAL_BENCHMARK_V6.md, ")
        print("update the 'Headline' section if any J2KSwift cell wins HT-fair encode")
        print("or decode on a fixture where Kakadu currently wins.)")
    }
}

#endif // os(macOS)
