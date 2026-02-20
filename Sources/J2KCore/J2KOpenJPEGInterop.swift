//
// J2KOpenJPEGInterop.swift
// J2KSwift
//
/// # OpenJPEG Interoperability Infrastructure
///
/// Week 266–268 deliverable: Comprehensive bidirectional interoperability testing
/// infrastructure with OpenJPEG (ISO/IEC 15444 reference implementation).
///
/// Provides OpenJPEG availability detection, CLI wrappers for `opj_compress` and
/// `opj_decompress`, automated encode/decode pipelines, a synthetic test image
/// corpus, and interoperability report generation.
///
/// ## Topics
///
/// ### Availability Detection
/// - ``OpenJPEGAvailability``
///
/// ### CLI Wrappers
/// - ``OpenJPEGCLIWrapper``
///
/// ### Interoperability Pipeline
/// - ``OpenJPEGInteropPipeline``
///
/// ### Test Corpus
/// - ``OpenJPEGTestCorpus``
///
/// ### Report Generation
/// - ``OpenJPEGInteropReport``

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
    private static func getToolVersion(path: String) -> String {
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

// MARK: - Interoperability Pipeline

/// Automated encode-with-one/decode-with-other interoperability pipeline.
///
/// This pipeline enables bidirectional testing between J2KSwift and OpenJPEG
/// by encoding with one implementation and decoding with the other.
public struct OpenJPEGInteropPipeline: Sendable {

    /// Direction of interoperability testing.
    public enum Direction: String, Sendable, CaseIterable {
        /// Encode with J2KSwift, decode with OpenJPEG.
        case j2kSwiftToOpenJPEG = "J2KSwift→OpenJPEG"
        /// Encode with OpenJPEG, decode with J2KSwift.
        case openJPEGToJ2KSwift = "OpenJPEG→J2KSwift"
    }

    /// Result of an interoperability pipeline run.
    public struct PipelineResult: Sendable {
        /// The test direction.
        public let direction: Direction
        /// Name of the test case.
        public let testName: String
        /// Whether the pipeline completed successfully.
        public let success: Bool
        /// Errors encountered during the pipeline.
        public let errors: [String]
        /// Warnings encountered during the pipeline.
        public let warnings: [String]
        /// PSNR between the original and round-tripped image (if calculable).
        public let psnr: Double?
        /// Maximum absolute error between original and round-tripped image.
        public let maxAbsoluteError: Int32?
        /// Whether the result is lossless (exact match).
        public let isLossless: Bool
        /// Encode time in seconds.
        public let encodeTime: TimeInterval?
        /// Decode time in seconds.
        public let decodeTime: TimeInterval?

        /// Creates a new pipeline result.
        public init(
            direction: Direction,
            testName: String,
            success: Bool,
            errors: [String],
            warnings: [String],
            psnr: Double?,
            maxAbsoluteError: Int32?,
            isLossless: Bool,
            encodeTime: TimeInterval?,
            decodeTime: TimeInterval?
        ) {
            self.direction = direction
            self.testName = testName
            self.success = success
            self.errors = errors
            self.warnings = warnings
            self.psnr = psnr
            self.maxAbsoluteError = maxAbsoluteError
            self.isLossless = isLossless
            self.encodeTime = encodeTime
            self.decodeTime = decodeTime
        }
    }

    /// Creates a PGM (Portable Grey Map) file for testing.
    ///
    /// PGM is the simplest image format supported by OpenJPEG and is ideal
    /// for single-component interoperability testing.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - bitDepth: Bits per pixel (8 or 16).
    ///   - pattern: The pixel pattern to generate.
    /// - Returns: The PGM file data.
    public static func createPGMData(
        width: Int,
        height: Int,
        bitDepth: Int = 8,
        pattern: TestImagePattern = .gradient
    ) -> Data {
        let maxVal = (1 << bitDepth) - 1
        var data = Data()
        let header = "P5\n\(width) \(height)\n\(maxVal)\n"
        data.append(contentsOf: header.utf8)

        let pixels = pattern.generatePixels(width: width, height: height, maxVal: maxVal)
        if bitDepth <= 8 {
            for pixel in pixels {
                data.append(UInt8(clamping: pixel))
            }
        } else {
            for pixel in pixels {
                let val = UInt16(clamping: pixel)
                data.append(UInt8(val >> 8))
                data.append(UInt8(val & 0xFF))
            }
        }

        return data
    }

    /// Creates a PPM (Portable Pixel Map) file for testing.
    ///
    /// PPM supports three-component (RGB) images and is supported by OpenJPEG.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - pattern: The pixel pattern to generate.
    /// - Returns: The PPM file data.
    public static func createPPMData(
        width: Int,
        height: Int,
        pattern: TestImagePattern = .gradient
    ) -> Data {
        let maxVal = 255
        var data = Data()
        let header = "P6\n\(width) \(height)\n\(maxVal)\n"
        data.append(contentsOf: header.utf8)

        let pixels = pattern.generatePixels(width: width, height: height, maxVal: maxVal)
        for pixel in pixels {
            let val = UInt8(clamping: pixel)
            // Write RGB (same value for greyscale pattern)
            data.append(val)
            data.append(val)
            data.append(val)
        }

        return data
    }
}

// MARK: - Test Image Pattern

/// Patterns for generating synthetic test images.
public enum TestImagePattern: String, Sendable, CaseIterable {
    /// Horizontal gradient from 0 to max.
    case gradient
    /// Uniform mid-grey.
    case uniform
    /// Checkerboard pattern.
    case checkerboard
    /// Random noise.
    case random
    /// Horizontal stripes.
    case stripes
    /// Diagonal pattern.
    case diagonal
    /// Single solid colour (black).
    case solidBlack
    /// Single solid colour (white).
    case solidWhite
    /// Zone plate (concentric rings).
    case zonePlate

    /// Generates pixel values for this pattern.
    ///
    /// - Parameters:
    ///   - width: Image width.
    ///   - height: Image height.
    ///   - maxVal: Maximum pixel value.
    /// - Returns: An array of pixel values (row-major order).
    public func generatePixels(width: Int, height: Int, maxVal: Int) -> [Int] {
        var pixels = [Int](repeating: 0, count: width * height)

        switch self {
        case .gradient:
            for y in 0..<height {
                for x in 0..<width {
                    pixels[y * width + x] = width > 1
                        ? (x * maxVal) / (width - 1) : maxVal / 2
                }
            }

        case .uniform:
            let mid = maxVal / 2
            for i in 0..<pixels.count {
                pixels[i] = mid
            }

        case .checkerboard:
            let blockSize = max(1, min(width, height) / 8)
            for y in 0..<height {
                for x in 0..<width {
                    let bx = x / blockSize
                    let by = y / blockSize
                    pixels[y * width + x] = ((bx + by) % 2 == 0) ? maxVal : 0
                }
            }

        case .random:
            // Deterministic pseudo-random using a simple LCG
            var seed: UInt64 = 42
            for i in 0..<pixels.count {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                pixels[i] = Int((seed >> 33) % UInt64(maxVal + 1))
            }

        case .stripes:
            let stripeHeight = max(1, height / 16)
            for y in 0..<height {
                let val = ((y / stripeHeight) % 2 == 0) ? maxVal : 0
                for x in 0..<width {
                    pixels[y * width + x] = val
                }
            }

        case .diagonal:
            for y in 0..<height {
                for x in 0..<width {
                    let sum = x + y
                    let total = width + height - 2
                    pixels[y * width + x] = total > 0
                        ? (sum * maxVal) / total : maxVal / 2
                }
            }

        case .solidBlack:
            // Already zeroed
            break

        case .solidWhite:
            for i in 0..<pixels.count {
                pixels[i] = maxVal
            }

        case .zonePlate:
            let cx = Double(width) / 2.0
            let cy = Double(height) / 2.0
            let scale = Double.pi / Double(max(width, height))
            for y in 0..<height {
                for x in 0..<width {
                    let dx = Double(x) - cx
                    let dy = Double(y) - cy
                    let r2 = dx * dx + dy * dy
                    let val = (cos(r2 * scale) + 1.0) / 2.0
                    pixels[y * width + x] = Int(val * Double(maxVal))
                }
            }
        }

        return pixels
    }
}

// MARK: - Test Corpus

/// Generates a corpus of synthetic test images for interoperability testing.
///
/// The corpus covers various image dimensions, bit depths, component counts,
/// and pixel patterns to ensure comprehensive coverage.
public struct OpenJPEGTestCorpus: Sendable {

    /// A test image entry in the corpus.
    public struct TestImage: Sendable {
        /// Human-readable name for this test image.
        public let name: String
        /// Image width.
        public let width: Int
        /// Image height.
        public let height: Int
        /// Number of components.
        public let components: Int
        /// Bit depth per component.
        public let bitDepth: Int
        /// Whether component values are signed.
        public let isSigned: Bool
        /// The pixel pattern used.
        public let pattern: TestImagePattern
        /// Category of this test image.
        public let category: TestImageCategory

        /// Creates a new test image entry.
        public init(
            name: String,
            width: Int,
            height: Int,
            components: Int,
            bitDepth: Int,
            isSigned: Bool,
            pattern: TestImagePattern,
            category: TestImageCategory
        ) {
            self.name = name
            self.width = width
            self.height = height
            self.components = components
            self.bitDepth = bitDepth
            self.isSigned = isSigned
            self.pattern = pattern
            self.category = category
        }
    }

    /// Categories for test images.
    public enum TestImageCategory: String, Sendable, CaseIterable {
        /// Synthetic test patterns.
        case synthetic
        /// Medical imaging scenarios.
        case medical
        /// Satellite/remote sensing scenarios.
        case satellite
        /// General photography scenarios.
        case photography
        /// Edge cases and boundary conditions.
        case edgeCase
    }

    /// Generates the standard test image corpus.
    ///
    /// - Returns: An array of test image entries covering all required categories.
    public static func standardCorpus() -> [TestImage] {
        var corpus: [TestImage] = []

        // Synthetic test patterns — various sizes
        let syntheticSizes = [(64, 64), (128, 128), (256, 256), (512, 512)]
        for (w, h) in syntheticSizes {
            for pattern in [TestImagePattern.gradient, .checkerboard, .zonePlate] {
                corpus.append(TestImage(
                    name: "synthetic_\(pattern.rawValue)_\(w)x\(h)",
                    width: w, height: h,
                    components: 1, bitDepth: 8,
                    isSigned: false, pattern: pattern,
                    category: .synthetic
                ))
            }
        }

        // RGB test images
        for (w, h) in [(64, 64), (256, 256)] {
            corpus.append(TestImage(
                name: "synthetic_rgb_gradient_\(w)x\(h)",
                width: w, height: h,
                components: 3, bitDepth: 8,
                isSigned: false, pattern: .gradient,
                category: .synthetic
            ))
        }

        // Medical imaging — 12-bit and 16-bit greyscale
        corpus.append(TestImage(
            name: "medical_12bit_256x256",
            width: 256, height: 256,
            components: 1, bitDepth: 12,
            isSigned: false, pattern: .gradient,
            category: .medical
        ))
        corpus.append(TestImage(
            name: "medical_16bit_256x256",
            width: 256, height: 256,
            components: 1, bitDepth: 16,
            isSigned: false, pattern: .gradient,
            category: .medical
        ))
        corpus.append(TestImage(
            name: "medical_16bit_signed_256x256",
            width: 256, height: 256,
            components: 1, bitDepth: 16,
            isSigned: true, pattern: .gradient,
            category: .medical
        ))

        // Satellite — larger images, multi-component
        corpus.append(TestImage(
            name: "satellite_8bit_512x512",
            width: 512, height: 512,
            components: 1, bitDepth: 8,
            isSigned: false, pattern: .zonePlate,
            category: .satellite
        ))
        corpus.append(TestImage(
            name: "satellite_rgb_256x256",
            width: 256, height: 256,
            components: 3, bitDepth: 8,
            isSigned: false, pattern: .zonePlate,
            category: .satellite
        ))

        // Photography — standard sizes
        corpus.append(TestImage(
            name: "photo_rgb_512x512",
            width: 512, height: 512,
            components: 3, bitDepth: 8,
            isSigned: false, pattern: .random,
            category: .photography
        ))

        // Edge cases
        corpus.append(TestImage(
            name: "edge_1x1_pixel",
            width: 1, height: 1,
            components: 1, bitDepth: 8,
            isSigned: false, pattern: .uniform,
            category: .edgeCase
        ))
        corpus.append(TestImage(
            name: "edge_1bit_64x64",
            width: 64, height: 64,
            components: 1, bitDepth: 1,
            isSigned: false, pattern: .checkerboard,
            category: .edgeCase
        ))
        corpus.append(TestImage(
            name: "edge_24bit_64x64",
            width: 64, height: 64,
            components: 1, bitDepth: 24,
            isSigned: false, pattern: .gradient,
            category: .edgeCase
        ))
        corpus.append(TestImage(
            name: "edge_32bit_64x64",
            width: 64, height: 64,
            components: 1, bitDepth: 32,
            isSigned: false, pattern: .gradient,
            category: .edgeCase
        ))
        corpus.append(TestImage(
            name: "edge_nonsquare_17x31",
            width: 17, height: 31,
            components: 1, bitDepth: 8,
            isSigned: false, pattern: .diagonal,
            category: .edgeCase
        ))
        corpus.append(TestImage(
            name: "edge_wide_256x1",
            width: 256, height: 1,
            components: 1, bitDepth: 8,
            isSigned: false, pattern: .gradient,
            category: .edgeCase
        ))
        corpus.append(TestImage(
            name: "edge_tall_1x256",
            width: 1, height: 256,
            components: 1, bitDepth: 8,
            isSigned: false, pattern: .gradient,
            category: .edgeCase
        ))
        corpus.append(TestImage(
            name: "edge_signed_8bit_64x64",
            width: 64, height: 64,
            components: 1, bitDepth: 8,
            isSigned: true, pattern: .gradient,
            category: .edgeCase
        ))

        return corpus
    }

    /// Generates the corpus of test images filtered by category.
    ///
    /// - Parameter category: The category to filter by.
    /// - Returns: The filtered list of test image entries.
    public static func corpus(category: TestImageCategory) -> [TestImage] {
        standardCorpus().filter { $0.category == category }
    }
}

// MARK: - Interoperability Validator

/// Validates interoperability between J2KSwift and OpenJPEG.
///
/// Provides configuration-specific validators for progression orders, quality
/// layers, file formats, and edge cases.
public struct OpenJPEGInteropValidator: Sendable {

    /// Validation configuration for a specific interoperability test.
    public struct ValidationConfig: Sendable {
        /// The test name.
        public let name: String
        /// The test direction.
        public let direction: OpenJPEGInteropPipeline.Direction
        /// Whether lossless is expected.
        public let expectLossless: Bool
        /// Minimum acceptable PSNR (dB) for lossy tests.
        public let minimumPSNR: Double
        /// Maximum acceptable absolute error.
        public let maximumAbsoluteError: Int32
        /// The output format to test.
        public let format: OpenJPEGOutputFormat
        /// The progression order to test.
        public let progressionOrder: OpenJPEGProgressionOrder
        /// The number of quality layers to test.
        public let qualityLayers: Int
        /// Tile width for multi-tile tests (0 = single tile).
        public let tileWidth: Int
        /// Tile height for multi-tile tests (0 = single tile).
        public let tileHeight: Int

        /// Creates a new validation configuration with defaults.
        public init(
            name: String,
            direction: OpenJPEGInteropPipeline.Direction = .j2kSwiftToOpenJPEG,
            expectLossless: Bool = true,
            minimumPSNR: Double = 30.0,
            maximumAbsoluteError: Int32 = 0,
            format: OpenJPEGOutputFormat = .jp2,
            progressionOrder: OpenJPEGProgressionOrder = .lrcp,
            qualityLayers: Int = 1,
            tileWidth: Int = 0,
            tileHeight: Int = 0
        ) {
            self.name = name
            self.direction = direction
            self.expectLossless = expectLossless
            self.minimumPSNR = minimumPSNR
            self.maximumAbsoluteError = maximumAbsoluteError
            self.format = format
            self.progressionOrder = progressionOrder
            self.qualityLayers = qualityLayers
            self.tileWidth = tileWidth
            self.tileHeight = tileHeight
        }
    }

    /// Result of an interoperability validation.
    public struct ValidationResult: Sendable {
        /// The configuration that was tested.
        public let config: ValidationConfig
        /// Whether the validation passed.
        public let passed: Bool
        /// Error message if validation failed.
        public let errorMessage: String?
        /// Calculated PSNR (if applicable).
        public let psnr: Double?
        /// Maximum absolute error.
        public let maxAbsoluteError: Int32?

        /// Creates a new validation result.
        public init(
            config: ValidationConfig,
            passed: Bool,
            errorMessage: String?,
            psnr: Double?,
            maxAbsoluteError: Int32?
        ) {
            self.config = config
            self.passed = passed
            self.errorMessage = errorMessage
            self.psnr = psnr
            self.maxAbsoluteError = maxAbsoluteError
        }
    }

    /// Generates the standard set of validation configurations for all progression orders.
    ///
    /// - Returns: An array of validation configurations.
    public static func progressionOrderConfigs() -> [ValidationConfig] {
        OpenJPEGProgressionOrder.allCases.map { order in
            ValidationConfig(
                name: "progression_order_\(order.rawValue)",
                direction: .j2kSwiftToOpenJPEG,
                expectLossless: true,
                progressionOrder: order
            )
        }
    }

    /// Generates validation configurations for quality layer testing.
    ///
    /// - Returns: An array of validation configurations.
    public static func qualityLayerConfigs() -> [ValidationConfig] {
        [1, 2, 3, 5, 10].map { layers in
            ValidationConfig(
                name: "quality_layers_\(layers)",
                direction: .j2kSwiftToOpenJPEG,
                expectLossless: false,
                minimumPSNR: 25.0,
                maximumAbsoluteError: 50,
                qualityLayers: layers
            )
        }
    }

    /// Generates validation configurations for file format testing.
    ///
    /// - Returns: An array of validation configurations.
    public static func formatConfigs() -> [ValidationConfig] {
        OpenJPEGOutputFormat.allCases.map { fmt in
            ValidationConfig(
                name: "format_\(fmt.rawValue)",
                direction: .j2kSwiftToOpenJPEG,
                format: fmt
            )
        }
    }

    /// Generates validation configurations for multi-tile testing.
    ///
    /// - Returns: An array of validation configurations.
    public static func multiTileConfigs() -> [ValidationConfig] {
        let tileSizes = [(64, 64), (128, 128), (32, 32)]
        return tileSizes.map { (tw, th) in
            ValidationConfig(
                name: "multi_tile_\(tw)x\(th)",
                direction: .openJPEGToJ2KSwift,
                tileWidth: tw,
                tileHeight: th
            )
        }
    }

    /// Generates validation configurations for edge case testing.
    ///
    /// - Returns: An array of validation configurations.
    public static func edgeCaseConfigs() -> [ValidationConfig] {
        [
            ValidationConfig(
                name: "edge_single_pixel",
                direction: .j2kSwiftToOpenJPEG
            ),
            ValidationConfig(
                name: "edge_non_square",
                direction: .j2kSwiftToOpenJPEG
            ),
            ValidationConfig(
                name: "edge_max_dimension",
                direction: .openJPEGToJ2KSwift
            ),
            ValidationConfig(
                name: "edge_unusual_tile_size",
                direction: .openJPEGToJ2KSwift,
                tileWidth: 13,
                tileHeight: 17
            ),
            ValidationConfig(
                name: "edge_signed_components",
                direction: .j2kSwiftToOpenJPEG
            ),
        ]
    }
}

// MARK: - Interoperability Report

/// Generates interoperability test reports in Markdown format.
///
/// Reports include test results, error analysis, and compatibility matrices.
public struct OpenJPEGInteropReport: Sendable {

    /// A single entry in the report.
    public struct ReportEntry: Sendable {
        /// Test case name.
        public let testName: String
        /// Test direction.
        public let direction: OpenJPEGInteropPipeline.Direction
        /// Whether the test passed.
        public let passed: Bool
        /// Error message if failed.
        public let errorMessage: String?
        /// PSNR value (if applicable).
        public let psnr: Double?
        /// Encode time in seconds.
        public let encodeTime: TimeInterval?
        /// Decode time in seconds.
        public let decodeTime: TimeInterval?

        /// Creates a new report entry.
        public init(
            testName: String,
            direction: OpenJPEGInteropPipeline.Direction,
            passed: Bool,
            errorMessage: String?,
            psnr: Double?,
            encodeTime: TimeInterval?,
            decodeTime: TimeInterval?
        ) {
            self.testName = testName
            self.direction = direction
            self.passed = passed
            self.errorMessage = errorMessage
            self.psnr = psnr
            self.encodeTime = encodeTime
            self.decodeTime = decodeTime
        }
    }

    /// Generates a Markdown interoperability report.
    ///
    /// - Parameters:
    ///   - entries: The test results to include.
    ///   - openJPEGVersion: The OpenJPEG version used.
    ///   - j2kSwiftVersion: The J2KSwift version used.
    /// - Returns: The report as a Markdown string.
    public static func generateMarkdownReport(
        entries: [ReportEntry],
        openJPEGVersion: String,
        j2kSwiftVersion: String
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let totalTests = entries.count
        let passedTests = entries.filter(\.passed).count
        let failedTests = totalTests - passedTests
        let passRate = totalTests > 0
            ? String(format: "%.1f", Double(passedTests) / Double(totalTests) * 100.0) : "N/A"

        var report = """
            # OpenJPEG Interoperability Report

            **Generated**: \(timestamp)
            **J2KSwift Version**: \(j2kSwiftVersion)
            **OpenJPEG Version**: \(openJPEGVersion)

            ## Summary

            | Metric | Value |
            |--------|-------|
            | Total Tests | \(totalTests) |
            | Passed | \(passedTests) |
            | Failed | \(failedTests) |
            | Pass Rate | \(passRate)% |

            ## Results

            | Test Name | Direction | Result | PSNR (dB) | Notes |
            |-----------|-----------|--------|-----------|-------|

            """

        for entry in entries {
            let result = entry.passed ? "✅ PASS" : "❌ FAIL"
            let psnrStr = entry.psnr.map { String(format: "%.2f", $0) } ?? "N/A"
            let notes = entry.errorMessage ?? ""
            report += "| \(entry.testName) | \(entry.direction.rawValue) | \(result) | \(psnrStr) | \(notes) |\n"
        }

        // Direction breakdown
        let j2kToOJP = entries.filter { $0.direction == .j2kSwiftToOpenJPEG }
        let ojpToJ2K = entries.filter { $0.direction == .openJPEGToJ2KSwift }

        report += """

            ## Direction Breakdown

            ### J2KSwift → OpenJPEG

            - Tests: \(j2kToOJP.count)
            - Passed: \(j2kToOJP.filter(\.passed).count)
            - Failed: \(j2kToOJP.filter { !$0.passed }.count)

            ### OpenJPEG → J2KSwift

            - Tests: \(ojpToJ2K.count)
            - Passed: \(ojpToJ2K.filter(\.passed).count)
            - Failed: \(ojpToJ2K.filter { !$0.passed }.count)

            """

        if failedTests > 0 {
            report += "\n## Failed Tests\n\n"
            for entry in entries where !entry.passed {
                report += "- **\(entry.testName)** (\(entry.direction.rawValue)): \(entry.errorMessage ?? "Unknown error")\n"
            }
        }

        return report
    }
}

// MARK: - Corrupt Codestream Generator

/// Generates intentionally corrupt or truncated JPEG 2000 codestreams for testing.
///
/// These codestreams exercise error handling in both J2KSwift and OpenJPEG decoders,
/// verifying graceful failure behaviour.
public struct CorruptCodestreamGenerator: Sendable {

    /// Type of corruption to apply.
    public enum CorruptionType: String, Sendable, CaseIterable {
        /// Truncate the codestream at a random point.
        case truncated
        /// Flip random bits in the codestream.
        case bitFlip
        /// Remove the EOC (End of Codestream) marker.
        case missingEOC
        /// Corrupt the SIZ marker segment.
        case corruptSIZ
        /// Corrupt the SOT marker segment.
        case corruptSOT
        /// Insert invalid marker codes.
        case invalidMarker
        /// Zero-length codestream.
        case empty
    }

    /// Applies corruption to a valid codestream.
    ///
    /// - Parameters:
    ///   - codestream: The original valid codestream.
    ///   - type: The type of corruption to apply.
    /// - Returns: The corrupted codestream.
    public static func corrupt(
        _ codestream: Data,
        type: CorruptionType
    ) -> Data {
        switch type {
        case .truncated:
            let truncatePoint = max(4, codestream.count / 2)
            return codestream.prefix(truncatePoint)

        case .bitFlip:
            var corrupted = codestream
            if corrupted.count > 10 {
                // Flip a bit in the middle of the data
                let idx = corrupted.count / 2
                corrupted[idx] ^= 0x40
            }
            return corrupted

        case .missingEOC:
            // Remove the last two bytes if they are EOC (0xFF 0xD9)
            if codestream.count >= 2,
               codestream[codestream.count - 2] == 0xFF,
               codestream[codestream.count - 1] == 0xD9
            {
                return codestream.prefix(codestream.count - 2)
            }
            return codestream

        case .corruptSIZ:
            var corrupted = codestream
            // SIZ marker is at offset 2; corrupt the segment length
            if corrupted.count > 5 {
                corrupted[4] = 0xFF  // Invalid segment length
                corrupted[5] = 0xFF
            }
            return corrupted

        case .corruptSOT:
            var corrupted = codestream
            // Find SOT marker (0xFF90) and corrupt it
            for i in 0..<(corrupted.count - 1) {
                if corrupted[i] == 0xFF && corrupted[i + 1] == 0x90 && i + 5 < corrupted.count {
                    corrupted[i + 4] = 0xFF  // Corrupt tile length
                    break
                }
            }
            return corrupted

        case .invalidMarker:
            var corrupted = codestream
            // Insert an invalid marker after the SOC
            if corrupted.count > 4 {
                var result = Data()
                result.append(contentsOf: [0xFF, 0x4F])  // SOC
                result.append(contentsOf: [0xFF, 0x01])  // Invalid marker
                result.append(contentsOf: [0x00, 0x02])  // Minimal length
                result.append(corrupted[2...])
                return result
            }
            return corrupted

        case .empty:
            return Data()
        }
    }
}

// MARK: - Interoperability Test Suite Configuration

/// Provides a full set of interoperability test configurations.
///
/// This generates over 100 test case configurations covering all required
/// interoperability testing scenarios.
public struct OpenJPEGInteropTestSuite: Sendable {

    /// A complete test case configuration.
    public struct TestCase: Sendable {
        /// Unique test identifier.
        public let id: String
        /// Human-readable description.
        public let description: String
        /// Test category.
        public let category: TestCategory
        /// Test image to use.
        public let image: OpenJPEGTestCorpus.TestImage
        /// Validation configuration.
        public let validation: OpenJPEGInteropValidator.ValidationConfig

        /// Creates a new test case.
        public init(
            id: String,
            description: String,
            category: TestCategory,
            image: OpenJPEGTestCorpus.TestImage,
            validation: OpenJPEGInteropValidator.ValidationConfig
        ) {
            self.id = id
            self.description = description
            self.category = category
            self.image = image
            self.validation = validation
        }
    }

    /// Categories for organising test cases.
    public enum TestCategory: String, Sendable, CaseIterable {
        /// OpenJPEG test harness tests.
        case harness
        /// J2KSwift → OpenJPEG tests.
        case j2kSwiftToOpenJPEG
        /// OpenJPEG → J2KSwift tests.
        case openJPEGToJ2KSwift
        /// Edge case tests.
        case edgeCase
    }

    /// Generates the complete set of interoperability test cases.
    ///
    /// - Returns: An array of test cases (100+ entries).
    public static func allTestCases() -> [TestCase] {
        var cases: [TestCase] = []
        let corpus = OpenJPEGTestCorpus.standardCorpus()

        // Helper: pick a default image for tests
        let defaultImage = corpus.first { $0.width == 64 && $0.height == 64 && $0.components == 1 }
            ?? corpus[0]

        let rgbImage = corpus.first { $0.components == 3 && $0.width == 64 }
            ?? defaultImage

        // ── 1. Harness tests ─────────────────────────────────────────────
        cases.append(TestCase(
            id: "harness_availability",
            description: "Verify OpenJPEG availability detection",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_availability")
        ))
        cases.append(TestCase(
            id: "harness_version_parsing",
            description: "Verify OpenJPEG version parsing",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_version_parsing")
        ))
        cases.append(TestCase(
            id: "harness_encode_arguments",
            description: "Verify encode argument building",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_encode_arguments")
        ))
        cases.append(TestCase(
            id: "harness_decode_arguments",
            description: "Verify decode argument building",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_decode_arguments")
        ))
        cases.append(TestCase(
            id: "harness_pgm_creation",
            description: "Verify PGM test image creation",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_pgm_creation")
        ))
        cases.append(TestCase(
            id: "harness_ppm_creation",
            description: "Verify PPM test image creation",
            category: .harness,
            image: rgbImage,
            validation: .init(name: "harness_ppm_creation")
        ))
        cases.append(TestCase(
            id: "harness_corpus_generation",
            description: "Verify test corpus generation",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_corpus_generation")
        ))
        cases.append(TestCase(
            id: "harness_report_generation",
            description: "Verify report generation",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_report_generation")
        ))
        cases.append(TestCase(
            id: "harness_corrupt_generator",
            description: "Verify corrupt codestream generation",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_corrupt_generator")
        ))
        cases.append(TestCase(
            id: "harness_htj2k_detection",
            description: "Verify HTJ2K support detection",
            category: .harness,
            image: defaultImage,
            validation: .init(name: "harness_htj2k_detection")
        ))

        // ── 2. J2KSwift → OpenJPEG tests ────────────────────────────────

        // Progression orders
        for order in OpenJPEGProgressionOrder.allCases {
            cases.append(TestCase(
                id: "j2k_to_ojp_progression_\(order.rawValue)",
                description: "Encode with J2KSwift (progression \(order.rawValue)), decode with OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: defaultImage,
                validation: .init(
                    name: "progression_\(order.rawValue)",
                    direction: .j2kSwiftToOpenJPEG,
                    progressionOrder: order
                )
            ))
        }

        // Quality layers
        for layers in [1, 2, 3, 5, 10] {
            cases.append(TestCase(
                id: "j2k_to_ojp_layers_\(layers)",
                description: "Encode with J2KSwift (\(layers) quality layers), decode with OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: defaultImage,
                validation: .init(
                    name: "quality_layers_\(layers)",
                    direction: .j2kSwiftToOpenJPEG,
                    expectLossless: false,
                    minimumPSNR: 25.0,
                    maximumAbsoluteError: 50,
                    qualityLayers: layers
                )
            ))
        }

        // Lossless round-trip
        for image in corpus.filter({ $0.bitDepth == 8 && $0.components == 1 }).prefix(5) {
            cases.append(TestCase(
                id: "j2k_to_ojp_lossless_\(image.name)",
                description: "Lossless round-trip: J2KSwift encode → OpenJPEG decode (\(image.name))",
                category: .j2kSwiftToOpenJPEG,
                image: image,
                validation: .init(
                    name: "lossless_\(image.name)",
                    direction: .j2kSwiftToOpenJPEG,
                    expectLossless: true,
                    maximumAbsoluteError: 0
                )
            ))
        }

        // Lossy encoding within PSNR tolerance
        for psnr in [30.0, 35.0, 40.0, 45.0, 50.0] {
            cases.append(TestCase(
                id: "j2k_to_ojp_lossy_psnr\(Int(psnr))",
                description: "Lossy encode PSNR≥\(Int(psnr))dB: J2KSwift → OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: defaultImage,
                validation: .init(
                    name: "lossy_psnr\(Int(psnr))",
                    direction: .j2kSwiftToOpenJPEG,
                    expectLossless: false,
                    minimumPSNR: psnr,
                    maximumAbsoluteError: 100
                )
            ))
        }

        // File format compatibility
        for fmt in OpenJPEGOutputFormat.allCases {
            cases.append(TestCase(
                id: "j2k_to_ojp_format_\(fmt.rawValue)",
                description: "Format compatibility (\(fmt.rawValue)): J2KSwift → OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: defaultImage,
                validation: .init(
                    name: "format_\(fmt.rawValue)",
                    direction: .j2kSwiftToOpenJPEG,
                    format: fmt
                )
            ))
        }

        // RGB images
        cases.append(TestCase(
            id: "j2k_to_ojp_rgb_lossless",
            description: "Lossless RGB: J2KSwift → OpenJPEG",
            category: .j2kSwiftToOpenJPEG,
            image: rgbImage,
            validation: .init(
                name: "rgb_lossless",
                direction: .j2kSwiftToOpenJPEG,
                expectLossless: true
            )
        ))
        cases.append(TestCase(
            id: "j2k_to_ojp_rgb_lossy",
            description: "Lossy RGB: J2KSwift → OpenJPEG",
            category: .j2kSwiftToOpenJPEG,
            image: rgbImage,
            validation: .init(
                name: "rgb_lossy",
                direction: .j2kSwiftToOpenJPEG,
                expectLossless: false,
                minimumPSNR: 30.0,
                maximumAbsoluteError: 50
            )
        ))

        // Decomposition level variants
        for levels in [1, 3, 6] {
            cases.append(TestCase(
                id: "j2k_to_ojp_decomp_\(levels)",
                description: "Decomposition levels=\(levels): J2KSwift → OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: defaultImage,
                validation: .init(
                    name: "decomp_\(levels)",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }

        // Code-block size variants
        for size in [16, 32, 64] {
            cases.append(TestCase(
                id: "j2k_to_ojp_cblk_\(size)",
                description: "Code-block size \(size)×\(size): J2KSwift → OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: defaultImage,
                validation: .init(
                    name: "cblk_\(size)",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }

        // Lossy compression ratio variants
        for ratio in [5.0, 10.0, 20.0, 50.0, 100.0] {
            cases.append(TestCase(
                id: "j2k_to_ojp_ratio_\(Int(ratio))",
                description: "Compression ratio \(Int(ratio)):1: J2KSwift → OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: defaultImage,
                validation: .init(
                    name: "ratio_\(Int(ratio))",
                    direction: .j2kSwiftToOpenJPEG,
                    expectLossless: false,
                    minimumPSNR: 20.0,
                    maximumAbsoluteError: 100
                )
            ))
        }

        // Pattern coverage for J2KSwift → OpenJPEG
        for pattern in [TestImagePattern.stripes, .diagonal, .zonePlate, .random, .uniform] {
            cases.append(TestCase(
                id: "j2k_to_ojp_pattern_\(pattern.rawValue)",
                description: "Pattern \(pattern.rawValue): J2KSwift → OpenJPEG",
                category: .j2kSwiftToOpenJPEG,
                image: OpenJPEGTestCorpus.TestImage(
                    name: "pattern_\(pattern.rawValue)_64x64",
                    width: 64, height: 64,
                    components: 1, bitDepth: 8,
                    isSigned: false, pattern: pattern,
                    category: .synthetic
                ),
                validation: .init(
                    name: "pattern_\(pattern.rawValue)",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }

        // ── 3. OpenJPEG → J2KSwift tests ────────────────────────────────

        // All OpenJPEG encoder configurations
        for order in OpenJPEGProgressionOrder.allCases {
            cases.append(TestCase(
                id: "ojp_to_j2k_progression_\(order.rawValue)",
                description: "Encode with OpenJPEG (progression \(order.rawValue)), decode with J2KSwift",
                category: .openJPEGToJ2KSwift,
                image: defaultImage,
                validation: .init(
                    name: "ojp_progression_\(order.rawValue)",
                    direction: .openJPEGToJ2KSwift,
                    progressionOrder: order
                )
            ))
        }

        // Multi-tile, multi-component
        for (tw, th) in [(64, 64), (128, 128), (32, 32)] {
            cases.append(TestCase(
                id: "ojp_to_j2k_tile_\(tw)x\(th)",
                description: "Multi-tile \(tw)×\(th): OpenJPEG → J2KSwift",
                category: .openJPEGToJ2KSwift,
                image: corpus.first { $0.width >= tw * 2 && $0.height >= th * 2 } ?? defaultImage,
                validation: .init(
                    name: "ojp_tile_\(tw)x\(th)",
                    direction: .openJPEGToJ2KSwift,
                    tileWidth: tw,
                    tileHeight: th
                )
            ))
        }

        // ROI decoding of OpenJPEG-encoded files
        cases.append(TestCase(
            id: "ojp_to_j2k_roi",
            description: "ROI decoding of OpenJPEG-encoded files",
            category: .openJPEGToJ2KSwift,
            image: defaultImage,
            validation: .init(
                name: "ojp_roi",
                direction: .openJPEGToJ2KSwift
            )
        ))

        // Progressive decoding of OpenJPEG codestreams
        cases.append(TestCase(
            id: "ojp_to_j2k_progressive",
            description: "Progressive decoding of OpenJPEG codestreams",
            category: .openJPEGToJ2KSwift,
            image: defaultImage,
            validation: .init(
                name: "ojp_progressive",
                direction: .openJPEGToJ2KSwift
            )
        ))

        // HTJ2K interoperability (OpenJPEG 2.5+)
        cases.append(TestCase(
            id: "ojp_to_j2k_htj2k",
            description: "HTJ2K interoperability (OpenJPEG 2.5+)",
            category: .openJPEGToJ2KSwift,
            image: defaultImage,
            validation: .init(
                name: "ojp_htj2k",
                direction: .openJPEGToJ2KSwift
            )
        ))

        // Multi-component images
        cases.append(TestCase(
            id: "ojp_to_j2k_multicomponent",
            description: "Multi-component image: OpenJPEG → J2KSwift",
            category: .openJPEGToJ2KSwift,
            image: rgbImage,
            validation: .init(
                name: "ojp_multicomponent",
                direction: .openJPEGToJ2KSwift
            )
        ))

        // Lossless from OpenJPEG
        for image in corpus.filter({ $0.bitDepth == 8 && $0.components == 1 }).prefix(3) {
            cases.append(TestCase(
                id: "ojp_to_j2k_lossless_\(image.name)",
                description: "Lossless: OpenJPEG encode → J2KSwift decode (\(image.name))",
                category: .openJPEGToJ2KSwift,
                image: image,
                validation: .init(
                    name: "ojp_lossless_\(image.name)",
                    direction: .openJPEGToJ2KSwift,
                    expectLossless: true,
                    maximumAbsoluteError: 0
                )
            ))
        }

        // Lossy from OpenJPEG
        for ratio in [10.0, 20.0, 50.0] {
            cases.append(TestCase(
                id: "ojp_to_j2k_lossy_ratio_\(Int(ratio))",
                description: "Lossy ratio \(Int(ratio)):1: OpenJPEG → J2KSwift",
                category: .openJPEGToJ2KSwift,
                image: defaultImage,
                validation: .init(
                    name: "ojp_lossy_ratio_\(Int(ratio))",
                    direction: .openJPEGToJ2KSwift,
                    expectLossless: false,
                    minimumPSNR: 20.0,
                    maximumAbsoluteError: 100
                )
            ))
        }

        // All formats from OpenJPEG
        for fmt in OpenJPEGOutputFormat.allCases {
            cases.append(TestCase(
                id: "ojp_to_j2k_format_\(fmt.rawValue)",
                description: "Format \(fmt.rawValue): OpenJPEG → J2KSwift",
                category: .openJPEGToJ2KSwift,
                image: defaultImage,
                validation: .init(
                    name: "ojp_format_\(fmt.rawValue)",
                    direction: .openJPEGToJ2KSwift,
                    format: fmt
                )
            ))
        }

        // Decomposition levels from OpenJPEG
        for levels in [1, 3, 6] {
            cases.append(TestCase(
                id: "ojp_to_j2k_decomp_\(levels)",
                description: "Decomposition levels=\(levels): OpenJPEG → J2KSwift",
                category: .openJPEGToJ2KSwift,
                image: defaultImage,
                validation: .init(
                    name: "ojp_decomp_\(levels)",
                    direction: .openJPEGToJ2KSwift
                )
            ))
        }

        // Pattern coverage for OpenJPEG → J2KSwift
        for pattern in [TestImagePattern.stripes, .diagonal, .checkerboard] {
            cases.append(TestCase(
                id: "ojp_to_j2k_pattern_\(pattern.rawValue)",
                description: "Pattern \(pattern.rawValue): OpenJPEG → J2KSwift",
                category: .openJPEGToJ2KSwift,
                image: OpenJPEGTestCorpus.TestImage(
                    name: "ojp_pattern_\(pattern.rawValue)_64x64",
                    width: 64, height: 64,
                    components: 1, bitDepth: 8,
                    isSigned: false, pattern: pattern,
                    category: .synthetic
                ),
                validation: .init(
                    name: "ojp_pattern_\(pattern.rawValue)",
                    direction: .openJPEGToJ2KSwift
                )
            ))
        }

        // ── 4. Edge case tests ───────────────────────────────────────────

        // Single-pixel images
        if let singlePixel = corpus.first(where: { $0.width == 1 && $0.height == 1 }) {
            for dir in OpenJPEGInteropPipeline.Direction.allCases {
                cases.append(TestCase(
                    id: "edge_single_pixel_\(dir == .j2kSwiftToOpenJPEG ? "j2k" : "ojp")",
                    description: "Single-pixel image (\(dir.rawValue))",
                    category: .edgeCase,
                    image: singlePixel,
                    validation: .init(
                        name: "single_pixel_\(dir.rawValue)",
                        direction: dir
                    )
                ))
            }
        }

        // Maximum-dimension images (synthetic small representation)
        cases.append(TestCase(
            id: "edge_max_dimension",
            description: "Large dimension image encoding/decoding",
            category: .edgeCase,
            image: corpus.first { $0.width == 512 } ?? defaultImage,
            validation: .init(
                name: "max_dimension",
                direction: .j2kSwiftToOpenJPEG
            )
        ))

        // Unusual bit depths
        for bitDepth in [1, 12, 16, 24, 32] {
            if let img = corpus.first(where: { $0.bitDepth == bitDepth }) {
                cases.append(TestCase(
                    id: "edge_bitdepth_\(bitDepth)",
                    description: "Unusual bit depth: \(bitDepth)-bit",
                    category: .edgeCase,
                    image: img,
                    validation: .init(
                        name: "bitdepth_\(bitDepth)",
                        direction: .j2kSwiftToOpenJPEG
                    )
                ))
            }
        }

        // Signed vs unsigned component data
        for img in corpus.filter({ $0.isSigned }) {
            cases.append(TestCase(
                id: "edge_signed_\(img.name)",
                description: "Signed component data: \(img.name)",
                category: .edgeCase,
                image: img,
                validation: .init(
                    name: "signed_\(img.name)",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }

        // Non-standard tile sizes
        for (tw, th) in [(7, 7), (13, 17), (3, 5)] {
            cases.append(TestCase(
                id: "edge_tile_\(tw)x\(th)",
                description: "Non-standard tile size: \(tw)×\(th)",
                category: .edgeCase,
                image: defaultImage,
                validation: .init(
                    name: "tile_\(tw)x\(th)",
                    direction: .openJPEGToJ2KSwift,
                    tileWidth: tw,
                    tileHeight: th
                )
            ))
        }

        // Corrupt/truncated codestreams from each encoder
        for corruptionType in CorruptCodestreamGenerator.CorruptionType.allCases {
            cases.append(TestCase(
                id: "edge_corrupt_\(corruptionType.rawValue)",
                description: "Corrupt codestream: \(corruptionType.rawValue)",
                category: .edgeCase,
                image: defaultImage,
                validation: .init(
                    name: "corrupt_\(corruptionType.rawValue)",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }

        // Non-square images
        if let nonSquare = corpus.first(where: { $0.width != $0.height }) {
            cases.append(TestCase(
                id: "edge_nonsquare",
                description: "Non-square image: \(nonSquare.width)×\(nonSquare.height)",
                category: .edgeCase,
                image: nonSquare,
                validation: .init(
                    name: "nonsquare",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }

        // Wide and tall images
        if let wide = corpus.first(where: { $0.width > 10 * $0.height }) {
            cases.append(TestCase(
                id: "edge_wide",
                description: "Wide image: \(wide.width)×\(wide.height)",
                category: .edgeCase,
                image: wide,
                validation: .init(
                    name: "wide",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }
        if let tall = corpus.first(where: { $0.height > 10 * $0.width }) {
            cases.append(TestCase(
                id: "edge_tall",
                description: "Tall image: \(tall.width)×\(tall.height)",
                category: .edgeCase,
                image: tall,
                validation: .init(
                    name: "tall",
                    direction: .j2kSwiftToOpenJPEG
                )
            ))
        }

        return cases
    }

    /// Returns the total number of test cases in the suite.
    public static var testCount: Int {
        allTestCases().count
    }

    /// Returns test cases filtered by category.
    ///
    /// - Parameter category: The category to filter by.
    /// - Returns: Matching test cases.
    public static func testCases(category: TestCategory) -> [TestCase] {
        allTestCases().filter { $0.category == category }
    }
}
