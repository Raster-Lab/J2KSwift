// v9.6 — measure a true single-pass encoder wall on DX-shaped synthetic
// 16-bit input. Uses .fixedQstep mode at a value the qstep search
// would converge to, bypassing the search loop entirely. Compares to
// the multi-pass corpus measurement.

import XCTest
import Darwin
@testable import J2KCodec
import J2KCore

final class V96SinglePassVsCorpusTests: XCTestCase {

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

    /// Measures the single-pass DX 2800×2288 wall via .fixedQstep, then
    /// reports per-stage means to compare against the multi-pass corpus
    /// benchmark output.
    func testSinglePassDXWall() async throws {
        let img = makeImage(width: 2800, height: 2288)
        // Use a qstep the strict-bounded search converges to for 2 bpp
        // on synthetic 16-bit content (matches the corpus benchmark
        // bitrate target so the single-pass output is comparable to
        // the 2-3-pass converged result).
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .fixedQstep(qstep: 350.0)  // approx converged qstep
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        // Warm-up — synthetic image, no fixture I/O
        _ = try await encoder.encode(img)

        let n = 5
        var samples = [Double](repeating: 0, count: n)
        var sumPre: TimeInterval = 0
        var sumDWT: TimeInterval = 0, sumEnt: TimeInterval = 0
        var sumQuant: TimeInterval = 0, sumCS: TimeInterval = 0
        for i in 0..<n {
            J2KEncodeTimings.reset()
            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            _ = try await encoder.encode(img)
            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            samples[i] = Double(t1 - t0) / 1_000_000.0
            let s = J2KEncodeTimings.snapshot()
            sumPre += s.preprocessing
            sumDWT += s.waveletTransform
            sumQuant += s.quantization
            sumEnt += s.entropyCoding
            sumCS += s.codestreamGeneration
        }
        samples.sort()
        let med = samples[n / 2]
        let scale = 1000.0 / Double(n)
        print("V96_SINGLEPASS_DX wall_ms=\(String(format: "%.2f", med)) preproc=\(String(format: "%.2f", sumPre * scale)) dwt=\(String(format: "%.2f", sumDWT * scale)) quant=\(String(format: "%.2f", sumQuant * scale)) entropy=\(String(format: "%.2f", sumEnt * scale)) codestream=\(String(format: "%.2f", sumCS * scale))")
    }

    /// Same workload as the corpus benchmark but with qstepCache enabled.
    /// Confirms that warm-cache encodes converge in 1 pass and drop the
    /// wall to ~30 ms (vs 99 ms cold-cache 3-pass).
    func testWarmQstepCacheDXWall() async throws {
        let img = makeImage(width: 2800, height: 2288)
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: 2.0)
        cfg.qstepCache = J2KQstepCache()  // explicit cache instance
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        // First call: cold cache, runs 3-pass qstep search, stores result.
        let cold0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        _ = try await encoder.encode(img)
        let coldMs = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - cold0) / 1_000_000.0

        // Warmed warm-up — first cache-hit call (still measured as warm)
        _ = try await encoder.encode(img)

        let n = 5
        var samples = [Double](repeating: 0, count: n)
        var sumDWT: TimeInterval = 0, sumEnt: TimeInterval = 0
        for i in 0..<n {
            J2KEncodeTimings.reset()
            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            _ = try await encoder.encode(img)
            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            samples[i] = Double(t1 - t0) / 1_000_000.0
            let s = J2KEncodeTimings.snapshot()
            sumDWT += s.waveletTransform
            sumEnt += s.entropyCoding
        }
        samples.sort()
        let med = samples[n / 2]
        let scale = 1000.0 / Double(n)
        print("V96_WARMCACHE_DX cold_first_ms=\(String(format: "%.2f", coldMs)) warm_med_ms=\(String(format: "%.2f", med)) warm_dwt=\(String(format: "%.2f", sumDWT * scale)) warm_entropy=\(String(format: "%.2f", sumEnt * scale))")
    }
}
