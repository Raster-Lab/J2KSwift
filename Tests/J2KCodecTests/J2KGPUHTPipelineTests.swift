// J2KGPUHTPipelineTests.swift
//
// M2-prime forward-validation: end-to-end pipeline test that
// `J2KDecoder().decodeWithGPUHT()` produces byte-identical output
// to `J2KDecoder().decodeGPU()` on lossless HTJ2K codestreams.
//
// `decodeGPU()` runs HT entropy decode on CPU and inverse DWT on GPU.
// `decodeWithGPUHT()` runs both HT entropy decode AND inverse DWT on
// GPU. The two must agree byte-for-byte; this is the bit-exactness
// gate for the M2-prime production-integration path landing in
// v5.5.0.

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KGPUHTPipelineTests: XCTestCase {

    private func deterministic16BitGrayscale(width: Int, height: Int, seed: UInt64) -> Data {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            state = state &* 2862933555777941757 &+ 3037000493
            let v = UInt16((state >> 32) & 0x0FFF)  // 12-bit DX-style range
            bytes[2 * i]     = UInt8(v & 0xFF)
            bytes[2 * i + 1] = UInt8((v >> 8) & 0xFF)
        }
        return Data(bytes)
    }

    private func makeImage(width: Int, height: Int, bitDepth: Int, seed: UInt64) -> J2KImage {
        let raw = deterministic16BitGrayscale(width: width, height: height, seed: seed)
        let component = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            data: raw, sampleByteOrder: .littleEndian)
        return J2KImage(
            width: width, height: height,
            components: [component], colorSpace: .grayscale)
    }

    /// 12-bit, 384×384, lossless 5/3, HTJ2K conformant. The GPU HT
    /// dispatch path must produce identical bytes to the CPU HT path.
    func testHTJ2KLossless_GPUHTMatchesCPUHT() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        let image = makeImage(width: 384, height: 384, bitDepth: 12, seed: 0xCAFEBABE)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuHT = try await decoder.decodeGPU(encoded)
        let gpuHT = try await decoder.decodeWithGPUHT(encoded)

        XCTAssertEqual(cpuHT.width, gpuHT.width)
        XCTAssertEqual(cpuHT.height, gpuHT.height)
        XCTAssertEqual(cpuHT.components.count, gpuHT.components.count)
        XCTAssertEqual(
            cpuHT.components.first?.data, gpuHT.components.first?.data,
            "GPU HT path must match CPU HT path byte-for-byte for lossless HTJ2K")
    }

    /// Larger workload (512×512, 16-bit). Stresses the multi-codeblock
    /// batch path with more codeblocks per tile.
    func testHTJ2KLossless512_GPUHTMatchesCPUHT() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        let image = makeImage(width: 512, height: 512, bitDepth: 16, seed: 0xFEEDFACE)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuHT = try await decoder.decodeGPU(encoded)
        let gpuHT = try await decoder.decodeWithGPUHT(encoded)

        XCTAssertEqual(
            cpuHT.components.first?.data, gpuHT.components.first?.data,
            "GPU HT path must match CPU HT path byte-for-byte (512×512)")
    }

    /// J2K Part 1 (no HTJ2K). The flag must be inert: with no HT
    /// blocks in the codestream, `decodeWithGPUHT` falls through to
    /// the existing CPU EBCOT path and produces identical output to
    /// `decodeGPU`.
    func testJ2KPart1_GPUHTFlagIsInert() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        let image = makeImage(width: 384, height: 384, bitDepth: 12, seed: 0xBEEFCAFE)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: false,                 // Part 1
            useReversibleFilter: true,
            htj2kBlockFormat: .custom)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuPath = try await decoder.decodeGPU(encoded)
        let gpuFlag = try await decoder.decodeWithGPUHT(encoded)

        XCTAssertEqual(
            cpuPath.components.first?.data, gpuFlag.components.first?.data,
            "useGPUHT flag must be inert on Part 1 codestreams")
    }
}
