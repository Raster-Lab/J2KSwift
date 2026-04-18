// Tests/J2KCodecTests/J2KMedicalBenchmarkTests.swift
//
// Comprehensive medical imaging benchmark: J2KSwift vs OpenJPEG 2.5.4
// Tests realistic medical imaging phantoms at multiple bit depths and compression modes.
// Measures in-process encoding/decoding for J2KSwift (no CLI overhead).
// Run with: swift test -c release --filter J2KMedicalBenchmarkTests

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KMedicalBenchmarkTests: XCTestCase {

    // MARK: - Configuration

    static let benchmarkRuns = 5
    static let warmupRuns = 2
    static let resultDir = "/tmp/j2k_medical_benchmark/results"
    nonisolated(unsafe) static var allResults: [BenchmarkResult] = []

    private let opjCompress   = "/opt/homebrew/bin/opj_compress"
    private let opjDecompress = "/opt/homebrew/bin/opj_decompress"

    struct BenchmarkResult {
        let imageName: String
        let modality: String
        let width: Int
        let height: Int
        let bitDepth: Int
        let mode: String
        let rateLabel: String

        let j2kEncTimeMs: Double
        let j2kDecTimeMs: Double
        let j2kSizeBytes: Int
        let j2kPSNR: Double
        let j2kMAE: Double

        let opjEncTimeMs: Double
        let opjDecTimeMs: Double
        let opjSizeBytes: Int

        var encSpeedup: Double { opjEncTimeMs > 0 ? opjEncTimeMs / max(j2kEncTimeMs, 0.001) : 0 }
        var decSpeedup: Double { opjDecTimeMs > 0 ? opjDecTimeMs / max(j2kDecTimeMs, 0.001) : 0 }
        var j2kRatio: Double { Double(width * height * (bitDepth > 8 ? 2 : 1)) / Double(max(j2kSizeBytes, 1)) }
        var opjRatio: Double { Double(width * height * (bitDepth > 8 ? 2 : 1)) / Double(max(opjSizeBytes, 1)) }
    }

    // MARK: - Image Generation Helpers

    private func generateCTPhantom(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        let pixelCount = width * height
        let bytesPerPixel = bitDepth > 8 ? 2 : 1
        var data = Data(count: pixelCount * bytesPerPixel)

        let cx = Double(width) / 2.0
        let cy = Double(height) / 2.0

        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x), dy = Double(y)
                    var val = 0.0

                    // Body outline
                    if pow(dx - cx, 2) / pow(cx * 0.85, 2) + pow(dy - cy, 2) / pow(cy * 0.90, 2) < 1.0 {
                        val = 0.35 * Double(maxVal)
                    }
                    // Left lung
                    if pow(dx - cx * 0.65, 2) / pow(cx * 0.25, 2) + pow(dy - cy, 2) / pow(cy * 0.6, 2) < 1.0 {
                        val = 0.1 * Double(maxVal)
                    }
                    // Right lung
                    if pow(dx - cx * 1.35, 2) / pow(cx * 0.25, 2) + pow(dy - cy, 2) / pow(cy * 0.6, 2) < 1.0 {
                        val = 0.1 * Double(maxVal)
                    }
                    // Heart
                    if pow(dx - cx * 0.95, 2) / pow(cx * 0.15, 2) + pow(dy - cy * 1.05, 2) / pow(cy * 0.2, 2) < 1.0 {
                        val = 0.45 * Double(maxVal)
                    }
                    // Spine
                    if pow(dx - cx, 2) / pow(cx * 0.06, 2) + pow(dy - cy * 1.2, 2) / pow(cy * 0.15, 2) < 1.0 {
                        val = 0.85 * Double(maxVal)
                    }
                    // Ribs
                    for angle in stride(from: -0.8, through: 0.8, by: 0.145) {
                        let ribCx = cx + cx * 0.55 * sin(angle)
                        let ribCy = cy + cy * 0.7 * cos(angle)
                        if pow(dx - ribCx, 2) / pow(cx * 0.03, 2) + pow(dy - ribCy, 2) / pow(cy * 0.02, 2) < 1.0 {
                            val = 0.75 * Double(maxVal)
                        }
                    }

                    let noise = sin(Double(x * 7 + y * 13)) * 0.02 * Double(maxVal)
                    val = min(max(val + noise, 0), Double(maxVal))

                    let i = y * width + x
                    if bitDepth <= 8 {
                        ptr[i] = UInt8(Int(val) & 0xFF)
                    } else {
                        let v = UInt16(min(Int(val), maxVal))
                        ptr[i * 2]     = UInt8(v >> 8)
                        ptr[i * 2 + 1] = UInt8(v & 0xFF)
                    }
                }
            }
        }

        let comp = J2KComponent(index: 0, bitDepth: bitDepth, signed: false,
                                width: width, height: height, data: data)
        return J2KImage(width: width, height: height, components: [comp])
    }

    private func generateMRIBrain(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        let pixelCount = width * height
        let bytesPerPixel = bitDepth > 8 ? 2 : 1
        var data = Data(count: pixelCount * bytesPerPixel)

        let cx = Double(width) / 2.0
        let cy = Double(height) / 2.0

        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x), dy = Double(y)
                    var val = 0.0

                    // Skull
                    let skullO = pow(dx - cx, 2) / pow(cx * 0.85, 2) + pow(dy - cy, 2) / pow(cy * 0.9, 2)
                    let skullI = pow(dx - cx, 2) / pow(cx * 0.78, 2) + pow(dy - cy, 2) / pow(cy * 0.83, 2)
                    if skullO < 1.0 && skullI >= 1.0 { val = 0.2 * Double(maxVal) }

                    // Gray matter
                    if pow(dx - cx, 2) / pow(cx * 0.75, 2) + pow(dy - cy, 2) / pow(cy * 0.80, 2) < 1.0 {
                        val = 0.55 * Double(maxVal)
                    }
                    // White matter
                    if pow(dx - cx, 2) / pow(cx * 0.55, 2) + pow(dy - cy, 2) / pow(cy * 0.6, 2) < 1.0 {
                        val = 0.75 * Double(maxVal)
                    }
                    // Ventricles
                    if pow(dx - cx * 0.88, 2) / pow(cx * 0.08, 2) + pow(dy - cy * 0.85, 2) / pow(cy * 0.2, 2) < 1.0 {
                        val = 0.15 * Double(maxVal)
                    }
                    if pow(dx - cx * 1.12, 2) / pow(cx * 0.08, 2) + pow(dy - cy * 0.85, 2) / pow(cy * 0.2, 2) < 1.0 {
                        val = 0.15 * Double(maxVal)
                    }

                    let noise = sin(Double(x * 11 + y * 17)) * 0.025 * Double(maxVal)
                    val = min(max(val + noise, 0), Double(maxVal))

                    let i = y * width + x
                    if bitDepth <= 8 {
                        ptr[i] = UInt8(Int(val) & 0xFF)
                    } else {
                        let v = UInt16(min(Int(val), maxVal))
                        ptr[i * 2]     = UInt8(v >> 8)
                        ptr[i * 2 + 1] = UInt8(v & 0xFF)
                    }
                }
            }
        }

        let comp = J2KComponent(index: 0, bitDepth: bitDepth, signed: false,
                                width: width, height: height, data: data)
        return J2KImage(width: width, height: height, components: [comp])
    }

    private func generateUltrasound(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        let pixelCount = width * height
        let bytesPerPixel = bitDepth > 8 ? 2 : 1
        var data = Data(count: pixelCount * bytesPerPixel)

        let cx = Double(width) / 2.0

        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x), dy = Double(y)
                    var val = 0.0

                    let dist = sqrt(pow(dx - cx, 2) + pow(dy, 2))
                    let angle = atan2(dx - cx, dy + 1)
                    let inFan = dist < Double(height) * 0.95 && abs(angle) < Double.pi / 3

                    if inFan {
                        let depthAtten = exp(-dy / (Double(height) * 0.8))
                        val = 0.3 * Double(maxVal) * depthAtten
                        let speckle = 0.5 + 0.5 * sin(Double(x * 23 + y * 37) * 0.1)
                        val *= (0.5 + speckle)
                    }

                    val = min(max(val, 0), Double(maxVal))

                    let i = y * width + x
                    if bitDepth <= 8 {
                        ptr[i] = UInt8(Int(val) & 0xFF)
                    } else {
                        let v = UInt16(min(Int(val), maxVal))
                        ptr[i * 2]     = UInt8(v >> 8)
                        ptr[i * 2 + 1] = UInt8(v & 0xFF)
                    }
                }
            }
        }

        let comp = J2KComponent(index: 0, bitDepth: bitDepth, signed: false,
                                width: width, height: height, data: data)
        return J2KImage(width: width, height: height, components: [comp])
    }

    private func generateMammogram(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        let pixelCount = width * height
        let bytesPerPixel = bitDepth > 8 ? 2 : 1
        var data = Data(count: pixelCount * bytesPerPixel)

        let cx = Double(width) * 0.35
        let cy = Double(height) / 2.0

        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x), dy = Double(y)
                    var val = 0.0

                    let breastD = pow(dx - cx, 2) / pow(cx * 0.8, 2) + pow(dy - cy, 2) / pow(cy * 0.85, 2)
                    let inBreast = breastD < 1.0 && dx > Double(width) * 0.05

                    if inBreast {
                        val = 0.4 * Double(maxVal)
                        val += sin(dx * 0.05) * cos(dy * 0.07) * 0.15 * Double(maxVal)
                    }

                    let noise = sin(Double(x * 31 + y * 43)) * 0.02 * Double(maxVal)
                    val = min(max(val + noise, 0), Double(maxVal))
                    if !inBreast { val = 0 }

                    let i = y * width + x
                    if bitDepth <= 8 {
                        ptr[i] = UInt8(Int(val) & 0xFF)
                    } else {
                        let v = UInt16(min(Int(val), maxVal))
                        ptr[i * 2]     = UInt8(v >> 8)
                        ptr[i * 2 + 1] = UInt8(v & 0xFF)
                    }
                }
            }
        }

        let comp = J2KComponent(index: 0, bitDepth: bitDepth, signed: false,
                                width: width, height: height, data: data)
        return J2KImage(width: width, height: height, components: [comp])
    }

    // MARK: - PGM I/O for OpenJPEG interop

    private func writePGM(_ image: J2KImage, to path: String) throws {
        let comp = image.components[0]
        let maxval = (1 << comp.bitDepth) - 1
        var pgmData = Data()
        let header = "P5\n\(image.width) \(image.height)\n\(maxval)\n"
        pgmData.append(contentsOf: header.utf8)
        pgmData.append(comp.data)
        try pgmData.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - OpenJPEG Runner

    @discardableResult
    private func runOPJ(compress: Bool, input: String, output: String,
                        rate: String? = nil) -> (success: Bool, timeMs: Double) {
        let tool = compress ? opjCompress : opjDecompress
        guard FileManager.default.fileExists(atPath: tool) else { return (false, 0) }

        var args = ["-i", input, "-o", output]
        if compress, let r = rate { args += ["-r", r] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let start = CFAbsoluteTimeGetCurrent()
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return (false, 0) }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        return (process.terminationStatus == 0, elapsed)
    }

    // MARK: - Quality Metrics

    private func computeMetrics(original: J2KImage, decoded: J2KImage) -> (psnr: Double, mae: Double) {
        guard !original.components.isEmpty, !decoded.components.isEmpty else { return (0, .infinity) }

        let origComp = original.components[0]
        let decComp  = decoded.components[0]
        let maxval   = Double((1 << origComp.bitDepth) - 1)
        let n        = origComp.width * origComp.height
        let is16     = origComp.bitDepth > 8

        guard origComp.data.count > 0, decComp.data.count > 0 else { return (0, .infinity) }

        var mse = 0.0
        var sumAE = 0.0

        origComp.data.withUnsafeBytes { origBuf in
            decComp.data.withUnsafeBytes { decBuf in
                let op = origBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let dp = decBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)

                let count = min(n, origComp.data.count / (is16 ? 2 : 1),
                                   decComp.data.count / (is16 ? 2 : 1))
                for i in 0..<count {
                    let ov: Double, dv: Double
                    if is16 {
                        ov = Double(UInt16(op[i * 2]) << 8 | UInt16(op[i * 2 + 1]))
                        dv = Double(UInt16(dp[i * 2]) << 8 | UInt16(dp[i * 2 + 1]))
                    } else {
                        ov = Double(op[i])
                        dv = Double(dp[i])
                    }
                    let diff = ov - dv
                    mse += diff * diff
                    sumAE += abs(diff)
                }
            }
        }

        mse /= Double(n)
        let mae = sumAE / Double(n)
        if mse == 0 { return (.infinity, 0) }
        return (10.0 * log10(maxval * maxval / mse), mae)
    }

    // MARK: - Core Benchmark Runner

    private func runBenchmark(
        image: J2KImage,
        imageName: String,
        modality: String,
        mode: String,
        rateLabel: String,
        quality: Double? = nil,
        bitrate: Double? = nil,
        opjRate: String? = nil
    ) async -> BenchmarkResult {
        let runs   = Self.benchmarkRuns
        let warmup = Self.warmupRuns
        let bd     = image.components[0].bitDepth

        // --- J2KSwift Encode ---
        var config = J2KEncodingConfiguration()
        if mode == "lossless" {
            config.lossless = true
            config.useReversibleFilter = true
        } else {
            config.lossless = false
            config.useReversibleFilter = false
            if let q = quality { config.quality = q }
            if let br = bitrate { config.bitrateMode = .constantBitrate(bitsPerPixel: br) }
        }

        let encoder = J2KEncoder(encodingConfiguration: config)

        // Warmup
        for _ in 0..<warmup { _ = try? await encoder.encode(image) }

        var j2kEncodeTimes: [Double] = []
        var encodedData: Data?
        for _ in 0..<runs {
            let start = CFAbsoluteTimeGetCurrent()
            let data = try? await encoder.encode(image)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
            j2kEncodeTimes.append(elapsed)
            if encodedData == nil { encodedData = data }
        }
        let j2kEncMedian = Self.median(j2kEncodeTimes)
        let j2kSize = encodedData?.count ?? 0

        // --- J2KSwift Decode ---
        let decoder = J2KDecoder()
        var j2kDecodeTimes: [Double] = []
        var decodedImage: J2KImage?

        if let data = encodedData {
            for _ in 0..<warmup { _ = try? await decoder.decode(data) }
            for _ in 0..<runs {
                let start = CFAbsoluteTimeGetCurrent()
                let dec = try? await decoder.decode(data)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                j2kDecodeTimes.append(elapsed)
                if decodedImage == nil { decodedImage = dec }
            }
        }
        let j2kDecMedian = j2kDecodeTimes.isEmpty ? 0 : Self.median(j2kDecodeTimes)

        // --- Quality ---
        var psnr = 0.0, mae = 0.0
        if let dec = decodedImage {
            let m = computeMetrics(original: image, decoded: dec)
            psnr = m.psnr
            mae  = m.mae
        }

        // --- OpenJPEG (process-level timing, includes I/O) ---
        let tmpDir  = Self.resultDir
        let pgmPath = "\(tmpDir)/bench_\(imageName)_\(rateLabel).pgm"
        let opjJ2k  = "\(tmpDir)/bench_\(imageName)_\(rateLabel)_opj.j2k"
        let opjDec  = "\(tmpDir)/bench_\(imageName)_\(rateLabel)_opj_dec.pgm"

        try? writePGM(image, to: pgmPath)

        // Warmup OPJ
        for _ in 0..<warmup {
            _ = runOPJ(compress: true, input: pgmPath, output: opjJ2k, rate: opjRate)
        }

        var opjEncTimes: [Double] = []
        for _ in 0..<runs {
            let r = runOPJ(compress: true, input: pgmPath, output: opjJ2k, rate: opjRate)
            if r.success { opjEncTimes.append(r.timeMs) }
        }
        let opjEncMedian = opjEncTimes.isEmpty ? 0 : Self.median(opjEncTimes)
        let opjSize: Int = {
            guard let attr = try? FileManager.default.attributesOfItem(atPath: opjJ2k) else { return 0 }
            return (attr[.size] as? Int) ?? 0
        }()

        // OPJ Decode
        var opjDecTimes: [Double] = []
        if FileManager.default.fileExists(atPath: opjJ2k) {
            for _ in 0..<warmup {
                _ = runOPJ(compress: false, input: opjJ2k, output: opjDec)
            }
            for _ in 0..<runs {
                let r = runOPJ(compress: false, input: opjJ2k, output: opjDec)
                if r.success { opjDecTimes.append(r.timeMs) }
            }
        }
        let opjDecMedian = opjDecTimes.isEmpty ? 0 : Self.median(opjDecTimes)

        // Cleanup temp files
        try? FileManager.default.removeItem(atPath: pgmPath)
        try? FileManager.default.removeItem(atPath: opjJ2k)
        try? FileManager.default.removeItem(atPath: opjDec)

        return BenchmarkResult(
            imageName: imageName, modality: modality,
            width: image.width, height: image.height, bitDepth: bd,
            mode: mode, rateLabel: rateLabel,
            j2kEncTimeMs: j2kEncMedian, j2kDecTimeMs: j2kDecMedian,
            j2kSizeBytes: j2kSize, j2kPSNR: psnr, j2kMAE: mae,
            opjEncTimeMs: opjEncMedian, opjDecTimeMs: opjDecMedian,
            opjSizeBytes: opjSize
        )
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        let n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 0 ? (s[n / 2 - 1] + s[n / 2]) / 2.0 : s[n / 2]
    }

    private func printResult(_ r: BenchmarkResult) {
        let speedup = r.opjEncTimeMs > 0 ? String(format: "%.1fx", r.encSpeedup) : "N/A"
        let psnrStr = r.j2kPSNR.isInfinite ? "lossless" : String(format: "%.2f dB", r.j2kPSNR)
        let modeStr = "\(r.mode)(\(r.rateLabel))"
        print("  \(r.imageName.padding(toLength: 22, withPad: " ", startingAt: 0)) " +
              "\(r.width)x\(r.height) \(r.bitDepth)-bit  \(modeStr.padding(toLength: 16, withPad: " ", startingAt: 0))  " +
              "J2K:\(String(format: "%7.1f", r.j2kEncTimeMs)) ms  " +
              "OPJ:\(String(format: "%7.1f", r.opjEncTimeMs)) ms  " +
              "Enc:\(speedup)  " +
              "J2K:\(String(format: "%6.1f", Double(r.j2kSizeBytes) / 1024.0)) KB  " +
              "OPJ:\(String(format: "%6.1f", Double(r.opjSizeBytes) / 1024.0)) KB  " +
              "\(psnrStr)  MAE:\(String(format: "%.4f", r.j2kMAE))")
    }

    // MARK: - Setup/Teardown

    override class func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(atPath: resultDir,
                                                   withIntermediateDirectories: true)
        allResults = []
        print("\n" + String(repeating: "=", count: 130))
        print("  J2KSwift vs OpenJPEG 2.5.4 — Medical Imaging Benchmark (In-Process)")
        print("  Runs: \(benchmarkRuns) | Warmup: \(warmupRuns)")
        print(String(repeating: "=", count: 130))
    }

    override class func tearDown() {
        guard !allResults.isEmpty else { super.tearDown(); return }

        print("\n" + String(repeating: "=", count: 130))
        print("  FINAL SUMMARY (\(allResults.count) test cases)")
        print(String(repeating: "=", count: 130))

        let encSpeedups = allResults.compactMap { $0.encSpeedup > 0 && !$0.encSpeedup.isNaN && !$0.encSpeedup.isInfinite ? $0.encSpeedup : nil }
        let decSpeedups = allResults.compactMap { $0.decSpeedup > 0 && !$0.decSpeedup.isNaN && !$0.decSpeedup.isInfinite ? $0.decSpeedup : nil }

        if !encSpeedups.isEmpty {
            let avgEnc = encSpeedups.reduce(0, +) / Double(encSpeedups.count)
            let avgDec = decSpeedups.isEmpty ? 0 : decSpeedups.reduce(0, +) / Double(decSpeedups.count)
            print("  Avg Encode Speedup: \(String(format: "%.2f", avgEnc))x")
            print("  Avg Decode Speedup: \(String(format: "%.2f", avgDec))x")
        }

        let lossless = allResults.filter { $0.mode == "lossless" }
        let allPerfect = lossless.allSatisfy { $0.j2kMAE == 0 }
        print("  Lossless: \(lossless.count) tests — \(allPerfect ? "ALL perfect (MAE=0)" : "Some imperfect")")

        // Generate Markdown report
        var md = """
        # J2KSwift vs OpenJPEG 2.5.4 — Medical Imaging Benchmark

        > **Date**: \(ISO8601DateFormatter().string(from: Date()))
        > **Platform**: Apple Silicon (ARM64) — macOS
        > **J2KSwift**: 2.3.0 (Pure Swift 6, release mode, **in-process** timing)
        > **OpenJPEG**: 2.5.4 (C reference implementation, **process-level** timing — includes I/O & startup)
        > **Methodology**: \(benchmarkRuns) runs, \(warmupRuns) warmup, median timing
        > **Note**: OpenJPEG timing includes process startup, file I/O, and teardown overhead.
        >           J2KSwift timing is pure in-process encode/decode — a fairer "library vs library" comparison
        >           would require linking OpenJPEG as a C library.

        ---

        ## Executive Summary

        """

        if !encSpeedups.isEmpty {
            let avgEnc = encSpeedups.reduce(0, +) / Double(encSpeedups.count)
            let maxS = encSpeedups.max() ?? 0
            let minS = encSpeedups.min() ?? 0

            md += """
            | Metric | Value |
            |--------|-------|
            | Average Encode Speedup vs OPJ | **\(String(format: "%.2f", avgEnc))x** |
            | Best Encode Speedup | **\(String(format: "%.2f", maxS))x** |
            | Worst Encode Speedup | **\(String(format: "%.2f", minS))x** |
            | Lossless Accuracy | \(allPerfect ? "**MAE = 0** (all tests)" : "See details") |
            | Test Cases | \(allResults.count) |


            """
        }

        // Encoding table
        md += """
        ## Encoding Performance

        | Image | Size | Bits | Mode | J2K (ms) | OPJ (ms) | Speedup | J2K Size | OPJ Size | Ratio |
        |-------|------|------|------|----------|----------|---------|----------|----------|-------|

        """
        for r in allResults {
            let sp = r.opjEncTimeMs > 0 ? String(format: "**%.2fx**", r.encSpeedup) : "N/A"
            md += "| \(r.imageName) | \(r.width)x\(r.height) | \(r.bitDepth) | \(r.mode)(\(r.rateLabel)) | "
            md += "\(String(format: "%.1f", r.j2kEncTimeMs)) | \(String(format: "%.1f", r.opjEncTimeMs)) | \(sp) | "
            md += "\(String(format: "%.1f", Double(r.j2kSizeBytes)/1024)) KB | \(String(format: "%.1f", Double(r.opjSizeBytes)/1024)) KB | "
            md += "\(String(format: "%.1f", r.j2kRatio)):1 |\n"
        }

        // Decoding table
        md += """

        ## Decoding Performance

        | Image | Mode | J2K Dec (ms) | OPJ Dec (ms) | Speedup |
        |-------|------|-------------|-------------|---------|

        """
        for r in allResults {
            let dsp = r.opjDecTimeMs > 0 ? String(format: "**%.2fx**", r.decSpeedup) : "N/A"
            md += "| \(r.imageName) | \(r.mode)(\(r.rateLabel)) | "
            md += "\(String(format: "%.1f", r.j2kDecTimeMs)) | \(String(format: "%.1f", r.opjDecTimeMs)) | \(dsp) |\n"
        }

        // Quality
        md += """

        ## Quality Metrics

        ### Lossless

        | Image | Bits | MAE | Status |
        |-------|------|-----|--------|

        """
        for r in allResults where r.mode == "lossless" {
            let st = r.j2kMAE == 0 ? "✅ Perfect" : "⚠️ MAE=\(String(format: "%.4f", r.j2kMAE))"
            md += "| \(r.imageName) | \(r.bitDepth) | \(String(format: "%.4f", r.j2kMAE)) | \(st) |\n"
        }

        md += """

        ### Lossy

        | Image | Bits | Mode | PSNR (dB) | MAE | J2K Size | Ratio |
        |-------|------|------|-----------|-----|----------|-------|

        """
        for r in allResults where r.mode != "lossless" {
            let ps = r.j2kPSNR.isInfinite ? "∞" : String(format: "%.2f", r.j2kPSNR)
            md += "| \(r.imageName) | \(r.bitDepth) | \(r.mode)(\(r.rateLabel)) | \(ps) | "
            md += "\(String(format: "%.4f", r.j2kMAE)) | \(String(format: "%.1f", Double(r.j2kSizeBytes)/1024)) KB | \(String(format: "%.1f", r.j2kRatio)):1 |\n"
        }

        // CSV
        var csv = "Image,Modality,Width,Height,BitDepth,Mode,Rate,J2K_Enc_ms,J2K_Dec_ms,J2K_Size,J2K_Ratio,"
        csv += "OPJ_Enc_ms,OPJ_Dec_ms,OPJ_Size,OPJ_Ratio,EncSpeedup,DecSpeedup,PSNR_dB,MAE\n"
        for r in allResults {
            let ps = r.j2kPSNR.isInfinite ? "inf" : String(format: "%.2f", r.j2kPSNR)
            csv += "\(r.imageName),\(r.modality),\(r.width),\(r.height),\(r.bitDepth),"
            csv += "\(r.mode),\(r.rateLabel),"
            csv += "\(String(format: "%.1f", r.j2kEncTimeMs)),\(String(format: "%.1f", r.j2kDecTimeMs)),\(r.j2kSizeBytes),\(String(format: "%.2f", r.j2kRatio)),"
            csv += "\(String(format: "%.1f", r.opjEncTimeMs)),\(String(format: "%.1f", r.opjDecTimeMs)),\(r.opjSizeBytes),\(String(format: "%.2f", r.opjRatio)),"
            csv += "\(String(format: "%.2f", r.encSpeedup)),\(String(format: "%.2f", r.decSpeedup)),\(ps),\(String(format: "%.4f", r.j2kMAE))\n"
        }

        md += "\n---\n*Report generated by J2KSwift medical imaging benchmark. © 2025 Raster-Lab.*\n"

        let reportPath = "\(resultDir)/MEDICAL_BENCHMARK_REPORT.md"
        let csvPath    = "\(resultDir)/medical_benchmark.csv"
        try? md.write(toFile: reportPath, atomically: true, encoding: .utf8)
        try? csv.write(toFile: csvPath, atomically: true, encoding: .utf8)

        print("\n  Report: \(reportPath)")
        print("  CSV:    \(csvPath)")
        print(String(repeating: "=", count: 130) + "\n")

        super.tearDown()
    }

    // MARK: - CT Chest Tests

    func testCT_512_12bit_Lossless() async throws {
        let image = generateCTPhantom(width: 512, height: 512, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "CT_512_12", modality: "CT",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless CT 512 12-bit must achieve MAE=0")
    }

    func testCT_512_12bit_Lossy_Q09() async throws {
        let image = generateCTPhantom(width: 512, height: 512, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "CT_512_12", modality: "CT",
                             mode: "lossy", rateLabel: "q0.9",
                             quality: 0.9, opjRate: "10")
        Self.allResults.append(r); printResult(r)
    }

    func testCT_512_12bit_Rate_1bpp() async throws {
        let image = generateCTPhantom(width: 512, height: 512, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "CT_512_12", modality: "CT",
                             mode: "rate", rateLabel: "1bpp",
                             bitrate: 1.0, opjRate: "12")
        Self.allResults.append(r); printResult(r)
    }

    func testCT_512_16bit_Lossless() async throws {
        let image = generateCTPhantom(width: 512, height: 512, bitDepth: 16)
        let r = await runBenchmark(image: image, imageName: "CT_512_16", modality: "CT",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless CT 512 16-bit must achieve MAE=0")
    }

    func testCT_512_16bit_Rate_1bpp() async throws {
        let image = generateCTPhantom(width: 512, height: 512, bitDepth: 16)
        let r = await runBenchmark(image: image, imageName: "CT_512_16", modality: "CT",
                             mode: "rate", rateLabel: "1bpp",
                             bitrate: 1.0, opjRate: "16")
        Self.allResults.append(r); printResult(r)
    }

    func testCT_1024_12bit_Lossless() async throws {
        let image = generateCTPhantom(width: 1024, height: 1024, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "CT_1024_12", modality: "CT",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless CT 1024 12-bit must achieve MAE=0")
    }

    func testCT_1024_12bit_Rate_1bpp() async throws {
        let image = generateCTPhantom(width: 1024, height: 1024, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "CT_1024_12", modality: "CT",
                             mode: "rate", rateLabel: "1bpp",
                             bitrate: 1.0, opjRate: "12")
        Self.allResults.append(r); printResult(r)
    }

    func testCT_1024_16bit_Lossless() async throws {
        let image = generateCTPhantom(width: 1024, height: 1024, bitDepth: 16)
        let r = await runBenchmark(image: image, imageName: "CT_1024_16", modality: "CT",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless CT 1024 16-bit must achieve MAE=0")
    }

    // MARK: - MRI Brain Tests

    func testMRI_512_12bit_Lossless() async throws {
        let image = generateMRIBrain(width: 512, height: 512, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "MRI_512_12", modality: "MRI",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless MRI 512 12-bit must achieve MAE=0")
    }

    func testMRI_512_12bit_Lossy_Q09() async throws {
        let image = generateMRIBrain(width: 512, height: 512, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "MRI_512_12", modality: "MRI",
                             mode: "lossy", rateLabel: "q0.9",
                             quality: 0.9, opjRate: "10")
        Self.allResults.append(r); printResult(r)
    }

    func testMRI_512_12bit_Rate_1bpp() async throws {
        let image = generateMRIBrain(width: 512, height: 512, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "MRI_512_12", modality: "MRI",
                             mode: "rate", rateLabel: "1bpp",
                             bitrate: 1.0, opjRate: "12")
        Self.allResults.append(r); printResult(r)
    }

    func testMRI_512_16bit_Lossless() async throws {
        let image = generateMRIBrain(width: 512, height: 512, bitDepth: 16)
        let r = await runBenchmark(image: image, imageName: "MRI_512_16", modality: "MRI",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless MRI 512 16-bit must achieve MAE=0")
    }

    func testMRI_1024_12bit_Lossless() async throws {
        let image = generateMRIBrain(width: 1024, height: 1024, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "MRI_1024_12", modality: "MRI",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless MRI 1024 12-bit must achieve MAE=0")
    }

    func testMRI_1024_12bit_Rate_1bpp() async throws {
        let image = generateMRIBrain(width: 1024, height: 1024, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "MRI_1024_12", modality: "MRI",
                             mode: "rate", rateLabel: "1bpp",
                             bitrate: 1.0, opjRate: "12")
        Self.allResults.append(r); printResult(r)
    }

    // MARK: - Ultrasound Tests

    func testUS_512_8bit_Lossless() async throws {
        let image = generateUltrasound(width: 512, height: 512, bitDepth: 8)
        let r = await runBenchmark(image: image, imageName: "US_512_8", modality: "US",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless US 512 8-bit must achieve MAE=0")
    }

    func testUS_512_8bit_Rate_1bpp() async throws {
        let image = generateUltrasound(width: 512, height: 512, bitDepth: 8)
        let r = await runBenchmark(image: image, imageName: "US_512_8", modality: "US",
                             mode: "rate", rateLabel: "1bpp",
                             bitrate: 1.0, opjRate: "8")
        Self.allResults.append(r); printResult(r)
    }

    func testUS_512_12bit_Lossless() async throws {
        let image = generateUltrasound(width: 512, height: 512, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "US_512_12", modality: "US",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless US 512 12-bit must achieve MAE=0")
    }

    // MARK: - Mammogram Tests

    func testMammo_1024_12bit_Lossless() async throws {
        let image = generateMammogram(width: 1024, height: 1024, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "Mammo_1024_12", modality: "Mammo",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless Mammo 1024 12-bit must achieve MAE=0")
    }

    func testMammo_1024_12bit_Rate_1bpp() async throws {
        let image = generateMammogram(width: 1024, height: 1024, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "Mammo_1024_12", modality: "Mammo",
                             mode: "rate", rateLabel: "1bpp",
                             bitrate: 1.0, opjRate: "12")
        Self.allResults.append(r); printResult(r)
    }

    func testMammo_2048_12bit_Lossless() async throws {
        let image = generateMammogram(width: 2048, height: 2048, bitDepth: 12)
        let r = await runBenchmark(image: image, imageName: "Mammo_2048_12", modality: "Mammo",
                             mode: "lossless", rateLabel: "lossless")
        Self.allResults.append(r); printResult(r)
        XCTAssertEqual(r.j2kMAE, 0, "Lossless Mammo 2048 12-bit must achieve MAE=0")
    }
}
