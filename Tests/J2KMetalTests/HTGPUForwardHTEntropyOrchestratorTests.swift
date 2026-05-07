// HTGPUForwardHTEntropyOrchestratorTests.swift
//
// v6-alpha6 phase 1.3 — orchestrator-level validation of the GPU
// forward HT entropy gate.
//
// Phase 1.3 wires the batched API from Phase 1.2 (#304) through
// `applyEntropyCodingHTJ2KFused`. This test ensures:
//
//   1. **Codestream bytes byte-identical** between gate-on and
//      gate-off runs. Production users opting in must see the same
//      bytes as production users on the default CPU path —
//      otherwise the lossless contract breaks (cross-codec
//      validation, downstream decode-equality, byte-for-byte
//      archive comparisons all fail).
//
//   2. **Telemetry counters fire correctly** through the
//      orchestrator path: one `gpuFireCount` per encode whose
//      block count clears the threshold; one `cpuFireByReason`
//      with the right enum value otherwise.
//
//   3. **Wall-time A/B (diagnostic)** — the headline question
//      Phase 1.3 was queued to answer: does the GPU classify
//      offload actually beat the CPU encoder at corpus scales?
//      Phase 0.5 + Phase 1.2 (256-block diagnostic) both hinted
//      "no at moderate scales, maybe at DX scale". This test
//      runs the full medical corpus through both paths and prints
//      the comparison.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class HTGPUForwardHTEntropyOrchestratorTests: XCTestCase {

    // MARK: - Fixtures

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // J2KMetalTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
        // Parse P5 header.
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
    }

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "MR-small 180²",   filename: "mr_study_002_instance_000100.pgm"),
        CorpusFixture(label: "CT 512²",         filename: "ct_study_001_instance_000001.pgm"),
        CorpusFixture(label: "MR 886²",         filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",        filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316",    filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288",    filename: "dx_study_002_instance_000001.pgm"),
    ]

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func encodeWithGateState(_ image: J2KImage, gateOn: Bool,
                                     blockThreshold: Int? = nil) async throws -> Data {
        let prevEnabled = EncoderPipeline._gpuForwardHTEntropyEnabled
        let prevThreshold = EncoderPipeline._gpuForwardHTEntropyBlockThreshold
        defer {
            EncoderPipeline._gpuForwardHTEntropyEnabled = prevEnabled
            EncoderPipeline._gpuForwardHTEntropyBlockThreshold = prevThreshold
        }
        EncoderPipeline._gpuForwardHTEntropyEnabled = gateOn
        if let t = blockThreshold {
            EncoderPipeline._gpuForwardHTEntropyBlockThreshold = t
        }
        return try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)
    }

    // MARK: - Bit-exact byte equality (the lossless contract)

    /// Full-pipeline byte equality across all corpus fixtures.
    /// Lowers the threshold to 1 so the gate fires on every fixture
    /// (small ones too) — confirms the orchestrator path produces
    /// byte-identical output to the CPU path even at sub-threshold
    /// fixture sizes.
    func testOrchestrator_GateOnVsOff_BytesIdentical_AllFixtures() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else {
                print("[skip] fixture not present: \(fix.filename)")
                continue
            }
            let cpuBytes = try await encodeWithGateState(image, gateOn: false)
            let gpuBytes = try await encodeWithGateState(image, gateOn: true,
                                                         blockThreshold: 1)
            XCTAssertEqual(cpuBytes.count, gpuBytes.count,
                "[\(fix.label)] codestream byte counts diverged: " +
                "cpu=\(cpuBytes.count) gpu=\(gpuBytes.count)")
            XCTAssertEqual(cpuBytes, gpuBytes,
                "[\(fix.label)] codestream bytes diverged " +
                "(\(cpuBytes.count) bytes total)")
        }
    }

    // MARK: - Telemetry through the orchestrator

    /// Gate off ⇒ telemetry must record the env-disabled skip; gate
    /// on with sub-threshold block count ⇒ below-threshold skip;
    /// gate on with threshold lowered to 1 ⇒ gpu fire.
    func testOrchestrator_TelemetryRoutingPredicates() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")
        guard let image = loadPGM16("mr_study_001_instance_000001.pgm") else {
            throw XCTSkip("MR 886² fixture not present")
        }

        // 1) Gate off
        J2KGPUForwardHTEntropyTelemetry.reset()
        _ = try await encodeWithGateState(image, gateOn: false)
        let s1 = J2KGPUForwardHTEntropyTelemetry.snapshot()
        XCTAssertEqual(s1.gpuFireCount, 0)
        XCTAssertGreaterThan(s1.cpuFireByReason[.envDisabled] ?? 0, 0,
            "gate off should record env-disabled skip")

        // 2) Gate on, sub-threshold (default 256 — MR 886² has fewer
        //    blocks than 256 in the LL band but probably more across
        //    all bands; force-bump the threshold above the fixture's
        //    block count so we definitely see below-threshold).
        J2KGPUForwardHTEntropyTelemetry.reset()
        _ = try await encodeWithGateState(image, gateOn: true,
                                          blockThreshold: 100_000)
        let s2 = J2KGPUForwardHTEntropyTelemetry.snapshot()
        XCTAssertEqual(s2.gpuFireCount, 0)
        XCTAssertGreaterThan(s2.cpuFireByReason[.belowBlockThreshold] ?? 0, 0,
            "gate on + threshold above block count should record below-threshold")

        // 3) Gate on, threshold lowered to 1 ⇒ GPU must fire.
        J2KGPUForwardHTEntropyTelemetry.reset()
        _ = try await encodeWithGateState(image, gateOn: true,
                                          blockThreshold: 1)
        let s3 = J2KGPUForwardHTEntropyTelemetry.snapshot()
        XCTAssertGreaterThan(s3.gpuFireCount, 0,
            "gate on + threshold 1 must fire GPU")
        XCTAssertGreaterThan(s3.gpuBlocksClassified, 0)
    }

    // MARK: - Wall-time A/B (diagnostic)

    /// Wall-time comparison across the corpus. Diagnostic — does not
    /// assert any threshold; the print output is the input to the
    /// Phase 1.3 decision (keep approach B / raise threshold / pivot
    /// to E).
    ///
    /// Median of 3 release-mode runs each. Uses warm session — the
    /// J2KMetalSession.processShared singleton from the v6.0.0
    /// forward DWT path is reused, so dispatch setup is amortised.
    func testOrchestrator_WallTimeAB_AcrossCorpus() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  Wall-time A/B in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter HTGPUForwardHTEntropyOrchestratorTests/testOrchestrator_WallTimeAB_AcrossCorpus")
        #endif

        let cfg = htConfig()
        print("=== v6-alpha6 Phase 1.3 — orchestrator wall-time A/B ===")
        print("(Production threshold lowered to 1 so every fixture exercises GPU path.)")
        print()
        print("| fixture | bytes | CPU ms | GPU ms | Δ % | telemetry |")
        print("|---|---:|---:|---:|---:|:---|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warm-up (both paths).
            _ = try await encodeWithGateState(image, gateOn: false)
            _ = try await encodeWithGateState(image, gateOn: true,
                                              blockThreshold: 1)

            // CPU path.
            var cpuMs: [Double] = []
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encodeWithGateState(image, gateOn: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }

            // GPU path with telemetry capture on the median run.
            var gpuMs: [Double] = []
            J2KGPUForwardHTEntropyTelemetry.reset()
            var bytes = 0
            for _ in 0..<3 {
                let t0 = Date().timeIntervalSinceReferenceDate
                let data = try await encodeWithGateState(image, gateOn: true,
                                                         blockThreshold: 1)
                gpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                bytes = data.count
            }
            let snap = J2KGPUForwardHTEntropyTelemetry.snapshot()

            cpuMs.sort(); gpuMs.sort()
            let cpuMed = cpuMs[1]
            let gpuMed = gpuMs[1]
            let delta = ((cpuMed - gpuMed) / cpuMed) * 100.0
            let blocks = snap.gpuBlocksClassified / max(1, snap.gpuFireCount)
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.1f | %d fires, ~%d blocks/fire |",
                fix.label, bytes, cpuMed, gpuMed, delta,
                snap.gpuFireCount, blocks))
        }

        print()
        print("Reading the table:")
        print("  - Δ% > 0  → GPU path faster than CPU at that fixture")
        print("  - Δ% < 0  → GPU path slower (regression — threshold should")
        print("    skip GPU at that fixture size)")
        print("  - Phase 0.5 dispatch-probe predicted the crossover lives")
        print("    above ~1000 blocks. The fire-count + blocks/fire tell")
        print("    you the actual scale of each fixture's entropy stage.")
    }
}
