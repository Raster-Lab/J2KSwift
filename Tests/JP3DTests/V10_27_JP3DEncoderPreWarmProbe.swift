// V10_27_JP3DEncoderPreWarmProbe.swift
//
// v10.16-research Phase 0 — measure JP3D *encoder* cold-start cost.
//
// v10.15.0 shipped `JP3DDecoder.preWarm` as a discoverable wrapper around
// `J2KDecoder.preWarm` (v5.28.0). Open question: does the encoder side
// also pay a non-trivial cold-start cost that a parallel
// `JP3DEncoder.preWarm` / `JP3DROIEncoder.preWarm` API would amortise?
//
// `J2KDecoder.preWarm` pre-compiles DECODE pipelines + (default) runs a
// tiny 256x256 synthetic encode+decode. The encode in the warmup dispatch
// is small enough that it likely takes the CPU forward DWT path — so the
// forward-DWT GPU kernels (j2k_dwt_forward_53_*_int*) and HT cleanup
// emit pipelines may still compile lazily on the user's first real
// encode.
//
// This probe captures three paths:
//   A. Cold first JP3D encode  (no preWarm)
//   B. First JP3D encode after `JP3DDecoder.preWarm(includeWarmupDispatch: true)`
//   C. Warm-median JP3D encode (5 trials)
//
// Deltas:
//   A - B  → how much existing decoder preWarm already saves on encode
//   B - C  → encoder-specific cold cost NOT amortised by decoder preWarm
//
// If B - C ≥ 3 ms (v7.4 acceptance threshold), a dedicated
// J2KEncoder.preWarm + JP3DEncoder.preWarm / JP3DROIEncoder.preWarm ship
// is justified. Otherwise it's a no-op API and should not ship per
// feedback_no_half_releases.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2K3D

final class V10_27_JP3DEncoderPreWarmProbe: XCTestCase {

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

    /// Phase 0 — measure encoder cold-start. Run in isolation via
    /// `swift test -c release --filter V10_27_JP3DEncoderPreWarmProbe`
    /// to ensure Path A captures genuine cold state (no prior Metal
    /// touch by sibling tests in the same process).
    func testJP3DEncoderColdVsWarmStart() async throws {
        let volume = makeLCGVolume(width: 128, height: 128, depth: 16)
        let encoderConfig = JP3DEncoderConfiguration(
            compressionMode: .losslessHTJ2K)

        // Path A: cold first encode in process.
        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = try await JP3DEncoder(configuration: encoderConfig).encode(volume)
        let coldMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

        // Path B: first encode AFTER the v10.15.0 JP3DDecoder.preWarm
        // (with warmup dispatch which does a real 256x256 encode+decode
        // round-trip). If the encode path's GPU kernels were exercised
        // by the warmup, this will be close to Path C (warm median).
        // If not, the gap is the encoder-specific cold cost.
        await JP3DDecoder.preWarm(includeWarmupDispatch: true)
        let t1 = DispatchTime.now().uptimeNanoseconds
        _ = try await JP3DEncoder(configuration: encoderConfig).encode(volume)
        let afterDecoderPreWarmMs = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1_000_000

        // Path C: warm median (5 trials).
        var subsequentMs: [Double] = []
        for _ in 0..<5 {
            let t = DispatchTime.now().uptimeNanoseconds
            _ = try await JP3DEncoder(configuration: encoderConfig).encode(volume)
            subsequentMs.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000)
        }
        subsequentMs.sort()
        let warmMedian = subsequentMs[subsequentMs.count / 2]

        let saveExistingPreWarm = coldMs - afterDecoderPreWarmMs
        let leftoverEncoderColdCost = afterDecoderPreWarmMs - warmMedian

        print(String(format: """

        V10_27 Phase 0 — JP3D ENCODER cold-start probe (mr_3d_small 128×128×16, lossless HTJ2K)

        Path A — Cold first encode in process                : %7.2f ms
        Path B — First encode after JP3DDecoder.preWarm(true): %7.2f ms
        Path C — Warm-median encode (5 trials)                : %7.2f ms

        Saved by existing JP3DDecoder.preWarm (A - B)         : %+7.2f ms
        Leftover encoder-specific cold cost (B - C)           : %+7.2f ms

        Decision rule:
        - If (B - C) ≥ 3 ms        → J2KEncoder.preWarm + JP3DEncoder.preWarm SHIP justified.
        - If (B - C) < 3 ms        → encoder preWarm is a no-op; do NOT ship per
                                     feedback_no_half_releases.md.
        """,
            coldMs, afterDecoderPreWarmMs, warmMedian,
            saveExistingPreWarm, leftoverEncoderColdCost))
    }

    /// Phase 0 alt — same measurement but using a larger JP3D fixture
    /// (256×256×16) to confirm whether the cold-start cost is fixture-
    /// invariant (as expected for a one-shot Metal init cost) or
    /// dominated by encode wall.
    func testJP3DEncoderColdVsWarmStartLarger() async throws {
        let volume = makeLCGVolume(width: 256, height: 256, depth: 16)
        let encoderConfig = JP3DEncoderConfiguration(
            compressionMode: .losslessHTJ2K)

        let t0 = DispatchTime.now().uptimeNanoseconds
        _ = try await JP3DEncoder(configuration: encoderConfig).encode(volume)
        let coldMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

        await JP3DDecoder.preWarm(includeWarmupDispatch: true)
        let t1 = DispatchTime.now().uptimeNanoseconds
        _ = try await JP3DEncoder(configuration: encoderConfig).encode(volume)
        let afterDecoderPreWarmMs = Double(DispatchTime.now().uptimeNanoseconds - t1) / 1_000_000

        var subsequentMs: [Double] = []
        for _ in 0..<5 {
            let t = DispatchTime.now().uptimeNanoseconds
            _ = try await JP3DEncoder(configuration: encoderConfig).encode(volume)
            subsequentMs.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1_000_000)
        }
        subsequentMs.sort()
        let warmMedian = subsequentMs[subsequentMs.count / 2]

        print(String(format: """

        V10_27 Phase 0 — JP3DEncoder cold-start probe (256×256×16, lossless HTJ2K)

        Path A — Cold first encode in process                 : %7.2f ms
        Path B — First encode after JP3DDecoder.preWarm()     : %7.2f ms
        Path C — Warm-median encode (5 trials)                : %7.2f ms

        Saved by existing JP3DDecoder.preWarm (A - B)         : %+7.2f ms
        Leftover encoder-specific cold cost (B - C)           : %+7.2f ms
        """,
            coldMs, afterDecoderPreWarmMs, warmMedian,
            coldMs - afterDecoderPreWarmMs, afterDecoderPreWarmMs - warmMedian))
    }
}
#endif
