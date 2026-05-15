// v10.3-research Phase 1A — cross-codec parity check with v8.2 bypass ON.
//
// Phase 1A's MG A/B showed bit-exact between v8.2-fix-ON and -OFF on MG
// lossless HT-J2K. This test extends the bit-exact check to the FULL
// medical-real corpus (CT/MR/XA/PX/DX/MG, all sizes), validating that
// the v8.3 GPU IDWT fix covers every fixture class — not just MG —
// before any default-flip decision.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class V10_3_V82BypassCrossCodecCheck: XCTestCase {

    private struct Fixture {
        let label: String
        let pgmPath: String
    }

    private let fixtures: [Fixture] = [
        Fixture(label: "MR 174x192",  pgmPath: "Tests/Fixtures/CrossCodec/medical-real/mr_real_small_174x192.pgm"),
        Fixture(label: "CT 512x512",  pgmPath: "Tests/Fixtures/CrossCodec/medical-real/ct_real_mid_512x512.pgm"),
        Fixture(label: "MR 512x512",  pgmPath: "Tests/Fixtures/CrossCodec/medical-real/mr_real_mid_512x512.pgm"),
        Fixture(label: "XA 1024x1024", pgmPath: "Tests/Fixtures/CrossCodec/medical-real/xa_real_mid_1024x1024.pgm"),
        Fixture(label: "PX 2793x1316", pgmPath: "Tests/Fixtures/CrossCodec/medical-real/px_real_mid_2793x1316.pgm"),
        Fixture(label: "DX 2800x2288", pgmPath: "Tests/Fixtures/CrossCodec/medical-real/dx_real_mid_2800x2288.pgm"),
        Fixture(label: "DX 2544x3056", pgmPath: "Tests/Fixtures/CrossCodec/medical-real/dx_real_large_2544x3056.pgm"),
        Fixture(label: "MG 3518x4784", pgmPath: "Tests/Fixtures/CrossCodec/medical-real/mg_real_mid_3518x4784.pgm"),
        Fixture(label: "MG 3521x4784", pgmPath: "Tests/Fixtures/CrossCodec/medical-real/mg_real_large_3521x4784.pgm")
    ]

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

    private func encodeLossless(_ image: J2KImage) async throws -> Data {
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        return try await J2KEncoder(encodingConfiguration: cfg).encode(image)
    }

    func testV82BypassBitExactAcrossCorpus() async throws {
        var allMatch = true
        var rows: [(label: String, dim: String, bytes: Int, match: Bool, mismatchOffset: Int)] = []

        for f in fixtures {
            guard let image = try loadPGM(f.pgmPath) else {
                print("SKIP: \(f.pgmPath)")
                continue
            }
            let codestream = try await encodeLossless(image)

            DecoderPipeline._v82_disableIDWTRoutingFix = false
            let decoder1 = J2KDecoder()
            _ = try await decoder1.decode(codestream)  // warm
            let imgOff = try await decoder1.decode(codestream)

            DecoderPipeline._v82_disableIDWTRoutingFix = true
            let decoder2 = J2KDecoder()
            _ = try await decoder2.decode(codestream)  // warm
            let imgOn = try await decoder2.decode(codestream)

            // Restore v10.3 default (true = bypass active).
            DecoderPipeline._v82_disableIDWTRoutingFix = true

            let bytesOff = imgOff.components.first?.data ?? Data()
            let bytesOn = imgOn.components.first?.data ?? Data()
            let match = bytesOff == bytesOn
            var firstMismatch = -1
            if !match {
                let n = min(bytesOff.count, bytesOn.count)
                for i in 0..<n where bytesOff[bytesOff.startIndex + i] != bytesOn[bytesOn.startIndex + i] {
                    firstMismatch = i; break
                }
            }
            rows.append((label: f.label, dim: "\(image.width)x\(image.height)",
                         bytes: bytesOff.count, match: match, mismatchOffset: firstMismatch))
            if !match { allMatch = false }
        }

        print("")
        print("=== V10_3_V82_BYPASS_CROSS_CORPUS_BEGIN ===")
        print("v8.2 fix ON vs OFF — bit-exact check across medical-real corpus")
        print("")
        print("| Fixture | Dim | Decoded bytes | Bit-exact? | First mismatch |")
        print("|---|---|---:|---|---:|")
        for r in rows {
            print("| \(r.label) | \(r.dim) | \(r.bytes) | \(r.match ? "YES" : "NO") | \(r.match ? "—" : String(r.mismatchOffset)) |")
        }
        print("")
        if allMatch {
            print("Status: ALL FIXTURES BIT-EXACT — v8.2 fix is no longer required for correctness")
            print("        on HT-J2K Lossless. Eligible for production default-flip.")
        } else {
            print("Status: ONE OR MORE FIXTURES DIFFER — v8.2 fix is still required for these")
            print("        codestream classes. Keep default-on.")
        }
        print("=== V10_3_V82_BYPASS_CROSS_CORPUS_END ===")
        print("")

        XCTAssertTrue(allMatch, "v8.2 bypass must be bit-exact across all medical-real fixtures before default-flip.")
    }
}
#endif
