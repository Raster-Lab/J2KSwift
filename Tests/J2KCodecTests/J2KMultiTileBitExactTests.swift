//
// J2KMultiTileBitExactTests.swift
// J2KSwift
//
// Verifies that the parallel multi-tile decode path (`decodeMultiTile` /
// `decodeMultiTileGPU`) produces byte-identical output to a known-good
// single-tile decode of the same image. Locks in the tile-level
// concurrency invariant — any future regression in the task-group
// composition will trip these tests.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KMultiTileBitExactTests: XCTestCase {
    private func deterministicGrayscale(width: Int, height: Int, bitDepth: Int, seed: UInt64) -> Data {
        var state = seed | 1
        let mask: UInt32 = (1 << UInt32(bitDepth)) - 1
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            state = state &* 2862933555777941757 &+ 3037000493
            let v = UInt16(UInt32(state >> 32) & mask)
            bytes[2 * i]     = UInt8(v & 0xFF)
            bytes[2 * i + 1] = UInt8((v >> 8) & 0xFF)
        }
        return Data(bytes)
    }

    private func makeImage(width: Int, height: Int, bitDepth: Int, seed: UInt64) -> J2KImage {
        let raw = deterministicGrayscale(width: width, height: height, bitDepth: bitDepth, seed: seed)
        let component = J2KComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: false,
            width: width,
            height: height,
            data: raw,
            sampleByteOrder: .littleEndian
        )
        return J2KImage(width: width, height: height, components: [component], colorSpace: .grayscale)
    }

    /// Encodes the image twice (single-tile reference vs N-tile), decodes
    /// each through CPU and GPU, and asserts all four outputs are
    /// byte-identical.
    private func assertMultiTileMatchesSingleTile(
        width: Int, height: Int, bitDepth: Int,
        tile: (width: Int, height: Int),
        useHTJ2K: Bool,
        seed: UInt64,
        line: UInt = #line
    ) async throws {
        let image = makeImage(width: width, height: height, bitDepth: bitDepth, seed: seed)

        // Single-tile reference (encoded with tileSize=(0,0))
        let refConfig = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: useHTJ2K,
            useReversibleFilter: true,
            htj2kBlockFormat: useHTJ2K ? .conformant : .custom
        )
        let refEncoder = J2KEncoder(encodingConfiguration: refConfig)
        let refEncoded = try await refEncoder.encode(image)

        // Multi-tile encoding with the requested tile size
        var multiConfig = refConfig
        multiConfig.tileSize = tile
        let multiEncoder = J2KEncoder(encodingConfiguration: multiConfig)
        let multiEncoded = try await multiEncoder.encode(image)

        // Decode all four ways
        let decoder = J2KDecoder()
        let refCPU   = try await decoder.decode(refEncoded)
        let refGPU   = try await decoder.decodeGPU(refEncoded)
        let multiCPU = try await decoder.decode(multiEncoded)
        let multiGPU = try await decoder.decodeGPU(multiEncoded)

        let baseline = refCPU.components.first?.data
        XCTAssertNotNil(baseline, line: line)
        XCTAssertEqual(baseline, refGPU.components.first?.data,
                       "single-tile CPU ≠ GPU", line: line)
        XCTAssertEqual(baseline, multiCPU.components.first?.data,
                       "multi-tile parallel CPU ≠ single-tile reference", line: line)
        XCTAssertEqual(baseline, multiGPU.components.first?.data,
                       "multi-tile parallel GPU ≠ single-tile reference", line: line)
    }

    /// 4 tiles, J2K Part 1 lossless 5/3.
    func test4Tiles_J2KPart1_LosslessGrayscale() async throws {
        try await assertMultiTileMatchesSingleTile(
            width: 512, height: 512, bitDepth: 12,
            tile: (256, 256),
            useHTJ2K: false,
            seed: 0xCAFE_BEEF
        )
    }

    /// 9 tiles (3×3 grid with non-square remainder), HTJ2K lossless.
    /// Exercises the path where `tileX/tileY` are mid-image offsets.
    func test9Tiles_HTJ2KLosslessGrayscale() async throws {
        try await assertMultiTileMatchesSingleTile(
            width: 768, height: 768, bitDepth: 12,
            tile: (256, 256),
            useHTJ2K: true,
            seed: 0xDEAD_BEEF
        )
    }

    /// 4 tiles on a non-power-of-2 image — last column / last row are smaller
    /// than the requested tile size, which exercises the boundary handling
    /// in compositeTile.
    func test4Tiles_J2KPart1_NonPowerOfTwoGrayscale() async throws {
        try await assertMultiTileMatchesSingleTile(
            width: 600, height: 600, bitDepth: 16,
            tile: (384, 384),
            useHTJ2K: false,
            seed: 0xFACE_FACE
        )
    }
}
