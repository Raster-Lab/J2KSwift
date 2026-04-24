// J2KHTBlockBenchmarkPart15Tests.swift
// Throughput benchmarks for the ISO/IEC 15444-15 block coder.
//
// Measures encode / decode wall-clock time across representative
// block sizes and sample densities. Numbers are relative, intended
// for tracking regressions and quantifying the scalar-path overhead
// before SIMD optimizations land.
//
// Also includes an OpenJPH subprocess benchmark (ojph_compress +
// ojph_expand round-trip on a synthetic PGM) for an order-of-
// magnitude sanity check — not apples-to-apples because OpenJPH's
// timing includes file I/O and full codestream marker processing.

import XCTest
import Foundation
@testable import J2KCodec

final class HTBlockBenchmarkPart15Tests: XCTestCase {

    // MARK: - Helpers

    private static func binCenter(mu: UInt32, sign: Bool, p: UInt32)
        -> UInt32
    {
        let mag = (2 * mu + 1) << (p - 1)
        return sign ? (mag | 0x8000_0000) : mag
    }

    /// Build a deterministic coefficient array with `density` fraction
    /// of bin-centered samples placed in a fixed scan order.
    private static func makeCoefficients(
        width: Int, height: Int, density: Double, seed: UInt64
    ) -> [UInt32] {
        let p: UInt32 = 30
        var coefs = [UInt32](repeating: 0, count: width * height)
        var state = seed | 1
        for i in 0..<coefs.count {
            // LCG: deterministic, fast, plenty random for this use.
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            let pct = Double(state >> 32) / Double(UInt32.max)
            if pct < density {
                let sign = (state & 1) == 1
                coefs[i] = binCenter(mu: 1, sign: sign, p: p)
            }
        }
        return coefs
    }

    private func timeIt(iterations: Int, _ body: () -> Void)
        -> (mean: Double, min: Double, max: Double)
    {
        var samples = [Double]()
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let t0 = CFAbsoluteTimeGetCurrent()
            body()
            samples.append(CFAbsoluteTimeGetCurrent() - t0)
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        let mn = samples.min() ?? 0
        let mx = samples.max() ?? 0
        return (mean, mn, mx)
    }

    private func report(
        _ label: String,
        _ samples: Int,
        _ stats: (mean: Double, min: Double, max: Double),
        bytes: Int? = nil
    ) {
        let throughput = Double(samples) / stats.min / 1_000_000
        var line = String(format: "%@ — %.3f ms min, %.3f ms mean (%.1f Msamples/s peak)",
            label, stats.min * 1000, stats.mean * 1000, throughput)
        if let b = bytes {
            line += String(format: ", %d bytes (%.2f bpp)",
                b, Double(b * 8) / Double(samples))
        }
        print(line)
    }

    // MARK: - Encoder throughput

    /// Encode a 32x32 block at 50% density. Scalar path baseline.
    func test32x32Encode50PctDensity() throws {
        let width = 32, height = 32
        let coefs = Self.makeCoefficients(
            width: width, height: height, density: 0.5, seed: 0x1234)
        let iters = 500

        let stats = timeIt(iterations: iters) {
            _ = HTBlockEncoderPart15.encode(
                coefficients: coefs, width: width, height: height,
                missingMSBs: 0)
        }
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: 0)
        report("encode 32x32 @ 50%",
               width * height, stats,
               bytes: ms.count + mel.count + vlc.count)
    }

    /// Encode a 64x64 block at 25% density — realistic medical
    /// wavelet subband distribution.
    func test64x64Encode25PctDensity() throws {
        let width = 64, height = 64
        let coefs = Self.makeCoefficients(
            width: width, height: height, density: 0.25, seed: 0x5678)
        let iters = 200

        let stats = timeIt(iterations: iters) {
            _ = HTBlockEncoderPart15.encode(
                coefficients: coefs, width: width, height: height,
                missingMSBs: 0)
        }
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: 0)
        report("encode 64x64 @ 25%",
               width * height, stats,
               bytes: ms.count + mel.count + vlc.count)
    }

    /// All-zero 32x32 block — best case (MagSgn empty).
    func test32x32EncodeAllZeros() throws {
        let width = 32, height = 32
        let coefs = [UInt32](repeating: 0, count: width * height)
        let iters = 2000

        let stats = timeIt(iterations: iters) {
            _ = HTBlockEncoderPart15.encode(
                coefficients: coefs, width: width, height: height,
                missingMSBs: 0)
        }
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: 0)
        report("encode 32x32 all-zeros",
               width * height, stats,
               bytes: ms.count + mel.count + vlc.count)
    }

    // MARK: - Decoder throughput

    /// Decode a 32x32 @ 50% block. Exercises the reference decoder's
    /// linear source-table scan (O(n) per codeword).
    func test32x32Decode50PctDensity() throws {
        let width = 32, height = 32
        let coefs = Self.makeCoefficients(
            width: width, height: height, density: 0.5, seed: 0x1234)
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: 0)
        let block = try HTBlockLayoutPart15.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let iters = 100  // Reference decoder is slow.

        let stats = timeIt(iterations: iters) {
            _ = try? HTBlockDecoderPart15.decode(
                block: block, width: width, height: height,
                missingMSBs: 0)
        }
        report("decode 32x32 @ 50%", width * height, stats)
    }

    func test64x64Decode25PctDensity() throws {
        let width = 64, height = 64
        let coefs = Self.makeCoefficients(
            width: width, height: height, density: 0.25, seed: 0x5678)
        let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
            coefficients: coefs, width: width, height: height,
            missingMSBs: 0)
        let block = try HTBlockLayoutPart15.assemble(
            magsgn: ms, mel: mel, vlc: vlc)
        let iters = 50

        let stats = timeIt(iterations: iters) {
            _ = try? HTBlockDecoderPart15.decode(
                block: block, width: width, height: height,
                missingMSBs: 0)
        }
        report("decode 64x64 @ 25%", width * height, stats)
    }

    // MARK: - Encode + decode round-trip

    /// End-to-end scalar block coder throughput.
    func test32x32RoundTrip() throws {
        let width = 32, height = 32
        let coefs = Self.makeCoefficients(
            width: width, height: height, density: 0.3, seed: 0xABCD)
        let iters = 100

        let stats = timeIt(iterations: iters) {
            let (ms, mel, vlc) = HTBlockEncoderPart15.encode(
                coefficients: coefs, width: width, height: height,
                missingMSBs: 0)
            if let block = try? HTBlockLayoutPart15.assemble(
                magsgn: ms, mel: mel, vlc: vlc) {
                _ = try? HTBlockDecoderPart15.decode(
                    block: block, width: width, height: height,
                    missingMSBs: 0)
            }
        }
        report("round-trip 32x32 @ 30%", width * height, stats)
    }

    // MARK: - OpenJPH reference benchmark

    /// End-to-end OpenJPH round-trip on a 256x256 PGM — gives a
    /// ballpark number for "native C++ HTJ2K" on this machine.
    /// Includes subprocess fork + file I/O, so it's not a direct
    /// throughput comparison with the scalar Swift path above.
    func testOpenJPHEndToEnd256x256() throws {
        let ojphCompress = "/opt/homebrew/bin/ojph_compress"
        let ojphExpand   = "/opt/homebrew/bin/ojph_expand"
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: ojphCompress),
              fm.isExecutableFile(atPath: ojphExpand) else {
            throw XCTSkip("OpenJPH CLI not found")
        }
        let tmp = fm.temporaryDirectory
        let pgmIn  = tmp.appendingPathComponent("bench_in.pgm")
        let j2c    = tmp.appendingPathComponent("bench.j2c")
        let pgmOut = tmp.appendingPathComponent("bench_out.pgm")
        defer {
            try? fm.removeItem(at: pgmIn)
            try? fm.removeItem(at: j2c)
            try? fm.removeItem(at: pgmOut)
        }

        // 256x256 deterministic-noise PGM.
        var bytes: [UInt8] = Array("P5\n256 256\n255\n".utf8)
        var state: UInt64 = 0x1BADB002
        for _ in 0..<(256 * 256) {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            bytes.append(UInt8(state >> 56))
        }
        try Data(bytes).write(to: pgmIn)

        func run(_ exe: String, _ args: [String]) throws -> Double {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            let t0 = CFAbsoluteTimeGetCurrent()
            try proc.run()
            proc.waitUntilExit()
            return CFAbsoluteTimeGetCurrent() - t0
        }

        let iters = 5
        var compressTimes: [Double] = []
        var expandTimes: [Double] = []
        for _ in 0..<iters {
            let tC = try run(ojphCompress, [
                "-i", pgmIn.path, "-o", j2c.path,
                "-num_decomps", "5", "-block_size", "{32,32}",
                "-reversible", "true"
            ])
            compressTimes.append(tC)
            let tE = try run(ojphExpand, [
                "-i", j2c.path, "-o", pgmOut.path
            ])
            expandTimes.append(tE)
        }

        let samples = 256 * 256
        let compressMin = compressTimes.min() ?? 0
        let expandMin = expandTimes.min() ?? 0
        print(String(format:
            "OpenJPH compress 256x256 — %.3f ms min (%.2f Msamples/s)",
            compressMin * 1000,
            Double(samples) / compressMin / 1_000_000))
        print(String(format:
            "OpenJPH expand 256x256 — %.3f ms min (%.2f Msamples/s)",
            expandMin * 1000,
            Double(samples) / expandMin / 1_000_000))
    }
}
