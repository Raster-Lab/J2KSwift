// J2KHTEndToEndCrossCodecTests.swift
// Full-codestream cross-codec validation: encode with J2KSwift's
// public API using `htj2kBlockFormat: .part15`, then hand the
// resulting .j2c bytes to OpenJPH's `ojph_expand` and verify the
// reconstructed image matches the input.
//
// This is the v5.0.0 acceptance criterion: OpenJPH must be able to
// decode what J2KSwift produces when Part-15 mode is on.

import XCTest
import Foundation
import J2KCore
@testable import J2KCodec

final class HTEndToEndCrossCodecTests: XCTestCase {

    private let ojphExpand = "/opt/homebrew/bin/ojph_expand"

    private func skipIfMissing() throws {
        guard FileManager.default.isExecutableFile(atPath: ojphExpand) else {
            throw XCTSkip("ojph_expand not found")
        }
    }

    /// Build a grayscale `J2KImage` from raw 8-bit samples.
    private func makeImage(width: Int, height: Int, pixels: [UInt8])
        -> J2KImage
    {
        let component = J2KComponent(
            index: 0, bitDepth: 8, width: width, height: height,
            data: Data(pixels))
        return J2KImage(width: width, height: height,
                        components: [component])
    }

    /// Run ojph_expand on a .j2c file, return the decoded raw pixel
    /// bytes (PGM or PPM payload) alongside the full PGM/PPM data.
    private func ojphDecode(_ j2c: URL)
        throws -> (width: Int, height: Int, pixels: [UInt8])
    {
        let tmp = FileManager.default.temporaryDirectory
        let out = tmp.appendingPathComponent("ojph_roundtrip.pgm")
        defer { try? FileManager.default.removeItem(at: out) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ojphExpand)
        proc.arguments = ["-i", j2c.path, "-o", out.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            throw NSError(domain: "ojph_expand",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output])
        }

        // Parse PGM: "P5\nW H\n255\n" + raw bytes.
        let data = try Data(contentsOf: out)
        guard data.starts(with: [0x50, 0x35]) else {
            throw NSError(domain: "PGM", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "not a PGM file"])
        }
        // Walk past three whitespace-separated header fields.
        var i = 3  // skip "P5\n"
        func readToken() -> String {
            var s = ""
            while i < data.count {
                let c = Character(UnicodeScalar(data[i]))
                if c == "\n" || c == " " || c == "\r" || c == "\t" {
                    i += 1
                    if !s.isEmpty { return s }
                } else {
                    s.append(c)
                    i += 1
                }
            }
            return s
        }
        // Skip potential comment lines.
        while i < data.count && data[i] == 0x23 /* # */ {
            while i < data.count && data[i] != 0x0A { i += 1 }
            i += 1
        }
        guard let w = Int(readToken()), let h = Int(readToken()),
              let _ = Int(readToken()) else {
            throw NSError(domain: "PGM", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "bad header"])
        }
        return (w, h, [UInt8](data[i..<data.count]))
    }

    /// Round-trip pixels through OpenJPH itself (compress + expand) —
    /// gives the ground-truth reference for what lossless Part-15
    /// output should be, including the standard's edge cases (e.g.
    /// 8-bit value 0 clamps to 128 on decode because `|v| = 128 =
    /// 2^7` overflows the 7-bit magnitude range signaled by K_max=7).
    private func ojphSelfRoundTrip(pixels: [UInt8],
                                   width: Int, height: Int,
                                   cb: Int)
        throws -> [UInt8]
    {
        let tmp = FileManager.default.temporaryDirectory
        let pgmIn = tmp.appendingPathComponent("ojph_in.pgm")
        let j2c = tmp.appendingPathComponent("ojph_ref.j2c")
        let pgmOut = tmp.appendingPathComponent("ojph_out.pgm")
        defer {
            try? FileManager.default.removeItem(at: pgmIn)
            try? FileManager.default.removeItem(at: j2c)
            try? FileManager.default.removeItem(at: pgmOut)
        }
        var header = [UInt8]()
        header.append(contentsOf:
            Array("P5\n\(width) \(height)\n255\n".utf8))
        header.append(contentsOf: pixels)
        try Data(header).write(to: pgmIn)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ojph_compress")
        proc.arguments = ["-i", pgmIn.path, "-o", j2c.path,
                          "-num_decomps", "0",
                          "-block_size", "{\(cb),\(cb)}",
                          "-reversible", "true"]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        try proc.run(); proc.waitUntilExit()
        let (_, _, out) = try ojphDecode(j2c)
        return out
    }

    // MARK: - Tests

    /// 4×4 uniform grayscale, lossless. End-to-end cross-codec:
    /// J2KSwift (Part-15 on-wire) → OpenJPH ojph_expand. Asserts
    /// output matches OpenJPH's own self round-trip reference.
    func testEndToEnd4x4UniformLossless() async throws {
        try skipIfMissing()
        let width = 4, height = 4
        let pixels = [UInt8](repeating: 0x40, count: width * height)
        let image = makeImage(width: width, height: height, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .part15
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (4, 4)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)

        let tmp = FileManager.default.temporaryDirectory
        let j2c = tmp.appendingPathComponent("e2e.j2c")
        defer { try? FileManager.default.removeItem(at: j2c) }
        try encoded.write(to: j2c)

        let (w, h, decoded) = try ojphDecode(j2c)
        XCTAssertEqual(w, width)
        XCTAssertEqual(h, height)
        let reference = try ojphSelfRoundTrip(
            pixels: pixels, width: width, height: height, cb: 4)
        XCTAssertEqual(decoded, reference,
            "J2KSwift Part-15 → OpenJPH must decode identically to " +
            "OpenJPH's own self round-trip")
    }

    /// 8×8 gradient, lossless.
    func testEndToEnd8x8GradientLossless() async throws {
        try skipIfMissing()
        let width = 8, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        for i in 0..<pixels.count { pixels[i] = UInt8(i * 3) }
        let image = makeImage(width: width, height: height, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .part15
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (8, 8)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)

        let tmp = FileManager.default.temporaryDirectory
        let j2c = tmp.appendingPathComponent("e2e_grad.j2c")
        defer { try? FileManager.default.removeItem(at: j2c) }
        try encoded.write(to: j2c)

        let (w, h, decoded) = try ojphDecode(j2c)
        XCTAssertEqual(w, width)
        XCTAssertEqual(h, height)
        let reference = try ojphSelfRoundTrip(
            pixels: pixels, width: width, height: height, cb: 8)
        XCTAssertEqual(decoded, reference)
    }

    /// 32×32 deterministic noise, lossless. Exercises multiple
    /// codeblocks and varied magnitude distributions.
    func testEndToEnd32x32NoiseLossless() async throws {
        try skipIfMissing()
        let width = 32, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height)
        var state: UInt64 = 0xC0FFEE
        for i in 0..<pixels.count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            pixels[i] = UInt8((state >> 56) & 0xFF)
        }
        let image = makeImage(width: width, height: height, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .part15
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (32, 32)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)

        let tmp = FileManager.default.temporaryDirectory
        let j2c = tmp.appendingPathComponent("e2e_noise.j2c")
        defer { try? FileManager.default.removeItem(at: j2c) }
        try encoded.write(to: j2c)

        let (w, h, decoded) = try ojphDecode(j2c)
        XCTAssertEqual(w, width)
        XCTAssertEqual(h, height)
        let reference = try ojphSelfRoundTrip(
            pixels: pixels, width: width, height: height, cb: 32)
        XCTAssertEqual(decoded, reference)
    }
}
