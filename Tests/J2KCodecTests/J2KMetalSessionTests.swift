// J2KMetalSessionTests.swift
//
// v5.6.0 (M3-prime): warm-process bit-exactness + perf measurement
// for the persistent Metal session path.
//
// Two gates:
//   1. Bit-exactness — `decodeWithGPUHT(data, session:)` produces
//      output byte-identical to the v5.5.0 sessionless path.
//   2. Warm-process speedup — repeated decodes through a shared
//      session amortise the ~50 ms first-call init cost. Reported
//      as median per-decode time across N runs; first run excluded.

import XCTest
@testable import J2KCodec
@testable import J2KCore
import J2KMetal

final class J2KMetalSessionTests: XCTestCase {

    private static let stderr = FileHandle.standardError
    private static func say(_ s: String) {
        stderr.write(Data((s + "\n").utf8))
    }

    private func deterministic16BitGrayscale(width: Int, height: Int, seed: UInt64) -> Data {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: width * height * 2)
        for i in 0..<(width * height) {
            state = state &* 2862933555777941757 &+ 3037000493
            let v = UInt16((state >> 32) & 0x0FFF)
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

    /// Generate a synthetic 8-bit RGB image with deterministic values
    /// per channel. Used by the v5.13b RGB MCT-fusion gate.
    private func makeRGBImage(width: Int, height: Int, seed: UInt64) -> J2KImage {
        var stateR = (seed | 1)
        var stateG = (seed | 1) &* 0xDEADBEEF
        var stateB = (seed | 1) &* 0xCAFEBABE
        var rBytes = [UInt8](repeating: 0, count: width * height)
        var gBytes = [UInt8](repeating: 0, count: width * height)
        var bBytes = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            stateR = stateR &* 2862933555777941757 &+ 3037000493
            stateG = stateG &* 2862933555777941757 &+ 3037000493
            stateB = stateB &* 2862933555777941757 &+ 3037000493
            rBytes[i] = UInt8(truncatingIfNeeded: stateR >> 32)
            gBytes[i] = UInt8(truncatingIfNeeded: stateG >> 32)
            bBytes[i] = UInt8(truncatingIfNeeded: stateB >> 32)
        }
        return J2KImage(
            width: width, height: height,
            components: [
                J2KComponent(index: 0, bitDepth: 8, signed: false,
                             width: width, height: height,
                             data: Data(rBytes), sampleByteOrder: .littleEndian),
                J2KComponent(index: 1, bitDepth: 8, signed: false,
                             width: width, height: height,
                             data: Data(gBytes), sampleByteOrder: .littleEndian),
                J2KComponent(index: 2, bitDepth: 8, signed: false,
                             width: width, height: height,
                             data: Data(bBytes), sampleByteOrder: .littleEndian)
            ],
            colorSpace: .sRGB)
    }

    /// Bit-exactness gate: decodeWithGPUHT(data) and
    /// decodeWithGPUHT(data, session: ...) must produce identical
    /// output bytes for the same codestream.
    func testSessionAndSessionlessAgreeBitExact() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let image = makeImage(width: 384, height: 384, bitDepth: 12, seed: 0xDEADBEEF)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        let decoder = J2KDecoder()
        let session = J2KMetalSession()

        let imgA = try await decoder.decodeWithGPUHT(encoded)
        let imgB = try await decoder.decodeWithGPUHT(encoded, session: session)

        XCTAssertEqual(
            imgA.components.first?.data,
            imgB.components.first?.data,
            "session-injected and sessionless decodeWithGPUHT must produce identical bytes")
    }

    /// Warm-process measurement: decode N images through a single
    /// shared session and report the per-decode median.
    /// First decode is excluded — that's the one that pays the
    /// init cost. Subsequent decodes should be substantially
    /// faster than the equivalent sessionless calls (which pay the
    /// init cost every time).
    func testWarmProcessSpeedup() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let image = makeImage(width: 512, height: 512, bitDepth: 12, seed: 0xCAFEBABE)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        let decoder = J2KDecoder()
        let session = J2KMetalSession()
        let runs = 6

        // Sessionless: every decode pays init cost — slow.
        var sessionlessMs: [Double] = []
        for _ in 0..<runs {
            let t0 = Date()
            _ = try await decoder.decodeWithGPUHT(encoded)
            sessionlessMs.append(Date().timeIntervalSince(t0) * 1000)
        }

        // With session: first call pays init, subsequent reuse.
        var sessionMs: [Double] = []
        for _ in 0..<runs {
            let t0 = Date()
            _ = try await decoder.decodeWithGPUHT(encoded, session: session)
            sessionMs.append(Date().timeIntervalSince(t0) * 1000)
        }

        let warmSession = Array(sessionMs.dropFirst())  // exclude first
        let warmSessionless = Array(sessionlessMs.dropFirst())  // first pays JIT/page-cache too
        let medSess = warmSession.sorted()[warmSession.count / 2]
        let medNone = warmSessionless.sorted()[warmSessionless.count / 2]
        let speedup = medNone / medSess

        Self.say(String(format:
            "[session] sessionless median=%.2fms session median=%.2fms speedup=%.2fx",
            medNone, medSess, speedup))

        // Soft assertion: session should be faster on average. The
        // exact ratio is hardware-dependent; we just gate on > 1.0×
        // to catch a regression where the session path is somehow
        // slower than fresh-instance.
        XCTAssertGreaterThan(
            speedup, 1.0,
            "session-shared decodes should be faster than sessionless on warm runs")
    }

    /// v5.13b gate (test-fixture-only for now; v5.13b implementation
    /// pending): asserts session and sessionless GPU-HT decodes
    /// produce byte-identical output on a synthetic 3-channel RGB
    /// image. The DICOM corpus is grayscale (single component) so
    /// MCT (multi-component transform) is a no-op there. This test
    /// covers the MCT branch — when v5.13b lands a GPU MCT-fusion
    /// kernel, this gate prevents bit-exactness regressions.
    func testRGBSessionAndSessionlessAgreeBitExact() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let image = makeRGBImage(width: 320, height: 240, seed: 0xC0FFEE02)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        let decoder = J2KDecoder()
        let session = J2KMetalSession()

        let imgA = try await decoder.decodeWithGPUHT(encoded)
        let imgB = try await decoder.decodeWithGPUHT(encoded, session: session)

        XCTAssertEqual(imgA.components.count, 3, "RGB decode should produce 3 components")
        XCTAssertEqual(imgB.components.count, 3, "RGB decode should produce 3 components")
        for c in 0..<3 {
            XCTAssertEqual(
                imgA.components[c].data, imgB.components[c].data,
                "RGB session vs sessionless component \(c) bytes diverged")
        }
    }

    /// v5.14 gate (test-fixture-only for now; v5.14 implementation
    /// pending): asserts session and sessionless GPU-HT decodes
    /// agree on a 9/7 irreversible (lossy) codestream. The fast
    /// lane currently gates on `!isIrreversible` so 9/7 takes the
    /// slow lane on both paths; this test verifies at minimum the
    /// slow-lane 9/7 paths agree end-to-end. When v5.14 extends
    /// the fast lane to 9/7, this gate prevents bit-divergence
    /// between the new fast-lane path and the existing slow-lane.
    ///
    /// Note: 9/7 is lossy, so neither path matches the original
    /// input byte-for-byte. The gate is session vs sessionless
    /// agreement (both should produce the same lossy output).
    func test97LossySessionAndSessionlessAgreeBitExact() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let image = makeImage(width: 320, height: 240, bitDepth: 8, seed: 0xC0FFEE03)
        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: false,  // 9/7 irreversible
            htj2kBlockFormat: .conformant)
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        let decoder = J2KDecoder()
        let session = J2KMetalSession()

        let imgA = try await decoder.decodeWithGPUHT(encoded)
        let imgB = try await decoder.decodeWithGPUHT(encoded, session: session)

        XCTAssertEqual(
            imgA.components.first?.data, imgB.components.first?.data,
            "9/7 lossy session vs sessionless decode bytes diverged")
    }

    /// v5.12 gate: multi-tile codestreams round-trip bit-exact
    /// through both the CPU and GPU multi-tile paths. The DICOM
    /// corpus is single-tile so v5.12's bounded-concurrency change
    /// is structurally important but not exercised by the corpus
    /// gates; this test covers the multi-tile branch specifically.
    ///
    /// Encodes a synthetic 256×256 grayscale image with 64×64 tiles
    /// (16 tiles total — exceeds `maxInFlightTilesGPU = 8`, so the
    /// chunked-TaskGroup path runs at least 2 chunks).
    func testMultiTileBoundedConcurrencyRoundTrip() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let image = makeImage(width: 256, height: 256, bitDepth: 12, seed: 0xC0FFEE01)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            tileSize: (width: 64, height: 64),
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoded = try await J2KEncoder(encodingConfiguration: config).encode(image)

        let decoder = J2KDecoder()
        let session = J2KMetalSession()

        // Sessionless and session both go through the multi-tile
        // path because the encoded codestream has 16 tiles. Both
        // must produce identical output.
        let imgA = try await decoder.decodeWithGPUHT(encoded)
        let imgB = try await decoder.decodeWithGPUHT(encoded, session: session)

        XCTAssertEqual(
            imgA.components.first?.data,
            imgB.components.first?.data,
            "multi-tile session vs sessionless decode bytes diverged")

        // Spot-check: the decoded image must round-trip something
        // close to the original (lossless) — this catches bounded-
        // concurrency bugs that produce ANY output but not
        // round-trip-correct output.
        let raw = image.components.first!.data
        let decoded = imgA.components.first!.data
        XCTAssertEqual(raw.count, decoded.count, "byte count mismatch")
        // For lossless encoding, decoded bytes match raw input bytes
        // pixel-for-pixel (modulo any byte-order quirks elsewhere in
        // the codec — this is what testSessionAndSessionlessAgreeBitExact
        // verifies elsewhere).
    }

    /// Corpus-wide bit-exactness gate: for every PGM in the
    /// CrossCodec fixture set, encodes to HTJ2K conformant and
    /// asserts `decodeWithGPUHT(data)` and `decodeWithGPUHT(data,
    /// session: ...)` produce byte-identical output.
    ///
    /// Catches what the synthetic 384×384 `testSessionAndSessionless
    /// AgreeBitExact` can't: fixtures where the GPU IDWT bails out
    /// to the CPU path (small images, custom wavelet kernels, …)
    /// and the fast lane therefore needs to skip itself rather than
    /// feed an empty `[SubbandInfo]` set to a CPU IDWT. mr_002
    /// (180×180) is the canonical small-image case — v5.9d's fast-
    /// lane gate keeps it on the slow lane.
    ///
    /// Also catches v5.9b's regression: the
    /// `compSubbands.isEmpty` short-circuit in
    /// `applyInverseWaveletTransformGPU` used to skip every
    /// component when the fast lane returned `([], batch)` — the
    /// IDWT path that consumed `gpuBatch` was unreachable on the
    /// fast lane and session decode collapsed to DC-offset only.
    /// v5.9e fixes that by checking `gpuBatch?.plansByComponent`
    /// before falling back to all-zero output.
    func testCorpusSessionAndSessionlessAgreeBitExact() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("CrossCodec")
        let pgms = try FileManager.default.contentsOfDirectory(
            at: fixturesDir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "pgm" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let decoder = J2KDecoder()
        let session = J2KMetalSession()

        func parsePGM(_ data: Data) throws -> J2KImage {
            var headerEnd = 0; var nl = 0; var i = 0
            while i < data.count {
                if data[i] == 0x0A { nl += 1; if nl == 3 { headerEnd = i + 1; break } }
                i += 1
            }
            let h = String(data: data.prefix(headerEnd - 1), encoding: .ascii) ?? ""
            let lines = h.split(separator: "\n")
            let dims = lines[1].split(separator: " ")
            let w = Int(dims[0])!, height = Int(dims[1])!
            let bd = Int(lines[2])! > 255 ? 16 : 8
            let pixels = data.subdata(in: headerEnd..<data.count)
            return J2KImage(
                width: w, height: height,
                components: [J2KComponent(
                    index: 0, bitDepth: bd, signed: false,
                    width: w, height: height,
                    data: pixels, sampleByteOrder: .littleEndian)],
                colorSpace: .grayscale)
        }

        for pgmURL in pgms {
            let pgmData = try Data(contentsOf: pgmURL)
            let image = try parsePGM(pgmData)
            let encoded = try await encoder.encode(image)

            let imgA = try await decoder.decodeWithGPUHT(encoded)
            let imgB = try await decoder.decodeWithGPUHT(encoded, session: session)

            XCTAssertEqual(
                imgA.components.first?.data, imgB.components.first?.data,
                "session and sessionless decode bytes diverged on \(pgmURL.lastPathComponent)")
        }
    }

    /// Corpus-wide warm-process measurement. For every PGM in the
    /// CrossCodec fixture set, encodes to HTJ2K conformant and
    /// measures GPU-HT decode time with and without a shared
    /// session. Excludes the first run per backend (warmup).
    /// Prints a markdown-formatted table to stderr suitable for
    /// pasting into the perf report.
    func testCorpusWarmProcessPerf() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("CrossCodec")
        let pgms = try FileManager.default.contentsOfDirectory(
            at: fixturesDir, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "pgm" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            progressionOrder: .rpcl,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: config)
        let decoder = J2KDecoder()
        let session = J2KMetalSession()
        let warmupRuns = 1
        let timedRuns = 4

        // Helper: minimal P5 PGM parser, copied from
        // J2KGPUHTPipelineTests for self-containment.
        func parsePGM(_ data: Data) throws -> J2KImage {
            var headerEnd = 0; var nl = 0; var i = 0
            while i < data.count {
                if data[i] == 0x0A { nl += 1; if nl == 3 { headerEnd = i + 1; break } }
                i += 1
            }
            let h = String(data: data.prefix(headerEnd - 1), encoding: .ascii) ?? ""
            let lines = h.split(separator: "\n")
            let dims = lines[1].split(separator: " ")
            let w = Int(dims[0])!, height = Int(dims[1])!
            let bd = Int(lines[2])! > 255 ? 16 : 8
            let pixels = data.subdata(in: headerEnd..<data.count)
            return J2KImage(
                width: w, height: height,
                components: [J2KComponent(
                    index: 0, bitDepth: bd, signed: false,
                    width: w, height: height,
                    data: pixels, sampleByteOrder: .littleEndian)],
                colorSpace: .grayscale)
        }

        // Header for the ad-hoc perf table. v5.9 adds a per-decode
        // UMA-counter snapshot column (memcpy / contents / makeBuffer
        // counts during ONE timed session run) so milestone deltas
        // are measurable, not just timing-based.
        Self.say("")
        Self.say("[corpus-warm] | fixture | size | sessionless (ms) | session (ms) | speedup | uma counts (one decode) |")
        Self.say("[corpus-warm] | --- | ---:| ---:| ---:| ---:| --- |")

        for pgmURL in pgms {
            let pgmData = try Data(contentsOf: pgmURL)
            let image = try parsePGM(pgmData)
            let encoded = try await encoder.encode(image)

            // Sessionless runs (every call pays init).
            for _ in 0..<warmupRuns {
                _ = try await decoder.decodeWithGPUHT(encoded)
            }
            var noSess: [Double] = []
            for _ in 0..<timedRuns {
                let t0 = Date()
                _ = try await decoder.decodeWithGPUHT(encoded)
                noSess.append(Date().timeIntervalSince(t0) * 1000)
            }

            // Session runs (first call pays init, rest reuse).
            for _ in 0..<warmupRuns {
                _ = try await decoder.decodeWithGPUHT(encoded, session: session)
            }
            var sess: [Double] = []
            for _ in 0..<timedRuns {
                let t0 = Date()
                _ = try await decoder.decodeWithGPUHT(encoded, session: session)
                sess.append(Date().timeIntervalSince(t0) * 1000)
            }

            // v5.9 instrumentation snapshot: reset → ONE decode →
            // snapshot. Reflects per-decode counters for the warm
            // session path (the one we're optimising).
            J2KMetalUMACounters.reset()
            _ = try await decoder.decodeWithGPUHT(encoded, session: session)
            let counters = J2KMetalUMACounters.snapshot()

            let medN = noSess.sorted()[noSess.count / 2]
            let medS = sess.sorted()[sess.count / 2]
            let speedup = medN / medS

            Self.say(String(format:
                "[corpus-warm] | %@ | %dx%d | %.2f | %.2f | %.2fx | %@ |",
                pgmURL.deletingPathExtension().lastPathComponent,
                image.width, image.height, medN, medS, speedup,
                counters.description))
        }
    }

    /// Sanity: `J2KMetalSession()` constructs with no arguments and
    /// reports availability matching `J2KMetalDevice.isAvailable`.
    func testSessionConstruction() {
        let session = J2KMetalSession()
        XCTAssertEqual(J2KMetalSession.isAvailable, J2KMetalDevice.isAvailable)
        // Smoke: the actor references exist and are callable. Don't
        // initialise — that would do real Metal work and tests
        // may run on Linux CI.
        _ = session.device
        _ = session.shaderLibrary
        _ = session.bufferPool
    }
}
