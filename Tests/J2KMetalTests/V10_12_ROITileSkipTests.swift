// V10_12_ROITileSkipTests.swift
//
// v10.12-research — validation for ROI decode Stage 2 (tile-granular
// iDWT skip).
//
// v10.6.0 ROI Stage 1 skipped the entropy stage for off-region
// code-blocks but still ran the inverse DWT full-tile. Stage 2 skips
// the *entire* decode (entropy + dequant + inverse DWT + colour + DC
// shift) for tiles that lie completely outside the requested region.
// JPEG 2000 tiles decode independently — no inverse-DWT halo crosses a
// tile boundary — so a fully-off-region tile can be dropped wholesale;
// its pixels are cropped away by `decodeRegion` regardless.
//
// The marquee case is the 16.8 MP MG mammography fixture, which the
// encoder lays out as 2×2 tiles: an ROI within one tile skips the
// other three tiles entirely.
//
// Tests:
//   1. .direct ROI bit-exact vs full-decode crop — MG 2×2 tiles, regions
//      placed to exercise 1-tile / 2-tile / 4-tile coverage
//   2. tile-skip A/B — .direct vs .fullImageExtraction on an MG corner
//      region (3 of 4 tiles skipped)

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_12_ROITileSkipTests: XCTestCase {

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

    func testROITileSkip_bitExact_MG() async throws {
        guard let image = try loadPGM16("medical-real/mg_real_mid_3518x4784.pgm") else {
            throw XCTSkip("MG fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()
        let full = try await decoder.decode(codestream)

        let W = image.width, H = image.height
        // Regions placed by quadrant to drive 1-tile / 2-tile / 4-tile
        // coverage of the encoder's 2×2 MG tiling. The bit-exact contract
        // holds regardless of the exact tile boundary — tile-skip only
        // drops tiles with zero region overlap.
        let regions: [(String, J2KRegion)] = [
            ("TL-quadrant (1 tile)",   J2KRegion(x: W / 8, y: H / 8,
                                                 width: W / 4, height: H / 4)),
            ("BR-quadrant (1 tile)",   J2KRegion(x: W - W / 8 - W / 4, y: H - H / 8 - H / 4,
                                                 width: W / 4, height: H / 4)),
            ("top-span (2 tiles)",     J2KRegion(x: W / 2 - W / 8, y: H / 8,
                                                 width: W / 4, height: H / 4)),
            ("left-span (2 tiles)",    J2KRegion(x: W / 8, y: H / 2 - H / 8,
                                                 width: W / 4, height: H / 4)),
            ("centre (4 tiles)",       J2KRegion(x: W / 2 - W / 8, y: H / 2 - H / 8,
                                                 width: W / 4, height: H / 4)),
            ("full (4 tiles)",         J2KRegion(x: 0, y: 0, width: W, height: H)),
        ]

        for (label, region) in regions {
            let expected = cropReference(full, region)
            let direct = try await decoder.decodeRegion(
                codestream,
                options: J2KROIDecodingOptions(region: region, strategy: .direct))
            XCTAssertEqual(direct.width, region.width, "[\(label)] width")
            XCTAssertEqual(direct.height, region.height, "[\(label)] height")
            XCTAssertEqual(direct.components[0].data, expected,
                "[\(label)] .direct ROI not bit-identical to full-decode crop")
        }
        print("V10_12 ROI tile-skip bit-exact: MG 3518×4784 ✓ (6 regions, 1/2/4-tile coverage)")
    }

    func testROITileSkip_AB_MG() async throws {
        guard let image = try loadPGM16("medical-real/mg_real_mid_3518x4784.pgm") else {
            throw XCTSkip("MG fixture missing")
        }
        let encoder = J2KEncoder(encodingConfiguration: htLosslessConfig())
        let codestream = try await encoder.encode(image)
        let decoder = J2KDecoder()

        // A 256² region in the top-left corner — for a 2×2 tiling this
        // sits inside one tile, so the other three tiles are skipped
        // wholesale (entropy + dequant + inverse DWT + colour + DC).
        let region = J2KRegion(x: 128, y: 128, width: 256, height: 256)

        let trials = 7
        var directWall = 0.0
        var fullWall = 0.0
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
            "V10_12 ROI tile-skip A/B (MG 3518×4784, 256² corner region, %d trials): " +
            ".direct %.2f ms  vs  .fullImageExtraction %.2f ms  (Δ %.2f ms, %.2f×)",
            trials, directAvg, fullAvg, fullAvg - directAvg,
            directAvg > 0 ? fullAvg / directAvg : 0))
        XCTAssertLessThan(directAvg, fullAvg,
            ".direct ROI decode should be faster than .fullImageExtraction on a multi-tile fixture")
    }
}
#endif
