//
// V10_20_JP3DBridgeParityTests.swift
// J2KSwift
//
// v10.20-research Phase 1 — JP3D bridge SPI parity oracle.
//
// Asserts the composition guarantee:
//
//     decode(data) ≡ _jp3dIDWTAndFinalize(_jp3dDecodeToCoefficients(data))
//
// on every single-tile codestream. The bridge SPI is the foundation
// for Phase 2's batched GPU iDWT; if the composition is bit-exact
// equal to `decode(_:)` then Phase 2's batched path is provably
// equivalent to the production single-slice path (since Phase 2 only
// changes WHERE the iDWT runs — same coefficients in, same spatial
// data out).

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10_20_JP3DBridgeParityTests: XCTestCase {

    // MARK: - Test fixture builder

    /// Mirrors the v10.18 JP3D parity-oracle LCG synthesis pattern
    /// (multiplier `1442695040888963407`) so the bytes look the same
    /// as the slices JP3DSliceStackCodec would route through this SPI.
    private func makeLCGImage(
        width: Int, height: Int,
        bitDepth: Int = 16, seed: UInt64 = 0xC0FFEE
    ) -> J2KImage {
        let bytesPerSample = (bitDepth + 7) / 8
        let voxelCount = width * height
        let maxVal = (1 << bitDepth) - 1
        var data = Data(count: voxelCount * bytesPerSample)
        var s: UInt64 = seed &* 6364136223846793005 &+ 1442695040888963407
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            for i in 0..<voxelCount {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let sample = UInt16(truncatingIfNeeded:
                    Int((s >> 16) & 0xFFFFFFFF) % (maxVal + 1))
                // Big-endian (matches J2KComponent.sampleByteOrder convention).
                p[i] = sample.bigEndian
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: data, sampleByteOrder: .bigEndian)
        return J2KImage(width: width, height: height, components: [comp])
    }

    private func losslessHTEncoder() -> J2KEncoder {
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
        return J2KEncoder(encodingConfiguration: cfg)
    }

    /// **Spec**: the bridge SPI composition equals the direct decode
    /// on a single-tile lossless HT codestream, byte-exact.
    func testBridgeCompositionEqualsDirectDecode_256x256() async throws {
        let image = makeLCGImage(width: 256, height: 256)
        let codestream = try await losslessHTEncoder().encode(image)

        let decoder = J2KDecoder()
        let direct = try await decoder.decode(codestream)
        let coefs   = try await decoder._jp3dDecodeToCoefficients(codestream)
        let bridged = try await decoder._jp3dIDWTAndFinalize(coefs)

        XCTAssertEqual(direct.width,  bridged.width)
        XCTAssertEqual(direct.height, bridged.height)
        XCTAssertEqual(direct.components.count, bridged.components.count)
        for (i, dComp) in direct.components.enumerated() {
            let bComp = bridged.components[i]
            XCTAssertEqual(dComp.bitDepth, bComp.bitDepth)
            XCTAssertEqual(dComp.signed,   bComp.signed)
            XCTAssertEqual(dComp.width,    bComp.width)
            XCTAssertEqual(dComp.height,   bComp.height)
            XCTAssertEqual(dComp.data,     bComp.data,
                           "Phase 1 composition broken on 256x256 — "
                           + "bridge SPI iDWT output differs from direct decode.")
        }
    }

    func testBridgeCompositionEqualsDirectDecode_512x512() async throws {
        let image = makeLCGImage(width: 512, height: 512, seed: 0xDEADBEEF)
        let codestream = try await losslessHTEncoder().encode(image)

        let decoder = J2KDecoder()
        let direct = try await decoder.decode(codestream)
        let coefs   = try await decoder._jp3dDecodeToCoefficients(codestream)
        let bridged = try await decoder._jp3dIDWTAndFinalize(coefs)

        XCTAssertEqual(direct.components.first?.data, bridged.components.first?.data,
                       "Phase 1 composition broken on 512x512.")
    }

    /// Tiny fixture — exercises the small-codestream edge cases.
    func testBridgeCompositionEqualsDirectDecode_64x64() async throws {
        let image = makeLCGImage(width: 64, height: 64, seed: 1)
        let codestream = try await losslessHTEncoder().encode(image)

        let decoder = J2KDecoder()
        let direct = try await decoder.decode(codestream)
        let coefs   = try await decoder._jp3dDecodeToCoefficients(codestream)
        let bridged = try await decoder._jp3dIDWTAndFinalize(coefs)

        XCTAssertEqual(direct.components.first?.data, bridged.components.first?.data,
                       "Phase 1 composition broken on 64x64.")
    }

    /// Width/height not equal — verifies the bridge doesn't assume
    /// square slices.
    func testBridgeCompositionEqualsDirectDecode_128x320() async throws {
        let image = makeLCGImage(width: 128, height: 320, seed: 42)
        let codestream = try await losslessHTEncoder().encode(image)

        let decoder = J2KDecoder()
        let direct = try await decoder.decode(codestream)
        let coefs   = try await decoder._jp3dDecodeToCoefficients(codestream)
        let bridged = try await decoder._jp3dIDWTAndFinalize(coefs)

        XCTAssertEqual(direct.width,  bridged.width)
        XCTAssertEqual(direct.height, bridged.height)
        XCTAssertEqual(direct.components.first?.data, bridged.components.first?.data,
                       "Phase 1 composition broken on 128x320.")
    }

    /// Determinism — two SPI runs against the same codestream produce
    /// byte-identical output.
    func testBridgeDeterministic() async throws {
        let image = makeLCGImage(width: 256, height: 256)
        let codestream = try await losslessHTEncoder().encode(image)

        let decoder = J2KDecoder()
        let coefs1 = try await decoder._jp3dDecodeToCoefficients(codestream)
        let out1   = try await decoder._jp3dIDWTAndFinalize(coefs1)
        let coefs2 = try await decoder._jp3dDecodeToCoefficients(codestream)
        let out2   = try await decoder._jp3dIDWTAndFinalize(coefs2)

        XCTAssertEqual(out1.components.first?.data, out2.components.first?.data,
                       "Phase 1 bridge SPI must be deterministic.")
    }

    // Multi-tile-throws test elided: J2KEncoder's tileSize parameter
    // auto-promotes to single-tile when image dims fit a single tile,
    // and forcing a true multi-tile codestream needs a separate fixture
    // source. JP3D's slice-stack codec by construction never emits
    // multi-tile per-slice codestreams, so the runtime constraint is
    // documented at the bridge SPI's `mutating func
    // decodeToCoefficients` site and exercised only when a manually-
    // constructed multi-tile codestream is routed through the SPI —
    // not a Phase 1 deliverable.
}
