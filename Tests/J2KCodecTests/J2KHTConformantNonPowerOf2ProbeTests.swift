// J2KHTConformantNonPowerOf2ProbeTests.swift
// Phase 1 of the v5.15.0 HT encoder hardening plan.
//
// The conformant encoder default was silently flipped to .conformant
// in the public API (J2KEncodingPresets.swift:435), but the docstring
// at J2KEncodingPresets.swift:341-347 acknowledges that "non-power-of-2
// subband dimensions are known to be lossy in the conformant encoder
// path." Existing block-level tests only cover power-of-2 dims up to
// 8×4 (J2KHTConformantBlockRoundTripTests), so the bug has no direct
// coverage today.
//
// METHODOLOGY: encoder takes pre-quantized sign-magnitude coefficients
// in OpenJPH convention. For a meaningful lossless round-trip test the
// input MUST be bin-aligned, i.e., `(2μ_p + 1) << (p − 1)` for some
// integer μ_p ≥ 1. Sub-bin-center inputs are quantized to zero by
// design and are not corruption.
//
// This file is the corruption probe: encode → assemble → decode round
// trip across a wide dimension grid (including non-power-of-2 widths
// AND heights) with multiple bin-aligned coefficient patterns. It
// reports which (width × height × pattern × missingMSBs) cells fail
// and dumps the matrix to /tmp for the Phase 1 report. The probe is
// intentionally non-failing — the matrix is the deliverable; Phase 2
// fixes the bug; Phase 3 lifts the matrix into a regression gate.

import XCTest
import Foundation
@testable import J2KCodec

final class HTConformantNonPowerOf2ProbeTests: XCTestCase {

    // Block dimensions — power-of-2 alongside odd / partial-quad
    // dimensions. Quads are 2×2 so any dim that is not a multiple of 2
    // forces partial-quad rows/columns; non-multiples-of-4 widths
    // additionally force partial quad-pairs.
    private static let widths:  [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 16, 17, 23, 32, 33, 64]
    private static let heights: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 16, 17, 23, 32, 33, 64]

    // missingMSBs values to sweep — controls `p = 30 − missingMSBs`,
    // i.e., the bit position of the most-significant bin boundary.
    // Larger missingMSBs (smaller p) leaves room for multiple distinct
    // bin-aligned magnitudes (μ_p = 1, 2, 3...) within 32 bits.
    private static let missingMSBsValues: [Int] = [0, 5, 10, 20, 25]

    private static let patternNames: [String] = [
        "all-zero",
        "single-pos-corner-mu1",
        "single-neg-far-corner-mu1",
        "right-edge-column-mu1",
        "bottom-edge-row-mu1",
        "checkerboard-mu1",
        "dense-uniform-mu1",
        "dense-uniform-mu3",
        "rand-bin-aligned",
    ]

    /// Bin-center value at quantization level `mu` (≥ 1) for parameter
    /// `p`. Returns OpenJPH-convention sign-magnitude: bit 31 sign,
    /// magnitude in bits below `p`.
    private func binCenter(mu: Int, p: Int, negative: Bool) -> UInt32 {
        precondition(mu >= 1, "mu_p must be ≥ 1")
        precondition(p >= 1 && p <= 30, "p out of range: \(p)")
        let mag = UInt32((2 * mu + 1) << (p - 1))
        return negative ? (mag | 0x8000_0000) : mag
    }

    private func buildPattern(_ name: String, width w: Int, height h: Int, p: Int) -> [UInt32] {
        let mu1Pos = binCenter(mu: 1, p: p, negative: false)
        let mu1Neg = binCenter(mu: 1, p: p, negative: true)
        let mu3Pos = binCenter(mu: 3, p: p, negative: false)
        let mu3Neg = binCenter(mu: 3, p: p, negative: true)

        switch name {
        case "all-zero":
            return [UInt32](repeating: 0, count: w * h)
        case "single-pos-corner-mu1":
            var c = [UInt32](repeating: 0, count: w * h)
            c[0] = mu1Pos
            return c
        case "single-neg-far-corner-mu1":
            var c = [UInt32](repeating: 0, count: w * h)
            c[w * h - 1] = mu1Neg
            return c
        case "right-edge-column-mu1":
            var c = [UInt32](repeating: 0, count: w * h)
            for y in 0..<h { c[y * w + (w - 1)] = mu1Pos }
            return c
        case "bottom-edge-row-mu1":
            var c = [UInt32](repeating: 0, count: w * h)
            for x in 0..<w { c[(h - 1) * w + x] = mu1Pos }
            return c
        case "checkerboard-mu1":
            var c = [UInt32](repeating: 0, count: w * h)
            for y in 0..<h {
                for x in 0..<w where (x + y) % 2 == 0 {
                    c[y * w + x] = (x % 4 == 0) ? mu1Pos : mu1Neg
                }
            }
            return c
        case "dense-uniform-mu1":
            return [UInt32](repeating: mu1Pos, count: w * h)
        case "dense-uniform-mu3":
            // mu=3 is only representable for p ≤ 28 — skip otherwise.
            guard p <= 28 else { return [UInt32](repeating: 0, count: w * h) }
            return [UInt32](repeating: mu3Pos, count: w * h)
        case "rand-bin-aligned":
            // Pick a random bin (zero or one of the supported μ values)
            // per pixel. Deterministic LCG so the matrix is reproducible.
            var s: UInt64 = 0xc001_d00d_dead_beef
            var c = [UInt32](repeating: 0, count: w * h)
            let canMu3 = p <= 28
            for i in 0..<(w * h) {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                let bucket = (s >> 28) & 0x7
                let neg = ((s >> 30) & 1) == 1
                switch bucket {
                case 0, 1, 2, 3:    c[i] = 0
                case 4, 5:           c[i] = neg ? mu1Neg : mu1Pos
                default:             c[i] = canMu3 ? (neg ? mu3Neg : mu3Pos)
                                                   : (neg ? mu1Neg : mu1Pos)
                }
            }
            return c
        default:
            preconditionFailure("unknown pattern \(name)")
        }
    }

    private struct CorruptionCell {
        let width: Int
        let height: Int
        let pattern: String
        let missingMSBs: Int
        let mismatchCount: Int
        let firstMismatchIndex: Int?
        let firstExpected: UInt32?
        let firstObserved: UInt32?
        var passed: Bool { mismatchCount == 0 }
    }

    func testBlockLevel_NonPowerOf2_CorruptionSweep() throws {
        var cells: [CorruptionCell] = []
        for missingMSBs in Self.missingMSBsValues {
            let p = 30 - missingMSBs
            for h in Self.heights {
                for w in Self.widths {
                    for name in Self.patternNames {
                        let coefs = buildPattern(name, width: w, height: h, p: p)
                        let cell = roundTrip(
                            coefs: coefs, width: w, height: h,
                            pattern: name, missingMSBs: missingMSBs)
                        cells.append(cell)
                    }
                }
            }
        }

        let total = cells.count
        let failed = cells.filter { !$0.passed }
        let p2  = cells.filter { isPowerOf2($0.width) && isPowerOf2($0.height) }
        let np2 = cells.filter { !isPowerOf2($0.width) || !isPowerOf2($0.height) }
        let p2F  = p2.filter  { !$0.passed }
        let np2F = np2.filter { !$0.passed }

        let perPattern = Dictionary(grouping: cells, by: { $0.pattern })
            .mapValues { rows in (rows.count, rows.filter { !$0.passed }.count) }
        let perMMSBs = Dictionary(grouping: cells, by: { $0.missingMSBs })
            .mapValues { rows in (rows.count, rows.filter { !$0.passed }.count) }

        // Identify the failing-dim profile per pattern (which widths
        // and heights induce failures, regardless of missingMSBs).
        var failingWidths = Set<Int>()
        var failingHeights = Set<Int>()
        for c in failed {
            failingWidths.insert(c.width)
            failingHeights.insert(c.height)
        }

        print("=== HT Conformant non-power-of-2 corruption sweep ===")
        print("Total cells: \(total)")
        print("Failed:      \(failed.count) (\(percent(failed.count, total)))")
        print("  power-of-2 dims:     \(p2F.count) / \(p2.count) (\(percent(p2F.count, p2.count)))")
        print("  non-power-of-2 dims: \(np2F.count) / \(np2.count) (\(percent(np2F.count, np2.count)))")
        print("\nPer-pattern failure rate:")
        for (name, (t, f)) in perPattern.sorted(by: { $0.key < $1.key }) {
            print("  \(name.padding(toLength: 36, withPad: " ", startingAt: 0)) \(f)/\(t) (\(percent(f, t)))")
        }
        print("\nPer-missingMSBs failure rate:")
        for (m, (t, f)) in perMMSBs.sorted(by: { $0.key < $1.key }) {
            print("  missingMSBs=\(String(format: "%2d", m))  \(f)/\(t) (\(percent(f, t)))")
        }
        print("\nFailing widths:  \(failingWidths.sorted())")
        print("Failing heights: \(failingHeights.sorted())")

        // First 40 failures (sorted: smallest dims first) to make
        // root-cause hunting easier in Phase 2.
        let sortedFailed = failed.sorted { a, b in
            if a.width != b.width { return a.width < b.width }
            if a.height != b.height { return a.height < b.height }
            if a.missingMSBs != b.missingMSBs { return a.missingMSBs < b.missingMSBs }
            return a.pattern < b.pattern
        }
        print("\nFirst 40 failures (w×h | mMSBs | pattern | mismatches | [idx] expected → observed):")
        for c in sortedFailed.prefix(40) {
            let dims = "\(c.width)×\(c.height)".padding(toLength: 8, withPad: " ", startingAt: 0)
            let mm   = String(format: "%2d", c.missingMSBs)
            let pat  = c.pattern.padding(toLength: 28, withPad: " ", startingAt: 0)
            let idx  = c.firstMismatchIndex.map(String.init) ?? "-"
            let exp  = c.firstExpected.map { String(format: "0x%08x", $0) } ?? "-"
            let obs  = c.firstObserved.map { String(format: "0x%08x", $0) } ?? "-"
            print("  \(dims) | \(mm) | \(pat) | \(c.mismatchCount) | [\(idx)] \(exp) → \(obs)")
        }

        // CSV dump for the Phase 1 corruption-matrix report.
        var csv = "width,height,missing_msbs,pattern,mismatch_count,first_mismatch_index,first_expected_hex,first_observed_hex,passed\n"
        for c in cells {
            csv += "\(c.width),\(c.height),\(c.missingMSBs),\(c.pattern),\(c.mismatchCount),"
            csv += c.firstMismatchIndex.map(String.init) ?? ""
            csv += ","
            csv += c.firstExpected.map { String(format: "0x%08x", $0) } ?? ""
            csv += ","
            csv += c.firstObserved.map { String(format: "0x%08x", $0) } ?? ""
            csv += ",\(c.passed)\n"
        }
        let outPath = "/tmp/J2K_HT_NonPowerOf2_BlockMatrix.csv"
        try csv.write(toFile: outPath, atomically: true, encoding: .utf8)
        print("\nCSV dump → \(outPath)")

        // Phase 1 deliverable is the matrix, not pass/fail. Just
        // assert the sweep ran so a crash surfaces as a test failure.
        XCTAssertGreaterThan(cells.count, 0, "sweep produced no cells")
    }

    // MARK: helpers

    private func roundTrip(
        coefs: [UInt32], width: Int, height: Int,
        pattern: String, missingMSBs: Int
    ) -> CorruptionCell {
        let (ms, mel, vlc) = HTBlockEncoderConformant.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: missingMSBs)
        let block: [UInt8]
        do {
            block = try HTBlockLayoutConformant.assemble(magsgn: ms, mel: mel, vlc: vlc)
        } catch {
            return CorruptionCell(
                width: width, height: height, pattern: pattern,
                missingMSBs: missingMSBs,
                mismatchCount: width * height,
                firstMismatchIndex: 0,
                firstExpected: coefs.first ?? 0, firstObserved: nil)
        }
        let decoded: [UInt32]
        do {
            decoded = try HTBlockDecoderConformant.decode(
                block: block, width: width, height: height,
                missingMSBs: missingMSBs)
        } catch {
            return CorruptionCell(
                width: width, height: height, pattern: pattern,
                missingMSBs: missingMSBs,
                mismatchCount: width * height,
                firstMismatchIndex: 0,
                firstExpected: coefs.first ?? 0, firstObserved: nil)
        }
        var mismatchCount = 0
        var firstIdx: Int? = nil
        var firstExp: UInt32? = nil
        var firstObs: UInt32? = nil
        for i in 0..<coefs.count where decoded[i] != coefs[i] {
            mismatchCount += 1
            if firstIdx == nil {
                firstIdx = i; firstExp = coefs[i]; firstObs = decoded[i]
            }
        }
        return CorruptionCell(
            width: width, height: height, pattern: pattern,
            missingMSBs: missingMSBs,
            mismatchCount: mismatchCount,
            firstMismatchIndex: firstIdx,
            firstExpected: firstExp, firstObserved: firstObs)
    }

    private func isPowerOf2(_ n: Int) -> Bool {
        return n > 0 && (n & (n - 1)) == 0
    }

    private func percent(_ a: Int, _ b: Int) -> String {
        if b == 0 { return "0%" }
        return String(format: "%.1f%%", Double(a) * 100 / Double(b))
    }
}
