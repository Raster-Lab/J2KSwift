// MultiTileGPUHTPostEntropyDriftTests.swift
//
// v7.1.0 H1.1 — Defect A post-entropy probe.
//
// H1.0 (#334) proved per-block GPU HT entropy output is bit-exact
// to CPU in every multi-tile per-tile context. The 32768 pixel
// diff observed in production multi-tile decode (E1.2 measurement)
// must originate downstream of per-block coefficients.
//
// This test calls `applyEntropyDecoding` directly with
// `isGPUPath: true` vs `isGPUPath: false` on the same DX failing
// tile, and compares the resulting `[SubbandInfo]` outputs per
// (component, level, subband). The divergence point identifies
// where the GPU path produces different downstream data despite
// per-block GPU vs CPU coefficients being identical.
//
// Hypotheses (from H1.0 #334's investigation doc):
//   1. Regroup mis-uses gpuPreDecoded[i] (per-tile assembly bug)
//   2. gpuBatch.codeblockBuffer pool side-effect on regroup state
//   3. isGPUPath=true triggers a code-path branch elsewhere

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MultiTileGPUHTPostEntropyDriftTests: XCTestCase {

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 {
                while i < raw.count, raw[i] != 0x0A { i += 1 }
                continue
            }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    /// Probe — call applyEntropyDecoding with isGPUPath: true vs
    /// isGPUPath: false on the failing DX tile and diff the
    /// resulting [SubbandInfo] arrays.
    func testDefectA_PostEntropyDriftOnFailingDXTile() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }

        // Encode DX multi-tile (2x2 — the historically failing case from E1.2).
        let cfg = htConfig()
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: image.width, imageHeight: image.height,
            decompositionLevels: 5, mode: .tiles2x2)
        XCTAssertTrue(layout.isMultiTile, "DX 2x2 must be multi-tile")
        let result = try await J2KMultiTileEncoder.encode(
            image: image, layout: layout, configuration: cfg)
        let codestream = result.codestream

        let pipeline = DecoderPipeline()
        let (metadata, tiles) = try pipeline.parseCodestream(codestream)
        XCTAssertEqual(tiles.count, 4, "DX 2x2 expected 4 tiles")

        // Force the GPU HT entropy gate flag; save + restore.
        let prevGate = DecoderPipeline._gpuHTEntropyEnabled
        defer { DecoderPipeline._gpuHTEntropyEnabled = prevGate }
        DecoderPipeline._gpuHTEntropyEnabled = true

        let session = J2KMetalSession()
        try await session.preWarm()

        // Run the probe for tile 1 (origin (1400, 0)) — historically
        // the smallest failing case from E1.2.
        let tileIndex = 1
        let (tileX, tileY, tileW, tileH) = metadata.tileDimensions(tileIndex: tileIndex)
        var tileMeta = metadata
        tileMeta.width = tileW
        tileMeta.height = tileH
        tileMeta.tileSize = (width: tileW, height: tileH)

        let codeBlocks = try pipeline.extractTileData(
            tiles[tileIndex].tileData, metadata: tileMeta,
            tileOriginX: tileX, tileOriginY: tileY)
        print("=== Probe: tile \(tileIndex) origin (\(tileX), \(tileY)) ===")
        print("  codeblock count: \(codeBlocks.count)")

        // Construct two pipelines with metalSession plumbed (matches
        // production warm-session decoder flow). Only difference:
        // isGPUPath argument when calling applyEntropyDecoding below.
        var pipeGPU = DecoderPipeline()
        pipeGPU.metalSession = session
        var pipeCPU = DecoderPipeline()
        pipeCPU.metalSession = session

        // Call applyEntropyDecoding both ways.
        let (subbandsCPU, _) = try await pipeCPU.applyEntropyDecoding(
            codeBlocks, metadata: tileMeta, isGPUPath: false)
        let (subbandsGPU, gpuBatchGPU) = try await pipeGPU.applyEntropyDecoding(
            codeBlocks, metadata: tileMeta, isGPUPath: true)
        print("  CPU path subbands: \(subbandsCPU.count)")
        print("  GPU path subbands: \(subbandsGPU.count); gpuBatch: \(gpuBatchGPU != nil)")

        // Sort both arrays by (componentIndex, level, subband.rawValue) for
        // apples-to-apples comparison — the regroup may emit them in
        // different order between paths.
        let sortKey: (DecoderPipeline.SubbandInfo) -> String = {
            "\($0.componentIndex)_\($0.level)_\($0.subband.rawValue)"
        }
        let cpuSorted = subbandsCPU.sorted { sortKey($0) < sortKey($1) }
        let gpuSorted = subbandsGPU.sorted { sortKey($0) < sortKey($1) }

        XCTAssertEqual(cpuSorted.count, gpuSorted.count,
            "subband count mismatch: CPU=\(cpuSorted.count), GPU=\(gpuSorted.count)")

        struct Drift {
            let key: String
            let dims: String
            let coeffMismatchCount: Int
            let maxAbsDiff: Int32
            let firstMismatchIndex: Int
            let cpuFirstMismatchValue: Int32
            let gpuFirstMismatchValue: Int32
        }
        var drifts: [Drift] = []

        for (cpu, gpu) in zip(cpuSorted, gpuSorted) {
            let cpuKey = sortKey(cpu)
            let gpuKey = sortKey(gpu)
            XCTAssertEqual(cpuKey, gpuKey, "subband ordering mismatch")
            XCTAssertEqual(cpu.width, gpu.width, "[\(cpuKey)] width mismatch")
            XCTAssertEqual(cpu.height, gpu.height, "[\(cpuKey)] height mismatch")
            XCTAssertEqual(cpu.coefficients.count, gpu.coefficients.count,
                "[\(cpuKey)] coeff count mismatch")

            var mismatch = 0
            var maxAbsDiff: Int32 = 0
            var firstMismatch = -1
            var cpuFirstVal: Int32 = 0
            var gpuFirstVal: Int32 = 0
            for (i, c) in cpu.coefficients.enumerated() where i < gpu.coefficients.count {
                let g = gpu.coefficients[i]
                if c != g {
                    if firstMismatch < 0 {
                        firstMismatch = i; cpuFirstVal = c; gpuFirstVal = g
                    }
                    mismatch += 1
                    let diff = abs(Int64(c) - Int64(g))
                    if diff > Int64(maxAbsDiff) { maxAbsDiff = Int32(min(diff, Int64(Int32.max))) }
                }
            }
            if mismatch > 0 {
                drifts.append(Drift(
                    key: cpuKey,
                    dims: "\(cpu.width)x\(cpu.height)",
                    coeffMismatchCount: mismatch,
                    maxAbsDiff: maxAbsDiff,
                    firstMismatchIndex: firstMismatch,
                    cpuFirstMismatchValue: cpuFirstVal,
                    gpuFirstMismatchValue: gpuFirstVal))
            }
        }

        print()
        print("  Total subbands: \(cpuSorted.count)")
        print("  Drift subbands: \(drifts.count)")
        if drifts.isEmpty {
            print("  ✅ SubbandInfo output bit-exact between GPU and CPU entropy paths.")
            print("  → The 32768 pixel diff is NOT in applyEntropyDecoding's [SubbandInfo] output.")
            print("  → Look further downstream: applyDequantization or applyInverseWaveletTransform.")
        } else {
            print("  ❌ SubbandInfo divergence located in applyEntropyDecoding.")
            print()
            print("  | subband (comp_level_subband) | dims | mismatch # | maxAbsDiff | firstIdx | CPU val | GPU val |")
            print("  |---|---|---|---|---|---|---|")
            for d in drifts.prefix(20) {
                print(String(format: "  | %@ | %@ | %d | %d | %d | %d | %d |",
                    d.key, d.dims,
                    d.coeffMismatchCount, d.maxAbsDiff,
                    d.firstMismatchIndex,
                    d.cpuFirstMismatchValue, d.gpuFirstMismatchValue))
            }
            print()
            // Subband distribution of drift.
            var subbandDist: [String: Int] = [:]
            for d in drifts {
                let parts = d.key.split(separator: "_")
                let sb = String(parts.last ?? "?")
                subbandDist[sb, default: 0] += 1
            }
            print("  Drift by subband: \(subbandDist)")
        }

        print()
        print("=== H1.1 readout ===")
        print("  If drifts.isEmpty → bug is in applyDequantization or IDWT")
        print("  If drifts only in LL → bug in regroup's LL handling (likely the v5.27 fast-out)")
        print("  If drifts spread across all subbands → regroup index-mapping is wrong")
    }
}
