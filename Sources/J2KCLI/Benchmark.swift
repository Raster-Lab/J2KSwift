/// Benchmark command implementation

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {
    /// Benchmark command: measure encoding/decoding performance
    static func benchmarkCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        let runs = Int(options["r"] ?? options["runs"] ?? "3") ?? 3
        let outputPath = options["o"] ?? options["output"]
        let encodeOnly = options["encode-only"] != nil
        let decodeOnly = options["decode-only"] != nil

        // Load input image
        print("Loading test image: \(inputPath)")
        let image = try loadImage(from: inputPath)
        print("  Image: \(image.width)×\(image.height), \(image.componentCount) components\n")

        // Configure encoder
        var config: J2KEncodingConfiguration
        if let preset = options["preset"] {
            switch preset {
            case "fast":
                config = J2KEncodingPreset.fast.configuration()
            case "balanced":
                config = J2KEncodingPreset.balanced.configuration()
            case "quality":
                config = J2KEncodingPreset.quality.configuration()
            default:
                print("Error: Unknown preset '\(preset)'")
                exit(1)
            }
            print("Using preset: \(preset)\n")
        } else {
            config = J2KEncodingConfiguration()
        }

        var results: [String: Any] = [
            "image": [
                "path": inputPath,
                "width": image.width,
                "height": image.height,
                "components": image.componentCount,
                "pixels": image.width * image.height
            ],
            "runs": runs
        ]

        // Benchmark encoding
        var encodedData: Data?
        if !decodeOnly {
            print("Benchmarking encoding (\(runs) runs)...")
            let encoder = J2KEncoder(encodingConfiguration: config)

            var encodeTimes: [Double] = []
            var totalEncodeTime: Double = 0

            for run in 1...runs {
                let start = Date()
                let data = try encoder.encode(image)
                let elapsed = Date().timeIntervalSince(start)
                encodeTimes.append(elapsed)
                totalEncodeTime += elapsed

                if run == 1 {
                    encodedData = data
                    let inputBytes = image.width * image.height * image.componentCount
                    let ratio = Double(inputBytes) / Double(data.count)
                    print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms (compressed to \(formatBytes(data.count)), ratio \(String(format: "%.2f", ratio)):1)")
                } else {
                    print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms")
                }
            }

            encodeTimes.sort()
            let avgTime = totalEncodeTime / Double(runs)
            let minTime = encodeTimes.first!
            let maxTime = encodeTimes.last!
            let medianTime = runs.isMultiple(of: 2)
                ? (encodeTimes[runs / 2 - 1] + encodeTimes[runs / 2]) / 2
                : encodeTimes[runs / 2]

            let megapixels = Double(image.width * image.height) / 1_000_000
            let throughput = megapixels / avgTime

            print("\n  Encode Statistics:")
            print("    Average: \(String(format: "%7.3f", avgTime * 1000)) ms")
            print("    Median:  \(String(format: "%7.3f", medianTime * 1000)) ms")
            print("    Min:     \(String(format: "%7.3f", minTime * 1000)) ms")
            print("    Max:     \(String(format: "%7.3f", maxTime * 1000)) ms")
            print("    Throughput: \(String(format: "%.2f", throughput)) MP/s\n")

            results["encode"] = [
                "runs": encodeTimes.map { $0 * 1000 },
                "average_ms": avgTime * 1000,
                "median_ms": medianTime * 1000,
                "min_ms": minTime * 1000,
                "max_ms": maxTime * 1000,
                "throughput_mpps": throughput,
                "compressed_size": encodedData!.count
            ]
        }

        // Benchmark decoding
        if !encodeOnly {
            if encodedData == nil {
                // Need to encode once to get data for decoding benchmark
                let encoder = J2KEncoder(encodingConfiguration: config)
                encodedData = try encoder.encode(image)
            }

            print("Benchmarking decoding (\(runs) runs)...")
            let decoder = J2KDecoder()

            guard let dataToUse = encodedData else {
                // This should never happen due to the logic above, but handle it safely
                throw J2KError.internalError("No encoded data available for decoding")
            }

            var decodeTimes: [Double] = []
            var totalDecodeTime: Double = 0

            for run in 1...runs {
                let start = Date()
                _ = try decoder.decode(dataToUse)
                let elapsed = Date().timeIntervalSince(start)
                decodeTimes.append(elapsed)
                totalDecodeTime += elapsed

                print("  Run \(run): \(String(format: "%.3f", elapsed * 1000)) ms")
            }

            decodeTimes.sort()
            let avgTime = totalDecodeTime / Double(runs)
            let minTime = decodeTimes.first!
            let maxTime = decodeTimes.last!
            let medianTime = runs.isMultiple(of: 2)
                ? (decodeTimes[runs / 2 - 1] + decodeTimes[runs / 2]) / 2
                : decodeTimes[runs / 2]

            let megapixels = Double(image.width * image.height) / 1_000_000
            let throughput = megapixels / avgTime

            print("\n  Decode Statistics:")
            print("    Average: \(String(format: "%7.3f", avgTime * 1000)) ms")
            print("    Median:  \(String(format: "%7.3f", medianTime * 1000)) ms")
            print("    Min:     \(String(format: "%7.3f", minTime * 1000)) ms")
            print("    Max:     \(String(format: "%7.3f", maxTime * 1000)) ms")
            print("    Throughput: \(String(format: "%.2f", throughput)) MP/s\n")

            results["decode"] = [
                "runs": decodeTimes.map { $0 * 1000 },
                "average_ms": avgTime * 1000,
                "median_ms": medianTime * 1000,
                "min_ms": minTime * 1000,
                "max_ms": maxTime * 1000,
                "throughput_mpps": throughput
            ]
        }

        // Save JSON report if requested
        if let outputPath = outputPath {
            let jsonData = try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)
            try jsonData.write(to: URL(fileURLWithPath: outputPath))
            print("Saved benchmark results to: \(outputPath)")
        }

        print("\nBenchmark complete!")
    }
}
