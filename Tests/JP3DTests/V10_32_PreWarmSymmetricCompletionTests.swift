// V10_32_PreWarmSymmetricCompletionTests.swift
//
// v10.20.0 — verify the six new preWarm wrappers are callable from
// each JP3D type's API surface (without importing J2KCodec). All
// wrappers delegate to J2KDecoder.preWarm which warms the shared
// J2KMetalSession.processShared — the contract verified here is
// purely API-surface availability, not unique cold-start savings
// (V10_27 already established encoder-side cold cost beyond what
// JP3DDecoder.preWarm covers is below the 3 ms gate).

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCore
@testable import J2K3D

final class V10_32_PreWarmSymmetricCompletionTests: XCTestCase {

    // Each test calls the wrapper to verify (a) it compiles from
    // `import J2K3D` alone (no J2KCodec import needed at the call
    // site) and (b) it doesn't throw / crash. The wrapper is
    // idempotent — calling it during any test won't disturb sibling
    // tests' Metal-session state.

    func testJP3DEncoderPreWarmCallable() async {
        await JP3DEncoder.preWarm()
        await JP3DEncoder.preWarm(includeWarmupDispatch: false)
    }

    func testJP3DMultiSpectralDecoderPreWarmCallable() async {
        await JP3DMultiSpectralDecoder.preWarm()
        await JP3DMultiSpectralDecoder.preWarm(includeWarmupDispatch: false)
    }

    func testJP3DMultiSpectralEncoderPreWarmCallable() async {
        await JP3DMultiSpectralEncoder.preWarm()
        await JP3DMultiSpectralEncoder.preWarm(includeWarmupDispatch: false)
    }

    func testJP3DProgressiveDecoderPreWarmCallable() async {
        await JP3DProgressiveDecoder.preWarm()
        await JP3DProgressiveDecoder.preWarm(includeWarmupDispatch: false)
    }

    func testJP3DStreamWriterPreWarmCallable() async {
        await JP3DStreamWriter.preWarm()
        await JP3DStreamWriter.preWarm(includeWarmupDispatch: false)
    }

    func testJP3DTranscoderPreWarmCallable() async {
        await JP3DTranscoder.preWarm()
        await JP3DTranscoder.preWarm(includeWarmupDispatch: false)
    }

    /// Sanity — all six wrappers point at the same underlying
    /// J2KDecoder.preWarm + share J2KMetalSession.processShared. After
    /// calling any of them with includeWarmupDispatch: true, a
    /// subsequent operation through ANY JP3D type runs in warm state.
    func testCrossTypePreWarmSharedSession() async throws {
        // Warm via JP3DEncoder.preWarm with the real synthetic dispatch.
        await JP3DEncoder.preWarm(includeWarmupDispatch: true)

        // A subsequent JP3DDecoder operation is also warm — confirmed
        // by V10_27's measurement (B - C ≈ 0 ms across fixtures).
        // Here we just verify the cross-type contract: encoding via
        // JP3DEncoder after the JP3DEncoder.preWarm completes works
        // end-to-end and the same shared session covers the decode.
        let volume = JP3DTestVolume.makeLCG(width: 64, height: 64, depth: 8)
        let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
            compressionMode: .losslessHTJ2K))
        let result = try await encoder.encode(volume)
        XCTAssertGreaterThan(result.data.count, 0)

        let decoder = JP3DDecoder()
        let decoded = try await decoder.decode(result.data)
        XCTAssertEqual(decoded.volume.width, 64)
        XCTAssertEqual(decoded.volume.height, 64)
        XCTAssertEqual(decoded.volume.depth, 8)
    }
}

// Helper — local LCG volume factory shared with the other V10_2x/V10_3x tests
// (kept here as a private nested type to avoid cross-file dependencies).
private enum JP3DTestVolume {
    static func makeLCG(width: Int, height: Int, depth: Int, seed: UInt64 = 0xFEED_FACE) -> J2KVolume {
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
}
#endif
