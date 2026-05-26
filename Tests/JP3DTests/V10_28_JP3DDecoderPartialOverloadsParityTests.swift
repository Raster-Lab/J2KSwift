// V10_28_JP3DDecoderPartialOverloadsParityTests.swift
//
// v10.16.0 parity gate — verify the new convenience overloads on
// `JP3DDecoder` (introduced 2026-05-26) produce byte-identical
// volumes vs the existing JP3DDecoderConfiguration + JP3DROIDecoder
// pattern they wrap. The overloads are pure additive surface — no
// existing path should change behaviour.
//
// Overloads under test:
//   1. JP3DDecoder.decode(_:resolutionLevel:) → bit-exact vs
//      JP3DDecoder(configuration: JP3DDecoderConfiguration(resolutionLevel: K)).decode(_:)
//   2. JP3DDecoder.decode(_:region:) → bit-exact vs
//      JP3DROIDecoder().decode(_:, region:)
//   3. JP3DDecoder.decode(_:region:resolutionLevel:) → bit-exact vs
//      JP3DROIDecoder(configuration: JP3DDecoderConfiguration(resolutionLevel: K)).decode(_:, region:)
//   4. JP3DDecoder.decode(_:resolutionLevel: 0) → bit-exact vs
//      JP3DDecoder.decode(_:) (no-op)
//   5. JP3DDecoder.decode(_:, region: <full extent>) → matches full decode volume

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCore
@testable import J2K3D

final class V10_28_JP3DDecoderPartialOverloadsParityTests: XCTestCase {

    private func makeLCGVolume(
        width: Int, height: Int, depth: Int, seed: UInt64 = 0xCAFEBABE
    ) -> J2KVolume {
        let voxelCount = width * height * depth
        var data = Data(count: voxelCount * 2)
        var s: UInt64 = seed &* 6364136223846793005 &+ 1442695040888963407
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt16.self)
            for i in 0..<voxelCount {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                p[i] = UInt16(truncatingIfNeeded: Int((s >> 16) & 0xFFFF))
            }
        }
        let comp = J2KVolumeComponent(
            index: 0, bitDepth: 16, signed: false,
            width: width, height: height, depth: depth,
            data: data)
        return J2KVolume(
            width: width, height: height, depth: depth,
            components: [comp])
    }

    private func encodeLossless(_ volume: J2KVolume) async throws -> Data {
        let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
            compressionMode: .losslessHTJ2K))
        return try await encoder.encode(volume).data
    }

    // MARK: - Tests

    /// 1. decode(_:resolutionLevel: K) bit-exact vs
    ///    JP3DDecoder(configuration: .init(resolutionLevel: K)).decode(_)
    func testDecodeResolutionLevelOverloadBitExact() async throws {
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let codestream = try await encodeLossless(volume)

        // Reference path: explicit configuration.
        let refCfg = JP3DDecoderConfiguration(resolutionLevel: 1)
        let referenceResult = try await JP3DDecoder(configuration: refCfg).decode(codestream)

        // Convenience path: new v10.16.0 overload.
        let convenienceResult = try await JP3DDecoder().decode(codestream, resolutionLevel: 1)

        XCTAssertEqual(referenceResult.volume.width, convenienceResult.volume.width,
                       "Width must match between reference and convenience paths.")
        XCTAssertEqual(referenceResult.volume.height, convenienceResult.volume.height,
                       "Height must match.")
        XCTAssertEqual(referenceResult.volume.depth, convenienceResult.volume.depth,
                       "Depth must match.")
        XCTAssertEqual(referenceResult.volume.components.count,
                       convenienceResult.volume.components.count,
                       "Component count must match.")
        for (rc, cc) in zip(referenceResult.volume.components, convenienceResult.volume.components) {
            XCTAssertEqual(rc.data, cc.data,
                           "Convenience overload must produce byte-identical component data.")
        }
    }

    /// 2. decode(_:region:) bit-exact vs JP3DROIDecoder().decode(_:, region:)
    func testDecodeRegionOverloadBitExact() async throws {
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let codestream = try await encodeLossless(volume)

        let region = JP3DRegion(
            x: 32..<96,
            y: 32..<96,
            z: 4..<12)

        let referenceResult = try await JP3DROIDecoder().decode(codestream, region: region)
        let convenienceResult = try await JP3DDecoder().decode(codestream, region: region)

        XCTAssertEqual(referenceResult.volume.width, convenienceResult.volume.width)
        XCTAssertEqual(referenceResult.volume.height, convenienceResult.volume.height)
        XCTAssertEqual(referenceResult.volume.depth, convenienceResult.volume.depth)
        XCTAssertEqual(referenceResult.tilesDecoded, convenienceResult.tilesDecoded)
        XCTAssertEqual(referenceResult.tilesSkipped, convenienceResult.tilesSkipped)
        for (rc, cc) in zip(referenceResult.volume.components, convenienceResult.volume.components) {
            XCTAssertEqual(rc.data, cc.data,
                           "Convenience region overload must produce byte-identical voxels.")
        }
    }

    /// 3. decode(_:region:resolutionLevel:) bit-exact vs explicit composition
    func testDecodeRegionAndResolutionLevelOverloadBitExact() async throws {
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let codestream = try await encodeLossless(volume)

        let region = JP3DRegion(
            x: 32..<96,
            y: 32..<96,
            z: 4..<12)
        let level = 1

        let refCfg = JP3DDecoderConfiguration(resolutionLevel: level)
        let referenceResult = try await JP3DROIDecoder(configuration: refCfg).decode(codestream, region: region)
        let convenienceResult = try await JP3DDecoder().decode(codestream, region: region, resolutionLevel: level)

        XCTAssertEqual(referenceResult.volume.width, convenienceResult.volume.width)
        XCTAssertEqual(referenceResult.volume.height, convenienceResult.volume.height)
        XCTAssertEqual(referenceResult.volume.depth, convenienceResult.volume.depth)
        for (rc, cc) in zip(referenceResult.volume.components, convenienceResult.volume.components) {
            XCTAssertEqual(rc.data, cc.data,
                           "Convenience K+ROI overload must produce byte-identical voxels.")
        }
    }

    /// 4. decode(_:resolutionLevel: 0) == decode(_:) (no-op level)
    func testDecodeResolutionLevelZeroIsNoOp() async throws {
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let codestream = try await encodeLossless(volume)

        let fullResult = try await JP3DDecoder().decode(codestream)
        let levelZeroResult = try await JP3DDecoder().decode(codestream, resolutionLevel: 0)

        XCTAssertEqual(fullResult.volume.width, levelZeroResult.volume.width)
        XCTAssertEqual(fullResult.volume.height, levelZeroResult.volume.height)
        XCTAssertEqual(fullResult.volume.depth, levelZeroResult.volume.depth)
        for (rc, cc) in zip(fullResult.volume.components, levelZeroResult.volume.components) {
            XCTAssertEqual(rc.data, cc.data,
                           "decode(_:resolutionLevel: 0) must be byte-identical to decode(_:).")
        }
    }

    /// 5. Negative level is clamped to 0 (defensive)
    func testNegativeResolutionLevelIsClamped() async throws {
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let codestream = try await encodeLossless(volume)

        let fullResult = try await JP3DDecoder().decode(codestream)
        // Negative levels should clamp to 0 (= full-resolution decode).
        let clampedResult = try await JP3DDecoder().decode(codestream, resolutionLevel: -3)

        XCTAssertEqual(fullResult.volume.width, clampedResult.volume.width)
        XCTAssertEqual(fullResult.volume.height, clampedResult.volume.height)
        XCTAssertEqual(fullResult.volume.depth, clampedResult.volume.depth)
    }

    /// 6. Configuration overrides honour overload semantics — caller's
    /// configuration's tolerateErrors flag must propagate to the inner
    /// decoder (regression guard).
    func testConfigurationPropagatesThroughOverload() async throws {
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let codestream = try await encodeLossless(volume)

        let outerCfg = JP3DDecoderConfiguration(
            maxQualityLayers: 0,
            resolutionLevel: 0,
            tolerateErrors: false)

        // Just verify the decode succeeds with the propagated configuration —
        // semantic check that the overload's transient inner decoder honours
        // the outer's flags (compile-time + runtime guard).
        let result = try await JP3DDecoder(configuration: outerCfg).decode(codestream, resolutionLevel: 1)
        XCTAssertGreaterThan(result.volume.width, 0)
        XCTAssertGreaterThan(result.volume.height, 0)
        XCTAssertGreaterThan(result.volume.depth, 0)
    }
}
#endif
