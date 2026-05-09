// v8 Phase 6.2 — gated to macOS: invokes external CLIs via Process() (unavailable on iOS).
#if os(macOS)
// J2KHTConformantSelfRoundTripTests.swift
// Regression coverage for the v5.0.0 decoder-pipeline bug where
// J2KSwift could not decode its own .conformant HTJ2K codestreams
// because the block decode sites unconditionally called the v4.x
// custom-format decoder. The fix emits a COM marker on the encoder
// side, parses it on the decoder side, and routes block dispatch to
// HTBlockDecoderConformant when the codestream is flagged.
//
// Coverage runs up through 32×32 code blocks now that the UVLC
// pair order mismatch (pre0/pre1/suf0/suf1 on the wire vs.
// interleaved reads in the decoder) has been fixed.

import XCTest
import Foundation
import J2KCore
@testable import J2KCodec

final class J2KHTConformantSelfRoundTripTests: XCTestCase {

    private func makeGrayscale(width: Int, height: Int, pixels: [UInt8])
        -> J2KImage
    {
        let component = J2KComponent(
            index: 0, bitDepth: 8, width: width, height: height,
            data: Data(pixels))
        return J2KImage(width: width, height: height,
                        components: [component])
    }

    private func extractBytes(_ image: J2KImage) -> [UInt8] {
        return [UInt8](image.components[0].data)
    }

    /// Exact repro from the bug report: encode with
    /// `htj2kBlockFormat = .conformant`, decode through J2KSwift's
    /// own public API, assert bit-exact recovery.
    func testConformantSelfRoundTripLossless4x4() async throws {
        let w = 4, h = 4
        let pixels: [UInt8] = [
            0x10, 0x20, 0x30, 0x40,
            0x50, 0x60, 0x70, 0x80,
            0x90, 0xA0, 0xB0, 0xC0,
            0xD0, 0xE0, 0xF0, 0xFF
        ]
        let image = makeGrayscale(width: w, height: h, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.bitrateMode = .lossless
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .conformant
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (4, 4)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)
        let decoded = try await J2KDecoder().decode(encoded)

        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.height, h)
        XCTAssertEqual(extractBytes(decoded), pixels)
    }

    /// 8×8 uniform: single code block spanning multiple quad rows.
    func testConformantSelfRoundTripLossless8x8Uniform() async throws {
        let w = 8, h = 8
        let pixels = [UInt8](repeating: 0x77, count: w * h)
        let image = makeGrayscale(width: w, height: h, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.bitrateMode = .lossless
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .conformant
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (8, 8)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(extractBytes(decoded), pixels)
    }

    /// 8×8 pseudo-random: varied magnitudes across quads.
    func testConformantSelfRoundTripLossless8x8Noise() async throws {
        let w = 8, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        var state: UInt64 = 0xBEEF
        for i in 0..<pixels.count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            pixels[i] = UInt8((state >> 56) & 0xFF)
        }
        let image = makeGrayscale(width: w, height: h, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.bitrateMode = .lossless
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .conformant
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (8, 8)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(extractBytes(decoded), pixels)
    }

    /// The encoder side still emits a standards-compliant codestream
    /// even at larger blocks — proves the dispatch bug only affects
    /// the decoder path, not interop output.
    func testConformantEncoderOutputDecodesInOpenJPHAt32x32() async throws {
        let ojph = "/opt/homebrew/bin/ojph_expand"
        guard FileManager.default.isExecutableFile(atPath: ojph) else {
            throw XCTSkip("ojph_expand not found")
        }
        let w = 32, h = 32
        var pixels = [UInt8](repeating: 0, count: w * h)
        var state: UInt64 = 0xDECAF
        for i in 0..<pixels.count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            pixels[i] = UInt8((state >> 56) & 0xFF)
        }
        let image = makeGrayscale(width: w, height: h, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.bitrateMode = .lossless
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .conformant
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (32, 32)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)
        let tmp = FileManager.default.temporaryDirectory
        let j2c = tmp.appendingPathComponent("probe32.j2c")
        let pgm = tmp.appendingPathComponent("probe32.pgm")
        defer {
            try? FileManager.default.removeItem(at: j2c)
            try? FileManager.default.removeItem(at: pgm)
        }
        try encoded.write(to: j2c)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ojph)
        proc.arguments = ["-i", j2c.path, "-o", pgm.path]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe
        try proc.run()
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8) ?? ""
        XCTAssertEqual(proc.terminationStatus, 0,
            "ojph_expand failed: \(out)")
    }

    // MARK: - Multi-row block-decoder regression coverage
    //
    // Before the UVLC fix these would desync the VLC stream whenever
    // any u_q value exceeded 2 (i.e. required a suffix codeword).

    func testConformantSelfRoundTrip16x16Noise() async throws {
        try await selfRoundTripNoise(w: 16, h: 16, cb: 16, seed: 0xBEEF)
    }

    func testConformantSelfRoundTrip32x32Uniform() async throws {
        let w = 32, h = 32
        let pixels = [UInt8](repeating: 0x42, count: w * h)
        let image = makeGrayscale(width: w, height: h, pixels: pixels)
        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.bitrateMode = .lossless
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .conformant
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (32, 32)
        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(extractBytes(decoded), pixels)
    }

    func testConformantSelfRoundTrip32x32Noise() async throws {
        try await selfRoundTripNoise(w: 32, h: 32, cb: 32, seed: 0xDECAF)
    }

    // 12×12 would be invalid as a code block size (J2K requires
    // power-of-2 dimensions). Omit.

    func testConformantSelfRoundTrip8x16Noise() async throws {
        try await selfRoundTripNoise(w: 8, h: 16, cb: 16, seed: 0xBEEF)
    }

    func testConformantSelfRoundTrip16x8Noise() async throws {
        try await selfRoundTripNoise(w: 16, h: 8, cb: 16, seed: 0xBEEF)
    }

    private func selfRoundTripNoise(
        w: Int, h: Int, cb: Int, seed: UInt64
    ) async throws {
        var pixels = [UInt8](repeating: 0, count: w * h)
        var state = seed
        for i in 0..<pixels.count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            // v5.1.1 bumped the conformant K_max by 1, so the
            // historical 8-bit pixel-0 edge case (|DC-shift(0)| = 128
            // overflowing K_max=7) no longer applies and the full
            // byte range round-trips bit-exactly.
            pixels[i] = UInt8((state >> 56) & 0xFF)
        }
        let image = makeGrayscale(width: w, height: h, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.bitrateMode = .lossless
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .conformant
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (cb, cb)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(extractBytes(decoded), pixels,
            "self round-trip failed at \(w)×\(h), cb=\(cb)")
    }

    /// The new COM signal must only drive `.conformant` codestreams.
    /// The default `.custom` path (used by every existing HTJ2K file)
    /// must keep routing to the v4.x custom block decoder.
    func testCustomSelfRoundTripUnaffected() async throws {
        let w = 16, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h)
        for i in 0..<pixels.count { pixels[i] = UInt8(i & 0xFF) }
        let image = makeGrayscale(width: w, height: h, pixels: pixels)

        var cfg = J2KEncodingConfiguration()
        cfg.lossless = true
        cfg.bitrateMode = .lossless
        cfg.useHTJ2K = true
        cfg.htj2kBlockFormat = .custom
        cfg.decompositionLevels = 0
        cfg.codeBlockSize = (16, 16)

        let encoded = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        XCTAssertEqual(extractBytes(decoded), pixels)
    }
}

#endif // os(macOS)
