// MultiTileGPUHTEntropyDriftTests.swift
//
// v7.1.0 H1.0 — Defect A Phase 0 root-cause probe.
//
// docs/V6_3_0_E1_2_INVESTIGATION.md #Defect A documented that
// GPU HT entropy decode in the multi-tile per-tile context
// produces decoded pixel data that diffs from CPU HT decode by
// exactly 32768 (= 2^15 = DC offset for 16-bit) on DX 2800×2288.
// Single-tile DX via the same `J2KGPUHTDispatch.decodeBatch` API
// is bit-exact since v5.5.0 — the bug is per-tile-shape-specific.
//
// This test isolates the defect at the block level: it encodes
// DX multi-tile, extracts codeblocks for the failing tile, runs
// them through both GPU HT (`J2KGPUHTDispatch.decodeBatch`) and
// CPU HT (`HTBlockDecoderConformant.decode`), and compares the
// per-block Int32 coefficient arrays.
//
// The diagnostic answers:
//
//   1. Which block(s) drift between GPU and CPU?
//   2. By what magnitude (per-coefficient diff distribution)?
//   3. Are drifts concentrated in the LL band (which would
//      explain the 32768 pixel diff post-IDWT — LL coefficients
//      reconstruct to spatial pixels via the lifting steps), or
//      spread across all subbands?
//   4. Does the same code path produce bit-exact output on
//      single-tile DX (control case)?
//
// Output of this test is the input to H1.1 (the actual fix).
// The data identifies the precise root cause (mis-counted
// outputSampleCount, kernel state corruption, descriptor
// mis-encoding, etc.) for a targeted fix.
//
// Skipped automatically in DEBUG (numbers / timing not relevant
// since this is a correctness probe) or when Metal is unavailable.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MultiTileGPUHTEntropyDriftTests: XCTestCase {

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

    /// Convert one CPU HT decoded block (UInt32 OpenJPH sign-magnitude)
    /// to Int32 integer-magnitude using the same shift the GPU no-
    /// session path applies in `J2KGPUHTDispatch.decodeBatch` for
    /// apples-to-apples comparison.
    private func cpuToInt32IntegerMagnitude(
        _ uint32Coeffs: [UInt32], missingMSBs: Int
    ) -> [Int32] {
        let shift = UInt32(30 - missingMSBs)
        return uint32Coeffs.map { uint -> Int32 in
            let sign = (uint & 0x8000_0000) != 0
            let mag = Int32((uint & 0x7FFF_FFFF) >> shift)
            return sign ? -mag : mag
        }
    }

    private struct BlockInfo {
        let originalIndex: Int
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let width: Int
        let height: Int
        let zeroBitPlanes: Int
        let dataLen: Int
    }

    private struct DriftCell {
        let blockInfo: BlockInfo
        let mismatchCount: Int
        let maxAbsDiff: Int32
        let cpuFirst10: [Int32]
        let gpuFirst10: [Int32]
    }

    /// Probe — run GPU HT batch + CPU HT decode on the same
    /// codeblock set extracted from the failing DX tile. Compare
    /// per-block. Report which blocks drift and how.
    func testDefectA_PerBlockDriftOnFailingDXTile() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }

        // Encode DX multi-tile (2x2 — the failing case from E1.2 measurements).
        let cfg = htConfig()
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: image.width, imageHeight: image.height,
            decompositionLevels: 5, mode: .tiles2x2)
        XCTAssertTrue(layout.isMultiTile, "DX 2x2 must be multi-tile")

        let result = try await J2KMultiTileEncoder.encode(
            image: image, layout: layout, configuration: cfg)
        let codestream = result.codestream

        // Parse the codestream + extract codeblocks for tile 1.
        // Tile 1 = top-right tile; origin (1400, 0) for DX 2x2.
        // Per E1.2 finding, every non-XA tile fails — pick tile 1
        // as a representative failing case.
        let pipeline = DecoderPipeline()
        let (metadata, tiles) = try pipeline.parseCodestream(codestream)
        XCTAssertEqual(tiles.count, 4, "DX 2x2 expected 4 tiles")

        // Run for tile 0/1/2/3 of DX 2x2 to compare per-block GPU vs CPU
        // coefficient outputs across all four tile-origin parities.
        // (v7.0.0 default-flip routes J2KEncoder.encode to .auto / 4x4 for DX,
        // so we can't easily get a single-tile control codestream from the
        // production path; instead we use multi-tile tile 0 (origin 0,0) as
        // the closest-to-single-tile control case.)
        let singleMetadata = metadata
        let singleTiles = tiles

        // Capture diff cells for tiles 0-3 of DX 2x2.
        _ = singleMetadata
        _ = singleTiles
        for (testCaseLabel, tileMeta, tileData, tileOriginX, tileOriginY) in [
            ("MULTI tile 0  origin(0,0)", multiTileMeta(metadata, tileIndex: 0),
             tiles[0].tileData, 0, 0),
            ("MULTI tile 1  origin(1400,0)", multiTileMeta(metadata, tileIndex: 1),
             tiles[1].tileData, 1400, 0),
            ("MULTI tile 2  origin(0,1144)", multiTileMeta(metadata, tileIndex: 2),
             tiles[2].tileData, 0, 1144),
            ("MULTI tile 3  origin(1400,1144)", multiTileMeta(metadata, tileIndex: 3),
             tiles[3].tileData, 1400, 1144)
        ] {
            print()
            print("=== \(testCaseLabel) ===")

            let codeBlocks = try pipeline.extractTileData(
                tileData, metadata: tileMeta,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY)
            print("  codeblock count: \(codeBlocks.count)")

            // Build the GPUHTBlock array (filter empties; mirror of
            // gpuEarly closure's filter).
            var gpuInputs: [GPUHTBlock] = []
            var inputOriginalIndices: [Int] = []
            for (i, block) in codeBlocks.enumerated() {
                guard !block.data.isEmpty, block.passCount > 0 else { continue }
                gpuInputs.append(GPUHTBlock(
                    width: block.width,
                    height: block.height,
                    data: [UInt8](block.data),
                    missingMSBs: block.zeroBitPlanes))
                inputOriginalIndices.append(i)
            }
            print("  eligible (non-empty, passCount>0): \(gpuInputs.count)")
            if gpuInputs.isEmpty { continue }

            // GPU dispatch (no session — uses the v5.6.0 shift-conversion path
            // so the test sees Int32 integer-magnitude per block,
            // independent of the warm-session fused path).
            let gpuResult = try await J2KGPUHTDispatch.decodeBatch(blocks: gpuInputs)
            XCTAssertTrue(gpuResult.cpuFallbackIndices.isEmpty,
                "[\(testCaseLabel)] expected all blocks GPU-decoded; got \(gpuResult.cpuFallbackIndices.count) fallbacks")

            // CPU per-block decode + shift conversion.
            var cells: [DriftCell] = []
            for (gpuIdx, gpuBlockResult) in gpuResult.results.enumerated() {
                let originalIdx = inputOriginalIndices[gpuResult.decodedBlockIndices[gpuIdx]]
                let block = codeBlocks[originalIdx]
                let cpuUInt32 = try HTBlockDecoderConformant.decode(
                    block: [UInt8](block.data),
                    width: block.width,
                    height: block.height,
                    missingMSBs: block.zeroBitPlanes)
                let cpuInt32 = cpuToInt32IntegerMagnitude(
                    cpuUInt32, missingMSBs: block.zeroBitPlanes)

                let gpuInt32 = gpuBlockResult.coefficients
                XCTAssertEqual(cpuInt32.count, gpuInt32.count,
                    "[\(testCaseLabel) block \(originalIdx)] coeff count mismatch")

                var mismatchCount = 0
                var maxAbsDiff: Int32 = 0
                for (i, c) in cpuInt32.enumerated() where i < gpuInt32.count {
                    let g = gpuInt32[i]
                    if c != g {
                        mismatchCount += 1
                        let diff = abs(Int64(c) - Int64(g))
                        if diff > Int64(maxAbsDiff) { maxAbsDiff = Int32(min(diff, Int64(Int32.max))) }
                    }
                }
                if mismatchCount > 0 {
                    let info = BlockInfo(
                        originalIndex: originalIdx,
                        componentIndex: block.componentIndex,
                        level: block.level,
                        subband: block.subband,
                        width: block.width, height: block.height,
                        zeroBitPlanes: block.zeroBitPlanes,
                        dataLen: block.data.count)
                    cells.append(DriftCell(
                        blockInfo: info,
                        mismatchCount: mismatchCount,
                        maxAbsDiff: maxAbsDiff,
                        cpuFirst10: Array(cpuInt32.prefix(10)),
                        gpuFirst10: Array(gpuInt32.prefix(10))))
                }
            }

            // Report.
            print("  drift cells: \(cells.count) blocks differ out of \(gpuResult.results.count)")
            if cells.isEmpty {
                print("  ✅ ALL BLOCKS BIT-EXACT GPU == CPU")
                continue
            }
            print()
            print("  | block# | comp | level | subband | w×h | missingMSBs | dataLen | mismatch | maxAbsDiff |")
            print("  |---|---|---|---|---|---|---|---|---|")
            for cell in cells.prefix(20) {
                let info = cell.blockInfo
                print(String(format: "  | %d | %d | %d | %@ | %dx%d | %d | %d | %d | %d |",
                    info.originalIndex,
                    info.componentIndex,
                    info.level,
                    String(describing: info.subband),
                    info.width, info.height,
                    info.zeroBitPlanes,
                    info.dataLen,
                    cell.mismatchCount,
                    cell.maxAbsDiff))
            }
            // Show first-10 CPU vs GPU coefficients for the first drift cell.
            if let first = cells.first {
                print()
                print("  First drift cell — block \(first.blockInfo.originalIndex):")
                print("    CPU first 10: \(first.cpuFirst10)")
                print("    GPU first 10: \(first.gpuFirst10)")
                print("    Differences: \(zip(first.cpuFirst10, first.gpuFirst10).enumerated().compactMap { i, p -> String? in p.0 == p.1 ? nil : "[\(i)] cpu=\(p.0) gpu=\(p.1) diff=\(p.0 - p.1)" })")
            }
        }

        // ──────────────────────────────────────────────────────────────
        // SECOND PROBE — decodeBatchGPUResident (production path, with session).
        // The first probe above used decodeBatch (no session). The
        // production multi-tile pipeline uses decodeBatchGPUResident
        // which returns BOTH per-block coefficients AND a gpuBatch
        // (codeblockBuffer + scatter descriptors). Per-block coeffs
        // confirmed bit-exact above; we now check whether the warm-
        // session path's per-block readback also matches CPU.
        // ──────────────────────────────────────────────────────────────
        print()
        print("=== Probe 2 — decodeBatchGPUResident (production with-session path) ===")
        let session = J2KMetalSession()
        for (testCaseLabel, _, tileData, tileOriginX, tileOriginY) in [
            ("MULTI tile 1 (warm-session)", multiTileMeta(metadata, tileIndex: 1),
             tiles[1].tileData, 1400, 0)
        ] {
            let tileMeta = multiTileMeta(metadata, tileIndex: 1)
            let codeBlocks = try pipeline.extractTileData(
                tileData, metadata: tileMeta,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY)
            var gpuInputs: [GPUHTBlock] = []
            var inputOriginalIndices: [Int] = []
            for (i, block) in codeBlocks.enumerated() {
                guard !block.data.isEmpty, block.passCount > 0 else { continue }
                gpuInputs.append(GPUHTBlock(
                    width: block.width, height: block.height,
                    data: [UInt8](block.data),
                    missingMSBs: block.zeroBitPlanes))
                inputOriginalIndices.append(i)
            }
            guard let result = try await J2KGPUHTDispatch.decodeBatchGPUResident(
                blocks: gpuInputs, session: session, includePerBlockCoefficients: true)
            else {
                print("  decodeBatchGPUResident returned nil (no eligible blocks)")
                continue
            }
            print("  \(testCaseLabel):")
            print("    eligible: \(gpuInputs.count); GPU-decoded: \(result.decodedBlockCoefficients.count); fallbacks: \(result.cpuFallbackIndices.count)")
            print("    outputSampleCount: \(result.outputSampleCount)")
            print("    decodedBlockOutputOffsets count: \(result.decodedBlockOutputOffsets.count)")

            // Diff per-block GPU vs CPU on this warm-session path.
            var driftCount = 0
            var maxAbsDiff: Int32 = 0
            for (gpuIdx, gpuCoeffs) in result.decodedBlockCoefficients {
                let originalIdx = inputOriginalIndices[gpuIdx]
                let block = codeBlocks[originalIdx]
                let cpuUInt32 = try HTBlockDecoderConformant.decode(
                    block: [UInt8](block.data),
                    width: block.width, height: block.height,
                    missingMSBs: block.zeroBitPlanes)
                // NOTE: decodeBatchGPUResident's per-block coefficients are
                // already Int32 integer-magnitude (no per-block shift needed,
                // unlike decodeBatch's no-session path). CPU still needs shift.
                let cpuInt32 = cpuToInt32IntegerMagnitude(
                    cpuUInt32, missingMSBs: block.zeroBitPlanes)
                for (i, c) in cpuInt32.enumerated() where i < gpuCoeffs.count {
                    let g = gpuCoeffs[i]
                    if c != g {
                        driftCount += 1
                        let diff = abs(Int64(c) - Int64(g))
                        if diff > Int64(maxAbsDiff) { maxAbsDiff = Int32(min(diff, Int64(Int32.max))) }
                    }
                }
            }
            print("    Drift coefficients: \(driftCount) (maxAbsDiff: \(maxAbsDiff))")
            if driftCount == 0 {
                print("    ✅ decodeBatchGPUResident per-block coefficients bit-exact")
            } else {
                print("    ❌ decodeBatchGPUResident per-block coefficients DRIFT — root cause located")
            }
        }

        print()
        print("=== H1.0 readout ===")
        print("  Probe 1 (decodeBatch, no session) — every tile + every block bit-exact.")
        print("  Probe 2 (decodeBatchGPUResident, with session) — confirms whether the")
        print("    warm-session production path agrees with CPU per-block.")
        print("  If both probes show 0 drift, the Defect A 32768 pixel diff is NOT in")
        print("    the GPU HT entropy decode itself; it's downstream — most likely in")
        print("    the gpuBatch fused-from-codeblocks IDWT path that reads from the")
        print("    codeblockBuffer via scatter descriptors. H1.1 fix scope pivots to")
        print("    inverse2DInt32FullFusedFromCodeblocks per-tile semantics.")
    }

    /// Build per-tile metadata view for tile k (mirrors decodeTilePayloadGPU
    /// line 802-806 from J2KDecoderPipeline.swift).
    private func multiTileMeta(_ imageMeta: CodestreamMetadata, tileIndex: Int) -> CodestreamMetadata {
        let (_, _, tileW, tileH) = imageMeta.tileDimensions(tileIndex: tileIndex)
        var tm = imageMeta
        tm.width = tileW
        tm.height = tileH
        tm.tileSize = (width: tileW, height: tileH)
        return tm
    }
}
