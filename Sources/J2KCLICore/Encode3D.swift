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

        guard let inputPath = options["i"] ?? options["input"] ?? options["slice-dir"] else {
            print("Error: Missing required argument: -i/--input or --slice-dir")
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
        let spacing = try parseVector3Option(options["spacing"], optionName: "spacing")
        let origin = try parseVector3Option(options["origin"], optionName: "origin")

        if isDir.boolValue {
            // Load from a directory of 2D slices, including CT DICOM slices.
            let supportedExtensions: Set<String> = ["pgm", "ppm", "png", "tif", "tiff", "dcm", "dicom"]
            let sliceFiles = try fm.contentsOfDirectory(atPath: inputPath)
                .filter { name in
                    let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
                    return supportedExtensions.contains(ext)
                }
                .sorted { lhs, rhs in
                    lhs.localizedStandardCompare(rhs) == .orderedAscending
                }

            guard !sliceFiles.isEmpty else {
                print("Error: No supported slice files found in \(inputPath)")
                exit(1)
            }

            if verbose {
                print("  Loading \(sliceFiles.count) slices...")
            }

            var slices: [J2KImage] = []
            slices.reserveCapacity(sliceFiles.count)

            for filename in sliceFiles {
                let slicePath = (inputPath as NSString).appendingPathComponent(filename)
                slices.append(try loadImage(from: slicePath))
            }

            volume = try makeVolumeFromSlices(slices, spacing: spacing, origin: origin)
            volumeWidth = volume.width
            volumeHeight = volume.height
            volumeDepth = volume.depth

            if verbose {
                let bitDepth = volume.components.map(\ .bitDepth).max() ?? 8
                print("  Volume: \(volumeWidth)×\(volumeHeight)×\(volumeDepth), \(volume.componentCount) component(s), \(bitDepth)-bit")
            }
        } else {
            // Load raw volumetric data.
            let dims = try parseVolumeDimensions(options)
            volumeWidth = dims.width
            volumeHeight = dims.height
            volumeDepth = dims.depth

            let componentCount = max(1, Int(options["components"] ?? "1") ?? 1)
            let bitDepth = max(1, Int(options["bit-depth"] ?? "8") ?? 8)
            let isSigned = options["signed"] != nil

            volume = try loadRawVolume(
                from: inputPath,
                width: volumeWidth,
                height: volumeHeight,
                depth: volumeDepth,
                componentCount: componentCount,
                bitDepth: bitDepth,
                signed: isSigned,
                spacing: spacing,
                origin: origin
            )

            if verbose {
                print("  Volume: \(volumeWidth)×\(volumeHeight)×\(volumeDepth), \(componentCount) component(s), \(bitDepth)-bit")
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

    // MARK: - Helpers

    static func parseVolumeDimensions(_ options: [String: String]) throws -> (width: Int, height: Int, depth: Int) {
        if let dimStr = options["dimensions"] {
            let dims = dimStr
                .split(whereSeparator: { $0 == "x" || $0 == "X" })
                .compactMap { Int($0) }
            guard dims.count == 3 else {
                throw J2KError.invalidParameter(
                    "Invalid dimensions format. Expected WxHxD (e.g. 256x256x128)"
                )
            }
            return (width: dims[0], height: dims[1], depth: dims[2])
        }

        guard let width = Int(options["width"] ?? ""),
              let height = Int(options["height"] ?? ""),
              let depth = Int(options["depth"] ?? "") else {
            throw J2KError.invalidParameter(
                "Raw input requires --dimensions WxHxD or --width/--height/--depth"
            )
        }

        return (width: width, height: height, depth: depth)
    }

    static func parseVector3Option(
        _ rawValue: String?,
        optionName: String
    ) throws -> (Double, Double, Double)? {
        guard let rawValue else { return nil }

        let values = rawValue
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }

        guard values.count == 3 else {
            throw J2KError.invalidParameter(
                "Invalid --\(optionName) format. Expected x,y,z"
            )
        }

        return (values[0], values[1], values[2])
    }

    static func makeVolumeFromSlices(
        _ slices: [J2KImage],
        spacing: (Double, Double, Double)? = nil,
        origin: (Double, Double, Double)? = nil
    ) throws -> J2KVolume {
        guard let firstSlice = slices.first else {
            throw J2KError.invalidParameter("At least one slice is required to build a volume")
        }

        let width = firstSlice.width
        let height = firstSlice.height
        let depth = slices.count
        let componentCount = firstSlice.componentCount

        var componentBuffers = Array(repeating: Data(), count: componentCount)
        var bitDepths: [Int] = []
        var signedFlags: [Bool] = []
        bitDepths.reserveCapacity(componentCount)
        signedFlags.reserveCapacity(componentCount)

        for component in firstSlice.components {
            bitDepths.append(component.bitDepth)
            signedFlags.append(component.signed)
        }

        for (sliceIndex, slice) in slices.enumerated() {
            guard slice.width == width, slice.height == height else {
                throw J2KError.invalidDimensions(
                    "Slice \(sliceIndex) has mismatched dimensions: expected \(width)×\(height), got \(slice.width)×\(slice.height)"
                )
            }
            guard slice.componentCount == componentCount else {
                throw J2KError.invalidComponentConfiguration(
                    "Slice \(sliceIndex) has mismatched component count: expected \(componentCount), got \(slice.componentCount)"
                )
            }

            for componentIndex in 0..<componentCount {
                let component = slice.components[componentIndex]
                guard component.bitDepth == bitDepths[componentIndex],
                      component.signed == signedFlags[componentIndex] else {
                    throw J2KError.invalidComponentConfiguration(
                        "Slice \(sliceIndex) component \(componentIndex) does not match the first slice's format"
                    )
                }
                componentBuffers[componentIndex].append(component.data)
            }
        }

        let volumeComponents = (0..<componentCount).map { componentIndex in
            J2KVolumeComponent(
                index: componentIndex,
                bitDepth: bitDepths[componentIndex],
                signed: signedFlags[componentIndex],
                width: width,
                height: height,
                depth: depth,
                data: componentBuffers[componentIndex]
            )
        }

        let volume = J2KVolume(
            width: width,
            height: height,
            depth: depth,
            components: volumeComponents,
            spacingX: spacing?.0 ?? 0,
            spacingY: spacing?.1 ?? 0,
            spacingZ: spacing?.2 ?? 0,
            originX: origin?.0 ?? 0,
            originY: origin?.1 ?? 0,
            originZ: origin?.2 ?? 0
        )
        try volume.validate()
        return volume
    }

    static func loadRawVolume(
        from path: String,
        width: Int,
        height: Int,
        depth: Int,
        componentCount: Int,
        bitDepth: Int,
        signed: Bool,
        spacing: (Double, Double, Double)? = nil,
        origin: (Double, Double, Double)? = nil
    ) throws -> J2KVolume {
        let bytesPerSample = max(1, (bitDepth + 7) / 8)
        let voxelsPerComponent = width * height * depth
        let expectedBytesPerComponent = voxelsPerComponent * bytesPerSample
        let expectedTotalBytes = expectedBytesPerComponent * componentCount

        let rawData = try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
        guard rawData.count >= expectedTotalBytes else {
            throw J2KError.invalidParameter(
                "Raw volume is truncated: expected at least \(expectedTotalBytes) bytes, got \(rawData.count)"
            )
        }

        let volumeComponents = (0..<componentCount).map { componentIndex in
            let start = componentIndex * expectedBytesPerComponent
            let end = start + expectedBytesPerComponent
            let componentData = rawData.subdata(in: start..<end)
            return J2KVolumeComponent(
                index: componentIndex,
                bitDepth: bitDepth,
                signed: signed,
                width: width,
                height: height,
                depth: depth,
                data: componentData
            )
        }

        let volume = J2KVolume(
            width: width,
            height: height,
            depth: depth,
            components: volumeComponents,
            spacingX: spacing?.0 ?? 0,
            spacingY: spacing?.1 ?? 0,
            spacingZ: spacing?.2 ?? 0,
            originX: origin?.0 ?? 0,
            originY: origin?.1 ?? 0,
            originZ: origin?.2 ?? 0
        )
        try volume.validate()
        return volume
    }

    // MARK: - Help

    private static func printEncode3DHelp() {
        print("""
        j2k encode3d - Compress volumetric / 3D data (JP3D)

        USAGE:
            j2k encode3d -i <input> -o <output> [options]

        INPUT:
            Directory of 2D slices (PGM, PPM, PNG, TIFF, DICOM) ordered by filename
            Raw volumetric data with --dimensions WxHxD or --width/--height/--depth

        OPTIONS:
            -i, --input PATH|DIR        Input slices directory or raw file
            --slice-dir DIR             Alias for input directory of CT or image slices
            -o, --output PATH           Output JP3D file
            --codec VARIANT             j2k-lossless|j2k-lossy|htj2k-lossless|htj2k-lossy
            --dimensions WxHxD          Volume dimensions (for raw input)
            --bit-depth N               Bit depth (for raw input, default: 8)
            --components N              Number of raw volume components (default: 1)
            --signed                    Treat raw samples as signed
            --spacing X,Y,Z             Optional voxel spacing metadata (for CT/MR)
            --origin X,Y,Z              Optional volume origin metadata
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
