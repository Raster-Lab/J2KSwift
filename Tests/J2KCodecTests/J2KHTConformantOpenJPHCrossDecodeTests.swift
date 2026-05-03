// J2KHTConformantOpenJPHCrossDecodeTests.swift
// Phase 1 of the v5.15.0 HT encoder hardening plan — OpenJPH cross-decode.
//
// The block-level and full-pipeline self round-trip probes both pass at
// 100% across the dimension grid. This test is the decisive third leg:
// hand J2KSwift's `.conformant` output to `ojph_expand` and check the
// reconstructed pixels match the input. If both pipelines round-trip
// AND OpenJPH cross-decodes correctly, the docstring caveat at
// J2KEncodingPresets.swift:341-347 is stale and the v5.15.0 plan
// reduces to: remove the caveat + lift the existing matrix into a
// permanent regression gate.
//
// Skipped automatically when /opt/homebrew/bin/ojph_expand is missing.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class HTConformantOpenJPHCrossDecodeTests: XCTestCase {

    private let ojphExpand = "/opt/homebrew/bin/ojph_expand"

    private func skipIfMissing() throws {
        guard FileManager.default.isExecutableFile(atPath: ojphExpand) else {
            throw XCTSkip("ojph_expand not found — cross-decode test skipped")
        }
    }

    // Same dim grid as the self round-trip probe so the matrices line up
    // 1:1 in the Phase 1 report. Trimmed slightly because each cell now
    // forks a process; full grid would be ~250 forks.
    private static let imageDims: [(w: Int, h: Int)] = [
        (32, 32), (33, 33), (31, 31),
        (64, 64), (65, 65), (63, 63),
        (33, 64), (64, 33),
        (128, 128), (129, 129), (127, 127),
        (257, 257),
        (37, 53), (79, 61), (101, 113),
    ]
    private static let decompLevels: [Int] = [0, 1, 3, 5]
    private static let bitDepths:    [Int] = [8, 16]

    private struct CrossCell {
        let width: Int
        let height: Int
        let bitDepth: Int
        let decomp: Int
        let mismatchCount: Int
        let firstMismatchIndex: Int?
        let firstExpected: UInt32?
        let firstObserved: UInt32?
        let encodedSize: Int
        let stage: String          // "encode" / "ojph" / "compare" / "ok"
        let stageError: String?
        var passed: Bool { mismatchCount == 0 && stageError == nil }
    }

    func testCrossDecode_NonPowerOf2_ojphExpandSweep() async throws {
        try skipIfMissing()

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("J2K_HT_OJPH_Probe_\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var cells: [CrossCell] = []
        for bd in Self.bitDepths {
            for (w, h) in Self.imageDims {
                for decomp in Self.decompLevels {
                    let cell = await runCross(
                        width: w, height: h, bitDepth: bd, decomp: decomp,
                        scratch: scratch)
                    cells.append(cell)
                }
            }
        }

        let total = cells.count
        let failed = cells.filter { !$0.passed }
        let p2  = cells.filter { isPowerOf2($0.width) && isPowerOf2($0.height) }
        let np2 = cells.filter { !isPowerOf2($0.width) || !isPowerOf2($0.height) }
        let p2F  = p2.filter  { !$0.passed }
        let np2F = np2.filter { !$0.passed }
        let perDecomp = Dictionary(grouping: cells, by: { $0.decomp })
            .mapValues { rows in (rows.count, rows.filter { !$0.passed }.count) }
        let perBitDepth = Dictionary(grouping: cells, by: { $0.bitDepth })
            .mapValues { rows in (rows.count, rows.filter { !$0.passed }.count) }
        let perStage = Dictionary(grouping: failed, by: { $0.stage })
            .mapValues { $0.count }

        print("=== HT Conformant OPENJPH CROSS-DECODE non-power-of-2 sweep ===")
        print("Total cells: \(total)")
        print("Failed:      \(failed.count) (\(percent(failed.count, total)))")
        print("  power-of-2 dims:     \(p2F.count) / \(p2.count) (\(percent(p2F.count, p2.count)))")
        print("  non-power-of-2 dims: \(np2F.count) / \(np2.count) (\(percent(np2F.count, np2.count)))")
        print("\nPer-decomp failure rate:")
        for (d, (t, f)) in perDecomp.sorted(by: { $0.key < $1.key }) {
            print("  decomp=\(d)  \(f)/\(t) (\(percent(f, t)))")
        }
        print("\nPer-bitDepth failure rate:")
        for (bd, (t, f)) in perBitDepth.sorted(by: { $0.key < $1.key }) {
            print("  bitDepth=\(bd)  \(f)/\(t) (\(percent(f, t)))")
        }
        if !perStage.isEmpty {
            print("\nFailures by stage:")
            for (s, c) in perStage.sorted(by: { $0.key < $1.key }) {
                print("  \(s): \(c)")
            }
        }

        let sortedFailed = failed.sorted { a, b in
            if a.bitDepth != b.bitDepth { return a.bitDepth < b.bitDepth }
            if a.decomp != b.decomp { return a.decomp < b.decomp }
            if a.width != b.width { return a.width < b.width }
            return a.height < b.height
        }
        print("\nFirst 50 failures (bd | decomp | w×h | stage | mismatches | err):")
        for c in sortedFailed.prefix(50) {
            let dims = "\(c.width)×\(c.height)".padding(toLength: 10, withPad: " ", startingAt: 0)
            let bd   = String(format: "%2d", c.bitDepth)
            let dc   = String(format: "%d", c.decomp)
            let mc   = String(format: "%6d", c.mismatchCount)
            let err  = (c.stageError ?? "").prefix(50)
            print("  \(bd) | \(dc) | \(dims) | \(c.stage) | \(mc) | \(err)")
        }

        var csv = "width,height,bit_depth,decomp,mismatch_count,first_expected_hex,first_observed_hex,encoded_size,stage,stage_error,passed\n"
        for c in cells {
            csv += "\(c.width),\(c.height),\(c.bitDepth),\(c.decomp),\(c.mismatchCount),"
            csv += c.firstExpected.map { String(format: "0x%08x", $0) } ?? ""
            csv += ","
            csv += c.firstObserved.map { String(format: "0x%08x", $0) } ?? ""
            csv += ",\(c.encodedSize),\(c.stage),"
            csv += (c.stageError ?? "").replacingOccurrences(of: ",", with: ";")
            csv += ",\(c.passed)\n"
        }
        let outPath = "/tmp/J2K_HT_NonPowerOf2_OJPHCrossMatrix.csv"
        try csv.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("\nCSV dump → \(outPath)")

        // Phase 3 hardening: strict regression gate. OpenJPH-decode
        // failure on conformant output is the highest-severity bug
        // class for J2KSwift's interop story.
        XCTAssertGreaterThan(cells.count, 0, "sweep produced no cells")
        XCTAssertEqual(failed.count, 0,
                       "regression: \(failed.count) cells failed OpenJPH cross-decode — see test log + /tmp CSV")
    }

    // MARK: helpers

    private func runCross(
        width: Int, height: Int, bitDepth: Int, decomp: Int,
        scratch: URL
    ) async -> CrossCell {
        let bytesPerSample = (bitDepth + 7) / 8
        let count = width * height
        let maxVal = (1 << bitDepth) - 1
        var s: UInt64 = 0xfeed_face_dead_beef &+ UInt64(width) &* 1009 &+ UInt64(height) &* 7919
        var bytes = [UInt8](repeating: 0, count: count * bytesPerSample)
        for i in 0..<count {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let x = i % width
            let y = i / width
            let gradient = (x * 31 + y * 17) & maxVal
            let noise = Int(s >> 40) & maxVal
            let sample = (gradient ^ noise) & maxVal
            if bytesPerSample == 1 {
                bytes[i] = UInt8(sample)
            } else {
                bytes[i * 2]     = UInt8((sample >> 8) & 0xFF)
                bytes[i * 2 + 1] = UInt8(sample & 0xFF)
            }
        }
        let data = Data(bytes)
        let component = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height,
            data: data,
            sampleByteOrder: bitDepth > 8 ? .bigEndian : nil)
        let image = J2KImage(width: width, height: height, components: [component])

        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: decomp,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true)
        cfg.useReversibleFilter = true
        cfg.htj2kBlockFormat = .conformant
        cfg.bitrateMode = .lossless

        let encoded: Data
        do {
            encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        } catch {
            return CrossCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count, firstMismatchIndex: 0,
                firstExpected: nil, firstObserved: nil,
                encodedSize: 0, stage: "encode", stageError: "\(error)")
        }

        let cellId = "w\(width)_h\(height)_bd\(bitDepth)_d\(decomp)"
        let j2cURL = scratch.appendingPathComponent("\(cellId).j2c")
        let pgmURL = scratch.appendingPathComponent("\(cellId).pgm")
        do {
            try encoded.write(to: j2cURL)
        } catch {
            return CrossCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count, firstMismatchIndex: 0,
                firstExpected: nil, firstObserved: nil,
                encodedSize: encoded.count, stage: "encode",
                stageError: "write failed: \(error)")
        }

        // Run ojph_expand
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ojphExpand)
        proc.arguments = ["-i", j2cURL.path, "-o", pgmURL.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return CrossCell(
                    width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                    mismatchCount: count, firstMismatchIndex: 0,
                    firstExpected: nil, firstObserved: nil,
                    encodedSize: encoded.count, stage: "ojph",
                    stageError: "exit=\(proc.terminationStatus) log=\(log.prefix(80))")
            }
        } catch {
            return CrossCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count, firstMismatchIndex: 0,
                firstExpected: nil, firstObserved: nil,
                encodedSize: encoded.count, stage: "ojph", stageError: "\(error)")
        }

        // Read PGM produced by ojph_expand and compare pixel bytes
        let pgmData: Data
        do {
            pgmData = try Data(contentsOf: pgmURL)
        } catch {
            return CrossCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count, firstMismatchIndex: 0,
                firstExpected: nil, firstObserved: nil,
                encodedSize: encoded.count, stage: "compare",
                stageError: "read pgm: \(error)")
        }
        guard let payload = stripPGMHeader(pgmData) else {
            return CrossCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count, firstMismatchIndex: 0,
                firstExpected: nil, firstObserved: nil,
                encodedSize: encoded.count, stage: "compare",
                stageError: "PGM header parse failed")
        }
        let cmpCount = min(bytes.count, payload.count)
        var mismatchCount = 0
        var firstIdx: Int? = nil
        var firstExp: UInt32? = nil
        var firstObs: UInt32? = nil
        for i in 0..<cmpCount where bytes[i] != payload[payload.startIndex + i] {
            mismatchCount += 1
            if firstIdx == nil {
                firstIdx = i
                firstExp = UInt32(bytes[i])
                firstObs = UInt32(payload[payload.startIndex + i])
            }
        }
        let stage = mismatchCount == 0 ? "ok" : "compare"
        return CrossCell(
            width: width, height: height, bitDepth: bitDepth, decomp: decomp,
            mismatchCount: mismatchCount,
            firstMismatchIndex: firstIdx,
            firstExpected: firstExp, firstObserved: firstObs,
            encodedSize: encoded.count, stage: stage, stageError: nil)
    }

    /// Strip a P5 PGM header and return the payload Data slice.
    /// Tolerates `#` comment lines in any whitespace position.
    private func stripPGMHeader(_ data: Data) -> Data? {
        guard data.count > 4, data[0] == 0x50, data[1] == 0x35 else {
            return nil  // not "P5"
        }
        var i = 2
        var fieldsConsumed = 0
        // Skip whitespace and comments until we've consumed 3 numeric
        // fields: width, height, max-value.
        while i < data.count, fieldsConsumed < 3 {
            let b = data[i]
            if b == 0x23 {  // '#' — skip to end-of-line
                while i < data.count, data[i] != 0x0A { i += 1 }
                continue
            }
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                i += 1
                continue
            }
            // Numeric field — consume until next whitespace
            while i < data.count {
                let c = data[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    break
                }
                i += 1
            }
            fieldsConsumed += 1
        }
        // Skip exactly one trailing whitespace byte to land on payload.
        while i < data.count {
            let b = data[i]
            if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                i += 1
                break
            }
            i += 1
        }
        guard i <= data.count else { return nil }
        return data.subdata(in: i..<data.count)
    }

    private func isPowerOf2(_ n: Int) -> Bool {
        return n > 0 && (n & (n - 1)) == 0
    }

    private func percent(_ a: Int, _ b: Int) -> String {
        if b == 0 { return "0%" }
        return String(format: "%.1f%%", Double(a) * 100 / Double(b))
    }
}
