/// Command implementations for J2KCLI

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {
    /// Parse command-line arguments into a dictionary
    static func parseArguments(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0

        while i < args.count {
            let arg = args[i]

            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    result[key] = args[i + 1]
                    i += 2
                } else {
                    result[key] = "true"
                    i += 1
                }
            } else if arg.hasPrefix("-") && arg.count == 2 {
                let key = String(arg.dropFirst())
                if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    result[key] = args[i + 1]
                    i += 2
                } else {
                    result[key] = "true"
                    i += 1
                }
            } else {
                i += 1
            }
        }

        return result
    }

    /// Encode command: convert image to JPEG 2000
    static func encodeCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        guard let outputPath = options["o"] ?? options["output"] else {
            print("Error: Missing required argument: -o/--output")
            exit(1)
        }

        let showTiming = options["timing"] != nil
        let jsonOutput = options["json"] != nil

        // Load input image
        let startLoad = Date()
        let image = try loadImage(from: inputPath)
        let loadTime = Date().timeIntervalSince(startLoad)

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
        } else {
            config = J2KEncodingConfiguration()
        }

        if let qualityStr = options["q"] ?? options["quality"],
           let quality = Double(qualityStr) {
            config.quality = quality
        }

        if options["lossless"] != nil {
            config.lossless = true
        }

        if let levelsStr = options["levels"], let levels = Int(levelsStr) {
            config.decompositionLevels = levels
        }

        if let layersStr = options["layers"], let layers = Int(layersStr) {
            config.qualityLayers = layers
        }

        if let blocksizeStr = options["blocksize"] {
            let parts = blocksizeStr.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 {
                config.codeBlockSize = (parts[0], parts[1])
            }
        }

        // Encode
        let encoder = J2KEncoder(encodingConfiguration: config)
        let startEncode = Date()
        let encodedData = try encoder.encode(image)
        let encodeTime = Date().timeIntervalSince(startEncode)

        // Write output
        let startWrite = Date()
        try encodedData.write(to: URL(fileURLWithPath: outputPath))
        let writeTime = Date().timeIntervalSince(startWrite)

        // Output results
        let inputBytes = image.width * image.height * image.componentCount
        let compressionRatio = Double(inputBytes) / Double(encodedData.count)

        if jsonOutput {
            let result: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "inputSize": inputBytes,
                "outputSize": encodedData.count,
                "compressionRatio": compressionRatio,
                "width": image.width,
                "height": image.height,
                "components": image.componentCount,
                "timing": [
                    "load": loadTime,
                    "encode": encodeTime,
                    "write": writeTime,
                    "total": loadTime + encodeTime + writeTime
                ]
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("Encoded: \(inputPath) -> \(outputPath)")
            print("  Input: \(image.width)×\(image.height), \(image.componentCount) components")
            print("  Output size: \(formatBytes(encodedData.count))")
            print("  Compression ratio: \(String(format: "%.2f", compressionRatio)):1")
            if showTiming {
                print("  Timing:")
                print("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms")
                print("    Encode: \(String(format: "%7.3f", encodeTime * 1000)) ms")
                print("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms")
                print("    Total:  \(String(format: "%7.3f", (loadTime + encodeTime + writeTime) * 1000)) ms")
            }
        }
    }

    /// Decode command: convert JPEG 2000 to image
    static func decodeCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        guard let outputPath = options["o"] ?? options["output"] else {
            print("Error: Missing required argument: -o/--output")
            exit(1)
        }

        let showTiming = options["timing"] != nil
        let jsonOutput = options["json"] != nil

        // Load encoded data
        let startLoad = Date()
        let encodedData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let loadTime = Date().timeIntervalSince(startLoad)

        // Decode
        let decoder = J2KDecoder()
        let startDecode = Date()
        let image = try decoder.decode(encodedData)
        let decodeTime = Date().timeIntervalSince(startDecode)

        // Write output
        let startWrite = Date()
        try saveImage(image, to: outputPath)
        let writeTime = Date().timeIntervalSince(startWrite)

        // Output results
        if jsonOutput {
            let result: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "inputSize": encodedData.count,
                "width": image.width,
                "height": image.height,
                "components": image.componentCount,
                "timing": [
                    "load": loadTime,
                    "decode": decodeTime,
                    "write": writeTime,
                    "total": loadTime + decodeTime + writeTime
                ]
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("Decoded: \(inputPath) -> \(outputPath)")
            print("  Input size: \(formatBytes(encodedData.count))")
            print("  Output: \(image.width)×\(image.height), \(image.componentCount) components")
            if showTiming {
                print("  Timing:")
                print("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms")
                print("    Decode: \(String(format: "%7.3f", decodeTime * 1000)) ms")
                print("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms")
                print("    Total:  \(String(format: "%7.3f", (loadTime + decodeTime + writeTime) * 1000)) ms")
            }
        }
    }

    /// Format bytes in human-readable form
    static func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.2f %@", value, units[unitIndex])
    }
}
