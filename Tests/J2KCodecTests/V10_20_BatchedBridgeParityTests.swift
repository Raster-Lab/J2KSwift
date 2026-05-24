//
// V10_20_BatchedBridgeParityTests.swift
// J2KSwift
//
// v10.20-research Phase 3b — JP3D batched bridge SPI parity oracle.
//
// Specification: for every slice `i` in the batch,
//     _jp3dIDWTAndFinalizeBatched(coefsBatch)[i].components[0].data ==
//         _jp3dIDWTAndFinalize(coefsBatch[i]).components[0].data
// on every JP3D-shape input (5/3 reversible, single-component,
// uniform dims across the batch, full resolution, no ROI).
//
// The batched bridge SPI is the Phase 3a Metal orchestrator wired
// into the v10.10.0-era bridge SPI surface so JP3DSliceStackCodec
// can consume it in Phase 3c. Bit-exact composition vs the serial
// bridge SPI is the safety net — any subband-grouping or pad/strip
// bug surfaces here, not as wrong voxels in JP3D output.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10_20_BatchedBridgeParityTests: XCTestCase {

    // MARK: - Fixture builder

    private func makeLCGImage(
        width: Int, height: Int,
        bitDepth: Int = 16, seed: UInt64
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

    // MARK: - Tests

    /// Single-slice batch — bit-exact equivalent to the serial bridge
    /// SPI. Establishes baseline before testing multi-slice.
    func testBatchedBridgeOfOneEqualsSerial_256x256() async throws {
        let image = makeLCGImage(width: 256, height: 256, seed: 1)
        let codestream = try await losslessHTEncoder().encode(image)

        let decoder = J2KDecoder()
        let coefs = try await decoder._jp3dDecodeToCoefficients(codestream)
        let serial = try await decoder._jp3dIDWTAndFinalize(coefs)
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched([coefs])

        XCTAssertEqual(batched.count, 1)
        XCTAssertEqual(serial.components.first?.data,
                       batched[0].components.first?.data,
                       "Batched bridge SPI of 1 diverges from serial")
    }

    /// 4-slice batch — typical JP3D mid-volume slice count for a tile.
    func testBatchedBridgeOfFourEqualsSerial_256x256() async throws {
        let decoder = J2KDecoder()
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<4 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0x100 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let coefs = try await decoder._jp3dDecodeToCoefficients(codestream)
            coefsArr.append(coefs)
            serials.append(try await decoder._jp3dIDWTAndFinalize(coefs))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)

        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge SPI slice \(s) diverges from serial")
        }
    }

    /// 16-slice batch — typical JP3D tile-depth size. Confirms the
    /// orchestrator scales correctly through the bridge SPI.
    func testBatchedBridgeOfSixteenEqualsSerial_256x256() async throws {
        let decoder = J2KDecoder()
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<16 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0x200 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let coefs = try await decoder._jp3dDecodeToCoefficients(codestream)
            coefsArr.append(coefs)
            serials.append(try await decoder._jp3dIDWTAndFinalize(coefs))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)

        XCTAssertEqual(batched.count, 16)
        for s in 0..<16 {
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge SPI 16-slice slice \(s) diverges from serial")
        }
    }

    /// 4-slice batch @ 512×512 — larger fixture, typical thorax CT slice.
    func testBatchedBridgeOfFourEqualsSerial_512x512() async throws {
        let decoder = J2KDecoder()
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<4 {
            let image = makeLCGImage(width: 512, height: 512, seed: UInt64(0x300 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let coefs = try await decoder._jp3dDecodeToCoefficients(codestream)
            coefsArr.append(coefs)
            serials.append(try await decoder._jp3dIDWTAndFinalize(coefs))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)

        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge SPI 512×512 slice \(s) diverges from serial")
        }
    }

    /// Empty batch returns empty without crashing.
    func testBatchedBridgeEmptyReturnsEmpty() async throws {
        let decoder = J2KDecoder()
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched([])
        XCTAssertEqual(batched.count, 0)
    }
}
