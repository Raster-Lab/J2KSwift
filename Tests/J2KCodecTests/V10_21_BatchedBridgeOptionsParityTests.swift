//
// V10_21_BatchedBridgeOptionsParityTests.swift
// J2KSwift
//
// v10.21-research — JP3D batched bridge SPI parity for the new
// `JP3DBridgeOptions` overload (partial-resolution + ROI).
//
// Specification: for every slice `i` in the batch and any `options`
// uniform across the batch,
//     _jp3dIDWTAndFinalizeBatched(coefsBatchWithOptions)[i].components[0].data ==
//         _jp3dIDWTAndFinalize(coefsBatchWithOptions[i]).components[0].data
// on every JP3D-shape input (5/3 reversible, single-component,
// uniform dims across the batch).
//
// The batched path's eligibility gate accepts uniform partial-res
// + ROI; the orchestrator truncates the chain to `effectiveLevels`
// for partial-res (K=N-effectiveLevels) and crops after iDWT for
// ROI. K=0 (thumbnail) falls back to per-slice serial because there
// are no iDWT levels to dispatch.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10_21_BatchedBridgeOptionsParityTests: XCTestCase {

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

    // MARK: - Partial-resolution parity

    /// 4-slice batch @ 256×256 with partial-resolution K=4 (one
    /// iDWT step from deepest, output 32×32). Batched ≡ per-slice
    /// serial bit-exact.
    func testBatchedBridgeWithPartialResolutionK4_4Slices_256x256() async throws {
        let decoder = J2KDecoder()
        let opts = JP3DBridgeOptions(partialResolutionLevel: 4)
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<4 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0x500 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let c = try await decoder._jp3dDecodeToCoefficients(codestream, options: opts)
            coefsArr.append(c)
            serials.append(try await decoder._jp3dIDWTAndFinalize(c))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)
        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            // For levels=5 codestream, K=4 means 4 iDWT steps run.
            // Output is at depth (5-4)=1, dims = ceil(256/2^1) = 128.
            XCTAssertEqual(serials[s].width, 128)
            XCTAssertEqual(serials[s].height, 128)
            XCTAssertEqual(batched[s].width, 128)
            XCTAssertEqual(batched[s].height, 128)
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge (K=4) slice \(s) diverges from serial")
        }
    }

    /// 4-slice batch @ 256×256 with partial-resolution K=2 (3 iDWT
    /// steps, output 32×32).
    func testBatchedBridgeWithPartialResolutionK2_4Slices_256x256() async throws {
        let decoder = J2KDecoder()
        let opts = JP3DBridgeOptions(partialResolutionLevel: 2)
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<4 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0x600 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let c = try await decoder._jp3dDecodeToCoefficients(codestream, options: opts)
            coefsArr.append(c)
            serials.append(try await decoder._jp3dIDWTAndFinalize(c))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)
        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            // K=2 means 2 iDWT steps run; output depth = 5-2 = 3,
            // dims = ceil(256/2^3) = 32.
            XCTAssertEqual(serials[s].width, 32)
            XCTAssertEqual(serials[s].height, 32)
            XCTAssertEqual(batched[s].width, 32)
            XCTAssertEqual(batched[s].height, 32)
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge (K=2) slice \(s) diverges from serial")
        }
    }

    /// K=N full-res via options should match the v10.20 no-options
    /// path bit-exact (the options carry .partialResolutionLevel=N
    /// which the orchestrator should treat as full-res).
    func testBatchedBridgeWithPartialResolutionKN_EquivalentToNoOptions() async throws {
        let decoder = J2KDecoder()
        let optsFull = JP3DBridgeOptions(partialResolutionLevel: 5)
        let image = makeLCGImage(width: 256, height: 256, seed: 0x700)
        let codestream = try await losslessHTEncoder().encode(image)
        let cNoOpts = try await decoder._jp3dDecodeToCoefficients(codestream)
        let cWithOpts = try await decoder._jp3dDecodeToCoefficients(codestream, options: optsFull)
        let serial = try await decoder._jp3dIDWTAndFinalize(cNoOpts)
        let batchedNoOpts = try await decoder._jp3dIDWTAndFinalizeBatched([cNoOpts])
        let batchedWithOpts = try await decoder._jp3dIDWTAndFinalizeBatched([cWithOpts])
        XCTAssertEqual(serial.components.first?.data,
                       batchedNoOpts[0].components.first?.data)
        XCTAssertEqual(serial.components.first?.data,
                       batchedWithOpts[0].components.first?.data,
                       "K=N options-batched diverges from K=nil options-batched")
    }

    // MARK: - ROI parity

    /// 4-slice batch @ 256×256, ROI = centre 128×128 corner. Batched
    /// ≡ per-slice serial bit-exact; both produce 128×128 output.
    func testBatchedBridgeWithROI_4Slices_256x256() async throws {
        let decoder = J2KDecoder()
        let region = J2KRegion(x: 64, y: 64, width: 128, height: 128)
        let opts = JP3DBridgeOptions(regionOfInterest: region)
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<4 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0x800 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let c = try await decoder._jp3dDecodeToCoefficients(codestream, options: opts)
            coefsArr.append(c)
            serials.append(try await decoder._jp3dIDWTAndFinalize(c))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)
        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            XCTAssertEqual(serials[s].width, 128)
            XCTAssertEqual(serials[s].height, 128)
            XCTAssertEqual(batched[s].width, 128)
            XCTAssertEqual(batched[s].height, 128)
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge (ROI 128²) slice \(s) diverges from serial")
        }
    }

    /// 16-slice batch with a small corner ROI — the typical JP3D
    /// volume slice-scrubbing case at viewport zoom.
    func testBatchedBridgeWithSmallROI_16Slices_256x256() async throws {
        let decoder = J2KDecoder()
        let region = J2KRegion(x: 0, y: 0, width: 64, height: 64)
        let opts = JP3DBridgeOptions(regionOfInterest: region)
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<16 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0x900 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let c = try await decoder._jp3dDecodeToCoefficients(codestream, options: opts)
            coefsArr.append(c)
            serials.append(try await decoder._jp3dIDWTAndFinalize(c))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)
        XCTAssertEqual(batched.count, 16)
        for s in 0..<16 {
            XCTAssertEqual(batched[s].width, 64)
            XCTAssertEqual(batched[s].height, 64)
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge (corner ROI) slice \(s) diverges from serial")
        }
    }

    // MARK: - Composition parity (partial-res + ROI)

    /// 4-slice batch with BOTH partial-res K=4 (in 2D codec terms,
    /// i.e. 4 iDWT steps) AND a full-coords ROI. v10.22 convention:
    /// ROI in `JP3DBridgeOptions` is full-image coords; the bridge
    /// maps it onto the reduced grid via `region / 2^(N-K)` before
    /// cropping. For partialResolutionLevel=4 with N=5, factor = 2,
    /// so full ROI(32, 32, 128, 128) → reduced ROI(16, 16, 64, 64)
    /// → output 64×64.
    func testBatchedBridgeWithPartialResolutionAndROI_4Slices_256x256() async throws {
        let decoder = J2KDecoder()
        // Full-coords ROI within 256×256. With K=4 (1 iDWT step short
        // of full), 2D output is 128×128. Region maps to reduced grid
        // via factor = 2^(5-4) = 2.
        let region = J2KRegion(x: 32, y: 32, width: 128, height: 128)
        let opts = JP3DBridgeOptions(
            partialResolutionLevel: 4, regionOfInterest: region)
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<4 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0xA00 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let c = try await decoder._jp3dDecodeToCoefficients(codestream, options: opts)
            coefsArr.append(c)
            serials.append(try await decoder._jp3dIDWTAndFinalize(c))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)
        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            // Reduced output: 128×128. ROI mapped: x=16, y=16,
            // w=64, h=64. → output 64×64.
            XCTAssertEqual(batched[s].width, 64)
            XCTAssertEqual(batched[s].height, 64)
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge (K=4 + full-coords ROI) slice \(s) diverges from serial")
        }
    }

    // MARK: - K=0 fallback

    /// K=0 (thumbnail = deepest LL only) — orchestrator can't dispatch
    /// an empty iDWT chain, so the path must fall back to per-slice
    /// serial. Batched output still matches serial bit-exact.
    func testBatchedBridgeWithPartialResolutionK0_FallsBackBitExact() async throws {
        let decoder = J2KDecoder()
        let opts = JP3DBridgeOptions(partialResolutionLevel: 0)
        var coefsArr: [JP3DSliceCoefficients] = []
        var serials: [J2KImage] = []
        for s in 0..<4 {
            let image = makeLCGImage(width: 256, height: 256, seed: UInt64(0xB00 + s))
            let codestream = try await losslessHTEncoder().encode(image)
            let c = try await decoder._jp3dDecodeToCoefficients(codestream, options: opts)
            coefsArr.append(c)
            serials.append(try await decoder._jp3dIDWTAndFinalize(c))
        }
        let batched = try await decoder._jp3dIDWTAndFinalizeBatched(coefsArr)
        XCTAssertEqual(batched.count, 4)
        for s in 0..<4 {
            // K=0 → output depth = N = 5, dims = ceil(256/32) = 8.
            XCTAssertEqual(batched[s].width, 8)
            XCTAssertEqual(batched[s].height, 8)
            XCTAssertEqual(serials[s].components.first?.data,
                           batched[s].components.first?.data,
                           "Batched bridge (K=0 thumbnail) slice \(s) diverges from serial")
        }
    }
}
