//
// Batch.swift
// J2KSwift
//
/// Batch command — batch-process files for encode, decode, or transcode operations.

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    /// Batch command: process multiple files with encode/decode/transcode.
    static func batchCommand(_ args: [String]) async throws {
        guard !args.isEmpty else {
            printBatchHelp()
            exit(1)
        }

        let subcommand = args[0]
        let subArgs = Array(args.dropFirst())
        let options = parseArguments(subArgs)

        if options["help"] != nil {
            printBatchHelp()
            return
        }

        let verbose = options["verbose"] != nil
        let quiet = options["quiet"] != nil
        let jsonOutput = options["json"] != nil
        let continueOnError = options["continue-on-error"] != nil
        let showProgress = options["progress"] != nil

        guard let inputDir = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input (directory)")
            exit(1)
        }

        guard let outputDir = options["o"] ?? options["output"] ?? options["output-dir"] else {
            print("Error: Missing required argument: -o/--output (directory)")
            exit(1)
        }

        // Create output directory
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // Resolve input files
        var batchOptions = options
        batchOptions["i"] = inputDir
        let paths = try resolveInputPaths(from: batchOptions)

        if paths.isEmpty {
            if !quiet { print("No supported files found in: \(inputDir)") }
            return
        }

        if !quiet { print("Found \(paths.count) file(s) to process") }

        switch subcommand {
        case "encode":
            let summary = try await batchEncode(paths: paths, outputDir: outputDir, options: options, continueOnError: continueOnError, verbose: verbose, quiet: quiet, showProgress: showProgress)
            printBatchSummary(summary, quiet: quiet, json: jsonOutput)

        case "decode":
            let summary = try await batchDecode(paths: paths, outputDir: outputDir, options: options, continueOnError: continueOnError, verbose: verbose, quiet: quiet, showProgress: showProgress)
            printBatchSummary(summary, quiet: quiet, json: jsonOutput)

        case "transcode":
            let summary = try await batchTranscode(paths: paths, outputDir: outputDir, options: options, continueOnError: continueOnError, verbose: verbose, quiet: quiet, showProgress: showProgress)
            printBatchSummary(summary, quiet: quiet, json: jsonOutput)

        default:
            print("Error: Unknown batch subcommand '\(subcommand)'. Expected: encode, decode, transcode")
            exit(1)
        }
    }

    // MARK: - Batch Encode

    private static func batchEncode(
        paths: [String],
        outputDir: String,
        options: [String: String],
        continueOnError: Bool,
        verbose: Bool,
        quiet: Bool,
        showProgress: Bool
    ) async throws -> BatchSummary {
        let outputSuffix = options["output-suffix"] ?? ".j2k"

        return await processFilesInParallel(
            paths: paths,
            outputDir: outputDir,
            outputSuffix: outputSuffix,
            continueOnError: continueOnError,
            verbose: verbose,
            quiet: quiet,
            showProgress: showProgress
        ) { inputPath, outputPath in
            let image = try loadImage(from: inputPath)
            var config = J2KEncodingConfiguration()
            if options["lossless"] != nil { config.lossless = true }
            if let q = options["quality"].flatMap({ Double($0) }) { config.quality = q }
            if options["htj2k"] != nil { config.useHTJ2K = true }
            if let codec = options["codec"] {
                applyCodecOption(codec, to: &config)
            }

            let encoder = J2KEncoder(encodingConfiguration: config)
            let encodedData = try encoder.encode(image)
            try encodedData.write(to: URL(fileURLWithPath: outputPath))

            let inputSize = image.width * image.height * image.componentCount
            return (inputSize, encodedData.count)
        }
    }

    // MARK: - Batch Decode

    private static func batchDecode(
        paths: [String],
        outputDir: String,
        options: [String: String],
        continueOnError: Bool,
        verbose: Bool,
        quiet: Bool,
        showProgress: Bool
    ) async throws -> BatchSummary {
        let outputSuffix = options["output-suffix"] ?? ".pgm"

        return await processFilesInParallel(
            paths: paths,
            outputDir: outputDir,
            outputSuffix: outputSuffix,
            continueOnError: continueOnError,
            verbose: verbose,
            quiet: quiet,
            showProgress: showProgress
        ) { inputPath, outputPath in
            let inputData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
            let decoder = J2KDecoder()
            let image = try decoder.decode(inputData)
            try saveImage(image, to: outputPath)

            let outputSize = image.width * image.height * image.componentCount
            return (inputData.count, outputSize)
        }
    }

    // MARK: - Batch Transcode

    private static func batchTranscode(
        paths: [String],
        outputDir: String,
        options: [String: String],
        continueOnError: Bool,
        verbose: Bool,
        quiet: Bool,
        showProgress: Bool
    ) async throws -> BatchSummary {
        let outputFormat = options["format"] ?? "j2k"
        let outputSuffix = options["output-suffix"] ?? ".\(outputFormat)"

        return await processFilesInParallel(
            paths: paths,
            outputDir: outputDir,
            outputSuffix: outputSuffix,
            continueOnError: continueOnError,
            verbose: verbose,
            quiet: quiet,
            showProgress: showProgress
        ) { inputPath, outputPath in
            let inputData = try Data(contentsOf: URL(fileURLWithPath: inputPath))
            let containerFormat = detectContainerFormat(inputData)
            let codestreamData = extractCodestream(from: inputData, format: containerFormat)

            var outputData: Data
            let toHTJ2K = options["to-htj2k"] != nil
            let fromHTJ2K = options["from-htj2k"] != nil

            if toHTJ2K || fromHTJ2K {
                let direction: TranscodingDirection = toHTJ2K ? .legacyToHT : .htToLegacy
                let transcoder = J2KTranscoder(configuration: .default)
                let result = try transcoder.transcode(codestreamData, direction: direction)
                outputData = result.data
            } else {
                let decoder = J2KDecoder()
                let image = try decoder.decode(codestreamData)
                let encoder = J2KEncoder(encodingConfiguration: J2KEncodingConfiguration())
                outputData = try encoder.encode(image)
            }

            try outputData.write(to: URL(fileURLWithPath: outputPath))
            return (inputData.count, outputData.count)
        }
    }

    // MARK: - Codec Option

    /// Apply a --codec flag value to an encoding configuration.
    static func applyCodecOption(_ codec: String, to config: inout J2KEncodingConfiguration) {
        switch codec.lowercased() {
        case "j2k-lossless":
            config.lossless = true
            config.useHTJ2K = false
        case "j2k-lossy":
            config.lossless = false
            config.useHTJ2K = false
        case "htj2k-lossless":
            config.lossless = true
            config.useHTJ2K = true
        case "htj2k-lossy":
            config.lossless = false
            config.useHTJ2K = true
        case "htj2k-lossless-rpcl":
            config.lossless = true
            config.useHTJ2K = true
            config.progressionOrder = .rpcl
        default:
            print("Warning: Unknown codec '\(codec)'. Using default.")
        }
    }

    // MARK: - Help

    private static func printBatchHelp() {
        print("""
        j2k batch - Batch-process files in a directory

        USAGE:
            j2k batch <encode|decode|transcode> -i <dir> -o <dir> [options]

        SUBCOMMANDS:
            encode          Batch encode images to JPEG 2000
            decode          Batch decode JPEG 2000 images
            transcode       Batch transcode between JPEG 2000 formats

        OPTIONS:
            -i, --input DIR             Input directory
            -o, --output DIR            Output directory
            --recursive                 Recursive directory traversal
            --filter GLOB               Include filter (e.g. "*.pgm")
            --exclude GLOB              Exclude filter
            --output-suffix SUFFIX      Output file suffix (e.g. ".j2k")
            --continue-on-error         Continue on file errors
            --threads N                 Parallel threads
            --progress                  Show progress
            --verbose                   Verbose output
            --quiet                     Suppress output
            --json                      JSON output

        ENCODE OPTIONS:
            --codec VARIANT             j2k-lossless|j2k-lossy|htj2k-lossless|htj2k-lossy
            --lossless                  Lossless compression
            --quality FLOAT             Quality 0.0-1.0
            --htj2k                     HTJ2K encoding

        TRANSCODE OPTIONS:
            --to-htj2k                  Transcode to HTJ2K
            --from-htj2k               Transcode from HTJ2K
            --format j2k|jp2|jpx       Output format

        EXAMPLES:
            j2k batch encode -i ./images/ -o ./encoded/ --codec htj2k-lossless --recursive
            j2k batch decode -i ./encoded/ -o ./decoded/ --output-suffix .ppm
            j2k batch transcode -i ./legacy/ -o ./htj2k/ --to-htj2k
        """)
    }
}
