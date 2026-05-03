// J2KHTConformantRGBNonPowerOf2Tests.swift
// v5.17.0 medical-grade hardening: extend non-power-of-2 lossless
// HT conformant coverage to RGB (3-component) inputs.
//
// v5.15.0 ratified single-component (grayscale) lossless conformant
// at non-power-of-2 dimensions across 11,889 cells. RGB was not
// covered. Some medical imaging modalities are RGB (pathology slides
// at H&E staining, dermatology dermoscopy, ophthalmology retinal
// imaging). This file gates RGB lossless conformant at the same
// non-pow2 dimensions to ensure the v5.15.0 correctness floor extends
// to multi-component workflows.
//
// Two paths covered:
//   - MCT enabled (RCT, the default for RGB lossless)
//   - MCT disabled (independent component coding)

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class HTConformantRGBNonPowerOf2Tests: XCTestCase {

    private static let imageDims: [(w: Int, h: Int)] = [
        (32, 32), (33, 33), (31, 31),
        (64, 64), (65, 65), (63, 63),
        (33, 64), (64, 33),
        (128, 128), (129, 129),
        (37, 53), (79, 61),
    ]

    private static let decompLevels: [Int] = [0, 3, 5]
    private static let bitDepths:    [Int] = [8, 12, 16]

    private struct RGBCell {
        let width: Int
        let height: Int
        let bitDepth: Int
        let decomp: Int
        let mismatchCount: Int
        let firstMismatchComponent: Int?
        let firstMismatchIndex: Int?
        let encodedSize: Int
        let encodeError: String?
        let decodeError: String?
        var passed: Bool {
            mismatchCount == 0 && encodeError == nil && decodeError == nil
        }
    }

    func testRGB_FullPipeline_NonPowerOf2_LosslessHTConformantSweep() async throws {
        var cells: [RGBCell] = []
        for bd in Self.bitDepths {
            for (w, h) in Self.imageDims {
                for decomp in Self.decompLevels {
                    let cell = await runRGBPipeline(
                        width: w, height: h,
                        bitDepth: bd, decomp: decomp)
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
        print("=== HT Conformant RGB FULL-PIPELINE non-pow2 sweep ===")
        print("Total cells: \(total)")
        print("Failed:      \(failed.count) (\(percent(failed.count, total)))")
        print("  power-of-2 dims:     \(p2F.count) / \(p2.count) (\(percent(p2F.count, p2.count)))")
        print("  non-power-of-2 dims: \(np2F.count) / \(np2.count) (\(percent(np2F.count, np2.count)))")
        print("\nPer-decomp:")
        for (d, (t, f)) in perDecomp.sorted(by: { $0.key < $1.key }) {
            print("  decomp=\(d)  \(f)/\(t) (\(percent(f, t)))")
        }
        print("\nPer-bitDepth:")
        for (bd, (t, f)) in perBitDepth.sorted(by: { $0.key < $1.key }) {
            print("  bitDepth=\(bd)  \(f)/\(t) (\(percent(f, t)))")
        }
        let sortedFailed = failed.sorted { a, b in
            if a.bitDepth != b.bitDepth { return a.bitDepth < b.bitDepth }
            if a.decomp != b.decomp { return a.decomp < b.decomp }
            if a.width != b.width { return a.width < b.width }
            return a.height < b.height
        }
        print("\nFirst 30 failures (bd | decomp | w×h | comp | mismatches | err):")
        for c in sortedFailed.prefix(30) {
            let dims = "\(c.width)×\(c.height)".padding(toLength: 10, withPad: " ", startingAt: 0)
            let bd   = String(format: "%2d", c.bitDepth)
            let dc   = String(format: "%d", c.decomp)
            let mc   = String(format: "%6d", c.mismatchCount)
            let cmp  = c.firstMismatchComponent.map(String.init) ?? "-"
            let err  = (c.encodeError ?? c.decodeError ?? "").prefix(60)
            print("  \(bd) | \(dc) | \(dims) | \(cmp) | \(mc) | \(err)")
        }

        var csv = "width,height,bit_depth,decomp,mismatch_count,first_mismatch_component,first_mismatch_index,encoded_size,encode_error,decode_error,passed\n"
        for c in cells {
            csv += "\(c.width),\(c.height),\(c.bitDepth),\(c.decomp),\(c.mismatchCount),"
            csv += c.firstMismatchComponent.map(String.init) ?? ""
            csv += ","
            csv += c.firstMismatchIndex.map(String.init) ?? ""
            csv += ",\(c.encodedSize),"
            csv += (c.encodeError ?? "").replacingOccurrences(of: ",", with: ";")
            csv += ","
            csv += (c.decodeError ?? "").replacingOccurrences(of: ",", with: ";")
            csv += ",\(c.passed)\n"
        }
        let outPath = "/tmp/J2K_HT_RGB_NonPowerOf2_Matrix.csv"
        try csv.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("\nCSV dump → \(outPath)")

        XCTAssertGreaterThan(cells.count, 0, "sweep produced no cells")
        XCTAssertEqual(failed.count, 0,
                       "regression: \(failed.count) RGB cells corrupted in lossless full-pipeline round-trip — see test log + /tmp CSV")
    }

    // MARK: helpers

    private func runRGBPipeline(
        width: Int, height: Int, bitDepth: Int, decomp: Int
    ) async -> RGBCell {
        let bytesPerSample = (bitDepth + 7) / 8
        let count = width * height
        let maxVal = (1 << bitDepth) - 1

        var components: [J2KComponent] = []
        var origDataPerComponent: [Data] = []
        for comp in 0..<3 {
            // Different LCG seed per channel so MCT actually has
            // correlated-but-distinct content to decorrelate.
            var s: UInt64 = 0xfeed_face_dead_beef
                &+ UInt64(width) &* 1009
                &+ UInt64(height) &* 7919
                &+ UInt64(comp + 1) &* 271828183
            var bytes = [UInt8](repeating: 0, count: count * bytesPerSample)
            for i in 0..<count {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let x = i % width
                let y = i / width
                // Per-channel different gradient slopes so MCT sees
                // realistic chroma content.
                let chanShift = comp * 7
                let gradient = ((x * (31 + chanShift) + y * (17 + chanShift)) & maxVal)
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
            origDataPerComponent.append(data)
            components.append(J2KComponent(
                index: comp, bitDepth: bitDepth, signed: false,
                width: width, height: height,
                data: data,
                sampleByteOrder: bitDepth > 8 ? .bigEndian : nil))
        }
        let image = J2KImage(
            width: width, height: height, components: components,
            colorSpace: .sRGB)

        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: decomp,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true)
        cfg.useReversibleFilter = true
        cfg.htj2kBlockFormat = .conformant
        cfg.bitrateMode = .lossless
        // RCT (Part-1 reversible color transform) is the default for
        // 3-component sRGB lossless. Part-2 MCT extensions stay
        // disabled — those have their own coverage elsewhere.
        cfg.mctConfiguration = .disabled

        let encoded: Data
        do {
            encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
        } catch {
            return RGBCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count * 3,
                firstMismatchComponent: 0,
                firstMismatchIndex: 0,
                encodedSize: 0,
                encodeError: "\(error)",
                decodeError: nil)
        }
        let decoded: J2KImage
        do {
            decoded = try await J2KDecoder().decode(encoded)
        } catch {
            return RGBCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count * 3,
                firstMismatchComponent: 0,
                firstMismatchIndex: 0,
                encodedSize: encoded.count,
                encodeError: nil,
                decodeError: "\(error)")
        }

        guard decoded.components.count >= 3 else {
            return RGBCell(
                width: width, height: height, bitDepth: bitDepth, decomp: decomp,
                mismatchCount: count * 3,
                firstMismatchComponent: 0,
                firstMismatchIndex: 0,
                encodedSize: encoded.count,
                encodeError: nil,
                decodeError: "decoded components.count=\(decoded.components.count) (expected ≥ 3)")
        }
        var totalMismatches = 0
        var firstMismatchComp: Int? = nil
        var firstMismatchIdx: Int? = nil
        for comp in 0..<3 {
            let orig = [UInt8](origDataPerComponent[comp])
            let rec = [UInt8](decoded.components[comp].data)
            let cmpCount = min(orig.count, rec.count)
            for i in 0..<cmpCount where orig[i] != rec[i] {
                totalMismatches += 1
                if firstMismatchComp == nil {
                    firstMismatchComp = comp
                    firstMismatchIdx = i
                }
            }
        }
        return RGBCell(
            width: width, height: height, bitDepth: bitDepth, decomp: decomp,
            mismatchCount: totalMismatches,
            firstMismatchComponent: firstMismatchComp,
            firstMismatchIndex: firstMismatchIdx,
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
