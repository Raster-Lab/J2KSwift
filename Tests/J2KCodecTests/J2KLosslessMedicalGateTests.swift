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

    /// Lossless config: HTJ2K conformant + reversible 5/3 + single
    /// quality layer + LRCP. These match the production lossless
    /// recommendation; if defaults shift, this test goes with them.
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
}
