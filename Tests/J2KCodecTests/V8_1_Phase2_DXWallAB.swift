// V8_1_Phase2_DXWallAB.swift
//
// v8.1 Phase 2 — end-to-end DX 2800×2288 in-process decode A/B.
// Three legs: scalar reference, v7.4 4-byte SWAR (production
// default), v8.1 8-byte SWAR (opt-in).
//
// Acceptance criterion (per v7.4 release-notes discipline carried
// forward as `feedback_commit_gate.md` / `feedback_v6_alpha4_lever_ceiling.md`
// and re-stated in V8_1_0_PHASE_1B_FINDING.md):
//
//   v8.1 (8-byte) must beat v7.4 (4-byte) by ≥ 3 ms median DX
//   in-process decode wall to justify flipping
//   `swarRefill8Enabled` to `true` by default in Phase 3.
//
// If the measured Δ is < 3 ms, the flag stays default OFF and
// the v8.1 path remains opt-in. Document the wash, archive the
// finding, and move on.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V8_1_Phase2_DXWallAB: XCTestCase {

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

    private func medianMs(
        _ runs: Int, _ body: () async throws -> Void
    ) async throws -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            try await body()
            let t1 = Date().timeIntervalSinceReferenceDate
            samples.append((t1 - t0) * 1000.0)
        }
        samples.sort()
        return samples[runs / 2]
    }

    func testDXInProcessWall_ScalarVsV74VsV81() async throws {
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX fixture not present")
        }
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let codestream = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)

        let runs = 5
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        let prevV74 = HTMagSgnDecoderConformant.neonRefillEnabled
        defer {
            HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8
            HTMagSgnDecoderConformant.neonRefillEnabled = prevV74
        }

        // Warmup — pull Metal cold-start, JIT, etc. out of the
        // first measurement.
        _ = try await J2KDecoder().decode(codestream)
        _ = try await J2KDecoder().decode(codestream)

        // Leg 1: scalar reference (both flags off).
        HTMagSgnDecoderConformant.swarRefill8Enabled = false
        HTMagSgnDecoderConformant.neonRefillEnabled = false
        let scalar = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(codestream)
        }

        // Leg 2: v7.4 4-byte SWAR (production default — flag OFF).
        HTMagSgnDecoderConformant.swarRefill8Enabled = false
        HTMagSgnDecoderConformant.neonRefillEnabled = true
        let v74 = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(codestream)
        }

        // Leg 3: v8.1 8-byte SWAR (opt-in).
        HTMagSgnDecoderConformant.swarRefill8Enabled = true
        HTMagSgnDecoderConformant.neonRefillEnabled = true
        let v81 = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(codestream)
        }

        let delta_v74_v81 = v74 - v81
        let pct_v74_v81 = delta_v74_v81 / v74 * 100.0
        let delta_scalar_v81 = scalar - v81
        let pct_scalar_v81 = delta_scalar_v81 / scalar * 100.0

        print("=== v8.1 Phase 2 DX in-process MagSgn refill A/B (median of \(runs)) ===")
        print(String(format: "  Image:           %d × %d", image.width, image.height))
        print(String(format: "  Codestream:      %d bytes", codestream.count))
        print()
        print(String(format: "  Scalar refill:        %.2f ms", scalar))
        print(String(format: "  v7.4 4-byte SWAR:     %.2f ms", v74))
        print(String(format: "  v8.1 8-byte SWAR:     %.2f ms", v81))
        print()
        print(String(format: "  v7.4 → v8.1 Δ:        %.2f ms (%+.1f %%)",
            delta_v74_v81, pct_v74_v81))
        print(String(format: "  Scalar → v8.1 Δ:      %.2f ms (%+.1f %%)",
            delta_scalar_v81, pct_scalar_v81))
        print()
        print("Acceptance: Δ (v7.4 → v8.1) must be ≥ 3 ms to flip default ON in Phase 3.")
        if delta_v74_v81 >= 3.0 {
            print(String(format: "  ⇒ PASS — Δ %.2f ms ≥ 3 ms threshold; GREENLIGHT Phase 3.",
                delta_v74_v81))
        } else {
            print(String(format: "  ⇒ WASH — Δ %.2f ms < 3 ms threshold; flag stays default OFF.",
                delta_v74_v81))
        }
    }
}
