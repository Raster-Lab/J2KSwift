// V11_0_1_EncodeLazyMetalProbeBenchTests.swift
// v11.0.1 — warm in-proc A/B driver for the lazy Metal-availability
// probe on the encode-side GPU forward 5/3 gate.
//
// The v11.0.0 cold+warm report found cold one-shot `j2k encode` pays
// a ~40-75 ms wall floor even at 174×192 because the forward-DWT gate
// evaluated `J2KMetalDWT.isAvailable` (→ `MTLCreateSystemDefaultDevice()`,
// ~40-75 ms in a fresh process) BEFORE the pixel-threshold short-circuit.
// The fix mirrors the decode-side v8 Phase 1 reorder: the availability
// probe only fires when `_gpuForward53Enabled` + pixel thresholds would
// actually route the dispatch to the GPU.
//
// This bench is the warm-side acceptance driver: production HT-lossless
// encode on the medical-real DX/MG fixtures, 2 warmups + median of 7.
// Run it on the baseline and the fixed tree; medians must agree within
// the v7.4 3 ms gate and the printed SHA-256 digests must be identical
// (codestream bytes unchanged).
//
//   swift test -c release --filter V11_0_1_EncodeLazyMetalProbeBench
//
// MEASUREMENT test — prints a table, no perf assertions. Byte-level
// correctness is asserted via the digest stability across runs within
// this process; cross-build identity is compared by hand in the A/B.

import XCTest
import Foundation
import CryptoKit
@testable import J2KCore
@testable import J2KCodec

final class V11_0_1_EncodeLazyMetalProbeBenchTests: XCTestCase {

    private func loadMedicalRealPGM(_ filename: String) throws -> J2KImage? {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/medical-real/\(filename)")
        guard FileManager.default.fileExists(atPath: fixture.path) else { return nil }
        let data = try Data(contentsOf: fixture)
        var i = 2
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 { while i < data.count, data[i] != 0x0A { i += 1 }; continue }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { i += 1; continue }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < data.count, [0x20, 0x09, 0x0A, 0x0D].contains(data[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: data.subdata(in: i..<data.count),
                sampleByteOrder: .bigEndian)])
    }

    /// Production HT-lossless shape — the config the CLI default and
    /// the DICOM archive path use, and the only shape that reaches
    /// the reversible 5/3 INT forward-DWT gate this change touches.
    private func losslessConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    func testWarmLosslessEncodeMedians_DX_MG() async throws {
        let fixtures: [(label: String, file: String)] = [
            ("DX mid 2800×2288",  "dx_real_mid_2800x2288.pgm"),
            ("DX large 2544×3056", "dx_real_large_2544x3056.pgm"),
            ("MG mid 3518×4784",  "mg_real_mid_3518x4784.pgm"),
            ("MG large 3521×4784", "mg_real_large_3521x4784.pgm"),
        ]
        let cfg = losslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let warmups = 2, runs = 7

        print("\n=== v11.0.1 warm in-proc HT-lossless encode (warmups=\(warmups), median of \(runs)) ===")
        print("| fixture | median ms | min ms | max ms | bytes | sha256-12 |")
        print("|---|---:|---:|---:|---:|---|")
        for f in fixtures {
            guard let image = try loadMedicalRealPGM(f.file) else {
                throw XCTSkip("fixture \(f.file) not present")
            }
            var digest: String = ""
            var byteCount = 0
            for _ in 0..<warmups {
                let d = try await encoder.encode(image)
                digest = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined().prefix(12).lowercased()
                byteCount = d.count
            }
            var walls: [Double] = []
            for _ in 0..<runs {
                let t0 = DispatchTime.now()
                let d = try await encoder.encode(image)
                walls.append(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6)
                let runDigest = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined().prefix(12).lowercased()
                XCTAssertEqual(runDigest, digest, "\(f.label): encode bytes unstable across warm runs")
            }
            walls.sort()
            print("| \(f.label) | \(String(format: "%.2f", walls[runs / 2])) | \(String(format: "%.2f", walls.first!)) | \(String(format: "%.2f", walls.last!)) | \(byteCount) | \(digest) |")
        }
        print("(A/B: run on baseline + fixed tree; medians within 3 ms, digests identical)\n")
    }
}
