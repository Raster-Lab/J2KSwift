// v8 Phase 6.2 — gated to macOS: depends on CrossCodecTooling (uses Process(), unavailable on iOS).
#if os(macOS)
// J2KLosslessMedicalGateTests.swift
// v5.38 lossless-only — milestone M1 scaffolding.
//
// SCOPE: J2KSwift lossless encode + CPU decode roundtrip across the
// medical corpus. Pure self-test, no external codecs invoked here.
// External codec columns (OpenJPEG, OpenJPH, Grok, Kakadu) land in
// M2 by extending this same test.
//
// What this gate proves at M1:
//   1. Every medical fixture roundtrips bit-exact through
//      J2KEncoder(.lossless).encode → J2KDecoder.decode (MAE = 0).
//   2. Per-fixture encode and decode wall-clock timings are captured
//      in a markdown table the user can paste into MEDICAL_BENCHMARK.md.
//
// Pass gate (this file): every present fixture rounds trips
// bit-exact. Missing fixtures `XCTSkip` rather than fail.
//
// What this file deliberately does NOT do (parked per v5.38 scope):
//   - No `.constantBitrateStrict`, no Qstep search, no R-D selection.
//   - No PSNR-per-byte tuning. PSNR is ∞ for lossless; we just
//     assert byte-exact match.
//   - No 9/7 lossy variant.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KLosslessMedicalGateTests: XCTestCase {

    /// HT lossless config: HTJ2K conformant + reversible 5/3 + single
    /// quality layer + LRCP. Production default for lossless;
    /// produces codestreams interoperable with OpenJPH and Part-15
    /// HT-aware decoders.
    private func losslessConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    /// EBCOT lossless config: classic Part-1 EBCOT entropy coder +
    /// reversible 5/3. Produces denser codestreams than HT lossless
    /// (~13-15% smaller for high-bit-depth medical content) at the
    /// cost of encode/decode parallelism. Available as a non-default
    /// path; tested here so the M4 comparison can document the format
    /// trade-off transparently.
    private func ebcotLosslessConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: false,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    // MARK: - M1 gate

    func testLosslessRoundTripBitExactAcrossMedicalCorpus() async throws {
        var rows: [(modality: String, label: String, pixels: Int,
                    rawBytes: Int, j2kBytes: Int,
                    encMs: Double, decMs: Double, ratioVsRaw: Double)] = []
        var ranAtLeastOne = false

        for fixture in CrossCodecTooling.medicalCorpus {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else {
                continue
            }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else {
                continue
            }
            ranAtLeastOne = true

            let cfg = losslessConfig()
            let encoder = J2KEncoder(encodingConfiguration: cfg)
            let decoder = J2KDecoder()

            // Warm-up encode + decode (caches, JIT-style first-touch
            // costs) to keep the measurement-pass timing stable.
            let warmEncoded = try await encoder.encode(img)
            _ = try await decoder.decode(warmEncoded)

            // Measurement pass.
            let encStart = CFAbsoluteTimeGetCurrent()
            let encoded = try await encoder.encode(img)
            let encMs = (CFAbsoluteTimeGetCurrent() - encStart) * 1000.0

            let decStart = CFAbsoluteTimeGetCurrent()
            let decoded = try await decoder.decode(encoded)
            let decMs = (CFAbsoluteTimeGetCurrent() - decStart) * 1000.0

            // Bit-exact roundtrip — the lossless contract.
            let exact = CrossCodecTooling.bitExactPixelMatch(img, decoded)
            if !exact {
                let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decoded)
                XCTFail("\(fixture.modality) \(fixture.path): lossless roundtrip not bit-exact (max abs diff = \(maxDiff))")
            }

            let pixels = img.width * img.height * img.componentCount
            let bytesPerSample = (img.components[0].bitDepth + 7) / 8
            let rawBytes = pixels * bytesPerSample
            let ratioVsRaw = Double(rawBytes) / Double(encoded.count)

            rows.append((
                modality: fixture.modality,
                label: fixture.labelHint.isEmpty ? "\(img.width)×\(img.height)" : fixture.labelHint,
                pixels: pixels,
                rawBytes: rawBytes,
                j2kBytes: encoded.count,
                encMs: encMs,
                decMs: decMs,
                ratioVsRaw: ratioVsRaw))
        }

        if !ranAtLeastOne {
            throw XCTSkip("medical corpus fixtures not present")
        }

        // Print a markdown table the user can paste into
        // MEDICAL_BENCHMARK.md. M2 extends this with codec columns.
        print("\n=== v5.38 M1 — J2KSwift lossless roundtrip across medical corpus ===")
        print("| Modality | Shape | Raw KB | J2KSwift KB | Ratio vs raw | Encode ms | Decode ms |")
        print("|---|---|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %@ | %d | %d | %.2fx | %.1f | %.1f |",
                         r.modality, r.label,
                         r.rawBytes / 1024,
                         r.j2kBytes / 1024,
                         r.ratioVsRaw,
                         r.encMs,
                         r.decMs))
        }
    }

    // MARK: - Format-fair cross-codec matrix (default / HT / EBCOT)

    /// Per-(codec, fixture) result captured by the matrix runner.
    /// `availability == .unsupported` means the codec's CLI build
    /// can't produce the requested format — printed as `N/A` rather
    /// than faked.
    private struct CodecRow {
        enum Availability { case ok, missingTool, unsupported }
        let codec: String
        var encMs: Double = 0
        var decMs: Double = 0
        var outBytes: Int = 0
        var roundTripBitExact: Bool = false
        var crossDecodeBitExact: Bool = false
        var availability: Availability = .missingTool
    }
    private struct FixtureReport {
        let modality: String
        let label: String
        let pixels: Int
        let rawBytes: Int
        var j2kSwiftBytes: Int
        var j2kSwiftEncMs: Double
        var j2kSwiftDecMs: Double
        var codecs: [CodecRow]
    }

    /// Median of `samples`. Caller passes a non-empty array.
    private static func median(_ samples: [Double]) -> Double {
        precondition(!samples.isEmpty)
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// Run one (J2KSwift config, external-codec mode) sweep across
    /// the medical corpus, taking the **median of 5** encode and
    /// decode times per (codec, fixture). Returns one `FixtureReport`
    /// per fixture.
    ///
    /// Per-(codec, fixture) gates that fail the test on violation:
    ///   - J2KSwift self-roundtrip bit-exact (MAE = 0)
    ///   - external self-roundtrip bit-exact (MAE = 0)
    ///   - external cross-decode of J2KSwift codestream bit-exact,
    ///     **only when both J2KSwift and external are emitting the
    ///     same format** — i.e., HT-fair sweep cross-decodes; EBCOT-
    ///     fair sweep cross-decodes; default-mode sweep cross-decodes
    ///     only where defaults align (J2KSwift HT → OpenJPH HT works,
    ///     J2KSwift HT → OpenJPEG EBCOT does not — the latter is
    ///     skipped, not failed).
    ///
    /// Encoded byte counts are checked deterministic across the 5
    /// runs (a fail flags an encoder non-determinism regression).
    private func runCrossCodecMatrix(
        j2kConfig: J2KEncodingConfiguration,
        externalMode: CrossCodecTooling.LosslessMode,
        formatFairCrossDecode: Bool,
        runs: Int = 5,
        sectionLabel: String,
        tempSubdir: String
    ) async throws -> [FixtureReport] {
        var reports: [FixtureReport] = []
        let tempDir = NSTemporaryDirectory().appending(tempSubdir)
        try? FileManager.default.removeItem(atPath: tempDir)
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)

        for fixture in CrossCodecTooling.medicalCorpus {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }

            let pixels = img.width * img.height * img.componentCount
            let bytesPerSample = (img.components[0].bitDepth + 7) / 8
            let rawBytes = pixels * bytesPerSample

            // J2KSwift: median-of-N encode + decode.
            let encoder = J2KEncoder(encodingConfiguration: j2kConfig)
            let decoder = J2KDecoder()
            // Warm up encode AND decode (Metal lazy-init can pollute
            // the first measured decode by ~40-50 ms on M1).
            let warmData = try await encoder.encode(img)
            _ = try await decoder.decode(warmData)

            var encSamples: [Double] = []
            var decSamples: [Double] = []
            var lastBytes: Int = 0
            for _ in 0..<runs {
                let encStart = CFAbsoluteTimeGetCurrent()
                let data = try await encoder.encode(img)
                encSamples.append((CFAbsoluteTimeGetCurrent() - encStart) * 1000.0)
                XCTAssertTrue(lastBytes == 0 || lastBytes == data.count,
                    "J2KSwift encode non-deterministic: \(fixture.modality) \(fixture.labelHint) — \(lastBytes) vs \(data.count)")
                lastBytes = data.count
                let decStart = CFAbsoluteTimeGetCurrent()
                let decoded = try await decoder.decode(data)
                decSamples.append((CFAbsoluteTimeGetCurrent() - decStart) * 1000.0)
                XCTAssertTrue(CrossCodecTooling.bitExactPixelMatch(img, decoded),
                    "J2KSwift self-roundtrip not bit-exact: \(fixture.modality) \(fixture.labelHint)")
            }
            let j2kEncMs = Self.median(encSamples)
            let j2kDecMs = Self.median(decSamples)
            let j2kBytes = lastBytes

            // Persist the J2KSwift codestream once for cross-decode
            // attempts later. Use a uniform `.j2k` extension; that's
            // valid on every external decoder we use.
            let j2kSwiftPath = tempDir + "j2kswift_\(fixture.modality)_\(fixture.labelHint).j2k"
            // Re-encode once into a Data we can write to disk.
            let j2kData = try await encoder.encode(img)
            try j2kData.write(to: URL(fileURLWithPath: j2kSwiftPath))

            // Per-external-codec roundtrip + (optionally) cross-decode.
            var codecRows: [CodecRow] = []
            for codec in CrossCodecTooling.Codec.allCases {
                var row = CodecRow(codec: codec.rawValue)
                if !CrossCodecTooling.codecSupports(codec, mode: externalMode) {
                    row.availability = .unsupported
                    codecRows.append(row); continue
                }
                if CrossCodecTooling.findTool(codec.compressTool) == nil {
                    row.availability = .missingTool
                    codecRows.append(row); continue
                }
                row.availability = .ok

                let inPath = url.path
                let ext = CrossCodecTooling.compressedExtension(codec, mode: externalMode)
                let outPath = tempDir + "\(codec.rawValue)_\(fixture.modality)_\(fixture.labelHint)\(ext)"
                let outPGM = tempDir + "\(codec.rawValue)_\(fixture.modality)_\(fixture.labelHint)_dec.pgm"
                let crossPGM = tempDir + "\(codec.rawValue)_\(fixture.modality)_\(fixture.labelHint)_crossdec.pgm"

                // External compress: median-of-N (with deterministic
                // bytes invariant on every run).
                var compSamples: [Double] = []
                var compBytes: Int = 0
                for runIdx in 0..<runs {
                    let comp = try CrossCodecTooling.compressLossless(
                        codec, mode: externalMode, input: inPath, output: outPath)
                    XCTAssertEqual(comp.status, 0,
                        "\(codec) [\(externalMode)] compress failed on \(fixture.modality) \(fixture.labelHint)")
                    let bytes = CrossCodecTooling.fileSize(outPath)
                    if runIdx > 0 {
                        XCTAssertEqual(bytes, compBytes,
                            "\(codec) [\(externalMode)] non-deterministic bytes on \(fixture.modality) \(fixture.labelHint)")
                    }
                    compBytes = bytes
                    compSamples.append(comp.ms)
                }
                row.encMs = Self.median(compSamples)
                row.outBytes = compBytes

                // External decompress: median-of-N + once-per-fixture
                // bit-exact roundtrip check.
                var decSamples: [Double] = []
                for _ in 0..<runs {
                    let dec = try CrossCodecTooling.decompressLossless(
                        codec, input: outPath, output: outPGM)
                    XCTAssertEqual(dec.status, 0,
                        "\(codec) decompress failed on \(fixture.modality) \(fixture.labelHint)")
                    decSamples.append(dec.ms)
                }
                row.decMs = Self.median(decSamples)
                if let decImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: outPGM)) {
                    row.roundTripBitExact = CrossCodecTooling.bitExactPixelMatch(img, decImg)
                    if !row.roundTripBitExact {
                        let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decImg)
                        XCTFail("\(codec) [\(externalMode)] self-roundtrip not bit-exact on \(fixture.modality) \(fixture.labelHint): max abs diff = \(maxDiff)")
                    }
                }

                // Cross-decode: only meaningful when J2KSwift and the
                // external codec emit the same format. If
                // `formatFairCrossDecode` is true, exercise it; if
                // false (default-mode sweep mixes formats), we still
                // try cross-decode where it's known to work (HT↔HT
                // and skip silently otherwise — the default-mode
                // sweep's cross-decode column is informative not
                // gating).
                let externalIsHT = (externalMode == .htLossless)
                                || (externalMode == .defaultLossless && codec == .openjph)
                let j2kIsHT = j2kConfig.useHTJ2K
                let formatsAlign = formatFairCrossDecode || (externalIsHT == j2kIsHT)
                if formatsAlign {
                    let cross = try CrossCodecTooling.decompressLossless(
                        codec, input: j2kSwiftPath, output: crossPGM)
                    if cross.status == 0,
                       let crossImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: crossPGM)) {
                        row.crossDecodeBitExact = CrossCodecTooling.bitExactPixelMatch(img, crossImg)
                        if !row.crossDecodeBitExact {
                            let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, crossImg)
                            XCTFail("J2KSwift→\(codec) [\(externalMode)] cross-decode not bit-exact on \(fixture.modality) \(fixture.labelHint): max abs diff = \(maxDiff)")
                        }
                    } else {
                        // formatFairCrossDecode means we EXPECT it to
                        // work; status != 0 is a failure to flag.
                        if formatFairCrossDecode {
                            XCTFail("J2KSwift→\(codec) [\(externalMode)] cross-decode failed (status \(cross.status)) on \(fixture.modality) \(fixture.labelHint)")
                        }
                    }
                }

                codecRows.append(row)
            }

            reports.append(FixtureReport(
                modality: fixture.modality,
                label: fixture.labelHint.isEmpty ? "\(img.width)×\(img.height)" : fixture.labelHint,
                pixels: pixels, rawBytes: rawBytes,
                j2kSwiftBytes: j2kBytes,
                j2kSwiftEncMs: j2kEncMs,
                j2kSwiftDecMs: j2kDecMs,
                codecs: codecRows))
        }

        if reports.isEmpty { throw XCTSkip("medical corpus fixtures not present") }

        // ---- Print Bytes table ----
        print("\n=== v5.38 \(sectionLabel) — Lossless BYTES + RATIO (median of \(runs) runs) ===")
        print("| Modality | Shape | Raw KB | J2KSwift KB | OpenJPEG KB | OpenJPH KB | Grok KB | Kakadu KB | J2KSwift× | OpenJPEG× | OpenJPH× | Grok× | Kakadu× |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in reports {
            func cell(_ name: String) -> CodecRow? {
                r.codecs.first(where: { $0.codec == name })
            }
            let opj = cell("openjpeg"); let oph = cell("openjph")
            let grk = cell("grok"); let kdu = cell("kakadu")
            func kb(_ row: CodecRow?) -> String {
                guard let row = row else { return "—" }
                switch row.availability {
                case .ok: return "\(row.outBytes / 1024)"
                case .unsupported: return "N/A"
                case .missingTool: return "—"
                }
            }
            func ratio(_ row: CodecRow?) -> String {
                guard let row = row, row.availability == .ok, row.outBytes > 0 else {
                    return row?.availability == .unsupported ? "N/A" : "—"
                }
                return String(format: "%.2f", Double(r.rawBytes) / Double(row.outBytes)) + "×"
            }
            let j2kKB = r.j2kSwiftBytes / 1024
            let j2kRatio = String(format: "%.2f", Double(r.rawBytes) / Double(r.j2kSwiftBytes))
            print("| \(r.modality) | \(r.label) | \(r.rawBytes / 1024) | \(j2kKB) | \(kb(opj)) | \(kb(oph)) | \(kb(grk)) | \(kb(kdu)) | \(j2kRatio)× | \(ratio(opj)) | \(ratio(oph)) | \(ratio(grk)) | \(ratio(kdu)) |")
        }

        // ---- Encode timing table + per-row fastest ----
        print("\n=== v5.38 \(sectionLabel) — Lossless ENCODE TIME (ms, median of \(runs)) ===")
        print("| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |")
        print("|---|---|---:|---:|---:|---:|---:|:---|---:|")
        for r in reports {
            func t(_ name: String) -> (String, Double?) {
                guard let row = r.codecs.first(where: { $0.codec == name }) else {
                    return ("—", nil)
                }
                switch row.availability {
                case .ok: return (String(format: "%.1f", row.encMs), row.encMs)
                case .unsupported: return ("N/A", nil)
                case .missingTool: return ("—", nil)
                }
            }
            let pairs: [(String, (String, Double?))] = [
                ("J2KSwift", (String(format: "%.1f", r.j2kSwiftEncMs), r.j2kSwiftEncMs)),
                ("OpenJPEG", t("openjpeg")),
                ("OpenJPH", t("openjph")),
                ("Grok", t("grok")),
                ("Kakadu", t("kakadu")),
            ]
            let times = pairs.compactMap { (name, p) -> (String, Double)? in
                p.1.map { (name, $0) }
            }
            let sorted = times.sorted { $0.1 < $1.1 }
            let fastest = sorted.first.map { $0.0 } ?? "—"
            let margin: String
            if sorted.count >= 2 {
                let next = sorted[1]
                let delta = next.1 - sorted[0].1
                let ratioX = next.1 / sorted[0].1
                margin = ratioX >= 1.5
                    ? String(format: "%.1f× → %@", ratioX, next.0)
                    : String(format: "+%.1f ms → %@", delta, next.0)
            } else {
                margin = "—"
            }
            print(String(format: "| %@ | %@ | %@ | %@ | %@ | %@ | %@ | %@ | %@ |",
                         r.modality, r.label,
                         pairs[0].1.0, pairs[1].1.0, pairs[2].1.0, pairs[3].1.0, pairs[4].1.0,
                         fastest, margin))
        }

        // ---- Decode timing table + per-row fastest ----
        print("\n=== v5.38 \(sectionLabel) — Lossless DECODE TIME (ms, median of \(runs)) ===")
        print("| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu | Fastest | Margin → next |")
        print("|---|---|---:|---:|---:|---:|---:|:---|---:|")
        for r in reports {
            func t(_ name: String) -> (String, Double?) {
                guard let row = r.codecs.first(where: { $0.codec == name }) else {
                    return ("—", nil)
                }
                switch row.availability {
                case .ok: return (String(format: "%.1f", row.decMs), row.decMs)
                case .unsupported: return ("N/A", nil)
                case .missingTool: return ("—", nil)
                }
            }
            let pairs: [(String, (String, Double?))] = [
                ("J2KSwift", (String(format: "%.1f", r.j2kSwiftDecMs), r.j2kSwiftDecMs)),
                ("OpenJPEG", t("openjpeg")),
                ("OpenJPH", t("openjph")),
                ("Grok", t("grok")),
                ("Kakadu", t("kakadu")),
            ]
            let times = pairs.compactMap { (name, p) -> (String, Double)? in
                p.1.map { (name, $0) }
            }
            let sorted = times.sorted { $0.1 < $1.1 }
            let fastest = sorted.first.map { $0.0 } ?? "—"
            let margin: String
            if sorted.count >= 2 {
                let next = sorted[1]
                let delta = next.1 - sorted[0].1
                let ratioX = next.1 / sorted[0].1
                margin = ratioX >= 1.5
                    ? String(format: "%.1f× → %@", ratioX, next.0)
                    : String(format: "+%.1f ms → %@", delta, next.0)
            } else {
                margin = "—"
            }
            print(String(format: "| %@ | %@ | %@ | %@ | %@ | %@ | %@ | %@ | %@ |",
                         r.modality, r.label,
                         pairs[0].1.0, pairs[1].1.0, pairs[2].1.0, pairs[3].1.0, pairs[4].1.0,
                         fastest, margin))
        }

        // ---- Roundtrip + cross-decode matrix ----
        print("\n=== v5.38 \(sectionLabel) — Roundtrip + cross-decode matrix ===")
        print("| Modality | Shape | OpenJPEG self | OpenJPH self | Grok self | Kakadu self | OpenJPEG ←J2K | OpenJPH ←J2K | Grok ←J2K | Kakadu ←J2K |")
        print("|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|")
        for r in reports {
            func mark(_ name: String, kind: String) -> String {
                guard let row = r.codecs.first(where: { $0.codec == name }) else { return "—" }
                switch row.availability {
                case .unsupported: return "N/A"
                case .missingTool: return "—"
                case .ok:
                    return kind == "self"
                        ? (row.roundTripBitExact ? "✓" : "✗")
                        : (row.crossDecodeBitExact ? "✓" : "—")
                    // crossDecode "—" means not attempted (formats
                    // misalign in default-mode sweep); fail would
                    // already have XCTFailed above.
                }
            }
            print("| \(r.modality) | \(r.label) | \(mark("openjpeg", kind: "self")) | \(mark("openjph", kind: "self")) | \(mark("grok", kind: "self")) | \(mark("kakadu", kind: "self")) | \(mark("openjpeg", kind: "cross")) | \(mark("openjph", kind: "cross")) | \(mark("grok", kind: "cross")) | \(mark("kakadu", kind: "cross")) |")
        }

        return reports
    }

    // MARK: - Three mode-specific tests

    /// **Default-mode sweep**: each codec runs as it ships out of the
    /// box. **Mixes HT and EBCOT formats in the same row** —
    /// J2KSwift / OpenJPH default to HT; OpenJPEG / Grok / Kakadu
    /// default to EBCOT. Useful for "what does the user get if they
    /// just run the binary as-is", but byte counts in this table
    /// reflect a format trade-off, not codec quality.
    func testLosslessCrossCodecMatrixAcrossMedicalCorpus_DefaultModes() async throws {
        _ = try await runCrossCodecMatrix(
            j2kConfig: losslessConfig(),  // J2KSwift HT default
            externalMode: .defaultLossless,
            formatFairCrossDecode: false,
            sectionLabel: "M2-default — codec-default modes (mixed HT/EBCOT)",
            tempSubdir: "/j2k_lossless_gate_default/")
    }

    /// **HT-fair sweep**: every codec emits HT/Part-15 lossless. Apples-to-
    /// apples format comparison. OpenJPEG is N/A on this build
    /// (CLI lacks HT encoding capability — its `-M 64` does not produce
    /// a Part-15 codestream that OpenJPH will accept).
    func testLosslessCrossCodecMatrixAcrossMedicalCorpus_HTFair() async throws {
        _ = try await runCrossCodecMatrix(
            j2kConfig: losslessConfig(),  // J2KSwift HT
            externalMode: .htLossless,
            formatFairCrossDecode: true,
            sectionLabel: "HT-fair — every codec emitting HT/Part-15",
            tempSubdir: "/j2k_lossless_gate_htfair/")
    }

    /// **EBCOT-fair sweep**: every codec emits EBCOT/Part-1 lossless.
    /// Apples-to-apples for the legacy decoder world. OpenJPH is N/A
    /// (HT-only codec).
    func testLosslessCrossCodecMatrixAcrossMedicalCorpus_EBCOTFair() async throws {
        _ = try await runCrossCodecMatrix(
            j2kConfig: ebcotLosslessConfig(),  // J2KSwift EBCOT
            externalMode: .ebcotLossless,
            formatFairCrossDecode: true,
            sectionLabel: "EBCOT-fair — every codec emitting EBCOT/Part-1",
            tempSubdir: "/j2k_lossless_gate_ebcotfair/")
    }

    // MARK: - M4 HT vs EBCOT comparison

    /// v5.38 M4 — runs the medical corpus through BOTH of J2KSwift's
    /// lossless paths (HT cleanup-only and EBCOT) and tabulates bytes
    /// + encode-time + decode-time + bit-exact roundtrip. This shows
    /// J2KSwift users the HT-vs-EBCOT trade-off transparently:
    ///
    ///   HT lossless (default): faster encode/decode, larger files
    ///                          (~13-15% denser than EBCOT on 16-bit
    ///                          medical content), Part-15 only — can
    ///                          only be decoded by HT-aware decoders.
    ///
    ///   EBCOT lossless:        denser files, slower encode/decode,
    ///                          decodable by every Part-1 decoder
    ///                          (broadest interop). Recommended when
    ///                          archival storage is the priority and
    ///                          the consumer might be a legacy decoder.
    ///
    /// Both paths produce bit-exact roundtrips (no LSB diff vs
    /// original). Pass gate: every fixture roundtrips bit-exact in
    /// both modes. The encode/decode time tables are diagnostic.
    func testJ2KSwiftLosslessHTvsEBCOTOnMedicalCorpus() async throws {
        struct Row {
            let modality: String
            let label: String
            let pixels: Int
            let rawBytes: Int
            let htBytes: Int; let htEncMs: Double; let htDecMs: Double
            let ebcotBytes: Int; let ebcotEncMs: Double; let ebcotDecMs: Double
        }
        var rows: [Row] = []
        var ranAtLeastOne = false

        for fixture in CrossCodecTooling.medicalCorpus {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }
            ranAtLeastOne = true

            // ---- HT lossless ----
            let htEnc = J2KEncoder(encodingConfiguration: losslessConfig())
            let htDec = J2KDecoder()
            _ = try await htEnc.encode(img)  // warm-up
            let htEncStart = CFAbsoluteTimeGetCurrent()
            let htData = try await htEnc.encode(img)
            let htEncMs = (CFAbsoluteTimeGetCurrent() - htEncStart) * 1000.0
            let htDecStart = CFAbsoluteTimeGetCurrent()
            let htDecoded = try await htDec.decode(htData)
            let htDecMs = (CFAbsoluteTimeGetCurrent() - htDecStart) * 1000.0
            XCTAssertTrue(CrossCodecTooling.bitExactPixelMatch(img, htDecoded),
                "\(fixture.modality) \(fixture.labelHint): HT lossless not bit-exact")

            // ---- EBCOT lossless ----
            let ebcotEnc = J2KEncoder(encodingConfiguration: ebcotLosslessConfig())
            let ebcotDec = J2KDecoder()
            _ = try await ebcotEnc.encode(img)  // warm-up
            let ebcotEncStart = CFAbsoluteTimeGetCurrent()
            let ebcotData = try await ebcotEnc.encode(img)
            let ebcotEncMs = (CFAbsoluteTimeGetCurrent() - ebcotEncStart) * 1000.0
            let ebcotDecStart = CFAbsoluteTimeGetCurrent()
            let ebcotDecoded = try await ebcotDec.decode(ebcotData)
            let ebcotDecMs = (CFAbsoluteTimeGetCurrent() - ebcotDecStart) * 1000.0
            XCTAssertTrue(CrossCodecTooling.bitExactPixelMatch(img, ebcotDecoded),
                "\(fixture.modality) \(fixture.labelHint): EBCOT lossless not bit-exact")

            let pixels = img.width * img.height * img.componentCount
            let bytesPerSample = (img.components[0].bitDepth + 7) / 8
            let rawBytes = pixels * bytesPerSample

            rows.append(Row(
                modality: fixture.modality,
                label: fixture.labelHint.isEmpty ? "\(img.width)×\(img.height)" : fixture.labelHint,
                pixels: pixels, rawBytes: rawBytes,
                htBytes: htData.count, htEncMs: htEncMs, htDecMs: htDecMs,
                ebcotBytes: ebcotData.count, ebcotEncMs: ebcotEncMs, ebcotDecMs: ebcotDecMs))
        }

        if !ranAtLeastOne { throw XCTSkip("medical corpus fixtures not present") }

        print("\n=== v5.38 M4 — J2KSwift HT vs EBCOT lossless on medical corpus ===")
        print("| Modality | Shape | Raw KB | HT KB | HT× | EBCOT KB | EBCOT× | EBCOT vs HT | HT enc / dec ms | EBCOT enc / dec ms |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let htRatio = Double(r.rawBytes) / Double(r.htBytes)
            let ebcotRatio = Double(r.rawBytes) / Double(r.ebcotBytes)
            let bytesDelta = Double(r.ebcotBytes - r.htBytes) / Double(r.htBytes) * 100.0
            print(String(format: "| %@ | %@ | %d | %d | %.2f× | %d | %.2f× | %+.1f%% | %.1f / %.1f | %.1f / %.1f |",
                r.modality, r.label,
                r.rawBytes / 1024,
                r.htBytes / 1024, htRatio,
                r.ebcotBytes / 1024, ebcotRatio,
                bytesDelta,
                r.htEncMs, r.htDecMs,
                r.ebcotEncMs, r.ebcotDecMs))
        }
    }
}

#endif // os(macOS)
