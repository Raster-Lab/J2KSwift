//
// Transcode.swift
// J2KSwift
//
/// Transcode command – convert between JPEG 2000 formats

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    /// Transcode command: re-encode a JPEG 2000 file in a different format or configuration.
    static func transcodeCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printTranscodeHelp()
            return
        }

        let verbose = options["verbose"] != nil
        let quiet   = options["quiet"]   != nil

        // Batch mode
        if let batchDir = options["batch"] {
            guard let outputDir = options["output-dir"] else {
                print("Error: --batch requires --output-dir")
                exit(1)
            }
            try await transcodeDirectory(batchDir, to: outputDir, options: options, verbose: verbose, quiet: quiet)
            return
        }

        // Single-file mode
        let inputPath: String
        if let p = options["i"] ?? options["input"] {
            inputPath = p
        } else if let p = options["_positional"] {
            inputPath = p
        } else {
            print("Error: Missing -i/--input argument")
            exit(1)
        }

        guard let outputPath = options["o"] ?? options["output"] else {
            print("Error: Missing -o/--output argument")
            exit(1)
        }

        try await transcodeFile(inputPath, to: outputPath, options: options, verbose: verbose, quiet: quiet)
    }

    // MARK: - Single-file transcode

    private static func transcodeFile(
        _ inputPath: String,
        to outputPath: String,
        options: [String: String],
        verbose: Bool,
        quiet: Bool
    ) async throws {
        if verbose { print("Transcoding: \(inputPath) -> \(outputPath)") }

        let inputData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let containerFormat = detectContainerFormat(inputData)
        let codestreamData  = extractCodestream(from: inputData, format: containerFormat)

        let isHTJ2KSource   = detectHTJ2K(codestreamData)
        let toHTJ2K         = options["to-htj2k"]   != nil
        let fromHTJ2K       = options["from-htj2k"]  != nil

        let outputFormat    = options["format"] ?? URL(fileURLWithPath: outputPath).pathExtension.lowercased()

        let startTime = Date()

        var outputData: Data

        if toHTJ2K || fromHTJ2K {
            // Use the J2KTranscoder for HTJ2K ↔ Part-1 conversions
            let direction: TranscodingDirection = toHTJ2K ? .legacyToHT : .htToLegacy
            let transcoder = J2KTranscoder(configuration: .default)
            let result = try transcoder.transcode(codestreamData, direction: direction)
            outputData = result.data
            if verbose {
                print("  Transcoded \(result.codeBlocksTranscoded) code-blocks in \(String(format: "%.1f", result.transcodingTime * 1000)) ms")
            }
        } else {
            // General re-encode path: decode then encode
            let decoder = J2KDecoder()
            let image   = try decoder.decode(codestreamData)

            var config = J2KEncodingConfiguration()

            if let qualStr = options["quality"], let q = Double(qualStr) { config.quality = q }
            if let bpStr  = options["bitrate"],  let b = Double(bpStr)  { config.bitrateMode = .constantBitrate(bitsPerPixel: b) }
            if let layStr = options["layers"],   let l = Int(layStr)    { config.qualityLayers = l }
            if let progStr = options["progression"],
               let order = J2KProgressionOrder(rawValue: progStr.uppercased()) {
                config.progressionOrder = order
            }

            let encoder = J2KEncoder(encodingConfiguration: config)
            outputData = try encoder.encode(image)
        }

        // Wrap in container if required
        if outputFormat == "jp2" || outputFormat == "jpx" {
            let decoder = J2KDecoder()
            do {
                let image = try decoder.decode(outputData)
                outputData = wrapInJP2Container(outputData, image: image)
            } catch {
                if verbose {
                    print("Warning: could not wrap output in JP2 container: \(error). Writing raw codestream.")
                }
            }
        }

        try outputData.write(to: URL(fileURLWithPath: outputPath))

        let elapsed = Date().timeIntervalSince(startTime) * 1000
        if !quiet {
            print("Transcoded: \(inputPath) -> \(outputPath) (\(String(format: "%.1f", elapsed)) ms)")
            let ratio = Double(inputData.count) / Double(outputData.count)
            print("  Input:  \(formatBytes(inputData.count))  Output: \(formatBytes(outputData.count))  ratio \(String(format: "%.2f", ratio)):1")
            if isHTJ2KSource { print("  Source: HTJ2K") }
        }
    }

    // MARK: - Batch mode

    private static func transcodeDirectory(
        _ inputDir: String,
        to outputDir: String,
        options: [String: String],
        verbose: Bool,
        quiet: Bool
    ) async throws {
        let fm = FileManager.default

        // Create output directory if needed
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let contents = try fm.contentsOfDirectory(atPath: inputDir)
        let j2kFiles = contents.filter { name in
            let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
            return ext == "j2k" || ext == "jp2" || ext == "jpx" || ext == "jpc"
        }

        if j2kFiles.isEmpty {
            if !quiet { print("No JPEG 2000 files found in: \(inputDir)") }
            return
        }

        let outputFmt = options["format"] ?? "j2k"
        var successCount = 0
        var failCount    = 0

        for filename in j2kFiles.sorted() {
            let inputPath  = (inputDir as NSString).appendingPathComponent(filename)
            let baseName   = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            let outputName = baseName + "." + outputFmt
            let outputPath = (outputDir as NSString).appendingPathComponent(outputName)

            do {
                try await transcodeFile(inputPath, to: outputPath, options: options, verbose: verbose, quiet: quiet)
                successCount += 1
            } catch {
                print("  Error processing \(filename): \(error.localizedDescription)")
                failCount += 1
            }
        }

        if !quiet {
            print("\nBatch complete: \(successCount) succeeded, \(failCount) failed")
        }
    }

    // MARK: - Help

    private static func printTranscodeHelp() {
        print("""
        j2k transcode - Transcode between JPEG 2000 formats

        USAGE:
            j2k transcode -i <input> -o <output> [options]
            j2k transcode --batch <dir> --output-dir <dir> [options]

        OPTIONS:
            -i, --input PATH            Input JPEG 2000 file
            -o, --output PATH           Output JPEG 2000 file
            --to-htj2k                  Transcode to HTJ2K (Part 15)
            --from-htj2k                Transcode from HTJ2K to Part 1
            --format j2k|jp2|jpx        Output container format
            --quality VALUE             Quality (0.0-1.0)
            --bitrate BPP               Target bit-rate (bits per pixel)
            --layers N                  Quality layers
            --progression ORDER         LRCP|RLCP|RPCL|PCRL|CPRL
            --batch DIR                 Input directory for batch mode
            --output-dir DIR            Output directory for batch mode
            --verbose                   Verbose output
            --quiet                     Suppress non-error output
        """)
    }
}
