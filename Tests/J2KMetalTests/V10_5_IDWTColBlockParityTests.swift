// V10_5_IDWTColBlockParityTests.swift
//
// v10.5-research Phase 3 — bit-exact parity gate for the column-block
// IDWT path. Toggles `J2KDWT2DOptimizer.columnBlockLiftEnabled` and
// decodes the real MG / DX / PX medical corpus through the lossless
// 5/3 HT-conformant path. Asserts every output byte matches between
// the canonical (transpose) path and the column-block path.
//
// Runs with:
//   swift test -c release --filter V10_5_IDWTColBlockParityTests
//
// This is the gate the warm A/B bench depends on — any mismatch
// here means the column-block path can't ship default-on.

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class V10_5_IDWTColBlockParityTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    /// Real medical corpus — MG, DX, PX — the fixtures we expect
    /// the column-block path to most benefit (largest level-1
    /// working sets).
    private static let corpus: [Fixture] = [
        // MG (mammography, ~16.8 MP, 5-level IDWT exercises every
        // pyramid level all the way down).
        Fixture(label: "MG small 3516×4784",
                filename: "medical-real/mg_real_small_3516x4784.pgm"),
        Fixture(label: "MG mid 3518×4784",
                filename: "medical-real/mg_real_mid_3518x4784.pgm"),
        Fixture(label: "MG large 3521×4784",
                filename: "medical-real/mg_real_large_3521x4784.pgm"),
        // DX (chest X-ray, ~6-8 MP).
        Fixture(label: "DX 2800×2288",
                filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX small 2224×2798",
                filename: "medical-real/dx_real_small_2224x2798.pgm"),
        Fixture(label: "DX large 2544×3056",
                filename: "medical-real/dx_real_large_2544x3056.pgm"),
        // PX (panoramic dental, ~3-4 MP, wide aspect ratio).
        Fixture(label: "PX 2459×1316",
                filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX large 2812×1316",
                filename: "medical-real/px_real_large_2812x1316.pgm"),
        // Plus small fixtures to make sure the gate doesn't break
        // anything below the 32×32 floor.
        Fixture(label: "MR-small 180²",
                filename: "mr_study_002_instance_000100.pgm"),
        Fixture(label: "CT 512²",
                filename: "ct_study_001_instance_000001.pgm"),
    ]

    private func loadPGM16(_ filename: String) throws -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path) else { return nil }
        let raw = try Data(contentsOf: here)
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
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

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Decode each corpus fixture with `columnBlockLiftEnabled = false`
    /// and then again with `= true`. Every output byte must match.
    func testColumnBlockLift_BitExactVsCanonical_MedicalCorpus() async throws {
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        var compared = 0
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label)
                continue
            }
            let codestream = try await encoder.encode(image)

            // Canonical path — transpose + stride-1 lift + untranspose.
            J2KDWT2DOptimizer.columnBlockLiftEnabled = false
            let canonical = try await decoder.decode(codestream)

            // Probe path — row-major column-block lift.
            J2KDWT2DOptimizer.columnBlockLiftEnabled = true
            let probe = try await decoder.decode(codestream)

            XCTAssertEqual(canonical.width, probe.width,
                "Width mismatch on \(fix.label)")
            XCTAssertEqual(canonical.height, probe.height,
                "Height mismatch on \(fix.label)")
            XCTAssertEqual(canonical.components.count, probe.components.count,
                "Component count mismatch on \(fix.label)")
            for (i, (cComp, pComp)) in zip(canonical.components, probe.components).enumerated() {
                XCTAssertEqual(cComp.data, pComp.data,
                    "Component \(i) bytes diverged on \(fix.label) " +
                    "(\(cComp.data.count) vs \(pComp.data.count) bytes)")
            }
            compared += 1
        }

        // Restore default ON for downstream tests.
        J2KDWT2DOptimizer.columnBlockLiftEnabled = true

        XCTAssertGreaterThan(compared, 0,
            "Parity gate didn't compare any fixtures — corpus path layout changed?")
        if !skipped.isEmpty {
            print("V10_5 column-block parity gate: skipped (fixture missing): \(skipped.joined(separator: ", "))")
        }
        print("V10_5 column-block parity gate: \(compared) fixture(s) bit-exact ✓")
    }

    /// Synthetic edge-case parity — odd-row, odd-col, tile-boundary
    /// sizes that exercise the column-block path's parity branches
    /// (even/odd evenRows/oddRows asymmetries on boundary rows).
    func testColumnBlockLift_BitExactVsCanonical_SyntheticEdgeCases() async throws {
        let edgeCases: [(Int, Int, String)] = [
            (33, 33, "odd-square 33×33"),
            (64, 65, "even-w odd-h 64×65"),
            (65, 64, "odd-w even-h 65×64"),
            (127, 129, "near-pow2 127×129"),
            (513, 511, "off-by-one 513×511"),
            (1023, 1025, "near-1024 1023×1025"),
        ]
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        for (w, h, label) in edgeCases {
            // Deterministic synthetic image.
            var bytes = [UInt8](repeating: 0, count: w * h * 2)
            var s: UInt64 = 0xdead_beef_cafe_babe
            for i in 0..<(w * h) {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let v = Int(s >> 48) & 0xFFFF
                bytes[i * 2]     = UInt8((v >> 8) & 0xFF)
                bytes[i * 2 + 1] = UInt8(v & 0xFF)
            }
            let image = J2KImage(
                width: w, height: h,
                components: [J2KComponent(
                    index: 0, bitDepth: 16, signed: false,
                    width: w, height: h,
                    data: Data(bytes), sampleByteOrder: .bigEndian)])
            let codestream = try await encoder.encode(image)

            J2KDWT2DOptimizer.columnBlockLiftEnabled = false
            let canonical = try await decoder.decode(codestream)
            J2KDWT2DOptimizer.columnBlockLiftEnabled = true
            let probe = try await decoder.decode(codestream)

            XCTAssertEqual(canonical.components[0].data, probe.components[0].data,
                "Synthetic edge case \(label) diverged")
        }
        J2KDWT2DOptimizer.columnBlockLiftEnabled = true
        print("V10_5 column-block parity gate (synthetic edge cases): 6/6 bit-exact ✓")
    }
}
