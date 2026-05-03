// J2KPGMRoundTripTests.swift
//
// v5.14.1: regression gate for the lossless PGM round-trip
// correctness. Pre-v5.14.1 the CLI's PGM writer emitted little-
// endian 16-bit pixels (the spec requires big-endian), causing
// every lossless-encoded medical image to fail byte-for-byte
// round-trip even though the codec itself was bit-exact.
// `medical_benchmark.py` showed PSNR ≈ 7 on CT 16-bit lossless,
// far from the expected ∞.
//
// This test exercises the full CLI encode → decode path on
// synthetic 12-bit and 16-bit grayscale images and asserts the
// decoded PGM bytes match the original PGM bytes exactly.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class J2KPGMRoundTripTests: XCTestCase {

    /// Helper: write a P5 (binary, big-endian for 16-bit) PGM file
    /// from a deterministic synthetic input.
    private func writeSyntheticPGM(
        path: String,
        width: Int,
        height: Int,
        bitDepth: Int,
        seed: UInt64
    ) throws {
        let maxValue = (1 << bitDepth) - 1
        var state = seed | 1
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * (bitDepth <= 8 ? 1 : 2))
        for _ in 0..<(width * height) {
            state = state &* 2862933555777941757 &+ 3037000493
            let v = Int((state >> 32) & 0xFFFFFFFF) % (maxValue + 1)
            if bitDepth <= 8 {
                bytes.append(UInt8(v))
            } else {
                // PGM 16-bit is big-endian: high byte first.
                bytes.append(UInt8((v >> 8) & 0xFF))
                bytes.append(UInt8(v & 0xFF))
            }
        }
        let header = "P5\n\(width) \(height)\n\(maxValue)\n"
        var data = Data(header.utf8)
        data.append(contentsOf: bytes)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Run the full CLI encode + decode pipeline and assert
    /// byte-for-byte match against the input. Requires the
    /// release-built `j2k` binary (built by the SPM target before
    /// tests run).
    private func roundTripCLI(
        width: Int,
        height: Int,
        bitDepth: Int,
        useHTJ2K: Bool,
        seed: UInt64
    ) throws {
        let cliURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/release/j2k")
        guard FileManager.default.fileExists(atPath: cliURL.path) else {
            throw XCTSkip("Release-built j2k CLI not found at \(cliURL.path); run `swift build -c release` first")
        }

        let tmpDir = NSTemporaryDirectory() + "j2k_pgm_roundtrip_\(seed)/"
        try? FileManager.default.removeItem(atPath: tmpDir)
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let inputPath = tmpDir + "input.pgm"
        let j2kPath = tmpDir + "encoded.j2k"
        let outputPath = tmpDir + "output.pgm"

        try writeSyntheticPGM(
            path: inputPath, width: width, height: height,
            bitDepth: bitDepth, seed: seed)

        // Encode
        let enc = Process()
        enc.executableURL = cliURL
        var encArgs = ["encode", "-i", inputPath, "-o", j2kPath, "--lossless", "--quiet"]
        if useHTJ2K { encArgs.append("--htj2k") }
        enc.arguments = encArgs
        try enc.run()
        enc.waitUntilExit()
        XCTAssertEqual(enc.terminationStatus, 0, "encode failed")

        // Decode
        let dec = Process()
        dec.executableURL = cliURL
        dec.arguments = ["decode", "-i", j2kPath, "-o", outputPath, "--quiet"]
        try dec.run()
        dec.waitUntilExit()
        XCTAssertEqual(dec.terminationStatus, 0, "decode failed")

        // Compare
        let original = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let decoded = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        XCTAssertEqual(
            original, decoded,
            "Lossless round-trip failed for \(width)x\(height) \(bitDepth)-bit useHTJ2K=\(useHTJ2K). " +
            "Decoded PGM is not byte-identical to input. v5.14.1's fix targets this — " +
            "if it regresses, check ImageIO.swift's PGM writer byte-order handling and " +
            "J2KDecoderPipeline.swift's component sampleByteOrder tagging.")
    }

    // 8-bit grayscale — sanity check (not affected by the byte-order bug)
    func testRoundTrip_8bit_Part1() throws {
        try roundTripCLI(width: 256, height: 256, bitDepth: 8, useHTJ2K: false, seed: 0xC0FFEE)
    }

    func testRoundTrip_8bit_HTJ2K() throws {
        try roundTripCLI(width: 256, height: 256, bitDepth: 8, useHTJ2K: true, seed: 0xC0FFEE)
    }

    // 12-bit grayscale (medical MRI / ultrasound depth)
    func testRoundTrip_12bit_Part1() throws {
        try roundTripCLI(width: 384, height: 384, bitDepth: 12, useHTJ2K: false, seed: 0xDEADBEEF)
    }

    func testRoundTrip_12bit_HTJ2K() throws {
        try roundTripCLI(width: 384, height: 384, bitDepth: 12, useHTJ2K: true, seed: 0xDEADBEEF)
    }

    // 16-bit grayscale (medical CT depth) — this was the case
    // medical_benchmark.py showed PSNR ≈ 7 on pre-v5.14.1.
    func testRoundTrip_16bit_Part1() throws {
        try roundTripCLI(width: 512, height: 512, bitDepth: 16, useHTJ2K: false, seed: 0xCAFEBABE)
    }

    func testRoundTrip_16bit_HTJ2K() throws {
        try roundTripCLI(width: 512, height: 512, bitDepth: 16, useHTJ2K: true, seed: 0xCAFEBABE)
    }
}
