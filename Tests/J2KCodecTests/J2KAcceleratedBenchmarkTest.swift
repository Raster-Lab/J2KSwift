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

    // MARK: - Deterministic PRNG

    /// Simple xorshift32 PRNG for reproducible noise across platforms.
    private struct Xorshift32 {
        var state: UInt32
        mutating func next() -> UInt32 {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return state
        }
        /// Returns a value in 0..<upperBound
        mutating func nextInt(_ upperBound: Int) -> Int {
            return Int(next() % UInt32(upperBound))
        }
    }

    // MARK: - Test Image Generation

    /// Generate a natural-looking test image with gradients, edges, and texture noise.
    ///
    /// This produces images that exercise the full codec pipeline:
    /// - Smooth gradients → LL subband energy
    /// - Sharp edges → HL/LH/HH subband energy
    /// - Random texture noise → detail coefficients that rate control can discard
    private func generateNaturalImage(width: Int, height: Int, components: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        var comps: [J2KComponent] = []

        for c in 0..<components {
            let pixelCount = width * height
            var data = Data(count: bitDepth <= 8 ? pixelCount : pixelCount * 2)
            var rng = Xorshift32(state: UInt32(42 + c * 1337))

            data.withUnsafeMutableBytes { buf in
                let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let w = width, h = height
                for y in 0..<h {
                    for x in 0..<w {
                        // Base: smooth gradient (different per component)
                        let gx = Double(x) / Double(max(w - 1, 1))
                        let gy = Double(y) / Double(max(h - 1, 1))
                        var base: Double
                        switch c {
                        case 0: base = gx * 0.4 + gy * 0.2
                        case 1: base = gy * 0.4 + gx * 0.1
                        default: base = (gx + gy) * 0.25
                        }

                        // Edges: rectangular blocks and circles
                        let bx = x / (w / 4), by = y / (h / 4)
                        if (bx + by) % 2 == 0 {
                            base += 0.15
                        }
                        let cx = Double(x) - Double(w) * 0.6
                        let cy = Double(y) - Double(h) * 0.4
                        let r = sqrt(cx * cx + cy * cy) / Double(min(w, h))
                        if r < 0.2 { base += 0.2 }

                        // Texture noise: ±10% of range
                        let noise = (Double(rng.nextInt(maxVal)) / Double(maxVal) - 0.5) * 0.2
                        base += noise

                        let clamped = max(0.0, min(1.0, base))
                        let val = Int(clamped * Double(maxVal) + 0.5)
                        let i = y * w + x
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

    /// Generate a medical-style phantom image with multiple tissue structures and noise.
    ///
    /// Includes:
    /// - Background tissue field with realistic intensity variation
    /// - Multiple elliptical organs at different densities
    /// - Gaussian noise simulating quantum noise (~2% of range)
    /// - Fine texture from pseudo-random tissue microstructure
    private func generateMedicalPhantom(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = Double((1 << bitDepth) - 1)
        let pixelCount = width * height
        var data = Data(count: pixelCount * 2)
        var rng = Xorshift32(state: 0xDEADBEEF)

        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let w = Double(width), h = Double(height)

            for y in 0..<height {
                let ny = Double(y) / h
                for x in 0..<width {
                    let nx = Double(x) / w

                    // Background: soft radial falloff (body cross-section)
                    let dx = nx - 0.5, dy = ny - 0.5
                    let bodyR = sqrt(dx * dx * 1.5 + dy * dy * 2.0)
                    var intensity = bodyR < 0.4 ? 0.3 + 0.1 * (1.0 - bodyR / 0.4) : 0.1

                    // Organ 1: bright ellipse (liver-like)
                    let o1x = nx - 0.4, o1y = ny - 0.45
                    if (o1x * o1x / 0.025 + o1y * o1y / 0.015) < 1.0 {
                        intensity = 0.55
                    }

                    // Organ 2: medium ellipse (kidney-like)
                    let o2x = nx - 0.65, o2y = ny - 0.5
                    if (o2x * o2x / 0.008 + o2y * o2y / 0.02) < 1.0 {
                        intensity = 0.45
                    }

                    // Organ 3: small bright circle (lesion)
                    let o3x = nx - 0.42, o3y = ny - 0.42
                    if (o3x * o3x + o3y * o3y) < 0.002 {
                        intensity = 0.7
                    }

                    // Spine: bright vertical stripe
                    if abs(nx - 0.5) < 0.02 && ny > 0.25 && ny < 0.75 {
                        intensity = 0.65
                    }

                    // Ribs: horizontal bright bars
                    let ribPhase = sin(ny * 30.0)
                    if abs(dx) > 0.15 && abs(dx) < 0.35 && ribPhase > 0.8 {
                        intensity += 0.1
                    }

                    // Quantum noise: ~2% of range (Gaussian approx from uniform)
                    let u1 = Double(rng.nextInt(10000)) / 10000.0
                    let u2 = Double(rng.nextInt(10000)) / 10000.0
                    let gaussNoise = (u1 + u2 - 1.0) * 0.03
                    intensity += gaussNoise

                    // Fine tissue texture: pseudo-random micro variation
                    let texHash = Double(rng.nextInt(1000)) / 1000.0
                    intensity += (texHash - 0.5) * 0.015

                    let clamped = max(0.0, min(1.0, intensity))
                    let val = UInt16(clamped * maxVal + 0.5)
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
    ///
    /// Times include process launch overhead (~60ms). OPJ timing is reported
    /// for reference only — quality comparison (PSNR/MAE at same ratio) is
    /// the primary metric since J2K runs in-process debug mode vs OPJ release binary.
    private func opjEncode(
        pgmPath: String, j2kPath: String,
        compressionRatio: Double?, lossless: Bool
    ) throws -> (time: Double, size: Int) {
        var times: [Double] = []
        for run in 0..<3 {
            if run > 0 { try? FileManager.default.removeItem(atPath: j2kPath) }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: opjCompress)
            if lossless {
                proc.arguments = ["-i", pgmPath, "-o", j2kPath]
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
            times.append(elapsed)
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: j2kPath)[.size] as? Int ?? 0
        return (times.sorted()[times.count / 2], fileSize)
    }

    /// Decode a J2K file with OpenJPEG and return decodeTime.
    ///
    /// Times include process launch overhead (~60ms).
    private func opjDecode(j2kPath: String, pgmPath: String) throws -> Double {
        var times: [Double] = []
        for run in 0..<3 {
            if run > 0 { try? FileManager.default.removeItem(atPath: pgmPath) }

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
            times.append(elapsed)
        }

        return times.sorted()[times.count / 2]
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

    /// Save an RGB image as PPM for OpenJPEG input.
    private func savePPM(
        components: [J2KComponent], width: Int, height: Int, bitDepth: Int, path: String
    ) throws {
        guard components.count >= 3 else { return }
        let maxVal = (1 << bitDepth) - 1
        var ppm = Data()
        let header = "P6\n\(width) \(height)\n\(maxVal)\n"
        ppm.append(header.data(using: .ascii)!)
        let pixelCount = width * height
        if bitDepth <= 8 {
            for i in 0..<pixelCount {
                ppm.append(components[0].data[i])
                ppm.append(components[1].data[i])
                ppm.append(components[2].data[i])
            }
        } else {
            for i in 0..<pixelCount {
                for c in 0..<3 {
                    ppm.append(components[c].data[i * 2])
                    ppm.append(components[c].data[i * 2 + 1])
                }
            }
        }
        try ppm.write(to: URL(fileURLWithPath: path))
    }

    /// Parse PPM pixel data (P6 format) into separate component Data arrays.
    private func parsePPMPixels(_ data: Data, expectedWidth: Int, expectedHeight: Int, bitDepth: Int) -> [Data]? {
        var headerEnd = 0
        var significantLines = 0
        var lineStart = 0
        for i in 0..<min(data.count, 1024) {
            if data[i] == 0x0A {
                if lineStart < data.count && data[lineStart] != 0x23 {
                    significantLines += 1
                }
                lineStart = i + 1
                if significantLines >= 3 {
                    headerEnd = i + 1
                    break
                }
            }
        }
        guard headerEnd > 0 else { return nil }
        let pixelData = data.subdata(in: headerEnd..<data.count)
        let pixelCount = expectedWidth * expectedHeight
        let bytesPerSample = bitDepth <= 8 ? 1 : 2
        let expectedSize = pixelCount * 3 * bytesPerSample
        guard pixelData.count >= expectedSize else { return nil }

        var r = Data(count: pixelCount * bytesPerSample)
        var g = Data(count: pixelCount * bytesPerSample)
        var b = Data(count: pixelCount * bytesPerSample)
        if bitDepth <= 8 {
            for i in 0..<pixelCount {
                r[i] = pixelData[i * 3]
                g[i] = pixelData[i * 3 + 1]
                b[i] = pixelData[i * 3 + 2]
            }
        } else {
            for i in 0..<pixelCount {
                r[i * 2]     = pixelData[i * 6]
                r[i * 2 + 1] = pixelData[i * 6 + 1]
                g[i * 2]     = pixelData[i * 6 + 2]
                g[i * 2 + 1] = pixelData[i * 6 + 3]
                b[i * 2]     = pixelData[i * 6 + 4]
                b[i * 2 + 1] = pixelData[i * 6 + 5]
            }
        }
        return [r, g, b]
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
        config.enableParallelCodeBlocks = true
        if let bpp = bpp {
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }
        let encoder = J2KEncoder(encodingConfiguration: config)

        // Warmup run (excluded from timing)
        _ = try encoder.encode(image)

        // Single timed run (debug mode; speed comparison not meaningful)
        let start = CFAbsoluteTimeGetCurrent()
        let encoded = try encoder.encode(image)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        return (elapsed, encoded)
    }

    private func j2kDecode(data: Data) throws -> (time: Double, image: J2KImage) {
        // Warmup run
        _ = try DecoderPipeline().decode(data)

        // Single timed run
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
        let encSpeedup: Double?  // J2K_enc/OPJ_enc (<1 means J2K faster, >1 means J2K slower)
        let decSpeedup: Double?  // J2K_dec/OPJ_dec (<1 means J2K faster, >1 means J2K slower)

        var csvLine: String {
            let pixels = Double(width * height)
            let mpxEnc  = pixels / 1_000_000.0 / j2kEncodeTime
            let mpxDec  = pixels / 1_000_000.0 / j2kDecodeTime
            let opjEnc  = opjEncodeTime.map { String(format: "%.4f", $0) } ?? "N/A"
            let opjDec  = opjDecodeTime.map { String(format: "%.4f", $0) } ?? "N/A"
            let opjMpxE = opjEncodeTime.map { String(format: "%.1f", pixels / 1_000_000.0 / $0) } ?? "N/A"
            let opjMpxD = opjDecodeTime.map { String(format: "%.1f", pixels / 1_000_000.0 / $0) } ?? "N/A"
            let opjSz   = opjFileSize.map { "\($0)" } ?? "N/A"
            let opjP    = opjPSNR.map { $0.isInfinite ? "Inf" : String(format: "%.2f", $0) } ?? "N/A"
            let opjM    = opjMAE.map { String(format: "%.2f", $0) } ?? "N/A"
            let encSpd  = encSpeedup.map { String(format: "%.2fx", $0) } ?? "N/A"
            let decSpd  = decSpeedup.map { String(format: "%.2fx", $0) } ?? "N/A"
            return "\(label),\(width)x\(height),\(bitDepth),\(mode)," +
                   "\(String(format: "%.4f", j2kEncodeTime))," +
                   "\(String(format: "%.1f", mpxEnc))," +
                   "\(String(format: "%.4f", j2kDecodeTime))," +
                   "\(String(format: "%.1f", mpxDec))," +
                   "\(j2kFileSize)," +
                   "\(j2kPSNR.isInfinite ? "Inf" : String(format: "%.2f", j2kPSNR))," +
                   "\(String(format: "%.2f", j2kMAE))," +
                   "\(opjEnc),\(opjMpxE),\(opjDec),\(opjMpxD),\(opjSz),\(opjP),\(opjM),\(encSpd),\(decSpd)"
        }
    }

    // MARK: - Full Benchmark Suite

    func testAcceleratedEncoderBenchmark() throws {
        var results: [BenchmarkResult] = []

        // Test configurations: (label, width, height, bitDepth, components, modes)
        let configs: [(String, Int, Int, Int, Int)] = [
            ("Nat-256-8b",    256,  256,  8, 1),
            ("Nat-512-8b",    512,  512,  8, 1),
            ("Nat-512-RGB",   512,  512,  8, 3),
            ("Nat-1024-8b",  1024, 1024,  8, 1),
            ("Med-512-12b",   512,  512, 12, 1),
            ("Med-512-16b",   512,  512, 16, 1),
        ]

        // Each bpp mode uses a LOWER quality to produce genuinely different
        // quantization, so the rate allocator has room to truncate.
        // quality controls quantization step sizes;
        // bpp controls PCRD rate-distortion truncation.
        let modes: [(String, Bool, Double, Double?)] = [
            // (label, lossless, quality, bpp)
            ("lossless",    true,  1.0,  nil),
            ("lossy-q0.9",  false, 0.9,  nil),
            ("lossy-2bpp",  false, 0.5,  2.0),
            ("lossy-1bpp",  false, 0.3,  1.0),
            ("lossy-0.5bpp", false, 0.2, 0.5),
        ]

        for (label, w, h, bd, comps) in configs {
            let image: J2KImage
            if comps == 1 && bd > 8 {
                image = generateMedicalPhantom(width: w, height: h, bitDepth: bd)
            } else {
                image = generateNaturalImage(width: w, height: h, components: comps, bitDepth: bd)
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

                // --- Quality metrics (average across all components) ---
                var psnrSum = 0.0
                var maeSum = 0.0
                let measuredComps = min(image.components.count, decoded.components.count)
                for c in 0..<measuredComps {
                    psnrSum += computePSNR(original: image.components[c].data,
                                           decoded: decoded.components[c].data, bitDepth: bd)
                    maeSum  += computeMAE(original: image.components[c].data,
                                          decoded: decoded.components[c].data, bitDepth: bd)
                }
                let psnr = psnrSum / Double(measuredComps)
                let mae  = maeSum / Double(measuredComps)

                // --- OpenJPEG comparison ---
                var opjEncTime: Double? = nil
                var opjDecTime: Double? = nil
                var opjSize: Int? = nil
                var opjPsnr: Double? = nil
                var opjMae: Double? = nil
                var speedup: Double? = nil

                if hasOpenJPEG {
                    let ext = comps == 1 ? "pgm" : "ppm"
                    let imgPath = "\(outputDir)/\(label)_\(modeLabel).\(ext)"
                    let opjJ2kPath = "\(outputDir)/\(label)_\(modeLabel)_opj.j2k"
                    let opjDecPath = "\(outputDir)/\(label)_\(modeLabel)_opj_dec.\(ext)"

                    if comps == 1 {
                        try savePGM(data: image.components[0].data,
                                    width: w, height: h, bitDepth: bd, path: imgPath)
                    } else {
                        try savePPM(components: image.components,
                                    width: w, height: h, bitDepth: bd, path: imgPath)
                    }

                    let ratio: Double? = lossless ? nil : {
                        // Give OPJ the SAME compression ratio J2K achieved.
                        // Use actual bit depth for uncompressed size (not storage bytes).
                        // OPJ's -r flag computes target from the source bit depth,
                        // so for 12-bit data it uses 12 bits/pixel, not 16.
                        let uncompressedBits = w * h * comps * bd
                        let uncompressedBytes = (uncompressedBits + 7) / 8
                        return max(2.0, Double(uncompressedBytes) / Double(encoded.count))
                    }()

                    do {
                        let (oEncTime, oSize) = try opjEncode(
                            pgmPath: imgPath, j2kPath: opjJ2kPath,
                            compressionRatio: ratio, lossless: lossless)
                        opjEncTime = oEncTime
                        opjSize = oSize

                        let oDecTime = try opjDecode(j2kPath: opjJ2kPath, pgmPath: opjDecPath)
                        opjDecTime = oDecTime

                        // Read decoded image and compute metrics
                        if let decFileData = FileManager.default.contents(atPath: opjDecPath) {
                            if comps == 1 {
                                if let opjPx = parsePGMPixels(decFileData, expectedWidth: w, expectedHeight: h, bitDepth: bd) {
                                    opjPsnr = computePSNR(original: image.components[0].data, decoded: opjPx, bitDepth: bd)
                                    opjMae  = computeMAE(original: image.components[0].data, decoded: opjPx, bitDepth: bd)
                                }
                            } else {
                                if let opjComps = parsePPMPixels(decFileData, expectedWidth: w, expectedHeight: h, bitDepth: bd) {
                                    var oPsnrSum = 0.0, oMaeSum = 0.0
                                    let cCount = min(opjComps.count, image.components.count)
                                    for c in 0..<cCount {
                                        oPsnrSum += computePSNR(original: image.components[c].data, decoded: opjComps[c], bitDepth: bd)
                                        oMaeSum  += computeMAE(original: image.components[c].data, decoded: opjComps[c], bitDepth: bd)
                                    }
                                    opjPsnr = oPsnrSum / Double(cCount)
                                    opjMae  = oMaeSum / Double(cCount)
                                }
                            }
                        }

                        speedup = opjEncTime.map { $0 > 0 ? encTime / $0 : 0 }
                    } catch {
                        print("  OpenJPEG failed for \(label) \(modeLabel): \(error)")
                    }
                }

                let dSpeedup = opjDecTime.flatMap { odt -> Double? in
                    odt > 0 ? decTime / odt : nil
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
                    encSpeedup: speedup, decSpeedup: dSpeedup)

                results.append(result)

                let encSpdStr = speedup.map { String(format: "%.2fx", $0) } ?? "-"
                let decSpdStr = dSpeedup.map { String(format: "%.2fx", $0) } ?? "-"
                let psnrStr = psnr == .infinity ? "Inf" : String(format: "%.1f", psnr)
                let mpxEnc = Double(w * h) / 1_000_000.0 / encTime
                print("[\(label)] \(modeLabel): enc=\(String(format: "%.3f", encTime))s (\(String(format: "%.1f", mpxEnc)) MP/s) " +
                      "dec=\(String(format: "%.3f", decTime))s " +
                      "size=\(encoded.count) PSNR=\(psnrStr) MAE=\(String(format: "%.1f", mae)) " +
                      "enc_vs_opj=\(encSpdStr) dec_vs_opj=\(decSpdStr)")
            }
        }

        // --- Write CSV ---
        let csvHeader = "Image,Resolution,BitDepth,Mode," +
                        "J2K_EncTime_s,J2K_Enc_MP/s,J2K_DecTime_s,J2K_Dec_MP/s,J2K_Size_bytes,J2K_PSNR_dB,J2K_MAE," +
                        "OPJ_EncTime_s,OPJ_Enc_MP/s,OPJ_DecTime_s,OPJ_Dec_MP/s,OPJ_Size_bytes,OPJ_PSNR_dB,OPJ_MAE," +
                        "J2K/OPJ_Enc,J2K/OPJ_Dec"
        let csvBody = results.map { $0.csvLine }.joined(separator: "\n")
        let csv = csvHeader + "\n" + csvBody + "\n"
        try csv.write(toFile: "\(outputDir)/benchmark_results.csv", atomically: true, encoding: .utf8)
        print("\nResults written to \(outputDir)/benchmark_results.csv")

        // --- Assertions ---
        // IMPORTANT: Performance numbers are NOT meaningful for comparison.
        // - J2K: runs in-process in DEBUG mode (no optimizations, ~10× slower than release)
        // - OPJ: runs as release-compiled binary via Process() (includes ~60ms launch overhead)
        // Quality (PSNR/MAE) at same compression ratio IS the valid comparison.
        print("")
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║  ⚠️  PERFORMANCE NUMBERS ARE NOT COMPARABLE                     ║")
        print("║  J2K = in-process DEBUG mode (~10× slower than release)          ║")
        print("║  OPJ = release binary + 60ms process overhead per run            ║")
        print("║  Only QUALITY metrics (PSNR/MAE) are valid for comparison.       ║")
        print("╚══════════════════════════════════════════════════════════════════╝")
        print("")

        for r in results {
            // Lossless: absolute requirement for medical safety
            if r.mode == "lossless" {
                XCTAssertEqual(r.j2kMAE, 0, accuracy: 0.001,
                    "CRITICAL: \(r.label) lossless MUST have MAE=0 (medical safety)")
                XCTAssert(r.j2kPSNR.isInfinite,
                    "CRITICAL: \(r.label) lossless MUST have infinite PSNR")
            }

            if r.mode.contains("lossy") {
                // Minimum quality floor: 20 dB ensures visible content is preserved
                // Natural textured images at aggressive compression (q=0.2) reach ~24 dB
                XCTAssertGreaterThan(r.j2kPSNR, 20.0,
                    "\(r.label) \(r.mode) PSNR=\(String(format: "%.1f", r.j2kPSNR)) dB below 20 dB floor")

                // Medical images: stricter requirements
                if r.label.hasPrefix("Med") {
                    let maxVal = Double((1 << r.bitDepth) - 1)
                    let maePercent = r.j2kMAE / maxVal * 100.0
                    XCTAssertLessThan(maePercent, 1.0,
                        "MEDICAL: \(r.label) \(r.mode) MAE=\(String(format: "%.2f", r.j2kMAE)) " +
                        "(\(String(format: "%.4f", maePercent))%% of range) exceeds 1%% tolerance")
                    // 35 dB floor: aggressive compression (q=0.2, 0.5bpp) reaches ~38 dB
                    XCTAssertGreaterThan(r.j2kPSNR, 35.0,
                        "MEDICAL: \(r.label) \(r.mode) PSNR=\(String(format: "%.1f", r.j2kPSNR)) dB below 35 dB minimum")
                }
            }

            // Quality comparison vs OPJ at same compression ratio.
            // Now valid because OPJ encodes at J2K's actual ratio.
            // Skip trivial cases where both achieve Inf PSNR.
            if let opjP = r.opjPSNR, !r.mode.contains("lossless"),
               !opjP.isInfinite, !r.j2kPSNR.isInfinite {
                let gap = r.j2kPSNR - opjP
                XCTAssertGreaterThan(gap, -15.0,
                    "\(r.label) \(r.mode) quality gap vs OPJ: \(String(format: "%.1f", gap)) dB " +
                    "(J2K=\(String(format: "%.1f", r.j2kPSNR)), OPJ=\(String(format: "%.1f", opjP)))")
            }
        }

        // --- Rate control validation: file sizes must decrease with bpp ---
        for (label, _, _, _, _) in configs {
            let configResults = results.filter { $0.label == label }
            let bpp2   = configResults.first { $0.mode == "lossy-2bpp" }
            let bpp1   = configResults.first { $0.mode == "lossy-1bpp" }
            let bpp05  = configResults.first { $0.mode == "lossy-0.5bpp" }
            if let s2 = bpp2?.j2kFileSize, let s1 = bpp1?.j2kFileSize, let s05 = bpp05?.j2kFileSize {
                XCTAssertGreaterThan(s2, s1,
                    "RATE CONTROL: \(label) 2bpp size (\(s2)) should exceed 1bpp (\(s1))")
                XCTAssertGreaterThan(s1, s05,
                    "RATE CONTROL: \(label) 1bpp size (\(s1)) should exceed 0.5bpp (\(s05))")
            }
        }
    }

    // MARK: - Encode-only micro-benchmark (XCTest measure)

    func testEncodeSpeed512x512Lossy() throws {
        let image = generateNaturalImage(width: 512, height: 512, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        measure {
            _ = try? encoder.encode(image)
        }
    }

    func testEncodeSpeed1024x1024Lossy() throws {
        let image = generateNaturalImage(width: 1024, height: 1024, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        measure {
            _ = try? encoder.encode(image)
        }
    }

    func testEncodeSpeed512x512Lossless() throws {
        let image = generateNaturalImage(width: 512, height: 512, components: 1, bitDepth: 8)
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
        // PGM header: P5\n[# comment lines]\nW H\nMAXVAL\n<pixel data>
        // Must handle comment lines (OpenJPEG adds "# Created by ...")
        var headerEnd = 0
        var significantLines = 0  // non-comment lines: magic, dimensions, maxval
        var lineStart = 0

        for i in 0..<min(data.count, 1024) {
            if data[i] == 0x0A { // newline
                // Check if this line is a comment (starts with '#')
                if lineStart < data.count && data[lineStart] != 0x23 {
                    significantLines += 1
                }
                lineStart = i + 1
                if significantLines >= 3 {
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
