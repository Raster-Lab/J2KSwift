//
// Benchmark.swift
// J2KSwift
//
/// Benchmark command implementation for CPU, GPU, and HTJ2K encoding/decoding
/// performance measurement with automatic GPU availability detection and fallback.

import Foundation
import J2KCore
import J2KCodec
#if canImport(Metal)
import Metal
#endif

extension J2KCLI {

    // MARK: - GPU Availability

    /// Detects whether Metal GPU acceleration is available on the current platform.
    ///
    /// Uses a runtime check via `MTLCreateSystemDefaultDevice()` when Metal is
    /// available at compile time, which handles headless systems where Metal is
    /// importable but no GPU device exists. On platforms without Metal (Linux),
    /// this returns false at compile time.
    ///
    /// When GPU is unavailable, the GPU pipeline (`encodeGPU`/`decodeGPU`)
    /// transparently falls back to CPU. The benchmark reports the fallback
    /// so users understand the results.
    private static var isGPUAvailable: Bool {
        #if canImport(Metal)
        if let _ = MTLCreateSystemDefaultDevice() {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    /// Returns a description of the GPU backend for display.
    private static var gpuBackendDescription: String {
        #if canImport(Metal)
        return isGPUAvailable ? "Metal" : "Metal (no device)"
        #else
        return "none"
        #endif
    }

    // MARK: - Benchmark Command

    /// Benchmark command: measure encoding/decoding performance across backends.
    ///
    /// Supports CPU, GPU, and HTJ2K modes. When `--gpu` is requested but Metal
    /// is unavailable, the benchmark runs with CPU fallback and clearly reports
    /// that GPU was not available.
    static func benchmarkCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printBenchmarkHelp()
            return
        }

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        let runs        = Int(options["r"] ?? options["runs"] ?? "3") ?? 3
        let warmupRuns  = Int(options["warmup"] ?? "1") ?? 1
        let outputPath  = options["o"] ?? options["output"]
        let encodeOnly  = options["encode-only"] != nil
        let decodeOnly  = options["decode-only"] != nil
        let compareOJ   = options["compare-openjpeg"] != nil
        let useGPU      = options["gpu"] != nil
        let useHTJ2K    = options["htj2k"] != nil
        let compareAll  = options["compare-all"] != nil
        let outputFmt   = options["format"] ?? "text"

        // Detect GPU availability
        let gpuAvailable = isGPUAvailable

        // Load input image
        if outputFmt == "text" { print("Loading test image: \(inputPath)") }
        let image = try loadImage(from: inputPath)
        if outputFmt == "text" {
            print("  Image: \(image.width)×\(image.height), \(image.componentCount) component(s)")
            print("  Pixels: \(image.width * image.height)")
            print("")
        }

        // Detect and report platform capabilities
        if outputFmt == "text" {
            print("Platform:")
            #if canImport(Metal)
            print("  GPU: Metal (available)")
            #else
            print("  GPU: not available (Metal not supported on this platform)")
            #endif
            #if arch(arm64)
            print("  SIMD: NEON")
            #elseif arch(x86_64)
            print("  SIMD: SSE/AVX")
            #else
            print("  SIMD: generic")
            #endif
            print("")
        }

        // Configure encoder
        let config = makeEncodingConfiguration(from: options, outputFmt: outputFmt)

        var results: [String: Any] = [
            "image": [
                "path":       inputPath,
                "width":      image.width,
                "height":     image.height,
                "components": image.componentCount,
                "pixels":     image.width * image.height,
            ],
            "runs":    runs,
            "warmup":  warmupRuns,
            "gpu_available": gpuAvailable,
            "gpu_backend": gpuBackendDescription,
        ]

        // Determine which benchmark modes to run
        var modes: [BenchmarkMode] = []
        if compareAll {
            modes.append(.cpu)
            modes.append(.gpu)
            modes.append(.htj2k)
            modes.append(.gpuHtj2k)
        } else if useGPU && useHTJ2K {
            modes.append(.gpuHtj2k)
        } else if useGPU {
            modes.append(.gpu)
        } else if useHTJ2K {
            modes.append(.htj2k)
        } else {
            modes.append(.cpu)
        }
        if compareOJ {
            modes.append(.openjpeg)
        }

        // Run benchmarks for each mode
        for mode in modes {
            // OpenJPEG uses subprocess CLI tools — handled separately
            if mode == .openjpeg {
                if outputFmt == "text" {
                    print("═══════════════════════════════════════════════════════════════")
                    print(" \(mode.title)")
                    print(" Note: times include process startup overhead (~5–20 ms)")
                    print("═══════════════════════════════════════════════════════════════")
                    print("")
                }
                do {
                    let ojResults = try benchmarkOpenJPEG(
                        image: image,
                        runs: runs,
                        warmupRuns: warmupRuns,
                        encodeOnly: encodeOnly,
                        decodeOnly: decodeOnly,
                        outputFmt: outputFmt
                    )
                    if let encStats = ojResults["encode"] { results["openjpeg_encode"] = encStats }
                    if let decStats = ojResults["decode"] { results["openjpeg_decode"] = decStats }
                } catch {
                    print("OpenJPEG benchmark failed: \(error)")
                }
                if outputFmt == "text" { print("") }
                continue
            }

            // Warn about GPU fallback if needed
            if (mode == .gpu || mode == .gpuHtj2k) && !gpuAvailable && outputFmt == "text" {
                print("⚠ GPU requested but not available — running with CPU fallback")
                print("  (GPU pipeline will use CPU implementations for all stages)")
                print("")
            }

            // Configure HTJ2K if needed
            var modeConfig = config
            if mode == .htj2k || mode == .gpuHtj2k {
                modeConfig.useHTJ2K = true
            }

            let prefix = mode.label
            if outputFmt == "text" {
                print("═══════════════════════════════════════════════════════════════")
                print(" \(mode.title)")
                if mode == .gpu || mode == .gpuHtj2k {
                    print(" Backend: \(gpuAvailable ? "Metal GPU" : "CPU fallback (no GPU)")")
                }
                print("═══════════════════════════════════════════════════════════════")
                print("")
            }

            // Benchmark encoding
            var encodedData: Data?
            if !decodeOnly {
                let encodeResult = try await benchmarkEncode(
                    image: image,
                    config: modeConfig,
                    useGPU: mode == .gpu || mode == .gpuHtj2k,
                    runs: runs,
                    warmupRuns: warmupRuns,
                    outputFmt: outputFmt
                )
                encodedData = encodeResult.data
                results["\(prefix)_encode"] = encodeResult.stats
            }

            // Benchmark decoding
            if !encodeOnly {
                if encodedData == nil {
                    let encoder = J2KEncoder(encodingConfiguration: modeConfig)
                    if mode == .gpu || mode == .gpuHtj2k {
                        encodedData = try await encoder.encodeGPU(image)
                    } else {
                        encodedData = try await encoder.encode(image)
                    }
                }
                guard let dataToUse = encodedData else {
                    throw J2KError.internalError("No encoded data available for decoding benchmark")
                }

                let decodeResult = try await benchmarkDecode(
                    data: dataToUse,
                    useGPU: mode == .gpu || mode == .gpuHtj2k,
                    runs: runs,
                    warmupRuns: warmupRuns,
                    pixels: image.width * image.height,
                    outputFmt: outputFmt
                )
                results["\(prefix)_decode"] = decodeResult
            }

            if outputFmt == "text" { print("") }
        }

        // Print comparison table when multiple modes were benchmarked
        if modes.count > 1 && outputFmt == "text" {
            printComparisonTable(results: results, modes: modes, gpuAvailable: gpuAvailable)
        }

        // Output results
        switch outputFmt {
        case "json":
            if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
               let str = String(data: jsonData, encoding: .utf8) {
                print(str)
            }
        case "csv":
            printCSV(results, modes: modes)
        default:
            if outputFmt == "text" { print("Benchmark complete!") }
        }

        // Save report if requested
        if let outPath = outputPath {
            let ext = URL(fileURLWithPath: outPath).pathExtension.lowercased()
            let saveData: Data
            if ext == "csv" {
                let csv = buildCSVString(results, modes: modes)
                saveData = csv.data(using: .utf8) ?? Data()
            } else {
                saveData = (try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)) ?? Data()
            }
            try saveData.write(to: URL(fileURLWithPath: outPath))
            print("Saved benchmark results to: \(outPath)")
        }
    }

    // MARK: - Benchmark Modes

    private enum BenchmarkMode: String {
        case cpu        = "cpu"
        case gpu        = "gpu"
        case htj2k      = "htj2k"
        case gpuHtj2k   = "gpu_htj2k"
        case openjpeg   = "openjpeg"

        var label: String { rawValue }

        var title: String {
            switch self {
            case .cpu:        return "CPU Benchmark (Part 1 EBCOT)"
            case .gpu:        return "GPU Benchmark (Metal Pipeline)"
            case .htj2k:      return "HTJ2K Benchmark (Part 15 FBCOT)"
            case .gpuHtj2k:   return "GPU+HTJ2K Benchmark (Metal DWT + FBCOT)"
            case .openjpeg:   return "OpenJPEG Benchmark (opj_compress / opj_decompress)"
            }
        }
    }

    // MARK: - Encoding Configuration

    private static func makeEncodingConfiguration(
        from options: [String: String],
        outputFmt: String
    ) -> J2KEncodingConfiguration {
        if let preset = options["preset"] {
            switch preset {
            case "fast":
                if outputFmt == "text" { print("Using preset: fast\n") }
                return J2KEncodingPreset.fast.configuration()
            case "balanced":
                if outputFmt == "text" { print("Using preset: balanced\n") }
                return J2KEncodingPreset.balanced.configuration()
            case "quality":
                if outputFmt == "text" { print("Using preset: quality\n") }
                return J2KEncodingPreset.quality.configuration()
            default:
                print("Error: Unknown preset '\(preset)'")
                exit(1)
            }
        }
        return J2KEncodingConfiguration()
    }

    // MARK: - Encode Benchmark

    private struct EncodeBenchmarkResult {
        let data: Data
        let stats: [String: Any]
    }

    private static func benchmarkEncode(
        image: J2KImage,
        config: J2KEncodingConfiguration,
        useGPU: Bool,
        runs: Int,
        warmupRuns: Int,
        outputFmt: String
    ) async throws -> EncodeBenchmarkResult {
        let encoder = J2KEncoder(encodingConfiguration: config)

        // Warm-up
        if warmupRuns > 0 && outputFmt == "text" { print("Warming up encoder (\(warmupRuns) run(s))…") }
        for _ in 0..<warmupRuns {
            if useGPU {
                _ = try await encoder.encodeGPU(image)
            } else {
                _ = try await encoder.encode(image)
            }
        }

        if outputFmt == "text" { print("Benchmarking encoding (\(runs) runs)…") }
        var encodeTimes: [Double] = []
        var firstData: Data?

        for run in 1...runs {
            let start = Date()
            let data: Data
            if useGPU {
                data = try await encoder.encodeGPU(image)
            } else {
                data = try await encoder.encode(image)
            }
            let elapsed = Date().timeIntervalSince(start)
            encodeTimes.append(elapsed)

            if run == 1 {
                firstData = data
                let inputBytes = image.width * image.height * image.componentCount
                let ratio = Double(inputBytes) / Double(data.count)
                if outputFmt == "text" {
                    print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms (compressed to \(formatBytes(data.count)), ratio \(String(format: "%.2f", ratio)):1)")
                }
            } else if outputFmt == "text" {
                print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms")
            }
        }

        guard let encoded = firstData else {
            throw J2KError.internalError("Encoding produced no data")
        }

        let stats = computeStats(encodeTimes)
        if outputFmt == "text" {
            printStats(label: "Encode", stats: stats, pixels: image.width * image.height)
        }

        return EncodeBenchmarkResult(
            data: encoded,
            stats: buildStatsDict(stats, times: encodeTimes, pixels: image.width * image.height, compressedSize: encoded.count)
        )
    }

    // MARK: - Decode Benchmark

    private static func benchmarkDecode(
        data: Data,
        useGPU: Bool,
        runs: Int,
        warmupRuns: Int,
        pixels: Int,
        outputFmt: String
    ) async throws -> [String: Any] {
        let decoder = J2KDecoder()

        // Warm-up
        if warmupRuns > 0 && outputFmt == "text" { print("Warming up decoder (\(warmupRuns) run(s))…") }
        for _ in 0..<warmupRuns {
            if useGPU {
                _ = try await decoder.decodeGPU(data)
            } else {
                _ = try await decoder.decode(data)
            }
        }

        if outputFmt == "text" { print("Benchmarking decoding (\(runs) runs)…") }
        var decodeTimes: [Double] = []

        for run in 1...runs {
            let start = Date()
            if useGPU {
                _ = try await decoder.decodeGPU(data)
            } else {
                _ = try await decoder.decode(data)
            }
            let elapsed = Date().timeIntervalSince(start)
            decodeTimes.append(elapsed)
            if outputFmt == "text" { print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms") }
        }

        let stats = computeStats(decodeTimes)
        if outputFmt == "text" {
            printStats(label: "Decode", stats: stats, pixels: pixels)
        }

        return buildStatsDict(stats, times: decodeTimes, pixels: pixels, compressedSize: nil)
    }

    // MARK: - OpenJPEG Benchmark

    private static func benchmarkOpenJPEG(
        image: J2KImage,
        runs: Int,
        warmupRuns: Int,
        encodeOnly: Bool,
        decodeOnly: Bool,
        outputFmt: String
    ) throws -> [String: Any] {
        guard let compressorPath = OpenJPEGAvailability.findTool("opj_compress") else {
            throw J2KError.internalError("opj_compress not found — install via: brew install openjpeg")
        }
        guard let decompressorPath = OpenJPEGAvailability.findTool("opj_decompress") else {
            throw J2KError.internalError("opj_decompress not found — install via: brew install openjpeg")
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let nComps = image.componentCount
        let ext    = nComps == 3 ? "ppm" : "pgm"
        let tmpInputURL   = tmpDir.appendingPathComponent("j2k_bench_oj_input.\(ext)")
        let tmpOutputURL  = tmpDir.appendingPathComponent("j2k_bench_oj_output.j2k")
        let tmpDecodedURL = tmpDir.appendingPathComponent("j2k_bench_oj_decoded.\(ext)")

        defer {
            try? FileManager.default.removeItem(at: tmpInputURL)
            try? FileManager.default.removeItem(at: tmpOutputURL)
            try? FileManager.default.removeItem(at: tmpDecodedURL)
        }

        // Write the input image to a temp file once
        if nComps == 3 {
            try savePPM(image, to: tmpInputURL)
        } else {
            try savePGM(image, to: tmpInputURL)
        }

        var results: [String: Any] = [:]
        let pixels = image.width * image.height

        // ── Encode ──────────────────────────────────────────────────────────
        if !decodeOnly {
            let encArgs = ["-i", tmpInputURL.path, "-o", tmpOutputURL.path]

            if warmupRuns > 0 && outputFmt == "text" {
                print("Warming up OpenJPEG encoder (\(warmupRuns) run(s))…")
            }
            for _ in 0..<warmupRuns {
                let r = OpenJPEGCLIWrapper.runTool(
                    toolPath: compressorPath, arguments: encArgs, outputPath: tmpOutputURL.path)
                if !r.success {
                    throw J2KError.internalError("opj_compress warmup failed:\n\(r.stderr)")
                }
            }

            if outputFmt == "text" { print("Benchmarking OpenJPEG encoding (\(runs) runs)…") }
            var encodeTimes: [Double] = []
            var firstSize: Int?

            for run in 1...runs {
                let r = OpenJPEGCLIWrapper.runTool(
                    toolPath: compressorPath, arguments: encArgs, outputPath: tmpOutputURL.path)
                if !r.success {
                    throw J2KError.internalError("opj_compress run \(run) failed:\n\(r.stderr)")
                }
                encodeTimes.append(r.elapsedTime)

                if run == 1 {
                    let sz = (try? FileManager.default.attributesOfItem(
                        atPath: tmpOutputURL.path))?[.size] as? Int
                    firstSize = sz
                    let inputBytes = pixels * nComps
                    let ratio = sz.map { Double(inputBytes) / Double($0) } ?? 0
                    if outputFmt == "text" {
                        let sizeStr = sz.map { formatBytes($0) } ?? "unknown"
                        print("  Run \(run): \(String(format: "%.3f", r.elapsedTime * 1000)) ms "
                            + "(compressed to \(sizeStr), ratio \(String(format: "%.2f", ratio)):1)")
                    }
                } else if outputFmt == "text" {
                    print("  Run \(run): \(String(format: "%.3f", r.elapsedTime * 1000)) ms")
                }
            }

            let stats = computeStats(encodeTimes)
            if outputFmt == "text" { printStats(label: "OpenJPEG Encode", stats: stats, pixels: pixels) }
            results["encode"] = buildStatsDict(stats, times: encodeTimes, pixels: pixels,
                                               compressedSize: firstSize)
        }

        // ── Decode ──────────────────────────────────────────────────────────
        if !encodeOnly {
            // If encode was skipped, produce the encoded file now
            if !FileManager.default.fileExists(atPath: tmpOutputURL.path) {
                let r = OpenJPEGCLIWrapper.runTool(
                    toolPath: compressorPath,
                    arguments: ["-i", tmpInputURL.path, "-o", tmpOutputURL.path],
                    outputPath: tmpOutputURL.path)
                if !r.success {
                    throw J2KError.internalError("opj_compress (for decode setup) failed:\n\(r.stderr)")
                }
            }

            let decArgs = ["-i", tmpOutputURL.path, "-o", tmpDecodedURL.path]

            if warmupRuns > 0 && outputFmt == "text" {
                print("Warming up OpenJPEG decoder (\(warmupRuns) run(s))…")
            }
            for _ in 0..<warmupRuns {
                let r = OpenJPEGCLIWrapper.runTool(
                    toolPath: decompressorPath, arguments: decArgs, outputPath: tmpDecodedURL.path)
                if !r.success {
                    throw J2KError.internalError("opj_decompress warmup failed:\n\(r.stderr)")
                }
            }

            if outputFmt == "text" { print("Benchmarking OpenJPEG decoding (\(runs) runs)…") }
            var decodeTimes: [Double] = []

            for run in 1...runs {
                let r = OpenJPEGCLIWrapper.runTool(
                    toolPath: decompressorPath, arguments: decArgs, outputPath: tmpDecodedURL.path)
                if !r.success {
                    throw J2KError.internalError("opj_decompress run \(run) failed:\n\(r.stderr)")
                }
                decodeTimes.append(r.elapsedTime)
                if outputFmt == "text" {
                    print("  Run \(run): \(String(format: "%.3f", r.elapsedTime * 1000)) ms")
                }
            }

            let stats = computeStats(decodeTimes)
            if outputFmt == "text" { printStats(label: "OpenJPEG Decode", stats: stats, pixels: pixels) }
            results["decode"] = buildStatsDict(stats, times: decodeTimes, pixels: pixels,
                                               compressedSize: nil)
        }

        return results
    }

    // MARK: - Comparison Table

    private static func printComparisonTable(
        results: [String: Any],
        modes: [BenchmarkMode],
        gpuAvailable: Bool
    ) {
        print("═══════════════════════════════════════════════════════════════")
        print(" Comparison Summary")
        print("═══════════════════════════════════════════════════════════════")
        print("")

        // Safe column-padding helpers (avoids %s crash with Swift strings)
        func padLeft(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : String(repeating: " ", count: w - s.count) + s
        }
        func padRight(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }

        // Header
        var header = padRight("Metric", 12)
        for mode in modes {
            var label = mode.label.uppercased()
            if (mode == .gpu || mode == .gpuHtj2k) && !gpuAvailable { label += "*" }
            header += "  " + padLeft(label, 14)
        }
        print(header)
        print(String(repeating: "─", count: 12 + modes.count * 16))

        // Encode row
        var encLine = padRight("Encode (ms)", 12)
        for mode in modes {
            if let d = results["\(mode.label)_encode"] as? [String: Any],
               let avg = d["average_ms"] as? Double {
                encLine += "  " + padLeft(String(format: "%.3f", avg), 14)
            } else {
                encLine += "  " + padLeft("—", 14)
            }
        }
        print(encLine)

        // Decode row
        var decLine = padRight("Decode (ms)", 12)
        for mode in modes {
            if let d = results["\(mode.label)_decode"] as? [String: Any],
               let avg = d["average_ms"] as? Double {
                decLine += "  " + padLeft(String(format: "%.3f", avg), 14)
            } else {
                decLine += "  " + padLeft("—", 14)
            }
        }
        print(decLine)

        // Throughput rows
        var encTPLine = padRight("Enc MP/s", 12)
        for mode in modes {
            if let d = results["\(mode.label)_encode"] as? [String: Any],
               let mpps = d["throughput_mpps"] as? Double {
                encTPLine += "  " + padLeft(String(format: "%.2f", mpps), 14)
            } else {
                encTPLine += "  " + padLeft("—", 14)
            }
        }
        print(encTPLine)

        var decTPLine = padRight("Dec MP/s", 12)
        for mode in modes {
            if let d = results["\(mode.label)_decode"] as? [String: Any],
               let mpps = d["throughput_mpps"] as? Double {
                decTPLine += "  " + padLeft(String(format: "%.2f", mpps), 14)
            } else {
                decTPLine += "  " + padLeft("—", 14)
            }
        }
        print(decTPLine)

        // Speedup relative to first mode
        if modes.count > 1 {
            print("")
            let baseline = modes[0]
            let baseEncAvg = (results["\(baseline.label)_encode"] as? [String: Any])?["average_ms"] as? Double
            let baseDecAvg = (results["\(baseline.label)_decode"] as? [String: Any])?["average_ms"] as? Double

            var speedLine = padRight("Speedup", 12)
            for mode in modes {
                if mode == baseline {
                    speedLine += "  " + padLeft("1.00x (base)", 14)
                } else {
                    let encAvg = (results["\(mode.label)_encode"] as? [String: Any])?["average_ms"] as? Double
                    let decAvg = (results["\(mode.label)_decode"] as? [String: Any])?["average_ms"] as? Double
                    if let be = baseEncAvg, let ce = encAvg, ce > 0 {
                        let speedup = be / ce
                        speedLine += "  " + padLeft(String(format: "%.2fx enc", speedup), 14)
                    } else if let bd = baseDecAvg, let cd = decAvg, cd > 0 {
                        let speedup = bd / cd
                        speedLine += "  " + padLeft(String(format: "%.2fx dec", speedup), 14)
                    } else {
                        speedLine += "  " + padLeft("—", 14)
                    }
                }
            }
            print(speedLine)
        }

        print("")
        if (modes.contains(.gpu) || modes.contains(.gpuHtj2k)) && !gpuAvailable {
            print("* GPU column ran with CPU fallback (Metal GPU not available)")
        }
        print("")
    }

    // MARK: - Statistics

    private struct Stats {
        let avg: Double
        let median: Double
        let min: Double
        let max: Double
        let stddev: Double
    }

    private static func computeStats(_ times: [Double]) -> Stats {
        guard !times.isEmpty else {
            return Stats(avg: 0, median: 0, min: 0, max: 0, stddev: 0)
        }
        let sorted = times.sorted()
        let n = Double(times.count)
        let avg = times.reduce(0, +) / n
        let median: Double
        if times.count == 1 {
            median = sorted[0]
        } else if times.count.isMultiple(of: 2) {
            median = (sorted[times.count / 2 - 1] + sorted[times.count / 2]) / 2
        } else {
            median = sorted[times.count / 2]
        }
        let variance = times.count > 1
            ? times.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(times.count - 1)
            : 0.0
        return Stats(
            avg: avg,
            median: median,
            min: sorted[0],
            max: sorted[sorted.count - 1],
            stddev: variance.squareRoot()
        )
    }

    private static func printStats(label: String, stats: Stats, pixels: Int) {
        print("\n  \(label) Statistics:")
        print("    Average: \(String(format: "%7.3f", stats.avg * 1000)) ms")
        print("    Median:  \(String(format: "%7.3f", stats.median * 1000)) ms")
        print("    Min:     \(String(format: "%7.3f", stats.min * 1000)) ms")
        print("    Max:     \(String(format: "%7.3f", stats.max * 1000)) ms")
        print("    Std Dev: \(String(format: "%7.3f", stats.stddev * 1000)) ms")
        let mpps = stats.avg > 0 ? Double(pixels) / 1_000_000 / stats.avg : 0
        print("    Throughput: \(String(format: "%.2f", mpps)) MP/s\n")
    }

    private static func buildStatsDict(
        _ stats: Stats, times: [Double], pixels: Int, compressedSize: Int?
    ) -> [String: Any] {
        var d: [String: Any] = [
            "runs":            times.map { $0 * 1000 },
            "average_ms":      stats.avg    * 1000,
            "median_ms":       stats.median * 1000,
            "min_ms":          stats.min    * 1000,
            "max_ms":          stats.max    * 1000,
            "stddev_ms":       stats.stddev * 1000,
            "throughput_mpps": stats.avg > 0 ? Double(pixels) / 1_000_000 / stats.avg : 0,
        ]
        if let cs = compressedSize { d["compressed_size"] = cs }
        return d
    }

    // MARK: - CSV output

    private static func printCSV(_ results: [String: Any], modes: [BenchmarkMode]) {
        print(buildCSVString(results, modes: modes))
    }

    private static func buildCSVString(_ results: [String: Any], modes: [BenchmarkMode]) -> String {
        var lines = ["mode,direction,average_ms,median_ms,min_ms,max_ms,stddev_ms,throughput_mpps,compressed_size,gpu_available"]
        let gpuAvail = results["gpu_available"] as? Bool ?? false

        for mode in modes {
            for direction in ["encode", "decode"] {
                let key = "\(mode.label)_\(direction)"
                guard let d = results[key] as? [String: Any] else { continue }
                let avg  = d["average_ms"]      as? Double ?? 0
                let med  = d["median_ms"]       as? Double ?? 0
                let mn   = d["min_ms"]          as? Double ?? 0
                let mx   = d["max_ms"]          as? Double ?? 0
                let std  = d["stddev_ms"]       as? Double ?? 0
                let mpps = d["throughput_mpps"] as? Double ?? 0
                let cs   = d["compressed_size"] as? Int
                let csStr = cs.map { String($0) } ?? ""
                lines.append("\(mode.label),\(direction),\(String(format: "%.3f", avg)),\(String(format: "%.3f", med)),\(String(format: "%.3f", mn)),\(String(format: "%.3f", mx)),\(String(format: "%.3f", std)),\(String(format: "%.2f", mpps)),\(csStr),\(gpuAvail)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Help

    private static func printBenchmarkHelp() {
        print("""
        j2k benchmark - Measure encoding/decoding performance

        USAGE:
            j2k benchmark -i <input> [options]

        MODES:
            (default)                   CPU-only Part 1 EBCOT benchmark
            --gpu                       GPU-accelerated pipeline (falls back to
                                        CPU when Metal is unavailable)
            --htj2k                     HTJ2K Part 15 FBCOT benchmark
            --compare-all               Run CPU, GPU, and HTJ2K side-by-side
                                        with a comparison summary table
            --compare-openjpeg          Add OpenJPEG (opj_compress/opj_decompress)
                                        to the benchmark for a side-by-side
                                        comparison (requires openjpeg installed)

        OPTIONS:
            -i, --input PATH            Input image file
            -r, --runs N                Measurement runs (default: 3)
            --warmup N                  Warm-up runs before measurement (default: 1)
            -o, --output PATH           Output report file
            --format text|json|csv      Output format (default: text)
            --encode-only               Only benchmark encoding
            --decode-only               Only benchmark decoding
            --preset fast|balanced|quality  Encoding preset

        OPENJPEG NOTES:
            OpenJPEG times are measured as wall-clock time for the full
            opj_compress/opj_decompress process, including ~5–20 ms of
            process startup overhead. Warmup runs ensure input files are
            in the OS page cache before measurement begins.
            Install OpenJPEG with: brew install openjpeg

        GPU NOTES:
            When --gpu or --compare-all is used and Metal is not available
            (e.g. on Linux or CI servers), the GPU pipeline automatically
            falls back to CPU. The benchmark clearly reports this so results
            are not misleading.

        EXAMPLES:
            j2k benchmark -i test.pgm -r 10
            j2k benchmark -i test.pgm --gpu
            j2k benchmark -i test.pgm --htj2k --encode-only
            j2k benchmark -i test.pgm --compare-all --format csv -o results.csv
            j2k benchmark -i test.pgm --compare-openjpeg
            j2k benchmark -i test.pgm --compare-all --compare-openjpeg -r 5
        """)
    }
}
