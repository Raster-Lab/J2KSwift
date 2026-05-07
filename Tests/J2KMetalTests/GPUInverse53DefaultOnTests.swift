// GPUInverse53DefaultOnTests.swift
//
// v6.2.0 work item D — promotes `DecoderPipeline._gpuInverse53Enabled`
// from default-off (effective default through v6.1.0 since
// `decode(_:)` never routed to the GPU iDWT path) to default-on for
// ≥4 MP fixtures. Direct mirror of v6.1.0's encode-side default
// flip (#310) but on the decode side.
//
// Validates two invariants that protect production users:
//
//   1. **Decoded J2KImage pixel data byte-identical** between gate-on
//      (production now) and forced-off (legacy CPU path) across every
//      medical-corpus fixture. This is the lossless decode contract —
//      v5.21.0 closed the GPU/CPU 5/3 INT bit-exactness gap; this
//      test pins it across the full pipeline at default-on.
//
//   2. **Default routing**: ≥4 MP fixtures take the GPU iDWT path on
//      default config; <4 MP fixtures stay on CPU (gated out by the
//      threshold predicate, identical to encode-side gate behaviour).
//
// Plus a wall-time A/B printed for each fixture so the PR has the
// actually-measured-on-this-host wins.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class GPUInverse53DefaultOnTests: XCTestCase {

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

    private struct CorpusFixture {
        let label: String
        let filename: String
        let pixels: Int
        let isAboveThreshold: Bool
    }

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "MR-small 180²",   filename: "mr_study_002_instance_000100.pgm",
                      pixels: 32_400,    isAboveThreshold: false),
        CorpusFixture(label: "CT 512²",         filename: "ct_study_001_instance_000001.pgm",
                      pixels: 262_144,   isAboveThreshold: false),
        CorpusFixture(label: "MR 886²",         filename: "mr_study_001_instance_000001.pgm",
                      pixels: 784_996,   isAboveThreshold: false),
        CorpusFixture(label: "XA 1024²",        filename: "xa_study_001_instance_000001.pgm",
                      pixels: 1_048_576, isAboveThreshold: false),
        CorpusFixture(label: "PX 2459×1316",    filename: "px_study_001_instance_000001.pgm",
                      pixels: 3_236_044, isAboveThreshold: false),
        CorpusFixture(label: "DX 2800×2288",    filename: "dx_study_002_instance_000001.pgm",
                      pixels: 6_406_400, isAboveThreshold: true),
    ]

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Save and restore the gate state.
    private func decode(codestream: Data, gateOn: Bool) async throws -> J2KImage {
        let prev = DecoderPipeline._gpuInverse53Enabled
        defer { DecoderPipeline._gpuInverse53Enabled = prev }
        DecoderPipeline._gpuInverse53Enabled = gateOn
        return try await J2KDecoder().decode(codestream)
    }

    /// Compare decoded pixel data byte-by-byte across every component.
    /// Returns nil if equal; (componentIndex, byteOffset) on first mismatch.
    private func firstPixelDiff(_ a: J2KImage, _ b: J2KImage) -> (Int, Int)? {
        guard a.width == b.width, a.height == b.height,
              a.components.count == b.components.count
        else { return (-1, -1) }
        for i in 0..<a.components.count {
            let aData = a.components[i].data
            let bData = b.components[i].data
            if aData.count != bData.count { return (i, -1) }
            let n = aData.count
            var diff = -1
            aData.withUnsafeBytes { (aRaw: UnsafeRawBufferPointer) in
                bData.withUnsafeBytes { (bRaw: UnsafeRawBufferPointer) in
                    let ab = aRaw.bindMemory(to: UInt8.self)
                    let bb = bRaw.bindMemory(to: UInt8.self)
                    for j in 0..<n where ab[j] != bb[j] {
                        diff = j; break
                    }
                }
            }
            if diff >= 0 { return (i, diff) }
        }
        return nil
    }

    // MARK: - Bit-exact pixel contract

    /// **Decoded pixel contract**: J2KImage pixel data byte-identical
    /// between default-on (production now) and forced-off (legacy CPU
    /// path) across every medical-corpus fixture. v5.21.0 closed the
    /// GPU/CPU 5/3 INT bit-exactness gap; this test pins it across
    /// the full pipeline at default-on.
    func testDefaultOn_DecodedPixelsIdentical_VsForcedOff_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        // Encoder is shared: encode each fixture once with the
        // production lossless config, then decode the same codestream
        // through both paths.
        let enc = J2KEncoder(encodingConfiguration: htConfig())

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else {
                print("[skip] fixture not present: \(fix.filename)")
                continue
            }
            let codestream = try await enc.encode(image)
            let cpuImage = try await decode(codestream: codestream, gateOn: false)
            let gpuImage = try await decode(codestream: codestream, gateOn: true)
            if let (compIdx, byteOff) = firstPixelDiff(cpuImage, gpuImage) {
                XCTFail("[\(fix.label)] decoded pixels diverged at " +
                        "component \(compIdx) byte \(byteOff)")
            }
        }
    }

    // MARK: - Default routing telemetry-equivalent

    /// On default config (`_gpuInverse53Enabled = true`,
    /// `_gpuInverse53PixelThreshold = 4_000_000`), DX 2800×2288
    /// should take the GPU path; the 5 sub-4 MP fixtures stay on CPU
    /// (gated by the threshold predicate). We can't easily inspect
    /// which path fired without telemetry, so this test does the
    /// next best thing: verify the gate-on default produces correct
    /// output (bit-exact pixels, no errors) on every fixture
    /// regardless of whether that fixture went to GPU or stayed on
    /// CPU. A full telemetry-counter test mirroring
    /// J2KGPUForward53Telemetry can be added in a follow-up if
    /// per-call routing observability is needed.
    func testDefaultOn_AllFixturesProduceCorrectPixels() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        let enc = J2KEncoder(encodingConfiguration: htConfig())
        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let codestream = try await enc.encode(image)
            // No gate manipulation — production default.
            let decoded = try await J2KDecoder().decode(codestream)
            XCTAssertEqual(decoded.width, image.width,
                "[\(fix.label)] decoded width != source width")
            XCTAssertEqual(decoded.height, image.height,
                "[\(fix.label)] decoded height != source height")
            // Pixel data must equal the original (lossless contract).
            let origData = image.components[0].data
            let decData = decoded.components[0].data
            XCTAssertEqual(origData.count, decData.count,
                "[\(fix.label)] decoded byte count mismatch")
            XCTAssertEqual(origData, decData,
                "[\(fix.label)] decoded pixels diverge from source")
        }
    }

    /// `J2K_GPU_INVERSE_53=0` opt-out (programmatic equivalent) —
    /// even ≥4 MP fixtures decode through the legacy CPU path. The
    /// pixel data is identical (lossless contract holds) but the
    /// route differs; the previous bit-exact test already pinned
    /// that. This test is a smoke check that the opt-out path
    /// doesn't error.
    func testDefaultOn_OptOut_DoesNotError() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX fixture not present")
        }
        let enc = J2KEncoder(encodingConfiguration: htConfig())
        let codestream = try await enc.encode(image)
        let decoded = try await decode(codestream: codestream, gateOn: false)
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
        XCTAssertEqual(decoded.components[0].data, image.components[0].data)
    }

    // MARK: - Wall-time A/B (diagnostic)

    /// Median-of-3 wall-time across the corpus, default-on vs forced-
    /// off. Diagnostic — prints the table the PR description records.
    func testDefaultOn_WallTimeAB_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  Wall-time A/B in DEBUG; numbers will be 50–100× too slow.")
        #endif

        let enc = J2KEncoder(encodingConfiguration: htConfig())

        print("=== v6.2.0 default-on GPU inverse 5/3 INT — DECODE wall-time A/B ===")
        print("(Threshold default = 4 MP. ≥4 MP fixtures route to GPU iDWT on default;")
        print(" sub-4 MP fixtures route to CPU regardless of flag — gated by threshold.)")
        print()
        print("| fixture | px | bytes | CPU ms | GPU(default) ms | Δ % | route |")
        print("|---|---:|---:|---:|---:|---:|:---|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let codestream = try await enc.encode(image)

            // Warm-up.
            _ = try await decode(codestream: codestream, gateOn: true)
            _ = try await decode(codestream: codestream, gateOn: false)

            // CPU (gateOn=false).
            var cpuMs: [Double] = []
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await decode(codestream: codestream, gateOn: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }

            // GPU (gateOn=true → production default after this PR).
            var gpuMs: [Double] = []
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await decode(codestream: codestream, gateOn: true)
                gpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }

            cpuMs.sort(); gpuMs.sort()
            let cpuMed = cpuMs[1]
            let gpuMed = gpuMs[1]
            let delta = ((cpuMed - gpuMed) / cpuMed) * 100.0
            let route = fix.isAboveThreshold ? "GPU" : "CPU (gated)"
            print(String(format: "| %@ | %d | %d | %6.2f | %6.2f | %+5.1f | %@ |",
                fix.label, fix.pixels, codestream.count,
                cpuMed, gpuMed, delta, route))
        }

        print()
        print("Reading the table:")
        print("  - For ≥4 MP fixtures (route=GPU): Δ% > 0 means default-on is faster")
        print("  - For <4 MP fixtures (route=CPU): both paths CPU; Δ% is M2 noise band")
    }
}
