// JP3DHTJ2KvsEBCOTByteSizeProbeTests.swift
//
// Investigation probe — captures empirical data on the open
// follow-up flagged in `project_jp3d_beat_openjpeg.md`:
//
//   "HTJ2K mode (htj2k-lossless) currently produces *larger*
//    output than EBCOT (j2k-lossless) on full 16-bit medical
//    content. Investigate whether HTJ2K's k_max overflow path
//    interacts with slice-stack inputs."
//
// Two probes:
//
//   1. **2D codec parity** — encode a 16-bit medical PGM directly
//      through `J2KEncoder` with HTJ2K vs EBCOT. Confirms whether
//      the regression is in the 2D codec itself (independent of
//      JP3D) or specific to slice-stack wrapping.
//
//   2. **JP3D slice-stack** — same volume encoded through
//      `JP3DEncoder` in HTJ2K vs EBCOT lossless presets. The
//      delta between HTJ2K and EBCOT here vs the 2D delta
//      isolates per-slice overhead vs codec-level overhead.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2K3D

final class JP3DHTJ2KvsEBCOTByteSizeProbeTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let fixtures: [Fixture] = [
        Fixture(label: "MR-small 180²", filename: "mr_study_002_instance_000100.pgm"),
        Fixture(label: "CT 512²",       filename: "ct_study_001_instance_000001.pgm"),
        Fixture(label: "MR 886²",       filename: "mr_study_001_instance_000001.pgm"),
        Fixture(label: "XA 1024²",      filename: "xa_study_001_instance_000001.pgm"),
        Fixture(label: "PX 2459×1316",  filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "DX 2800×2288",  filename: "dx_study_002_instance_000001.pgm"),
    ]

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

    func test2DCodec_EBCOTvsHTJ2K_LosslessByteSize() async throws {
        print("=== 2D codec — EBCOT vs HTJ2K lossless byte size ===")
        print("(Same J2KEncoder, useHTJ2K toggled. useReversibleFilter=true, qualityLayers=1.)")
        print()
        print("| fixture | EBCOT bytes | HTJ2K bytes | Δ bytes | HTJ2K/EBCOT |")
        print("|---|---:|---:|---:|---:|")

        for fix in Self.fixtures {
            guard let image = loadPGM16(fix.filename) else { continue }

            let ebcotCfg = J2KEncodingConfiguration(
                quality: 1.0, lossless: true, qualityLayers: 1,
                useHTJ2K: false, useReversibleFilter: true)
            let htj2kCfg = J2KEncodingConfiguration(
                quality: 1.0, lossless: true, qualityLayers: 1,
                useHTJ2K: true, useReversibleFilter: true,
                htj2kBlockFormat: .conformant)

            let ebcotBytes = try await J2KEncoder(encodingConfiguration: ebcotCfg).encode(image)
            let htj2kBytes = try await J2KEncoder(encodingConfiguration: htj2kCfg).encode(image)

            let delta = htj2kBytes.count - ebcotBytes.count
            let ratio = Double(htj2kBytes.count) / Double(ebcotBytes.count)
            print(String(format: "| %@ | %d | %d | %+d | %.3f× |",
                fix.label, ebcotBytes.count, htj2kBytes.count, delta, ratio))
        }
        print()
        print("Reading: ratio > 1.0 means HTJ2K is LARGER than EBCOT (regression).")
        print("If every row's ratio is > 1.0, the issue is in the 2D codec, not JP3D.")
    }
}
