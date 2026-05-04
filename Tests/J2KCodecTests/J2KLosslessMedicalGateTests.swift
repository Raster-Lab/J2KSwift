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

    // MARK: - M2 cross-codec gate

    /// v5.38 M2 — same medical corpus, but each fixture is run through
    /// J2KSwift + OpenJPEG + OpenJPH + Grok + Kakadu with bit-exact
    /// roundtrip + cross-decode assertions and per-codec timing.
    ///
    /// What the test verifies, per (codec, fixture):
    ///   - codec roundtrip is bit-exact (codec encode → codec decode → original)
    ///   - cross-decode: J2KSwift's lossless codestream decodes bit-exact
    ///     in the external decoder
    ///
    /// What it reports (markdown table):
    ///   - encode-ms, decode-ms, output-bytes, ratio-vs-raw per codec
    ///   - cross-decode pass/fail for each (J2KSwift→external) pair
    ///
    /// Tools missing on disk are skipped (XCTSkip per codec); the test
    /// only fails on a positive bit-exact violation. This means the
    /// gate is informative on partial environments but only enforces
    /// what's actually installed.
    func testLosslessCrossCodecMatrixAcrossMedicalCorpus() async throws {
        struct CodecRow {
            let codec: String
            var encMs: Double = 0
            var decMs: Double = 0
            var outBytes: Int = 0
            var roundTripBitExact: Bool = false
            var crossDecodeBitExact: Bool = false
            var available: Bool = false
        }
        struct FixtureReport {
            let modality: String
            let label: String
            let pixels: Int
            let rawBytes: Int
            var j2kSwiftBytes: Int
            var j2kSwiftEncMs: Double
            var j2kSwiftDecMs: Double
            var codecs: [CodecRow]
        }

        var reports: [FixtureReport] = []
        var ranAtLeastOne = false
        let tempDir = NSTemporaryDirectory().appending("/j2k_lossless_gate_m2/")
        try? FileManager.default.removeItem(atPath: tempDir)
        try FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true)

        for fixture in CrossCodecTooling.medicalCorpus {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }
            ranAtLeastOne = true

            let pixels = img.width * img.height * img.componentCount
            let bytesPerSample = (img.components[0].bitDepth + 7) / 8
            let rawBytes = pixels * bytesPerSample

            // J2KSwift baseline.
            let cfg = losslessConfig()
            let encoder = J2KEncoder(encodingConfiguration: cfg)
            let decoder = J2KDecoder()
            // Warm up BOTH encode and decode. The Metal-backed decode
            // pays a one-time lazy-init cost on its first non-trivial
            // call (~40-50 ms on M1 for a 512² CT image); without a
            // decoder warm-up that latency lands in the first measured
            // pass and pollutes the table. Encoder also benefits.
            let warmData = try await encoder.encode(img)
            _ = try await decoder.decode(warmData)
            let encStart = CFAbsoluteTimeGetCurrent()
            let j2kData = try await encoder.encode(img)
            let j2kEncMs = (CFAbsoluteTimeGetCurrent() - encStart) * 1000.0
            let decStart = CFAbsoluteTimeGetCurrent()
            let j2kDecoded = try await decoder.decode(j2kData)
            let j2kDecMs = (CFAbsoluteTimeGetCurrent() - decStart) * 1000.0
            XCTAssertTrue(CrossCodecTooling.bitExactPixelMatch(img, j2kDecoded),
                "J2KSwift lossless self-roundtrip not bit-exact: \(fixture.modality) \(fixture.labelHint)")

            // J2KSwift codestream written to disk for cross-decode.
            let j2kSwiftPath = tempDir + "j2kswift_\(fixture.modality)_\(fixture.labelHint).j2k"
            try j2kData.write(to: URL(fileURLWithPath: j2kSwiftPath))

            // Per-codec roundtrip + cross-decode.
            var codecRows: [CodecRow] = []
            for codec in CrossCodecTooling.Codec.allCases {
                var row = CodecRow(codec: codec.rawValue)
                let inPath = url.path  // original PGM
                let outJ2K = tempDir + "\(codec.rawValue)_\(fixture.modality)_\(fixture.labelHint).j2k"
                let outPGM = tempDir + "\(codec.rawValue)_\(fixture.modality)_\(fixture.labelHint)_dec.pgm"
                let crossPGM = tempDir + "\(codec.rawValue)_\(fixture.modality)_\(fixture.labelHint)_crossdec.pgm"

                // Compressor.
                let comp = try CrossCodecTooling.compressLossless(codec, input: inPath, output: outJ2K)
                if comp.status == -1 {
                    // Tool missing — leave row.available = false and continue.
                    codecRows.append(row); continue
                }
                row.available = true
                XCTAssertEqual(comp.status, 0,
                    "\(codec) compress failed on \(fixture.modality) \(fixture.labelHint)")
                row.encMs = comp.ms
                row.outBytes = CrossCodecTooling.fileSize(outJ2K)

                // Decompressor (codec roundtrip).
                let dec = try CrossCodecTooling.decompressLossless(codec, input: outJ2K, output: outPGM)
                XCTAssertEqual(dec.status, 0,
                    "\(codec) decompress failed on \(fixture.modality) \(fixture.labelHint)")
                row.decMs = dec.ms

                if let decImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: outPGM)) {
                    row.roundTripBitExact = CrossCodecTooling.bitExactPixelMatch(img, decImg)
                    if !row.roundTripBitExact {
                        let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, decImg)
                        XCTFail("\(codec) self-roundtrip not bit-exact on \(fixture.modality) \(fixture.labelHint): max abs diff = \(maxDiff)")
                    }
                }

                // Cross-decode: J2KSwift codestream → external decoder.
                let cross = try CrossCodecTooling.decompressLossless(codec, input: j2kSwiftPath, output: crossPGM)
                if cross.status == 0,
                   let crossImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: crossPGM)) {
                    row.crossDecodeBitExact = CrossCodecTooling.bitExactPixelMatch(img, crossImg)
                    if !row.crossDecodeBitExact {
                        let maxDiff = CrossCodecTooling.maxAbsPixelDiff(img, crossImg)
                        XCTFail("J2KSwift→\(codec) cross-decode not bit-exact on \(fixture.modality) \(fixture.labelHint): max abs diff = \(maxDiff)")
                    }
                } else {
                    XCTFail("J2KSwift→\(codec) cross-decode failed (status \(cross.status)) on \(fixture.modality) \(fixture.labelHint)")
                }

                codecRows.append(row)
            }

            reports.append(FixtureReport(
                modality: fixture.modality,
                label: fixture.labelHint.isEmpty ? "\(img.width)×\(img.height)" : fixture.labelHint,
                pixels: pixels, rawBytes: rawBytes,
                j2kSwiftBytes: j2kData.count,
                j2kSwiftEncMs: j2kEncMs,
                j2kSwiftDecMs: j2kDecMs,
                codecs: codecRows))
        }

        if !ranAtLeastOne { throw XCTSkip("medical corpus fixtures not present") }

        // ---- Print Bytes / Ratio table ----
        print("\n=== v5.38 M2 — Lossless cross-codec BYTES + RATIO across medical corpus ===")
        print("| Modality | Shape | Raw KB | J2KSwift KB | OpenJPEG KB | OpenJPH KB | Grok KB | Kakadu KB | J2KSwift× | OpenJPEG× | OpenJPH× | Grok× | Kakadu× |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in reports {
            func cell(_ codec: String) -> CodecRow? {
                r.codecs.first(where: { $0.codec == codec })
            }
            let opj = cell("openjpeg"); let oph = cell("openjph"); let grk = cell("grok"); let kdu = cell("kakadu")
            func kb(_ b: Int) -> String { b > 0 ? "\(b / 1024)" : "—" }
            func ratio(_ b: Int) -> String { b > 0 ? String(format: "%.2f", Double(r.rawBytes) / Double(b)) : "—" }
            let j2kKB = r.j2kSwiftBytes / 1024
            let j2kRatio = String(format: "%.2f", Double(r.rawBytes) / Double(r.j2kSwiftBytes))
            print("| \(r.modality) | \(r.label) | \(r.rawBytes / 1024) | \(j2kKB) | \(kb(opj?.outBytes ?? 0)) | \(kb(oph?.outBytes ?? 0)) | \(kb(grk?.outBytes ?? 0)) | \(kb(kdu?.outBytes ?? 0)) | \(j2kRatio)× | \(ratio(opj?.outBytes ?? 0))× | \(ratio(oph?.outBytes ?? 0))× | \(ratio(grk?.outBytes ?? 0))× | \(ratio(kdu?.outBytes ?? 0))× |")
        }

        // ---- Print Encode timing table ----
        print("\n=== v5.38 M2 — Lossless ENCODE TIME (ms) across medical corpus ===")
        print("| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |")
        print("|---|---|---:|---:|---:|---:|---:|")
        for r in reports {
            func t(_ codec: String) -> String {
                guard let row = r.codecs.first(where: { $0.codec == codec }), row.available else { return "—" }
                return String(format: "%.1f", row.encMs)
            }
            print(String(format: "| %@ | %@ | %.1f | %@ | %@ | %@ | %@ |",
                         r.modality, r.label, r.j2kSwiftEncMs,
                         t("openjpeg"), t("openjph"), t("grok"), t("kakadu")))
        }

        // ---- Print Decode timing table ----
        print("\n=== v5.38 M2 — Lossless DECODE TIME (ms) across medical corpus ===")
        print("| Modality | Shape | J2KSwift | OpenJPEG | OpenJPH | Grok | Kakadu |")
        print("|---|---|---:|---:|---:|---:|---:|")
        for r in reports {
            func t(_ codec: String) -> String {
                guard let row = r.codecs.first(where: { $0.codec == codec }), row.available else { return "—" }
                return String(format: "%.1f", row.decMs)
            }
            print(String(format: "| %@ | %@ | %.1f | %@ | %@ | %@ | %@ |",
                         r.modality, r.label, r.j2kSwiftDecMs,
                         t("openjpeg"), t("openjph"), t("grok"), t("kakadu")))
        }

        // ---- Print Cross-decode pass/fail matrix ----
        print("\n=== v5.38 M2 — Lossless CROSS-DECODE matrix (J2KSwift → external) ===")
        print("| Modality | Shape | OpenJPEG | OpenJPH | Grok | Kakadu |")
        print("|---|---|:---:|:---:|:---:|:---:|")
        for r in reports {
            func m(_ codec: String) -> String {
                guard let row = r.codecs.first(where: { $0.codec == codec }), row.available else { return "n/a" }
                return row.crossDecodeBitExact ? "✓" : "✗"
            }
            print("| \(r.modality) | \(r.label) | \(m("openjpeg")) | \(m("openjph")) | \(m("grok")) | \(m("kakadu")) |")
        }
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
