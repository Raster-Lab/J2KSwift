// DecoderAPIWarmSessionTests.swift
//
// v6.3.0 work item F2 — plumbs `J2KMetalSession.processShared`
// through the no-session overloads of `decodeGPU(_:)` and
// `decodeWithGPUHT(_:)`, mirroring v6.2.0 D3 (#316) on the
// default `decode(_:)` entry point.
//
// Pre-F2 these no-session overloads built a fresh
// `DecoderPipeline()` per call without `metalSession`, so every
// fresh `J2KDecoder().decodeGPU(data)` paid the cold-start cost
// (~25-30 ms Metal init per memory `project_gpu97_warm_session_ceiling.md`).
// Post-F2 they share the same singleton session the default
// `decode()` uses, so successive calls amortise cold-start across
// the process.
//
// Two contracts to validate:
//
//   1. **Bit-exact**: result of `decodeGPU(data)` equals result of
//      `decodeGPU(data, session: explicit)` byte-for-byte. F2 only
//      changes which session is used, not the decode behaviour.
//
//   2. **Wall-time**: successive calls to the no-session overload
//      should run at warm-session speed (T_min over N calls << T_1).
//      Reported as a human-review printout — not asserted because
//      timings vary across hosts. The contract is "warm session is
//      used" as evidenced by the steady-state speed approaching the
//      explicit-session baseline.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class DecoderAPIWarmSessionTests: XCTestCase {

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 {
                while i < raw.count, raw[i] != 0x0A { i += 1 }
                continue
            }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    // MARK: - Bit-exact contract

    /// `decodeGPU(_:)` (no-session overload using `processShared`)
    /// must return byte-identical pixels to `decodeGPU(_:session:)`
    /// (explicit-session overload). F2 only changes which session is
    /// used, not the decode behaviour.
    func testDecodeGPU_NoSessionOverload_BitExactWithExplicitSession() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)

        let noSession = try await J2KDecoder().decodeGPU(codestream)
        let session = J2KMetalSession()
        let explicit = try await J2KDecoder().decodeGPU(codestream, session: session)

        XCTAssertEqual(noSession.components[0].data, explicit.components[0].data,
            "decodeGPU no-session vs explicit-session pixels diverged")
    }

    /// Same contract for `decodeWithGPUHT(_:)`.
    func testDecodeWithGPUHT_NoSessionOverload_BitExactWithExplicitSession() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)

        let noSession = try await J2KDecoder().decodeWithGPUHT(codestream)
        let session = J2KMetalSession()
        let explicit = try await J2KDecoder().decodeWithGPUHT(codestream, session: session)

        XCTAssertEqual(noSession.components[0].data, explicit.components[0].data,
            "decodeWithGPUHT no-session vs explicit-session pixels diverged")
    }

    // MARK: - Wall-time A/B

    /// Wall-time A/B for the no-session overloads. F2's contract is
    /// that successive calls to `J2KDecoder().decodeGPU(data)` run
    /// at warm-session speed (the singleton `processShared` amortises
    /// cold-start across the process). This is reported, not asserted
    /// — the printout is the F2 deliverable per `RELEASING.md`'s
    /// "release notes ship the data" principle.
    func testDecoderAPI_WarmSession_WallTimeAB() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }
        let codestream = try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)

        // Pre-warm processShared so call 1 below is the F2 case
        // (warm singleton). Without preWarm, call 1's cost would be
        // dominated by whatever earlier test happened to warm
        // processShared first, making the timing noisy.
        try await J2KMetalSession.processShared.preWarm()

        // Decode N times via the no-session overload. With F2,
        // every call shares `processShared` so all N calls run at
        // warm-session speed.
        let n = 5
        var decodeGPUMs: [Double] = []
        var decodeWithGPUHTMs: [Double] = []
        for _ in 0..<n {
            let t0 = DispatchTime.now()
            _ = try await J2KDecoder().decodeGPU(codestream)
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            decodeGPUMs.append(dt)
        }
        for _ in 0..<n {
            let t0 = DispatchTime.now()
            _ = try await J2KDecoder().decodeWithGPUHT(codestream)
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            decodeWithGPUHTMs.append(dt)
        }

        // Baseline: explicit-session API. Each call here uses the
        // same `session` so we get the true warm-session per-call
        // wall time without any overload-dispatch cost.
        let baseline = J2KMetalSession()
        try await baseline.preWarm()
        var baselineGPUMs: [Double] = []
        var baselineHTMs: [Double] = []
        for _ in 0..<n {
            let t0 = DispatchTime.now()
            _ = try await J2KDecoder().decodeGPU(codestream, session: baseline)
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            baselineGPUMs.append(dt)
        }
        for _ in 0..<n {
            let t0 = DispatchTime.now()
            _ = try await J2KDecoder().decodeWithGPUHT(codestream, session: baseline)
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            baselineHTMs.append(dt)
        }

        let processor = String(cString: getProcessorName())

        print()
        print("=== v6.3.0 F2 — decoder API warm-session A/B ===")
        print("Processor: \(processor)")
        print("Image: DX 2800×2288 HT-conformant lossless 5/3, n=\(n) per cell, min-of-N")
        print()
        print("| API                                             | min ms | mean ms |")
        print("|---|---:|---:|")
        print(String(format: "| `decodeGPU(_:)` (F2 no-session, processShared)  | %6.1f | %7.1f |",
                     decodeGPUMs.min() ?? 0,
                     decodeGPUMs.reduce(0, +) / Double(decodeGPUMs.count)))
        print(String(format: "| `decodeGPU(_:session:)` (explicit-session)      | %6.1f | %7.1f |",
                     baselineGPUMs.min() ?? 0,
                     baselineGPUMs.reduce(0, +) / Double(baselineGPUMs.count)))
        print(String(format: "| `decodeWithGPUHT(_:)` (F2 no-session)           | %6.1f | %7.1f |",
                     decodeWithGPUHTMs.min() ?? 0,
                     decodeWithGPUHTMs.reduce(0, +) / Double(decodeWithGPUHTMs.count)))
        print(String(format: "| `decodeWithGPUHT(_:session:)` (explicit-session)| %6.1f | %7.1f |",
                     baselineHTMs.min() ?? 0,
                     baselineHTMs.reduce(0, +) / Double(baselineHTMs.count)))
        print()
        print("F2 contract: no-session min ≈ explicit-session min (within ~5%)")
        print("→ no-session overload is using the warm singleton, not paying cold-start.")
    }

    private func getProcessorName() -> [CChar] {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
        return name
    }
}
