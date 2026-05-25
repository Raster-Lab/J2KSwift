// V10_26_JP3DPreWarmProfile.swift
//
// v10.26-research Phase 0 — measure JP3D cold-start cost. The
// 2D codec ships `J2KDecoder.preWarm()` (since v5.28.0) that
// warms `J2KMetalSession.processShared`; JP3DDecoder consumers
// inherit this if they call J2KDecoder.preWarm() before any
// JP3D decode, but the API is not discoverable from the JP3D
// surface. If cold-start is substantial, a JP3DDecoder.preWarm()
// convenience wrapper is the v10.15.0 ship.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2K3D

final class V10_26_JP3DPreWarmProfile: XCTestCase {

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

    /// Measure JP3D cold-start (first decode in a process) vs warm
    /// (subsequent decodes). A meaningful gap (≥ 10 ms) on a small
    /// fixture confirms the value of a JP3DDecoder.preWarm() API.
    func testJP3DColdVsWarmStart() async throws {
        // Use the smallest realistic JP3D fixture (mr_3d_small dims).
        // Bigger fixtures have decode walls that swamp the cold-start
        // signal; the wedge is most visible at small sizes.
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
            compressionMode: .losslessHTJ2K))
        let codestream = try await encoder.encode(volume).data

        // Path A: cold first decode (no preWarm; this trial only
        // captures Metal init if the process is fresh, which it
        // might not be — the test runner may have warmed Metal in
        // an earlier test). Documented limitation.
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = try await JP3DDecoder().decode(codestream)
        let coldMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

        // Path B: explicit preWarm via the NEW JP3DDecoder.preWarm
        // convenience wrapper (v10.15.0).
        await JP3DDecoder.preWarm(includeWarmupDispatch: true)
        let t1 = DispatchTime.now().uptimeNanoseconds
        _ = try await JP3DDecoder().decode(codestream)
        let warmMs = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1_000_000

        // Path C: subsequent warm calls (median of 5)
        var subsequentMs: [Double] = []
        for _ in 0..<5 {
            let t = DispatchTime.now().uptimeNanoseconds
            _ = try await JP3DDecoder().decode(codestream)
            subsequentMs.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000)
        }
        subsequentMs.sort()
        let warmMedian = subsequentMs[subsequentMs.count / 2]

        print(String(format: """

        V10_26 Phase 0 — JP3D cold-start profile (mr_3d_small 128×128×16)

        First decode in process     : %7.2f ms  (cold; may include Metal init)
        First after preWarm()       : %7.2f ms
        Warm median (5 trials)      : %7.2f ms

        Cold-start cost vs warm     : %+7.2f ms

        If cold > warm by ≥ 10 ms on this small fixture, JP3DDecoder.preWarm()
        is a real-world ship for consumers doing one-shot JP3D decodes.
        """,
            coldMs, warmMs, warmMedian,
            coldMs - warmMedian))
    }
}
#endif
