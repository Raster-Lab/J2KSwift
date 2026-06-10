//
// InProcBench.swift
// J2KSwift
//
// In-process per-call timing for one fixture, suitable for cross-codec
// orchestration where the parent script invokes this command once per
// fixture and aggregates JSON results. The Swift launcher cost (dyld,
// runtime init) is amortised across (warmups + runs) iterations within
// a single launch — all timed runs measure pure codec work.

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    static func inProcBenchCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil || options["_positional"] == nil {
            printInProcBenchHelp()
            return
        }

        guard let inputPath = options["_positional"] else {
            FileHandle.standardError.write(Data("Error: input fixture path required\n".utf8))
            exit(1)
        }

        let runs = Int(options["runs"] ?? "7") ?? 7
        let warmups = Int(options["warmups"] ?? "2") ?? 2
        let mode = options["mode"] ?? "both"  // "encode" | "decode" | "both"

        // Load fixture once (PGM / DCM / PPM / TIFF / PNG auto-detected by extension)
        let image = try loadImage(from: inputPath)

        // Lossless HT-conformant config — matches Scripts/benchmarks/
        // cross_codec_warm_bench.py invocation flags `--htj2k --lossless`.
        // useReversibleFilter auto-set to true because lossless=true (init).
        var config = J2KEncodingConfiguration()
        config.lossless = true
        config.useHTJ2K = true
        config.useReversibleFilter = true
        let encoder = J2KEncoder(encodingConfiguration: config)

        var encodeSamples: [Double] = []
        var decodeSamples: [Double] = []
        var encodedBytes: Data = Data()

        // ENCODE pass
        if mode == "encode" || mode == "both" {
            for _ in 0..<warmups {
                _ = try await encoder.encode(image)
            }
            for _ in 0..<runs {
                let t0 = DispatchTime.now()
                let bytes = try await encoder.encode(image)
                let t1 = DispatchTime.now()
                let ms = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
                encodeSamples.append(ms)
                encodedBytes = bytes
            }
        }

        // DECODE pass — needs codestream bytes; encode once if we skipped encode pass
        if mode == "decode" || mode == "both" {
            if encodedBytes.isEmpty {
                encodedBytes = try await encoder.encode(image)
            }
            let decoder = J2KDecoder()
            for _ in 0..<warmups {
                _ = try await decoder.decode(encodedBytes)
            }
            for _ in 0..<runs {
                let t0 = DispatchTime.now()
                _ = try await decoder.decode(encodedBytes)
                let t1 = DispatchTime.now()
                let ms = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
                decodeSamples.append(ms)
            }
        }

        var result: [String: Any] = [
            "input": inputPath,
            "width": image.width,
            "height": image.height,
            "components": image.componentCount,
            "bitDepth": image.components.first?.bitDepth ?? 0,
            "encodedSize": encodedBytes.count,
            "runs": runs,
            "warmups": warmups
        ]
        if !encodeSamples.isEmpty {
            result["encode"] = stats(encodeSamples)
        }
        if !decodeSamples.isEmpty {
            result["decode"] = stats(decodeSamples)
        }

        let json = try JSONSerialization.data(
            withJSONObject: result, options: [.sortedKeys])
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func stats(_ samples: [Double]) -> [String: Any] {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        return [
            "samples": samples,
            "median": median,
            "min": sorted.first!,
            "max": sorted.last!
        ]
    }

    static func printInProcBenchHelp() {
        let help = """
        Usage: j2k inproc-bench <input.pgm|.j2k> [options]

        Run in-process encode + decode timing on a single fixture.
        All timed iterations share one Swift process — launcher cost is
        amortised in warmups; samples reflect pure codec wall.

        Options:
          --runs N         Timed runs (default 7)
          --warmups N      Untimed warmups (default 2)
          --mode <m>       encode | decode | both (default both)
          --help           Show this help

        Output: JSON to stdout with encode/decode {samples, median, min, max}
        """
        print(help)
    }
}
