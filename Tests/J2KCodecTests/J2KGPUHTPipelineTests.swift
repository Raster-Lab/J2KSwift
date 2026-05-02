// J2KGPUHTPipelineTests.swift
//
// M2-prime forward-validation: end-to-end pipeline test that
// `J2KDecoder().decodeWithGPUHT()` produces byte-identical output
// to `J2KDecoder().decodeGPU()` on lossless HTJ2K codestreams.
//
// `decodeGPU()` runs HT entropy decode on CPU and inverse DWT on GPU.
// `decodeWithGPUHT()` runs both HT entropy decode AND inverse DWT on
// GPU. The two must agree byte-for-byte; this is the bit-exactness
// gate for the M2-prime production-integration path landing in
// v5.5.0.

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KGPUHTPipelineTests: XCTestCase {

    private func deterministic16BitGrayscale(width: Int, height: Int, seed: UInt64) -> Data {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            state = state &* 2862933555777941757 &+ 3037000493
            let v = UInt16((state >> 32) & 0x0FFF)  // 12-bit DX-style range
            bytes[2 * i]     = UInt8(v & 0xFF)
            bytes[2 * i + 1] = UInt8((v >> 8) & 0xFF)
        }
        return Data(bytes)
    }

    private func makeImage(width: Int, height: Int, bitDepth: Int, seed: UInt64) -> J2KImage {
        let raw = deterministic16BitGrayscale(width: width, height: height, seed: seed)
        let component = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            data: raw, sampleByteOrder: .littleEndian)
        return J2KImage(
            width: width, height: height,
            components: [component], colorSpace: .grayscale)
    }

    /// 12-bit, 384×384, lossless 5/3, HTJ2K conformant. The GPU HT
    /// dispatch path must produce identical bytes to the CPU HT path.
    func testHTJ2KLossless_GPUHTMatchesCPUHT() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        let image = makeImage(width: 384, height: 384, bitDepth: 12, seed: 0xCAFEBABE)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuHT = try await decoder.decodeGPU(encoded)
        let gpuHT = try await decoder.decodeWithGPUHT(encoded)

        XCTAssertEqual(cpuHT.width, gpuHT.width)
        XCTAssertEqual(cpuHT.height, gpuHT.height)
        XCTAssertEqual(cpuHT.components.count, gpuHT.components.count)
        XCTAssertEqual(
            cpuHT.components.first?.data, gpuHT.components.first?.data,
            "GPU HT path must match CPU HT path byte-for-byte for lossless HTJ2K")
    }

    /// Larger workload (512×512, 16-bit). Stresses the multi-codeblock
    /// batch path with more codeblocks per tile.
    func testHTJ2KLossless512_GPUHTMatchesCPUHT() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        let image = makeImage(width: 512, height: 512, bitDepth: 16, seed: 0xFEEDFACE)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuHT = try await decoder.decodeGPU(encoded)
        let gpuHT = try await decoder.decodeWithGPUHT(encoded)

        XCTAssertEqual(
            cpuHT.components.first?.data, gpuHT.components.first?.data,
            "GPU HT path must match CPU HT path byte-for-byte (512×512)")
    }

    // MARK: - Corpus-wide gate (M2P-3)
    //
    // The cross-codec DICOM PGM corpus committed under
    // Tests/Fixtures/CrossCodec/ is the same fixture set the cross-
    // codec matrix exercises. Loading them as J2KImage, encoding to
    // HTJ2K conformant, decoding both ways, and asserting byte-equal
    // output is the M2P-3 bit-exactness gate.

    /// Minimal 16-bit PGM (P5) parser. Accepts standard `P5\n<W>
    /// <H>\n<maxval>\n<binary>` layout — the format the fixtures use.
    private func parsePGM16Bit(_ data: Data) throws -> J2KImage {
        var headerEnd = 0
        var newlineCount = 0
        var idx = 0
        while idx < data.count {
            if data[idx] == 0x0A {  // '\n'
                newlineCount += 1
                if newlineCount == 3 { headerEnd = idx + 1; break }
            }
            idx += 1
        }
        guard headerEnd > 0 else {
            throw NSError(domain: "PGM", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "header not terminated"])
        }
        let headerStr = String(
            data: data.prefix(headerEnd - 1), encoding: .ascii) ?? ""
        let lines = headerStr.split(separator: "\n")
        guard lines.count >= 3, lines[0] == "P5" else {
            throw NSError(domain: "PGM", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "not a P5 PGM"])
        }
        let dims = lines[1].split(separator: " ")
        guard dims.count >= 2,
              let width = Int(dims[0]), let height = Int(dims[1]),
              let maxval = Int(lines[2]) else {
            throw NSError(domain: "PGM", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "bad dims/maxval"])
        }
        let bitDepth = maxval > 255 ? 16 : 8
        let pixelData = data.subdata(in: headerEnd..<data.count)
        let expectedBytes = width * height * (bitDepth == 16 ? 2 : 1)
        guard pixelData.count == expectedBytes else {
            throw NSError(domain: "PGM", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                              "pixel data \(pixelData.count) bytes, expected \(expectedBytes)"])
        }
        // Byte-order doesn't affect the test invariant (cpuOut == gpuOut)
        // since both decode paths use the same encoder convention.
        let component = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            data: pixelData, sampleByteOrder: .littleEndian)
        return J2KImage(
            width: width, height: height,
            components: [component], colorSpace: .grayscale)
    }

    /// Bit-exactness gate over the full DICOM corpus committed under
    /// `Tests/Fixtures/CrossCodec/`. For every fixture, encodes to
    /// HTJ2K conformant and asserts `decodeWithGPUHT` matches
    /// `decodeGPU` byte-for-byte. This covers a much wider range of
    /// codeblock shapes and content patterns than the synthetic
    /// 384/512 tests above.
    func testFullDICOMCorpus_GPUHTMatchesCPUHT() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()              // Tests/J2KCodecTests/
            .deletingLastPathComponent()              // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("CrossCodec")

        let pgms = try FileManager.default.contentsOfDirectory(
            at: fixturesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "pgm" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(
            pgms.isEmpty,
            "no PGM fixtures found at \(fixturesDir.path)")

        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let decoder = J2KDecoder()

        var checked = 0
        for pgmURL in pgms {
            let pgmData = try Data(contentsOf: pgmURL)
            let image = try parsePGM16Bit(pgmData)
            let encoded = try await encoder.encode(image)

            let cpuHT = try await decoder.decodeGPU(encoded)
            let gpuHT = try await decoder.decodeWithGPUHT(encoded)

            XCTAssertEqual(cpuHT.width, gpuHT.width,
                           "width mismatch on \(pgmURL.lastPathComponent)")
            XCTAssertEqual(cpuHT.height, gpuHT.height,
                           "height mismatch on \(pgmURL.lastPathComponent)")
            XCTAssertEqual(
                cpuHT.components.first?.data,
                gpuHT.components.first?.data,
                "GPU HT path must match CPU HT path byte-for-byte on \(pgmURL.lastPathComponent)")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(
            checked, 7,
            "expected ≥7 fixtures in the corpus; got \(checked)")
    }

    /// J2K Part 1 (no HTJ2K). The flag must be inert: with no HT
    /// blocks in the codestream, `decodeWithGPUHT` falls through to
    /// the existing CPU EBCOT path and produces identical output to
    /// `decodeGPU`.
    func testJ2KPart1_GPUHTFlagIsInert() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        let image = makeImage(width: 384, height: 384, bitDepth: 12, seed: 0xBEEFCAFE)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: false,                 // Part 1
            useReversibleFilter: true,
            htj2kBlockFormat: .custom)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try await encoder.encode(image)

        let decoder = J2KDecoder()
        let cpuPath = try await decoder.decodeGPU(encoded)
        let gpuFlag = try await decoder.decodeWithGPUHT(encoded)

        XCTAssertEqual(
            cpuPath.components.first?.data, gpuFlag.components.first?.data,
            "useGPUHT flag must be inert on Part 1 codestreams")
    }
}
