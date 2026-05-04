// J2KGPULossy97PerformanceTests.swift
// v5.25.0 — Float multi-level fused IDWT lands; 9/7 lossy speedup
// jumps from ~1.4× to ~2.6–3.1× on warm session.
//
// History: v5.20.0 caught the GPU 9/7 IDWT correctness bug;
// v5.21.0 fixed it; v5.22.0 locked in cross-module convention;
// v5.23.0 measured warm-session end-to-end speedup; v5.24.0 split
// the timer into stages and revealed that GPU IDWT was the
// dominant win and the per-level upload/readback was the next
// architectural lever. v5.25.0 closes that lever by adding
// `J2KMetalDWT.inverse2DMultiLevelFused` (Float variant) and
// wiring it into `applyInverseWaveletTransformGPU`'s 9/7 branch.
//
// Three-way warm-session result (release, M2, 1024×1024 16-bit
// lossy 9/7 @ 2 bpp, n=5 medians, post-v5.25.0):
//
//   path                    end-to-end   speedup
//   CPU       (decode)         ~26.6 ms  1.00×  baseline
//   decodeGPU (CPU HT + GPU IDWT)  ~10.0 ms  2.64–3.13×  ← winner
//   decodeWithGPUHT (GPU HT+IDWT)  ~26.5 ms  1.00–1.36×
//
// Per-stage means (typical post-v5.25.0):
//
//   stage                    CPU   gpuIDWT  GPU-HT
//   entropyDecoding          1.5   1.4      15.8
//     ├─ gpuHTDispatch       0.0   0.0      15.3  ← still the regression
//     └─ regroup (CPU)       1.5   1.4       0.4
//   inverseWaveletTransform  23.4  7.4      10.8  ← v5.25.0 win
//
// IDWT delta vs v5.24.0: gpuIDWT path 15.2 → 7.4 ms (50% drop).
// `decodeWithGPUHT` IDWT also benefits (10.6 → ~10 ms-ish, smaller
// effect because the GPU-HT path was already partially fused).
//
// What's still open:
//   1. The 15.3 ms `gpuHTDispatch` overhead remains — this is why
//      `decodeWithGPUHT` is a wash. Reducing per-tile dispatch
//      cost is a separate optimisation track.
//   2. The fused path still uploads LH/HL/HH from CPU per level;
//      a Float scatter kernel from a GPU-resident codeblock buffer
//      would close that too, but only `decodeWithGPUHT` benefits
//      (the entropy stage is what produces the codeblock buffer).
//
// Gate semantics: MEASUREMENT gate, not assertion gate. Variance
// across release-mode runs is real (sub-stage timings move ±20%).
// Correctness is guarded by the v5.20-v5.22 audit gates.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class J2KGPULossy97PerformanceTests: XCTestCase {

    /// Build a synth 16-bit image and encode it once.
    private func makeAndEncode(width: Int, height: Int, bpp: Double) async throws -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        var s: UInt64 = 0xfeed_face
        for i in 0..<(width * height) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let v = Int(s >> 48) & 0xFFFF
            bytes[i * 2]     = UInt8((v >> 8) & 0xFF)
            bytes[i * 2 + 1] = UInt8(v & 0xFF)
        }
        let component = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: width, height: height,
            data: Data(bytes), sampleByteOrder: .bigEndian)
        let image = J2KImage(width: width, height: height, components: [component])
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        return try await J2KEncoder(encodingConfiguration: cfg).encode(image)
    }

    /// Benchmark CPU decode vs GPU-HT decode with shared session.
    /// Reports per-image median time and per-stage breakdown via
    /// `J2KDecodeTimings`.
    func testWarmSessionGPUSpeedupVsCPU() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let width = 1024
        let height = 1024
        let n = 5  // images per timing batch

        // Encode once; reuse the same encoded bytes for both paths.
        let encoded = try await makeAndEncode(width: width, height: height, bpp: 2.0)

        // CPU baseline (no Metal involvement)
        let cpuDecoder = J2KDecoder()
        // Warm CPU caches first
        _ = try await cpuDecoder.decode(encoded)
        var cpuTimes: [TimeInterval] = []
        var cpuStageTotals = StageTotals()
        for _ in 0..<n {
            J2KDecodeTimings.reset()
            let t0 = Date()
            _ = try await cpuDecoder.decode(encoded)
            cpuTimes.append(Date().timeIntervalSince(t0))
            cpuStageTotals.add(J2KDecodeTimings.snapshot())
        }

        // GPU-IDWT-only path (CPU HT + GPU IDWT, no GPU HT dispatch)
        let session = J2KMetalSession()
        let gpuIDWTDecoder = J2KDecoder()
        _ = try await gpuIDWTDecoder.decodeGPU(encoded, session: session)
        var gpuIDWTTimes: [TimeInterval] = []
        var gpuIDWTStageTotals = StageTotals()
        for _ in 0..<n {
            J2KDecodeTimings.reset()
            let t0 = Date()
            _ = try await gpuIDWTDecoder.decodeGPU(encoded, session: session)
            gpuIDWTTimes.append(Date().timeIntervalSince(t0))
            gpuIDWTStageTotals.add(J2KDecodeTimings.snapshot())
        }

        // GPU-HT path (CPU HT entropy + CPU regroup → GPU IDWT)
        let gpuDecoder = J2KDecoder()
        // Warm-up: first call pays Metal startup cost
        _ = try await gpuDecoder.decodeWithGPUHT(encoded, session: session)
        var gpuTimes: [TimeInterval] = []
        var gpuStageTotals = StageTotals()
        for _ in 0..<n {
            J2KDecodeTimings.reset()
            let t0 = Date()
            _ = try await gpuDecoder.decodeWithGPUHT(encoded, session: session)
            gpuTimes.append(Date().timeIntervalSince(t0))
            gpuStageTotals.add(J2KDecodeTimings.snapshot())
        }

        let cpuMedian = cpuTimes.sorted()[n / 2] * 1000
        let gpuIDWTMedian = gpuIDWTTimes.sorted()[n / 2] * 1000
        let gpuMedian = gpuTimes.sorted()[n / 2] * 1000

        print("=== GPU 9/7 lossy decode warm-session benchmark ===")
        print("Image: \(width)×\(height) 16-bit lossy 9/7 @ 2 bpp, n=\(n)")
        print("")
        print("End-to-end medians:")
        print("  CPU            (decode):                      \(fmt(cpuMedian)) ms (\(String(format: "%.2fx", 1.0)) baseline)")
        print("  GPU IDWT only  (decodeGPU, CPU HT + GPU IDWT): \(fmt(gpuIDWTMedian)) ms (\(String(format: "%.2fx", cpuMedian / gpuIDWTMedian)))")
        print("  GPU-HT         (decodeWithGPUHT, GPU HT+IDWT): \(fmt(gpuMedian)) ms (\(String(format: "%.2fx", cpuMedian / gpuMedian)))")
        print("")
        print("Sample times (ms):")
        print("  CPU:           \(cpuTimes.map { fmt($0 * 1000) }.joined(separator: " "))")
        print("  GPU IDWT only: \(gpuIDWTTimes.map { fmt($0 * 1000) }.joined(separator: " "))")
        print("  GPU-HT:        \(gpuTimes.map { fmt($0 * 1000) }.joined(separator: " "))")
        print("")
        print("Per-stage means (\(n) samples each, ms):")
        print(stageTable(cpu: cpuStageTotals.mean(over: n),
                        gpuIDWT: gpuIDWTStageTotals.mean(over: n),
                        gpu: gpuStageTotals.mean(over: n)))

        // Measurement gate (not assertion gate). See header comment.
        XCTAssertGreaterThan(gpuMedian, 0)
        XCTAssertGreaterThan(cpuMedian, 0)
    }

    private func fmt(_ ms: Double) -> String { String(format: "%.1f", ms) }

    /// Sums a sequence of `J2KDecodeTimings.Snapshot` values and
    /// produces per-stage means in milliseconds.
    private struct StageTotals {
        var extractTileData: TimeInterval = 0
        var entropyDecoding: TimeInterval = 0
        var gpuHTDispatch: TimeInterval = 0
        var dequantization: TimeInterval = 0
        var inverseWaveletTransform: TimeInterval = 0
        var inverseColorTransform: TimeInterval = 0
        var dcLevelUnshift: TimeInterval = 0
        var reconstructImage: TimeInterval = 0
        mutating func add(_ s: J2KDecodeTimings.Snapshot) {
            extractTileData += s.extractTileData
            entropyDecoding += s.entropyDecoding
            gpuHTDispatch += s.gpuHTDispatch
            dequantization += s.dequantization
            inverseWaveletTransform += s.inverseWaveletTransform
            inverseColorTransform += s.inverseColorTransform
            dcLevelUnshift += s.dcLevelUnshift
            reconstructImage += s.reconstructImage
        }
        struct Means {
            let extractTileData, entropyDecoding: Double
            let gpuHTDispatch, entropyRegroup: Double
            let dequantization: Double
            let inverseWaveletTransform, inverseColorTransform: Double
            let dcLevelUnshift, reconstructImage: Double
            var total: Double {
                extractTileData + entropyDecoding + dequantization
                    + inverseWaveletTransform + inverseColorTransform
                    + dcLevelUnshift + reconstructImage
            }
        }
        func mean(over n: Int) -> Means {
            let scale = 1000.0 / Double(n)  // seconds → ms then divide by n
            let entropy = entropyDecoding * scale
            let dispatch = gpuHTDispatch * scale
            return Means(
                extractTileData: extractTileData * scale,
                entropyDecoding: entropy,
                gpuHTDispatch: dispatch,
                entropyRegroup: max(0, entropy - dispatch),
                dequantization: dequantization * scale,
                inverseWaveletTransform: inverseWaveletTransform * scale,
                inverseColorTransform: inverseColorTransform * scale,
                dcLevelUnshift: dcLevelUnshift * scale,
                reconstructImage: reconstructImage * scale)
        }
    }

    private func stageTable(cpu: StageTotals.Means,
                            gpuIDWT: StageTotals.Means,
                            gpu: StageTotals.Means) -> String {
        let pad = { (s: String, w: Int) in s.padding(toLength: w, withPad: " ", startingAt: 0) }
        let rj  = { (s: String, w: Int) in String(repeating: " ", count: max(0, w - s.count)) + s }
        var rows: [String] = []
        rows.append("\(pad("Stage", 26))  \(rj("CPU", 8))  \(rj("gpuIDWT", 8))  \(rj("GPU-HT", 8))")
        rows.append("\(pad("─────", 26))  \(rj("───", 8))  \(rj("───────", 8))  \(rj("──────", 8))")
        func row(_ name: String, _ c: Double, _ gi: Double, _ g: Double) -> String {
            "\(pad(name, 26))  \(rj(fmt(c), 8))  \(rj(fmt(gi), 8))  \(rj(fmt(g), 8))"
        }
        rows.append(row("extractTileData",         cpu.extractTileData,         gpuIDWT.extractTileData,         gpu.extractTileData))
        rows.append(row("entropyDecoding",         cpu.entropyDecoding,         gpuIDWT.entropyDecoding,         gpu.entropyDecoding))
        rows.append(row("  ├─ gpuHTDispatch",      cpu.gpuHTDispatch,           gpuIDWT.gpuHTDispatch,           gpu.gpuHTDispatch))
        rows.append(row("  └─ regroup (CPU)",      cpu.entropyRegroup,          gpuIDWT.entropyRegroup,          gpu.entropyRegroup))
        rows.append(row("dequantization",          cpu.dequantization,          gpuIDWT.dequantization,          gpu.dequantization))
        rows.append(row("inverseWaveletTransform", cpu.inverseWaveletTransform, gpuIDWT.inverseWaveletTransform, gpu.inverseWaveletTransform))
        rows.append(row("inverseColorTransform",   cpu.inverseColorTransform,   gpuIDWT.inverseColorTransform,   gpu.inverseColorTransform))
        rows.append(row("dcLevelUnshift",          cpu.dcLevelUnshift,          gpuIDWT.dcLevelUnshift,          gpu.dcLevelUnshift))
        rows.append(row("reconstructImage",        cpu.reconstructImage,        gpuIDWT.reconstructImage,        gpu.reconstructImage))
        rows.append("\(pad("─────", 26))  \(rj("───", 8))  \(rj("───────", 8))  \(rj("──────", 8))")
        rows.append(row("instrumented total",      cpu.total, gpuIDWT.total, gpu.total))
        return rows.joined(separator: "\n")
    }
}
