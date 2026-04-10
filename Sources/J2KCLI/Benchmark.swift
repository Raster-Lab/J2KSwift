//
// Benchmark.swift
// J2KSwift
//
/// Benchmark command implementation

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {
    /// Benchmark command: measure encoding/decoding performance
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
        let compareHTJ2K = options["compare-htj2k"] != nil || options["htj2k"] != nil
        let outputFmt   = options["format"] ?? "text"

        // Load input image
        if outputFmt == "text" { print("Loading test image: \(inputPath)") }
        let image = try loadImage(from: inputPath)
        if outputFmt == "text" { print("  Image: \(image.width)×\(image.height), \(image.componentCount) component(s)\n") }

        // Configure encoder
        var config: J2KEncodingConfiguration
        if let preset = options["preset"] {
            switch preset {
            case "fast":     config = J2KEncodingPreset.fast.configuration()
            case "balanced": config = J2KEncodingPreset.balanced.configuration()
            case "quality":  config = J2KEncodingPreset.quality.configuration()
            default:
                print("Error: Unknown preset '\(preset)'")
                exit(1)
            }
            if outputFmt == "text" { print("Using preset: \(preset)\n") }
        } else {
            config = J2KEncodingConfiguration()
        }

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
        ]

        // Run legacy benchmark
        let legacyResults = try runBenchmarkPass(
            image: image, config: config, runs: runs, warmupRuns: warmupRuns,
            encodeOnly: encodeOnly, decodeOnly: decodeOnly,
            label: compareHTJ2K ? "Legacy EBCOT" : nil,
            outputFmt: outputFmt
        )
        results["encode"] = legacyResults.encodeStats
        results["decode"] = legacyResults.decodeStats

        // HTJ2K comparison mode
        if compareHTJ2K {
            var htConfig = config
            htConfig.useHTJ2K = true
            if outputFmt == "text" {
                print("\n" + String(repeating: "─", count: 60))
                print("HTJ2K (Part 15) Comparison")
                print(String(repeating: "─", count: 60) + "\n")
            }

            let htResults = try runBenchmarkPass(
                image: image, config: htConfig, runs: runs, warmupRuns: warmupRuns,
                encodeOnly: encodeOnly, decodeOnly: decodeOnly,
                label: "HTJ2K FBCOT",
                outputFmt: outputFmt
            )
            results["htj2k_encode"] = htResults.encodeStats
            results["htj2k_decode"] = htResults.decodeStats

            // Print comparison summary
            if outputFmt == "text" {
                print("\n" + String(repeating: "═", count: 60))
                print("COMPARISON SUMMARY: Legacy EBCOT vs HTJ2K FBCOT")
                print(String(repeating: "═", count: 60))

                if let legEnc = legacyResults.encodeAvg, let htEnc = htResults.encodeAvg {
                    let speedup = legEnc / htEnc
                    print(String(format: "  Encode:  Legacy %7.1f ms  │  HTJ2K %7.1f ms  │  %.2f×", legEnc * 1000, htEnc * 1000, speedup))
                }
                if let legDec = legacyResults.decodeAvg, let htDec = htResults.decodeAvg {
                    let speedup = legDec / htDec
                    print(String(format: "  Decode:  Legacy %7.1f ms  │  HTJ2K %7.1f ms  │  %.2f×", legDec * 1000, htDec * 1000, speedup))
                }
                if let legSize = legacyResults.compressedSize, let htSize = htResults.compressedSize {
                    let ratio = Double(legSize) / Double(htSize)
                    print(String(format: "  Size:    Legacy %7d B   │  HTJ2K %7d B   │  %.2f×", legSize, htSize, ratio))
                }
                print(String(repeating: "═", count: 60) + "\n")
            }
        }

        // OpenJPEG comparison
        if compareOJ {
            if outputFmt == "text" {
                print("\n" + String(repeating: "─", count: 60))
                print("OpenJPEG Comparison")
                print(String(repeating: "─", count: 60))
            }
            let ojResults = try runOpenJPEGBenchmark(
                inputPath: inputPath, runs: runs, warmupRuns: warmupRuns,
                encodeOnly: encodeOnly, decodeOnly: decodeOnly,
                outputFmt: outputFmt
            )
            results["openjpeg_encode"] = ojResults.encodeStats
            results["openjpeg_decode"] = ojResults.decodeStats

            // Print cross-codec comparison
            if outputFmt == "text" {
                print("\n" + String(repeating: "═", count: 60))
                print("CROSS-CODEC SUMMARY: J2KSwift vs OpenJPEG")
                print(String(repeating: "═", count: 60))

                if let j2kEnc = legacyResults.encodeAvg, let ojEnc = ojResults.encodeAvg {
                    let speedup = ojEnc / j2kEnc
                    print(String(format: "  Encode:  J2KSwift %7.1f ms  │  OpenJPEG %7.1f ms  │  %.2f×", j2kEnc * 1000, ojEnc * 1000, speedup))
                }
                if let j2kDec = legacyResults.decodeAvg, let ojDec = ojResults.decodeAvg {
                    let speedup = ojDec / j2kDec
                    print(String(format: "  Decode:  J2KSwift %7.1f ms  │  OpenJPEG %7.1f ms  │  %.2f×", j2kDec * 1000, ojDec * 1000, speedup))
                }
                print(String(repeating: "═", count: 60) + "\n")
            }
        }

        // Output results
        switch outputFmt {
        case "json":
            if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: jsonData, encoding: .utf8) {
                print(str)
            }
        case "csv":
            printCSV(results)
        default:
            if outputFmt == "text" { print("Benchmark complete!") }
        }

        // Save report if requested
        if let outPath = outputPath {
            let ext = URL(fileURLWithPath: outPath).pathExtension.lowercased()
            let saveData: Data
            if ext == "csv" {
                let csv = buildCSVString(results)
                saveData = csv.data(using: .utf8) ?? Data()
            } else {
                saveData = (try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            }
            try saveData.write(to: URL(fileURLWithPath: outPath))
            print("Saved benchmark results to: \(outPath)")
        }
    }

    // MARK: - Benchmark Pass

    private struct BenchmarkPassResult {
        let encodeStats: [String: Any]?
        let decodeStats: [String: Any]?
        let encodeAvg: Double?
        let decodeAvg: Double?
        let compressedSize: Int?
    }

    private static func runBenchmarkPass(
        image: J2KImage,
        config: J2KEncodingConfiguration,
        runs: Int,
        warmupRuns: Int,
        encodeOnly: Bool,
        decodeOnly: Bool,
        label: String?,
        outputFmt: String
    ) throws -> BenchmarkPassResult {
        let prefix = label.map { "[\($0)] " } ?? ""
        var encodeStatsDict: [String: Any]?
        var decodeStatsDict: [String: Any]?
        var encodeAvgTime: Double?
        var decodeAvgTime: Double?
        var compSize: Int?

        // Benchmark encoding
        var encodedData: Data?
        if !decodeOnly {
            let encoder = J2KEncoder(encodingConfiguration: config)

            if warmupRuns > 0 && outputFmt == "text" { print("\(prefix)Warming up (\(warmupRuns) run(s))…") }
            for _ in 0..<warmupRuns { _ = try encoder.encode(image) }

            if outputFmt == "text" { print("\(prefix)Benchmarking encoding (\(runs) runs)…") }
            var encodeTimes: [Double] = []

            for run in 1...runs {
                let start   = Date()
                let data    = try encoder.encode(image)
                let elapsed = Date().timeIntervalSince(start)
                encodeTimes.append(elapsed)

                if run == 1 {
                    encodedData = data
                    compSize = data.count
                    let inputBytes = image.width * image.height * image.componentCount
                    let ratio = Double(inputBytes) / Double(data.count)
                    if outputFmt == "text" {
                        print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms (compressed to \(formatBytes(data.count)), ratio \(String(format: "%.2f", ratio)):1)")
                    }
                } else if outputFmt == "text" {
                    print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms")
                }
            }

            let stats = computeStats(encodeTimes)
            encodeAvgTime = stats.avg
            if outputFmt == "text" {
                print("\n  \(prefix)Encode Statistics:")
                print("    Average: \(String(format: "%7.3f", stats.avg * 1000)) ms")
                print("    Median:  \(String(format: "%7.3f", stats.median * 1000)) ms")
                print("    Min:     \(String(format: "%7.3f", stats.min * 1000)) ms")
                print("    Max:     \(String(format: "%7.3f", stats.max * 1000)) ms")
                print("    Std Dev: \(String(format: "%7.3f", stats.stddev * 1000)) ms")
                let mpps = Double(image.width * image.height) / 1_000_000 / stats.avg
                print("    Throughput: \(String(format: "%.2f", mpps)) MP/s\n")
            }
            encodeStatsDict = buildStatsDict(stats, times: encodeTimes, pixels: image.width * image.height, compressedSize: compSize)
        }

        // Benchmark decoding
        if !encodeOnly {
            if encodedData == nil {
                let encoder = J2KEncoder(encodingConfiguration: config)
                encodedData = try encoder.encode(image)
            }
            guard let dataToUse = encodedData else {
                throw J2KError.internalError("No encoded data available for decoding benchmark")
            }

            let decoder = J2KDecoder()
            for _ in 0..<warmupRuns { _ = try decoder.decode(dataToUse) }

            if outputFmt == "text" { print("\(prefix)Benchmarking decoding (\(runs) runs)…") }
            var decodeTimes: [Double] = []

            for run in 1...runs {
                let start   = Date()
                _ = try decoder.decode(dataToUse)
                let elapsed = Date().timeIntervalSince(start)
                decodeTimes.append(elapsed)
                if outputFmt == "text" { print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms") }
            }

            let stats = computeStats(decodeTimes)
            decodeAvgTime = stats.avg
            if outputFmt == "text" {
                print("\n  \(prefix)Decode Statistics:")
                print("    Average: \(String(format: "%7.3f", stats.avg * 1000)) ms")
                print("    Median:  \(String(format: "%7.3f", stats.median * 1000)) ms")
                print("    Min:     \(String(format: "%7.3f", stats.min * 1000)) ms")
                print("    Max:     \(String(format: "%7.3f", stats.max * 1000)) ms")
                print("    Std Dev: \(String(format: "%7.3f", stats.stddev * 1000)) ms")
                let mpps = Double(image.width * image.height) / 1_000_000 / stats.avg
                print("    Throughput: \(String(format: "%.2f", mpps)) MP/s\n")
            }
            decodeStatsDict = buildStatsDict(stats, times: decodeTimes, pixels: image.width * image.height, compressedSize: nil)
        }

        return BenchmarkPassResult(
            encodeStats: encodeStatsDict,
            decodeStats: decodeStatsDict,
            encodeAvg: encodeAvgTime,
            decodeAvg: decodeAvgTime,
            compressedSize: compSize
        )
    }

    // MARK: - OpenJPEG Benchmark

    private struct OpenJPEGPassResult {
        let encodeStats: [String: Any]?
        let decodeStats: [String: Any]?
        let encodeAvg: Double?
        let decodeAvg: Double?
    }

    private static func runOpenJPEGBenchmark(
        inputPath: String,
        runs: Int,
        warmupRuns: Int,
        encodeOnly: Bool,
        decodeOnly: Bool,
        outputFmt: String
    ) throws -> OpenJPEGPassResult {
        let opjCompress = findExecutable("opj_compress")
        let opjDecompress = findExecutable("opj_decompress")

        guard opjCompress != nil || opjDecompress != nil else {
            if outputFmt == "text" {
                print("  OpenJPEG not found. Install with: brew install openjpeg (macOS) or apt install libopenjp2-tools (Linux)")
            }
            return OpenJPEGPassResult(encodeStats: nil, decodeStats: nil, encodeAvg: nil, decodeAvg: nil)
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("j2k_opj_bench_\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let j2kOutput = tmpDir.appendingPathComponent("output.j2k").path
        let pgmOutput = tmpDir.appendingPathComponent("output.pgm").path

        var encodeStatsDict: [String: Any]?
        var decodeStatsDict: [String: Any]?
        var encodeAvgTime: Double?
        var decodeAvgTime: Double?

        // Encode benchmark
        if let compressor = opjCompress, !decodeOnly {
            if warmupRuns > 0 {
                for _ in 0..<warmupRuns {
                    runProcess(compressor, arguments: ["-i", inputPath, "-o", j2kOutput, "-r", "1"])
                }
            }

            if outputFmt == "text" { print("  [OpenJPEG] Benchmarking encoding (\(runs) runs)…") }
            var encodeTimes: [Double] = []

            for run in 1...runs {
                let start = Date()
                runProcess(compressor, arguments: ["-i", inputPath, "-o", j2kOutput, "-r", "1"])
                let elapsed = Date().timeIntervalSince(start)
                encodeTimes.append(elapsed)
                if outputFmt == "text" { print("    Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms") }
            }

            let stats = computeStats(encodeTimes)
            encodeAvgTime = stats.avg
            if outputFmt == "text" {
                print("\n    [OpenJPEG] Encode Average: \(String(format: "%.3f", stats.avg * 1000)) ms\n")
            }
            encodeStatsDict = [
                "average_ms": stats.avg * 1000,
                "median_ms": stats.median * 1000,
                "min_ms": stats.min * 1000,
                "max_ms": stats.max * 1000,
            ]
        }

        // Decode benchmark
        if let decompressor = opjDecompress, !encodeOnly {
            // Ensure we have a J2K file to decode
            if !FileManager.default.fileExists(atPath: j2kOutput), let compressor = opjCompress {
                runProcess(compressor, arguments: ["-i", inputPath, "-o", j2kOutput, "-r", "1"])
            }

            guard FileManager.default.fileExists(atPath: j2kOutput) else {
                if outputFmt == "text" { print("  [OpenJPEG] No encoded file available for decode benchmark") }
                return OpenJPEGPassResult(encodeStats: encodeStatsDict, decodeStats: nil, encodeAvg: encodeAvgTime, decodeAvg: nil)
            }

            for _ in 0..<warmupRuns {
                runProcess(decompressor, arguments: ["-i", j2kOutput, "-o", pgmOutput])
            }

            if outputFmt == "text" { print("  [OpenJPEG] Benchmarking decoding (\(runs) runs)…") }
            var decodeTimes: [Double] = []

            for run in 1...runs {
                let start = Date()
                runProcess(decompressor, arguments: ["-i", j2kOutput, "-o", pgmOutput])
                let elapsed = Date().timeIntervalSince(start)
                decodeTimes.append(elapsed)
                if outputFmt == "text" { print("    Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms") }
            }

            let stats = computeStats(decodeTimes)
            decodeAvgTime = stats.avg
            if outputFmt == "text" {
                print("\n    [OpenJPEG] Decode Average: \(String(format: "%.3f", stats.avg * 1000)) ms\n")
            }
            decodeStatsDict = [
                "average_ms": stats.avg * 1000,
                "median_ms": stats.median * 1000,
                "min_ms": stats.min * 1000,
                "max_ms": stats.max * 1000,
            ]
        }

        return OpenJPEGPassResult(encodeStats: encodeStatsDict, decodeStats: decodeStatsDict, encodeAvg: encodeAvgTime, decodeAvg: decodeAvgTime)
    }

    // MARK: - Process Helpers

    private static func findExecutable(_ name: String) -> String? {
        let searchPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    @discardableResult
    private static func runProcess(_ executablePath: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
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
        let sorted = times.sorted()
        let n = Double(times.count)
        let avg = times.reduce(0, +) / n
        let median = times.count.isMultiple(of: 2)
            ? (sorted[times.count / 2 - 1] + sorted[times.count / 2]) / 2
            : sorted[times.count / 2]
        let variance = times.count > 1
            ? times.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(times.count - 1)
            : 0.0
        return Stats(avg: avg, median: median, min: sorted.first!, max: sorted.last!, stddev: variance.squareRoot())
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
            "throughput_mpps": Double(pixels) / 1_000_000 / stats.avg,
        ]
        if let cs = compressedSize { d["compressed_size"] = cs }
        return d
    }

    // MARK: - CSV output

    private static func printCSV(_ results: [String: Any]) {
        print(buildCSVString(results))
    }

    private static func buildCSVString(_ results: [String: Any]) -> String {
        var lines = ["metric,value_ms,throughput_mpps"]
        let keys = ["encode", "decode", "htj2k_encode", "htj2k_decode", "openjpeg_encode", "openjpeg_decode"]
        for key in keys {
            guard let d = results[key] as? [String: Any] else { continue }
            let avg  = d["average_ms"]      as? Double ?? 0
            let mpps = d["throughput_mpps"] as? Double ?? 0
            lines.append("\(key)_avg,\(String(format: "%.3f", avg)),\(String(format: "%.2f", mpps))")
            let min  = d["min_ms"]  as? Double ?? 0
            let max  = d["max_ms"]  as? Double ?? 0
            let std  = d["stddev_ms"] as? Double ?? 0
            lines.append("\(key)_min,\(String(format: "%.3f", min)),")
            lines.append("\(key)_max,\(String(format: "%.3f", max)),")
            lines.append("\(key)_stddev,\(String(format: "%.3f", std)),")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Help

    private static func printBenchmarkHelp() {
        print("""
        j2k benchmark - Measure encoding/decoding performance

        USAGE:
            j2k benchmark -i <input> [options]

        OPTIONS:
            -i, --input PATH            Input image file
            -r, --runs N                Measurement runs (default: 3)
            --warmup N                  Warm-up runs (default: 1)
            -o, --output PATH           Output report file
            --format text|json|csv      Output format (default: text)
            --encode-only               Only benchmark encoding
            --decode-only               Only benchmark decoding
            --preset fast|balanced|quality  Encoding preset
            --htj2k, --compare-htj2k    Compare Legacy EBCOT vs HTJ2K FBCOT
            --compare-openjpeg          Cross-codec comparison with OpenJPEG
        """)
    }
}

