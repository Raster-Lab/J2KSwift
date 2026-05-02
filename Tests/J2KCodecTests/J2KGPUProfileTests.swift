// J2KGPUProfileTests.swift
//
// v5.12.1: ad-hoc profile harness for the GPU HT decode session
// path. Surfaces per-stage timings on dx_002 (the largest corpus
// fixture) to identify where remaining cost lives. NOT a perf gate
// — just a diagnostic. Run with:
//
//    J2K_PROFILE_DECODE=1 swift test --filter J2KGPUProfileTests
//
// to see the per-stage breakdown.

import XCTest
@testable import J2KCodec
@testable import J2KCore
import J2KMetal

final class J2KGPUProfileTests: XCTestCase {

    private static let stderr = FileHandle.standardError
    private static func say(_ s: String) {
        stderr.write(Data((s + "\n").utf8))
    }

    func testProfileDX002() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["J2K_PROFILE_DECODE"] != nil,
            "Run with J2K_PROFILE_DECODE=1 to capture timings")

        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("CrossCodec")
        let pgmURL = fixturesDir.appendingPathComponent("dx_study_002_instance_000001.pgm")
        let pgmData = try Data(contentsOf: pgmURL)
        var headerEnd = 0; var nl = 0; var i = 0
        while i < pgmData.count {
            if pgmData[i] == 0x0A { nl += 1; if nl == 3 { headerEnd = i + 1; break } }
            i += 1
        }
        let h = String(data: pgmData.prefix(headerEnd - 1), encoding: .ascii) ?? ""
        let lines = h.split(separator: "\n")
        let dims = lines[1].split(separator: " ")
        let w = Int(dims[0])!, height = Int(dims[1])!
        let bd = Int(lines[2])! > 255 ? 16 : 8
        let pixels = pgmData.subdata(in: headerEnd..<pgmData.count)
        let image = J2KImage(
            width: w, height: height,
            components: [J2KComponent(
                index: 0, bitDepth: bd, signed: false,
                width: w, height: height,
                data: pixels, sampleByteOrder: .littleEndian)],
            colorSpace: .grayscale)

        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        let decoder = J2KDecoder()
        let session = J2KMetalSession()

        Self.say("[profile] === dx_002 \(w)×\(height) bd=\(bd) ===")

        // Warmup
        _ = try await decoder.decodeWithGPUHT(encoded, session: session)
        Self.say("[profile] --- warmup done; timed run follows ---")

        // Single timed run with profile output
        let t0 = DispatchTime.now()
        _ = try await decoder.decodeWithGPUHT(encoded, session: session)
        let total = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
        Self.say(String(format: "[profile] TOTAL session decode = %.1f ms", total))
    }
}
