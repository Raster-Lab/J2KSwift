// HTApproachECPUSIMDTests.swift
//
// v6-alpha6 phase 1.4 — approach E (CPU-SIMD only) validation.
//
// Phase 1.3 (#305) measured GPU approach B regressing at every
// medical-corpus scale on Apple M2 (-141% to -249%). The plan doc's
// §4 candidate-approach table flagged approach E as the fall-back
// for exactly this case: skip GPU entirely, promote v5.39 M1's SIMD
// per-quad classifier to production-default, measure the win.
//
// What this suite gates:
//
//   1. **Bit-exact byte equality**: SIMD-on (production-default
//      since this PR) vs SIMD-off (legacy `J2K_HT_SIMD=0` opt-out)
//      across every medical-corpus fixture. The `useSIMDClassification`
//      toggle has been bytes-identical at the per-block level since
//      v5.39 M1 (HTSIMDIntegrationTests proved it over 25K random
//      blocks); this test extends the proof to full-pipeline encode
//      bytes across the corpus.
//
//   2. **Wall-time A/B**: SIMD-on vs SIMD-off across the corpus.
//      The diagnostic that decides whether the new default is a real
//      win, a wash, or a regression. Phase 0 plan §4 estimated
//      "+10-20% DX wall reduction"; this test prints the actual
//      delta so the PR description can record the empirical number.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTApproachECPUSIMDTests: XCTestCase {

    // MARK: - Fixtures

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

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "MR-small 180²",   filename: "mr_study_002_instance_000100.pgm"),
        CorpusFixture(label: "CT 512²",         filename: "ct_study_001_instance_000001.pgm"),
        CorpusFixture(label: "MR 886²",         filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",        filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316",    filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288",    filename: "dx_study_002_instance_000001.pgm"),
    ]

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func encode(image: J2KImage, simdOn: Bool) async throws -> Data {
        let prev = EncoderPipeline._htSIMDClassificationEnabled
        defer { EncoderPipeline._htSIMDClassificationEnabled = prev }
        EncoderPipeline._htSIMDClassificationEnabled = simdOn
        return try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)
    }

    // MARK: - Bit-exact byte equality

    /// Production default (SIMD on) must produce byte-identical
    /// codestreams to the legacy scalar path (SIMD off) across every
    /// medical-corpus fixture. This is the lossless contract — any
    /// drift here breaks cross-codec validation, byte-archive
    /// comparison, and downstream decode equality.
    func testApproachE_BytesIdentical_AllCorpus() async throws {
        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else {
                print("[skip] fixture not present: \(fix.filename)")
                continue
            }
            let scalar = try await encode(image: image, simdOn: false)
            let simd = try await encode(image: image, simdOn: true)
            XCTAssertEqual(scalar.count, simd.count,
                "[\(fix.label)] codestream byte counts diverged: " +
                "scalar=\(scalar.count) simd=\(simd.count)")
            XCTAssertEqual(scalar, simd,
                "[\(fix.label)] codestream bytes diverged " +
                "(\(scalar.count) bytes total)")
        }
    }

    // MARK: - Wall-time A/B (diagnostic)

    /// Median-of-3 wall-time A/B across the corpus. Prints a markdown
    /// table for paste into the Phase 1.4 PR description.
    /// Diagnostic — does not assert any threshold; the print is the
    /// data the team makes the production-default decision on.
    func testApproachE_WallTimeAB_AcrossCorpus() async throws {
        #if DEBUG
        print("⚠️  Wall-time A/B in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter HTApproachECPUSIMDTests/testApproachE_WallTimeAB_AcrossCorpus")
        #endif

        print("=== v6-alpha6 Phase 1.4 — approach E (CPU-SIMD) wall-time A/B ===")
        print("(SIMD-on is the new production default since this PR; SIMD-off")
        print(" is the legacy scalar path opt-in via J2K_HT_SIMD=0.)")
        print()
        print("| fixture | bytes | scalar ms | SIMD ms | Δ % |")
        print("|---|---:|---:|---:|---:|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warm-up.
            _ = try await encode(image: image, simdOn: false)
            _ = try await encode(image: image, simdOn: true)

            // Scalar.
            var scalarMs: [Double] = []
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encode(image: image, simdOn: false)
                scalarMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }

            // SIMD.
            var simdMs: [Double] = []
            var bytes = 0
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                let data = try await encode(image: image, simdOn: true)
                simdMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                bytes = data.count
            }

            scalarMs.sort(); simdMs.sort()
            let scalarMed = scalarMs[1]
            let simdMed = simdMs[1]
            let delta = ((scalarMed - simdMed) / scalarMed) * 100.0
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.1f |",
                fix.label, bytes, scalarMed, simdMed, delta))
        }

        print()
        print("Reading the table:")
        print("  - Δ% > 0  → SIMD path faster than scalar (the win we're shipping)")
        print("  - Δ% ≈ 0  → wash (then v5.39 M1 was correct to leave it opt-in,")
        print("    and v6-alpha6 phase 1.4 should also revert the default)")
        print("  - Δ% < 0  → SIMD slower (regression — REVERT this PR)")
    }
}
