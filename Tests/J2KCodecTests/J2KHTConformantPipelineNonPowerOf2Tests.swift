// J2KHTConformantPipelineNonPowerOf2Tests.swift
// Phase 1 of the v5.15.0 HT encoder hardening plan — full-pipeline
// probe.
//
// Block-level probe (J2KHTConformantNonPowerOf2ProbeTests) showed the
// raw HTBlockEncoderConformant + HTBlockDecoderConformant round-trip
// is bit-exact across every dimension we care about. So if there's a
// non-power-of-2 corruption bug it has to live UPSTREAM of the block
// coder — in subband-to-block tiling, in the encoder pipeline's
// integration with the block coder, or only manifest with specific
// coefficient values that synthetic patterns don't reproduce.
//
// This file exercises the FULL J2KEncoder → J2KDecoder pipeline at
// non-power-of-2 image dimensions and varying decomposition levels.
// Lossless mode means corruption (if present) shows as exact pixel
// mismatch.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class HTConformantPipelineNonPowerOf2Tests: XCTestCase {

    /// Image dimensions to probe — mix of power-of-2, almost-power-of-2,
    /// and odd primes to expose any subband-geometry edge case.
    private static let imageDims: [(w: Int, h: Int)] = [
        (32, 32), (33, 33), (31, 31),
        (64, 64), (65, 65), (63, 63),
        (33, 64), (64, 33), (65, 31), (31, 65),
        (128, 128), (129, 129), (127, 127),
        (257, 257), (255, 255),
        (37, 53), (79, 61), (101, 113), (511, 511),
    ]

    /// Decomposition levels to sweep — 0 disables DWT, 5 is the public
    /// default. Each level halves subband dims, so odd image sizes
    /// produce a chain of ceiling-divided odd subbands at deep levels.
    private static let decompLevels: [Int] = [0, 1, 3, 5]

    private static let bitDepths: [Int] = [8, 12, 16]

    private struct PipelineCell {
        let width: Int
        let height: Int
        let bitDepth: Int
        let decomp: Int
        let mismatchCount: Int
        let firstMismatchIndex: Int?
        let firstExpected: UInt32?
        let firstObserved: UInt32?
        let encodedSize: Int
        let encodeError: String?
        let decodeError: String?
        var passed: Bool {
            mismatchCount == 0 && encodeError == nil && decodeError == nil
        }
    }

    func testFullPipeline_NonPowerOf2_LosslessHTConformantSweep() async throws {
        var cells: [PipelineCell] = []
        for bd in Self.bitDepths {
            for (w, h) in Self.imageDims {
                for decomp in Self.decompLevels {
                    let cell = await runPipeline(
                        width: w, height: h, bitDepth: bd, decomp: decomp)
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

        print("=== HT Conformant FULL-PIPELINE non-power-of-2 sweep ===")
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

        let sortedFailed = failed.sorted { a, b in
            if a.bitDepth != b.bitDepth { return a.bitDepth < b.bitDepth }
            if a.decomp != b.decomp { return a.decomp < b.decomp }
            if a.width != b.width { return a.width < b.width }
            return a.height < b.height
        }
        print("\nFirst 50 failures (bd | decomp | w×h | mismatches | [idx] expected→observed | enc=bytes | err):")
        for c in sortedFailed.prefix(50) {
            let dims = "\(c.width)×\(c.height)".padding(toLength: 10, withPad: " ", startingAt: 0)
            let bd   = String(format: "%2d", c.bitDepth)
            let dc   = String(format: "%d", c.decomp)
            let mc   = String(format: "%6d", c.mismatchCount)
            let idx  = c.firstMismatchIndex.map(String.init) ?? "-"
            let exp  = c.firstExpected.map { String(format: "0x%08x", $0) } ?? "-"
            let obs  = c.firstObserved.map { String(format: "0x%08x", $0) } ?? "-"
            let sz   = String(format: "%6d", c.encodedSize)
            let err  = (c.encodeError ?? c.decodeError ?? "").prefix(40)
            print("  \(bd) | \(dc) | \(dims) | \(mc) | [\(idx)] \(exp)→\(obs) | enc=\(sz) | \(err)")
        }

        // CSV dump
        var csv = "width,height,bit_depth,decomp,mismatch_count,first_mismatch_index,first_expected_hex,first_observed_hex,encoded_size,encode_error,decode_error,passed\n"
        for c in cells {
            csv += "\(c.width),\(c.height),\(c.bitDepth),\(c.decomp),\(c.mismatchCount),"
            csv += c.firstMismatchIndex.map(String.init) ?? ""
            csv += ","
            csv += c.firstExpected.map { String(format: "0x%08x", $0) } ?? ""
            csv += ","
            csv += c.firstObserved.map { String(format: "0x%08x", $0) } ?? ""
            csv += ",\(c.encodedSize),"
            csv += (c.encodeError ?? "").replacingOccurrences(of: ",", with: ";")
            csv += ","
            csv += (c.decodeError ?? "").replacingOccurrences(of: ",", with: ";")
            csv += ",\(c.passed)\n"
        }
        let outPath = "/tmp/J2K_HT_NonPowerOf2_PipelineMatrix.csv"
        try csv.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("\nCSV dump → \(outPath)")

        XCTAssertGreaterThan(cells.count, 0, "sweep produced no cells")
    }

    // MARK: helpers

    private func runPipeline(
        width: Int, height: Int, bitDepth: Int, decomp: Int
    ) async -> PipelineCell {
        // Build a deterministic synth image. Pattern: gradient + LCG
        // noise so neighboring pixels differ — exercises high-freq
        // subbands at the edges where partial-quad processing happens.
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
                // PGM/DICOM convention: big-endian for 16-bit.
                let hi = UInt8((sample >> 8) & 0xFF)
                let lo = UInt8(sample & 0xFF)
                bytes[i * 2]     = hi
                bytes[i * 2 + 1] = lo
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
            return PipelineCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count, firstMismatchIndex: 0,
                firstExpected: nil, firstObserved: nil,
                encodedSize: 0,
                encodeError: "\(error)",
                decodeError: nil)
        }
        let decoded: J2KImage
        do {
            decoded = try await J2KDecoder().decode(encoded)
        } catch {
            return PipelineCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count, firstMismatchIndex: 0,
                firstExpected: nil, firstObserved: nil,
                encodedSize: encoded.count,
                encodeError: nil,
                decodeError: "\(error)")
        }

        // Compare bytes — same byte-order, so direct compare is OK.
        let origBytes = [UInt8](image.components[0].data)
        let recBytes  = [UInt8](decoded.components[0].data)
        let cmpCount  = min(origBytes.count, recBytes.count)
        var mismatchCount = 0
        var firstIdx: Int? = nil
        var firstExp: UInt32? = nil
        var firstObs: UInt32? = nil
        for i in 0..<cmpCount where origBytes[i] != recBytes[i] {
            mismatchCount += 1
            if firstIdx == nil {
                firstIdx = i
                firstExp = UInt32(origBytes[i])
                firstObs = UInt32(recBytes[i])
            }
        }
        return PipelineCell(
            width: width, height: height, bitDepth: bitDepth, decomp: decomp,
            mismatchCount: mismatchCount,
            firstMismatchIndex: firstIdx,
            firstExpected: firstExp, firstObserved: firstObs,
            encodedSize: encoded.count,
            encodeError: nil,
            decodeError: nil)
    }

    private func isPowerOf2(_ n: Int) -> Bool {
        return n > 0 && (n & (n - 1)) == 0
    }

    private func percent(_ a: Int, _ b: Int) -> String {
        if b == 0 { return "0%" }
        return String(format: "%.1f%%", Double(a) * 100 / Double(b))
    }
}
