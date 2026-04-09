import XCTest
@testable import J2KCodec
@testable import J2KCore
import Foundation

/// Comprehensive benchmark suite: speed + quality of J2KSwift vs OpenJPEG.
///
/// Measures encoding time, decoding time, PSNR, SSIM, and compression ratio
/// for synthetic and real-world test images at multiple bitrates and resolutions.
/// Results are written to `/tmp/j2k_benchmark_results.csv` for analysis.
final class J2KAcceleratedBenchmarkTest: XCTestCase {

    private let opjCompress   = "/opt/homebrew/bin/opj_compress"
    private let opjDecompress = "/opt/homebrew/bin/opj_decompress"
    private let outputDir     = "/tmp/j2k_accel_benchmark"

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(
            atPath: outputDir, withIntermediateDirectories: true)
    }

    // MARK: - Test Image Generation

    /// Generate a gradient test image (deterministic, hardware-agnostic).
    private func generateGradientImage(width: Int, height: Int, components: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        var comps: [J2KComponent] = []

        for c in 0..<components {
            let pixelCount = width * height
            var data = Data(count: bitDepth <= 8 ? pixelCount : pixelCount * 2)
            data.withUnsafeMutableBytes { buf in
                let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let val: Int
                        switch c {
                        case 0: val = (x * maxVal) / max(width - 1, 1)
                        case 1: val = (y * maxVal) / max(height - 1, 1)
                        default: val = ((x + y) * maxVal) / max(width + height - 2, 1)
                        }
                        let i = y * width + x
                        if bitDepth <= 8 {
                            ptr[i] = UInt8(min(val, maxVal))
                        } else {
                            let v = UInt16(min(val, maxVal))
                            ptr[i * 2]     = UInt8(v >> 8)
                            ptr[i * 2 + 1] = UInt8(v & 0xFF)
                        }
                    }
                }
            }

            comps.append(J2KComponent(
                index: c, bitDepth: bitDepth, signed: false,
                width: width, height: height, data: data))
        }

        return J2KImage(width: width, height: height, components: comps)
    }

    /// Generate a medical-style phantom image (16-bit grayscale).
    private func generateMedicalPhantom(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = Double((1 << bitDepth) - 1)
        let pixelCount = width * height
        var data = Data(count: pixelCount * 2)

        let cx = Double(width) / 2
        let cy = Double(height) / 2
        let radius = Double(min(width, height)) / 2

        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let dy = Double(y) - cy
                for x in 0..<width {
                    let dx = Double(x) - cx
                    let dist = sqrt(dx * dx + dy * dy)
                    let norm = max(0.0, 1.0 - dist / radius)
                    let scaled = norm * maxVal * 0.8 + maxVal * 0.1
                    let clamped = min(maxVal, scaled)
                    let val = UInt16(clamped)
                    let i = y * width + x
                    ptr[i * 2]     = UInt8(val >> 8)
                    ptr[i * 2 + 1] = UInt8(val & 0xFF)
                }
            }
        }

        let comp = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height, data: data)
        return J2KImage(width: width, height: height, components: [comp])
    }

    // MARK: - Metrics

    /// Compute PSNR between original and decoded images (single component).
    private func computePSNR(original: Data, decoded: Data, bitDepth: Int) -> Double {
        let maxVal = Double((1 << bitDepth) - 1)
        var mse: Double = 0
        let count: Int

        if bitDepth <= 8 {
            count = min(original.count, decoded.count)
            for i in 0..<count {
                let diff = Double(original[i]) - Double(decoded[i])
                mse += diff * diff
            }
        } else {
            count = min(original.count, decoded.count) / 2
            original.withUnsafeBytes { origBuf in
                decoded.withUnsafeBytes { decBuf in
                    let origPtr = origBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let decPtr = decBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<count {
                        let o = Double(UInt16(origPtr[i*2]) << 8 | UInt16(origPtr[i*2+1]))
                        let d = Double(UInt16(decPtr[i*2]) << 8 | UInt16(decPtr[i*2+1]))
                        mse += (o - d) * (o - d)
                    }
                }
            }
        }

        guard count > 0 else { return 0 }
        mse /= Double(count)
        guard mse > 0 else { return Double.infinity }
        return 10.0 * log10(maxVal * maxVal / mse)
    }

    /// Compute MAE between original and decoded images (single component).
    private func computeMAE(original: Data, decoded: Data, bitDepth: Int) -> Double {
        var totalErr: Double = 0
        let count: Int

        if bitDepth <= 8 {
            count = min(original.count, decoded.count)
            for i in 0..<count {
                totalErr += abs(Double(original[i]) - Double(decoded[i]))
            }
        } else {
            count = min(original.count, decoded.count) / 2
            original.withUnsafeBytes { origBuf in
                decoded.withUnsafeBytes { decBuf in
                    let origPtr = origBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    let decPtr = decBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<count {
                        let o = Double(UInt16(origPtr[i*2]) << 8 | UInt16(origPtr[i*2+1]))
                        let d = Double(UInt16(decPtr[i*2]) << 8 | UInt16(decPtr[i*2+1]))
                        totalErr += abs(o - d)
                    }
                }
            }
        }

        return count > 0 ? totalErr / Double(count) : 0
    }

    // MARK: - OpenJPEG Helpers

    private var hasOpenJPEG: Bool {
        FileManager.default.fileExists(atPath: opjCompress) &&
        FileManager.default.fileExists(atPath: opjDecompress)
    }

    /// Encode a PGM file with OpenJPEG and return (encodeTime, fileSize).
    private func opjEncode(
        pgmPath: String, j2kPath: String,
        compressionRatio: Double?, lossless: Bool
    ) throws -> (time: Double, size: Int) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opjCompress)
        if lossless {
            proc.arguments = ["-i", pgmPath, "-o", j2kPath, "-r", "1"]
        } else {
            let ratio = compressionRatio ?? 10.0
            proc.arguments = ["-i", pgmPath, "-o", j2kPath, "-r", String(format: "%.1f", ratio)]
        }
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        let start = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OPJ", code: Int(proc.terminationStatus))
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: j2kPath)[.size] as? Int ?? 0
        return (elapsed, fileSize)
    }

    /// Decode a J2K file with OpenJPEG and return (decodeTime, pgmPath).
    private func opjDecode(j2kPath: String, pgmPath: String) throws -> Double {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opjDecompress)
        proc.arguments = ["-i", j2kPath, "-o", pgmPath]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        let start = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OPJ", code: Int(proc.terminationStatus))
        }

        return elapsed
    }

    /// Save a grayscale image as PGM for OpenJPEG input.
    private func savePGM(
        data: Data, width: Int, height: Int, bitDepth: Int, path: String
    ) throws {
        let maxVal = (1 << bitDepth) - 1
        var pgm = Data()
        let header = "P5\n\(width) \(height)\n\(maxVal)\n"
        pgm.append(header.data(using: .ascii)!)
        pgm.append(data)
        try pgm.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - J2KSwift Encode/Decode Timing

    private func j2kEncode(
        image: J2KImage, quality: Double, lossless: Bool,
        bpp: Double? = nil,
        decompositionLevels: Int = 5
    ) throws -> (time: Double, data: Data) {
        var config = J2KEncodingConfiguration(
            quality: quality, lossless: lossless,
            decompositionLevels: decompositionLevels)
        if let bpp = bpp {
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }
        let encoder = J2KEncoder(encodingConfiguration: config)

        let start = CFAbsoluteTimeGetCurrent()
        let encoded = try encoder.encode(image)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        return (elapsed, encoded)
    }

    private func j2kDecode(data: Data) throws -> (time: Double, image: J2KImage) {
        let start = CFAbsoluteTimeGetCurrent()
        let decoded = try DecoderPipeline().decode(data)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        return (elapsed, decoded)
    }

    // MARK: - Benchmark Result

    struct BenchmarkResult {
        let label: String
        let width: Int
        let height: Int
        let bitDepth: Int
        let mode: String
        let j2kEncodeTime: Double
        let j2kDecodeTime: Double
        let j2kFileSize: Int
        let j2kPSNR: Double
        let j2kMAE: Double
        let opjEncodeTime: Double?
        let opjDecodeTime: Double?
        let opjFileSize: Int?
        let opjPSNR: Double?
        let opjMAE: Double?
        let speedup: Double?     // J2K/OPJ encode time ratio (<1 means J2K faster)

        var csvLine: String {
            let opjEnc  = opjEncodeTime.map { String(format: "%.4f", $0) } ?? "N/A"
            let opjDec  = opjDecodeTime.map { String(format: "%.4f", $0) } ?? "N/A"
            let opjSz   = opjFileSize.map { "\($0)" } ?? "N/A"
            let opjP    = opjPSNR.map { String(format: "%.2f", $0) } ?? "N/A"
            let opjM    = opjMAE.map { String(format: "%.2f", $0) } ?? "N/A"
            let spd     = speedup.map { String(format: "%.2fx", $0) } ?? "N/A"
            return "\(label),\(width)x\(height),\(bitDepth),\(mode)," +
                   "\(String(format: "%.4f", j2kEncodeTime))," +
                   "\(String(format: "%.4f", j2kDecodeTime))," +
                   "\(j2kFileSize)," +
                   "\(j2kPSNR == .infinity ? "Inf" : String(format: "%.2f", j2kPSNR))," +
                   "\(String(format: "%.2f", j2kMAE))," +
                   "\(opjEnc),\(opjDec),\(opjSz),\(opjP),\(opjM),\(spd)"
        }
    }

    // MARK: - Full Benchmark Suite

    func testAcceleratedEncoderBenchmark() throws {
        var results: [BenchmarkResult] = []

        // Test configurations: (label, width, height, bitDepth, components, modes)
        let configs: [(String, Int, Int, Int, Int)] = [
            ("Grad-256-8b",   256,  256,  8, 1),
            ("Grad-512-8b",   512,  512,  8, 1),
            ("Grad-512-RGB",  512,  512,  8, 3),
            ("Grad-1024-8b", 1024, 1024,  8, 1),
            ("Med-512-12b",   512,  512, 12, 1),
            ("Med-512-16b",   512,  512, 16, 1),
        ]

        let modes: [(String, Bool, Double, Double?)] = [
            // (label, lossless, quality, bpp)
            ("lossless",  true,  1.0, nil),
            ("lossy-q0.9", false, 0.9, nil),
            ("lossy-2bpp", false, 0.8, 2.0),
            ("lossy-1bpp", false, 0.7, 1.0),
            ("lossy-0.5bpp", false, 0.5, 0.5),
        ]

        for (label, w, h, bd, comps) in configs {
            let image: J2KImage
            if comps == 1 && bd > 8 {
                image = generateMedicalPhantom(width: w, height: h, bitDepth: bd)
            } else {
                image = generateGradientImage(width: w, height: h, components: comps, bitDepth: bd)
            }

            for (modeLabel, lossless, quality, bpp) in modes {
                // Skip lossy modes for very small images
                if w < 64 && !lossless { continue }

                let levels = min(5, Int(log2(Double(min(w, h)))) - 1)

                // --- J2KSwift encode ---
                let (encTime, encoded) = try j2kEncode(
                    image: image, quality: quality, lossless: lossless,
                    bpp: bpp, decompositionLevels: levels)

                // --- J2KSwift decode ---
                let (decTime, decoded) = try j2kDecode(data: encoded)

                // --- Quality metrics ---
                let origData = image.components[0].data
                let decData  = decoded.components[0].data
                let psnr = computePSNR(original: origData, decoded: decData, bitDepth: bd)
                let mae  = computeMAE(original: origData, decoded: decData, bitDepth: bd)

                // --- OpenJPEG comparison (if available, grayscale only) ---
                var opjEncTime: Double? = nil
                var opjDecTime: Double? = nil
                var opjSize: Int? = nil
                var opjPsnr: Double? = nil
                var opjMae: Double? = nil
                var speedup: Double? = nil

                if hasOpenJPEG && comps == 1 {
                    let pgmPath = "\(outputDir)/\(label)_\(modeLabel).pgm"
                    let opjJ2kPath = "\(outputDir)/\(label)_\(modeLabel)_opj.j2k"
                    let opjPgmPath = "\(outputDir)/\(label)_\(modeLabel)_opj_dec.pgm"

                    try savePGM(data: origData, width: w, height: h, bitDepth: bd, path: pgmPath)

                    let ratio: Double? = lossless ? nil : {
                        // Approximate compression ratio from bpp
                        if let bpp = bpp { return Double(bd) / bpp }
                        return Double(bd) / (Double(bd) * quality)
                    }()

                    do {
                        let (oEncTime, oSize) = try opjEncode(
                            pgmPath: pgmPath, j2kPath: opjJ2kPath,
                            compressionRatio: ratio, lossless: lossless)
                        opjEncTime = oEncTime
                        opjSize = oSize

                        let oDecTime = try opjDecode(j2kPath: opjJ2kPath, pgmPath: opjPgmPath)
                        opjDecTime = oDecTime

                        // Read decoded PGM and compute metrics
                        if let pgmData = FileManager.default.contents(atPath: opjPgmPath) {
                            let opjPixels = parsePGMPixels(pgmData, expectedWidth: w, expectedHeight: h, bitDepth: bd)
                            if let opjPx = opjPixels {
                                opjPsnr = computePSNR(original: origData, decoded: opjPx, bitDepth: bd)
                                opjMae  = computeMAE(original: origData, decoded: opjPx, bitDepth: bd)
                            }
                        }

                        speedup = opjEncTime.map { encTime > 0 ? $0 / encTime : 0 }
                    } catch {
                        print("  OpenJPEG failed for \(label) \(modeLabel): \(error)")
                    }
                }

                let result = BenchmarkResult(
                    label: label, width: w, height: h, bitDepth: bd,
                    mode: modeLabel,
                    j2kEncodeTime: encTime, j2kDecodeTime: decTime,
                    j2kFileSize: encoded.count,
                    j2kPSNR: psnr, j2kMAE: mae,
                    opjEncodeTime: opjEncTime, opjDecodeTime: opjDecTime,
                    opjFileSize: opjSize,
                    opjPSNR: opjPsnr, opjMAE: opjMae,
                    speedup: speedup)

                results.append(result)

                let speedStr = speedup.map { String(format: "%.2fx", $0) } ?? "-"
                let psnrStr = psnr == .infinity ? "Inf" : String(format: "%.1f", psnr)
                print("[\(label)] \(modeLabel): enc=\(String(format: "%.3f", encTime))s " +
                      "dec=\(String(format: "%.3f", decTime))s " +
                      "size=\(encoded.count) PSNR=\(psnrStr) MAE=\(String(format: "%.1f", mae)) " +
                      "speedup=\(speedStr)")
            }
        }

        // --- Write CSV ---
        let csvHeader = "Image,Resolution,BitDepth,Mode," +
                        "J2K_EncTime_s,J2K_DecTime_s,J2K_Size_bytes,J2K_PSNR_dB,J2K_MAE," +
                        "OPJ_EncTime_s,OPJ_DecTime_s,OPJ_Size_bytes,OPJ_PSNR_dB,OPJ_MAE,Speedup"
        let csvBody = results.map { $0.csvLine }.joined(separator: "\n")
        let csv = csvHeader + "\n" + csvBody + "\n"
        try csv.write(toFile: "\(outputDir)/benchmark_results.csv", atomically: true, encoding: .utf8)
        print("\nResults written to \(outputDir)/benchmark_results.csv")

        // --- Assertions ---
        for r in results {
            if r.mode == "lossless" {
                XCTAssertEqual(r.j2kMAE, 0, accuracy: 0.001,
                    "\(r.label) lossless must have MAE=0")
                XCTAssert(r.j2kPSNR.isInfinite,
                    "\(r.label) lossless must have infinite PSNR")
            }
            // Quality should not be worse than baseline thresholds
            if r.mode.contains("lossy") {
                XCTAssertGreaterThan(r.j2kPSNR, 25.0,
                    "\(r.label) \(r.mode) PSNR too low: \(r.j2kPSNR)")
            }
            // If OpenJPEG available, quality gap should be small
            if let opjP = r.opjPSNR, !r.mode.contains("lossless") {
                let gap = r.j2kPSNR - opjP
                XCTAssertGreaterThan(gap, -3.0,
                    "\(r.label) \(r.mode) PSNR gap vs OPJ too large: \(gap) dB")
            }
        }
    }

    // MARK: - Encode-only micro-benchmark (XCTest measure)

    func testEncodeSpeed512x512Lossy() throws {
        let image = generateGradientImage(width: 512, height: 512, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        measure {
            _ = try? encoder.encode(image)
        }
    }

    func testEncodeSpeed1024x1024Lossy() throws {
        let image = generateGradientImage(width: 1024, height: 1024, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        measure {
            _ = try? encoder.encode(image)
        }
    }

    func testEncodeSpeed512x512Lossless() throws {
        let image = generateGradientImage(width: 512, height: 512, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        measure {
            _ = try? encoder.encode(image)
        }
    }

    func testEncodeSpeedMedical512x512_12bit() throws {
        let image = generateMedicalPhantom(width: 512, height: 512, bitDepth: 12)
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        measure {
            _ = try? encoder.encode(image)
        }
    }

    // MARK: - PGM Parser

    private func parsePGMPixels(_ data: Data, expectedWidth: Int, expectedHeight: Int, bitDepth: Int) -> Data? {
        guard let str = String(data: data.prefix(256), encoding: .ascii) else { return nil }
        let lines = str.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return nil }

        // Find end of header (P5\nW H\nMAXVAL\n)
        var headerEnd = 0
        var newlineCount = 0
        for (i, byte) in data.enumerated() {
            if byte == 0x0A { // newline
                newlineCount += 1
                if newlineCount >= 3 {
                    headerEnd = i + 1
                    break
                }
            }
        }

        guard headerEnd > 0 else { return nil }
        let pixelData = data.subdata(in: headerEnd..<data.count)
        let expectedSize = bitDepth <= 8
            ? expectedWidth * expectedHeight
            : expectedWidth * expectedHeight * 2
        guard pixelData.count >= expectedSize else { return nil }
        return pixelData.prefix(expectedSize)
    }
}
