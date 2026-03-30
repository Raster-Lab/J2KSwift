//
// main.swift
// J2KSwift
//
import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

/// J2KSwift Command-Line Interface
///
/// A command-line tool for encoding, decoding, transcoding, validating,
/// and benchmarking JPEG 2000 images.
@main
struct J2KCLI {
    static func main() async {
        let args = CommandLine.arguments

        // Handle --version flag at the top level
        if args.contains("--version") {
            printVersion()
            return
        }

        guard args.count > 1 else {
            printUsage()
            exit(1)
        }

        let command = args[1]
        let commandArgs = Array(args.dropFirst(2))

        do {
            switch command {
            case "encode":
                try await encodeCommand(commandArgs)
            case "decode":
                try await decodeCommand(commandArgs)
            case "benchmark":
                try await benchmarkCommand(commandArgs)
            case "info":
                if commandArgs.first == "--capabilities" || commandArgs.contains("--capabilities") {
                    try await capabilitiesCommand(commandArgs)
                } else if commandArgs.contains("--list-gpus") {
                    listGPUs()
                } else {
                    try await infoCommand(commandArgs)
                }
            case "transcode":
                try await transcodeCommand(commandArgs)
            case "validate":
                try await validateCommand(commandArgs)
            case "encode3d":
                try await encode3DCommand(commandArgs)
            case "decode3d":
                try await decode3DCommand(commandArgs)
            case "jpip":
                if commandArgs.first == "server" {
                    try await jpipServerCommand(Array(commandArgs.dropFirst()))
                } else if commandArgs.first == "client" {
                    try await jpipClientCommand(Array(commandArgs.dropFirst()))
                } else {
                    print("Error: Unknown jpip subcommand. Expected: server, client")
                    exit(1)
                }
            case "batch":
                try await batchCommand(commandArgs)
            case "compare":
                try await compareCommand(commandArgs)
            case "convert":
                try await convertCommand(commandArgs)
            case "completions":
                try await completionsCommand(commandArgs)
            case "testapp":
                try await testappCommand(commandArgs)
            case "version":
                printVersion()
            case "help", "-h", "--help":
                printUsage()
            default:
                print("Error: Unknown command '\(command)'")
                printUsage()
                exit(1)
            }
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }

    static func printVersion() {
        let version = getVersion()
        print("J2KSwift version \(version)")
    }

    static func printUsage() {
        print("""
        J2KSwift - JPEG 2000 Encoder/Decoder CLI

        USAGE:
            j2k <command> [subcommand] [options]

        COMMANDS:
            encode      Compress image(s) to JPEG 2000 / HTJ2K
            decode      Decompress JPEG 2000 / HTJ2K image(s)
            transcode   Lossless transcoding between J2K ↔ HTJ2K
            info        Display codestream / file-format metadata
            validate    Conformance validation
            benchmark   Performance benchmarking
            encode3d    Compress volumetric / 3D data (JP3D)
            decode3d    Decompress volumetric / 3D data (JP3D)
            jpip        JPIP streaming (server/client)
            batch       Batch-process files in a directory
            compare     Compare two images (PSNR, MSE, MAE)
            convert     Convert between image formats
            completions Generate shell completions (bash/zsh/fish)
            testapp     Run test app in headless mode (CI/CD)
            version     Print version information
            help        Show this help message

        ENCODE OPTIONS:
            -i, --input PATH            Input image file (PGM, PPM, PNM, RAW)
            -o, --output PATH           Output J2K/JP2/JPX file
            -q, --quality FLOAT         Quality (0.0-1.0, default: 1.0)
            --lossless                  Use lossless compression
            --bitrate BPP               Target bit-rate in bits per pixel
            --psnr VALUE                Target PSNR (dB)
            --visually-lossless         Visually lossless mode
            --preset NAME               Use preset: fast, balanced, quality
            --levels N                  Decomposition levels (0-10, default: 5)
            --blocksize WxH             Code block size (default: 32x32)
            --layers N                  Quality layers (1-20, default: 5)
            --format FORMAT             Output format: j2k, jp2, or jpx (default: j2k)
            --progression ORDER         Progression order: LRCP, RLCP, RPCL, PCRL, CPRL
            --tile-size WxH             Tile size (e.g. 256x256)
            --roi x,y,w,h               Region of interest
            --htj2k                     Enable HTJ2K (Part 15) encoding
            --mct / --no-mct            Enable/disable multi-component transform
            --gpu / --no-gpu            Enable/disable GPU acceleration
            --colour-space / --color-space CS  Colour space
            --verbose                   Verbose output
            --quiet                     Suppress non-error output
            --timing                    Show detailed timing information
            --json                      Output results as JSON

        DECODE OPTIONS:
            -i, --input PATH            Input J2K/JP2/JPX file
            -o, --output PATH           Output image file (PGM, PPM, RAW)
            --level N                   Resolution level for partial decoding
            --layer N                   Quality layer for partial decoding
            --component N               Single component to decode
            --components N,M,...        Components to decode
            --colour-space / --color-space  Convert colour space
            --gpu / --no-gpu            Enable/disable GPU acceleration
            --verbose                   Verbose output
            --quiet                     Suppress non-error output
            --timing                    Show detailed timing information
            --json                      Output results as JSON

        INFO OPTIONS:
            <file>                      JPEG 2000 file to inspect
            --markers                   List codestream marker segments
            --boxes                     List JP2/JPX file format boxes
            --json                      Output as JSON
            --validate                  Perform quick conformance check

        TRANSCODE OPTIONS:
            -i, --input PATH            Input JPEG 2000 file
            -o, --output PATH           Output JPEG 2000 file
            --to-htj2k                  Transcode to HTJ2K
            --from-htj2k                Transcode from HTJ2K to Part 1
            --format j2k|jp2|jpx        Output format
            --quality VALUE             Re-quality setting
            --bitrate BPP               Target bit-rate
            --layers N                  Quality layers
            --progression ORDER         Progression order
            --batch DIR                 Batch-process a directory
            --output-dir DIR            Output directory for batch mode
            --verbose                   Verbose output
            --quiet                     Suppress non-error output

        VALIDATE OPTIONS:
            <file>                      JPEG 2000 file to validate
            --part1                     Check Part 1 conformance
            --part2                     Check Part 2 conformance
            --part15                    Check Part 15 (HTJ2K) conformance
            --strict                    Strict validation mode
            --json                      Output results as JSON
            --quiet                     Suppress non-error output

        BENCHMARK OPTIONS:
            -i, --input PATH            Input image file for benchmarking
            -r, --runs N                Number of runs (default: 3)
            --warmup N                  Warm-up runs before measurement (default: 1)
            -o, --output PATH           Output report file (optional)
            --format text|json|csv      Output format (default: text)
            --encode-only               Only benchmark encoding
            --decode-only               Only benchmark decoding
            --preset NAME               Use preset: fast, balanced, quality
            --compare-openjpeg          Compare with OpenJPEG (if available)

        GLOBAL FLAGS:
            --version                   Print version and exit

        EXAMPLES:
            j2k encode -i input.pgm -o output.j2k --lossless
            j2k encode -i input.ppm -o output.jp2 --quality 0.9 --progression RPCL
            j2k decode -i input.j2k -o output.pgm
            j2k info image.jp2 --boxes
            j2k transcode -i old.j2k -o new.j2k --to-htj2k
            j2k validate image.jp2 --part1 --json
            j2k benchmark -i test.pgm -r 10 --format csv -o results.csv
        """)
    }
}
