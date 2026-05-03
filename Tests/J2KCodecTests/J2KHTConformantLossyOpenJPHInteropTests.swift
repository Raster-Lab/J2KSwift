// J2KHTConformantLossyOpenJPHInteropTests.swift
// v5.16.0 regression gate — lossy HT conformant must produce
// codestreams that ojph_expand decodes to the same quality as
// J2KSwift's own decoder.
//
// Pre-v5.16.0 bug: the lossy K_max formula in encodeCodeBlockConformant
// used `bandKb - guardBits + 1` (correct for lossless via the v5.1.1
// conformant ε bias) but mismatched the Part-15 decoder's formula
// `K_max = ε + guardBits - 1` for lossy mode (where the ε bias is not
// applied — see writeQCDMarker:3596 reversible-only gate). Result:
// J2KSwift's encoder shifted magnitudes one bit lower than any
// Part-15 decoder expected. J2KSwift's own decoder mirrored the wrong
// shift via packet-header `missing_msbs`, so self-round-trip looked
// reasonable. ojph_expand applied the SPEC shift and decoded ~10 dB
// of garbage at high bpp (18 dB on 16-bit CT @ 8 bpp).
//
// v5.16.0 fix: split conformant K_max by useReversibleFilter — lossy
// uses K_max = bandKb to match the spec ε formula. After the fix,
// ojph_expand decodes lossy HT conformant at the same quality as
// J2KSwift's own decoder. This test gates that.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class HTConformantLossyOpenJPHInteropTests: XCTestCase {

    private let ojphExpand = "/opt/homebrew/bin/ojph_expand"

    private func skipIfMissing() throws {
        guard FileManager.default.isExecutableFile(atPath: ojphExpand) else {
            throw XCTSkip("ojph_expand not found — interop test skipped")
        }
    }

    /// Encode a synth medical image at varying bpps with HT conformant
    /// lossy, decode with both J2KSwift and ojph_expand. The two
    /// PSNRs must be within 0.5 dB of each other — i.e., the
    /// codestream must transmit the same precision interpretation
    /// regardless of which Part-15 decoder reads it.
    func testLossyHTConformant_OJPHDecodeMatchesJ2KSwiftDecode() async throws {
        try skipIfMissing()

        // Synth 16-bit medical-style image. Same construction as
        // HTConformantPipelineNonPowerOf2Tests for consistency.
        let width = 256
        let height = 256
        let bitDepth = 16
        let bytesPerSample = 2
        let count = width * height
        let maxVal = (1 << bitDepth) - 1
        var s: UInt64 = 0xfeed_face_dead_beef
        var bytes = [UInt8](repeating: 0, count: count * bytesPerSample)
        for i in 0..<count {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let x = i % width
            let y = i / width
            let gradient = (x * 31 + y * 17) & maxVal
            let noise = Int(s >> 40) & maxVal
            let sample = (gradient ^ noise) & maxVal
            bytes[i * 2]     = UInt8((sample >> 8) & 0xFF)
            bytes[i * 2 + 1] = UInt8(sample & 0xFF)
        }
        let inputData = Data(bytes)
        let component = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height, data: inputData,
            sampleByteOrder: .bigEndian)
        let image = J2KImage(width: width, height: height, components: [component])

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("J2K_v5_16_lossy_interop_\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Test at three bpp targets that exercise different rate-control
        // regimes. At 8 bpp every block fits; at 4 bpp PCRD truncation
        // dominates; at 1 bpp PCRD must be aggressive.
        var failures: [String] = []
        for bpp in [1.0, 4.0, 8.0] {
            var cfg = J2KEncodingConfiguration(
                quality: 1.0, lossless: false,
                decompositionLevels: 5,
                qualityLayers: 1,
                progressionOrder: .lrcp,
                useHTJ2K: true)
            cfg.useReversibleFilter = false
            cfg.htj2kBlockFormat = .conformant
            cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)

            let encoded: Data
            do {
                encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
            } catch {
                XCTFail("encode @ \(bpp) bpp failed: \(error)")
                continue
            }

            // Decode with J2KSwift
            let jswImage: J2KImage
            do {
                jswImage = try await J2KDecoder().decode(encoded)
            } catch {
                XCTFail("J2KSwift decode @ \(bpp) bpp failed: \(error)")
                continue
            }
            let jswPSNR = computePSNR16(orig: inputData, rec: jswImage.components[0].data, peak: maxVal)

            // Decode with ojph_expand
            let cellId = "bpp\(bpp)"
            let j2cURL = scratch.appendingPathComponent("\(cellId).j2c")
            let pgmURL = scratch.appendingPathComponent("\(cellId).pgm")
            try encoded.write(to: j2cURL)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ojphExpand)
            proc.arguments = ["-i", j2cURL.path, "-o", pgmURL.path]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                XCTFail("ojph_expand failed @ \(bpp) bpp: \(log)")
                continue
            }
            let pgmData = try Data(contentsOf: pgmURL)
            guard let payload = stripPGMHeader(pgmData) else {
                XCTFail("PGM header parse failed @ \(bpp) bpp")
                continue
            }
            let ojphPSNR = computePSNR16(orig: inputData, rec: payload, peak: maxVal)

            let delta = abs(jswPSNR - ojphPSNR)
            print("LOSSY_INTEROP @ \(bpp) bpp: J2KSwift=\(String(format: "%.2f", jswPSNR)) dB, ojph_expand=\(String(format: "%.2f", ojphPSNR)) dB, |Δ|=\(String(format: "%.3f", delta)) dB, encoded=\(encoded.count) bytes")

            // Allow 0.5 dB tolerance for floating-point and dequantizer
            // micro-differences. Pre-v5.16.0 the gap was 40+ dB.
            if delta > 0.5 {
                failures.append("@ \(bpp) bpp: J2KSwift=\(jswPSNR) dB, ojph=\(ojphPSNR) dB, |Δ|=\(delta) dB > 0.5 dB tolerance")
            }
        }
        if !failures.isEmpty {
            XCTFail("Lossy HT conformant cross-decode interop broken: " + failures.joined(separator: "; "))
        }
    }

    // MARK: helpers

    private func stripPGMHeader(_ data: Data) -> Data? {
        guard data.count > 4, data[0] == 0x50, data[1] == 0x35 else {
            return nil
        }
        var i = 2
        var fieldsConsumed = 0
        while i < data.count, fieldsConsumed < 3 {
            let b = data[i]
            if b == 0x23 {
                while i < data.count, data[i] != 0x0A { i += 1 }
                continue
            }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                i += 1
                continue
            }
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    break
                }
                i += 1
            }
            fieldsConsumed += 1
        }
        while i < data.count {
            let b = data[i]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                i += 1
                break
            }
            i += 1
        }
        guard i <= data.count else { return nil }
        return data.subdata(in: i..<data.count)
    }

    private func computePSNR16(orig: Data, rec: Data, peak: Int) -> Double {
        let count = min(orig.count, rec.count) / 2
        guard count > 0 else { return -.infinity }
        let origBytes = [UInt8](orig)
        let recBytes  = [UInt8](rec)
        var sse: Double = 0
        for i in 0..<count {
            let o = (Int(origBytes[i * 2]) << 8) | Int(origBytes[i * 2 + 1])
            let r = (Int(recBytes[i * 2]) << 8) | Int(recBytes[i * 2 + 1])
            let d = Double(o - r)
            sse += d * d
        }
        if sse == 0 { return .infinity }
        let mse = sse / Double(count)
        return 10.0 * log10(Double(peak) * Double(peak) / mse)
    }
}
