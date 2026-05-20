// V10_15_MultiLayerDecodeTests.swift
//
// v10.15-research — validation for multi-layer packet decode and
// `decodeQuality` (v10.9.0).
//
// Phase 0 found J2KSwift silently mis-decoded any multi-layer JPEG 2000
// codestream (the packet loop was hardcoded single-layer). Phase 1 adds
// `extractTileDataMultiLayer` — the layer-aware packet decode. Phase 2
// adds `decodeQuality(layer:)` on top.
//
// Fixtures (Tests/Fixtures/MultiLayer/) are genuine multi-layer
// codestreams produced by Kakadu 8.4.1 (`kdu_compress Clayers=N
// Creversible=yes`), plus `kdu_expand -layers N` layer-truncated
// references.
//
// Tests:
//   1. decode() of a 2/3/4-layer lossless codestream is bit-identical
//      to the original image (the conformance fix)
//   2. decodeQuality(layer: last) == decode()
//   3. decodeQuality(layer: L) — valid dims, quality monotonically
//      improves with L, full layer is lossless, and each truncated
//      layer is close to the Kakadu -layers reference

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_15_MultiLayerDecodeTests: XCTestCase {

    private func fixtureURL(_ rel: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(rel)")
    }

    private func loadPGM16(_ url: URL) throws -> J2KImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let raw = try Data(contentsOf: url)
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

    /// PSNR between two 16-bit big-endian sample buffers. Returns
    /// `.infinity` when identical.
    private func psnr16(_ a: Data, _ b: Data) -> Double {
        let n = min(a.count, b.count) / 2
        guard n > 0 else { return 0 }
        var sumSq = 0.0
        a.withUnsafeBytes { ap in
            b.withUnsafeBytes { bp in
                let a8 = ap.bindMemory(to: UInt8.self)
                let b8 = bp.bindMemory(to: UInt8.self)
                for k in 0..<n {
                    let av = Int(a8[2*k]) << 8 | Int(a8[2*k+1])
                    let bv = Int(b8[2*k]) << 8 | Int(b8[2*k+1])
                    let d = Double(av - bv)
                    sumSq += d * d
                }
            }
        }
        let mse = sumSq / Double(n)
        if mse == 0 { return .infinity }
        return 10.0 * log10(65535.0 * 65535.0 / mse)
    }

    func testMultiLayerDecode_bitExact() async throws {
        guard let original = try loadPGM16(
            fixtureURL("CrossCodec/medical-real/ct_real_mid_512x512.pgm")) else {
            throw XCTSkip("CT fixture missing")
        }
        let decoder = J2KDecoder()
        for layers in [2, 3, 4] {
            let url = fixtureURL("MultiLayer/ct512_L\(layers).j2k")
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("multi-layer fixture ct512_L\(layers).j2k missing")
            }
            let codestream = try Data(contentsOf: url)
            let decoded = try await decoder.decode(codestream)
            XCTAssertEqual(decoded.width, original.width, "[L\(layers)] width")
            XCTAssertEqual(decoded.height, original.height, "[L\(layers)] height")
            XCTAssertEqual(decoded.components[0].data, original.components[0].data,
                "[L\(layers)] multi-layer decode must be bit-identical to the original (lossless)")
        }
        print("V10_15 multi-layer decode bit-exact: ct512 L2/L3/L4 ✓ (conformance fix)")
    }

    func testDecodeQuality_fullLayerEqualsDecode() async throws {
        let url = fixtureURL("MultiLayer/ct512_L4.j2k")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("ct512_L4.j2k missing")
        }
        let codestream = try Data(contentsOf: url)
        let decoder = J2KDecoder()
        let full = try await decoder.decode(codestream)
        // Layer index 3 = the last of 4 layers = full quality.
        let viaQuality = try await decoder.decodeQuality(
            codestream, options: J2KQualityDecodingOptions(layer: 3))
        XCTAssertEqual(viaQuality.components[0].data, full.components[0].data,
            "decodeQuality(layer: last) must equal decode()")
        print("V10_15 decodeQuality(layer: last) ≡ decode() ✓")
    }

    func testDecodeQuality_truncatedLayers() async throws {
        guard let original = try loadPGM16(
            fixtureURL("CrossCodec/medical-real/ct_real_mid_512x512.pgm")) else {
            throw XCTSkip("CT fixture missing")
        }
        let url = fixtureURL("MultiLayer/ct512_L4.j2k")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("ct512_L4.j2k missing")
        }
        let codestream = try Data(contentsOf: url)
        let decoder = J2KDecoder()
        let origData = original.components[0].data

        var prevPSNR = -1.0
        for layer in 0...3 {
            let img = try await decoder.decodeQuality(
                codestream, options: J2KQualityDecodingOptions(layer: layer))
            XCTAssertEqual(img.width, 512, "[layer \(layer)] width")
            XCTAssertEqual(img.height, 512, "[layer \(layer)] height")

            let p = psnr16(img.components[0].data, origData)
            // Quality must improve (or hold) as more layers are decoded.
            XCTAssertGreaterThanOrEqual(p, prevPSNR - 0.01,
                "[layer \(layer)] PSNR \(p) regressed vs previous layer \(prevPSNR)")
            prevPSNR = p

            // Cross-check against Kakadu's own layer-truncated decode.
            if layer < 3,
               let kdu = try loadPGM16(
                fixtureURL("MultiLayer/ct512_L4_kdu_layers\(layer + 1).pgm")) {
                let pk = psnr16(img.components[0].data, kdu.components[0].data)
                print(String(format: "  layer %d: PSNR vs original %.2f dB, vs kdu -layers%d %.2f dB",
                             layer, p, layer + 1, pk))
                XCTAssertGreaterThan(pk, 30.0,
                    "[layer \(layer)] decodeQuality should be close to kdu_expand -layers \(layer+1)")
            } else {
                print(String(format: "  layer %d: PSNR vs original %.2f dB", layer, p))
            }
        }
        // The last layer is lossless — PSNR is infinite (bit-exact).
        XCTAssertEqual(prevPSNR, .infinity,
            "decodeQuality(layer: 3) of a 4-layer lossless codestream must be bit-exact")
        print("V10_15 decodeQuality truncated layers: monotonic quality 0→3, full layer lossless ✓")
    }
}
#endif
