//
// Decode3D.swift
// J2KSwift
//
/// 3D volumetric decoding command using the J2K3D (JP3D) module.

import Foundation
import J2KCore
import J2KCodec
import J2K3D

extension J2KCLI {

    /// Decode3D command: decompress volumetric / 3D data.
    static func decode3DCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printDecode3DHelp()
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
        let showTiming = options["timing"] != nil

        if verbose { print("Loading: \(inputPath)") }
        let startTime = Date()

        // Load compressed data
        let compressedData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let loadTime = Date().timeIntervalSince(startTime)

        // Configure decoder
        var decoderConfig = JP3DDecoderConfiguration.default

        // Parse slice range if specified
        let sliceRange: ClosedRange<Int>?
        if let rangeStr = options["slice-range"] {
            let parts = rangeStr.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                sliceRange = parts[0]...parts[1]
            } else {
                print("Error: Invalid slice-range format. Expected START:END (e.g. 10:20)")
                exit(1)
            }
        } else {
            sliceRange = nil
        }

        // Decode
        if verbose { print("Decoding...") }
        let decodeStart = Date()

        let decoder = JP3DDecoder(configuration: decoderConfig)
        let decodedVolume: J2KVolume

        if let range = sliceRange {
            // Region-of-interest decode via ROI decoder
            let roiDecoder = JP3DROIDecoder(configuration: decoderConfig)
            let metadata = try await decoder.peekMetadata(compressedData)
            let region = JP3DRegion(
                originX: 0,
                originY: 0,
                originZ: range.lowerBound,
                width: metadata.width,
                height: metadata.height,
                depth: range.count
            )
            let roiResult = try await roiDecoder.decode(compressedData, region: region)
            decodedVolume = roiResult.volume
        } else {
            let fullResult = try await decoder.decode(compressedData)
            decodedVolume = fullResult.volume
        }

        let decodeTime = Date().timeIntervalSince(decodeStart)

        // Extract volume info
        let resultWidth = decodedVolume.width
        let resultHeight = decodedVolume.height
        let resultDepth = decodedVolume.depth

        // Output handling
        let fm = FileManager.default
        let writeStart = Date()

        let outputFormat = options["output-format"] ?? URL(fileURLWithPath: outputPath).pathExtension.lowercased()

        if outputFormat == "raw" {
            // Write as raw volumetric data — concatenate all component data
            var rawOutput = Data()
            for component in decodedVolume.components {
                rawOutput.append(component.data)
            }
            try rawOutput.write(to: URL(fileURLWithPath: outputPath))
            if verbose { print("Written raw volume to: \(outputPath)") }
        } else {
            // Write as directory of 2D slices
            try fm.createDirectory(atPath: outputPath, withIntermediateDirectories: true)

            let sliceNaming = options["slice-naming"] ?? "slice_%04d"
            let sliceExt = outputFormat.isEmpty ? "pgm" : outputFormat
            let sliceSize = resultWidth * resultHeight
            let componentData = decodedVolume.components.first?.data ?? Data()
            let bitDepth = decodedVolume.components.first?.bitDepth ?? 8

            for z in 0..<resultDepth {
                let sliceName = String(format: sliceNaming, z) + ".\(sliceExt)"
                let slicePath = (outputPath as NSString).appendingPathComponent(sliceName)

                let sliceStart = z * sliceSize
                let sliceEnd = min(sliceStart + sliceSize, componentData.count)
                let sliceData: Data
                if sliceStart < componentData.count {
                    sliceData = componentData.subdata(in: sliceStart..<sliceEnd)
                } else {
                    sliceData = Data(count: sliceSize)
                }

                let component = J2KComponent(
                    index: 0,
                    bitDepth: bitDepth,
                    signed: false,
                    width: resultWidth,
                    height: resultHeight,
                    subsamplingX: 1,
                    subsamplingY: 1,
                    data: sliceData
                )

                let sliceImage = J2KImage(
                    width: resultWidth,
                    height: resultHeight,
                    components: [component],
                    colorSpace: .grayscale
                )

                try saveImage(sliceImage, to: slicePath)
            }

            if verbose { print("Written \(resultDepth) slices to: \(outputPath)") }
        }

        let writeTime = Date().timeIntervalSince(writeStart)
        let totalTime = Date().timeIntervalSince(startTime)
        let totalVoxels = resultWidth * resultHeight * resultDepth

        if jsonOutput {
            let resultDict: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "width": resultWidth,
                "height": resultHeight,
                "depth": resultDepth,
                "voxels": totalVoxels,
                "inputSize": compressedData.count,
                "timing": [
                    "load": loadTime,
                    "decode": decodeTime,
                    "write": writeTime,
                    "total": totalTime
                ]
            ]
            printJSON(resultDict)
        } else if !quiet {
            print("Decoded 3D: \(inputPath) -> \(outputPath)")
            print("  Volume:  \(resultWidth)×\(resultHeight)×\(resultDepth) (\(totalVoxels) voxels)")
            print("  Input:   \(formatBytes(compressedData.count))")
            if showTiming {
                print("  Timing:")
                print("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms")
                print("    Decode: \(String(format: "%7.3f", decodeTime * 1000)) ms")
                print("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms")
                print("    Total:  \(String(format: "%7.3f", totalTime * 1000)) ms")
                let vps = Double(totalVoxels) / 1_000_000 / decodeTime
                print("    Throughput: \(String(format: "%.2f", vps)) Mvoxel/s")
            }
        }
    }

    // MARK: - Help

    private static func printDecode3DHelp() {
        print("""
        j2k decode3d - Decompress volumetric / 3D data (JP3D)

        USAGE:
            j2k decode3d -i <input> -o <output_dir> [options]

        OPTIONS:
            -i, --input PATH            Input JP3D file
            -o, --output PATH|DIR       Output directory (slices) or file (raw)
            --output-format pgm|ppm|raw Output format (default: pgm)
            --slice-range START:END     Extract slice range (e.g. 10:20)
            --region x,y,z,w,h,d        3D region of interest
            --scale N                   Multi-resolution decode (1, 2, 4, 8)
            --slice-naming PATTERN      Slice filename pattern (default: slice_%04d)
            --verbose                   Verbose output
            --quiet                     Suppress output
            --timing                    Show timing breakdown
            --json                      JSON output

        EXAMPLES:
            j2k decode3d -i volume.jp3d -o ./slices/ --output-format pgm
            j2k decode3d -i volume.jp3d -o volume.raw --output-format raw
            j2k decode3d -i volume.jp3d -o ./slices/ --slice-range 10:20
        """)
    }
}
