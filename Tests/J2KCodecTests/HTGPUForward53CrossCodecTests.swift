// HTGPUForward53CrossCodecTests.swift
//
// v6-alpha5 Phase 8 — explicit external-decoder cross-codec
// validation of the GPU forward 5/3 INT path.
//
// Phase 0 / 1 / 2 / 4 proved GPU-forward-encoded codestream bytes
// are byte-identical to CPU-forward-encoded bytes. The CPU path's
// cross-codec correctness is in turn proven bit-exact through
// OpenJPH / Grok / Kakadu by `HTTileParityMatrixTests` (12 × 3 =
// 36 cells, every one zero max-abs-pixel-diff). By transitivity
// the GPU path inherits the same external-decoder correctness.
//
// This test makes that transitivity *explicit* — encodes real
// medical fixtures via the GPU forward path, writes the bytes to
// a temp file, hands them to OpenJPH / Grok / Kakadu, and asserts
// the decoded PGM is bit-exact against the original. Catches any
// future drift that breaks the byte-identical assumption (e.g. a
// regression in the parity-aware kernels, or a memory-corruption
// bug in the per-call MTLCommandQueue dispatch from Phase 6).
//
// Skipped automatically when:
//   - Metal isn't available (Linux CI)
//   - The fixture corpus isn't present on disk
//   - The relevant external decoder binary isn't on $PATH
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class HTGPUForward53CrossCodecTests: XCTestCase {

    private func htConfig(decompositionLevels: Int = 5) -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: decompositionLevels,
            qualityLayers: 1, progressionOrder: .lrcp,
            bitrateMode: .lossless, maxThreads: 8,
            useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
    }

    /// Encode helper that explicitly forces the GPU forward path.
    /// Restores both the env-var-cached enable flag and the pixel
    /// threshold (so other tests in the same process aren't
    /// affected).
    private func encodeViaGPU(
        _ image: J2KImage,
        config: J2KEncodingConfiguration
    ) async throws -> Data {
        let prevEnabled = EncoderPipeline._gpuForward53Enabled
        let prevThreshold = EncoderPipeline._gpuForward53PixelThreshold
        defer {
            EncoderPipeline._gpuForward53Enabled = prevEnabled
            EncoderPipeline._gpuForward53PixelThreshold = prevThreshold
        }
        EncoderPipeline._gpuForward53Enabled = true
        // Force-arm GPU on every fixture size (the production
        // 4 MP threshold would route MR / XA / CT to CPU; we want
        // to verify the GPU path bytes specifically).
        EncoderPipeline._gpuForward53PixelThreshold = 1
        let encoder = J2KEncoder(encodingConfiguration: config)
        return try await encoder.encode(image)
    }

    /// Cross-decode helper: writes the codestream to a tmp file,
    /// runs the named external decoder, loads the resulting PGM,
    /// returns max-abs-pixel-diff against the original (or `nil`
    /// if the decoder binary is unavailable / failed).
    private func crossDecodeMaxDiff(
        codestream: Data,
        original: J2KImage,
        codec: CrossCodecTooling.Codec,
        scratchPrefix: String
    ) throws -> Int? {
        let tmpDir = NSTemporaryDirectory()
        let codeStreamPath = tmpDir + scratchPrefix + ".j2k"
        let outPath        = tmpDir + scratchPrefix + "_\(codec.rawValue).pgm"
        try codestream.write(to: URL(fileURLWithPath: codeStreamPath))
        defer {
            try? FileManager.default.removeItem(atPath: codeStreamPath)
            try? FileManager.default.removeItem(atPath: outPath)
        }

        guard CrossCodecTooling.findTool(codec.decompressTool) != nil else {
            return nil  // decoder binary missing — skip
        }
        let dec = try CrossCodecTooling.decompressLossless(
            codec, input: codeStreamPath, output: outPath)
        if dec.status != 0 {
            return -1  // decoder ran but reported failure
        }
        guard let crossImg = try CrossCodecTooling.loadPGM16BE(URL(fileURLWithPath: outPath)) else {
            return -2  // decoder succeeded but PGM unreadable
        }
        return CrossCodecTooling.maxAbsPixelDiff(original, crossImg)
    }

    /// Sweep the medical corpus through the GPU forward encode
    /// path and cross-decode every output through every external
    /// HT-capable decoder. Print a parity-matrix-style table and
    /// assert every (fixture, decoder) cell is bit-exact (max-abs-
    /// pixel-diff = 0).
    func testGPUForward53_MedicalCorpus_CrossDecodesBitExactExternalDecoders() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let cfg = htConfig()
        let codecs: [CrossCodecTooling.Codec] = [.openjph, .grok, .kakadu]

        struct Row {
            let modality: String
            let shape: String
            let bytesOut: Int
            let crossDiff: [String: Int?]  // codec → maxAbsDiff (nil = decoder missing)
        }
        var rows: [Row] = []
        var anyFixturePresent = false

        for fixture in CrossCodecTooling.medicalCorpus {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }
            anyFixturePresent = true

            let codestream = try await encodeViaGPU(img, config: cfg)
            let stem = "\(fixture.modality)_\(fixture.labelHint.replacingOccurrences(of: "×", with: "x"))_gpu"

            var perCodec: [String: Int?] = [:]
            for codec in codecs {
                let diff = try crossDecodeMaxDiff(
                    codestream: codestream, original: img,
                    codec: codec, scratchPrefix: stem)
                perCodec[codec.rawValue] = diff
            }

            rows.append(Row(
                modality: fixture.modality, shape: fixture.labelHint,
                bytesOut: codestream.count, crossDiff: perCodec))
        }

        if !anyFixturePresent { throw XCTSkip("medical corpus not present") }

        // Print the cross-codec table.
        print("\n=== Phase 8 — GPU forward 5/3 INT cross-codec validation ===")
        print("(max-abs-pixel-diff vs original PGM; 0 = bit-exact, " +
              "-1 = decoder failed, missing = binary not on PATH)")
        print()
        print("| Modality | Shape | Bytes | OpenJPH | Grok | Kakadu |")
        print("|---|---|---:|---:|---:|---:|")
        for r in rows {
            func cell(_ name: String) -> String {
                if let v = r.crossDiff[name] {
                    if let d = v { return String(d) } else { return "—" }
                }
                return "—"
            }
            print(String(format: "| %@ | %@ | %d | %@ | %@ | %@ |",
                r.modality, r.shape, r.bytesOut,
                cell("openjph"), cell("grok"), cell("kakadu")))
        }
        print()

        // Assert: every (fixture, decoder-found) cell is 0
        // (bit-exact). Missing-binary cells are skipped.
        for r in rows {
            for codec in codecs {
                guard let diff = r.crossDiff[codec.rawValue], let d = diff else { continue }
                XCTAssertEqual(d, 0,
                    "GPU-forward-encoded \(r.modality) \(r.shape) " +
                    "must cross-decode bit-exact through \(codec.rawValue) " +
                    "(got max-abs-pixel-diff = \(d))")
            }
        }
    }
}
