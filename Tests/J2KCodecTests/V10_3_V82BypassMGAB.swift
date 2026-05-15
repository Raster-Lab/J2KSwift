// v10.3-research Phase 1A — A/B for the v8.2 IDWT-routing-fix bypass on
// MG 2x2 lossless HT-J2K.
//
// Hypothesis (from the architect's read of decodeTilePayloadGPU lines
// 1252-1262): the v8.2 fix forces CPU IDWT whenever
// `preBatchedGPUCoefficients != nil`. On MG with E2's 2x2 tile override
// + HT-J2K Lossless, the GPU HT entropy batched path always sets that
// field, so every MG tile's IDWT falls back to CPU. v8.3's defensive
// IDWT fix (PR #400) may now make the GPU IDWT bit-exact, in which case
// bypassing the v8.2 fallback unlocks the GPU IDWT for MG.
//
// This test:
//   1. Loads `Tests/Fixtures/CrossCodec/medical-real/mg_real_mid_3518x4784.pgm`
//   2. Encodes lossless HT-J2K conformant (matches substitute driver shape)
//   3. Decodes 7 times with `_v82_disableIDWTRoutingFix=false` (current default)
//   4. Decodes 7 times with `_v82_disableIDWTRoutingFix=true` (bypass)
//   5. Asserts bit-exact output between the two configurations
//   6. Reports both medians for the wall-time A/B
//
// Bit-exact failure ⇒ v8.2 fix is still needed; close Phase 1A.
// Bit-exact pass + wall reduction ≥3 ms ⇒ Phase 1A is a real win.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class V10_3_V82BypassMGAB: XCTestCase {

    private func loadPGM(_ relativePath: String, file: String = #filePath) throws -> J2KImage? {
        let testFileURL = URL(fileURLWithPath: file)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = packageRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count > 4, data[0] == 0x50, data[1] == 0x35 else {
            throw NSError(domain: "PGM", code: 1)
        }
        var i = 2
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 { while i < data.count, data[i] != 0x0A { i += 1 }; continue }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30)
                i += 1
            }
            fields.append(num)
        }
        if i < data.count {
            let b = data[i]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1 }
        }
        let payload = data.subdata(in: i..<data.count)
        let bitDepth = fields[2] > 255 ? 16 : 8
        let component = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: fields[0], height: fields[1],
            data: payload,
            sampleByteOrder: bitDepth > 8 ? .bigEndian : nil)
        return J2KImage(width: fields[0], height: fields[1], components: [component])
    }

    private func encodeLosslessHTJ2K(_ image: J2KImage) async throws -> Data {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        _ = cfg
        return try await J2KEncoder(encodingConfiguration: cfg).encode(image)
    }

    private func decodeAndMedianMs(_ codestream: Data, warmups: Int, runs: Int) async throws -> (image: J2KImage, medianMs: Double) {
        let decoder = J2KDecoder()
        for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
        var samples: [Double] = []
        var lastImage: J2KImage? = nil
        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            lastImage = try await decoder.decode(codestream)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0)
        }
        samples.sort()
        return (lastImage!, samples[samples.count / 2])
    }

    private func componentBytes(_ image: J2KImage) -> Data {
        guard let first = image.components.first else { return Data() }
        return first.data
    }

    /// Per-fixture A/B harness: in a single process, encode lossless
    /// HT-J2K, decode N times with v8.2 fix ON, decode N times with
    /// v8.2 fix OFF, compare bit-exactness + median wall. In-process
    /// means thermal drift doesn't bias the result.
    private func abFixture(_ relativePath: String, label: String) async throws -> (msOff: Double, msOn: Double, bitExact: Bool)? {
        guard let image = try loadPGM(relativePath) else {
            print("SKIP: \(relativePath) not found"); return nil
        }
        let codestream = try await encodeLosslessHTJ2K(image)

        DecoderTuning._v82_disableIDWTRoutingFix = false
        let (imgOff, msOff) = try await decodeAndMedianMs(codestream, warmups: 2, runs: 7)
        let bytesOff = componentBytes(imgOff)

        DecoderTuning._v82_disableIDWTRoutingFix = true
        let (imgOn, msOn) = try await decodeAndMedianMs(codestream, warmups: 2, runs: 7)
        let bytesOn = componentBytes(imgOn)

        DecoderTuning._v82_disableIDWTRoutingFix = false  // restore

        let bitExact = (bytesOff == bytesOn)
        let delta = msOn - msOff
        print(String(format: "| %@ | %.2f | %.2f | %+.2f | %@ |",
                     label, msOff, msOn, delta, bitExact ? "YES" : "NO"))
        return (msOff, msOn, bitExact)
    }

    /// Cross-fixture A/B: DX, MG, PX, plus CT (single-tile control).
    /// Required to certify the bypass before promoting to default.
    func testV82Bypass_crossFixture() async throws {
        print("")
        print("=== V10_3_PHASE_1A_V82_BYPASS_CROSS_FIXTURE_BEGIN ===")
        print("Configuration: lossless HT-J2K conformant, encoder .auto tile-mode planner")
        print("")
        print("| Fixture | v82 ON (ms) | v82 BYPASS (ms) | Δ ms | bit-exact |")
        print("|---|---:|---:|---:|---|")
        let fixtures: [(String, String)] = [
            ("Tests/Fixtures/CrossCodec/medical-real/ct_real_small_512x512.pgm",       "CT 512² (single-tile)"),
            ("Tests/Fixtures/CrossCodec/medical-real/px_real_mid_2793x1316.pgm",       "PX 2793×1316 (4x4)"),
            ("Tests/Fixtures/CrossCodec/medical-real/dx_real_mid_2800x2288.pgm",       "DX 2800×2288 (4x4)"),
            ("Tests/Fixtures/CrossCodec/medical-real/dx_real_large_2544x3056.pgm",     "DX 2544×3056 (4x4)"),
            ("Tests/Fixtures/CrossCodec/medical-real/mg_real_small_3516x4784.pgm",     "MG 3516×4784 (2x2)"),
            ("Tests/Fixtures/CrossCodec/medical-real/mg_real_mid_3518x4784.pgm",       "MG 3518×4784 (2x2)"),
            ("Tests/Fixtures/CrossCodec/medical-real/mg_real_large_3521x4784.pgm",     "MG 3521×4784 (2x2)"),
        ]
        var allBitExact = true
        for (path, label) in fixtures {
            if let r = try await abFixture(path, label: label) {
                allBitExact = allBitExact && r.bitExact
            }
        }
        print("")
        print("All bit-exact: \(allBitExact ? "YES" : "NO")")
        print("=== V10_3_PHASE_1A_V82_BYPASS_CROSS_FIXTURE_END ===")
        print("")
        XCTAssertTrue(allBitExact, "v8.2 bypass produced non-bit-exact output on at least one fixture")
    }

    func testV82BypassMG_lossless_HTJ2K() async throws {
        guard let image = try loadPGM("Tests/Fixtures/CrossCodec/medical-real/mg_real_mid_3518x4784.pgm") else {
            print("SKIP: mg_real_mid_3518x4784.pgm not found")
            return
        }
        let codestream = try await encodeLosslessHTJ2K(image)
        print("v10.3-1A: codestream \(codestream.count) bytes for MG 3518x4784")

        // OFF baseline (v8.2 fix ON, default)
        DecoderTuning._v82_disableIDWTRoutingFix = false
        let (imgOff, msOff) = try await decodeAndMedianMs(codestream, warmups: 2, runs: 7)
        let bytesOff = componentBytes(imgOff)

        // ON bypass (v8.2 fix OFF — GPU IDWT for all tiles)
        DecoderTuning._v82_disableIDWTRoutingFix = true
        let (imgOn, msOn) = try await decodeAndMedianMs(codestream, warmups: 2, runs: 7)
        let bytesOn = componentBytes(imgOn)

        // Restore production default
        DecoderTuning._v82_disableIDWTRoutingFix = false

        print("")
        print("=== V10_3_PHASE_1A_V82_BYPASS_MG_BEGIN ===")
        print("Fixture: MG 3518x4784 16-bit lossless HT-J2K conformant (E2 2x2 tile override)")
        print("")
        print("| Configuration                         | median ms | bytes match? |")
        print("|---|---:|---|")
        print("| v82 fix ON (production default)       | \(String(format: "%.2f", msOff)) | (baseline) |")
        let bytesMatch = (bytesOff == bytesOn)
        print("| v82 fix BYPASSED (GPU IDWT active)    | \(String(format: "%.2f", msOn)) | \(bytesMatch ? "YES" : "NO — corruption detected!") |")
        print("")
        print(String(format: "Δ vs baseline: %.2f ms (%+.1f%%)", msOn - msOff, (msOn - msOff) / msOff * 100))
        print("Bytes off-vs-on match: \(bytesMatch ? "BIT-EXACT" : "DIFFER")")
        if !bytesMatch {
            // First mismatch offset for triage
            let n = min(bytesOff.count, bytesOn.count)
            var firstMismatch = -1
            for i in 0..<n where bytesOff[bytesOff.startIndex + i] != bytesOn[bytesOn.startIndex + i] {
                firstMismatch = i; break
            }
            print("First mismatch at byte offset: \(firstMismatch) of \(n)")
        }
        let phase1AGate = bytesMatch && (msOff - msOn) >= 3.0
        if phase1AGate {
            print("Status: PASS — bypass is bit-exact AND saves ≥3 ms. Promote to production?")
        } else if bytesMatch {
            print("Status: BYPASS BIT-EXACT but wall delta < 3 ms — close per stop trigger.")
        } else {
            print("Status: CORRUPTION — v8.2 fix is still required; close Phase 1A.")
        }
        print("=== V10_3_PHASE_1A_V82_BYPASS_MG_END ===")
        print("")

        XCTAssertGreaterThan(msOff, 0)
        XCTAssertGreaterThan(msOn, 0)
        // Don't fail the test on the bytesMatch check — record the finding either way.
    }
}

/// Internal tuning surface for the v8.2 routing fix. The static
/// `_v82_disableIDWTRoutingFix` lives on `DecoderPipeline`.
internal enum DecoderTuning {
    static var _v82_disableIDWTRoutingFix: Bool {
        get { DecoderPipeline._v82_disableIDWTRoutingFix }
        set { DecoderPipeline._v82_disableIDWTRoutingFix = newValue }
    }
}

#endif
