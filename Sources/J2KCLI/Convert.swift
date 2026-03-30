//
// Convert.swift
// J2KSwift
//
/// Convert command — convert between image formats (PGM, PPM, PNM, RAW).

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    /// Convert command: convert between image formats.
    static func convertCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printConvertHelp()
            return
        }

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input")
            exit(1)
        }

        guard let outputPath = options["o"] ?? options["output"] else {
            print("Error: Missing required argument: -o/--output")
            exit(1)
        }

        let verbose = options["verbose"] != nil
        let quiet = options["quiet"] != nil
        let jsonOutput = options["json"] != nil

        if verbose { print("Loading: \(inputPath)") }

        let startTime = Date()

        // Load input — handle both image formats and JPEG 2000 files
        let inputExt = URL(fileURLWithPath: inputPath).pathExtension.lowercased()
        let j2kExts = Set(["j2k", "jp2", "jpx", "jph", "j2c", "jpc"])

        let image: J2KImage
        if j2kExts.contains(inputExt) {
            let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
            let decoder = J2KDecoder()
            image = try decoder.decode(data)
        } else {
            image = try loadImage(from: inputPath)
        }

        // Bit depth conversion
        let outputImage: J2KImage
        if let bitDepthStr = options["bit-depth"], let targetBitDepth = Int(bitDepthStr) {
            outputImage = convertBitDepth(image, to: targetBitDepth)
        } else {
            outputImage = image
        }

        // Determine output format
        let outputExt = (options["output-format"] ?? URL(fileURLWithPath: outputPath).pathExtension).lowercased()

        // Save output
        if j2kExts.contains(outputExt) {
            // Encode to JPEG 2000
            let config = J2KEncodingConfiguration()
            let encoder = J2KEncoder(encodingConfiguration: config)
            let encodedData = try encoder.encode(outputImage)
            try encodedData.write(to: URL(fileURLWithPath: outputPath))
        } else {
            try saveImage(outputImage, to: outputPath)
        }

        let elapsed = Date().timeIntervalSince(startTime)

        if jsonOutput {
            let result: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "width": outputImage.width,
                "height": outputImage.height,
                "components": outputImage.componentCount,
                "time": elapsed
            ]
            printJSON(result)
        } else if !quiet {
            print("Converted: \(inputPath) -> \(outputPath)")
            print("  Dimensions: \(outputImage.width)×\(outputImage.height), \(outputImage.componentCount) component(s)")
            print("  Time: \(String(format: "%.1f", elapsed * 1000)) ms")
        }
    }

    // MARK: - Bit Depth Conversion

    /// Convert image bit depth (e.g. 16-bit to 8-bit or vice versa).
    static func convertBitDepth(_ image: J2KImage, to targetBitDepth: Int) -> J2KImage {
        var newComponents: [J2KComponent] = []

        for comp in image.components {
            if comp.bitDepth == targetBitDepth {
                newComponents.append(comp)
                continue
            }

            let pixelCount = comp.width * comp.height
            let sourceBPP = comp.bitDepth <= 8 ? 1 : 2
            let targetBPP = targetBitDepth <= 8 ? 1 : 2

            var newData = Data(count: pixelCount * targetBPP)
            let sourceMax = Double((1 << comp.bitDepth) - 1)
            let targetMax = Double((1 << targetBitDepth) - 1)

            for i in 0..<pixelCount {
                let sourceVal: Int
                if sourceBPP == 1 {
                    sourceVal = i < comp.data.count ? Int(comp.data[i]) : 0
                } else {
                    let idx = i * 2
                    if idx + 1 < comp.data.count {
                        sourceVal = Int(comp.data[idx]) | (Int(comp.data[idx + 1]) << 8)
                    } else {
                        sourceVal = 0
                    }
                }

                let normalised = Double(sourceVal) / sourceMax
                let targetVal = Int(normalised * targetMax + 0.5)
                let clamped = max(0, min(Int(targetMax), targetVal))

                if targetBPP == 1 {
                    newData[i] = UInt8(clamped)
                } else {
                    let idx = i * 2
                    newData[idx] = UInt8(clamped & 0xFF)
                    newData[idx + 1] = UInt8((clamped >> 8) & 0xFF)
                }
            }

            newComponents.append(J2KComponent(
                index: comp.index,
                bitDepth: targetBitDepth,
                signed: comp.signed,
                width: comp.width,
                height: comp.height,
                subsamplingX: comp.subsamplingX,
                subsamplingY: comp.subsamplingY,
                data: newData
            ))
        }

        return J2KImage(
            width: image.width,
            height: image.height,
            components: newComponents,
            colorSpace: image.colorSpace
        )
    }

    // MARK: - Help

    private static func printConvertHelp() {
        print("""
        j2k convert - Convert between image formats

        USAGE:
            j2k convert -i <input> -o <output> [options]

        OPTIONS:
            -i, --input PATH            Input image
            -o, --output PATH           Output image
            --bit-depth N               Target bit depth (8 or 16)
            --output-format FORMAT      Output format: pgm, ppm, pnm, raw
            --verbose                   Verbose output
            --quiet                     Suppress output
            --json                      JSON output

        SUPPORTED FORMATS:
            PGM     Portable GrayMap (grayscale)
            PPM     Portable PixMap (RGB)
            J2K     JPEG 2000 codestream
            JP2     JPEG 2000 Part 1 container
            JPX     JPEG 2000 Part 2 container
            JPH     HTJ2K codestream

        EXAMPLES:
            j2k convert -i input.pgm -o output.ppm
            j2k convert -i input.j2k -o output.pgm
            j2k convert -i input.pgm -o output.pgm --bit-depth 16
        """)
    }
}
