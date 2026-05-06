// CrossVersionDeltaBenchmark.swift
//
// Self-contained encode/decode harness designed to be dropped onto
// **any** historical revision of J2KSwift back to v5.38.0 and run
// without modification.
//
// Uses only the long-stable public API:
//   - J2KEncodingConfiguration init (quality / lossless / HT / etc.)
//   - J2KEncoder.encode(_: J2KImage) async throws -> Data
//   - J2KDecoder.decode(_: Data) async throws -> J2KImage
//   - J2KImage / J2KComponent designated initializers
//
// Captures, for every (fixture, mode) pair:
//   - encode wall ms (median of N)
//   - decode wall ms (median of N)
//   - bytes
//   - self-roundtrip first-mismatch index (0 == bit-exact)
//   - codestream md5 (so caller can diff bytes between runs/versions)
//
// Writes encoded bytes to $J2K_DELTA_OUT/$LABEL/{fixture}_{mode}.j2c
// so an offline shell driver can ojph_expand and decode-diff them
// for quality validation. Path defaults to /tmp/j2k_delta_${LABEL}.

import XCTest
import Foundation
import CryptoKit
@testable import J2KCore
@testable import J2KCodec

final class CrossVersionDeltaBenchmark: XCTestCase {

    // MARK: - Fixtures

    private struct Fixture {
        let label: String
        let path: String
        let bitDepth: Int
    }

    /// 16-bit medical PGMs that ship in Tests/Fixtures/CrossCodec/
    /// at every revision back to v5.38.0. Bit-depth metadata is hard-
    /// coded to match `expected_results.csv` from the same directory.
    private func fixtures() -> [Fixture] {
        let root = pgmRoot()
        return [
            Fixture(label: "MR-small_180x180",   path: "\(root)/mr_study_002_instance_000100.pgm", bitDepth: 16),
            Fixture(label: "CT_512x512",         path: "\(root)/ct_study_001_instance_000001.pgm", bitDepth: 16),
            Fixture(label: "CT_512x512_alt",     path: "\(root)/ct_study_003_instance_000050.pgm", bitDepth: 16),
            Fixture(label: "MR_886x886",         path: "\(root)/mr_study_001_instance_000001.pgm", bitDepth: 16),
            Fixture(label: "XA_1024x1024",       path: "\(root)/xa_study_001_instance_000001.pgm", bitDepth: 16),
            Fixture(label: "PX_2459x1316",       path: "\(root)/px_study_001_instance_000001.pgm", bitDepth: 16),
            Fixture(label: "DX_2800x2288",       path: "\(root)/dx_study_002_instance_000001.pgm", bitDepth: 16),
        ]
    }

    private func pgmRoot() -> String {
        // First try the location relative to this source file (works
        // when SourceSwift is invoked with --package-path …).
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // J2KCodecTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures/CrossCodec").path
        if FileManager.default.fileExists(atPath: here) { return here }
        // Fallback: process working dir relative.
        return "Tests/Fixtures/CrossCodec"
    }

    // MARK: - PGM loader

    /// Reads a P5 16-bit big-endian PGM and returns (w, h, BE-byte
    /// data). Tolerant of comments and various whitespace styles.
    private func loadPGM16(_ path: String) throws -> (Int, Int, Data) {
        let url = URL(fileURLWithPath: path)
        let raw = try Data(contentsOf: url)

        // Parse header (ASCII until pixel data starts).
        var idx = 0
        func readToken() -> String {
            // Skip whitespace and comments
            while idx < raw.count {
                let b = raw[idx]
                if b == 0x23 {  // '#' — comment to end-of-line
                    while idx < raw.count && raw[idx] != 0x0A { idx += 1 }
                } else if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                    idx += 1
                } else {
                    break
                }
            }
            let start = idx
            while idx < raw.count {
                let b = raw[idx]
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                    break
                }
                idx += 1
            }
            return String(data: raw.subdata(in: start..<idx),
                          encoding: .ascii) ?? ""
        }

        let magic = readToken()
        let widthStr = readToken()
        let heightStr = readToken()
        let maxvalStr = readToken()
        // Single whitespace byte after maxval, then pixels.
        idx += 1

        guard magic == "P5",
              let w = Int(widthStr),
              let h = Int(heightStr),
              let maxval = Int(maxvalStr) else {
            throw NSError(domain: "PGM", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                     "Bad PGM header in \(path)"])
        }
        let bytesPerSample = (maxval > 255) ? 2 : 1
        let needed = w * h * bytesPerSample
        guard raw.count - idx >= needed else {
            throw NSError(domain: "PGM", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                                     "Truncated PGM \(path): " +
                                     "have \(raw.count - idx) bytes, " +
                                     "need \(needed)"])
        }
        return (w, h, raw.subdata(in: idx..<(idx + needed)))
    }

    // MARK: - Encode/decode helpers

    private func htConfig(tileSize: (Int, Int) = (0, 0)) -> J2KEncodingConfiguration {
        // Designated args common to v5.38.0 and current. Avoids any
        // newer-only arguments (tileLayoutMode, etc.) so this file
        // compiles unchanged on older revisions.
        return J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            tileSize: tileSize,
            bitrateMode: .lossless,
            maxThreads: 8,
            useHTJ2K: true,
            useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
    }

    private func image(width: Int, height: Int, bitDepth: Int,
                       data: Data,
                       tileSize: (Int, Int) = (0, 0)) -> J2KImage {
        let comp = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: data,
            sampleByteOrder: .bigEndian)
        return J2KImage(
            width: width, height: height,
            components: [comp],
            tileWidth: tileSize.0, tileHeight: tileSize.1)
    }

    private func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Output dir

    private func outDir() -> String {
        let label = ProcessInfo.processInfo.environment["LABEL"] ?? "current"
        let base = ProcessInfo.processInfo.environment["J2K_DELTA_OUT"]
            ?? "/tmp/j2k_delta_\(label)"
        try? FileManager.default.createDirectory(
            atPath: base, withIntermediateDirectories: true)
        return base
    }

    // MARK: - Single benchmark cell

    private func benchOne(_ fix: Fixture,
                          modeLabel: String,
                          tileSize: (Int, Int),
                          runs: Int) async throws -> [String: String] {
        let (w, h, samples) = try loadPGM16(fix.path)
        let img = image(width: w, height: h, bitDepth: fix.bitDepth,
                        data: samples, tileSize: tileSize)
        let cfg = htConfig(tileSize: tileSize)
        let enc = J2KEncoder(encodingConfiguration: cfg)
        let dec = J2KDecoder()

        // Warm-up: 1 encode + 1 decode (excluded from timing).
        let warmBytes = try await enc.encode(img)
        _ = try await dec.decode(warmBytes)

        var encMs: [Double] = []
        var decMs: [Double] = []
        var lastBytes = Data()
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            let bytes = try await enc.encode(img)
            let t1 = Date().timeIntervalSinceReferenceDate
            encMs.append((t1 - t0) * 1000.0)
            lastBytes = bytes

            let d0 = Date().timeIntervalSinceReferenceDate
            let decoded = try await dec.decode(bytes)
            let d1 = Date().timeIntervalSinceReferenceDate
            decMs.append((d1 - d0) * 1000.0)

            // Roundtrip check on first run.
            if encMs.count == 1 {
                let dData = decoded.components[0].data
                XCTAssertEqual(dData.count, samples.count,
                    "[\(fix.label) \(modeLabel)] decoded sample count mismatch")
                var firstDiff = -1
                let n = min(dData.count, samples.count)
                dData.withUnsafeBytes { (dRaw: UnsafeRawBufferPointer) in
                    samples.withUnsafeBytes { (sRaw: UnsafeRawBufferPointer) in
                        let db = dRaw.bindMemory(to: UInt8.self)
                        let sb = sRaw.bindMemory(to: UInt8.self)
                        for i in 0..<n where db[i] != sb[i] {
                            firstDiff = i; break
                        }
                    }
                }
                if firstDiff >= 0 {
                    XCTFail("[\(fix.label) \(modeLabel)] " +
                            "self-roundtrip mismatch at byte \(firstDiff)")
                }
            }
        }
        encMs.sort(); decMs.sort()
        let encMed = encMs[runs / 2]
        let decMed = decMs[runs / 2]

        // Persist the codestream for offline cross-codec verification.
        let dir = outDir()
        let outPath = "\(dir)/\(fix.label)_\(modeLabel).j2c"
        try lastBytes.write(to: URL(fileURLWithPath: outPath))

        return [
            "fixture":  fix.label,
            "shape":    "\(w)x\(h)",
            "px":       "\(w * h)",
            "mode":     modeLabel,
            "enc_ms":   String(format: "%.2f", encMed),
            "dec_ms":   String(format: "%.2f", decMed),
            "bytes":    "\(lastBytes.count)",
            "md5":      md5Hex(lastBytes),
            "out":      outPath,
        ]
    }

    // MARK: - Benchmark entry point

    /// Single-tile + 2x2 tile sweep across every medical fixture.
    /// Median of 5 by default; override via env $RUNS.
    func testCrossVersionDeltaBenchmark() async throws {
        #if DEBUG
        // We allow DEBUG runs but they will be 50–100× slower.
        // The shell driver invokes us with `swift test -c release`.
        #endif

        let runs = Int(ProcessInfo.processInfo.environment["RUNS"] ?? "5") ?? 5
        let label = ProcessInfo.processInfo.environment["LABEL"] ?? "current"

        let header = "| fixture | shape | px | mode | enc ms | dec ms | bytes | md5 |"
        let sep    = "|---|---|---:|:---:|---:|---:|---:|---|"
        print("=== CROSS-VERSION DELTA BENCHMARK (label=\(label), runs=\(runs)) ===")
        print(header)
        print(sep)

        // CSV mirror so the shell driver can parse without re-grepping.
        let csvPath = "\(outDir())/results.csv"
        var csvLines: [String] = ["fixture,shape,px,mode,enc_ms,dec_ms,bytes,md5,out"]

        for fix in fixtures() {
            // Single-tile (works at every version).
            let single = try await benchOne(
                fix, modeLabel: "single", tileSize: (0, 0), runs: runs)
            print("| \(single["fixture"]!) | \(single["shape"]!) | "
                  + "\(single["px"]!) | \(single["mode"]!) | "
                  + "\(single["enc_ms"]!) | \(single["dec_ms"]!) | "
                  + "\(single["bytes"]!) | `\(single["md5"]!.prefix(12))…` |")
            csvLines.append([
                single["fixture"]!, single["shape"]!, single["px"]!,
                single["mode"]!, single["enc_ms"]!, single["dec_ms"]!,
                single["bytes"]!, single["md5"]!, single["out"]!,
            ].joined(separator: ","))

            // 2x2 multi-tile via J2KImage.tileWidth/tileHeight (also
            // available at v5.38.0). Pick a tile that splits cleanly.
            let (w, h, _) = try loadPGM16(fix.path)
            // Skip tiny fixtures where 2x2 is meaningless.
            if w >= 256 && h >= 256 {
                let tileW = (w + 1) / 2
                let tileH = (h + 1) / 2
                let multi = try await benchOne(
                    fix, modeLabel: "tile2x2",
                    tileSize: (tileW, tileH), runs: runs)
                print("| \(multi["fixture"]!) | \(multi["shape"]!) | "
                      + "\(multi["px"]!) | \(multi["mode"]!) | "
                      + "\(multi["enc_ms"]!) | \(multi["dec_ms"]!) | "
                      + "\(multi["bytes"]!) | `\(multi["md5"]!.prefix(12))…` |")
                csvLines.append([
                    multi["fixture"]!, multi["shape"]!, multi["px"]!,
                    multi["mode"]!, multi["enc_ms"]!, multi["dec_ms"]!,
                    multi["bytes"]!, multi["md5"]!, multi["out"]!,
                ].joined(separator: ","))
            }
        }

        try csvLines.joined(separator: "\n").write(
            toFile: csvPath, atomically: true, encoding: .utf8)
        print()
        print("CSV written to: \(csvPath)")
        print("Codestreams written to: \(outDir())")
    }
}
