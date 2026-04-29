//
// J2KGPUvsCPULosslessTests.swift
// J2KSwift
//
// Verifies that `J2KDecoder().decodeGPU()` produces byte-identical output
// to `J2KDecoder().decode()` for lossless (5/3 reversible) codestreams.
// DICOMKit's verifyEncodedRoundTrip relies on this for HTJ2K-Lossless.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KGPUvsCPULosslessTests: XCTestCase {
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

    /// 12-bit, 384×384 grayscale, lossless 5/3, HTJ2K. Above the 256×256 GPU
    /// threshold so the GPU IDWT path is exercised.
    func testHTJ2KLossless_GPUDecodeMatchesCPU() async throws {
        let image = makeImage(width: 384, height: 384, bitDepth: 12, seed: 0xCAFEBABE)
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuImage = try await decoder.decode(encoded)
        let gpuImage = try await decoder.decodeGPU(encoded)

        XCTAssertEqual(cpuImage.width, gpuImage.width)
        XCTAssertEqual(cpuImage.height, gpuImage.height)
        XCTAssertEqual(cpuImage.components.count, gpuImage.components.count)
        XCTAssertEqual(cpuImage.components.first?.data, gpuImage.components.first?.data,
                       "GPU decode must produce byte-identical output to CPU decode for lossless")
    }

    /// 16-bit, 512×512 grayscale, lossless 5/3, J2K Part 1 (no HTJ2K).
    func testJ2KPart1Lossless_GPUDecodeMatchesCPU() async throws {
        let image = makeImage(width: 512, height: 512, bitDepth: 16, seed: 0xC0FFEE)
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: false,
            useReversibleFilter: true,
            htj2kBlockFormat: .custom
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuImage = try await decoder.decode(encoded)
        let gpuImage = try await decoder.decodeGPU(encoded)

        XCTAssertEqual(cpuImage.components.first?.data, gpuImage.components.first?.data,
                       "GPU decode must produce byte-identical output to CPU decode for lossless")
    }
}
