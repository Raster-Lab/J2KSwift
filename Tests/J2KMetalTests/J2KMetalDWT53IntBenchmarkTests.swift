//
// J2KMetalDWT53IntBenchmarkTests.swift
// J2KSwift
//
// IDWT-only micro-benchmark for the bit-exact integer 5/3 GPU path on the
// dimensions of the 10 real DICOMs used in CROSS_CODEC_DICOM_REPORT.md /
// CROSS_CODEC_CPU_VS_GPU_REPORT.md. The end-to-end CPU-vs-GPU benchmark
// shows tiny wall-clock differences because entropy decoding (still CPU)
// dominates total decode time. This isolates the IDWT stage to expose the
// real GPU vs CPU speedup hidden inside `decodeGPU`.
//
// Run with:
//   swift test --filter J2KMetalDWT53IntBenchmarkTests 2>&1 | grep '\[5/3'
//
// Configure release-style timing by building with `-c release` first if
// you want apples-to-apples numbers vs production code.
//

import XCTest
@testable import J2KMetal
@testable import J2KCore

final class J2KMetalDWT53IntBenchmarkTests: XCTestCase {

    private static func deterministic12BitDecomposition(
        width: Int, height: Int, levels: Int, seed: UInt64
    ) -> (ll: [Int32], lh: [[Int32]], hl: [[Int32]], hh: [[Int32]],
          llSizes: [(Int, Int)], parentSizes: [(Int, Int)]) {
        // Build a multi-level decomposition with random Int32 coefficients
        // representative of 12-bit DX-style data after wavelet expansion.
        var state = seed | 1
        func rand() -> Int32 {
            state = state &* 2862933555777941757 &+ 3037000493
            return Int32(truncatingIfNeeded: (Int64(bitPattern: state) >> 32) & 0xFFFF) - 8192
        }

        var levelSizes: [(width: Int, height: Int)] = [(width, height)]
        for _ in 0..<levels {
            let (pw, ph) = levelSizes.last!
            levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))
        }

        let llW = levelSizes[levels].width
        let llH = levelSizes[levels].height
        var ll = [Int32](repeating: 0, count: llW * llH)
        for i in 0..<ll.count { ll[i] = rand() }

        var lh: [[Int32]] = []
        var hl: [[Int32]] = []
        var hh: [[Int32]] = []
        var llSizes: [(Int, Int)] = []
        var parentSizes: [(Int, Int)] = []
        for level in (1...levels).reversed() {
            let parentW = levelSizes[level - 1].width
            let parentH = levelSizes[level - 1].height
            let lW = levelSizes[level].width
            let lH = levelSizes[level].height
            let hW = parentW - lW
            let lhH_ = parentH - lH
            llSizes.append((lW, lH))
            parentSizes.append((parentW, parentH))

            var lhBand = [Int32](repeating: 0, count: lW * lhH_)
            for i in 0..<lhBand.count { lhBand[i] = rand() }
            var hlBand = [Int32](repeating: 0, count: hW * lH)
            for i in 0..<hlBand.count { hlBand[i] = rand() }
            var hhBand = [Int32](repeating: 0, count: hW * lhH_)
            for i in 0..<hhBand.count { hhBand[i] = rand() }

            lh.append(lhBand)
            hl.append(hlBand)
            hh.append(hhBand)
        }

        return (ll, lh, hl, hh, llSizes, parentSizes)
    }

    private func runMultiLevelIDWT(
        dwt: J2KMetalDWT,
        decomposition: (ll: [Int32], lh: [[Int32]], hl: [[Int32]], hh: [[Int32]],
                        llSizes: [(Int, Int)], parentSizes: [(Int, Int)]),
        backend: J2KMetalDWTBackend
    ) async throws -> [Int32] {
        var current = decomposition.ll
        for i in 0..<decomposition.lh.count {
            let (llW, llH) = decomposition.llSizes[i]
            let (parentW, parentH) = decomposition.parentSizes[i]
            let subbands = J2KMetalDWTSubbandsInt32(
                ll: current,
                lh: decomposition.lh[i],
                hl: decomposition.hl[i],
                hh: decomposition.hh[i],
                llWidth: llW, llHeight: llH,
                originalWidth: parentW, originalHeight: parentH
            )
            current = try await dwt.inverse2DInt32(subbands: subbands, backend: backend)
        }
        return current
    }

    private func benchmark(
        label: String, width: Int, height: Int, levels: Int = 5,
        warmup: Int = 2, iterations: Int = 5
    ) async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let decomposition = Self.deterministic12BitDecomposition(
            width: width, height: height, levels: levels, seed: UInt64(width * 31 + height)
        )

        let dwt = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: .reversible53, decompositionLevels: levels, gpuThreshold: 0
        ))
        try await dwt.initialize()

        // Warmup
        for _ in 0..<warmup {
            _ = try await runMultiLevelIDWT(dwt: dwt, decomposition: decomposition, backend: .cpu)
            _ = try await runMultiLevelIDWT(dwt: dwt, decomposition: decomposition, backend: .gpu)
        }

        // Sanity: outputs must be identical (bit-exactness invariant)
        let cpuOutput = try await runMultiLevelIDWT(
            dwt: dwt, decomposition: decomposition, backend: .cpu)
        let gpuOutput = try await runMultiLevelIDWT(
            dwt: dwt, decomposition: decomposition, backend: .gpu)
        XCTAssertEqual(cpuOutput, gpuOutput,
                       "[\(label) \(width)x\(height)] CPU and GPU IDWT must agree byte-for-byte")

        // Timed runs — collect each iteration, print median
        func medianOf(_ block: () async throws -> Void) async rethrows -> Double {
            var samples: [Double] = []
            for _ in 0..<iterations {
                let start = DispatchTime.now()
                try await block()
                let end = DispatchTime.now()
                samples.append(Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0)
            }
            samples.sort()
            return samples[samples.count / 2]
        }

        let cpuMs = try await medianOf {
            _ = try await self.runMultiLevelIDWT(
                dwt: dwt, decomposition: decomposition, backend: .cpu)
        }
        let gpuMs = try await medianOf {
            _ = try await self.runMultiLevelIDWT(
                dwt: dwt, decomposition: decomposition, backend: .gpu)
        }

        let speedup = cpuMs / max(gpuMs, 0.001)
        print("[5/3 IDWT \(label) \(width)x\(height) L=\(levels)] " +
              "CPU=\(String(format: "%6.2f", cpuMs))ms  " +
              "GPU=\(String(format: "%6.2f", gpuMs))ms  " +
              "speedup=\(String(format: "%.2f", speedup))x")
    }

    // MARK: - Same 10 dimensions used in CROSS_CODEC_CPU_VS_GPU_REPORT.md

    func testBench53Int_CT_512x512() async throws {
        try await benchmark(label: "ct_s001", width: 512, height: 512)
    }

    func testBench53Int_DX_2544x3056() async throws {
        try await benchmark(label: "dx_s001", width: 2544, height: 3056)
    }

    func testBench53Int_DX_2800x2288() async throws {
        try await benchmark(label: "dx_s002", width: 2800, height: 2288)
    }

    func testBench53Int_MG_3520x4784() async throws {
        try await benchmark(label: "mg_s001", width: 3520, height: 4784)
    }

    func testBench53Int_MG_3521x4784() async throws {
        try await benchmark(label: "mg_s002", width: 3521, height: 4784)
    }

    func testBench53Int_MR_886x886() async throws {
        try await benchmark(label: "mr_s001", width: 886, height: 886)
    }

    func testBench53Int_MR_180x180() async throws {
        // Below the 256×256 GPU dispatch threshold used in the pipeline. Useful
        // sanity: speedup will be near 1× since both paths run on CPU.
        try await benchmark(label: "mr_s002", width: 180, height: 180)
    }

    func testBench53Int_PX_2459x1316() async throws {
        try await benchmark(label: "px_s001", width: 2459, height: 1316)
    }

    func testBench53Int_XA_1024x1024() async throws {
        try await benchmark(label: "xa_s001", width: 1024, height: 1024)
    }
}
