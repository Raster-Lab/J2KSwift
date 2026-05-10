// V8_3_GPUIDWTRootCauseDiagnostic.swift
//
// v8.3 — root-cause diagnostic for the GPU multi-tile-per-tile
// 5/3 IDWT corruption that the v8.2 fix routed around.
//
// The v8.2 fix forces CPU IDWT in `decodeTilePayloadGPU` when the
// cross-tile batched-entropy short-circuit is active (see
// V8_2_0_MG_CORRUPTION_ROOT_CAUSE.md). The underlying GPU IDWT
// bug is not actually fixed — this test bypasses the v8.2 fix
// to reproduce the bug, then localises the failing tile + level.
//
// **Test-only**: flips `DecoderPipeline._v82_disableIDWTRoutingFix`
// to `true` for the duration of one decode, then restores. Never
// affects production. The flag exists for v8.3 diagnostic +
// regression coverage only.

#if os(macOS)

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V8_3_GPUIDWTRootCauseDiagnostic: XCTestCase {

    private func makeImage(width: Int, height: Int) -> J2KImage {
        var data = Data(count: width * height * 2)
        var rng: UInt64 = 0xC0FFEE_DEADBEEF
        data.withUnsafeMutableBytes { rawBuf in
            let p = rawBuf.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(width * height) {
                rng &+= 0x9E37_79B9_7F4A_7C15
                var z = rng
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                let v = UInt16((z ^ (z >> 31)) & 0x0FFF) // 12-bit
                p[i * 2 + 0] = UInt8(v >> 8)
                p[i * 2 + 1] = UInt8(v & 0xFF)
            }
        }
        return J2KImage(
            width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height,
                data: data, sampleByteOrder: .bigEndian)])
    }

    private func encodeMultiTile(_ image: J2KImage) async throws -> Data {
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, qualityLayers: 1,
            useHTJ2K: true, useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: image.width,
            imageHeight: image.height,
            decompositionLevels: cfg.decompositionLevels,
            mode: .tiles2x2)
        XCTAssertTrue(layout.isMultiTile)
        let r = try await J2KMultiTileEncoder.encode(
            image: image, layout: layout, configuration: cfg)
        return r.codestream
    }

    /// **v8.3 fix verified**: GPU multi-tile-per-tile IDWT now
    /// decodes bit-exactly even with the v8.2 routing fix bypassed
    /// (i.e. when GPU IDWT is the active path for batched-entropy).
    /// The two underlying bugs (naive-recursion levelSizes for
    /// non-zero canvas X origin; `halfHH = H/2` instead of `H − llH`
    /// for odd canvas Y origin) are both fixed in v8.3.
    func testGPUIDWT_BatchedEntropy_BitExact_1760x2392() async throws {
        let image = makeImage(width: 1760, height: 2392)
        let bytes = try await encodeMultiTile(image)

        let prevBatched = DecoderPipeline._multiTileBatchedEntropyEnabled
        let prevFix = DecoderPipeline._v82_disableIDWTRoutingFix
        defer {
            DecoderPipeline._multiTileBatchedEntropyEnabled = prevBatched
            DecoderPipeline._v82_disableIDWTRoutingFix = prevFix
        }
        DecoderPipeline._multiTileBatchedEntropyEnabled = true
        DecoderPipeline._v82_disableIDWTRoutingFix = true

        let decoded = try await J2KDecoder().decode(bytes)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "v8.3: GPU multi-tile-per-tile IDWT must decode bit-exactly via the " +
            "batched-entropy path even with the v8.2 routing fix bypassed")
    }

    /// v8.3 — GPU IDWT must also decode the production mg DICOM
    /// dimensions (3520×4784) bit-exactly via the batched-entropy
    /// path with the v8.2 routing fix bypassed.
    func testGPUIDWT_BatchedEntropy_BitExact_MgFixture() async throws {
        let image = makeImage(width: 3520, height: 4784)
        let bytes = try await encodeMultiTile(image)

        let prevBatched = DecoderPipeline._multiTileBatchedEntropyEnabled
        let prevFix = DecoderPipeline._v82_disableIDWTRoutingFix
        defer {
            DecoderPipeline._multiTileBatchedEntropyEnabled = prevBatched
            DecoderPipeline._v82_disableIDWTRoutingFix = prevFix
        }
        DecoderPipeline._multiTileBatchedEntropyEnabled = true
        DecoderPipeline._v82_disableIDWTRoutingFix = true

        let decoded = try await J2KDecoder().decode(bytes)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data,
            "v8.3: GPU multi-tile-per-tile IDWT must decode the mg fixture " +
            "(3520×4784, 16.84 M px) bit-exactly via the batched-entropy path")
    }

    /// Per-tile divergence localisation: which tile produces incorrect
    /// pixels under the GPU IDWT path? Runs once with v8.2 fix ON
    /// (CPU IDWT — ground truth) and once OFF (GPU IDWT — buggy),
    /// reports per-tile mismatch counts.
    func testLocalisation_PerTileDivergence_1760x2392() async throws {
        let image = makeImage(width: 1760, height: 2392)
        let bytes = try await encodeMultiTile(image)

        let prevBatched = DecoderPipeline._multiTileBatchedEntropyEnabled
        let prevFix = DecoderPipeline._v82_disableIDWTRoutingFix
        defer {
            DecoderPipeline._multiTileBatchedEntropyEnabled = prevBatched
            DecoderPipeline._v82_disableIDWTRoutingFix = prevFix
        }

        // Decode with v8.2 fix (CPU IDWT) — ground truth.
        DecoderPipeline._multiTileBatchedEntropyEnabled = true
        DecoderPipeline._v82_disableIDWTRoutingFix = false
        let decFixed = try await J2KDecoder().decode(bytes)

        // Decode with v8.2 fix bypassed (GPU IDWT) — buggy.
        DecoderPipeline._v82_disableIDWTRoutingFix = true
        let decBuggy = try await J2KDecoder().decode(bytes)

        let cpuBytes = decFixed.components[0].data
        let gpuBytes = decBuggy.components[0].data

        // Tile partition: 2x2 of 880×1196 each. Image origin (0,0)
        // is tile (0,0); right half is tile column 1; bottom half
        // is tile row 1.
        let halfW = (image.width + 1) / 2
        let halfH = (image.height + 1) / 2

        var perTileMismatch = [[Int]](repeating: [Int](repeating: 0, count: 2), count: 2)
        var firstMismatchPerTile = [[Int?]](repeating: [Int?](repeating: nil, count: 2), count: 2)

        let pixelCount = image.width * image.height
        for px in 0..<pixelCount {
            let lo = px * 2
            let hi = lo + 1
            if cpuBytes[lo] != gpuBytes[lo] || cpuBytes[hi] != gpuBytes[hi] {
                let row = px / image.width
                let col = px % image.width
                let tr = row >= halfH ? 1 : 0
                let tc = col >= halfW ? 1 : 0
                perTileMismatch[tr][tc] += 1
                if firstMismatchPerTile[tr][tc] == nil {
                    firstMismatchPerTile[tr][tc] = px
                }
            }
        }

        print("[diag] per-tile mismatch counts (CPU-IDWT vs GPU-IDWT):")
        for tr in 0..<2 {
            for tc in 0..<2 {
                let n = perTileMismatch[tr][tc]
                if n > 0 {
                    let firstPx = firstMismatchPerTile[tr][tc]!
                    let row = firstPx / image.width
                    let col = firstPx % image.width
                    let tileLocalRow = row - tr * halfH
                    let tileLocalCol = col - tc * halfW
                    print(String(format: "[diag]   tile (%d, %d): %d mismatches; first at image (row=%d col=%d) = tile-local (row=%d col=%d)",
                        tr, tc, n, row, col, tileLocalRow, tileLocalCol))
                } else {
                    print("[diag]   tile (\(tr), \(tc)): clean")
                }
            }
        }
    }
}

#endif
