import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

/// J2KSwift Command-Line Interface
///
/// A command-line tool for encoding, decoding, and benchmarking JPEG 2000 images.
@main
struct J2KCLI {
    static func main() async {
        let args = CommandLine.arguments

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
            j2k <command> [options]

        COMMANDS:
            encode      Encode an image to JPEG 2000
            decode      Decode a JPEG 2000 image
            benchmark   Run encoding/decoding benchmarks
            version     Print version information
            help        Show this help message

        ENCODE OPTIONS:
            -i, --input PATH        Input image file (PGM, PPM, RAW)
            -o, --output PATH       Output J2K/JP2 file
            -q, --quality FLOAT     Quality (0.0-1.0, default: 1.0)
            --lossless              Use lossless compression
            --preset NAME           Use preset: fast, balanced, quality
            --levels N              Decomposition levels (0-10, default: 5)
            --blocksize WxH         Code block size (default: 32x32)
            --layers N              Quality layers (1-20, default: 5)
            --format FORMAT         Output format: j2k or jp2 (default: j2k)
            --timing                Show detailed timing information
            --json                  Output results as JSON

        DECODE OPTIONS:
            -i, --input PATH        Input J2K/JP2 file
            -o, --output PATH       Output image file (PGM, PPM, RAW)
            --timing                Show detailed timing information
            --json                  Output results as JSON

        BENCHMARK OPTIONS:
            -i, --input PATH        Input image file for benchmarking
            -r, --runs N            Number of runs (default: 3)
            -o, --output PATH       Output JSON report file (optional)
            --encode-only           Only benchmark encoding
            --decode-only           Only benchmark decoding
            --preset NAME           Use preset: fast, balanced, quality

        EXAMPLES:
            # Encode an image with default settings
            j2k encode -i input.pgm -o output.j2k

            # Encode with lossless compression
            j2k encode -i input.pgm -o output.j2k --lossless

            # Decode a JPEG 2000 file
            j2k decode -i input.j2k -o output.pgm

            # Benchmark encoding performance
            j2k benchmark -i test.pgm -r 10 -o results.json
        """)
    }
}
