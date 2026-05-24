//
// V10_20_GPUvsCPUIDWTDiagnostic.swift
// J2KSwift
//
// v10.20-research Phase 3d diagnostic — does
// `J2KMetalDWT.inverse2DInt32MultiLevelFused` (GPU multi-level
// chain) produce byte-identical output to per-level
// `inverse2DInt32(backend: .cpu)` (CPU per-level loop) on real
// codestream coefficient data?
//
// Phase 3a parity tests proved batched GPU ≡ serial GPU on
// synthetic LCG-noise subbands. Phase 3b uncovered byte divergence
// between the bridge SPI's batched path (GPU multi-level) and
// serial path (CPU per-level by default) on real codestream
// coefficients. This test closes the question of WHICH side
// diverges — GPU vs GPU (my code) or GPU vs CPU (pre-existing).

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V10_20_GPUvsCPUIDWTDiagnostic: XCTestCase {

    private func makeLCGImage(
        width: Int, height: Int, seed: UInt64
    ) -> J2KImage {
        let voxelCount = width * height
        let maxVal = 65535
        var data = Data(count: voxelCount * 2)
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
            index: 0, bitDepth: 16, signed: false,
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

    /// Diagnostic: GPU multi-level fused vs CPU per-level loop on real
    /// codestream data. If divergent, the v10.20 Phase 3d block is a
    /// pre-existing J2KSwift GPU vs CPU iDWT divergence (not the
    /// Phase 3a orchestrator's fault). If equal, my batched
    /// orchestrator has a bug not caught by synthetic tests.
    func testGPUMultiLevelFusedVsCPUPerLevel_256x256() async throws {
        // Get real coefficients via the Phase 1 bridge SPI.
        let image = makeLCGImage(width: 256, height: 256, seed: 0xCAFE)
        let codestream = try await losslessHTEncoder().encode(image)
        let coefs = try await J2KDecoder()._jp3dDecodeToCoefficients(codestream)
        let subbands = coefs._internal.dequantizedSubbands
            .filter { $0.componentIndex == 0 }

        // Build per-level SubbandsInt32 chain (innermost first).
        // Mirrors what applyInverseWaveletTransform does at line ~4738+.
        let levels = 5
        let compW = 256, compH = 256
        var levelSizes: [(width: Int, height: Int)] = []
        for d in 0...levels {
            let denom = 1 << d
            levelSizes.append(((compW + denom - 1) / denom,
                               (compH + denom - 1) / denom))
        }

        func padInt32(_ src: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Int32] {
            if srcW == dstW && srcH == dstH { return src }
            var dst = [Int32](repeating: 0, count: dstW * dstH)
            let copyW = min(srcW, dstW), copyH = min(srcH, dstH)
            for y in 0..<copyH {
                for x in 0..<copyW {
                    dst[y * dstW + x] = src[y * srcW + x]
                }
            }
            return dst
        }
        func get(_ level: Int, _ band: J2KSubband, _ dstW: Int, _ dstH: Int) -> [Int32] {
            if let sb = subbands.first(where: { $0.level == level && $0.subband == band }) {
                return padInt32(sb.coefficients, srcW: sb.width, srcH: sb.height,
                                 dstW: dstW, dstH: dstH)
            }
            return [Int32](repeating: 0, count: dstW * dstH)
        }

        let llDims = levelSizes[levels]
        let initialLL: [Int32]
        if let ll = subbands.first(where: { $0.subband == .ll && $0.level == levels }) {
            initialLL = padInt32(ll.coefficients, srcW: ll.width, srcH: ll.height,
                                  dstW: llDims.width, dstH: llDims.height)
        } else {
            initialLL = [Int32](repeating: 0, count: llDims.width * llDims.height)
        }

        var chain: [J2KMetalDWTSubbandsInt32] = []
        for level in (1...levels).reversed() {
            let parentW = levelSizes[level - 1].width
            let parentH = levelSizes[level - 1].height
            let llW = levelSizes[level].width
            let llH = levelSizes[level].height
            let hlW = parentW - llW
            let lhH = parentH - llH

            let llForLevel = chain.isEmpty ? initialLL : []
            chain.append(J2KMetalDWTSubbandsInt32(
                ll: llForLevel,
                lh: get(level, .lh, llW, lhH),
                hl: get(level, .hl, hlW, llH),
                hh: get(level, .hh, hlW, lhH),
                llWidth: llW, llHeight: llH,
                originalWidth: parentW, originalHeight: parentH,
                tileOriginX: 0, tileOriginY: 0))
        }

        let dwt = J2KMetalDWT()

        // Path A: GPU multi-level fused (one cb, GPU-resident chain).
        let gpuFused = try await dwt.inverse2DInt32MultiLevelFused(
            subbandsPerLevel: chain)

        // Path B: CPU per-level loop (one inverse2DInt32 per level,
        // backend: .cpu — what applyInverseWaveletTransform's per-level
        // path does for small dims via backend: .auto).
        var currentLL = initialLL
        for (idx, level) in (1...levels).reversed().enumerated() {
            let parentW = levelSizes[level - 1].width
            let parentH = levelSizes[level - 1].height
            let llW = levelSizes[level].width
            let llH = levelSizes[level].height
            let hlW = parentW - llW
            let lhH = parentH - llH

            let sub = J2KMetalDWTSubbandsInt32(
                ll: currentLL,
                lh: get(level, .lh, llW, lhH),
                hl: get(level, .hl, hlW, llH),
                hh: get(level, .hh, hlW, lhH),
                llWidth: llW, llHeight: llH,
                originalWidth: parentW, originalHeight: parentH,
                tileOriginX: 0, tileOriginY: 0)
            currentLL = try await dwt.inverse2DInt32(subbands: sub, backend: .cpu)
            _ = idx
        }
        let cpuPerLevel = currentLL

        // Compare
        if gpuFused == cpuPerLevel {
            print("\nV10_20 diagnostic: GPU-multi-level-fused ≡ CPU-per-level (BIT-EXACT). "
                  + "Phase 3a orchestrator has a bug not caught by synthetic tests.")
        } else {
            let mismatches = zip(gpuFused, cpuPerLevel).enumerated()
                .filter { $0.element.0 != $0.element.1 }
            let first10 = mismatches.prefix(10)
            print("\nV10_20 diagnostic: GPU-multi-level-fused ≠ CPU-per-level. "
                  + "Pre-existing J2KSwift GPU-vs-CPU iDWT divergence on real data.")
            print("  Total length: \(gpuFused.count); mismatches: \(mismatches.count)")
            print("  First 10 mismatches (idx, GPU, CPU):")
            for (idx, (g, c)) in first10 {
                print(String(format: "    [%6d]  GPU=%6d  CPU=%6d  Δ=%+d", idx, g, c, g - c))
            }
        }

        // Don't fail — this is a diagnostic measurement.
    }

    /// Diagnostic 2: my batched orchestrator vs serial GPU multi-level
    /// fused on REAL codestream data (not synthetic LCG). Phase 3a
    /// parity tests used LCG-noise subbands with limited magnitude
    /// range — this test uses encoder output coefficients which have
    /// the full lossless dynamic range.
    func testBatchedOrchestratorVsSerialGPU_realCoefs_256x256() async throws {
        let image = makeLCGImage(width: 256, height: 256, seed: 0xCAFE)
        let codestream = try await losslessHTEncoder().encode(image)
        let coefs = try await J2KDecoder()._jp3dDecodeToCoefficients(codestream)
        let subbands = coefs._internal.dequantizedSubbands
            .filter { $0.componentIndex == 0 }

        let levels = 5
        let compW = 256, compH = 256
        var levelSizes: [(width: Int, height: Int)] = []
        for d in 0...levels {
            let denom = 1 << d
            levelSizes.append(((compW + denom - 1) / denom,
                               (compH + denom - 1) / denom))
        }

        func padInt32(_ src: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Int32] {
            if srcW == dstW && srcH == dstH { return src }
            var dst = [Int32](repeating: 0, count: dstW * dstH)
            let copyW = min(srcW, dstW), copyH = min(srcH, dstH)
            for y in 0..<copyH {
                for x in 0..<copyW {
                    dst[y * dstW + x] = src[y * srcW + x]
                }
            }
            return dst
        }
        func get(_ level: Int, _ band: J2KSubband, _ dstW: Int, _ dstH: Int) -> [Int32] {
            if let sb = subbands.first(where: { $0.level == level && $0.subband == band }) {
                return padInt32(sb.coefficients, srcW: sb.width, srcH: sb.height,
                                 dstW: dstW, dstH: dstH)
            }
            return [Int32](repeating: 0, count: dstW * dstH)
        }

        let llDims = levelSizes[levels]
        let initialLL: [Int32]
        if let ll = subbands.first(where: { $0.subband == .ll && $0.level == levels }) {
            initialLL = padInt32(ll.coefficients, srcW: ll.width, srcH: ll.height,
                                  dstW: llDims.width, dstH: llDims.height)
        } else {
            initialLL = [Int32](repeating: 0, count: llDims.width * llDims.height)
        }

        var chain: [J2KMetalDWTSubbandsInt32] = []
        for level in (1...levels).reversed() {
            let parentW = levelSizes[level - 1].width
            let parentH = levelSizes[level - 1].height
            let llW = levelSizes[level].width
            let llH = levelSizes[level].height
            let hlW = parentW - llW
            let lhH = parentH - llH

            let llForLevel = chain.isEmpty ? initialLL : []
            chain.append(J2KMetalDWTSubbandsInt32(
                ll: llForLevel,
                lh: get(level, .lh, llW, lhH),
                hl: get(level, .hl, hlW, llH),
                hh: get(level, .hh, hlW, lhH),
                llWidth: llW, llHeight: llH,
                originalWidth: parentW, originalHeight: parentH,
                tileOriginX: 0, tileOriginY: 0))
        }

        let dwt = J2KMetalDWT()
        let serialGPU = try await dwt.inverse2DInt32MultiLevelFused(
            subbandsPerLevel: chain)
        let batchedOut = try await dwt.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: [chain])

        XCTAssertEqual(batchedOut.count, 1)
        if serialGPU == batchedOut[0] {
            print("\nV10_20 diag 2: batched orchestrator ≡ serial GPU on REAL coefs (no bug visible at 256×256×5L).")
        } else {
            let mismatches = zip(serialGPU, batchedOut[0]).enumerated()
                .filter { $0.element.0 != $0.element.1 }
            print("\nV10_20 diag 2: batched orchestrator ≠ serial GPU on REAL coefs.")
            print("  Total: \(serialGPU.count); mismatches: \(mismatches.count)")
            print("  First 10 (idx, serial, batched, Δ):")
            for (idx, (s, b)) in mismatches.prefix(10) {
                print(String(format: "    [%6d]  serial=%6d  batched=%6d  Δ=%+d",
                             idx, s, b, b - s))
            }
            XCTFail("Batched orchestrator diverges from serial GPU on real codestream coefficients — root cause of Phase 3b parity failures.")
        }
    }
}
