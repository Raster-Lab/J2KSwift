// v8 Phase 6.2 — gated to macOS: invokes external CLIs via Process() (unavailable on iOS).
#if os(macOS)
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
    /// reference codecs (OpenJPEG, OpenJPH, Grok). v5.34 claims
    /// premature-EOC is universally legal per ISO 15444-1 Annex B;
    /// this is the cross-codec sanity check that backs the claim.
    /// v5.35.0 expanded the validation set to include Grok
    /// (libgrokj2k v20.3.0) — a third independent JPEG 2000
    /// implementation with its own HT (Part 15) support.
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

        // Grok decode (third independent codec, libgrokj2k v20.3.0)
        let grkOut = tmpDir.appendingPathComponent("strict_px_001_grk.pgm")
        let grkResult = runDecoder("grk_decompress", args: [
            "-i", inputURL.path, "-o", grkOut.path
        ])
        defer { try? FileManager.default.removeItem(at: grkOut) }
        XCTAssertEqual(grkResult.exit, 0,
            "Grok grk_decompress failed on strict-truncated codestream: \(grkResult.stderr)")

        print("=== Cross-codec strict-truncated decode ===")
        print("Input: px_001 @ 0.5 bpp strict, \(encoded.count) bytes")
        print("opj_decompress exit \(opjResult.exit)")
        print("ojph_expand exit \(ojphResult.exit)")
        print("grk_decompress exit \(grkResult.exit)")
    }

    /// DICOM Pixel Data round-trip: a JPEG 2000-compressed DICOM image
    /// stores the codestream inside a Pixel Data sequence — each frame
    /// is an item with the byte format `[FFFE E000][LL LL LL LL][raw J2K
    /// codestream]`. The codestream travels verbatim; the decapsulator
    /// reads `length` bytes after the item tag and feeds them to a
    /// JPEG 2000 decoder.
    ///
    /// This test simulates that round-trip without a full DICOM stack:
    /// (1) encode → (2) wrap in synthetic DICOM Pixel Data item bytes →
    /// (3) parse the item back out → (4) decode the unwrapped codestream
    /// in J2KSwift and OpenJPEG. Validates that the strict codestream
    /// is byte-clean for DICOM Transfer Syntax UID 1.2.840.10008.1.2.4.90
    /// (JPEG 2000 Image Compression).
    func testStrictCodestreamSurvivesDICOMPixelDataRoundTrip() async throws {
        guard let img = try loadPGM("ct_study_001_instance_000001.pgm") else {
            throw XCTSkip("ct_001 fixture not found")
        }
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrateStrict(
            bitsPerPixel: 1.0, maxOvershootRatio: 1.0, maxPasses: 3)
        let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(img)

        // Wrap: DICOM Pixel Data item = tag (FFFE E000) + length (4 BE) + bytes.
        // DICOM uses little-endian for the item tag/length per the standard
        // explicit-VR transfer syntaxes; pad to even length per DICOM.
        var wrapped = Data()
        wrapped.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0]) // Item tag (little-endian)
        let paddedLen = (codestream.count + 1) & ~1  // round up to even
        let len = UInt32(paddedLen)
        wrapped.append(UInt8(len & 0xFF))
        wrapped.append(UInt8((len >> 8) & 0xFF))
        wrapped.append(UInt8((len >> 16) & 0xFF))
        wrapped.append(UInt8((len >> 24) & 0xFF))
        wrapped.append(codestream)
        if codestream.count != paddedLen {
            wrapped.append(0x00)  // pad byte
        }
        print("DICOM wrap: codestream=\(codestream.count) bytes; item=\(wrapped.count) bytes (tag+len+data+pad)")

        // Unwrap: skip 8-byte header, read `len` bytes, strip trailing pad.
        let itemTag = (UInt32(wrapped[0]) | (UInt32(wrapped[1]) << 8) | (UInt32(wrapped[2]) << 16) | (UInt32(wrapped[3]) << 24))
        XCTAssertEqual(itemTag, 0xE000FFFE, "DICOM item tag must be FFFE E000")
        let unwrappedLen = (UInt32(wrapped[4]) | (UInt32(wrapped[5]) << 8) | (UInt32(wrapped[6]) << 16) | (UInt32(wrapped[7]) << 24))
        XCTAssertEqual(Int(unwrappedLen), paddedLen)
        let unwrapped = wrapped.subdata(in: 8..<(8 + codestream.count))
        XCTAssertEqual(unwrapped, codestream,
            "DICOM unwrap must return byte-identical codestream")

        // Decode the unwrapped codestream — J2KSwift
        let decoded = try await J2KDecoder().decode(unwrapped)
        XCTAssertEqual(decoded.width, img.width)
        XCTAssertEqual(decoded.height, img.height)

        // Also validate via OpenJPEG (independent codec on the unwrapped bytes)
        let tmpDir = FileManager.default.temporaryDirectory
        let unwrappedURL = tmpDir.appendingPathComponent("dicom_unwrapped.j2k")
        try unwrapped.write(to: unwrappedURL)
        defer { try? FileManager.default.removeItem(at: unwrappedURL) }
        let opjOut = tmpDir.appendingPathComponent("dicom_unwrapped.pgm")
        defer { try? FileManager.default.removeItem(at: opjOut) }
        let opjResult = runDecoder("opj_decompress", args: [
            "-i", unwrappedURL.path, "-o", opjOut.path
        ])
        XCTAssertEqual(opjResult.exit, 0,
            "OpenJPEG must decode DICOM-unwrapped strict codestream: \(opjResult.stderr)")
    }
}

#endif // os(macOS)
