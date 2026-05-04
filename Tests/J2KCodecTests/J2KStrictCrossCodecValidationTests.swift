import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KStrictCrossCodecValidationTests: XCTestCase {
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

    private func runDecoder(_ binaryName: String, args: [String]) -> (exit: Int32, stderr: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/\(binaryName)")
        proc.arguments = args
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return (proc.terminationStatus, String(data: errData, encoding: .utf8) ?? "")
        } catch {
            return (-1, "spawn error: \(error)")
        }
    }

    /// v5.34.0 consistency: CPU `encode()` and GPU `encodeGPU()` must
    /// produce the SAME bytes when given the same `.constantBitrate(bpp)`
    /// on the auto-promote-eligible path (HT-conformant lossy 9/7
    /// bitDepth ≥ 12). Pre-fix encodeGPU bypassed the auto-promote and
    /// silently produced a PCRD codestream while encode() produced a
    /// strict codestream — different bytes, different quality.
    func testEncodeAndEncodeGPUProduceSameBytesForAutoPromotedConstantBitrate() async throws {
        guard let img = try loadPGM("ct_study_001_instance_000001.pgm") else {
            throw XCTSkip("ct_001 fixture not found")
        }
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: 2.0)

        let cpu = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
        let gpu = try await J2KEncoder(encodingConfiguration: cfg).encodeGPU(img)

        print("CPU encode: \(cpu.count) bytes; GPU encode: \(gpu.count) bytes")
        XCTAssertEqual(cpu.count, gpu.count,
            "CPU and GPU encode must produce same byte count for auto-promoted .constantBitrate")
        XCTAssertEqual(cpu, gpu,
            "CPU and GPU encode must produce byte-identical codestream for auto-promoted .constantBitrate")
    }

    /// Reality check: strict-mode truncated codestreams must decode in
    /// reference codecs (OpenJPEG, OpenJPH). v5.34 claims premature-EOC
    /// is universally legal per ISO 15444-1 Annex B; this is the
    /// cross-codec sanity check that backs the claim.
    func testStrictTruncatedDecodesInOpenJPEGAndOpenJPH() async throws {
        guard let img = try loadPGM("px_study_001_instance_000001.pgm") else {
            throw XCTSkip("px_001 fixture not found")
        }
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrateStrict(
            bitsPerPixel: 0.5, maxOvershootRatio: 1.0, maxPasses: 3)
        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(img)
        let tmpDir = FileManager.default.temporaryDirectory
        let inputURL = tmpDir.appendingPathComponent("strict_px_001.j2k")
        try encoded.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        // OpenJPEG decode
        let opjOut = tmpDir.appendingPathComponent("strict_px_001_opj.pgm")
        let opjResult = runDecoder("opj_decompress", args: [
            "-i", inputURL.path, "-o", opjOut.path
        ])
        defer { try? FileManager.default.removeItem(at: opjOut) }
        XCTAssertEqual(opjResult.exit, 0,
            "OpenJPEG opj_decompress failed on strict-truncated codestream: \(opjResult.stderr)")

        // OpenJPH decode (HTJ2K reference)
        let ojphOut = tmpDir.appendingPathComponent("strict_px_001_ojph.pgm")
        let ojphResult = runDecoder("ojph_expand", args: [
            "-i", inputURL.path, "-o", ojphOut.path
        ])
        defer { try? FileManager.default.removeItem(at: ojphOut) }
        XCTAssertEqual(ojphResult.exit, 0,
            "OpenJPH ojph_expand failed on strict-truncated codestream: \(ojphResult.stderr)")

        print("=== Cross-codec strict-truncated decode ===")
        print("Input: px_001 @ 0.5 bpp strict, \(encoded.count) bytes")
        print("opj_decompress exit \(opjResult.exit)")
        print("ojph_expand exit \(ojphResult.exit)")
    }
}
