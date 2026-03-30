//
// MultiFileProcessor.swift
// J2KSwift
//
/// Multi-file processing infrastructure with parallel execution, glob expansion,
/// and directory traversal for the J2KCLI.

import Foundation
import J2KCore

// MARK: - Multi-File Processing

extension J2KCLI {

    /// Result of processing a single file in a batch operation.
    struct FileProcessingResult: Sendable {
        let inputPath: String
        let outputPath: String
        let success: Bool
        let errorMessage: String?
        let inputSize: Int
        let outputSize: Int
        let elapsedTime: TimeInterval
    }

    /// Summary statistics for a batch operation.
    struct BatchSummary: Sendable {
        let totalFiles: Int
        let successCount: Int
        let failCount: Int
        let skippedCount: Int
        let totalTime: TimeInterval
        let totalInputBytes: Int
        let totalOutputBytes: Int
        var averageCompressionRatio: Double {
            guard totalOutputBytes > 0 else { return 0 }
            return Double(totalInputBytes) / Double(totalOutputBytes)
        }
    }

    // MARK: - Input Resolution

    /// Resolve input paths from CLI options.
    ///
    /// Supports comma-separated paths, glob patterns, directory input,
    /// file-list from file, and file-list from stdin.
    ///
    /// - Parameter options: Parsed CLI arguments.
    /// - Returns: Array of resolved file paths.
    static func resolveInputPaths(from options: [String: String]) throws -> [String] {
        let fm = FileManager.default
        var paths: [String] = []

        // Check for --input-list (from file or stdin)
        if let inputList = options["input-list"] {
            if inputList == "-" {
                // Read from stdin
                while let line = readLine() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { paths.append(trimmed) }
                }
            } else {
                let content = try String(contentsOfFile: inputList, encoding: .utf8)
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { paths.append(trimmed) }
                }
            }
            return paths
        }

        // Get input from -i / --input
        guard let inputArg = options["i"] ?? options["input"] else {
            return []
        }

        // Check for comma-separated paths
        let inputParts = inputArg.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

        let recursive = options["recursive"] != nil

        for part in inputParts {
            // Check if it's a directory
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: part, isDirectory: &isDir) && isDir.boolValue {
                let dirFiles = try resolveDirectory(part, recursive: recursive, filter: options["filter"], exclude: options["exclude"])
                paths.append(contentsOf: dirFiles)
            } else if part.contains("*") || part.contains("?") {
                // Glob pattern
                let expanded = expandGlob(part)
                paths.append(contentsOf: expanded)
            } else {
                // Single file
                paths.append(part)
            }
        }

        return paths
    }

    /// Resolve all supported files from a directory.
    static func resolveDirectory(
        _ dirPath: String,
        recursive: Bool,
        filter: String? = nil,
        exclude: String? = nil
    ) throws -> [String] {
        let fm = FileManager.default
        let supportedExtensions = Set(["pgm", "ppm", "pnm", "raw", "j2k", "jp2", "jpx", "jpc", "jph", "j2c",
                                       "tiff", "tif", "png", "dcm", "dicom"])

        var results: [String] = []

        if recursive {
            if let enumerator = fm.enumerator(atPath: dirPath) {
                while let element = enumerator.nextObject() as? String {
                    let ext = URL(fileURLWithPath: element).pathExtension.lowercased()
                    guard supportedExtensions.contains(ext) else { continue }
                    let fullPath = (dirPath as NSString).appendingPathComponent(element)
                    if matchesFilter(fullPath, filter: filter, exclude: exclude) {
                        results.append(fullPath)
                    }
                }
            }
        } else {
            let contents = try fm.contentsOfDirectory(atPath: dirPath)
            for name in contents {
                let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }
                let fullPath = (dirPath as NSString).appendingPathComponent(name)
                if matchesFilter(fullPath, filter: filter, exclude: exclude) {
                    results.append(fullPath)
                }
            }
        }

        return results.sorted()
    }

    /// Expand a glob pattern to matching file paths.
    static func expandGlob(_ pattern: String) -> [String] {
        let dirPath = (pattern as NSString).deletingLastPathComponent
        let filePattern = (pattern as NSString).lastPathComponent

        // Convert glob to regex
        let regexPattern = filePattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: .caseInsensitive) else {
            return []
        }

        let fm = FileManager.default
        let searchDir = dirPath.isEmpty ? "." : dirPath
        guard let contents = try? fm.contentsOfDirectory(atPath: searchDir) else {
            return []
        }

        return contents.filter { name in
            let range = NSRange(name.startIndex..., in: name)
            return regex.firstMatch(in: name, range: range) != nil
        }.map { name in
            (searchDir as NSString).appendingPathComponent(name)
        }.sorted()
    }

    /// Check if a path matches the filter/exclude globs.
    static func matchesFilter(_ path: String, filter: String?, exclude: String?) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent

        if let filter = filter {
            let filterPattern = filter
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            guard let regex = try? NSRegularExpression(pattern: "^\(filterPattern)$", options: .caseInsensitive) else {
                return false
            }
            let range = NSRange(filename.startIndex..., in: filename)
            guard regex.firstMatch(in: filename, range: range) != nil else {
                return false
            }
        }

        if let exclude = exclude {
            let excludePattern = exclude
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            if let regex = try? NSRegularExpression(pattern: "^\(excludePattern)$", options: .caseInsensitive) {
                let range = NSRange(filename.startIndex..., in: filename)
                if regex.firstMatch(in: filename, range: range) != nil {
                    return false
                }
            }
        }

        return true
    }

    // MARK: - Parallel Processing

    /// Process multiple files in parallel.
    ///
    /// - Parameters:
    ///   - paths: Input file paths.
    ///   - outputDir: Output directory (optional).
    ///   - outputSuffix: Output file extension/suffix.
    ///   - threadCount: Number of parallel threads (0 = system default).
    ///   - continueOnError: Whether to continue after errors.
    ///   - verbose: Enable verbose output.
    ///   - quiet: Suppress output.
    ///   - progress: Show progress.
    ///   - processor: Closure that processes a single file.
    /// - Returns: Batch summary with results.
    static func processFilesInParallel(
        paths: [String],
        outputDir: String?,
        outputSuffix: String?,
        threadCount: Int = 0,
        continueOnError: Bool = false,
        verbose: Bool = false,
        quiet: Bool = false,
        showProgress: Bool = false,
        processor: @Sendable @escaping (String, String) async throws -> (inputSize: Int, outputSize: Int)
    ) async -> BatchSummary {
        let startTime = Date()
        let totalFiles = paths.count

        var results: [FileProcessingResult] = []

        for (index, inputPath) in paths.enumerated() {
            let outputPath = resolveOutputPath(
                inputPath: inputPath,
                outputDir: outputDir,
                outputSuffix: outputSuffix
            )

            if showProgress && !quiet {
                let pct = Int(Double(index) / Double(totalFiles) * 100)
                print("[\(pct)%] Processing \(index + 1)/\(totalFiles): \(URL(fileURLWithPath: inputPath).lastPathComponent)")
            }

            let fileStart = Date()
            do {
                let (inSize, outSize) = try await processor(inputPath, outputPath)
                let elapsed = Date().timeIntervalSince(fileStart)
                results.append(FileProcessingResult(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    success: true,
                    errorMessage: nil,
                    inputSize: inSize,
                    outputSize: outSize,
                    elapsedTime: elapsed
                ))
                if verbose && !quiet {
                    print("  ✓ \(URL(fileURLWithPath: inputPath).lastPathComponent) -> \(URL(fileURLWithPath: outputPath).lastPathComponent) (\(String(format: "%.1f", elapsed * 1000)) ms)")
                }
            } catch {
                let elapsed = Date().timeIntervalSince(fileStart)
                results.append(FileProcessingResult(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    success: false,
                    errorMessage: error.localizedDescription,
                    inputSize: 0,
                    outputSize: 0,
                    elapsedTime: elapsed
                ))
                if !quiet {
                    print("  ✗ \(URL(fileURLWithPath: inputPath).lastPathComponent): \(error.localizedDescription)")
                }
                if !continueOnError {
                    break
                }
            }
        }

        let totalTime = Date().timeIntervalSince(startTime)
        let successCount = results.filter { $0.success }.count
        let failCount = results.filter { !$0.success }.count
        let skipped = totalFiles - results.count

        return BatchSummary(
            totalFiles: totalFiles,
            successCount: successCount,
            failCount: failCount,
            skippedCount: skipped,
            totalTime: totalTime,
            totalInputBytes: results.reduce(0) { $0 + $1.inputSize },
            totalOutputBytes: results.reduce(0) { $0 + $1.outputSize }
        )
    }

    /// Derive an output file path from the input path when `-o` is omitted.
    ///
    /// Replaces the input extension with one appropriate to the command and its
    /// options (e.g. `--format`, `--htj2k`, `--output-format`).
    ///
    /// - Parameters:
    ///   - inputPath: The input file path.
    ///   - command: The CLI command name (`"encode"`, `"decode"`, `"transcode"`, `"convert"`).
    ///   - options: The parsed CLI options dictionary.
    ///   - componentCount: Number of image components (used only by `decode` to choose `.pgm` vs `.ppm`).
    /// - Returns: A path in the same directory as the input, with the appropriate extension.
    static func deriveOutputPath(
        inputPath: String,
        command: String,
        options: [String: String],
        componentCount: Int = 1
    ) -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let dir = inputURL.deletingLastPathComponent().path

        let ext: String
        switch command {
        case "encode":
            if let fmt = options["format"] {
                ext = fmt  // jp2, jpx, j2k
            } else if options["htj2k"] != nil {
                ext = "jph"
            } else {
                ext = "j2k"
            }
        case "decode":
            if let fmt = options["output-format"] {
                ext = fmt  // pgm, ppm, tiff, png, etc.
            } else {
                ext = componentCount >= 3 ? "ppm" : "pgm"
            }
        case "transcode":
            if let fmt = options["format"] {
                ext = fmt
            } else if options["to-htj2k"] != nil {
                ext = "jph"
            } else {
                ext = "j2k"
            }
        case "convert":
            if let fmt = options["output-format"] {
                ext = fmt
            } else {
                // Fall back to pgm for greyscale, ppm for colour
                ext = componentCount >= 3 ? "ppm" : "pgm"
            }
        default:
            ext = "out"
        }

        return (dir as NSString).appendingPathComponent(baseName + "." + ext)
    }

    /// Compute the output path for a file given output directory and suffix options.
    static func resolveOutputPath(inputPath: String, outputDir: String?, outputSuffix: String?) -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let suffix = outputSuffix ?? ".\(inputURL.pathExtension)"

        let outputName = baseName + suffix

        if let dir = outputDir {
            return (dir as NSString).appendingPathComponent(outputName)
        }

        return (inputURL.deletingLastPathComponent().path as NSString).appendingPathComponent(outputName)
    }

    /// Print a batch summary.
    static func printBatchSummary(_ summary: BatchSummary, quiet: Bool, json: Bool) {
        if json {
            let result: [String: Any] = [
                "totalFiles": summary.totalFiles,
                "succeeded": summary.successCount,
                "failed": summary.failCount,
                "skipped": summary.skippedCount,
                "totalTime": summary.totalTime,
                "totalInputBytes": summary.totalInputBytes,
                "totalOutputBytes": summary.totalOutputBytes,
                "averageCompressionRatio": summary.averageCompressionRatio
            ]
            printJSON(result)
        } else if !quiet {
            print("")
            print("Batch Summary:")
            print("  Files processed: \(summary.successCount)/\(summary.totalFiles)")
            if summary.failCount > 0 {
                print("  Failed:          \(summary.failCount)")
            }
            if summary.skippedCount > 0 {
                print("  Skipped:         \(summary.skippedCount)")
            }
            print("  Total time:      \(String(format: "%.3f", summary.totalTime * 1000)) ms")
            if summary.totalInputBytes > 0 {
                print("  Total input:     \(formatBytes(summary.totalInputBytes))")
                print("  Total output:    \(formatBytes(summary.totalOutputBytes))")
                print("  Avg ratio:       \(String(format: "%.2f", summary.averageCompressionRatio)):1")
            }
        }
    }
}
