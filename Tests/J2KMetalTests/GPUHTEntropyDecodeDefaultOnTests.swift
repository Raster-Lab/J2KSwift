// GPUHTEntropyDecodeDefaultOnTests.swift
//
// v6.2.0 work item D2 — pairs the v6.2.0-D1 (#314) gate flag
// `_gpuInverse53Enabled` with a new `_gpuHTEntropyEnabled` flag that
// ALSO sets `useGPUHT = true` on the routed GPU path. Mirror of
// `decodeWithGPUHT(_:)` at the gate level. Targets the 45 % of DX
// wall the iDWT-only routing in D1 missed (entropy stage per #313).
//
// Validates two invariants:
//
//   1. **Decoded J2KImage pixel data byte-identical** between both
//      flags on (GPU iDWT + GPU HT entropy path) and both flags off
//      (legacy CPU path) across every medical-corpus fixture.
//      Lossless contract preserved.
//
//   2. **Wall-time A/B** — does pairing iDWT routing with HT entropy
//      flip D1's regression to a win at corpus scale? D1 measured
//      iDWT-only routing as a regression on every corpus fixture
//      because CPU 5/3 INT iDWT was already very fast. D2 tests
//      whether the additional HT entropy GPU work tips the balance.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class GPUHTEntropyDecodeDefaultOnTests: XCTestCase {

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

    /// Save and restore both flag states. Setting `gateOn=true` flips
    /// BOTH `_gpuInverse53Enabled` and `_gpuHTEntropyEnabled` to true
    /// — the combined-routing scenario D2 tests.
    private func decode(codestream: Data, gateOn: Bool) async throws -> J2KImage {
        let prevInv = DecoderPipeline._gpuInverse53Enabled
        let prevHT = DecoderPipeline._gpuHTEntropyEnabled
        defer {
            DecoderPipeline._gpuInverse53Enabled = prevInv
            DecoderPipeline._gpuHTEntropyEnabled = prevHT
        }
        DecoderPipeline._gpuInverse53Enabled = gateOn
        DecoderPipeline._gpuHTEntropyEnabled = gateOn
        return try await J2KDecoder().decode(codestream)
    }

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

    /// Decoded J2KImage pixel data byte-identical between combined-
    /// gate-on (GPU iDWT + useGPUHT) and forced-off (legacy CPU)
    /// across every corpus fixture. Lossless contract preserved.
    func testD2_DecodedPixelsIdentical_VsForcedOff_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

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

    // MARK: - Wall-time A/B (the headline diagnostic)

    /// Median-of-3 wall-time A/B. The data answers: does pairing
    /// iDWT routing with GPU HT entropy flip D1's regression to a win?
    func testD2_WallTimeAB_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  Wall-time A/B in DEBUG; numbers will be 50–100× too slow.")
        #endif

        let enc = J2KEncoder(encodingConfiguration: htConfig())

        print("=== v6.2.0 work item D2 — GPU iDWT + GPU HT entropy DECODE wall-time A/B ===")
        print("(gateOn flips BOTH _gpuInverse53Enabled AND _gpuHTEntropyEnabled to true.)")
        print("(Threshold default = 4 MP. ≥4 MP fixtures route to GPU+useGPUHT path on default;")
        print(" sub-4 MP fixtures route to CPU regardless of flags.)")
        print()
        print("| fixture | px | bytes | CPU ms | GPU+HT ms | Δ % | route |")
        print("|---|---:|---:|---:|---:|---:|:---|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let codestream = try await enc.encode(image)

            // Warm-up.
            _ = try await decode(codestream: codestream, gateOn: true)
            _ = try await decode(codestream: codestream, gateOn: false)

            // CPU baseline (both flags off).
            var cpuMs: [Double] = []
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await decode(codestream: codestream, gateOn: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }

            // GPU + HT entropy (both flags on).
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
            let route = fix.isAboveThreshold ? "GPU + useGPUHT" : "CPU (gated)"
            print(String(format: "| %@ | %d | %d | %6.2f | %6.2f | %+5.1f | %@ |",
                fix.label, fix.pixels, codestream.count,
                cpuMed, gpuMed, delta, route))
        }

        print()
        print("Reading the table:")
        print("  - For ≥4 MP (route=GPU+useGPUHT): Δ% > 0 means D2 wins → flip default ON")
        print("  - For ≥4 MP: Δ% < 0 means D2 also regresses → keep default OFF, doc the wash")
    }
}
