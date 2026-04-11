//
// Benchmark.swift
// J2KSwift
//
/// Benchmark command implementation for CPU, GPU, and HTJ2K encoding/decoding
/// performance measurement with automatic GPU availability detection and fallback.

import Foundation
import J2KCore
import J2KCodec

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

        let inputPath   = options["i"] ?? options["input"]
        let sizesStr    = options["sizes"]
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

        // Multi-size mode: --sizes 256,512,1024,2048
        if let sizesStr = sizesStr {
            let sizes = parseSizes(sizesStr)
            guard !sizes.isEmpty else {
                print("Error: Invalid --sizes value. Use comma-separated dimensions, e.g. --sizes 256,512,1024,2048")
                exit(1)
            }
            try await runMultiSizeBenchmark(
                sizes: sizes, options: options, runs: runs, warmupRuns: warmupRuns,
                outputPath: outputPath, encodeOnly: encodeOnly, decodeOnly: decodeOnly,
                compareOJ: compareOJ, useGPU: useGPU, useHTJ2K: useHTJ2K,
                compareAll: compareAll, outputFmt: outputFmt
            )
            return
        }

        guard let inputPath = inputPath else {
            print("Error: Missing required argument: -i/--input or --sizes")
            exit(1)
        }

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
        } else if useGPU && useHTJ2K {
            modes.append(.gpu)
            modes.append(.htj2k)
        } else if useGPU {
            modes.append(.gpu)
        } else if useHTJ2K {
            modes.append(.htj2k)
        } else {
            modes.append(.cpu)
        }

        // Run benchmarks for each mode
        for mode in modes {
            // Warn about GPU fallback if needed
            if mode == .gpu && !gpuAvailable && outputFmt == "text" {
                print("⚠ GPU requested but not available — running with CPU fallback")
                print("  (GPU pipeline will use CPU implementations for all stages)")
                print("")
            }

            // Configure HTJ2K if needed
            var modeConfig = config
            if mode == .htj2k {
                modeConfig.useHTJ2K = true
            }

            let prefix = mode.label
            if outputFmt == "text" {
                print("═══════════════════════════════════════════════════════════════")
                print(" \(mode.title)")
                if mode == .gpu {
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
                    useGPU: mode == .gpu,
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
                    if mode == .gpu {
                        encodedData = try await encoder.encodeGPU(image)
                    } else {
                        encodedData = try encoder.encode(image)
                    }
                }
                guard let dataToUse = encodedData else {
                    throw J2KError.internalError("No encoded data available for decoding benchmark")
                }

                let decodeResult = try await benchmarkDecode(
                    data: dataToUse,
                    useGPU: mode == .gpu,
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

        if compareOJ {
            print("Note: OpenJPEG comparison is not available on this platform.")
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
        case cpu   = "cpu"
        case gpu   = "gpu"
        case htj2k = "htj2k"

        var label: String { rawValue }

        var title: String {
            switch self {
            case .cpu:   return "CPU Benchmark (Part 1 EBCOT)"
            case .gpu:   return "GPU Benchmark (Metal Pipeline)"
            case .htj2k: return "HTJ2K Benchmark (Part 15 FBCOT)"
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
                _ = try encoder.encode(image)
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
                data = try encoder.encode(image)
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
                _ = try decoder.decode(data)
            }
        }

        if outputFmt == "text" { print("Benchmarking decoding (\(runs) runs)…") }
        var decodeTimes: [Double] = []

        for run in 1...runs {
            let start = Date()
            if useGPU {
                _ = try await decoder.decodeGPU(data)
            } else {
                _ = try decoder.decode(data)
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

        // Header
        var header = String(format: "%-12s", "Metric")
        for mode in modes {
            var label = mode.label.uppercased()
            if mode == .gpu && !gpuAvailable {
                label += "*"
            }
            header += String(format: "  %14s", label)
        }
        print(header)
        print(String(repeating: "─", count: 12 + modes.count * 16))

        // Encode row
        var encLine = String(format: "%-12s", "Encode (ms)")
        for mode in modes {
            if let d = results["\(mode.label)_encode"] as? [String: Any],
               let avg = d["average_ms"] as? Double {
                encLine += String(format: "  %14.3f", avg)
            } else {
                encLine += String(format: "  %14s", "—")
            }
        }
        print(encLine)

        // Decode row
        var decLine = String(format: "%-12s", "Decode (ms)")
        for mode in modes {
            if let d = results["\(mode.label)_decode"] as? [String: Any],
               let avg = d["average_ms"] as? Double {
                decLine += String(format: "  %14.3f", avg)
            } else {
                decLine += String(format: "  %14s", "—")
            }
        }
        print(decLine)

        // Throughput rows
        var encTPLine = String(format: "%-12s", "Enc MP/s")
        for mode in modes {
            if let d = results["\(mode.label)_encode"] as? [String: Any],
               let mpps = d["throughput_mpps"] as? Double {
                encTPLine += String(format: "  %14.2f", mpps)
            } else {
                encTPLine += String(format: "  %14s", "—")
            }
        }
        print(encTPLine)

        var decTPLine = String(format: "%-12s", "Dec MP/s")
        for mode in modes {
            if let d = results["\(mode.label)_decode"] as? [String: Any],
               let mpps = d["throughput_mpps"] as? Double {
                decTPLine += String(format: "  %14.2f", mpps)
            } else {
                decTPLine += String(format: "  %14s", "—")
            }
        }
        print(decTPLine)

        // Speedup relative to first mode
        if modes.count > 1 {
            print("")
            let baseline = modes[0]
            let baseEncAvg = (results["\(baseline.label)_encode"] as? [String: Any])?["average_ms"] as? Double
            let baseDecAvg = (results["\(baseline.label)_decode"] as? [String: Any])?["average_ms"] as? Double

            var speedLine = String(format: "%-12s", "Speedup")
            for mode in modes {
                if mode == baseline {
                    speedLine += String(format: "  %14s", "1.00x (base)")
                } else {
                    let encAvg = (results["\(mode.label)_encode"] as? [String: Any])?["average_ms"] as? Double
                    let decAvg = (results["\(mode.label)_decode"] as? [String: Any])?["average_ms"] as? Double
                    // Use encode speedup if available, else decode
                    if let be = baseEncAvg, let ce = encAvg, ce > 0 {
                        let speedup = be / ce
                        speedLine += String(format: "  %11.2fx enc", speedup)
                    } else if let bd = baseDecAvg, let cd = decAvg, cd > 0 {
                        let speedup = bd / cd
                        speedLine += String(format: "  %11.2fx dec", speedup)
                    } else {
                        speedLine += String(format: "  %14s", "—")
                    }
                }
            }
            print(speedLine)
        }

        print("")
        if modes.contains(.gpu) && !gpuAvailable {
            print("* GPU column ran with CPU fallback (Metal GPU not available)")
        }
        print("")
    }

    // MARK: - Multi-Size Benchmark

    /// Parses a comma-separated list of square image dimensions.
    ///
    /// - Parameter str: Comma-separated dimensions, e.g. "256,512,1024,2048".
    /// - Returns: Array of parsed dimensions.
    private static func parseSizes(_ str: String) -> [Int] {
        str.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }
    }

    /// Generates a synthetic grayscale test image with pseudo-random data.
    ///
    /// Uses a linear congruential generator seeded with the dimension to
    /// produce deterministic but non-trivial pixel data that exercises
    /// the full encoding pipeline (DWT, quantization, entropy coding).
    ///
    /// - Parameter size: The width and height of the square image.
    /// - Returns: A grayscale `J2KImage` of the requested size.
    private static func generateSyntheticImage(size: Int) -> J2KImage {
        let pixelCount = size * size
        var data = Data(count: pixelCount)
        // Deterministic pseudo-random fill using LCG
        var state: UInt64 = UInt64(size) &* 2654435761
        data.withUnsafeMutableBytes { ptr in
            let buf = ptr.bindMemory(to: UInt8.self)
            for i in 0..<pixelCount {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                buf[i] = UInt8(truncatingIfNeeded: state >> 33)
            }
        }
        let component = J2KComponent(
            index: 0, bitDepth: 8, signed: false,
            width: size, height: size, data: data
        )
        return J2KImage(width: size, height: size, components: [component])
    }

    /// Runs benchmarks across multiple image sizes using synthetic test images.
    ///
    /// For each size the encoder (and optionally decoder) is benchmarked.
    /// Results are collected into a single output with per-size rows in CSV
    /// mode, or per-size sections in text mode.
    private static func runMultiSizeBenchmark(
        sizes: [Int],
        options: [String: String],
        runs: Int,
        warmupRuns: Int,
        outputPath: String?,
        encodeOnly: Bool,
        decodeOnly: Bool,
        compareOJ: Bool,
        useGPU: Bool,
        useHTJ2K: Bool,
        compareAll: Bool,
        outputFmt: String
    ) async throws {
        let gpuAvailable = isGPUAvailable

        // Determine benchmark modes
        var modes: [BenchmarkMode] = []
        if compareAll {
            modes.append(.cpu)
            modes.append(.gpu)
            modes.append(.htj2k)
        } else if useGPU && useHTJ2K {
            modes.append(.gpu)
            modes.append(.htj2k)
        } else if useGPU {
            modes.append(.gpu)
        } else if useHTJ2K {
            modes.append(.htj2k)
        } else {
            modes.append(.cpu)
        }

        let config = makeEncodingConfiguration(from: options, outputFmt: outputFmt)

        if outputFmt == "text" {
            print("═══════════════════════════════════════════════════════════════")
            print(" Multi-Size Benchmark")
            print(" Sizes: \(sizes.map { "\($0)×\($0)" }.joined(separator: ", "))")
            print(" Runs: \(runs), Warmup: \(warmupRuns)")
            if gpuAvailable {
                print(" GPU: Metal")
            } else {
                print(" GPU: not available (CPU fallback)")
            }
            print("═══════════════════════════════════════════════════════════════")
            print("")
        }

        // Collect all rows: (name, mode, direction, stats dict)
        var allRows: [(name: String, mode: BenchmarkMode, direction: String, stats: [String: Any])] = []

        for size in sizes {
            let image = generateSyntheticImage(size: size)

            if outputFmt == "text" {
                print("───────────────────────────────────────────────────────────────")
                print(" Image: \(size)×\(size) (\(size * size) pixels)")
                print("───────────────────────────────────────────────────────────────")
                print("")
            }

            for mode in modes {
                var modeConfig = config
                if mode == .htj2k { modeConfig.useHTJ2K = true }

                if mode == .gpu && !gpuAvailable && outputFmt == "text" {
                    print("⚠ GPU requested but not available — running with CPU fallback\n")
                }

                let testName = "\(mode.label)_\(size)x\(size)"

                // Benchmark encoding
                var encodedData: Data?
                if !decodeOnly {
                    if outputFmt == "text" {
                        print("  \(mode.title) — Encode:")
                    }
                    let encodeResult = try await benchmarkEncode(
                        image: image, config: modeConfig, useGPU: mode == .gpu,
                        runs: runs, warmupRuns: warmupRuns, outputFmt: outputFmt
                    )
                    encodedData = encodeResult.data
                    allRows.append((name: testName, mode: mode, direction: "encode", stats: encodeResult.stats))
                }

                // Benchmark decoding
                if !encodeOnly {
                    if encodedData == nil {
                        let encoder = J2KEncoder(encodingConfiguration: modeConfig)
                        if mode == .gpu {
                            encodedData = try await encoder.encodeGPU(image)
                        } else {
                            encodedData = try encoder.encode(image)
                        }
                    }
                    guard let dataToUse = encodedData else {
                        throw J2KError.internalError("No encoded data available for decoding benchmark")
                    }
                    if outputFmt == "text" {
                        print("  \(mode.title) — Decode:")
                    }
                    let decodeStats = try await benchmarkDecode(
                        data: dataToUse, useGPU: mode == .gpu,
                        runs: runs, warmupRuns: warmupRuns,
                        pixels: size * size, outputFmt: outputFmt
                    )
                    allRows.append((name: testName, mode: mode, direction: "decode", stats: decodeStats))
                }
            }
        }

        if compareOJ && outputFmt == "text" {
            print("Note: OpenJPEG comparison is not available on this platform.")
        }

        // Output results
        switch outputFmt {
        case "csv":
            printMultiSizeCSV(allRows, gpuAvailable: gpuAvailable)
        case "json":
            printMultiSizeJSON(allRows, gpuAvailable: gpuAvailable, sizes: sizes)
        default:
            if outputFmt == "text" { print("Benchmark complete!") }
        }

        // Save report if requested
        if let outPath = outputPath {
            let ext = URL(fileURLWithPath: outPath).pathExtension.lowercased()
            let saveData: Data
            if ext == "csv" {
                let csv = buildMultiSizeCSVString(allRows, gpuAvailable: gpuAvailable)
                saveData = csv.data(using: .utf8) ?? Data()
            } else {
                let jsonObj = buildMultiSizeJSONObject(allRows, gpuAvailable: gpuAvailable, sizes: sizes)
                saveData = (try? JSONSerialization.data(withJSONObject: jsonObj, options: .prettyPrinted)) ?? Data()
            }
            try saveData.write(to: URL(fileURLWithPath: outPath))
            if outputFmt == "text" { print("Saved benchmark results to: \(outPath)") }
        }
    }

    // MARK: - Multi-Size Output Formatting

    private static func printMultiSizeCSV(
        _ rows: [(name: String, mode: BenchmarkMode, direction: String, stats: [String: Any])],
        gpuAvailable: Bool
    ) {
        print(buildMultiSizeCSVString(rows, gpuAvailable: gpuAvailable))
    }

    private static func buildMultiSizeCSVString(
        _ rows: [(name: String, mode: BenchmarkMode, direction: String, stats: [String: Any])],
        gpuAvailable: Bool
    ) -> String {
        var lines = ["name,mode,direction,average_ms,median_ms,min_ms,max_ms,stddev_ms,throughput_mpps,compressed_size,gpu_available"]
        for row in rows {
            let d    = row.stats
            let avg  = d["average_ms"]      as? Double ?? 0
            let med  = d["median_ms"]       as? Double ?? 0
            let mn   = d["min_ms"]          as? Double ?? 0
            let mx   = d["max_ms"]          as? Double ?? 0
            let std  = d["stddev_ms"]       as? Double ?? 0
            let mpps = d["throughput_mpps"] as? Double ?? 0
            let cs   = d["compressed_size"] as? Int
            let csStr = cs.map { String($0) } ?? ""
            lines.append("\(row.name),\(row.mode.label),\(row.direction),\(String(format: "%.3f", avg)),\(String(format: "%.3f", med)),\(String(format: "%.3f", mn)),\(String(format: "%.3f", mx)),\(String(format: "%.3f", std)),\(String(format: "%.2f", mpps)),\(csStr),\(gpuAvailable)")
        }
        return lines.joined(separator: "\n")
    }

    private static func printMultiSizeJSON(
        _ rows: [(name: String, mode: BenchmarkMode, direction: String, stats: [String: Any])],
        gpuAvailable: Bool,
        sizes: [Int]
    ) {
        let jsonObj = buildMultiSizeJSONObject(rows, gpuAvailable: gpuAvailable, sizes: sizes)
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObj, options: .prettyPrinted),
           let str = String(data: jsonData, encoding: .utf8) {
            print(str)
        }
    }

    private static func buildMultiSizeJSONObject(
        _ rows: [(name: String, mode: BenchmarkMode, direction: String, stats: [String: Any])],
        gpuAvailable: Bool,
        sizes: [Int]
    ) -> [String: Any] {
        var results: [String: Any] = [
            "gpu_available": gpuAvailable,
            "sizes": sizes.map { "\($0)x\($0)" },
        ]
        for row in rows {
            results[row.name] = row.stats
        }
        return results
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
            j2k benchmark --sizes 256,512,1024,2048 [options]

        MODES:
            (default)                   CPU-only Part 1 EBCOT benchmark
            --gpu                       GPU-accelerated pipeline (falls back to
                                        CPU when Metal is unavailable)
            --htj2k                     HTJ2K Part 15 FBCOT benchmark
            --compare-all               Run CPU, GPU, and HTJ2K side-by-side
                                        with a comparison summary table

        OPTIONS:
            -i, --input PATH            Input image file
            --sizes D1,D2,...           Run multi-size benchmark with synthetic
                                        square images at each dimension (e.g.
                                        --sizes 256,512,1024,2048). Mutually
                                        exclusive with -i/--input.
            -r, --runs N                Measurement runs (default: 3)
            --warmup N                  Warm-up runs before measurement (default: 1)
            -o, --output PATH           Output report file
            --format text|json|csv      Output format (default: text)
            --encode-only               Only benchmark encoding
            --decode-only               Only benchmark decoding
            --preset fast|balanced|quality  Encoding preset
            --compare-openjpeg          Note if OpenJPEG comparison is available

        GPU NOTES:
            When --gpu or --compare-all is used and Metal is not available
            (e.g. on Linux or CI servers), the GPU pipeline automatically
            falls back to CPU. The benchmark clearly reports this so results
            are not misleading.

        MULTI-SIZE NOTES:
            When --sizes is used, the benchmark generates synthetic grayscale
            test images filled with pseudo-random data at each requested
            dimension. This is useful for measuring GPU scaling across image
            sizes without needing external test files. CSV output includes a
            'name' column identifying each test (e.g. gpu_256x256).

        EXAMPLES:
            j2k benchmark -i test.pgm -r 10
            j2k benchmark -i test.pgm --gpu
            j2k benchmark -i test.pgm --htj2k --encode-only
            j2k benchmark -i test.pgm --compare-all --format csv -o results.csv
            j2k benchmark --sizes 256,512,1024,2048 --gpu --format csv
            j2k benchmark --sizes 256,512,1024,2048 --compare-all --encode-only
        """)
    }
}
