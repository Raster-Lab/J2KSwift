//
// J2KOpenJPEGCLI.swift
// J2KSwift
//
/// # OpenJPEG CLI Integration
///
/// OpenJPEG availability detection and CLI wrappers for `opj_compress`
/// and `opj_decompress`, used by `j2k benchmark --compare-openjpeg` and
/// the J2KTestApp interop view.
///
/// Extracted from J2KOpenJPEGInterop.swift in v11.0.0; the interop test
/// pipeline, synthetic corpus, validator, report generator, and corrupt
/// codestream generator were removed as dead scaffolding (superseded by
/// Scripts/benchmarks/cross_codec_warm_bench.py).
///
/// ## Topics
///
/// ### Availability Detection
/// - ``OpenJPEGAvailability``
///
/// ### CLI Wrappers
/// - ``OpenJPEGCLIWrapper``

import Foundation

// MARK: - OpenJPEG Availability

/// Detects whether OpenJPEG command-line tools are available on the system.
///
/// This struct provides methods to check for `opj_compress` and `opj_decompress`
/// availability, determine the installed version, and assess feature support
/// (e.g., HTJ2K in OpenJPEG 2.5+).
public struct OpenJPEGAvailability: Sendable {

    /// Information about an installed OpenJPEG binary.
    public struct ToolInfo: Sendable {
        /// The full path to the tool binary.
        public let path: String
        /// The version string (e.g., "2.5.0").
        public let version: String
        /// Whether HTJ2K is supported (OpenJPEG ≥ 2.5).
        public let supportsHTJ2K: Bool

        /// Creates a new tool info instance.
        public init(path: String, version: String, supportsHTJ2K: Bool) {
            self.path = path
            self.version = version
            self.supportsHTJ2K = supportsHTJ2K
        }
    }

    /// Result of an OpenJPEG availability check.
    public struct AvailabilityResult: Sendable {
        /// Whether `opj_compress` is available.
        public let compressorAvailable: Bool
        /// Whether `opj_decompress` is available.
        public let decompressorAvailable: Bool
        /// Information about the compressor tool, if available.
        public let compressorInfo: ToolInfo?
        /// Information about the decompressor tool, if available.
        public let decompressorInfo: ToolInfo?
        /// Whether both tools are available for bidirectional testing.
        public var isBidirectionalTestingAvailable: Bool {
            compressorAvailable && decompressorAvailable
        }

        /// Creates a new availability result.
        public init(
            compressorAvailable: Bool,
            decompressorAvailable: Bool,
            compressorInfo: ToolInfo?,
            decompressorInfo: ToolInfo?
        ) {
            self.compressorAvailable = compressorAvailable
            self.decompressorAvailable = decompressorAvailable
            self.compressorInfo = compressorInfo
            self.decompressorInfo = decompressorInfo
        }
    }

    /// Checks whether a command-line tool exists in the system PATH.
    ///
    /// - Parameter toolName: The name of the tool to locate (e.g., "opj_compress").
    /// - Returns: The full path to the tool, or `nil` if not found.
    public static func findTool(_ toolName: String) -> String? {
        let searchPaths = [
            "/usr/local/bin",
            "/usr/bin",
            "/opt/homebrew/bin",
            "/opt/local/bin",
        ]

        for dir in searchPaths {
            let path = "\(dir)/\(toolName)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try PATH-based lookup
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":").map(String.init) {
            let path = "\(dir)/\(toolName)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Parses the OpenJPEG version from a tool's `--help` or `-h` output.
    ///
    /// - Parameter helpOutput: The stdout/stderr from running the tool with `--help`.
    /// - Returns: The version string, or "unknown" if parsing fails.
    public static func parseVersion(from helpOutput: String) -> String {
        // OpenJPEG help output typically contains a line like:
        // "opj_compress version 2.5.0"  or  "[INFO] Version: 2.5.0"
        let patterns = [
            "version\\s+(\\d+\\.\\d+\\.?\\d*)",
            "Version:\\s*(\\d+\\.\\d+\\.?\\d*)",
            "(\\d+\\.\\d+\\.\\d+)",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(
                   in: helpOutput,
                   range: NSRange(helpOutput.startIndex..., in: helpOutput)
               ),
               let range = Range(match.range(at: 1), in: helpOutput)
            {
                return String(helpOutput[range])
            }
        }
        return "unknown"
    }

    /// Determines whether a version string indicates HTJ2K support (≥ 2.5).
    ///
    /// - Parameter version: The version string to evaluate.
    /// - Returns: `true` if HTJ2K is supported.
    public static func versionSupportsHTJ2K(_ version: String) -> Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        if parts[0] > 2 { return true }
        if parts[0] == 2 && parts[1] >= 5 { return true }
        return false
    }

    /// Checks for OpenJPEG tool availability on the current system.
    ///
    /// - Returns: An ``AvailabilityResult`` describing what is available.
    public static func check() -> AvailabilityResult {
        let compressorPath = findTool("opj_compress")
        let decompressorPath = findTool("opj_decompress")

        var compressorInfo: ToolInfo?
        var decompressorInfo: ToolInfo?

        if let path = compressorPath {
            let version = getToolVersion(path: path)
            compressorInfo = ToolInfo(
                path: path,
                version: version,
                supportsHTJ2K: versionSupportsHTJ2K(version)
            )
        }

        if let path = decompressorPath {
            let version = getToolVersion(path: path)
            decompressorInfo = ToolInfo(
                path: path,
                version: version,
                supportsHTJ2K: versionSupportsHTJ2K(version)
            )
        }

        return AvailabilityResult(
            compressorAvailable: compressorPath != nil,
            decompressorAvailable: decompressorPath != nil,
            compressorInfo: compressorInfo,
            decompressorInfo: decompressorInfo
        )
    }

    /// Gets the version of an OpenJPEG tool by running it with `-h`.
    ///
    /// - Parameter path: The full path to the tool binary.
    /// - Returns: The parsed version string.
    ///
    /// **iOS note (v8 Phase 6.2)**: `Process` is unavailable on iOS.
    /// This function returns "unavailable" on iOS — OpenJPEG CLI
    /// interop is a macOS-only feature (no shell-spawned binaries
    /// on iOS). The caller (`OpenJPEGAvailability.detect()`) treats
    /// "unavailable" as "OpenJPEG not present," which is the correct
    /// behaviour on iOS.
    private static func getToolVersion(path: String) -> String {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-h"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return parseVersion(from: output)
        } catch {
            return "unknown"
        }
        #else
        return "unavailable"
        #endif
    }
}

// MARK: - OpenJPEG CLI Wrapper

/// Swift wrapper around the OpenJPEG command-line tools (`opj_compress`, `opj_decompress`).
///
/// Provides type-safe interfaces for encoding and decoding operations, with support
/// for all standard OpenJPEG options including progression orders, quality layers,
/// tile sizes, and HTJ2K mode.
public struct OpenJPEGCLIWrapper: Sendable {

    /// Configuration for an OpenJPEG encode operation.
    public struct EncodeConfiguration: Sendable {
        /// Output format (j2k, jp2, jpx).
        public let outputFormat: OpenJPEGOutputFormat
        /// Whether to use lossless compression (reversible 5/3 wavelet).
        public let lossless: Bool
        /// Compression ratio (for lossy). Ignored if lossless is `true`.
        public let compressionRatio: Double?
        /// PSNR target in dB (for lossy). Ignored if lossless is `true`.
        public let targetPSNR: Double?
        /// Number of quality layers.
        public let qualityLayers: Int
        /// Progression order.
        public let progressionOrder: OpenJPEGProgressionOrder
        /// Number of decomposition levels.
        public let decompositionLevels: Int
        /// Code-block width (log2).
        public let codeBlockWidth: Int
        /// Code-block height (log2).
        public let codeBlockHeight: Int
        /// Tile width (0 = single tile).
        public let tileWidth: Int
        /// Tile height (0 = single tile).
        public let tileHeight: Int
        /// Whether to use HTJ2K encoding (OpenJPEG 2.5+ only).
        public let useHTJ2K: Bool
        /// Additional raw command-line arguments.
        public let additionalArguments: [String]

        /// Creates a new encode configuration with defaults.
        public init(
            outputFormat: OpenJPEGOutputFormat = .jp2,
            lossless: Bool = true,
            compressionRatio: Double? = nil,
            targetPSNR: Double? = nil,
            qualityLayers: Int = 1,
            progressionOrder: OpenJPEGProgressionOrder = .lrcp,
            decompositionLevels: Int = 5,
            codeBlockWidth: Int = 64,
            codeBlockHeight: Int = 64,
            tileWidth: Int = 0,
            tileHeight: Int = 0,
            useHTJ2K: Bool = false,
            additionalArguments: [String] = []
        ) {
            self.outputFormat = outputFormat
            self.lossless = lossless
            self.compressionRatio = compressionRatio
            self.targetPSNR = targetPSNR
            self.qualityLayers = qualityLayers
            self.progressionOrder = progressionOrder
            self.decompositionLevels = decompositionLevels
            self.codeBlockWidth = codeBlockWidth
            self.codeBlockHeight = codeBlockHeight
            self.tileWidth = tileWidth
            self.tileHeight = tileHeight
            self.useHTJ2K = useHTJ2K
            self.additionalArguments = additionalArguments
        }
    }

    /// Result of running an OpenJPEG CLI command.
    public struct CLIResult: Sendable {
        /// Whether the command completed successfully (exit code 0).
        public let success: Bool
        /// The exit code of the process.
        public let exitCode: Int32
        /// Standard output from the command.
        public let stdout: String
        /// Standard error from the command.
        public let stderr: String
        /// The path to the output file, if applicable.
        public let outputPath: String?
        /// Elapsed wall-clock time in seconds.
        public let elapsedTime: TimeInterval

        /// Creates a new CLI result.
        public init(
            success: Bool,
            exitCode: Int32,
            stdout: String,
            stderr: String,
            outputPath: String?,
            elapsedTime: TimeInterval
        ) {
            self.success = success
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
            self.outputPath = outputPath
            self.elapsedTime = elapsedTime
        }
    }

    /// The path to `opj_compress`.
    public let compressorPath: String?
    /// The path to `opj_decompress`.
    public let decompressorPath: String?

    /// Creates a new CLI wrapper, auto-detecting tool locations.
    public init() {
        self.compressorPath = OpenJPEGAvailability.findTool("opj_compress")
        self.decompressorPath = OpenJPEGAvailability.findTool("opj_decompress")
    }

    /// Creates a new CLI wrapper with explicit tool paths.
    public init(compressorPath: String?, decompressorPath: String?) {
        self.compressorPath = compressorPath
        self.decompressorPath = decompressorPath
    }

    /// Builds the command-line arguments for an encode operation.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the input image file.
    ///   - outputPath: Path for the encoded output file.
    ///   - configuration: The encode configuration.
    /// - Returns: An array of command-line arguments.
    public static func buildEncodeArguments(
        inputPath: String,
        outputPath: String,
        configuration: EncodeConfiguration
    ) -> [String] {
        var args: [String] = []

        args.append(contentsOf: ["-i", inputPath])
        args.append(contentsOf: ["-o", outputPath])

        // Progression order
        args.append(contentsOf: ["-p", configuration.progressionOrder.rawValue])

        // Decomposition levels
        args.append(contentsOf: ["-n", "\(configuration.decompositionLevels)"])

        // Code-block size
        args.append(contentsOf: [
            "-b", "\(configuration.codeBlockWidth),\(configuration.codeBlockHeight)",
        ])

        // Quality / compression
        if configuration.lossless {
            // No additional quality flags needed for lossless
        } else if let ratio = configuration.compressionRatio {
            args.append(contentsOf: ["-r", "\(ratio)"])
        } else if let psnr = configuration.targetPSNR {
            args.append(contentsOf: ["-q", "\(psnr)"])
        }

        // Tile size
        if configuration.tileWidth > 0 && configuration.tileHeight > 0 {
            args.append(contentsOf: [
                "-t", "\(configuration.tileWidth),\(configuration.tileHeight)",
            ])
        }

        // HTJ2K
        if configuration.useHTJ2K {
            args.append("-HT")
        }

        // Additional arguments
        args.append(contentsOf: configuration.additionalArguments)

        return args
    }

    /// Builds the command-line arguments for a decode operation.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the JPEG 2000 input file.
    ///   - outputPath: Path for the decoded output file.
    /// - Returns: An array of command-line arguments.
    public static func buildDecodeArguments(
        inputPath: String,
        outputPath: String
    ) -> [String] {
        return ["-i", inputPath, "-o", outputPath]
    }

    /// Runs an OpenJPEG CLI tool with the given arguments.
    ///
    /// - Parameters:
    ///   - toolPath: Full path to the tool executable.
    ///   - arguments: Command-line arguments.
    ///   - outputPath: Expected output file path (for result reporting).
    /// - Returns: A ``CLIResult`` describing the outcome.
    public static func runTool(
        toolPath: String,
        arguments: [String],
        outputPath: String?
    ) -> CLIResult {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            return CLIResult(
                success: false,
                exitCode: -1,
                stdout: "",
                stderr: "Failed to launch process: \(error.localizedDescription)",
                outputPath: outputPath,
                elapsedTime: elapsed
            )
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CLIResult(
            success: process.terminationStatus == 0,
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            outputPath: outputPath,
            elapsedTime: elapsed
        )
        #else
        // iOS: no shell-spawned binaries. OpenJPEG CLI interop is
        // a macOS-only diagnostic feature.
        return CLIResult(
            success: false,
            exitCode: -1,
            stdout: "",
            stderr: "OpenJPEG CLI interop is unavailable on iOS",
            outputPath: outputPath,
            elapsedTime: 0
        )
        #endif
    }
}

// MARK: - Output Format

/// JPEG 2000 output file formats supported by OpenJPEG.
public enum OpenJPEGOutputFormat: String, Sendable, CaseIterable {
    /// Raw JPEG 2000 codestream (.j2k).
    case j2k
    /// JP2 file format (.jp2).
    case jp2
    /// JPX file format (.jpx) — extended JP2.
    case jpx

    /// The file extension for this format.
    public var fileExtension: String { rawValue }
}

// MARK: - Progression Order

/// JPEG 2000 progression orders.
public enum OpenJPEGProgressionOrder: String, Sendable, CaseIterable {
    /// Layer-Resolution-Component-Position.
    case lrcp = "LRCP"
    /// Resolution-Layer-Component-Position.
    case rlcp = "RLCP"
    /// Resolution-Position-Component-Layer.
    case rpcl = "RPCL"
    /// Position-Component-Resolution-Layer.
    case pcrl = "PCRL"
    /// Component-Position-Resolution-Layer.
    case cprl = "CPRL"
}

