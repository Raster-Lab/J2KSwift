// V10_11_DecodeRegionDirectTests.swift
//
// v10.11-research — validation for true ROI decode (`decodeRegion`
// with the `.direct` strategy), replacing the v10.5.0-era
// `notImplemented` stub.
//
// `.direct` ROI decode keeps only the code-blocks whose inverse-DWT
// spatial footprint overlaps the requested region and skips the
// dominant entropy decode stage for the rest. The inverse DWT still
// runs full-tile (off-region code-blocks reconstruct as zeros), then
// the result is cropped to the region.
//
// Correctness contract: because every code-block influencing an
// in-region pixel is retained, the cropped `.direct` output must be
// BIT-IDENTICAL to a full `decode()` followed by the same crop. These
// tests assert exactly that against a test-side reference crop, across
// the medical corpus and a spread of region positions (corners,
// centre, strips, tile-boundary-crossing, full).
//
// Tests:
//   1. .direct ROI bit-exact vs full-decode crop — CT (single-tile)
//   2. .direct ROI bit-exact vs full-decode crop — DX (large single-tile)
//   3. .direct ROI bit-exact vs full-decode crop — MG (large, 2x2 tiles)
//   4. .direct and .fullImageExtraction agree
//   5. entropy-skip A/B — .direct faster than .fullImageExtraction

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_11_DecodeRegionDirectTests: XCTestCase {

    private func loadPGM16(_ filename: String) throws -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path) else { return nil }
        let raw = try Data(contentsOf: here)
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

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Independent test-side crop reference: extracts `region` from a
    /// fully-decoded image, copying `bytesPerSample` bytes per pixel.
    private func cropReference(_ image: J2KImage, _ region: J2KRegion) -> Data {
        let comp = image.components[0]
        let bps = (comp.bitDepth + 7) / 8
        var out = Data(count: region.width * region.height * bps)
        comp.data.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.baseAddress, let dst = dstRaw.baseAddress else { return }
                for y in 0..<region.height {
                    let srcOff = ((region.y + y) * comp.width + region.x) * bps
                    let dstOff = y * region.width * bps
                    memcpy(dst + dstOff, src + srcOff, region.width * bps)
                }
            }
        }
        return out
    }

    /// A spread of region positions exercising corners, centre, thin
    /// strips, a tiny region, and the full image. For multi-tile
    /// fixtures the centre / strip regions cross tile boundaries.
    private func regions(width W: Int, height H: Int) -> [(String, J2KRegion)] {
        [
            ("full",         J2KRegion(x: 0, y: 0, width: W, height: H)),
            ("top-left",     J2KRegion(x: 0, y: 0, width: W / 4, height: H / 4)),
            ("centre",       J2KRegion(x: W / 2 - W / 8, y: H / 2 - H / 8,
                                       width: W / 4, height: H / 4)),
            ("bottom-right", J2KRegion(x: W - W / 4, y: H - H / 4,
                                       width: W / 4, height: H / 4)),
            ("h-strip",      J2KRegion(x: 0, y: H / 2, width: W,
                                       height: max(8, H / 64))),
            ("v-strip",      J2KRegion(x: W / 2, y: 0, width: max(8, W / 64),
                                       height: H)),
            ("tiny",         J2KRegion(x: W / 3, y: H / 3, width: 32, height: 32)),
        ]
    }

    private func runBitExact(_ name: String, _ filename: String) async throws {
        guard let image = try loadPGM16(filename) else {
            throw XCTSkip("\(name) fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()
        let full = try await decoder.decode(codestream)

        for (label, region) in regions(width: image.width, height: image.height) {
            let expected = cropReference(full, region)

            let direct = try await decoder.decodeRegion(
                codestream,
                options: J2KROIDecodingOptions(region: region, strategy: .direct))
            XCTAssertEqual(direct.width, region.width,
                           "[\(name)/\(label)] width mismatch")
            XCTAssertEqual(direct.height, region.height,
                           "[\(name)/\(label)] height mismatch")
            XCTAssertEqual(direct.components[0].data, expected,
                "[\(name)/\(label)] .direct ROI not bit-identical to full-decode crop")

            let viaFull = try await decoder.decodeRegion(
                codestream,
                options: J2KROIDecodingOptions(region: region,
                                               strategy: .fullImageExtraction))
            XCTAssertEqual(viaFull.components[0].data, expected,
                "[\(name)/\(label)] .fullImageExtraction crop not bit-identical to reference")
        }
        print("V10_11 ROI .direct bit-exact: \(name) ✓ (7 regions, .direct ≡ .fullImageExtraction ≡ crop)")
    }

    func testROIDirect_bitExact_CT_512() async throws {
        try await runBitExact("CT 512²", "medical-real/ct_real_mid_512x512.pgm")
    }

    func testROIDirect_bitExact_DX_2800() async throws {
        try await runBitExact("DX 2800×2288", "medical-real/dx_real_mid_2800x2288.pgm")
    }

    func testROIDirect_bitExact_MG_3518() async throws {
        try await runBitExact("MG 3518×4784", "medical-real/mg_real_mid_3518x4784.pgm")
    }

    /// A/B wall: `.direct` (entropy-skip) vs `.fullImageExtraction`
    /// (full entropy decode) for a small region of a large fixture.
    func testROIDirect_entropySkip_AB() async throws {
        guard let image = try loadPGM16("medical-real/dx_real_mid_2800x2288.pgm") else {
            throw XCTSkip("DX fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()

        // A small 256×256 region near the centre — most code-blocks are
        // off-region, so the entropy-skip should be substantial.
        let region = J2KRegion(x: image.width / 2 - 128,
                               y: image.height / 2 - 128,
                               width: 256, height: 256)

        let trials = 7
        var directWall = 0.0
        var fullWall = 0.0
        // Warmup.
        _ = try await decoder.decodeRegion(
            codestream, options: J2KROIDecodingOptions(region: region, strategy: .direct))
        _ = try await decoder.decodeRegion(
            codestream, options: J2KROIDecodingOptions(region: region, strategy: .fullImageExtraction))

        for _ in 0..<trials {
            var t0 = DispatchTime.now()
            _ = try await decoder.decodeRegion(
                codestream, options: J2KROIDecodingOptions(region: region, strategy: .direct))
            directWall += Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000

            t0 = DispatchTime.now()
            _ = try await decoder.decodeRegion(
                codestream, options: J2KROIDecodingOptions(region: region, strategy: .fullImageExtraction))
            fullWall += Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        }
        let directAvg = directWall / Double(trials)
        let fullAvg = fullWall / Double(trials)
        print(String(format:
            "V10_11 ROI entropy-skip A/B (DX 2800×2288, 256² region, %d trials): " +
            ".direct %.2f ms  vs  .fullImageExtraction %.2f ms  (Δ %.2f ms, %.2f×)",
            trials, directAvg, fullAvg, fullAvg - directAvg,
            directAvg > 0 ? fullAvg / directAvg : 0))
        // Not a hard gate — wall A/B is noisy — but .direct should not be
        // slower than full extraction.
        XCTAssertLessThanOrEqual(directAvg, fullAvg + 5.0,
            ".direct ROI decode should not be slower than .fullImageExtraction")
    }
}
#endif
