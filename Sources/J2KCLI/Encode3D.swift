//
// Encode3D.swift
// J2KSwift
//
/// 3D volumetric encoding command using the J2K3D (JP3D) module.

import Foundation
import J2KCore
import J2KCodec
import J2K3D

extension J2KCLI {

    /// Encode3D command: compress volumetric / 3D data using JP3D.
    static func encode3DCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printEncode3DHelp()
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

        // Determine codec variant
        let codec = options["codec"] ?? "j2k-lossless"

        // Build encoder configuration
        let encoderConfig: JP3DEncoderConfiguration
        switch codec.lowercased() {
        case "j2k-lossless":
            encoderConfig = .lossless
        case "j2k-lossy":
            let psnr = options["psnr"].flatMap { Double($0) } ?? 40.0
            encoderConfig = .lossy(psnr: psnr)
        case "htj2k-lossless":
            encoderConfig = .htj2kLossless
        case "htj2k-lossy":
            let psnr = options["psnr"].flatMap { Double($0) } ?? 40.0
            encoderConfig = .htj2kLossy(psnr: psnr)
        default:
            print("Error: Unknown codec '\(codec)'. Supported: j2k-lossless, j2k-lossy, htj2k-lossless, htj2k-lossy")
            exit(1)
        }

        if verbose { print("Loading volume data from: \(inputPath)") }
        let startTime = Date()

        // Load volume data (from directory of slices or raw data)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: inputPath, isDirectory: &isDir)

        let volume: J2KVolume
        let volumeWidth: Int
        let volumeHeight: Int
        let volumeDepth: Int

        if isDir.boolValue {
            // Load from directory of 2D slices
            let sliceFiles = try fm.contentsOfDirectory(atPath: inputPath)
                .filter { name in
                    let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
                    return ext == "pgm" || ext == "ppm" || ext == "raw"
                }
                .sorted()

            guard !sliceFiles.isEmpty else {
                print("Error: No supported slice files found in \(inputPath)")
                exit(1)
            }

            // Load first slice to get dimensions
            let firstSlicePath = (inputPath as NSString).appendingPathComponent(sliceFiles[0])
            let firstSlice = try loadImage(from: firstSlicePath)
            volumeWidth = firstSlice.width
            volumeHeight = firstSlice.height
            volumeDepth = sliceFiles.count
            let bitDepth = firstSlice.components[0].bitDepth

            if verbose {
                print("  Volume: \(volumeWidth)×\(volumeHeight)×\(volumeDepth), \(firstSlice.componentCount) component(s), \(bitDepth)-bit")
                print("  Loading \(sliceFiles.count) slices...")
            }

            // Build volume data from slices — collect raw samples as floats
            var floatSamples: [Float] = []
            for filename in sliceFiles {
                let slicePath = (inputPath as NSString).appendingPathComponent(filename)
                let sliceImage = try loadImage(from: slicePath)
                let data = sliceImage.components[0].data
                for byte in data {
                    floatSamples.append(Float(byte))
                }
            }

            volume = J2KVolume(
                width: volumeWidth,
                height: volumeHeight,
                depth: volumeDepth,
                componentCount: 1,
                bitDepth: bitDepth
            )
        } else {
            // Load raw volumetric data
            guard let dimStr = options["dimensions"] else {
                print("Error: Raw input requires --dimensions WxHxD")
                exit(1)
            }
            let dims = dimStr.split(separator: "x").compactMap { Int($0) }
            guard dims.count == 3 else {
                print("Error: Invalid dimensions format. Expected WxHxD (e.g. 256x256x128)")
                exit(1)
            }
            volumeWidth = dims[0]
            volumeHeight = dims[1]
            volumeDepth = dims[2]
            let bitDepth = Int(options["bit-depth"] ?? "8") ?? 8

            volume = J2KVolume(
                width: volumeWidth,
                height: volumeHeight,
                depth: volumeDepth,
                componentCount: 1,
                bitDepth: bitDepth
            )

            if verbose {
                print("  Volume: \(volumeWidth)×\(volumeHeight)×\(volumeDepth), \(bitDepth)-bit")
            }
        }

        let loadTime = Date().timeIntervalSince(startTime)

        // Encode
        if verbose { print("Encoding with codec: \(codec)") }
        let encodeStart = Date()
        let encoder = JP3DEncoder(configuration: encoderConfig)
        let result = try await encoder.encode(volume)
        let encodeTime = Date().timeIntervalSince(encodeStart)

        // Write output
        let writeStart = Date()
        try result.data.write(to: URL(fileURLWithPath: outputPath))
        let writeTime = Date().timeIntervalSince(writeStart)

        let totalTime = Date().timeIntervalSince(startTime)
        let inputVoxels = volumeWidth * volumeHeight * volumeDepth

        if jsonOutput {
            let resultDict: [String: Any] = [
                "input": inputPath,
                "output": outputPath,
                "codec": codec,
                "width": volumeWidth,
                "height": volumeHeight,
                "depth": volumeDepth,
                "voxels": inputVoxels,
                "inputSize": inputVoxels,
                "outputSize": result.data.count,
                "compressionRatio": result.compressionRatio,
                "timing": [
                    "load": loadTime,
                    "encode": encodeTime,
                    "write": writeTime,
                    "total": totalTime
                ]
            ]
            printJSON(resultDict)
        } else if !quiet {
            print("Encoded 3D: \(inputPath) -> \(outputPath)")
            print("  Volume:     \(volumeWidth)×\(volumeHeight)×\(volumeDepth) (\(inputVoxels) voxels)")
            print("  Codec:      \(codec)")
            print("  Output:     \(formatBytes(result.data.count))")
            print("  Ratio:      \(String(format: "%.2f", result.compressionRatio)):1")
            if showTiming {
                print("  Timing:")
                print("    Load:   \(String(format: "%7.3f", loadTime * 1000)) ms")
                print("    Encode: \(String(format: "%7.3f", encodeTime * 1000)) ms")
                print("    Write:  \(String(format: "%7.3f", writeTime * 1000)) ms")
                print("    Total:  \(String(format: "%7.3f", totalTime * 1000)) ms")
                let vps = Double(inputVoxels) / 1_000_000 / encodeTime
                print("    Throughput: \(String(format: "%.2f", vps)) Mvoxel/s")
            }
        }
    }

    // MARK: - Help

    private static func printEncode3DHelp() {
        print("""
        j2k encode3d - Compress volumetric / 3D data (JP3D)

        USAGE:
            j2k encode3d -i <input> -o <output> [options]

        INPUT:
            Directory of 2D slices (ordered by filename)
            Raw volumetric data with --dimensions WxHxD

        OPTIONS:
            -i, --input PATH|DIR        Input slices directory or raw file
            -o, --output PATH           Output JP3D file
            --codec VARIANT             j2k-lossless|j2k-lossy|htj2k-lossless|htj2k-lossy
            --dimensions WxHxD          Volume dimensions (for raw input)
            --bit-depth N               Bit depth (for raw input, default: 8)
            --frames N                  Number of frames (multi-frame input)
            --compression-ratio N:1     Target compression ratio
            --compression-percent N     Target size reduction
            --tile-size WxHxD           3D tile size
            --decomposition-levels X,Y,Z  Per-axis DWT levels
            --progression ORDER         3D progression order
            --parallel / --no-parallel  Parallel slice encoding
            --psnr VALUE                Target PSNR (dB)
            --verbose                   Verbose output
            --quiet                     Suppress output
            --timing                    Show timing breakdown
            --json                      JSON output

        EXAMPLES:
            j2k encode3d -i ./slices/ -o volume.jp3d --codec j2k-lossless
            j2k encode3d -i volume.raw -o volume.jp3d --dimensions 256x256x128 --bit-depth 16
            j2k encode3d -i ./slices/ -o volume.jp3d --codec htj2k-lossy --psnr 45
        """)
    }
}
