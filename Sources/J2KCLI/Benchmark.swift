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

        // Benchmark encoding
        var encodedData: Data?
        if !decodeOnly {
            let encoder = J2KEncoder(encodingConfiguration: config)

            // Warm-up
            if warmupRuns > 0 && outputFmt == "text" { print("Warming up (\(warmupRuns) run(s))…") }
            for _ in 0..<warmupRuns { _ = try encoder.encode(image) }

            if outputFmt == "text" { print("Benchmarking encoding (\(runs) runs)…") }
            var encodeTimes: [Double] = []

            for run in 1...runs {
                let start   = Date()
                let data    = try encoder.encode(image)
                let elapsed = Date().timeIntervalSince(start)
                encodeTimes.append(elapsed)

                if run == 1 {
                    encodedData = data
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
            if outputFmt == "text" {
                print("\n  Encode Statistics:")
                print("    Average: \(String(format: "%7.3f", stats.avg * 1000)) ms")
                print("    Median:  \(String(format: "%7.3f", stats.median * 1000)) ms")
                print("    Min:     \(String(format: "%7.3f", stats.min * 1000)) ms")
                print("    Max:     \(String(format: "%7.3f", stats.max * 1000)) ms")
                print("    Std Dev: \(String(format: "%7.3f", stats.stddev * 1000)) ms")
                let mpps = Double(image.width * image.height) / 1_000_000 / stats.avg
                print("    Throughput: \(String(format: "%.2f", mpps)) MP/s\n")
            }

            results["encode"] = buildStatsDict(stats, times: encodeTimes, pixels: image.width * image.height, compressedSize: encodedData!.count)
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

            // Warm-up
            for _ in 0..<warmupRuns { _ = try decoder.decode(dataToUse) }

            if outputFmt == "text" { print("Benchmarking decoding (\(runs) runs)…") }
            var decodeTimes: [Double] = []

            for run in 1...runs {
                let start   = Date()
                _ = try decoder.decode(dataToUse)
                let elapsed = Date().timeIntervalSince(start)
                decodeTimes.append(elapsed)
                if outputFmt == "text" { print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms") }
            }

            let stats = computeStats(decodeTimes)
            if outputFmt == "text" {
                print("\n  Decode Statistics:")
                print("    Average: \(String(format: "%7.3f", stats.avg * 1000)) ms")
                print("    Median:  \(String(format: "%7.3f", stats.median * 1000)) ms")
                print("    Min:     \(String(format: "%7.3f", stats.min * 1000)) ms")
                print("    Max:     \(String(format: "%7.3f", stats.max * 1000)) ms")
                print("    Std Dev: \(String(format: "%7.3f", stats.stddev * 1000)) ms")
                let mpps = Double(image.width * image.height) / 1_000_000 / stats.avg
                print("    Throughput: \(String(format: "%.2f", mpps)) MP/s\n")
            }
            results["decode"] = buildStatsDict(stats, times: decodeTimes, pixels: image.width * image.height, compressedSize: nil)
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
                saveData = (try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)) ?? Data()
            }
            try saveData.write(to: URL(fileURLWithPath: outPath))
            print("Saved benchmark results to: \(outPath)")
        }
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
        for key in ["encode", "decode"] {
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
            --compare-openjpeg          Note if OpenJPEG comparison is available
        """)
    }
}

