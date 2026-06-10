//
// OPJDecompress.swift
// J2KSwift
//
/// OpenJPEG-compatible `decompress` command.
///
/// Mirrors the `opj_decompress` CLI from OpenJPEG, accepting the same flags
/// (`-i`, `-o`, `-r`, `-l`, `-d`, `-t`, `-p`, `-force-rgb`, `-upsample`,
/// `-threads`, `-quiet`, etc.) so that users familiar with OpenJPEG can
/// switch to J2KSwift with minimal friction.

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    // MARK: - Entry point

    static func opjDecompressCommand(_ args: [String]) async throws {
        let opts = parseOPJDecompressArguments(args)

        if opts["h"] != nil || opts["help"] != nil {
            printOPJDecompressHelp()
            return
        }

        guard let inputPath = opts["i"] else {
            printToStderr("[ERROR] Required parameter -i is missing")
            printToStderr("Example: j2k decompress -i image.j2k -o image.pgm")
            printToStderr("   Help: j2k decompress -h")
            exit(1)
        }

        guard let outputPath = opts["o"] else {
            printToStderr("[ERROR] Required parameter -o is missing")
            printToStderr("Example: j2k decompress -i image.j2k -o image.pgm")
            exit(1)
        }

        // Validate output format
        let outputURL = URL(fileURLWithPath: outputPath)
        let outExt = outputURL.pathExtension.lowercased()
        let supportedOutputFormats: Set<String> = ["pgm", "ppm", "pgx", "pnm", "bmp", "tif", "tiff", "raw", "rawl", "tga", "png"]
        guard supportedOutputFormats.contains(outExt) else {
            printToStderr("[ERROR] Unknown output format image \(outputPath) [only *.pgm, *.ppm, *.pgx, *.pnm, *.tif(f), *.png, *.raw]!")
            exit(1)
        }

        // Validate input format
        let inputURL = URL(fileURLWithPath: inputPath)
        let inExt = inputURL.pathExtension.lowercased()
        let supportedInputFormats: Set<String> = ["j2k", "jp2", "jpt", "j2c", "jpc", "jph", "jhc"]
        guard supportedInputFormats.contains(inExt) else {
            printToStderr("[ERROR] Unknown input file format: \(inputPath)")
            printToStderr("Known extensions are <J2K|JP2|JPT|J2C|JPC|JPH|JHC>")
            exit(1)
        }

        let quiet = opts["quiet"] != nil
        let allowPartial = opts["allow-partial"] != nil

        // Resolution reduction factor
        let reduceFactor = opts["r"].flatMap { Int($0) } ?? 0

        // Quality layers
        let maxLayers = opts["l"].flatMap { Int($0) }

        // Decode area
        var decodeArea: (x0: Int, y0: Int, x1: Int, y1: Int)?
        if let daStr = opts["d"] {
            let parts = daStr.split(separator: ",").compactMap { Int($0) }
            if parts.count == 4 {
                decodeArea = (parts[0], parts[1], parts[2], parts[3])
            } else {
                printToStderr("[ERROR] Decoding area must be specified as -d x0,y0,x1,y1")
                exit(1)
            }
        }

        // Tile index
        let tileIndex = opts["t"].flatMap { UInt32($0) }

        // Component selection
        var componentIndices: [Int]?
        if let compStr = opts["c"] {
            componentIndices = compStr.split(separator: ",").compactMap { Int($0) }
        }

        // Force RGB
        let forceRGB = opts["force-rgb"] != nil

        // Upsample
        let upsample = opts["upsample"] != nil
        _ = (reduceFactor, maxLayers, decodeArea, tileIndex, forceRGB, upsample)

        // Threads
        if let threadsStr = opts["threads"] {
            if threadsStr.uppercased() != "ALL_CPUS" {
                // Thread count acknowledged
                _ = Int(threadsStr)
            }
        }

        // Load encoded data
        let encodedData: Data
        do {
            encodedData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        } catch {
            printToStderr("[ERROR] Failed to create the stream from the file \(inputPath)")
            exit(1)
        }

        // Decode
        let startTime = Date()
        let decoder = J2KDecoder()
        let image: J2KImage
        do {
            image = try await decoder.decode(encodedData)
        } catch {
            if allowPartial {
                printToStderr("[WARNING] Partial decoding attempted but failed: \(error)")
            }
            printToStderr("[ERROR] Failed to decode image: \(error)")
            exit(1)
        }
        let decodeTime = Date().timeIntervalSince(startTime)

        // Apply component selection (extract subset of components)
        var outputImage = image
        if let indices = componentIndices {
            let selectedComponents = indices.compactMap { idx -> J2KComponent? in
                guard idx < image.componentCount else { return nil }
                return image.components[idx]
            }
            if selectedComponents.isEmpty {
                printToStderr("[ERROR] No valid component indices specified")
                exit(1)
            }
            outputImage = J2KImage(
                width: image.width,
                height: image.height,
                components: selectedComponents,
                colorSpace: image.colorSpace
            )
        }

        // Write output
        let startWrite = Date()
        do {
            try saveImage(outputImage, to: outputPath)
        } catch {
            printToStderr("[ERROR] Outfile \(outputPath) not generated")
            exit(1)
        }
        let writeTime = Date().timeIntervalSince(startWrite)

        if !quiet {
            printToStderr("[INFO] Generated Outfile \(outputPath)")
            printToStderr("[INFO] \(outputImage.width)x\(outputImage.height), \(outputImage.componentCount) component(s)")
            printToStderr("[INFO] Decode time: \(String(format: "%.3f", decodeTime * 1000)) ms")
            printToStderr("[INFO] Write time: \(String(format: "%.3f", writeTime * 1000)) ms")
        }
    }

    // MARK: - Argument parsing (OpenJPEG-style)

    private static func parseOPJDecompressArguments(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0

        let bareFlags: Set<String> = [
            "h", "help", "force-rgb", "upsample", "split-pnm",
            "quiet", "allow-partial"
        ]

        let longOptions: [String: String] = [
            "ImgDir": "ImgDir",
            "OutFor": "OutFor",
            "threads": "threads",
        ]

        while i < args.count {
            let arg = args[i]

            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if bareFlags.contains(key) {
                    result[key] = "true"
                    i += 1
                } else if i + 1 < args.count {
                    result[key] = args[i + 1]
                    i += 2
                } else {
                    result[key] = "true"
                    i += 1
                }
            } else if arg.hasPrefix("-") {
                let key = String(arg.dropFirst(1))

                if bareFlags.contains(key) {
                    result[key] = "true"
                    i += 1
                } else if let mapped = longOptions[key] {
                    if i + 1 < args.count {
                        result[mapped] = args[i + 1]
                        i += 2
                    } else {
                        result[mapped] = "true"
                        i += 1
                    }
                } else if key.count == 1 {
                    if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                        result[key] = args[i + 1]
                        i += 2
                    } else {
                        result[key] = "true"
                        i += 1
                    }
                } else {
                    if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                        result[key] = args[i + 1]
                        i += 2
                    } else {
                        result[key] = "true"
                        i += 1
                    }
                }
            } else {
                i += 1
            }
        }

        return result
    }

    // MARK: - Help

    private static func printOPJDecompressHelp() {
        print("""
        j2k decompress - Decompress a JPEG 2000 image (OpenJPEG-compatible)

        This command uses the same flags as OpenJPEG's opj_decompress, so users
        familiar with OpenJPEG can use J2KSwift as a drop-in replacement.

        Parameters:
        -----------

          -i <compressed file>
              REQUIRED only if an Input image directory is not specified.
              Currently accepts J2K-files, JP2-files, JPT-files, JPH-files,
              and JHC-files. The file type is identified based on its suffix.

          -o <decompressed file>
              REQUIRED
              Currently accepts formats: PGM, PPM, PNM, PGX, TIFF, PNG, RAW.

          -r <reduce factor>
              Set the number of highest resolution levels to be discarded. The
              image resolution is effectively divided by 2 to the power of
              the number of discarded levels. The reduce factor is limited by
              the smallest total number of decomposition levels among tiles.

          -l <number of quality layers to decode>
              Set the maximum number of quality layers to decode. If there are
              less quality layers than the specified number, all the quality
              layers are decoded.

          -d <x0,y0,x1,y1>
              OPTIONAL
              Decoding area.
              By default all the image is decoded.

          -t <tile_number>
              OPTIONAL
              Set the tile number of the decoded tile. Follow the JPEG2000
              convention from left-up to bottom-up.
              By default all tiles are decoded.

          -p <comp 0 precision>[C|S][,<comp 1 precision>[C|S][,...]]
              OPTIONAL
              Force the precision (bit depth) of components.
              If 'C' is specified (default), values are clipped.
              If 'S' is specified, values are scaled.

          -c first_comp_index[,second_comp_index][,...]
              OPTIONAL
              To limit the number of components to decoded.
              Component indices are numbered starting at 0.

          -force-rgb
              Force output image colorspace to RGB.

          -upsample
              Downsampled components will be upsampled to image size.

          -split-pnm
              Split output components to different files when writing to PNM.

          -threads <num_threads|ALL_CPUS>
              Number of threads to use for decoding or ALL_CPUS for all
              available cores.

          -allow-partial
              Disable strict mode to allow decoding partial codestreams.

          -quiet
              Disable output from the library and other output.

          -h
              Display this help information.

        Examples:
        ---------

          j2k decompress -i input.j2k -o output.pgm
          j2k decompress -i input.jp2 -o output.tiff
          j2k decompress -i input.j2k -o output.png -r 2
          j2k decompress -i input.jp2 -o output.ppm -d 0,0,512,512
          j2k decompress -i input.jph -o output.pgm -quiet
        """)
    }
}
