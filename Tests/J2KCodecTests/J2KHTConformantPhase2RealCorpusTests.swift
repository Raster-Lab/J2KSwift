// J2KHTConformantPhase2RealCorpusTests.swift
// Phase 2 of the v5.15.0 HT encoder hardening plan — thorough
// validation on real medical PGM corpus + lossy mode.
//
// Phase 1 found zero corruption with synth gradient+LCG inputs. To be
// extra confident before removing the docstring caveat, this phase
// runs the same probe pattern over real medical 16-bit PGM payloads
// (which have realistic coefficient distributions after DWT) and adds
// lossy-mode coverage in case the original bug was lossy-only.
//
// All 7 cross-codec PGM fixtures in Tests/Fixtures/CrossCodec/ are
// non-power-of-2 in at least one dimension except ct_001, ct_003,
// xa_001 — making them direct stress tests for the alleged bug.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class HTConformantPhase2RealCorpusTests: XCTestCase {

    private struct FixtureCase {
        let name: String
        let path: String
    }

    private static let fixtures: [FixtureCase] = [
        FixtureCase(name: "ct_001",  path: "Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm"),
        FixtureCase(name: "ct_003",  path: "Tests/Fixtures/CrossCodec/ct_study_003_instance_000050.pgm"),
        FixtureCase(name: "dx_002",  path: "Tests/Fixtures/CrossCodec/dx_study_002_instance_000001.pgm"),
        FixtureCase(name: "mr_001",  path: "Tests/Fixtures/CrossCodec/mr_study_001_instance_000001.pgm"),
        FixtureCase(name: "mr_002",  path: "Tests/Fixtures/CrossCodec/mr_study_002_instance_000100.pgm"),
        FixtureCase(name: "px_001",  path: "Tests/Fixtures/CrossCodec/px_study_001_instance_000001.pgm"),
        FixtureCase(name: "xa_001",  path: "Tests/Fixtures/CrossCodec/xa_study_001_instance_000001.pgm"),
    ]

    private static let decompLevels: [Int] = [0, 3, 5]

    /// Run lossless self round-trip across the medical corpus.
    /// Critical correctness gate — if anything corrupts, Phase 2 stops.
    func testRealCorpus_LosslessConformant_SelfRoundTrip() async throws {
        var failures: [String] = []
        var summary = "name | dims | decomp | enc bytes | mismatch / total | result\n"

        for fx in Self.fixtures {
            guard let image = try loadPGM(fx.path) else {
                summary += "\(fx.name) | <missing> | - | - | - | SKIP\n"
                continue
            }
            let dims = "\(image.width)×\(image.height)"
            let isPow2 = isPowerOf2(image.width) && isPowerOf2(image.height)
            let label = "\(dims)\(isPow2 ? " (pow2)" : " (NPow2)")"

            for decomp in Self.decompLevels {
                let result = try await runRoundTrip(
                    image: image, decomp: decomp, lossless: true)
                let mc = result.mismatchCount
                let tag = mc == 0 ? "PASS" : "FAIL"
                let sample = "\(image.components[0].data.count)"
                summary += "\(fx.name) | \(label) | \(decomp) | \(result.encodedSize) | \(mc)/\(sample) | \(tag)\n"
                if mc != 0 {
                    failures.append("\(fx.name) decomp=\(decomp) lossless: \(mc) mismatches at first idx \(result.firstMismatchIndex ?? -1)")
                }
            }
        }

        print("=== HT Conformant Phase 2 LOSSLESS real-corpus self round-trip ===")
        print(summary)
        if !failures.isEmpty {
            print("FAILURES:")
            for f in failures { print("  \(f)") }
            XCTFail("Lossless real-corpus round-trip had \(failures.count) failure(s) — see log")
        }
    }

    /// Lossy mode wasn't covered by the Phase 1 sweep. We test that
    /// non-power-of-2 dimensions don't show DRAMATICALLY worse PSNR
    /// than power-of-2 dimensions at the same decomp level — which
    /// would be a smoking-gun signal of a non-power-of-2 specific bug.
    ///
    /// We don't test absolute PSNR thresholds: lossy at decomp=0 has
    /// bad PSNR universally regardless of pow2-ness because there's
    /// no DWT to quantize cleverly, which is unrelated to the bug we
    /// were investigating. So this test only flags failure when
    /// non-pow2 cells are >5 dB worse than the closest pow2 cell at
    /// the same decomp level.
    func testRealCorpus_LossyConformant_NonPow2NotWorseThanPow2() async throws {
        var pow2PSNR: [Int: [Double]] = [:]   // decomp → list of PSNRs from pow2 cells
        var np2PSNR:  [Int: [Double]] = [:]   // decomp → list of PSNRs from non-pow2 cells
        var summary = "name | dims | decomp | enc bytes | PSNR (dB) | type\n"

        let smallFixtures = Self.fixtures.filter {
            ["ct_001", "mr_002", "ct_003", "mr_001", "xa_001"].contains($0.name)
        }

        for fx in smallFixtures {
            guard let image = try loadPGM(fx.path) else {
                summary += "\(fx.name) | <missing> | - | - | - | SKIP\n"
                continue
            }
            let dims = "\(image.width)×\(image.height)"
            let isPow2 = isPowerOf2(image.width) && isPowerOf2(image.height)
            let label = "\(dims)\(isPow2 ? " (pow2)" : " (NPow2)")"

            for decomp in Self.decompLevels {
                let result = try await runRoundTrip(
                    image: image, decomp: decomp, lossless: false)
                let psnr = computePSNR16(orig: image.components[0].data,
                                          rec: result.decodedData,
                                          peak: 65535)
                summary += "\(fx.name) | \(label) | \(decomp) | \(result.encodedSize) | \(String(format: "%.2f", psnr)) | \(isPow2 ? "pow2" : "NPow2")\n"
                if isPow2 {
                    pow2PSNR[decomp, default: []].append(psnr)
                } else {
                    np2PSNR[decomp, default: []].append(psnr)
                }
            }
        }

        print("=== HT Conformant Phase 2 LOSSY real-corpus PSNR ===")
        print(summary)
        print("\nLossy PSNR comparison (mean per category, per decomp):")
        var failures: [String] = []
        for decomp in Self.decompLevels {
            let p2 = pow2PSNR[decomp] ?? []
            let np = np2PSNR[decomp]  ?? []
            guard !p2.isEmpty, !np.isEmpty else { continue }
            let p2Mean = p2.reduce(0, +) / Double(p2.count)
            let npMean = np.reduce(0, +) / Double(np.count)
            let delta  = npMean - p2Mean
            print("  decomp=\(decomp): pow2 mean=\(String(format: "%.2f", p2Mean)) dB, NPow2 mean=\(String(format: "%.2f", npMean)) dB, Δ=\(String(format: "%+.2f", delta)) dB")
            // If non-pow2 is >5 dB WORSE than pow2 it's a smoking gun.
            // If non-pow2 is *better*, that's just content-dependence —
            // ct/mr/xa images have different complexity profiles.
            if delta < -5.0 {
                failures.append("decomp=\(decomp): NPow2 mean PSNR \(npMean) dB is >5 dB below pow2 mean \(p2Mean) dB")
            }
        }
        if !failures.isEmpty {
            print("FAILURES:")
            for f in failures { print("  \(f)") }
            XCTFail("Non-pow2 PSNR significantly worse than pow2 — possible non-pow2 lossy bug")
        }
    }

    // MARK: helpers

    private struct RoundTripResult {
        let encodedSize: Int
        let mismatchCount: Int
        let firstMismatchIndex: Int?
        let decodedData: Data
    }

    private func runRoundTrip(
        image: J2KImage, decomp: Int, lossless: Bool
    ) async throws -> RoundTripResult {
        var cfg = J2KEncodingConfiguration(
            quality: lossless ? 1.0 : 0.9,
            lossless: lossless,
            decompositionLevels: decomp,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true)
        cfg.useReversibleFilter = lossless
        cfg.htj2kBlockFormat = .conformant
        cfg.bitrateMode = lossless ? .lossless : .constantQuality

        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        let decoded = try await J2KDecoder().decode(encoded)
        let origBytes = [UInt8](image.components[0].data)
        let recBytes  = [UInt8](decoded.components[0].data)
        let cmpCount  = min(origBytes.count, recBytes.count)
        var mismatchCount = 0
        var firstIdx: Int? = nil
        for i in 0..<cmpCount where origBytes[i] != recBytes[i] {
            mismatchCount += 1
            if firstIdx == nil { firstIdx = i }
        }
        return RoundTripResult(
            encodedSize: encoded.count,
            mismatchCount: mismatchCount,
            firstMismatchIndex: firstIdx,
            decodedData: decoded.components[0].data)
    }

    private func loadPGM(_ relativePath: String, file: String = #filePath) throws -> J2KImage? {
        // Derive the package root from this source file's path —
        // robust to whatever CWD swift test launches with.
        let testFileURL = URL(fileURLWithPath: file)
        // testFileURL is …/J2KSwift/Tests/J2KCodecTests/<this-file>.swift
        // Package root is two levels up.
        let packageRoot = testFileURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            packageRoot.appendingPathComponent(relativePath),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(relativePath),
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        // Parse P5 header: P5\nW H\nMAX\n[payload]
        guard data.count > 4, data[0] == 0x50, data[1] == 0x35 else {
            throw NSError(domain: "PGM", code: 1, userInfo: [NSLocalizedDescriptionKey: "not P5"])
        }
        var i = 2
        var fields: [Int] = []
        while i < data.count, fields.count < 3 {
            let b = data[i]
            if b == 0x23 {
                while i < data.count, data[i] != 0x0A { i += 1 }
                continue
            }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                i += 1
                continue
            }
            var num = 0
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { break }
                guard c >= 0x30 && c <= 0x39 else {
                    throw NSError(domain: "PGM", code: 2, userInfo: [NSLocalizedDescriptionKey: "non-numeric in field"])
                }
                num = num * 10 + Int(c - 0x30)
                i += 1
            }
            fields.append(num)
        }
        // Skip exactly one whitespace byte before payload.
        if i < data.count {
            let b = data[i]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                i += 1
            }
        }
        let width = fields[0]
        let height = fields[1]
        let maxVal = fields[2]
        let bitDepth = maxVal > 255 ? 16 : 8
        let payload = data.subdata(in: i..<data.count)
        let component = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            data: payload,
            sampleByteOrder: bitDepth > 8 ? .bigEndian : nil)
        return J2KImage(width: width, height: height, components: [component])
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

    private func isPowerOf2(_ n: Int) -> Bool {
        return n > 0 && (n & (n - 1)) == 0
    }
}
