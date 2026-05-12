// v9.7 — measure cold-shot DX wall (no warmup, no prior encodes).
// The v9.6 process-default cache only helps subsequent encodes. The
// very first encode of any (bitDepth, components, bpp) shape still
// pays the 3-pass qstep-search cost (~112 ms on M4 DX).
//
// This test isolates the cold-shot wall by:
//   1. Disabling the process-default cache via env var (each
//      invocation is fully cold).
//   2. Measuring exactly ONE encode wall + per-stage breakdown.
//
// The companion test `testColdShotWithProcessCacheSeed` measures
// after the v9.7 seed-the-shared-cache fix lands. The two-test split
// lets us quantify how much of the cold-shot gap the seed closes
// without relying on test ordering for state.

import XCTest
import Darwin
@testable import J2KCodec
import J2KCore

final class V97ColdShotTests: XCTestCase {

    private func makeImage(width: Int, height: Int) -> J2KImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        var s: UInt64 = 0xfeed_face
        for i in 0..<(width * height) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let v = Int(s >> 48) & 0xFFFF
            bytes[i * 2]     = UInt8((v >> 8) & 0xFF)
            bytes[i * 2 + 1] = UInt8(v & 0xFF)
        }
        return J2KImage(
            width: width, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: width, height: height,
                data: Data(bytes), sampleByteOrder: .bigEndian)])
    }

    private func htConfig(bpp: Double) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        return cfg
    }

    /// Cold-shot DX wall with the v9.6 process-default cache active.
    /// First encode of a given (bitDepth, components, bpp) shape on a
    /// fresh process: the cache is either empty (pre-v9.7) or pre-
    /// seeded (post-v9.7), and the result tells us whether the first
    /// encode hit a 3-pass search or a 1-pass cache-seed match.
    func testColdShotDX_2bpp_FirstEncode() async throws {
        // Force a fresh per-encoder cache so we measure the cold path
        // unaffected by other tests in the same process. This mirrors
        // a single-shot CLI invocation.
        var cfg = htConfig(bpp: 2.0)
        cfg.qstepCache = J2KQstepCache()  // empty per-call cache
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let img = makeImage(width: 2800, height: 2288)

        J2KEncodeTimings.reset()
        let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        _ = try await encoder.encode(img)
        let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let wallMs = Double(t1 - t0) / 1_000_000.0
        let s = J2KEncodeTimings.snapshot()
        print("V97_COLD_DX wall_ms=\(String(format: "%.2f", wallMs)) preproc=\(String(format: "%.2f", s.preprocessing * 1000)) dwt=\(String(format: "%.2f", s.waveletTransform * 1000)) entropy=\(String(format: "%.2f", s.entropyCoding * 1000)) codestream=\(String(format: "%.2f", s.codestreamGeneration * 1000)) stages_total=\(String(format: "%.2f", s.total * 1000))")
    }

    /// Cold-shot with the v9.7 process-default seed — relies on the
    /// `J2KQstepCache.shared` being pre-populated with empirical 16-bit
    /// medical priors at startup. Expected: ~30 ms (1-pass) if the
    /// seed is accurate, vs ~112 ms (3-pass) without the seed.
    func testColdShotDX_2bpp_ProcessSeed() async throws {
        // Use the process-default cache (do NOT supply an explicit one).
        let cfg = htConfig(bpp: 2.0)
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let img = makeImage(width: 2800, height: 2288)

        J2KEncodeTimings.reset()
        let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        _ = try await encoder.encode(img)
        let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let wallMs = Double(t1 - t0) / 1_000_000.0
        let s = J2KEncodeTimings.snapshot()
        print("V97_SEED_DX wall_ms=\(String(format: "%.2f", wallMs)) preproc=\(String(format: "%.2f", s.preprocessing * 1000)) dwt=\(String(format: "%.2f", s.waveletTransform * 1000)) entropy=\(String(format: "%.2f", s.entropyCoding * 1000)) codestream=\(String(format: "%.2f", s.codestreamGeneration * 1000)) stages_total=\(String(format: "%.2f", s.total * 1000))")
    }
}
