// J2KCrossScaleRDQualityProbe.swift
// v5.31.0 investigation — measure roundtrip PSNR across the medical
// corpus at multiple bitrates to characterise whether the encoder's
// λ / bit-allocation model is consistent across image scale.
//
// Hypothesis (from user feedback + MEDICAL_BENCHMARK.md observations):
//   - 12-bit MRI at 0.5 bpp: 42 dB (good, +2.7 dB vs OpenJPEG)
//   - 16-bit CT at 0.5 bpp: 55 dB (-0.3 dB vs OpenJPEG)
//   - 16-bit DX at 2 bpp:  14 dB (catastrophic, observed in v5.30.0)
//
// PSNR should INCREASE with bpp (more bits → less distortion).
// PSNR should be roughly comparable for similar bitdepth across
// modalities.  Anything that violates these expectations indicates
// an inconsistent λ / slope formulation.
//
// This is a probe, not a gate. It prints a table of
//   fixture × bpp → PSNR(dB), encoded bytes
// for human inspection. The fix follows from what the table reveals.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KCrossScaleRDQualityProbe: XCTestCase {

    private struct Probe {
        let name: String
        let path: String
        let bitDepth: Int  // PSNR maxVal = 2^bitDepth - 1
    }

    /// Real fixtures present in the corpus. Bit-depth annotated based
    /// on the file: PGM `maxval` field. Most are 16-bit (maxval ≥
    /// 4096 → 12+ bits); some DICOM-derived images are actually 12 or
    /// 14-bit data padded into 16-bit. We measure PSNR against
    /// 2^16 = 65535 throughout — that's the file format's max; the
    /// codec itself is bitdepth-agnostic, so this is the user-facing
    /// number.
    private static let probes: [Probe] = [
        Probe(name: "mr_002 (180×180 MR)",     path: "mr_study_002_instance_000100.pgm", bitDepth: 16),
        Probe(name: "ct_001 (512×512 CT)",     path: "ct_study_001_instance_000001.pgm", bitDepth: 16),
        Probe(name: "ct_003 (512×512 CT)",     path: "ct_study_003_instance_000050.pgm", bitDepth: 16),
        Probe(name: "mr_001 (886×886 MR)",     path: "mr_study_001_instance_000001.pgm", bitDepth: 16),
        Probe(name: "xa_001 (1024² XA)",       path: "xa_study_001_instance_000001.pgm", bitDepth: 16),
        Probe(name: "px_001 (2459×1316 PX)",   path: "px_study_001_instance_000001.pgm", bitDepth: 16),
        Probe(name: "dx_002 (2800×2288 DX)",   path: "dx_study_002_instance_000001.pgm", bitDepth: 16),
    ]

    /// PGM loader (same as J2KMedicalCorpusPerformanceTests).
    private func loadPGM(_ filename: String) throws -> J2KImage? {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = packageRoot.appendingPathComponent(
            "Tests/Fixtures/CrossCodec/\(filename)")
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

    /// PSNR at the given file-format bit depth (typically 16 for PGM).
    /// Both inputs assumed big-endian 16-bit.
    private func psnr(_ a: Data, _ b: Data, bitDepth: Int) -> (psnr: Double, dataMaxObserved: Int) {
        let aBytes = [UInt8](a)
        let bBytes = [UInt8](b)
        let n = min(aBytes.count, bBytes.count) / 2
        var sumSq: Double = 0
        var observedMax = 0
        for i in 0..<n {
            let av = Int(aBytes[i*2]) * 256 + Int(aBytes[i*2 + 1])
            let bv = Int(bBytes[i*2]) * 256 + Int(bBytes[i*2 + 1])
            if av > observedMax { observedMax = av }
            let d = Double(av - bv)
            sumSq += d * d
        }
        let mse = sumSq / Double(n)
        if mse == 0 { return (.infinity, observedMax) }
        let maxVal = Double((1 << bitDepth) - 1)
        return (10.0 * log10(maxVal * maxVal / mse), observedMax)
    }

    /// Sanity probe: encode dx_002 LOSSLESSLY (5/3 reversible),
    /// decode, verify byte-exact. If this passes, the wavelet +
    /// coefficient pipeline is sound; bugs in the lossy R-D
    /// numbers are isolated to PCRD-opt slope formulation /
    /// quantizer scaling.
    func testDX002LosslessRoundtripExact() async throws {
        guard let img = try loadPGM("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("dx_002 fixture not found")
        }
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
        let decoded = try await J2KDecoder().decode(encoded)
        let p = psnr(img.components[0].data, decoded.components[0].data, bitDepth: 16)
        print("dx_002 lossless: encoded \(encoded.count) bytes; PSNR \(p.psnr) dB; dataMax \(p.dataMaxObserved)")
        XCTAssertTrue(p.psnr.isInfinite || p.psnr > 100,
            "Lossless should give infinite PSNR; got \(p.psnr)")
    }

    /// Compare `.constantBitrate` (PCRD-opt, all-or-nothing per HT
    /// conformant block) vs `.constantBitrateViaQstep` (binary-search
    /// qstep to hit target). The v5.16.0 R-D gap on conformant
    /// cleanup-only HT was diagnosed as a granularity issue: PCRD
    /// can't truncate within a single-pass HT block, so per-block
    /// include/exclude decisions become discrete. constantBitrateViaQstep
    /// is the workaround — uniform quantization tuned to the budget.
    /// If this mode produces consistent quality across scale, the
    /// fix is to make it the default for HT-conformant lossy. If it
    /// also produces scale-dependent quality, the bug is elsewhere.
    func testCrossScaleQstepVsPCRD() async throws {
        let bpps: [Double] = [0.5, 1.0, 2.0, 4.0]
        struct Row {
            let name: String
            let pixels: Int
            let pcrdAt: [Double: Double]
            let qstepAt: [Double: Double]
            let qstepBytesAt: [Double: Int]
        }
        var rows: [Row] = []
        for probe in Self.probes {
            guard let img = try loadPGM(probe.path) else { continue }
            var pcrdAt: [Double: Double] = [:]
            var qstepAt: [Double: Double] = [:]
            var qstepBytesAt: [Double: Int] = [:]
            for bpp in bpps {
                // PCRD path
                var cfg1 = J2KEncodingConfiguration(
                    quality: 1.0, lossless: false,
                    decompositionLevels: 5, qualityLayers: 1,
                    progressionOrder: .lrcp, useHTJ2K: true,
                    useReversibleFilter: false,
                    htj2kBlockFormat: .conformant)
                cfg1.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
                let enc1 = try await J2KEncoder(encodingConfiguration: cfg1).encode(img)
                let dec1 = try await J2KDecoder().decode(enc1)
                pcrdAt[bpp] = psnr(img.components[0].data, dec1.components[0].data, bitDepth: 16).psnr

                // Qstep-search path
                var cfg2 = cfg1
                cfg2.bitrateMode = .constantBitrateViaQstep(bitsPerPixel: bpp)
                let enc2 = try await J2KEncoder(encodingConfiguration: cfg2).encode(img)
                let dec2 = try await J2KDecoder().decode(enc2)
                qstepAt[bpp] = psnr(img.components[0].data, dec2.components[0].data, bitDepth: 16).psnr
                qstepBytesAt[bpp] = enc2.count
            }
            rows.append(Row(name: probe.name, pixels: img.width * img.height,
                            pcrdAt: pcrdAt, qstepAt: qstepAt, qstepBytesAt: qstepBytesAt))
        }
        print("=== v5.31.0 PCRD-opt vs constantBitrateViaQstep ===")
        print("PSNR (dB), \"PCRD\" = .constantBitrate, \"Qstep\" = .constantBitrateViaQstep")
        print("| Fixture | px | PCRD@0.5 | Qstep@0.5 | PCRD@1.0 | Qstep@1.0 | PCRD@2.0 | Qstep@2.0 | PCRD@4.0 | Qstep@4.0 |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        let f: (Double) -> String = { p in p.isInfinite ? "∞" : String(format: "%.2f", p) }
        for r in rows {
            print(String(format: "| %@ | %d | %@ | %@ | %@ | %@ | %@ | %@ | %@ | %@ |",
                         r.name, r.pixels,
                         f(r.pcrdAt[0.5]!), f(r.qstepAt[0.5]!),
                         f(r.pcrdAt[1.0]!), f(r.qstepAt[1.0]!),
                         f(r.pcrdAt[2.0]!), f(r.qstepAt[2.0]!),
                         f(r.pcrdAt[4.0]!), f(r.qstepAt[4.0]!)))
        }
        XCTAssertFalse(rows.isEmpty)
    }

    /// Sweep each fixture × bpp ∈ {0.5, 1.0, 2.0, 4.0}; measure PSNR
    /// of CPU encode → CPU decode roundtrip. Print table.
    func testCrossScaleRDPSNRSweep() async throws {
        let bpps: [Double] = [0.5, 1.0, 2.0, 4.0]

        struct Row {
            let name: String
            let pixels: Int
            let dataMax: Int    // observed max value in source — tells us actual bit depth
            let psnrAt: [Double: Double]  // bpp → PSNR
            let bytesAt: [Double: Int]    // bpp → encoded byte count
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for probe in Self.probes {
            guard let img = try loadPGM(probe.path) else {
                skipped.append(probe.name)
                continue
            }

            var psnrAt = [Double: Double]()
            var bytesAt = [Double: Int]()
            var dataMax = 0

            for bpp in bpps {
                var cfg = J2KEncodingConfiguration(
                    quality: 1.0, lossless: false,
                    decompositionLevels: 5, qualityLayers: 1,
                    progressionOrder: .lrcp, useHTJ2K: true,
                    useReversibleFilter: false,
                    htj2kBlockFormat: .conformant)
                cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)

                let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
                let decoded = try await J2KDecoder().decode(encoded)
                let p = psnr(img.components[0].data, decoded.components[0].data, bitDepth: 16)
                psnrAt[bpp] = p.psnr
                bytesAt[bpp] = encoded.count
                dataMax = max(dataMax, p.dataMaxObserved)
            }

            rows.append(Row(
                name: probe.name,
                pixels: img.width * img.height,
                dataMax: dataMax,
                psnrAt: psnrAt,
                bytesAt: bytesAt))
        }

        print("=== v5.31.0 cross-scale R-D quality probe ===")
        print("HT-conformant lossy 9/7, 5 levels. PSNR computed against 16-bit max (65535).")
        print("dataMax = max observed pixel value in source (reveals true bit depth: < 4096 = 12-bit, < 16384 = 14-bit, ≥ 16384 = up to 16-bit).")
        if !skipped.isEmpty {
            print("Skipped: \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | dataMax | PSNR @0.5 | PSNR @1.0 | PSNR @2.0 | PSNR @4.0 |")
        print("|---|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let psnrFmt: (Double) -> String = { p in
                p.isInfinite ? "∞" : String(format: "%.2f", p)
            }
            print(String(format: "| %@ | %d | %d | %@ | %@ | %@ | %@ |",
                         r.name,
                         r.pixels,
                         r.dataMax,
                         psnrFmt(r.psnrAt[0.5]!),
                         psnrFmt(r.psnrAt[1.0]!),
                         psnrFmt(r.psnrAt[2.0]!),
                         psnrFmt(r.psnrAt[4.0]!)))
        }
        print("")
        print("Encoded bytes per fixture × bpp:")
        print("| Fixture | @0.5 | @1.0 | @2.0 | @4.0 |")
        print("|---|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %d | %d | %d |",
                         r.name,
                         r.bytesAt[0.5]!,
                         r.bytesAt[1.0]!,
                         r.bytesAt[2.0]!,
                         r.bytesAt[4.0]!))
        }

        XCTAssertFalse(rows.isEmpty)
    }
}
