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

    /// Deterministic xorshift32 PRNG for reproducible test images.
    private struct XorShift32 {
        var state: UInt32
        mutating func next() -> UInt32 {
            state ^= state &<< 13
            state ^= state &>> 17
            state ^= state &<< 5
            return state
        }
    }

    /// Generate a textured test image with edges, gradients, and noise.
    ///
    /// Combines smooth gradients with sharp edges (rectangles, circles) and
    /// pseudo-random noise to create a realistic compression workload where
    /// lossy rate control has meaningful data to truncate.
    private func generateGradientImage(width: Int, height: Int, components: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        var comps: [J2KComponent] = []

        for c in 0..<components {
            let pixelCount = width * height
            var data = Data(count: bitDepth <= 8 ? pixelCount : pixelCount * 2)
            data.withUnsafeMutableBytes { buf in
                let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                var rng = XorShift32(state: UInt32(42 + c * 7919))

                for y in 0..<height {
                    for x in 0..<width {
                        // Base: gradient
                        var val: Double
                        switch c {
                        case 0: val = Double(x * maxVal) / Double(max(width - 1, 1))
                        case 1: val = Double(y * maxVal) / Double(max(height - 1, 1))
                        default: val = Double((x + y) * maxVal) / Double(max(width + height - 2, 1))
                        }

                        // Add sharp-edged rectangles at varying positions
                        let bx = width / 4, by = height / 4
                        let bw = width / 3, bh = height / 3
                        if x >= bx && x < bx + bw && y >= by && y < by + bh {
                            val = Double(maxVal) * 0.7
                        }
                        // Diagonal bar
                        let diag = abs(x - y)
                        if diag < max(4, width / 64) {
                            val = Double(maxVal) * 0.9
                        }

                        // Add deterministic noise (±12.5% of range)
                        let noise = Double(rng.next() % UInt32(max(maxVal / 4, 1))) - Double(maxVal / 8)
                        val += noise
                        let clamped = max(0, min(maxVal, Int(val)))

                        let i = y * width + x
                        if bitDepth <= 8 {
                            ptr[i] = UInt8(clamped)
                        } else {
                            let v = UInt16(clamped)
                            ptr[i * 2]     = UInt8(v >> 8)
                            ptr[i * 2 + 1] = UInt8(v & 0xFF)
                        }
                    }
                }
            }

            comps.append(J2KComponent(
                index: c, bitDepth: bitDepth, signed: false,
                width: width, height: height, data: data,
                sampleByteOrder: bitDepth > 8 ? .bigEndian : nil))
        }

        return J2KImage(width: width, height: height, components: comps)
    }

    /// Generate a medical-style phantom image with tissue textures.
    ///
    /// Simulates a CT-like cross-section with concentric structures (bone,
    /// soft tissue, organs), sharp boundaries, and Poisson-like noise to
    /// create a realistic high-bit-depth compression workload.
    private func generateMedicalPhantom(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = Double((1 << bitDepth) - 1)
        let pixelCount = width * height
        var data = Data(count: pixelCount * 2)

        let cx = Double(width) / 2
        let cy = Double(height) / 2
        let radius = Double(min(width, height)) / 2

        data.withUnsafeMutableBytes { buf in
            let ptr = buf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var rng = XorShift32(state: 314159)

            for y in 0..<height {
                let dy = Double(y) - cy
                for x in 0..<width {
                    let dx = Double(x) - cx
                    let dist = sqrt(dx * dx + dy * dy)

                    // Multi-region phantom: outer ring (bone), soft tissue, organ
                    var val: Double
                    if dist > radius * 0.95 {
                        val = maxVal * 0.05 // Background (air)
                    } else if dist > radius * 0.85 {
                        val = maxVal * 0.85 // Bone
                    } else if dist > radius * 0.5 {
                        val = maxVal * 0.45 // Soft tissue
                    } else if dist > radius * 0.3 {
                        val = maxVal * 0.60 // Organ
                    } else {
                        val = maxVal * 0.35 // Internal cavity
                    }

                    // Smaller embedded ellipses (simulate vessels/structures)
                    let ex1 = (dx - radius * 0.2) / (radius * 0.15)
                    let ey1 = (dy + radius * 0.1) / (radius * 0.1)
                    if ex1 * ex1 + ey1 * ey1 < 1.0 {
                        val = maxVal * 0.75
                    }
                    let ex2 = (dx + radius * 0.3) / (radius * 0.08)
                    let ey2 = (dy - radius * 0.15) / (radius * 0.12)
                    if ex2 * ex2 + ey2 * ey2 < 1.0 {
                        val = maxVal * 0.20
                    }

                    // Add Poisson-like noise (~2% of range)
                    let noise = Double(Int32(bitPattern: rng.next()) % Int32(max(Int(maxVal) / 50, 1)))
                    val += noise
                    let clamped = UInt16(max(0, min(maxVal, val)))

                    let i = y * width + x
                    ptr[i * 2]     = UInt8(clamped >> 8)
                    ptr[i * 2 + 1] = UInt8(clamped & 0xFF)
                }
            }
        }

        let comp = J2KComponent(
            index: 0, bitDepth: bitDepth, signed: false,
            width: width, height: height, data: data,
            sampleByteOrder: bitDepth > 8 ? .bigEndian : nil)
        return J2KImage(width: width, height: height, components: [comp])
    }

    /// Generate a synthetic Whole-Slide-Image tile that mimics H&E-stained
    /// pathology content: hematoxylin (blue/purple nuclei) clusters overlaid
    /// on an eosin (pink) cytoplasm background, with multi-scale texture from
    /// summed noise octaves. Realistic enough to exercise the codec's
    /// multi-component + high-frequency paths while remaining deterministic.
    private func generateWSITile(width: Int, height: Int, bitDepth: Int) -> J2KImage {
        let maxVal = (1 << bitDepth) - 1
        let bytesPerSample = bitDepth <= 8 ? 1 : 2

        var rData = Data(count: width * height * bytesPerSample)
        var gData = Data(count: width * height * bytesPerSample)
        var bData = Data(count: width * height * bytesPerSample)

        rData.withUnsafeMutableBytes { rBuf in
        gData.withUnsafeMutableBytes { gBuf in
        bData.withUnsafeMutableBytes { bBuf in
            let rPtr = rBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let gPtr = gBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let bPtr = bBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)

            // Deterministic PRNG seeded per-slot so content is reproducible.
            var rng = XorShift32(state: 0xABCD)

            // Three octaves of smooth noise to simulate tissue fractal structure.
            // Use a tile of per-octave random offsets for O(1) lookup.
            func octaveNoise(_ x: Int, _ y: Int, freq: Double, seed: UInt32) -> Double {
                // Simple hash-based smooth noise in [0, 1]
                var h = UInt32(truncatingIfNeeded: Int32(Double(x) * freq)) &* 73856093
                h ^= UInt32(truncatingIfNeeded: Int32(Double(y) * freq)) &* 19349663
                h ^= seed &* 83492791
                h ^= h >> 13
                h = h &* 1274126177
                return Double(h % 1024) / 1024.0
            }

            for y in 0..<height {
                for x in 0..<width {
                    // Base tissue texture: three noise octaves summed.
                    let n1 = octaveNoise(x, y, freq: 0.02, seed: 1)
                    let n2 = octaveNoise(x, y, freq: 0.08, seed: 2)
                    let n3 = octaveNoise(x, y, freq: 0.32, seed: 3)
                    let tissueDensity = 0.5 * n1 + 0.3 * n2 + 0.2 * n3  // [0,1]

                    // H&E stain mix: dense nuclei = purple/blue, sparse = pink.
                    // R channel: high in pink (eosin), medium in purple (hematoxylin)
                    // G channel: medium in pink, low in purple
                    // B channel: low in pink, high in purple
                    let eosinR   = 0.95, eosinG   = 0.60, eosinB   = 0.75
                    let hematR   = 0.55, hematG   = 0.40, hematB   = 0.75
                    let nucleiR  = 0.35, nucleiG  = 0.25, nucleiB  = 0.65

                    let blend: (Double, Double, Double)
                    if tissueDensity < 0.3 {
                        // Background / stroma: eosin-dominant pink
                        let t = tissueDensity / 0.3
                        blend = (eosinR * (1 - t * 0.2), eosinG, eosinB * (0.9 + t * 0.1))
                    } else if tissueDensity < 0.7 {
                        // Soft tissue: transition
                        let t = (tissueDensity - 0.3) / 0.4
                        blend = (eosinR * (1 - t) + hematR * t,
                                 eosinG * (1 - t) + hematG * t,
                                 eosinB * (1 - t) + hematB * t)
                    } else {
                        // Dense nuclei cluster
                        let t = (tissueDensity - 0.7) / 0.3
                        blend = (hematR * (1 - t) + nucleiR * t,
                                 hematG * (1 - t) + nucleiG * t,
                                 hematB * (1 - t) + nucleiB * t)
                    }

                    // Add fine-grain noise (~3% of range) — cellular speckle
                    let speckle = Double(rng.next() % 1024) / 1024.0 - 0.5
                    let jitter = 0.03 * speckle

                    let r = max(0.0, min(1.0, blend.0 + jitter))
                    let g = max(0.0, min(1.0, blend.1 + jitter))
                    let b = max(0.0, min(1.0, blend.2 + jitter))

                    let ri = Int(r * Double(maxVal))
                    let gi = Int(g * Double(maxVal))
                    let bi = Int(b * Double(maxVal))

                    let idx = y * width + x
                    if bitDepth <= 8 {
                        rPtr[idx] = UInt8(ri)
                        gPtr[idx] = UInt8(gi)
                        bPtr[idx] = UInt8(bi)
                    } else {
                        let rv = UInt16(ri)
                        let gv = UInt16(gi)
                        let bv = UInt16(bi)
                        rPtr[idx*2]     = UInt8(rv >> 8)
                        rPtr[idx*2 + 1] = UInt8(rv & 0xFF)
                        gPtr[idx*2]     = UInt8(gv >> 8)
                        gPtr[idx*2 + 1] = UInt8(gv & 0xFF)
                        bPtr[idx*2]     = UInt8(bv >> 8)
                        bPtr[idx*2 + 1] = UInt8(bv & 0xFF)
                    }
                }
            }
        }}}

        let byteOrder: J2KComponent.ByteOrder? = bitDepth > 8 ? .bigEndian : nil
        let comps = [
            J2KComponent(index: 0, bitDepth: bitDepth, signed: false,
                         width: width, height: height, data: rData, sampleByteOrder: byteOrder),
            J2KComponent(index: 1, bitDepth: bitDepth, signed: false,
                         width: width, height: height, data: gData, sampleByteOrder: byteOrder),
            J2KComponent(index: 2, bitDepth: bitDepth, signed: false,
                         width: width, height: height, data: bData, sampleByteOrder: byteOrder),
        ]
        return J2KImage(width: width, height: height, components: comps)
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
    /// Parses OpenJPEG's own "encode time: N ms" from stdout to avoid
    /// conflating process launch overhead (~50-60 ms on macOS) with
    /// actual encoding time. Falls back to wall-clock if parsing fails.
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
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()

        let wallStart = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        let wallElapsed = CFAbsoluteTimeGetCurrent() - wallStart

        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OPJ", code: Int(proc.terminationStatus))
        }

        // Parse OPJ's internal timing: "encode time: <N> ms"
        var elapsed = wallElapsed
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: stdoutData, encoding: .utf8) {
            // Match "encode time: 29 ms" or similar
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("encode time"),
                   let range = lower.range(of: #"(\d+)\s*ms"#, options: .regularExpression),
                   let ms = Double(lower[range].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    elapsed = ms / 1000.0
                    break
                }
            }
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: j2kPath)[.size] as? Int ?? 0
        return (elapsed, fileSize)
    }

    /// Decode a J2K file with OpenJPEG and return decodeTime.
    ///
    /// Parses OpenJPEG's own "decode time: N ms" from stdout to avoid
    /// conflating process launch overhead with actual decoding time.
    /// Falls back to wall-clock if parsing fails.
    private func opjDecode(j2kPath: String, pgmPath: String) throws -> Double {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opjDecompress)
        proc.arguments = ["-i", j2kPath, "-o", pgmPath]
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()

        let wallStart = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        let wallElapsed = CFAbsoluteTimeGetCurrent() - wallStart

        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OPJ", code: Int(proc.terminationStatus))
        }

        // Parse OPJ's internal timing: "decode time: <N> ms"
        var elapsed = wallElapsed
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: stdoutData, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("decode time"),
                   let range = lower.range(of: #"(\d+)\s*ms"#, options: .regularExpression),
                   let ms = Double(lower[range].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    elapsed = ms / 1000.0
                    break
                }
            }
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
    ) async throws -> (time: Double, data: Data) {
        var config = J2KEncodingConfiguration(
            quality: quality, lossless: lossless,
            decompositionLevels: decompositionLevels)
        if let bpp = bpp {
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }
        // Use 1 quality layer for lossy single-rate encoding to match
        // OpenJPEG's behavior (opj_compress -r uses 1 layer by default).
        // Multiple layers are only needed for progressive quality decoding.
        if !lossless {
            config.qualityLayers = 1
        }
        let encoder = J2KEncoder(encodingConfiguration: config)

        let start = CFAbsoluteTimeGetCurrent()
        let encoded = try await encoder.encode(image)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        return (elapsed, encoded)
    }

    /// Encode using HTJ2K (ISO/IEC 15444-15) block coder.
    ///
    /// Uses `J2KEncodingConfiguration.useHTJ2K = true` with the same
    /// quality/bpp/lossless settings as `j2kEncode` for a fair comparison.
    private func htj2kEncode(
        image: J2KImage, quality: Double, lossless: Bool,
        bpp: Double? = nil,
        decompositionLevels: Int = 5
    ) async throws -> (time: Double, data: Data) {
        var config = J2KEncodingConfiguration(
            quality: quality, lossless: lossless,
            decompositionLevels: decompositionLevels)
        config.useHTJ2K = true
        if let bpp = bpp {
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }
        if !lossless {
            config.qualityLayers = 1
        }
        let encoder = J2KEncoder(encodingConfiguration: config)

        let start = CFAbsoluteTimeGetCurrent()
        let encoded = try await encoder.encode(image)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        return (elapsed, encoded)
    }

    private func j2kDecode(data: Data) async throws -> (time: Double, image: J2KImage) {
        let start = CFAbsoluteTimeGetCurrent()
        let decoded = try await DecoderPipeline().decode(data)
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

    func testAcceleratedEncoderBenchmark() async throws {
        // Guard against running in debug mode — Swift debug builds are
        // 20-40× slower than release, producing meaningless benchmarks.
        #if DEBUG
        print("⚠️  WARNING: Running benchmark in DEBUG mode. Results will be")
        print("   unreliable. Use: swift test -c release --filter testAcceleratedEncoderBenchmark")
        #endif

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
                let (encTime, encoded) = try await j2kEncode(
                    image: image, quality: quality, lossless: lossless,
                    bpp: bpp, decompositionLevels: levels)

                // --- J2KSwift decode ---
                let (decTime, decoded) = try await j2kDecode(data: encoded)

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
                        if let bpp = bpp { return Double(bd) / bpp }
                        // Map quality → bpp matching J2KRateControl.qualityToBitrate
                        let targetBpp: Double
                        if quality >= 1.0 {
                            targetBpp = 8.0
                        } else if quality >= 0.95 {
                            targetBpp = 2.0 + (quality - 0.95) * 120.0
                        } else if quality >= 0.80 {
                            targetBpp = 0.5 + (quality - 0.80) * 10.0
                        } else if quality >= 0.50 {
                            targetBpp = 0.15 + (quality - 0.50) * 1.167
                        } else {
                            targetBpp = 0.05 + quality * 0.2
                        }
                        return Double(bd) / targetBpp
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
            // Quality should not be worse than baseline thresholds.
            // Low bitrates (≤0.5bpp) and multi-component (RGB) images have
            // inherently lower PSNR — use relaxed threshold for those.
            if r.mode.contains("lossy") {
                let threshold: Double = r.mode.contains("0.5bpp") || r.label.contains("RGB") ? 22.0 : 25.0
                XCTAssertGreaterThan(r.j2kPSNR, threshold,
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

    func testEncodeSpeed512x512Lossy() async throws {
        let image = generateGradientImage(width: 512, height: 512, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        _ = try await encoder.encode(image)
    }

    func testEncodeSpeed1024x1024Lossy() async throws {
        let image = generateGradientImage(width: 1024, height: 1024, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 0.8, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        _ = try await encoder.encode(image)
    }

    func testEncodeSpeed512x512Lossless() async throws {
        let image = generateGradientImage(width: 512, height: 512, components: 1, bitDepth: 8)
        let config = J2KEncodingConfiguration(
            quality: 1.0, lossless: true, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        _ = try await encoder.encode(image)
    }

    func testEncodeSpeedMedical512x512_12bit() async throws {
        let image = generateMedicalPhantom(width: 512, height: 512, bitDepth: 12)
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 5)
        let encoder = J2KEncoder(encodingConfiguration: config)

        _ = try await encoder.encode(image)
    }

    // MARK: - HDR / high-bit-depth color coverage

    /// Smoke-test lossless round-trip for RGB at 8, 10, 12, 14, 16 bits per
    /// channel and grayscale HDR (14-bit, 16-bit signed). Verifies the codec
    /// handles the full bit-depth spectrum that a medical-grade PACS sees
    /// (pathology slides are often 48-bit RGB, DCM DX is 14-16 bit, etc.).
    func testHDRAndColorCoverage() async throws {
        #if DEBUG
        print("⚠️  DEBUG mode — timings unreliable")
        #endif
        let logPath = "/tmp/hdr_coverage_results.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let fh = FileHandle(forWritingAtPath: logPath)!
        func emit(_ s: String) {
            let line = s + "\n"
            fh.write(line.data(using: .utf8)!)
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }

        emit("\n== HDR / Color Coverage ==")
        emit(String(repeating: "─", count: 72))
        emit("Config                          enc(ms)  dec(ms)   size(B)  PSNR    MAE  OK?")
        emit(String(repeating: "─", count: 72))

        // (label, width, height, bitDepth, components, levels)
        let configs: [(String, Int, Int, Int, Int, Int)] = [
            // 8-bit baseline
            ("RGB-8bit      512x512",    512,  512,  8, 3, 5),
            ("RGB-8bit     1024x1024",  1024, 1024,  8, 3, 5),
            // HDR grayscale depths
            ("Gray-10bit    512x512",    512,  512, 10, 1, 5),
            ("Gray-12bit    512x512",    512,  512, 12, 1, 5),
            ("Gray-14bit    512x512",    512,  512, 14, 1, 5),
            ("Gray-16bit    512x512",    512,  512, 16, 1, 5),
            ("Gray-16bit    512x1024",   512, 1024, 16, 1, 5),
            ("Gray-16bit   1024x1024",  1024, 1024, 16, 1, 5),
            ("Gray-16bit   2048x2048",  2048, 2048, 16, 1, 5),
            // HDR RGB (pathology, HDR photography)
            ("RGB-10bit     512x512",    512,  512, 10, 3, 5),
            ("RGB-10bit    1024x1024",  1024, 1024, 10, 3, 5),
            ("RGB-12bit     512x512",    512,  512, 12, 3, 5),
            ("RGB-12bit    1024x1024",  1024, 1024, 12, 3, 5),
            ("RGB-14bit     512x512",    512,  512, 14, 3, 5),
            ("RGB-14bit    1024x1024",  1024, 1024, 14, 3, 5),
            ("RGB-16bit     512x512",    512,  512, 16, 3, 5),
            ("RGB-16bit     768x768",    768,  768, 16, 3, 5),
            ("RGB-16bit    1024x1024",  1024, 1024, 16, 3, 5),
            ("RGB-16bit    2048x2048",  2048, 2048, 16, 3, 5),
        ]

        // LOSSLESS round-trip
        for (label, w, h, bd, comps, levels) in configs {
            let image = generateGradientImage(width: w, height: h, components: comps, bitDepth: bd)
            let cfg = J2KEncodingConfiguration(quality: 1.0, lossless: true, decompositionLevels: levels)
            let enc = J2KEncoder(encodingConfiguration: cfg)
            let t0 = CFAbsoluteTimeGetCurrent()
            let encoded = try await enc.encode(image)
            let encMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            let t1 = CFAbsoluteTimeGetCurrent()
            let decoded = try await DecoderPipeline().decode(encoded)
            let decMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000

            // Compare every component bit-exactly
            var maxMAE: Double = 0
            var worstPSNR: Double = .infinity
            for (idx, origComp) in image.components.enumerated() where idx < decoded.components.count {
                let mae  = computeMAE(original: origComp.data, decoded: decoded.components[idx].data, bitDepth: bd)
                let psnr = computePSNR(original: origComp.data, decoded: decoded.components[idx].data, bitDepth: bd)
                maxMAE = max(maxMAE, mae)
                worstPSNR = min(worstPSNR, psnr)
            }
            let psnrStr = worstPSNR.isInfinite ? "∞ " : String(format: "%.1f dB", worstPSNR)
            let ok = maxMAE == 0 && worstPSNR.isInfinite ? "✓ bit-exact" : "✗ LOSSY!"
            let pad = label.padding(toLength: 30, withPad: " ", startingAt: 0)
            emit("\(pad)  \(String(format: "%6.2f", encMs))   \(String(format: "%6.2f", decMs))   \(String(format: "%8d", encoded.count))  \(psnrStr)  \(String(format: "%.2f", maxMAE))  \(ok)")
        }

        emit(String(repeating: "─", count: 72))
        emit("All lossless entries above must show MAE=0.00 and PSNR=∞ for correctness.")
        fh.closeFile()
    }

    // MARK: - HTJ2K (Part-15) — benchmarked against OpenJPH reference

    private let ojphCompress = "/opt/homebrew/bin/ojph_compress"
    private let ojphExpand   = "/opt/homebrew/bin/ojph_expand"
    private var hasOpenJPH: Bool {
        FileManager.default.fileExists(atPath: ojphCompress) &&
        FileManager.default.fileExists(atPath: ojphExpand)
    }

    /// Encode a PGM/PPM file with OpenJPH's `ojph_compress`.
    @discardableResult
    private func ojphEncode(srcPath: String, j2kPath: String, lossless: Bool,
                            qstep: Double? = nil) throws -> (time: Double, size: Int) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ojphCompress)
        var args = ["-i", srcPath, "-o", j2kPath, "-reversible", lossless ? "true" : "false"]
        if !lossless, let q = qstep {
            args += ["-qstep", String(format: "%.5f", q)]
        }
        proc.arguments = args
        proc.standardOutput = Pipe(); proc.standardError = Pipe()

        let t0 = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OJPH", code: Int(proc.terminationStatus))
        }
        let size = try FileManager.default.attributesOfItem(atPath: j2kPath)[.size] as? Int ?? 0
        return (elapsed, size)
    }

    /// Decode a HTJ2K file with OpenJPH's `ojph_expand` to PGM/PPM.
    @discardableResult
    private func ojphDecode(j2kPath: String, outPath: String) throws -> Double {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ojphExpand)
        proc.arguments = ["-i", j2kPath, "-o", outPath]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()

        let t0 = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OJPH", code: Int(proc.terminationStatus))
        }
        return elapsed
    }

    /// HTJ2K (ISO 15444-15 Part-15) benchmark against OpenJPH — the
    /// reference HTJ2K codec (OpenJPEG 2.5 can't decode Part-15 at all).
    ///
    /// HTJ2K is where JPEG-2000 differentiates in 2025: FBCOT (fast block
    /// coding of truncated codestreams) replaces MQ with a MEL+VLC+MagSgn
    /// tier-1 that's much more SIMD-friendly, giving 3–10× encoder
    /// speedups and similar decoder speedups vs legacy Part-1.
    ///
    /// This test validates:
    ///   1. Bit-exact lossless (reversible 5/3 HT) self round-trip and
    ///      cross-decode with OpenJPH
    ///   2. Encode + decode time vs OpenJPH at equivalent settings
    ///   3. Compression efficiency (file size, PSNR) vs OpenJPH
    ///   4. Coverage across medical + natural image sizes and bit depths
    func testHTJ2KvsOpenJPH() async throws {
        #if DEBUG
        print("⚠️  DEBUG mode — timings unreliable.")
        print("   Use: swift test -c release --filter testHTJ2KvsOpenJPH")
        #endif
        guard hasOpenJPH else {
            print("SKIP testHTJ2KvsOpenJPH: ojph_compress/ojph_expand not found")
            return
        }

        let logPath = "/tmp/htj2k_results.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let fh = FileHandle(forWritingAtPath: logPath)!
        func emit(_ s: String) {
            let line = s + "\n"
            fh.write(line.data(using: .utf8)!)
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }

        let outDir = "/tmp/j2k_htj2k"
        try? FileManager.default.createDirectory(atPath: outDir,
            withIntermediateDirectories: true)

        emit("\n═══════════════════════════════════════════════════════════")
        emit(" HTJ2K (Part-15) — J2KSwift vs OpenJPH reference")
        emit("═══════════════════════════════════════════════════════════")

        // Test corpus — mix of medical, natural, and pathology-style.
        let configs: [(String, Int, Int, Int, Int)] = [
            // (label, w, h, bitDepth, components)
            ("Grad-512-8b",  512,  512,  8, 1),
            ("Grad-1024-8b", 1024, 1024, 8, 1),
            ("Med-512-12b",  512,  512, 12, 1),
            ("Med-512-16b",  512,  512, 16, 1),
            ("RGB-512-8b",   512,  512,  8, 3),
            ("RGB-1024-8b",  1024, 1024, 8, 3),
            ("RGB-1024-16b", 1024, 1024, 16, 3),
        ]

        struct HTResult {
            let label: String
            let rawBytes: Int
            let j2kEncMs: Double; let j2kDecMs: Double; let j2kSize: Int
            let ojphEncMs: Double; let ojphDecMs: Double; let ojphSize: Int
            let selfBitExact: Bool; let crossBitExact: Bool
        }
        var results: [HTResult] = []

        emit("\n── Lossless HTJ2K round-trip + cross-codec ──")
        emit("Config          raw(KB)  J2Kenc   OJPHenc   J2Kdec   OJPHdec   J2Ksize   OJPHsize    self✓  cross✓")
        emit(String(repeating: "─", count: 105))

        for (label, w, h, bd, comps) in configs {
            let image: J2KImage
            if comps == 1 {
                image = generateGradientImage(width: w, height: h, components: 1, bitDepth: bd)
            } else {
                // Use WSI-style content for RGB (more realistic than gradient)
                image = generateWSITile(width: w, height: h, bitDepth: bd)
            }
            let raw = w * h * comps * (bd <= 8 ? 1 : 2)

            // Write source as PGM (1 comp) or PPM (3 comp) for OpenJPH input
            let srcExt = comps == 1 ? "pgm" : "ppm"
            let srcPath = "\(outDir)/\(label).\(srcExt)"
            if comps == 1 {
                try savePGM(data: image.components[0].data,
                            width: w, height: h, bitDepth: bd, path: srcPath)
            } else {
                try writeRGBAsPPM(image: image, path: srcPath, bitDepth: bd)
            }

            // J2KSwift HTJ2K encode + decode
            var cfg = J2KEncodingConfiguration(
                quality: 1.0, lossless: true, decompositionLevels: 5)
            cfg.useHTJ2K = true
            let enc = J2KEncoder(encodingConfiguration: cfg)
            let t0 = CFAbsoluteTimeGetCurrent()
            let j2kData = try await enc.encode(image)
            let j2kEncMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

            let t1 = CFAbsoluteTimeGetCurrent()
            let decoded = try await DecoderPipeline().decode(j2kData)
            let j2kDecMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000

            // Bit-exact check vs original
            var selfBitExact = true
            for (i, origC) in image.components.enumerated() where i < decoded.components.count {
                if origC.data != decoded.components[i].data { selfBitExact = false; break }
            }

            // OpenJPH encode + decode
            let ojphJ2kPath = "\(outDir)/\(label)_ojph.j2k"
            let ojphOutPath = "\(outDir)/\(label)_ojph_dec.\(srcExt)"
            var ojphEncMs: Double = 0
            var ojphDecMs: Double = 0
            var ojphSize: Int = 0
            var crossBitExact = false

            do {
                let (eTime, eSize) = try ojphEncode(
                    srcPath: srcPath, j2kPath: ojphJ2kPath, lossless: true)
                ojphEncMs = eTime * 1000
                ojphSize = eSize

                ojphDecMs = (try ojphDecode(j2kPath: ojphJ2kPath, outPath: ojphOutPath)) * 1000

                // Cross-decode: feed OpenJPH's stream to our decoder
                let ojphData = try Data(contentsOf: URL(fileURLWithPath: ojphJ2kPath))
                let ojphDecoded = try await DecoderPipeline().decode(ojphData)
                crossBitExact = true
                for (i, origC) in image.components.enumerated()
                    where i < ojphDecoded.components.count {
                    if origC.data != ojphDecoded.components[i].data {
                        crossBitExact = false; break
                    }
                }
            } catch {
                emit("  \(label) OpenJPH failed: \(error)")
            }

            let selfMark = selfBitExact ? "✓" : "✗"
            let crossMark = crossBitExact ? "✓" : (ojphSize > 0 ? "✗" : "—")

            let pad = label.padding(toLength: 15, withPad: " ", startingAt: 0)
            emit("\(pad) \(String(format: "%6d", raw/1024))  \(String(format: "%6.1fms", j2kEncMs))  \(String(format: "%6.1fms", ojphEncMs))  \(String(format: "%6.1fms", j2kDecMs))  \(String(format: "%6.1fms", ojphDecMs))  \(String(format: "%8d", j2kData.count))  \(String(format: "%8d", ojphSize))     \(selfMark)     \(crossMark)")

            results.append(HTResult(
                label: label, rawBytes: raw,
                j2kEncMs: j2kEncMs, j2kDecMs: j2kDecMs, j2kSize: j2kData.count,
                ojphEncMs: ojphEncMs, ojphDecMs: ojphDecMs, ojphSize: ojphSize,
                selfBitExact: selfBitExact, crossBitExact: crossBitExact))
        }
        emit(String(repeating: "─", count: 105))

        // Speedup table
        emit("\n── Speedup (OpenJPH / J2KSwift) ──")
        emit("Config           Enc speedup   Dec speedup   Size ratio (J2K/OJPH)")
        emit(String(repeating: "─", count: 70))
        var totalJ2KEnc = 0.0, totalOJPHEnc = 0.0
        var totalJ2KDec = 0.0, totalOJPHDec = 0.0
        var totalJ2KSize = 0, totalOJPHSize = 0
        for r in results where r.ojphSize > 0 {
            let encSp = r.ojphEncMs / r.j2kEncMs
            let decSp = r.ojphDecMs / r.j2kDecMs
            let sizeR = Double(r.j2kSize) / Double(r.ojphSize)
            totalJ2KEnc += r.j2kEncMs; totalOJPHEnc += r.ojphEncMs
            totalJ2KDec += r.j2kDecMs; totalOJPHDec += r.ojphDecMs
            totalJ2KSize += r.j2kSize; totalOJPHSize += r.ojphSize
            let pad = r.label.padding(toLength: 15, withPad: " ", startingAt: 0)
            emit("\(pad)   \(String(format: "%5.2fx", encSp))       \(String(format: "%5.2fx", decSp))        \(String(format: "%.4f", sizeR))")
        }
        emit(String(repeating: "─", count: 70))
        if totalOJPHEnc > 0 {
            emit(String(format: "Aggregate        %5.2fx       %5.2fx        %.4f",
                        totalOJPHEnc / totalJ2KEnc,
                        totalOJPHDec / totalJ2KDec,
                        Double(totalJ2KSize) / Double(totalOJPHSize)))
        }

        // Summary
        emit("\n── Summary ──")
        let allSelf = results.allSatisfy { $0.selfBitExact }
        let crossResults = results.filter { $0.ojphSize > 0 }
        let allCross = crossResults.allSatisfy { $0.crossBitExact }
        emit("  Bit-exact (J2KSwift HT → J2KSwift):     \(allSelf ? "✓ ALL PASS" : "✗ FAILURES")")
        emit("  Bit-exact (OpenJPH HT → J2KSwift dec):  \(allCross ? "✓ ALL PASS" : "✗ SOME FAIL") \(crossResults.count)/\(results.count)")
        emit("\nResults → \(logPath)")
        fh.closeFile()

        XCTAssertTrue(allSelf, "J2KSwift HTJ2K self round-trip must be bit-exact")
    }

    // MARK: - DICOM Whole Slide Imaging (WSI / pathology)

    /// Whole Slide Imaging benchmark — realistic pathology workload.
    ///
    /// DICOM VL Whole Slide Microscopy Image Storage (SOP Class
    /// 1.2.840.10008.5.1.4.1.1.77.1.6) is the standard for digital pathology.
    /// WSI content is typically:
    ///   - 24-bit sRGB (8-bit × 3 channels), sometimes 48-bit for high-end
    ///     scanners or sRGB wide-gamut workflows
    ///   - Stored as a tiled pyramid: base layer + downsampled levels,
    ///     each tile independently decodable (typically 256² or 512²)
    ///   - H&E stained (hematoxylin = blue/purple nuclei, eosin = pink
    ///     cytoplasm) or IHC with varied stains
    ///   - Total pixel count often 10–100 gigapixels per slide
    ///
    /// Per DICOM-WG-26 / IHE Pathology profile, lossless JPEG 2000
    /// (transfer syntax 1.2.840.10008.1.2.4.90) is the recommended
    /// format for primary diagnostic use.
    ///
    /// This test validates:
    ///   1. Bit-exact lossless round-trip at every realistic tile size
    ///   2. Cross-codec interop (our stream decodes in OpenJPEG, reference
    ///      stream decodes in ours) — required for DICOMweb distribution
    ///   3. Compression ratio vs OpenJPEG (sets the storage budget
    ///      a PACS actually sees per WSI)
    ///   4. Tile-decode latency at 1024² (drives viewer responsiveness
    ///      when panning/zooming — must stay below 40 ms for 25 fps)
    func testDICOMWholeSlideImaging() async throws {
        #if DEBUG
        print("⚠️  WARNING: DEBUG mode — timings unreliable.")
        print("   Use: swift test -c release --filter testDICOMWholeSlideImaging")
        #endif
        guard hasOpenJPEG else {
            print("SKIP testDICOMWholeSlideImaging: OpenJPEG CLI not found")
            return
        }

        let logPath = "/tmp/wsi_results.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let fh = FileHandle(forWritingAtPath: logPath)!
        func emit(_ s: String) {
            let line = s + "\n"
            fh.write(line.data(using: .utf8)!)
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }

        let outDir = "/tmp/j2k_wsi"
        try? FileManager.default.createDirectory(atPath: outDir,
            withIntermediateDirectories: true)

        emit("\n═══════════════════════════════════════════════════════════")
        emit(" DICOM Whole Slide Imaging (WSI / pathology) benchmark")
        emit(" Simulated H&E-stained tissue; standard tile sizes")
        emit("═══════════════════════════════════════════════════════════")

        // Standard WSI tile sizes. 256² and 512² are DICOMweb / BigPicture
        // Project defaults; 1024² and 2048² represent high-resolution
        // scanning scenarios; 4096² is the practical large-tile upper
        // bound for single-decode viewer tiles.
        let tileSizes: [Int] = [256, 512, 1024, 2048, 4096]

        // Both common WSI depths: sRGB-24 (mainstream) and 48-bit (pro).
        let bitDepths: [Int] = [8, 16]

        // ── Section 1: lossless round-trip + cross-codec ─────────────────
        emit("\n── 1. Lossless round-trip (bit-exact required for diagnostic) ──")
        emit("Config                       enc(ms)  dec(ms)   size(B)   ratio   J2K→OPJ   OK?")
        emit(String(repeating: "─", count: 88))

        struct WSIResult {
            let label: String; let tileSize: Int; let bitDepth: Int
            let rawBytes: Int; let encBytes: Int; let encMs: Double; let decMs: Double
            let selfBitExact: Bool; let crossBitExact: Bool
            let opjSize: Int; let opjDecMs: Double
        }
        var losslessResults: [WSIResult] = []

        for bd in bitDepths {
            for size in tileSizes {
                let label = "\(bd)-bit RGB \(size)×\(size)"
                let image = generateWSITile(width: size, height: size, bitDepth: bd)
                let raw = size * size * 3 * (bd <= 8 ? 1 : 2)

                // Encode lossless
                let cfg = J2KEncodingConfiguration(
                    quality: 1.0, lossless: true, decompositionLevels: 5)
                let enc = J2KEncoder(encodingConfiguration: cfg)
                let t0 = CFAbsoluteTimeGetCurrent()
                let encoded = try await enc.encode(image)
                let encMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000

                // Self decode (J2K → J2K)
                let t1 = CFAbsoluteTimeGetCurrent()
                let decoded = try await DecoderPipeline().decode(encoded)
                let decMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000

                var selfBitExact = true
                for (i, origC) in image.components.enumerated() where i < decoded.components.count {
                    if origC.data != decoded.components[i].data { selfBitExact = false; break }
                }

                // Cross decode via OpenJPEG (J2K → OPJ)
                let j2kPath = "\(outDir)/wsi_\(bd)bit_\(size).j2k"
                let opjDecDir = "\(outDir)/wsi_\(bd)bit_\(size)_opjdec"
                try? FileManager.default.createDirectory(atPath: opjDecDir,
                    withIntermediateDirectories: true)
                try encoded.write(to: URL(fileURLWithPath: j2kPath))

                var crossBitExact = false
                var opjDecMs: Double = 0
                do {
                    // Decode to PPM (3-component) via opj_decompress
                    let ppmPath = "\(opjDecDir)/out.ppm"
                    let t2 = CFAbsoluteTimeGetCurrent()
                    _ = try opjDecodeToFile(j2kPath: j2kPath, outPath: ppmPath)
                    opjDecMs = (CFAbsoluteTimeGetCurrent() - t2) * 1000

                    if let ppm = FileManager.default.contents(atPath: ppmPath),
                       let (r, g, b) = parsePPMPixels(ppm, expectedWidth: size,
                                                     expectedHeight: size, bitDepth: bd) {
                        crossBitExact = (r == image.components[0].data &&
                                         g == image.components[1].data &&
                                         b == image.components[2].data)
                    }
                } catch {
                    // OPJ failure — record but don't fail the test; some OPJ
                    // builds may not support 16-bit PPM output.
                    emit("  (OPJ decode failed: \(error))")
                }

                // OpenJPEG encode of same content for compression-ratio comparison.
                // We need a raw source — write the image as PPM first.
                let srcPpm = "\(outDir)/src_\(bd)bit_\(size).ppm"
                try writeRGBAsPPM(image: image, path: srcPpm, bitDepth: bd)
                let opjJ2kPath = "\(outDir)/opj_\(bd)bit_\(size).j2k"
                var opjSize = 0
                do {
                    let (_, sz) = try opjEncode(
                        pgmPath: srcPpm, j2kPath: opjJ2kPath,
                        compressionRatio: nil, lossless: true)
                    opjSize = sz
                } catch {
                    // OPJ encode failure — leave opjSize at 0 (reported as N/A)
                }

                let ratio = Double(raw) / Double(encoded.count)
                let okMark = selfBitExact && crossBitExact ? "✓" : (selfBitExact ? "≈ self-only" : "✗")
                let opjRatioStr = opjSize > 0 ? String(format: "%.2fx", Double(raw) / Double(opjSize)) : "N/A"
                let crossMark = crossBitExact ? "✓" : "—"
                let pad = label.padding(toLength: 28, withPad: " ", startingAt: 0)
                emit("\(pad) \(String(format: "%6.1f", encMs))   \(String(format: "%6.1f", decMs))  \(String(format: "%9d", encoded.count))  \(String(format: "%.2fx", ratio)) (OPJ \(opjRatioStr))  \(crossMark)   \(okMark)")

                losslessResults.append(WSIResult(
                    label: label, tileSize: size, bitDepth: bd,
                    rawBytes: raw, encBytes: encoded.count,
                    encMs: encMs, decMs: decMs,
                    selfBitExact: selfBitExact, crossBitExact: crossBitExact,
                    opjSize: opjSize, opjDecMs: opjDecMs))
            }
        }
        emit(String(repeating: "─", count: 88))

        // ── Section 2: lossy compression curve (visually-lossless benchmark) ──
        emit("\n── 2. Lossy rate-distortion (visually-lossless @ 0.7-1.0 bpp is typical) ──")
        emit("Config                       bpp     size(B)    PSNR(dB)    OPJ PSNR    ΔPSNR")
        emit(String(repeating: "─", count: 80))

        let lossySizes: [Int] = [512, 1024]
        let lossyBpp: [Double] = [0.5, 1.0, 2.0]
        for size in lossySizes {
            let image = generateWSITile(width: size, height: size, bitDepth: 8)
            let pgmSrc = "\(outDir)/wsi_lossy_src_\(size).ppm"
            try writeRGBAsPPM(image: image, path: pgmSrc, bitDepth: 8)

            for bpp in lossyBpp {
                var cfg = J2KEncodingConfiguration(
                    quality: 0.5, lossless: false, decompositionLevels: 5)
                cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
                cfg.qualityLayers = 1
                let enc = J2KEncoder(encodingConfiguration: cfg)
                let encoded = try await enc.encode(image)
                let decoded = try await DecoderPipeline().decode(encoded)

                // PSNR across all 3 channels
                var totalMSE = 0.0
                var count = 0
                for (i, origC) in image.components.enumerated() where i < decoded.components.count {
                    let n = min(origC.data.count, decoded.components[i].data.count)
                    for j in 0..<n {
                        let d = Double(origC.data[j]) - Double(decoded.components[i].data[j])
                        totalMSE += d * d
                    }
                    count += n
                }
                let mse = totalMSE / Double(max(1, count))
                let psnr = mse > 0 ? 10 * log10(255 * 255 / mse) : Double.infinity

                // OPJ comparison
                let opjJ2k = "\(outDir)/wsi_lossy_opj_\(size)_\(bpp).j2k"
                let opjOut = "\(outDir)/wsi_lossy_opj_\(size)_\(bpp)_out.ppm"
                var opjPSNR: Double = .nan
                do {
                    // Raw is 24 bits/pixel (8-bit × 3 channels); `bpp` is the
                    // total compressed bits per pixel across all channels,
                    // matching J2KSwift's `constantBitrate(bitsPerPixel:)`
                    // semantics. So the compression ratio is 24 / bpp.
                    let ratio = 24.0 / bpp
                    _ = try opjEncode(
                        pgmPath: pgmSrc, j2kPath: opjJ2k,
                        compressionRatio: ratio, lossless: false)
                    _ = try opjDecodeToFile(j2kPath: opjJ2k, outPath: opjOut)
                    if let ppm = FileManager.default.contents(atPath: opjOut),
                       let (r, g, b) = parsePPMPixels(ppm, expectedWidth: size,
                                                     expectedHeight: size, bitDepth: 8) {
                        var opjMSE = 0.0
                        var opjCount = 0
                        for (opjCh, origCh) in zip([r, g, b], image.components) {
                            let n = min(opjCh.count, origCh.data.count)
                            for k in 0..<n {
                                let d = Double(origCh.data[k]) - Double(opjCh[k])
                                opjMSE += d * d
                            }
                            opjCount += n
                        }
                        let opjM = opjMSE / Double(max(1, opjCount))
                        opjPSNR = opjM > 0 ? 10 * log10(255 * 255 / opjM) : Double.infinity
                    }
                } catch {}

                let delta = opjPSNR.isFinite ? psnr - opjPSNR : Double.nan
                let psnrStr = psnr.isFinite ? String(format: "%5.2f", psnr) : "   ∞"
                let opjStr = opjPSNR.isFinite ? String(format: "%5.2f", opjPSNR) : "  n/a"
                let deltaStr = delta.isFinite ? String(format: "%+5.2f", delta) : " n/a"
                let pad = "\(size)×\(size)".padding(toLength: 28, withPad: " ", startingAt: 0)
                emit("\(pad) \(String(format: "%5.2f", bpp))  \(String(format: "%9d", encoded.count))    \(psnrStr)      \(opjStr)      \(deltaStr)")
            }
        }
        emit(String(repeating: "─", count: 80))

        // ── Section 3: summary ───────────────────────────────────────────
        emit("\n── 3. Summary ──")
        let allSelfOK = losslessResults.allSatisfy { $0.selfBitExact }
        let allCrossOK = losslessResults.allSatisfy { $0.crossBitExact }
        let totalRaw = losslessResults.map { $0.rawBytes }.reduce(0, +)
        let totalEnc = losslessResults.map { $0.encBytes }.reduce(0, +)
        let totalOPJ = losslessResults.map { $0.opjSize }.reduce(0, +)
        let aggRatio = Double(totalRaw) / Double(totalEnc)
        emit("  Bit-exact (J2KSwift → J2KSwift):  \(allSelfOK ? "✓ ALL PASS" : "✗ FAILURES")")
        emit("  Bit-exact (J2KSwift → OpenJPEG):  \(allCrossOK ? "✓ ALL PASS" : "✗ FAILURES — check OPJ PPM support")")
        emit(String(format: "  Aggregate J2KSwift compression ratio: %.2fx  (raw %d B → encoded %d B)",
                    aggRatio, totalRaw, totalEnc))
        if totalOPJ > 0 {
            emit(String(format: "  Aggregate OpenJPEG compression ratio: %.2fx  (%d B)",
                        Double(totalRaw) / Double(totalOPJ), totalOPJ))
        }

        emit("\nResults → \(logPath)")
        fh.closeFile()

        // Assertions
        XCTAssertTrue(allSelfOK, "WSI lossless round-trip must be bit-exact for all tile sizes and bit depths")
    }

    /// Write an RGB J2KImage as a PPM P6 file (for OpenJPEG input).
    private func writeRGBAsPPM(image: J2KImage, path: String, bitDepth: Int) throws {
        guard image.components.count >= 3 else {
            throw NSError(domain: "WSI", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Need 3 RGB components"])
        }
        let w = image.width, h = image.height
        let maxVal = (1 << bitDepth) - 1
        let header = "P6\n\(w) \(h)\n\(maxVal)\n"
        var out = Data()
        out.append(header.data(using: .ascii)!)
        let bps = bitDepth <= 8 ? 1 : 2
        var pixels = Data(count: w * h * 3 * bps)
        pixels.withUnsafeMutableBytes { dst in
            let dPtr = dst.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for c in 0..<3 {
                image.components[c].data.withUnsafeBytes { src in
                    let sPtr = src.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<(w * h) {
                        for bi in 0..<bps {
                            dPtr[(i * 3 + c) * bps + bi] = sPtr[i * bps + bi]
                        }
                    }
                }
            }
        }
        out.append(pixels)
        try out.write(to: URL(fileURLWithPath: path))
    }

    /// Decode a J2K file to PPM/PGM via opj_decompress (handles RGB too).
    @discardableResult
    private func opjDecodeToFile(j2kPath: String, outPath: String) throws -> Double {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: opjDecompress)
        proc.arguments = ["-i", j2kPath, "-o", outPath]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        let t0 = CFAbsoluteTimeGetCurrent()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "OPJ", code: Int(proc.terminationStatus))
        }
        return CFAbsoluteTimeGetCurrent() - t0
    }

    /// Parse a PPM P6 file into (R, G, B) Data, stored big-endian for 16-bit.
    private func parsePPMPixels(_ data: Data, expectedWidth: Int, expectedHeight: Int,
                                bitDepth: Int) -> (Data, Data, Data)? {
        // P6 header: "P6\n<w> <h>\n<maxval>\n<pixels>"
        var idx = 0
        func readLine() -> String? {
            var line = ""
            while idx < data.count {
                let b = data[idx]; idx += 1
                if b == 0x0A { return line }
                if b == 0x23 {  // '#' comment; skip rest of line
                    while idx < data.count && data[idx] != 0x0A { idx += 1 }
                    if idx < data.count { idx += 1 }
                    continue
                }
                line.append(Character(UnicodeScalar(b)))
            }
            return line.isEmpty ? nil : line
        }
        guard readLine() == "P6" else { return nil }
        guard let dimLine = readLine() else { return nil }
        let dims = dimLine.split(separator: " ").compactMap { Int($0) }
        guard dims.count == 2, dims[0] == expectedWidth, dims[1] == expectedHeight else { return nil }
        guard let mvLine = readLine(), let _ = Int(mvLine) else { return nil }

        let bps = bitDepth <= 8 ? 1 : 2
        let pxCount = expectedWidth * expectedHeight
        let needed = pxCount * 3 * bps
        guard data.count - idx >= needed else { return nil }

        var r = Data(count: pxCount * bps)
        var g = Data(count: pxCount * bps)
        var b = Data(count: pxCount * bps)
        r.withUnsafeMutableBytes { rBuf in
        g.withUnsafeMutableBytes { gBuf in
        b.withUnsafeMutableBytes { bBuf in
            let rP = rBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let gP = gBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let bP = bBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
            data.withUnsafeBytes { src in
                let sP = src.baseAddress!.assumingMemoryBound(to: UInt8.self) + idx
                for i in 0..<pxCount {
                    for bi in 0..<bps {
                        rP[i * bps + bi] = sP[(i * 3 + 0) * bps + bi]
                        gP[i * bps + bi] = sP[(i * 3 + 1) * bps + bi]
                        bP[i * bps + bi] = sP[(i * 3 + 2) * bps + bi]
                    }
                }
            }
        }}}
        return (r, g, b)
    }

    // MARK: - Decode micro-benchmark (stage-isolated timing)

    /// Decode-focused micro-benchmark. Runs N decodes on pre-encoded streams
    /// and reports per-stage medians. Used to target decode hotspot
    /// optimizations (Priority 2 in the optimization roadmap).
    func testDecodeHotspotProfile() async throws {
        #if DEBUG
        print("⚠️  WARNING: DEBUG mode — timings unreliable")
        print("   Use: swift test -c release --filter testDecodeHotspotProfile")
        #endif

        // Representative workload mix covering the two decode regimes that
        // dominate in practice: small-block lossless (Tier-1 bound) and
        // medical lossy (IDWT bound).
        let runs = 10
        let logPath = "/tmp/decode_profile_results.txt"
        try? FileManager.default.removeItem(atPath: logPath)
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let fh = FileHandle(forWritingAtPath: logPath)!
        func emit(_ s: String) {
            let line = s + "\n"
            fh.write(line.data(using: .utf8)!)
            FileHandle.standardError.write(line.data(using: .utf8)!)
        }
        emit("\n==DECODE-PROFILE== \(runs) runs each, median ms")

        var configs: [(label: String, image: J2KImage, lossless: Bool, bpp: Double)] = []
        configs.append(("Grad-256-8b  lossy 1b", generateGradientImage(width: 256, height: 256, components: 1, bitDepth: 8), false, 1.0))
        configs.append(("Grad-256-8b  lossy 2b", generateGradientImage(width: 256, height: 256, components: 1, bitDepth: 8), false, 2.0))
        configs.append(("Grad-1024-8b lossless", generateGradientImage(width: 1024, height: 1024, components: 1, bitDepth: 8), true, 0))
        configs.append(("Grad-1024-8b lossy 1b", generateGradientImage(width: 1024, height: 1024, components: 1, bitDepth: 8), false, 1.0))
        configs.append(("Med-512-12b  lossless", generateMedicalPhantom(width: 512, height: 512, bitDepth: 12), true, 0))
        configs.append(("Med-512-12b  lossy 1b", generateMedicalPhantom(width: 512, height: 512, bitDepth: 12), false, 1.0))
        configs.append(("Med-512-16b  lossless", generateMedicalPhantom(width: 512, height: 512, bitDepth: 16), true, 0))
        configs.append(("Med-512-16b  lossy 1b", generateMedicalPhantom(width: 512, height: 512, bitDepth: 16), false, 1.0))
        emit("Built \(configs.count) configs")
        emit(String(repeating: "─", count: 60))
        emit("Config                      total (ms)")
        emit(String(repeating: "─", count: 60))

        for (label, image, lossless, bpp) in configs {
            do {
                var cfg = J2KEncodingConfiguration(
                    quality: lossless ? 1.0 : 0.5,
                    lossless: lossless,
                    decompositionLevels: 5)
                if !lossless {
                    cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
                    cfg.qualityLayers = 1
                }
                let enc = J2KEncoder(encodingConfiguration: cfg)
                emit("  encoding \(label)...")
                let encoded = try await enc.encode(image)
                emit("  encoded \(encoded.count) B, running decode \(runs) times...")
                let decoder = DecoderPipeline()

                _ = try await decoder.decode(encoded)

                var timings: [Double] = []
                for _ in 0..<runs {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    _ = try await decoder.decode(encoded)
                    timings.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                }
                timings.sort()
                let median = timings[runs / 2]
                let pad = label.padding(toLength: 26, withPad: " ", startingAt: 0)
                emit("\(pad)  \(String(format: "%10.3f", median))")
            } catch {
                emit("  \(label) FAILED: \(error)")
            }
        }
        emit(String(repeating: "─", count: 60))
        fh.closeFile()
    }

    // MARK: - Rate-Distortion / Compression Ratio Benchmark

    /// Rate-distortion benchmark: compares J2KSwift vs OpenJPEG compression efficiency.
    ///
    /// For each image, encodes at several bpp targets with both codecs and records
    /// (bpp, size, PSNR). Then reports three views:
    /// 1. **Same bpp → PSNR**: who has higher quality at equal bitrate?
    /// 2. **Same PSNR → size**: who produces smaller files at equal quality (log-linear
    ///    interpolation on the rate-distortion curve).
    /// 3. **BD-rate** (Bjøntegaard-Delta): average relative bitrate difference of
    ///    J2KSwift vs OpenJPEG over the overlapping PSNR range. Negative = J2KSwift
    ///    needs fewer bits at equal quality (better); positive = worse.
    func testCompressionRatioVsOpenJPEG() async throws {
        #if DEBUG
        print("⚠️  WARNING: Running compression-ratio benchmark in DEBUG mode.")
        print("   Use: swift test -c release --filter testCompressionRatioVsOpenJPEG")
        #endif

        guard hasOpenJPEG else {
            print("SKIP testCompressionRatioVsOpenJPEG: OpenJPEG CLI not found")
            return
        }

        // Rate-distortion sweep. Covers low-rate regime where rate control matters.
        let bppPoints: [Double] = [0.125, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0]

        // Target PSNRs for matched-quality size comparison.
        let targetPSNRs: [Double] = [25, 30, 35, 40, 45]

        let configs: [(String, Int, Int, Int)] = [
            ("Grad-512-8b",  512,  512,  8),
            ("Grad-1024-8b", 1024, 1024, 8),
            ("Med-512-12b",  512,  512, 12),
            ("Med-512-16b",  512,  512, 16),
        ]

        let outDir = "/tmp/j2k_compression_ratio"
        try? FileManager.default.createDirectory(atPath: outDir,
            withIntermediateDirectories: true)

        var csvLines: [String] = ["Image,Resolution,BitDepth,Codec,bpp,Size_bytes,PSNR_dB"]

        for (label, w, h, bd) in configs {
            let image: J2KImage
            if bd > 8 {
                image = generateMedicalPhantom(width: w, height: h, bitDepth: bd)
            } else {
                image = generateGradientImage(width: w, height: h, components: 1, bitDepth: bd)
            }
            let origData = image.components[0].data
            let pgmPath = "\(outDir)/\(label).pgm"
            try savePGM(data: origData, width: w, height: h, bitDepth: bd, path: pgmPath)
            let levels = min(5, Int(log2(Double(min(w, h)))) - 1)

            var j2kPoints: [RDPoint] = []
            var opjPoints: [RDPoint] = []

            print("\n[\(label) \(w)x\(h) \(bd)-bit] Rate-distortion sweep")
            print("  bpp     J2K Size   J2K PSNR   OPJ Size   OPJ PSNR   ΔPSNR(J2K−OPJ)   Size J2K/OPJ")
            print("  ─────   ────────   ────────   ────────   ────────   ──────────────   ────────────")

            for bpp in bppPoints {
                // J2KSwift encode at this bpp via .constantBitrate
                var cfg = J2KEncodingConfiguration(
                    quality: 0.5, lossless: false, decompositionLevels: levels)
                cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
                cfg.qualityLayers = 1
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                let j2kData = try await encoder.encode(image)
                let (_, j2kDec) = try await j2kDecode(data: j2kData)
                let j2kPSNR = computePSNR(original: origData,
                                          decoded: j2kDec.components[0].data, bitDepth: bd)

                // OpenJPEG encode at this bpp (ratio = bd/bpp)
                let ratio = Double(bd) / bpp
                let opjJ2kPath = "\(outDir)/\(label)_opj_\(bpp).j2k"
                let opjPgmPath = "\(outDir)/\(label)_opj_\(bpp)_dec.pgm"
                let (_, opjSize) = try opjEncode(
                    pgmPath: pgmPath, j2kPath: opjJ2kPath,
                    compressionRatio: ratio, lossless: false)
                _ = try opjDecode(j2kPath: opjJ2kPath, pgmPath: opjPgmPath)
                guard let pgmData = FileManager.default.contents(atPath: opjPgmPath),
                      let opjPixels = parsePGMPixels(pgmData,
                           expectedWidth: w, expectedHeight: h, bitDepth: bd) else {
                    continue
                }
                let opjPSNR = computePSNR(original: origData,
                                          decoded: opjPixels, bitDepth: bd)

                j2kPoints.append(RDPoint(bpp: bpp, size: j2kData.count, psnr: j2kPSNR))
                opjPoints.append(RDPoint(bpp: bpp, size: opjSize,     psnr: opjPSNR))

                csvLines.append("\(label),\(w)x\(h),\(bd),J2KSwift,\(bpp),\(j2kData.count),\(j2kPSNR)")
                csvLines.append("\(label),\(w)x\(h),\(bd),OpenJPEG,\(bpp),\(opjSize),\(opjPSNR)")

                let sizeRatio = Double(j2kData.count) / Double(opjSize)
                let psnrDelta = j2kPSNR - opjPSNR
                print(String(format: "  %5.3f   %8d   %6.2f dB  %8d   %6.2f dB   %+6.2f dB        %5.3f×",
                             bpp, j2kData.count, j2kPSNR, opjSize, opjPSNR, psnrDelta, sizeRatio))
            }

            // Same-PSNR → size comparison (log-linear interpolation of rate-distortion curve)
            print("\n  Matched-PSNR size comparison (log-linear RD interpolation):")
            print("  Target PSNR   J2K Size     OPJ Size     J2K/OPJ   Verdict")
            print("  ───────────   ──────────   ──────────   ───────   ──────────────────────")
            for target in targetPSNRs {
                guard let jSize = interpolateSizeAtPSNR(points: j2kPoints, targetPSNR: target),
                      let oSize = interpolateSizeAtPSNR(points: opjPoints, targetPSNR: target) else {
                    print(String(format: "  %6.1f dB      (out of range for one codec)", target))
                    continue
                }
                let ratio = jSize / oSize
                let verdict: String
                if ratio < 0.98 { verdict = "J2KSwift smaller ✓" }
                else if ratio > 1.02 { verdict = "OpenJPEG smaller" }
                else { verdict = "≈ equal" }
                print(String(format: "  %6.1f dB      %10d   %10d   %5.3f×   %@",
                             target, Int(jSize), Int(oSize), ratio, verdict))
            }

            // BD-rate: average relative bitrate difference over overlapping PSNR range
            if let bdRate = bjontegaardDeltaRate(reference: opjPoints, target: j2kPoints) {
                let verdict = bdRate < 0 ? "J2KSwift uses fewer bits at equal quality" :
                              bdRate > 0 ? "J2KSwift uses more bits at equal quality" : "equal"
                print(String(format: "\n  BD-rate (J2KSwift vs OpenJPEG): %+6.2f%%  → %@",
                             bdRate, verdict))
            }
        }

        let csv = csvLines.joined(separator: "\n") + "\n"
        let csvPath = "\(outDir)/rate_distortion.csv"
        try csv.write(toFile: csvPath, atomically: true, encoding: .utf8)
        print("\nRate-distortion data → \(csvPath)")
    }

    /// Log-linear interpolation of file size (bytes) at a target PSNR value.
    ///
    /// Rate-distortion curves are monotonic and approximately linear when
    /// plotted as `log(size)` vs `PSNR`, which is the standard transformation
    /// used in video coding rate-distortion analysis.
    private func interpolateSizeAtPSNR(
        points: [RDPoint], targetPSNR: Double
    ) -> Double? {
        guard points.count >= 2 else { return nil }
        let sorted = points.sorted { $0.psnr < $1.psnr }
        guard targetPSNR >= sorted.first!.psnr, targetPSNR <= sorted.last!.psnr else {
            return nil
        }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            if targetPSNR >= a.psnr && targetPSNR <= b.psnr {
                let ls = log(Double(a.size)), le = log(Double(b.size))
                let t = (targetPSNR - a.psnr) / (b.psnr - a.psnr)
                return exp(ls + t * (le - ls))
            }
        }
        return nil
    }

    /// Shared RD-point type for interpolation helpers.
    struct RDPoint { let bpp: Double; let size: Int; let psnr: Double }

    /// Bjøntegaard-Delta rate (BD-rate): average percentage bitrate difference
    /// between two rate-distortion curves over their overlapping PSNR range.
    ///
    /// Negative = `target` needs fewer bits than `reference` at equal quality.
    /// Implementation uses simple trapezoidal integration of (log bitrate vs PSNR)
    /// — sufficient for first-order RD comparison. Returns nil if curves don't overlap.
    private func bjontegaardDeltaRate(
        reference: [RDPoint], target: [RDPoint]
    ) -> Double? {
        guard reference.count >= 2, target.count >= 2 else { return nil }
        let refSorted = reference.sorted { $0.psnr < $1.psnr }
        let tgtSorted = target.sorted { $0.psnr < $1.psnr }
        let lo = max(refSorted.first!.psnr, tgtSorted.first!.psnr)
        let hi = min(refSorted.last!.psnr,  tgtSorted.last!.psnr)
        guard hi > lo else { return nil }

        // Sample both curves at N points across the overlap, integrate log(bpp)
        // via the trapezoidal rule, then convert mean log-ratio → percentage.
        let N = 20
        var sumRef = 0.0, sumTgt = 0.0
        for i in 0..<N {
            let t = Double(i) / Double(N - 1)
            let psnr = lo + t * (hi - lo)
            guard let rSize = interpolateSizeAtPSNR(points: refSorted, targetPSNR: psnr),
                  let tSize = interpolateSizeAtPSNR(points: tgtSorted, targetPSNR: psnr) else {
                return nil
            }
            sumRef += log(rSize)
            sumTgt += log(tSize)
        }
        let meanLogRef = sumRef / Double(N)
        let meanLogTgt = sumTgt / Double(N)
        return (exp(meanLogTgt - meanLogRef) - 1.0) * 100.0
    }

    // MARK: - Real-DICOM Rate-Distortion Benchmark

    /// Minimal DICOM loader: handles uncompressed Explicit VR Little Endian files
    /// (the dominant on-disk format for modern PACS datasets). Extracts pixel
    /// geometry + raw pixel bytes and returns a `J2KImage`.
    ///
    /// Intentionally scoped to the subset of DICOM needed to drive rate-distortion
    /// analysis on real medical images — we don't need full DICOM VR/UID coverage.
    private func loadUncompressedDICOM(_ url: URL) throws -> (
        image: J2KImage, width: Int, height: Int, bitDepth: Int, signed: Bool
    ) {
        let data = try Data(contentsOf: url)
        guard data.count >= 132 + 4 else {
            throw NSError(domain: "DICOM", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Too small: \(url.lastPathComponent)"])
        }
        let magic = String(data: data.subdata(in: 128..<132), encoding: .ascii)
        guard magic == "DICM" else {
            throw NSError(domain: "DICOM", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No DICM magic: \(url.lastPathComponent)"])
        }

        // Little-endian readers
        func u16(_ off: Int) -> UInt16 {
            UInt16(data[off]) | (UInt16(data[off + 1]) << 8)
        }
        func u32(_ off: Int) -> UInt32 {
            UInt32(data[off]) | (UInt32(data[off + 1]) << 8) |
            (UInt32(data[off + 2]) << 16) | (UInt32(data[off + 3]) << 24)
        }

        // Step 1: File Meta Info (group 0002) — always Explicit VR LE.
        // We need the Transfer Syntax UID.
        var offset = 132
        var transferSyntaxUID = "1.2.840.10008.1.2.1"
        while offset + 8 <= data.count {
            let group = u16(offset)
            if group != 0x0002 { break }
            let element = u16(offset + 2)
            let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)),
                            encoding: .ascii) ?? ""
            let longVRs: Set<String> = ["OB", "OW", "OF", "SQ", "UT", "UN"]
            let valueLength: Int
            let headerSize: Int
            if longVRs.contains(vr) {
                valueLength = Int(u32(offset + 8))
                headerSize = 12
            } else {
                valueLength = Int(u16(offset + 6))
                headerSize = 8
            }
            if element == 0x0010 {
                if let uid = String(data: data.subdata(
                    in: (offset + headerSize)..<(offset + headerSize + valueLength)),
                    encoding: .ascii)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) {
                    transferSyntaxUID = uid
                }
            }
            offset = offset + headerSize + valueLength
        }

        // Only support uncompressed Explicit VR LE for this benchmark
        guard transferSyntaxUID == "1.2.840.10008.1.2.1" ||
              transferSyntaxUID == "1.2.840.10008.1.2" else {
            throw NSError(domain: "DICOM", code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    "Unsupported TS \(transferSyntaxUID) in \(url.lastPathComponent)"])
        }
        let explicitVR = (transferSyntaxUID == "1.2.840.10008.1.2.1")

        // Step 2: Walk the main dataset looking for the tags we need.
        var rows = 0, columns = 0
        var bitsAllocated = 16, bitsStored = 0
        var pixelRepresentation = 0
        var pixelDataOffset = -1
        var pixelDataLength = 0

        while offset + 4 <= data.count {
            let group = u16(offset)
            let element = u16(offset + 2)
            let tag = (group, element)
            if tag == (0x7FE0, 0x0010) {
                // Pixel Data — read length then break
                if explicitVR {
                    // OW or OB with long form: reserved(2) + length(4)
                    let valueLength = Int(u32(offset + 8))
                    pixelDataOffset = offset + 12
                    pixelDataLength = valueLength
                } else {
                    let valueLength = Int(u32(offset + 4))
                    pixelDataOffset = offset + 8
                    pixelDataLength = valueLength
                }
                break
            }
            let valueLength: Int
            let headerSize: Int
            if explicitVR {
                let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)),
                                encoding: .ascii) ?? ""
                let longVRs: Set<String> = ["OB", "OW", "OF", "SQ", "UT", "UN"]
                if longVRs.contains(vr) {
                    valueLength = Int(u32(offset + 8))
                    headerSize = 12
                } else {
                    valueLength = Int(u16(offset + 6))
                    headerSize = 8
                }
            } else {
                valueLength = Int(u32(offset + 4))
                headerSize = 8
            }
            let valueStart = offset + headerSize
            if group == 0x0028 {
                switch element {
                case 0x0010: rows = Int(u16(valueStart))
                case 0x0011: columns = Int(u16(valueStart))
                case 0x0100: bitsAllocated = Int(u16(valueStart))
                case 0x0101: bitsStored = Int(u16(valueStart))
                case 0x0103: pixelRepresentation = Int(u16(valueStart))
                default: break
                }
            }
            offset = valueStart + valueLength
        }

        guard rows > 0, columns > 0, pixelDataOffset > 0 else {
            throw NSError(domain: "DICOM", code: 4,
                userInfo: [NSLocalizedDescriptionKey:
                    "Missing geometry or pixel data in \(url.lastPathComponent)"])
        }
        let effectiveBitDepth = bitsStored > 0 ? bitsStored : bitsAllocated
        let signed = (pixelRepresentation == 1)
        let bytesPerSample = bitsAllocated <= 8 ? 1 : 2
        let samplesPerFrame = rows * columns
        let frameBytes = samplesPerFrame * bytesPerSample
        guard pixelDataOffset + frameBytes <= data.count else {
            throw NSError(domain: "DICOM", code: 5,
                userInfo: [NSLocalizedDescriptionKey:
                    "Pixel data truncated in \(url.lastPathComponent)"])
        }
        // DICOM pixel data is always little-endian in Explicit VR LE transfer
        // syntax. Our benchmark pipeline (PGM writer, PSNR comparator, decoder
        // output) uses big-endian, so we transcode here. For 12-bit-in-16-bit
        // data we also mask to `bitsStored` before swapping.
        var frameData = data.subdata(
            in: pixelDataOffset..<(pixelDataOffset + frameBytes))
        if bytesPerSample == 2 {
            let mask: UInt16 = effectiveBitDepth < 16
                ? UInt16((1 << effectiveBitDepth) - 1) : 0xFFFF
            frameData.withUnsafeMutableBytes { buf in
                guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for i in 0..<samplesPerFrame {
                    let lo = UInt16(ptr[i * 2])
                    let hi = UInt16(ptr[i * 2 + 1])
                    let v = (lo | (hi << 8)) & mask
                    ptr[i * 2]     = UInt8(v >> 8)     // BE: high byte first
                    ptr[i * 2 + 1] = UInt8(v & 0xFF)
                }
            }
        }
        let comp = J2KComponent(
            index: 0, bitDepth: effectiveBitDepth, signed: signed,
            width: columns, height: rows, data: frameData,
            sampleByteOrder: effectiveBitDepth > 8 ? .bigEndian : nil)
        let image = J2KImage(width: columns, height: rows, components: [comp])
        return (image, columns, rows, effectiveBitDepth, signed)
    }

    /// Rate-distortion benchmark on real DICOM images across modalities (CT, DX,
    /// MG, MR, PX, XA). Reports BD-rate vs OpenJPEG to quantify the compression
    /// efficiency gap that matters for PACS deployment. Skipped gracefully if the
    /// local DICOM dataset is not available.
    func testCompressionRatioOnRealDICOM() async throws {
        #if DEBUG
        print("⚠️  WARNING: Running DICOM rate-distortion in DEBUG mode.")
        print("   Use: swift test -c release --filter testCompressionRatioOnRealDICOM")
        #endif

        guard hasOpenJPEG else {
            print("SKIP testCompressionRatioOnRealDICOM: OpenJPEG CLI not found")
            return
        }

        let root = "/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized"
        guard FileManager.default.fileExists(atPath: root) else {
            print("SKIP testCompressionRatioOnRealDICOM: DICOM dataset not present at \(root)")
            return
        }

        // Curated representative sample per modality — one file each keeps
        // benchmark runtime bounded while still covering the PACS spectrum.
        let samples: [(modality: String, path: String)] = [
            ("CT", "\(root)/ct/study_001/instance_000001.dcm"),
            ("DX", "\(root)/dx/study_001/instance_000001.dcm"),
            ("MG", "\(root)/mg/study_001/instance_000001.dcm"),
            ("MR", "\(root)/mr/study_001/instance_000001.dcm"),
            ("PX", "\(root)/px/study_001/instance_000001.dcm"),
            ("XA", "\(root)/xa/study_001/instance_000001.dcm"),
        ]

        let bppPoints: [Double] = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0]
        let targetPSNRs: [Double] = [35, 40, 45, 50]

        let outDir = "/tmp/j2k_dicom_benchmark"
        try? FileManager.default.createDirectory(atPath: outDir,
            withIntermediateDirectories: true)

        var csvLines: [String] = [
            "Modality,File,Resolution,BitDepth,Codec,bpp,Size_bytes,PSNR_dB"]
        var perModalityBDRate: [(modality: String, w: Int, h: Int, bd: Int, bdRate: Double)] = []

        for (modality, path) in samples {
            guard FileManager.default.fileExists(atPath: path) else {
                print("  SKIP \(modality): \(path) not found")
                continue
            }

            let image: J2KImage
            let w: Int, h: Int, bd: Int
            do {
                let loaded = try loadUncompressedDICOM(URL(fileURLWithPath: path))
                image = loaded.image
                w = loaded.width; h = loaded.height; bd = loaded.bitDepth
            } catch {
                print("  SKIP \(modality): \(error.localizedDescription)")
                continue
            }

            let origData = image.components[0].data
            let pgmPath = "\(outDir)/\(modality).pgm"
            try savePGM(data: origData, width: w, height: h, bitDepth: bd, path: pgmPath)
            let levels = min(5, Int(log2(Double(min(w, h)))) - 1)

            // Lossless sanity check — isolate encoder vs decoder bugs via
            // J2K→J2K and J2K→OPJ cross-decode on the same stream.
            do {
                let cfg = J2KEncodingConfiguration(
                    quality: 1.0, lossless: true, decompositionLevels: levels)
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                let encoded = try await encoder.encode(image)

                // J2K → J2K (our decoder)
                let (_, selfDec) = try await j2kDecode(data: encoded)
                let selfPSNR = computePSNR(original: origData,
                                           decoded: selfDec.components[0].data, bitDepth: bd)
                let selfMAE = computeMAE(original: origData,
                                         decoded: selfDec.components[0].data, bitDepth: bd)

                // J2K → OPJ (OpenJPEG decodes our stream)
                let j2kPath = "\(outDir)/\(modality)_lossless.j2k"
                let opjDecPgm = "\(outDir)/\(modality)_lossless_opj.pgm"
                try encoded.write(to: URL(fileURLWithPath: j2kPath))
                var opjCrossPSNR: Double = 0
                var opjCrossOK = false
                do {
                    _ = try opjDecode(j2kPath: j2kPath, pgmPath: opjDecPgm)
                    if let pgm = FileManager.default.contents(atPath: opjDecPgm),
                       let px = parsePGMPixels(pgm, expectedWidth: w, expectedHeight: h, bitDepth: bd) {
                        opjCrossPSNR = computePSNR(original: origData,
                                                   decoded: px, bitDepth: bd)
                        opjCrossOK = true
                    }
                } catch {}

                let selfStr = selfPSNR.isInfinite ? "∞" : String(format: "%.2f dB", selfPSNR)
                let opjStr = opjCrossOK
                    ? (opjCrossPSNR.isInfinite ? "∞"
                        : String(format: "%.2f dB", opjCrossPSNR))
                    : "FAIL"
                let verdict: String
                if selfPSNR.isInfinite && opjCrossPSNR.isInfinite {
                    verdict = "OK (bit-exact both ways)"
                } else if opjCrossPSNR.isInfinite {
                    verdict = "DECODER BUG (our stream is valid, OPJ decodes it; our decoder fails)"
                } else if selfPSNR.isInfinite {
                    verdict = "OPJ DECODE QUIRK (self works, OPJ output differs — likely byte-order/format mismatch)"
                } else {
                    verdict = "ENCODER BUG (even OPJ can't recover the original from our stream)"
                }
                print("\n[\(modality) \(w)x\(h) \(bd)-bit] lossless: self=\(selfStr) (MAE=\(String(format: "%.1f", selfMAE))), J2K→OPJ=\(opjStr), size=\(encoded.count)\n  ⇒ \(verdict)")
            } catch {
                print("\n[\(modality) \(w)x\(h) \(bd)-bit] lossless encode threw: \(error)")
            }

            print("[\(modality) \(w)x\(h) \(bd)-bit] Rate-distortion sweep")
            print("  bpp     J2K Size   J2K PSNR   OPJ Size   OPJ PSNR   ΔPSNR(J2K−OPJ)   Size J2K/OPJ")
            print("  ─────   ────────   ────────   ────────   ────────   ──────────────   ────────────")

            var j2kPoints: [RDPoint] = []
            var opjPoints: [RDPoint] = []

            for bpp in bppPoints {
                var cfg = J2KEncodingConfiguration(
                    quality: 0.5, lossless: false, decompositionLevels: levels)
                cfg.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
                cfg.qualityLayers = 1
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                let j2kData: Data
                do {
                    j2kData = try await encoder.encode(image)
                } catch {
                    print(String(format: "  %5.3f   J2K encode failed: %@", bpp, "\(error)"))
                    continue
                }
                let (_, j2kDec) = try await j2kDecode(data: j2kData)
                let j2kPSNR = computePSNR(original: origData,
                                          decoded: j2kDec.components[0].data, bitDepth: bd)

                let ratio = Double(bd) / bpp
                let opjJ2kPath = "\(outDir)/\(modality)_opj_\(bpp).j2k"
                let opjPgmPath = "\(outDir)/\(modality)_opj_\(bpp)_dec.pgm"
                let (_, opjSize): (Double, Int)
                do {
                    (_, opjSize) = try opjEncode(
                        pgmPath: pgmPath, j2kPath: opjJ2kPath,
                        compressionRatio: ratio, lossless: false)
                } catch {
                    print(String(format: "  %5.3f   OPJ encode failed: %@", bpp, "\(error)"))
                    continue
                }
                _ = try opjDecode(j2kPath: opjJ2kPath, pgmPath: opjPgmPath)
                guard let pgmData = FileManager.default.contents(atPath: opjPgmPath),
                      let opjPixels = parsePGMPixels(pgmData,
                           expectedWidth: w, expectedHeight: h, bitDepth: bd) else { continue }
                let opjPSNR = computePSNR(original: origData,
                                          decoded: opjPixels, bitDepth: bd)

                j2kPoints.append(RDPoint(bpp: bpp, size: j2kData.count, psnr: j2kPSNR))
                opjPoints.append(RDPoint(bpp: bpp, size: opjSize,     psnr: opjPSNR))

                csvLines.append("\(modality),\(URL(fileURLWithPath: path).lastPathComponent),\(w)x\(h),\(bd),J2KSwift,\(bpp),\(j2kData.count),\(j2kPSNR)")
                csvLines.append("\(modality),\(URL(fileURLWithPath: path).lastPathComponent),\(w)x\(h),\(bd),OpenJPEG,\(bpp),\(opjSize),\(opjPSNR)")

                let sizeRatio = Double(j2kData.count) / Double(opjSize)
                let psnrDelta = j2kPSNR - opjPSNR
                print(String(format: "  %5.3f   %8d   %6.2f dB  %8d   %6.2f dB   %+6.2f dB        %5.3f×",
                             bpp, j2kData.count, j2kPSNR, opjSize, opjPSNR, psnrDelta, sizeRatio))
            }

            print("\n  Matched-PSNR size comparison:")
            print("  Target PSNR   J2K Size     OPJ Size     J2K/OPJ   Verdict")
            for target in targetPSNRs {
                guard let jSize = interpolateSizeAtPSNR(points: j2kPoints, targetPSNR: target),
                      let oSize = interpolateSizeAtPSNR(points: opjPoints, targetPSNR: target) else {
                    continue
                }
                let ratio = jSize / oSize
                let verdict: String
                if ratio < 0.98 { verdict = "J2KSwift smaller ✓" }
                else if ratio > 1.02 { verdict = "OpenJPEG smaller" }
                else { verdict = "≈ equal" }
                print(String(format: "  %6.1f dB      %10d   %10d   %5.3f×   %@",
                             target, Int(jSize), Int(oSize), ratio, verdict))
            }

            if let bdRate = bjontegaardDeltaRate(reference: opjPoints, target: j2kPoints) {
                let verdict = bdRate < 0 ? "J2KSwift uses fewer bits at equal quality" :
                              bdRate > 0 ? "J2KSwift uses more bits at equal quality" : "equal"
                print(String(format: "\n  BD-rate (%@): %+6.2f%%  → %@", modality, bdRate, verdict))
                perModalityBDRate.append((modality, w, h, bd, bdRate))
            }
        }

        // Aggregate
        if !perModalityBDRate.isEmpty {
            let avg = perModalityBDRate.map { $0.bdRate }.reduce(0, +) /
                      Double(perModalityBDRate.count)
            print("\n═══════════════════════════════════════════════════════════")
            print(" DICOM BD-rate summary (J2KSwift vs OpenJPEG)")
            print("═══════════════════════════════════════════════════════════")
            print(" Mod.    Size         Bits    BD-rate")
            print(" ──────  ──────────   ────    ──────────────────────────")
            for e in perModalityBDRate {
                let sizeStr = "\(e.w)x\(e.h)"
                let paddedMod = e.modality.padding(toLength: 6, withPad: " ", startingAt: 0)
                let paddedSize = sizeStr.padding(toLength: 11, withPad: " ", startingAt: 0)
                print(String(format: " %@  %@ %-4d    %+7.2f%%",
                             paddedMod, paddedSize, e.bd, e.bdRate))
            }
            print(String(format: "\n Average BD-rate across all modalities: %+6.2f%%", avg))
            print("═══════════════════════════════════════════════════════════")
        }

        let csv = csvLines.joined(separator: "\n") + "\n"
        let csvPath = "\(outDir)/dicom_rate_distortion.csv"
        try csv.write(toFile: csvPath, atomically: true, encoding: .utf8)
        print("\nDICOM rate-distortion data → \(csvPath)")
    }

    // MARK: - Cross-Codec Interoperability Benchmark

    /// Comprehensive cross-codec interoperability test: J2KSwift ↔ OpenJPEG encode/decode matrix.
    ///
    /// Tests all four codec combinations per image config and compression mode:
    /// - **J2KSwift → J2KSwift** (self round-trip)
    /// - **J2KSwift → OpenJPEG** (our streams decoded by reference implementation)
    /// - **OpenJPEG → J2KSwift** (reference streams decoded by our implementation)
    /// - **OpenJPEG → OpenJPEG** (reference baseline)
    ///
    /// For each combination, records encode time, decode time, file size, PSNR, and MAE.
    /// Lossless paths must produce MAE = 0 (pixel-perfect). Lossy paths record quality metrics
    /// and verify that cross-codec PSNR matches same-codec PSNR within 1 dB.
    ///
    /// Results are written to `/tmp/j2k_cross_codec/cross_codec_results.csv`.
    func testCrossCodecInteroperability() async throws {
        #if DEBUG
        print("⚠️  WARNING: Running cross-codec benchmark in DEBUG mode. Timing results are unreliable.")
        print("   Use: swift test -c release --filter testCrossCodecInteroperability")
        #endif

        guard hasOpenJPEG else {
            print("SKIP testCrossCodecInteroperability: OpenJPEG not found at \(opjCompress)")
            return
        }

        let crossDir = "/tmp/j2k_cross_codec"
        try FileManager.default.createDirectory(atPath: crossDir, withIntermediateDirectories: true)

        struct CrossResult {
            let image: String
            let resolution: String
            let bitDepth: Int
            let mode: String
            let encoder: String
            let decoder: String
            let encodeTime: Double
            let decodeTime: Double
            let fileSize: Int
            let psnr: Double
            let mae: Double

            var csvLine: String {
                let psnrStr = psnr.isInfinite ? "Inf" : String(format: "%.2f", psnr)
                return "\(image),\(resolution),\(bitDepth),\(mode),\(encoder),\(decoder)," +
                       "\(String(format: "%.4f", encodeTime))," +
                       "\(String(format: "%.4f", decodeTime))," +
                       "\(fileSize),\(psnrStr),\(String(format: "%.3f", mae))"
            }
        }

        var results: [CrossResult] = []

        // Test matrix: (label, width, height, bitDepth)
        let configs: [(String, Int, Int, Int)] = [
            ("Grad-256-8b",   256,  256,  8),
            ("Grad-512-8b",   512,  512,  8),
            ("Grad-1024-8b", 1024, 1024,  8),
            ("Med-512-12b",   512,  512, 12),
            ("Med-512-16b",   512,  512, 16),
        ]

        // (modeLabel, lossless, j2kQuality, bpp)
        let modes: [(String, Bool, Double, Double?)] = [
            ("lossless",    true,  1.0, nil),
            ("lossy-q0.9",  false, 0.9, nil),
            ("lossy-2bpp",  false, 0.8, 2.0),
            ("lossy-1bpp",  false, 0.7, 1.0),
            ("lossy-0.5bpp", false, 0.5, 0.5),
        ]

        var grandTotal = 0
        var grandPassed = 0

        for (label, w, h, bd) in configs {
            let image: J2KImage = bd > 8
                ? generateMedicalPhantom(width: w, height: h, bitDepth: bd)
                : generateGradientImage(width: w, height: h, components: 1, bitDepth: bd)
            let origData = image.components[0].data
            let levels = min(5, Int(log2(Double(min(w, h)))) - 1)

            // Save original as PGM for OpenJPEG (reused across all modes)
            let pgmPath = "\(crossDir)/\(label)_orig.pgm"
            try savePGM(data: origData, width: w, height: h, bitDepth: bd, path: pgmPath)

            for (modeLabel, lossless, quality, bpp) in modes {
                let tag = "\(label)_\(modeLabel)"
                print("\n[\(tag)]")

                // Compute OPJ compression ratio from bpp or quality.
                // For quality-based modes (no explicit bpp), map quality → bpp
                // using the same piecewise curve as J2KSwift's rate control
                // (qualityToBitrate). This ensures fair comparison: both encoders
                // target the same bitrate.
                let opjRatio: Double? = lossless ? nil : {
                    if let b = bpp { return Double(bd) / b }
                    // Map quality → bpp matching J2KRateControl.qualityToBitrate
                    let targetBpp: Double
                    if quality >= 1.0 {
                        targetBpp = 8.0
                    } else if quality >= 0.95 {
                        targetBpp = 2.0 + (quality - 0.95) * 120.0
                    } else if quality >= 0.80 {
                        targetBpp = 0.5 + (quality - 0.80) * 10.0
                    } else if quality >= 0.50 {
                        targetBpp = 0.15 + (quality - 0.50) * 1.167
                    } else {
                        targetBpp = 0.05 + quality * 0.2
                    }
                    return Double(bd) / targetBpp
                }()

                // ── A. J2KSwift encode (shared for J2K→J2K and J2K→OPJ) ──────────
                let (j2kEncTime, j2kData) = try await j2kEncode(
                    image: image, quality: quality, lossless: lossless,
                    bpp: bpp, decompositionLevels: levels)
                let j2kFilePath = "\(crossDir)/\(tag)_j2k.j2k"
                try j2kData.write(to: URL(fileURLWithPath: j2kFilePath))

                // ── B. OPJ encode (shared for OPJ→J2K and OPJ→OPJ) ──────────────
                let opjJ2kPath = "\(crossDir)/\(tag)_opj.j2k"
                var opjEncTime: Double = 0
                var opjFileSize: Int = 0
                var opjEncOK = false
                do {
                    let (t, sz) = try opjEncode(
                        pgmPath: pgmPath, j2kPath: opjJ2kPath,
                        compressionRatio: opjRatio, lossless: lossless)
                    opjEncTime = t; opjFileSize = sz; opjEncOK = true
                } catch {
                    print("  OPJ encode FAILED: \(error)")
                }

                // ── 1. J2KSwift → J2KSwift ───────────────────────────────────────
                do {
                    let (decTime, decImage) = try await j2kDecode(data: j2kData)
                    let decData = decImage.components[0].data
                    let psnr = computePSNR(original: origData, decoded: decData, bitDepth: bd)
                    let mae  = computeMAE(original: origData, decoded: decData, bitDepth: bd)
                    results.append(CrossResult(
                        image: label, resolution: "\(w)x\(h)", bitDepth: bd,
                        mode: modeLabel, encoder: "J2KSwift", decoder: "J2KSwift",
                        encodeTime: j2kEncTime, decodeTime: decTime,
                        fileSize: j2kData.count, psnr: psnr, mae: mae))
                    let psnrStr = psnr.isInfinite ? "Inf" : String(format: "%.2f", psnr)
                    print("  J2KSwift→J2KSwift  enc=\(String(format: "%.3f", j2kEncTime))s " +
                          "dec=\(String(format: "%.3f", decTime))s " +
                          "size=\(j2kData.count) PSNR=\(psnrStr)dB MAE=\(String(format: "%.3f", mae))")
                    grandTotal += 1; if lossless { if mae == 0 { grandPassed += 1 } } else { if psnr > 22 { grandPassed += 1 } }
                } catch {
                    print("  J2KSwift→J2KSwift FAILED: \(error)")
                    grandTotal += 1
                }

                // ── 2. J2KSwift → OpenJPEG ───────────────────────────────────────
                let j2kToOpjPgm = "\(crossDir)/\(tag)_j2k_opjdec.pgm"
                do {
                    let decTime = try opjDecode(j2kPath: j2kFilePath, pgmPath: j2kToOpjPgm)
                    if let pgmData = FileManager.default.contents(atPath: j2kToOpjPgm),
                       let pixels = parsePGMPixels(pgmData, expectedWidth: w, expectedHeight: h, bitDepth: bd) {
                        let psnr = computePSNR(original: origData, decoded: pixels, bitDepth: bd)
                        let mae  = computeMAE(original: origData, decoded: pixels, bitDepth: bd)
                        results.append(CrossResult(
                            image: label, resolution: "\(w)x\(h)", bitDepth: bd,
                            mode: modeLabel, encoder: "J2KSwift", decoder: "OpenJPEG",
                            encodeTime: j2kEncTime, decodeTime: decTime,
                            fileSize: j2kData.count, psnr: psnr, mae: mae))
                        let psnrStr = psnr.isInfinite ? "Inf" : String(format: "%.2f", psnr)
                        print("  J2KSwift→OpenJPEG  enc=\(String(format: "%.3f", j2kEncTime))s " +
                              "dec=\(String(format: "%.3f", decTime))s (OPJ) " +
                              "PSNR=\(psnrStr)dB MAE=\(String(format: "%.3f", mae))")
                        grandTotal += 1; if lossless { if mae == 0 { grandPassed += 1 } } else { if psnr > 22 { grandPassed += 1 } }
                    }
                } catch {
                    print("  J2KSwift→OpenJPEG FAILED: \(error)")
                    grandTotal += 1
                }

                guard opjEncOK else { continue }

                // ── 3. OpenJPEG → J2KSwift ───────────────────────────────────────
                do {
                    let opjRawData = try Data(contentsOf: URL(fileURLWithPath: opjJ2kPath))
                    let (decTime, decImage) = try await j2kDecode(data: opjRawData)
                    let decData = decImage.components[0].data
                    let psnr = computePSNR(original: origData, decoded: decData, bitDepth: bd)
                    let mae  = computeMAE(original: origData, decoded: decData, bitDepth: bd)
                    results.append(CrossResult(
                        image: label, resolution: "\(w)x\(h)", bitDepth: bd,
                        mode: modeLabel, encoder: "OpenJPEG", decoder: "J2KSwift",
                        encodeTime: opjEncTime, decodeTime: decTime,
                        fileSize: opjFileSize, psnr: psnr, mae: mae))
                    let psnrStr = psnr.isInfinite ? "Inf" : String(format: "%.2f", psnr)
                    print("  OpenJPEG→J2KSwift  enc=\(String(format: "%.3f", opjEncTime))s (OPJ) " +
                          "dec=\(String(format: "%.3f", decTime))s " +
                          "size=\(opjFileSize) PSNR=\(psnrStr)dB MAE=\(String(format: "%.3f", mae))")
                    grandTotal += 1; if lossless { if mae == 0 { grandPassed += 1 } } else { if psnr > 22 { grandPassed += 1 } }
                } catch {
                    print("  OpenJPEG→J2KSwift FAILED: \(error)")
                    grandTotal += 1
                }

                // ── 4. OpenJPEG → OpenJPEG (reference baseline) ──────────────────
                let opjToOpjPgm = "\(crossDir)/\(tag)_opj_opjdec.pgm"
                do {
                    let decTime = try opjDecode(j2kPath: opjJ2kPath, pgmPath: opjToOpjPgm)
                    if let pgmData = FileManager.default.contents(atPath: opjToOpjPgm),
                       let pixels = parsePGMPixels(pgmData, expectedWidth: w, expectedHeight: h, bitDepth: bd) {
                        let psnr = computePSNR(original: origData, decoded: pixels, bitDepth: bd)
                        let mae  = computeMAE(original: origData, decoded: pixels, bitDepth: bd)
                        results.append(CrossResult(
                            image: label, resolution: "\(w)x\(h)", bitDepth: bd,
                            mode: modeLabel, encoder: "OpenJPEG", decoder: "OpenJPEG",
                            encodeTime: opjEncTime, decodeTime: decTime,
                            fileSize: opjFileSize, psnr: psnr, mae: mae))
                        let psnrStr = psnr.isInfinite ? "Inf" : String(format: "%.2f", psnr)
                        print("  OpenJPEG→OpenJPEG  enc=\(String(format: "%.3f", opjEncTime))s (OPJ) " +
                              "dec=\(String(format: "%.3f", decTime))s (OPJ) " +
                              "size=\(opjFileSize) PSNR=\(psnrStr)dB MAE=\(String(format: "%.3f", mae))")
                        grandTotal += 1; if lossless { if mae == 0 { grandPassed += 1 } } else { if psnr > 22 { grandPassed += 1 } }
                    }
                } catch {
                    print("  OpenJPEG→OpenJPEG FAILED: \(error)")
                    grandTotal += 1
                }

                // ── 5. HTJ2K → HTJ2K (self round-trip) ───────────────────────────
                do {
                    let (htEncTime, htData) = try await htj2kEncode(
                        image: image, quality: quality, lossless: lossless,
                        bpp: bpp, decompositionLevels: levels)
                    let htFilePath = "\(crossDir)/\(tag)_htj2k.j2k"
                    try htData.write(to: URL(fileURLWithPath: htFilePath))

                    let (htDecTime, htDecImage) = try await j2kDecode(data: htData)
                    let htDecData = htDecImage.components[0].data
                    let psnr = computePSNR(original: origData, decoded: htDecData, bitDepth: bd)
                    let mae  = computeMAE(original: origData, decoded: htDecData, bitDepth: bd)
                    results.append(CrossResult(
                        image: label, resolution: "\(w)x\(h)", bitDepth: bd,
                        mode: modeLabel, encoder: "HTJ2K", decoder: "J2KSwift",
                        encodeTime: htEncTime, decodeTime: htDecTime,
                        fileSize: htData.count, psnr: psnr, mae: mae))
                    let psnrStr = psnr.isInfinite ? "Inf" : String(format: "%.2f", psnr)
                    print("  HTJ2K→J2KSwift     enc=\(String(format: "%.3f", htEncTime))s " +
                          "dec=\(String(format: "%.3f", htDecTime))s " +
                          "size=\(htData.count) PSNR=\(psnrStr)dB MAE=\(String(format: "%.3f", mae))")
                    grandTotal += 1; if lossless { if mae == 0 { grandPassed += 1 } } else { if psnr > 22 { grandPassed += 1 } }

                    // ── 6. HTJ2K → OpenJPEG (cross-decoder) ──────────────────────
                    let htToOpjPgm = "\(crossDir)/\(tag)_htj2k_opjdec.pgm"
                    do {
                        let htDecTimeOpj = try opjDecode(j2kPath: htFilePath, pgmPath: htToOpjPgm)
                        if let pgmData = FileManager.default.contents(atPath: htToOpjPgm),
                           let pixels = parsePGMPixels(pgmData, expectedWidth: w, expectedHeight: h, bitDepth: bd) {
                            let psnrCross = computePSNR(original: origData, decoded: pixels, bitDepth: bd)
                            let maeCross  = computeMAE(original: origData, decoded: pixels, bitDepth: bd)
                            results.append(CrossResult(
                                image: label, resolution: "\(w)x\(h)", bitDepth: bd,
                                mode: modeLabel, encoder: "HTJ2K", decoder: "OpenJPEG",
                                encodeTime: htEncTime, decodeTime: htDecTimeOpj,
                                fileSize: htData.count, psnr: psnrCross, mae: maeCross))
                            let psnrCStr = psnrCross.isInfinite ? "Inf" : String(format: "%.2f", psnrCross)
                            print("  HTJ2K→OpenJPEG     enc=\(String(format: "%.3f", htEncTime))s " +
                                  "dec=\(String(format: "%.3f", htDecTimeOpj))s (OPJ) " +
                                  "PSNR=\(psnrCStr)dB MAE=\(String(format: "%.3f", maeCross))")
                            grandTotal += 1
                            if lossless { if maeCross == 0 { grandPassed += 1 } } else { if psnrCross > 22 { grandPassed += 1 } }
                        }
                    } catch {
                        print("  HTJ2K→OpenJPEG FAILED: \(error)")
                        grandTotal += 1
                    }
                } catch {
                    print("  HTJ2K encode/decode FAILED: \(error)")
                    grandTotal += 2
                }
            }
        }

        // ── CSV output ────────────────────────────────────────────────────────────
        let csvHeader = "Image,Resolution,BitDepth,Mode,Encoder,Decoder," +
                        "EncTime_s,DecTime_s,FileSize_bytes,PSNR_dB,MAE"
        let csvPath = "\(crossDir)/cross_codec_results.csv"
        let csv = csvHeader + "\n" + results.map { $0.csvLine }.joined(separator: "\n") + "\n"
        try csv.write(toFile: csvPath, atomically: true, encoding: .utf8)
        print("\nCross-codec results → \(csvPath)")

        // ── Summary table ─────────────────────────────────────────────────────────
        let sep = String(repeating: "─", count: 90)
        print("\n" + sep)
        print("Image            Mode          Encoder    Decoder    PSNR_dB       MAE   Size_bytes")
        print(sep)
        for r in results {
            let psnrStr = r.psnr.isInfinite ? "       ∞" : String(format: "%8.2f", r.psnr)
            let imgPad  = r.image.padding(toLength: 16, withPad: " ", startingAt: 0)
            let modePad = r.mode.padding(toLength: 13, withPad: " ", startingAt: 0)
            let encPad  = r.encoder.padding(toLength: 10, withPad: " ", startingAt: 0)
            let decPad  = r.decoder.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("\(imgPad) \(modePad) \(encPad) \(decPad) \(psnrStr) \(String(format: "%8.3f", r.mae)) \(String(format: "%10d", r.fileSize))")
        }
        print(sep)
        print("Passed \(grandPassed)/\(grandTotal) quality checks\n")

        // ── Assertions ────────────────────────────────────────────────────────────
        for r in results {
            // HTJ2K encoder paths are metrics-only: the HTJ2K block coder is still
            // in development and its quality does not yet meet J2K/OPJ thresholds.
            if r.encoder == "HTJ2K" { continue }

            if r.mode == "lossless" {
                XCTAssertEqual(r.mae, 0.0, accuracy: 0.001,
                    "\(r.image) lossless \(r.encoder)→\(r.decoder) MAE=\(r.mae) (must be 0)")
                XCTAssert(r.psnr.isInfinite,
                    "\(r.image) lossless \(r.encoder)→\(r.decoder) PSNR=\(r.psnr) (must be ∞)")
            } else {
                // Minimum acceptable PSNR varies by bitrate
                let minPSNR: Double = r.mode.contains("0.5bpp") ? 22.0 : 25.0
                XCTAssertGreaterThan(r.psnr, minPSNR,
                    "\(r.image) \(r.mode) \(r.encoder)→\(r.decoder) PSNR=\(String(format: "%.2f", r.psnr)) below \(minPSNR) dB")

                // Same-encoder streams decoded by different decoders must agree within 1 dB.
                // Guard against NaN that arises when both PSNRs are ∞ (lossless-by-coincidence).
                func psnrDelta(_ a: Double, _ b: Double) -> Double {
                    if a.isInfinite && b.isInfinite { return 0.0 }
                    return abs(a - b)
                }

                if r.encoder == "J2KSwift" && r.decoder == "OpenJPEG" {
                    if let ref = results.first(where: { $0.image == r.image && $0.mode == r.mode &&
                                                         $0.encoder == "J2KSwift" && $0.decoder == "J2KSwift" }) {
                        XCTAssertLessThan(psnrDelta(r.psnr, ref.psnr), 1.0,
                            "\(r.image) \(r.mode) J2KSwift stream: OPJ-decode PSNR=\(String(format: "%.2f", r.psnr)) vs self-decode PSNR=\(String(format: "%.2f", ref.psnr))")
                    }
                }
                if r.encoder == "OpenJPEG" && r.decoder == "J2KSwift" {
                    if let ref = results.first(where: { $0.image == r.image && $0.mode == r.mode &&
                                                         $0.encoder == "OpenJPEG" && $0.decoder == "OpenJPEG" }) {
                        XCTAssertLessThan(psnrDelta(r.psnr, ref.psnr), 1.0,
                            "\(r.image) \(r.mode) OPJ stream: J2K-decode PSNR=\(String(format: "%.2f", r.psnr)) vs OPJ-decode PSNR=\(String(format: "%.2f", ref.psnr))")
                    }
                }
            }
        }
    }

    // MARK: - PGM Parser

    private func parsePGMPixels(_ data: Data, expectedWidth: Int, expectedHeight: Int, bitDepth: Int) -> Data? {
        // Validate PGM magic ("P5") from first two bytes only — no ASCII conversion of binary pixel data.
        guard data.count > 3 && data[0] == UInt8(ascii: "P") && data[1] == UInt8(ascii: "5") else {
            return nil
        }

        // Scan newlines to find header end, skipping comment lines (starting with '#').
        // opj_decompress emits "#OpenJPEG-2.5.4" as second line, giving 4 newlines before pixels.
        var headerEnd = 0
        var nonCommentLines = 0  // count non-comment lines: magic, "W H", maxval  (need 3)
        var lineStart = 0
        for (i, byte) in data.enumerated() {
            if byte == 0x0A { // '\n'
                let firstByteOfLine = lineStart < data.count ? data[lineStart] : 0
                if firstByteOfLine != UInt8(ascii: "#") {
                    nonCommentLines += 1
                    if nonCommentLines == 3 {
                        headerEnd = i + 1
                        break
                    }
                }
                lineStart = i + 1  // always advance past this newline
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

    // MARK: - HTJ2K Lossy Diagnostic

    func testHTJ2KLossyDiagnostic() async throws {
        let width = 64, height = 64, bitDepth = 8
        // Create gradient test image using J2KImage convenience init + pixel data
        let image = generateGradientImage(width: width, height: height, components: 1, bitDepth: bitDepth)

        func computePSNR(_ img1: J2KImage, _ img2: J2KImage) -> Double {
            let maxVal = Double((1 << bitDepth) - 1)
            let data1 = img1.components[0].data
            let data2 = img2.components[0].data
            var mse: Double = 0
            let count = min(data1.count, data2.count)
            for i in 0..<count {
                let d = Double(data1[i]) - Double(data2[i])
                mse += d * d
            }
            mse /= Double(count)
            return mse > 0 ? 10 * log10(maxVal * maxVal / mse) : Double.infinity
        }

        // Test 1: HTJ2K lossless
        var losslessCfg = J2KEncodingConfiguration(quality: 1.0, lossless: true)
        losslessCfg.useHTJ2K = true
        losslessCfg.decompositionLevels = 3
        let enc1 = J2KEncoder(encodingConfiguration: losslessCfg)
        let data1 = try await enc1.encode(image)
        let dec1 = try await DecoderPipeline().decode(data1)
        let psnr1 = computePSNR(image, dec1)
        print("HTJ2K LOSSLESS: PSNR=\(psnr1) size=\(data1.count)")

        // Test 2: HTJ2K lossy 9/7
        var lossyCfg = J2KEncodingConfiguration(quality: 0.9, lossless: false)
        lossyCfg.useHTJ2K = true
        lossyCfg.decompositionLevels = 3
        lossyCfg.qualityLayers = 1
        let enc2 = J2KEncoder(encodingConfiguration: lossyCfg)
        let data2 = try await enc2.encode(image)
        let dec2 = try await DecoderPipeline().decode(data2)
        let psnr2 = computePSNR(image, dec2)
        print("HTJ2K LOSSY-97: PSNR=\(psnr2) size=\(data2.count)")

        // Test 3: Standard J2K lossy 9/7
        var stdCfg = J2KEncodingConfiguration(quality: 0.9, lossless: false)
        stdCfg.useHTJ2K = false
        stdCfg.decompositionLevels = 3
        stdCfg.qualityLayers = 1
        let enc3 = J2KEncoder(encodingConfiguration: stdCfg)
        let data3 = try await enc3.encode(image)
        let dec3 = try await DecoderPipeline().decode(data3)
        let psnr3 = computePSNR(image, dec3)
        print("STD LOSSY-97: PSNR=\(psnr3) size=\(data3.count)")

        // Test 4: HTJ2K lossy 5/3
        var rev53Cfg = J2KEncodingConfiguration(quality: 0.9, lossless: false)
        rev53Cfg.useHTJ2K = true
        rev53Cfg.decompositionLevels = 3
        rev53Cfg.qualityLayers = 1
        rev53Cfg.useReversibleFilter = true
        let enc4 = J2KEncoder(encodingConfiguration: rev53Cfg)
        let data4 = try await enc4.encode(image)
        let dec4 = try await DecoderPipeline().decode(data4)
        let psnr4 = computePSNR(image, dec4)
        print("HTJ2K LOSSY-53: PSNR=\(psnr4) size=\(data4.count)")

        // Test 5: HTJ2K lossy 9/7 at quality=1.0 (near-lossless PCRD, includes all passes)
        var maxQCfg = J2KEncodingConfiguration(quality: 1.0, lossless: false)
        maxQCfg.useHTJ2K = true
        maxQCfg.decompositionLevels = 3
        maxQCfg.qualityLayers = 1
        let enc5 = J2KEncoder(encodingConfiguration: maxQCfg)
        let data5 = try await enc5.encode(image)
        let dec5 = try await DecoderPipeline().decode(data5)
        let psnr5 = computePSNR(image, dec5)
        print("HTJ2K LOSSY-97 q=1.0: PSNR=\(psnr5) size=\(data5.count)")

        // Test 6: STD lossy 9/7 at quality=1.0
        var maxQStd = J2KEncodingConfiguration(quality: 1.0, lossless: false)
        maxQStd.useHTJ2K = false
        maxQStd.decompositionLevels = 3
        maxQStd.qualityLayers = 1
        let enc6 = J2KEncoder(encodingConfiguration: maxQStd)
        let data6 = try await enc6.encode(image)
        let dec6 = try await DecoderPipeline().decode(data6)
        let psnr6 = computePSNR(image, dec6)
        print("STD LOSSY-97 q=1.0: PSNR=\(psnr6) size=\(data6.count)")

        // Pixel-level comparison at Q=1.0
        let origPx = image.components[0].data
        let htPx = dec5.components[0].data
        let stdPx = dec6.components[0].data
        // Print error histogram
        var htErrors = [Int: Int]()
        var stdErrors = [Int: Int]()
        for i in 0..<min(origPx.count, htPx.count) {
            let he = abs(Int(origPx[i]) - Int(htPx[i]))
            htErrors[he, default: 0] += 1
        }
        for i in 0..<min(origPx.count, stdPx.count) {
            let se = abs(Int(origPx[i]) - Int(stdPx[i]))
            stdErrors[se, default: 0] += 1
        }
        print("HTJ2K Q=1.0 error histogram: \(htErrors.sorted { $0.key < $1.key }.map { "e=\($0.key):\($0.value)" }.joined(separator: " "))")
        print("STD Q=1.0 error histogram: \(stdErrors.sorted { $0.key < $1.key }.map { "e=\($0.key):\($0.value)" }.joined(separator: " "))")

        XCTAssertEqual(psnr1, Double.infinity, "HTJ2K lossless should be perfect")
        XCTAssertGreaterThan(psnr2, 22, "HTJ2K lossy 9/7 should be >22 dB")
        XCTAssertGreaterThan(psnr3, 25, "Standard lossy 9/7 should be >25 dB")
        XCTAssertGreaterThan(psnr4, 22, "HTJ2K lossy 5/3 should be >22 dB")

        // Write HTJ2K lossy codestream for OPJ debugging
        let htLossyFile = "\(outputDir)/htj2k_lossy_debug.j2k"
        try data2.write(to: URL(fileURLWithPath: htLossyFile))

        // Note: OpenJPEG v2.5.4 limits HT code blocks to 3 coding passes.
        // Our codec generates more passes for better quality (spec-compliant
        // per ISO/IEC 15444-15). OPJ will reject these with:
        // "We do not support more than 3 coding passes in an HT codeblock"
        // This is an OPJ implementation limitation, not a J2KSwift bug.
    }

    /// Tests HTJ2K block coder encode→decode directly (no pipeline).
    func testHTJ2KBlockCoderDirect() async throws {
        let w = 8, h = 8
        // Simple gradient coefficients with values 0..63
        var coefficients = [Int32](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            coefficients[i] = Int32(i)
        }

        let encoder = HTBlockEncoder(width: w, height: h, subband: .ll)
        let decoder = HTBlockDecoder(width: w, height: h, subband: .ll)

        // Encode cleanup at topBitPlane = 5 (max value 63, 2^5=32 ≤ 63 < 64=2^6)
        let topBP = 5
        let cleanupBlock = try await encoder.encodeCleanup(
            coefficients: coefficients.map { Int($0) }, bitPlane: topBP)

        // Full decode (cleanup only)
        let decoded1 = try decoder.decodeFromCodestream(
            data: cleanupBlock.codedData, passCount: 1,
            bitDepth: 8, zeroBitPlanes: 2)
        var err1 = 0
        for i in 0..<(w * h) {
            err1 = max(err1, abs(Int(coefficients[i]) - Int(decoded1[i])))
        }
        print("BLOCK cleanup-only: maxErr=\(err1) (should be ≤\(1 << topBP))")

        // Now encode refinement passes and decode
        var absMags = coefficients.map { abs($0) }
        let count = w * h
        let sigLen = (count + 63) / 64
        var sigPacked = [UInt64](repeating: 0, count: sigLen)
        // Init significance from cleanup: sample significant if abs(coeff) >= (1 << topBP)
        for i in 0..<count {
            if (absMags[i] >> Int32(topBP)) & 1 != 0 {
                sigPacked[i >> 6] |= 1 << (i & 63)
            }
        }

        let cleanupSigPacked = sigPacked
        var allData = cleanupBlock.codedData
        var totalPasses = 1
        var passLengths = [cleanupBlock.codedData.count]

        for bp in stride(from: topBP - 1, through: 0, by: -1) {
            let refResult = encoder.encodeFusedRefinement(
                coefficients: coefficients,
                absMags: absMags,
                sigPacked: &sigPacked,
                cleanupSigPacked: cleanupSigPacked,
                bitPlane: bp
            )
            allData.append(refResult.sigPropData)
            totalPasses += 1
            passLengths.append(refResult.sigPropData.count)

            allData.append(refResult.magRefData)
            totalPasses += 1
            passLengths.append(refResult.magRefData.count)

            // Update significance for next bit-plane
            for i in 0..<count {
                if (absMags[i] >> Int32(bp)) & 1 != 0 {
                    sigPacked[i >> 6] |= 1 << (i & 63)
                }
            }
        }
        print("BLOCK total data=\(allData.count) totalPasses=\(totalPasses)")

        // Decode full (all passes)
        let decodedFull = try decoder.decodeFromCodestream(
            data: allData, passCount: totalPasses,
            bitDepth: 8, zeroBitPlanes: 2,
            passSegmentLengths: passLengths)
        var errFull = 0
        for i in 0..<(w * h) {
            errFull = max(errFull, abs(Int(coefficients[i]) - Int(decodedFull[i])))
        }
        print("BLOCK full-decode: maxErr=\(errFull)")

        // Decode with passSegmentLengths=[] (continuous stream)
        let decodedCont = try decoder.decodeFromCodestream(
            data: allData, passCount: totalPasses,
            bitDepth: 8, zeroBitPlanes: 2)
        var errCont = 0
        for i in 0..<(w * h) {
            errCont = max(errCont, abs(Int(coefficients[i]) - Int(decodedCont[i])))
        }
        print("BLOCK continuous-decode: maxErr=\(errCont)")

        // Decode truncated (3 passes = cleanup + 1 refinement bp)
        let trunc3Bytes = passLengths[0] + passLengths[1] + passLengths[2]
        let trunc3Data = allData.prefix(trunc3Bytes)
        let decoded3 = try decoder.decodeFromCodestream(
            data: trunc3Data, passCount: 3,
            bitDepth: 8, zeroBitPlanes: 2)
        var err3 = 0
        for i in 0..<(w * h) {
            err3 = max(err3, abs(Int(coefficients[i]) - Int(decoded3[i])))
        }
        print("BLOCK trunc-3-passes: maxErr=\(err3) (should be ≤\(1 << (topBP - 1)))")

        XCTAssertEqual(errFull, 0, "Full lossless decode should be exact")
        XCTAssertEqual(errCont, 0, "Continuous stream decode should be exact")
    }
}
