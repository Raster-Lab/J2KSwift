// J2KGPULossy97PerformanceTests.swift
// v5.26.0 — Float scatter+dequant kernel + GPU-resident dispatch
// for 9/7 lossy. `decodeWithGPUHT` warm-session speedup goes from
// ~1.0× to ~1.85× by routing 9/7 lossy through the same
// `decodeBatchGPUResident` + scatter+IDWT fused path that 5/3
// lossless has been using since v5.8.
//
// History: v5.20.0 caught GPU 9/7 IDWT correctness bug; v5.21.0
// fixed it; v5.22.0 locked in cross-module convention; v5.23.0
// measured end-to-end; v5.24.0 split into stages + decodeGPU
// session API; v5.25.0 added Float multi-level fused IDWT (closed
// per-level readback). v5.26.0 closes the remaining levers for
// `decodeWithGPUHT` 9/7 lossy: GPU-resident codeblock buffer (no
// readback), Float scatter+dequant kernel, fused-from-codeblocks
// IDWT (no per-level CPU upload of LH/HL/HH).
//
// Three-way warm-session result (release, M2, 1024×1024 16-bit
// lossy 9/7 @ 2 bpp, n=5 medians, post-v5.26.0; runs 2-4 of 4):
//
//   path                    end-to-end   speedup
//   CPU       (decode)         ~25.7 ms  1.00×  baseline
//   decodeGPU (CPU HT + GPU IDWT)         ~9.8 ms   2.5–3.1×  ← winner
//   decodeWithGPUHT (GPU HT+IDWT, fused)  ~14.0 ms  1.81–1.86× ← v5.26.0 win
//
// Per-stage means (typical run on warm session post-v5.26.0):
//
//   stage                    CPU   gpuIDWT  GPU-HT
//   entropyDecoding          1.3   1.3       7.5
//     ├─ gpuHTDispatch       0.0   0.0       7.1  ← v5.26.0: was 15ms+
//     └─ regroup (CPU)       1.3   1.3       0.4
//   inverseWaveletTransform  22.7  7.0       5.0  ← v5.26.0: was ~10 ms
//
// What changed in v5.26.0:
//   1. `applyEntropyDecoding`'s fused-batch gate dropped
//      `!isIrreversibleFilter`. 9/7 lossy now also routes through
//      `decodeBatchGPUResident` instead of the fallback `decodeBatch`
//      (which paid a full host readback). Saves ~8 ms on
//      `gpuHTDispatch` for 9/7 lossy on this workload.
//   2. New Float scatter+dequant Metal kernel
//      (`j2k_subband_scatter_float_dequant`). Reads Int32 codeblock
//      output, applies `(coeff ± 0.5) * stepSize` (HTJ2K conformant
//      cleanup-only dequant formula), writes Float to per-subband
//      2D layout. `inverse2DFullFusedFromCodeblocks` Float variant
//      chains scatter + multi-level IDWT in one cb. Saves ~5 ms on
//      `inverseWaveletTransform` for `decodeWithGPUHT` 9/7 lossy.
//
// What's still open:
//   - `decodeGPU` (CPU HT + GPU IDWT) remains the fastest path on
//     this workload because parallelised CPU HT (~1.3 ms) is still
//     cheaper than even the v5.26.0-reduced GPU HT dispatch (~7 ms).
//     `decodeWithGPUHT` overtakes only when the dispatch
//     amortises — likely on much larger images.
//
// Gate semantics: MEASUREMENT gate, not assertion gate. Variance
// across release-mode runs is real (the first run after a metallib
// regen / cold cache shows ~2× higher dispatch). Correctness is
// guarded by the v5.20-v5.22 + v5.26 audit gates.

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
