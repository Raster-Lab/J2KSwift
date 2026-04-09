//
// Commands.swift
// J2KSwift
//
/// Command implementations for J2KCLI

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {
    /// Parse command-line arguments into a dictionary.
    ///
    /// Normalises British/American spelling variants so callers only need to check
    /// the canonical (American) form.  Positional arguments are stored under the
    /// synthetic key `"_positional"`.
    static func parseArguments(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0

        while i < args.count {
            let arg = args[i]

            if arg.hasPrefix("--") {
                let raw = String(arg.dropFirst(2))
                let key = Self.normaliseKey(raw)
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
                // Treat unrecognised bare tokens as positional arguments
                result["_positional"] = arg
                i += 1
            }
        }

        return result
    }

    /// Normalise a flag key so that British and American spellings map to the same key.
    static func normaliseKey(_ key: String) -> String {
        switch key {
        // --colour -> --color
        case "colour":                  return "color"
        case "colour-space":            return "color-space"
        case "no-colour":               return "no-color"
        // --optimise -> --optimize
        case "optimise":                return "optimize"
        case "optimise-progressive":    return "optimize-progressive"
        // --normalise -> --normalize
        case "normalise":               return "normalize"
        default:                        return key
        }
    }

    /// Encode command: convert image to JPEG 2000
    static func encodeCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printEncodeHelp()
            return
        }

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        let pipeInput  = (inputPath == "-")
        let pipeOutput: Bool
        let outputPath: String

        if let o = options["o"] ?? options["output"] {
            pipeOutput = (o == "-")
            outputPath = o
        } else {
            pipeOutput = false
            outputPath = deriveOutputPath(inputPath: inputPath, command: "encode", options: options)
        }

        let showTiming  = options["timing"] != nil
        let jsonOutput  = options["json"] != nil
        let verbose     = options["verbose"] != nil
        let quiet       = options["quiet"] != nil

        // Load input image
        if verbose { printInfo("Loading: \(inputPath)", pipeMode: pipeOutput) }
        let startLoad = Date()
        let image: J2KImage
        if pipeInput {
            image = try loadImageFromStdin()
        } else {
            image = try loadImage(from: inputPath)
        }
        let loadTime = Date().timeIntervalSince(startLoad)
        if verbose { printInfo("  \(image.width)×\(image.height), \(image.componentCount) component(s)", pipeMode: pipeOutput) }

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
        } else {
            config = J2KEncodingConfiguration()
        }

        // Quality / rate modes
        if options["lossless"] != nil {
            config.lossless = true
        } else if let bpStr = options["bitrate"], let bpp = Double(bpStr) {
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        } else if let qualStr = options["q"] ?? options["quality"],
                  let quality = Double(qualStr) {
            config.quality = quality
        }

        if options["visually-lossless"] != nil {
            config.quality = 0.99
        }

        // Filter selection: --irreversible forces 9/7 DWT, --reversible forces 5/3
        if options["irreversible"] != nil {
            config.useReversibleFilter = false
        } else if options["reversible"] != nil {
            config.useReversibleFilter = true
        }

        // Structural options
        if let levelsStr = options["levels"], let levels = Int(levelsStr) {
            config.decompositionLevels = levels
        }
        if let layersStr = options["layers"], let layers = Int(layersStr) {
            config.qualityLayers = layers
        }
        if let blocksizeStr = options["blocksize"] {
            let parts = blocksizeStr.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { config.codeBlockSize = (parts[0], parts[1]) }
        }
        if let tileSizeStr = options["tile-size"] {
            let parts = tileSizeStr.split(separator: "x").compactMap { Int($0) }
            if parts.count == 2 { config.tileSize = (parts[0], parts[1]) }
        }
        if let progStr = options["progression"] {
            if let order = J2KProgressionOrder(rawValue: progStr.uppercased()) {
                config.progressionOrder = order
            } else {
                print("Error: Unknown progression order '\(progStr)'. Expected: LRCP, RLCP, RPCL, PCRL, CPRL")
                exit(1)
            }
        }
        if options["htj2k"] != nil { config.useHTJ2K = true }
        if options["no-mct"] != nil { config.mctConfiguration = .disabled }

        // Codec variant selection
        if let codec = options["codec"] {
            applyCodecOption(codec, to: &config)
        }

        // Compression ratio / percentage
        if let ratioStr = options["compression-ratio"] {
            // Parse "N:1" format
            let parts = ratioStr.split(separator: ":")
            if let ratio = parts.first.flatMap({ Double($0) }) {
                let bpp = Double(image.componentCount * image.components[0].bitDepth) / ratio
                config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
            }
        }
        if let pctStr = options["compression-percent"], let pct = Double(pctStr) {
            // N% size reduction => ratio = 100 / (100 - N)
            let ratio = 100.0 / max(1, 100.0 - pct)
            let bpp = Double(image.componentCount * image.components[0].bitDepth) / ratio
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }
        if let sizeStr = options["target-size"], let targetBytes = Int(sizeStr) {
            let totalPixels = image.width * image.height
            let bpp = Double(targetBytes * 8) / Double(totalPixels)
            config.bitrateMode = .constantBitrate(bitsPerPixel: bpp)
        }

        // Note: enabling MCT via --mct uses the default configuration from preset
        // GPU toggle is noted but has no effect on this platform
        if verbose, options["gpu"] != nil { print("Note: GPU acceleration requested (not available on this platform)") }

        // Encode
        if verbose { print("Encoding…") }
        let encoder = J2KEncoder(encodingConfiguration: config)
        let startEncode = Date()
        var encodedData = try encoder.encode(image)
        let encodeTime = Date().timeIntervalSince(startEncode)

        // Wrap in JP2 container if requested
        let format = options["format"] ?? "j2k"
        if format == "jp2" || format == "jpx" {
            encodedData = wrapInJP2Container(encodedData, image: image)
        }

        // Progress indicator for verbose mode
        if verbose { printInfo("Writing: \(outputPath)", pipeMode: pipeOutput) }

        // Write output
        let startWrite = Date()
        if pipeOutput {
            FileHandle.standardOutput.write(encodedData)
        } else {
            try encodedData.write(to: URL(fileURLWithPath: outputPath))
        }
        let writeTime = Date().timeIntervalSince(startWrite)

        // Output results
        let inputBytes = image.width * image.height * image.componentCount
        let compressionRatio = Double(inputBytes) / Double(encodedData.count)

        if jsonOutput {
            let result: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "format": format,
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
                printInfo(jsonString, pipeMode: pipeOutput)
            }
        } else if !quiet {
            printInfo("Encoded: \(inputPath) -> \(outputPath)", pipeMode: pipeOutput)
            printInfo("  Input:  \(image.width)×\(image.height), \(image.componentCount) component(s)", pipeMode: pipeOutput)
            printInfo("  Output size: \(formatBytes(encodedData.count))", pipeMode: pipeOutput)
            printInfo("  Compression ratio: \(String(format: "%.2f", compressionRatio)):1", pipeMode: pipeOutput)
            if showTiming {
                printInfo("  Timing:", pipeMode: pipeOutput)
                printInfo("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Encode: \(String(format: "%7.3f", encodeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Total:  \(String(format: "%7.3f", (loadTime + encodeTime + writeTime) * 1000)) ms", pipeMode: pipeOutput)
            }
        }
    }

    private static func printEncodeHelp() {
        print("""
        j2k encode - Encode an image to JPEG 2000

        USAGE:
            j2k encode -i <input> [-o <output>] [options]

        OPTIONS:
            -i, --input PATH            Input image (PGM, PPM, TIFF, PNG, DICOM)
            -o, --output PATH           Output file (optional; derived from input name if omitted)
            -q, --quality FLOAT         Quality 0.0-1.0 (default 1.0)
            --lossless                  Lossless compression
            --bitrate BPP               Target bit-rate (bits per pixel)
            --psnr VALUE                Target PSNR (dB)
            --visually-lossless         Near-lossless preset
            --reversible                Use 5/3 reversible DWT (default, best for medical)
            --irreversible              Use 9/7 irreversible DWT
            --preset fast|balanced|quality  Encoding preset
            --levels N                  DWT decomposition levels
            --blocksize WxH             Code-block size (e.g. 64x64)
            --layers N                  Quality layers
            --format j2k|jp2|jpx        Output container format
            --progression ORDER         LRCP|RLCP|RPCL|PCRL|CPRL
            --tile-size WxH             Tile size
            --htj2k                     Use HTJ2K (Part 15)
            --mct / --no-mct            Multi-component transform
            --gpu / --no-gpu            GPU acceleration
            --colour-space CS           Set colour space
            --verbose                   Verbose output
            --quiet                     Suppress output
            --timing                    Show timing breakdown
            --json                      JSON output

        PIPING:
            -i -                        Read input from stdin
            -o -                        Write output to stdout
            When piping, diagnostic messages are sent to stderr.

        EXAMPLES:
            j2k encode -i input.pgm -o output.j2k --lossless
            j2k encode -i input.tiff --htj2k
            j2k encode -i scan.dcm -o compressed.jp2 --format jp2
            cat image.pgm | j2k encode -i - -o output.j2k
        """)
    }

    /// Decode command: convert JPEG 2000 to image
    static func decodeCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printDecodeHelp()
            return
        }

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        let pipeInput  = (inputPath == "-")
        let explicitOutput = options["o"] ?? options["output"]
        let pipeOutput = (explicitOutput == "-")

        let showTiming = options["timing"] != nil
        let jsonOutput = options["json"] != nil
        let verbose    = options["verbose"] != nil
        let quiet      = options["quiet"] != nil

        // Partial-decoding options (informational – passed to decoder when supported)
        let resolutionLevel = options["level"].flatMap { Int($0) }
        let qualityLayer    = options["layer"].flatMap { Int($0) }
        let headerOnly      = options["header-only"] != nil
        let stripAlpha      = options["strip-alpha"] != nil
        let scale           = options["scale"].flatMap { Int($0) }
        let regionStr       = options["region"]
        let outputFormat    = options["output-format"]
        let bitDepthConvert = options["bit-depth"].flatMap { Int($0) }

        if verbose {
            printInfo("Loading: \(inputPath)", pipeMode: pipeOutput)
            if let l = resolutionLevel { printInfo("  Resolution level: \(l)", pipeMode: pipeOutput) }
            if let l = qualityLayer    { printInfo("  Quality layer: \(l)", pipeMode: pipeOutput) }
        }

        // Load encoded data
        let startLoad = Date()
        let encodedData: Data
        if pipeInput {
            encodedData = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            encodedData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        }
        let loadTime = Date().timeIntervalSince(startLoad)

        // Decode
        let decoder = J2KDecoder()
        let startDecode = Date()
        let decodedImage = try decoder.decode(encodedData)
        let decodeTime = Date().timeIntervalSince(startDecode)

        // Header-only mode: print info and exit
        if headerOnly {
            printInfo("Codestream Info:", pipeMode: pipeOutput)
            printInfo("  Dimensions: \(decodedImage.width)×\(decodedImage.height)", pipeMode: pipeOutput)
            printInfo("  Components: \(decodedImage.componentCount)", pipeMode: pipeOutput)
            for c in decodedImage.components {
                printInfo("  [\(c.index)] \(c.width)×\(c.height), \(c.bitDepth)-bit \(c.signed ? "signed" : "unsigned")", pipeMode: pipeOutput)
            }
            return
        }

        // Post-processing: bit depth conversion
        var image = decodedImage
        if let targetBD = bitDepthConvert {
            image = convertBitDepth(image, to: targetBD)
        }

        // Derive output path if not specified (after decoding, so component count is known)
        let outputPath: String
        if let o = explicitOutput {
            outputPath = o
        } else {
            outputPath = deriveOutputPath(inputPath: inputPath, command: "decode", options: options, componentCount: image.componentCount)
        }

        // Write output
        if verbose { printInfo("Writing: \(outputPath)", pipeMode: pipeOutput) }
        let startWrite = Date()
        if pipeOutput {
            try saveImageToStdout(image, format: outputFormat)
        } else {
            try saveImage(image, to: outputPath)
        }
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
                "resolutionLevel": resolutionLevel as Any,
                "qualityLayer": qualityLayer as Any,
                "timing": [
                    "load": loadTime,
                    "decode": decodeTime,
                    "write": writeTime,
                    "total": loadTime + decodeTime + writeTime
                ]
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                printInfo(jsonString, pipeMode: pipeOutput)
            }
        } else if !quiet {
            printInfo("Decoded: \(inputPath) -> \(outputPath)", pipeMode: pipeOutput)
            printInfo("  Input size: \(formatBytes(encodedData.count))", pipeMode: pipeOutput)
            printInfo("  Output: \(image.width)×\(image.height), \(image.componentCount) component(s)", pipeMode: pipeOutput)
            if showTiming {
                printInfo("  Timing:", pipeMode: pipeOutput)
                printInfo("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Decode: \(String(format: "%7.3f", decodeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms", pipeMode: pipeOutput)
                printInfo("    Total:  \(String(format: "%7.3f", (loadTime + decodeTime + writeTime) * 1000)) ms", pipeMode: pipeOutput)
            }
        }
    }

    private static func printDecodeHelp() {
        print("""
        j2k decode - Decode a JPEG 2000 image

        USAGE:
            j2k decode -i <input> [-o <output>] [options]

        OPTIONS:
            -i, --input PATH            Input file (.j2k, .jp2, .jpx)
            -o, --output PATH           Output image (optional; derived from input if omitted)
            --output-format FORMAT      Output format: pgm, ppm, tiff, png
            --level N                   Resolution level (0 = full)
            --layer N                   Quality layer
            --component N               Single component index
            --components N,M,...        Component indices
            --colour-space              Convert colour space
            --gpu / --no-gpu            GPU acceleration
            --verbose                   Verbose output
            --quiet                     Suppress output
            --timing                    Timing breakdown
            --json                      JSON output

        PIPING:
            -i -                        Read input from stdin
            -o -                        Write output to stdout (PNM format)
            When piping, diagnostic messages are sent to stderr.

        EXAMPLES:
            j2k decode -i input.j2k -o output.pgm
            j2k decode -i input.jp2 -o output.tiff
            j2k decode -i input.j2k
            j2k decode -i input.j2k -o - | other-tool -i -
        """)
    }

    /// Wraps a raw J2K codestream in a minimal JP2 container.
    ///
    /// Builds a JP2 file with four boxes: JP2 signature, file-type, JP2 header
    /// (containing image-header and colour-specification sub-boxes), and the
    /// contiguous codestream box (`jp2c`) that holds the supplied codestream.
    ///
    /// - Parameters:
    ///   - codestream: The raw JPEG 2000 codestream bytes.
    ///   - image: The decoded image, used to populate the image-header box.
    /// - Returns: A valid JP2 file as `Data`.
    static func wrapInJP2Container(_ codestream: Data, image: J2KImage) -> Data {
        // JP2 signature box
        var out = Data()
        func appendBox(type: String, payload: Data) {
            var boxLen = UInt32(payload.count + 8).bigEndian
            out.append(contentsOf: withUnsafeBytes(of: &boxLen) { Array($0) })
            out.append(type.data(using: .ascii)!)
            out.append(payload)
        }

        // Signature box
        appendBox(type: "jP  ", payload: Data([0x0D, 0x0A, 0x87, 0x0A]))

        // File-type box
        var ftPayload = Data()
        ftPayload.append("jp2 ".data(using: .ascii)!)           // brand
        ftPayload.append(contentsOf: [0, 0, 0, 0] as [UInt8])  // minor version
        ftPayload.append("jp2 ".data(using: .ascii)!)           // compat
        appendBox(type: "ftyp", payload: ftPayload)

        // JP2 Header box (ihdr + colr)
        var ihdrPayload = Data(count: 14)
        let w = UInt32(image.width).bigEndian
        let h = UInt32(image.height).bigEndian
        let nc = UInt16(image.componentCount).bigEndian
        let bd = UInt8(image.components.first?.bitDepth ?? 8) - 1
        withUnsafeBytes(of: h) { ihdrPayload.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: w) { ihdrPayload.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: nc) { ihdrPayload.replaceSubrange(8..<10, with: $0) }
        ihdrPayload[10] = bd
        ihdrPayload[11] = 7   // C = 7 (JPEG 2000 compression)
        ihdrPayload[12] = 0   // UnkC
        ihdrPayload[13] = 0   // IPR
        appendBox(type: "ihdr", payload: ihdrPayload)

        // Codestream box
        appendBox(type: "jp2c", payload: codestream)

        return out
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
