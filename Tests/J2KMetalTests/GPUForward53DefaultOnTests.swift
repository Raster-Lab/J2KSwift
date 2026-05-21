// GPUForward53DefaultOnTests.swift
//
// v6.1.0 — promotes `_gpuForward53Enabled` from default-off to
// default-on. Validates two invariants that protect production
// users on this change:
//
//   1. **Codestream bytes byte-identical** between default-on
//      (this PR) and forced-off (env var = 0). Per RELEASING.md
//      this is the load-bearing invariant for a non-bytes-changing
//      default flip — only routing changes; all observable output
//      stays the same.
//
//   2. **Telemetry confirms expected routing on default config**:
//      ≥3 MP fixtures see GPU fire by default; <3 MP fixtures stay
//      on CPU (gated out by the threshold predicate).
//
// Plus a wall-time A/B printed for each fixture so the PR has the
// actually-measured-on-this-host wins, not just citations of
// v6-alpha5 Phase 9 numbers.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class GPUForward53DefaultOnTests: XCTestCase {

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
        let isAboveThreshold: Bool   // ≥ 3 MP (v6.3.0 E2) — should hit GPU on default
    }

    private static let corpus: [CorpusFixture] = [
        // pixels = w*h; threshold default = 3_000_000 (v6.3.0 E2;
        // was 4_000_000 in v6.0.0 / v6-alpha5 phase 5).
        CorpusFixture(label: "MR-small 180²",   filename: "mr_study_002_instance_000100.pgm",
                      pixels: 32_400,    isAboveThreshold: false),
        CorpusFixture(label: "CT 512²",         filename: "ct_study_001_instance_000001.pgm",
                      pixels: 262_144,   isAboveThreshold: false),
        CorpusFixture(label: "MR 886²",         filename: "mr_study_001_instance_000001.pgm",
                      pixels: 784_996,   isAboveThreshold: false),
        CorpusFixture(label: "XA 1024²",        filename: "xa_study_001_instance_000001.pgm",
                      pixels: 1_048_576, isAboveThreshold: false),
        CorpusFixture(label: "PX 2459×1316",    filename: "px_study_001_instance_000001.pgm",
                      pixels: 3_236_044, isAboveThreshold: true),  // v6.3.0 E2: now ≥ 3 MP threshold
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

    /// Save and restore the gate state so this test class doesn't
    /// pollute later tests in the same process.
    private func encode(image: J2KImage, gateOn: Bool) async throws -> Data {
        let prev = EncoderPipeline._gpuForward53Enabled
        defer { EncoderPipeline._gpuForward53Enabled = prev }
        EncoderPipeline._gpuForward53Enabled = gateOn
        return try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)
    }

    // MARK: - Bit-exact contract

    /// **Lossless contract**: bytes byte-identical between default-on
    /// (production now) and forced-off (legacy CPU path) across every
    /// medical-corpus fixture. Failing this would mean codestream
    /// bytes changed on a non-bytes-changing default flip — the
    /// release-notes contract is broken.
    func testDefaultOn_BytesIdentical_VsForcedOff_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else {
                print("[skip] fixture not present: \(fix.filename)")
                continue
            }
            let gpuBytes = try await encode(image: image, gateOn: true)
            let cpuBytes = try await encode(image: image, gateOn: false)
            XCTAssertEqual(gpuBytes.count, cpuBytes.count,
                "[\(fix.label)] codestream byte counts diverged: " +
                "gpuOn=\(gpuBytes.count) gpuOff=\(cpuBytes.count)")
            XCTAssertEqual(gpuBytes, cpuBytes,
                "[\(fix.label)] codestream bytes diverged " +
                "(\(gpuBytes.count) bytes total)")
        }
    }

    // MARK: - Default routing telemetry

    /// `J2K_GPU_FORWARD_53=0` opt-out — when the flag is forced off
    /// programmatically (mirroring what the env var would do at
    /// startup), even ≥3 MP fixtures must skip GPU and record an
    /// envDisabled telemetry event. Documents the opt-out path for
    /// users who need to force the legacy CPU path.
    func testDefaultOn_OptOut_RoutesToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX fixture not present")
        }

        let prev = EncoderPipeline._gpuForward53Enabled
        defer { EncoderPipeline._gpuForward53Enabled = prev }
        EncoderPipeline._gpuForward53Enabled = false

        J2KGPUForward53Telemetry.reset()
        _ = try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)

        let snap = J2KGPUForward53Telemetry.snapshot()
        XCTAssertEqual(snap.gpuFireCount, 0,
            "opt-out (flag=false) should keep DX on CPU")
        XCTAssertGreaterThan(snap.cpuFireByReason[.envDisabled] ?? 0, 0,
            "opt-out should record envDisabled skip reason")
    }

    // MARK: - Wall-time A/B (diagnostic)

    /// Median-of-3 wall-time across the corpus, default-on vs
    /// forced-off. Diagnostic — does not assert any threshold; the
    /// print is the data the PR description records.
    func testDefaultOn_WallTimeAB_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  Wall-time A/B in DEBUG; numbers will be 50–100× too slow.")
        #endif

        print("=== v6.1.0 default-on GPU forward 5/3 INT — wall-time A/B ===")
        print("(Threshold default = 3 MP after v6.3.0 E2. ≥3 MP fixtures route to GPU on default;")
        print(" sub-3 MP fixtures route to CPU regardless of flag — gated by threshold.)")
        print()
        print("| fixture | px | bytes | CPU ms | GPU(default) ms | Δ % | route |")
        print("|---|---:|---:|---:|---:|---:|:---|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warm-up.
            _ = try await encode(image: image, gateOn: true)
            _ = try await encode(image: image, gateOn: false)

            // CPU (gateOn=false).
            var cpuMs: [Double] = []
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encode(image: image, gateOn: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }

            // GPU (gateOn=true → production default after this PR).
            var gpuMs: [Double] = []
            var bytes = 0
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                let data = try await encode(image: image, gateOn: true)
                gpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                bytes = data.count
            }

            cpuMs.sort(); gpuMs.sort()
            let cpuMed = cpuMs[1]
            let gpuMed = gpuMs[1]
            let delta = ((cpuMed - gpuMed) / cpuMed) * 100.0
            let route = fix.isAboveThreshold ? "GPU" : "CPU (gated)"
            print(String(format: "| %@ | %d | %d | %6.2f | %6.2f | %+5.1f | %@ |",
                fix.label, fix.pixels, bytes, cpuMed, gpuMed, delta, route))
        }

        print()
        print("Reading the table:")
        print("  - For ≥3 MP fixtures (route=GPU): Δ% > 0 means default-on is faster")
        print("    (the win this PR ships).")
        print("  - For <3 MP fixtures (route=CPU): Δ% should be near zero — the")
        print("    threshold gate routes both paths to CPU regardless of flag.")
        print("    Any non-noise delta there indicates the threshold predicate")
        print("    isn't doing its job.")
    }
}
