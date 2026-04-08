//
// QualityBenchmark.swift
// J2KSwift
//
/// Quality benchmark command — measure encoder quality against reference images.
///
/// Computes PSNR, SSIM, MAE, and maximum absolute error between an original
/// (reference) image and one or more encoded outputs. Generates JSON reports,
/// Markdown summaries, absolute difference images, and worst-error patches.

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {

    /// Entry point for `j2k benchmark --input <original> --compare <encoded...>`.
    ///
    /// When `--compare` is present, the benchmark command switches from performance
    /// timing to quality analysis mode.
    static func qualityBenchmarkCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printQualityBenchmarkHelp()
            return
        }

        guard let inputPath = options["i"] ?? options["input"] else {
            print("Error: Missing required argument: -i/--input (original image)")
            exit(1)
        }

        let compareFiles = parseCompareFiles(args)
        guard !compareFiles.isEmpty else {
            print("Error: --compare requires at least one file")
            exit(1)
        }

        let outputDir = options["o"] ?? options["output"] ?? "benchmark_report"
        let quiet = options["quiet"] != nil
        let patchSize = Int(options["patch-size"] ?? "64") ?? 64

        // Create output directory
        let fm = FileManager.default
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // Load original image
        if !quiet { print("Loading original: \(inputPath)") }
        let originalImage = try loadImage(from: inputPath)
        let originalFileSize = try fileSize(path: inputPath)
        if !quiet {
            print("  Dimensions: \(originalImage.width)×\(originalImage.height), \(originalImage.componentCount) component(s)")
        }

        // Process each comparison file
        var reports: [J2KQualityReport] = []

        for comparePath in compareFiles {
            if !quiet { print("\nAnalysing: \(comparePath)") }

            let comparedImage: J2KImage
            let ext = URL(fileURLWithPath: comparePath).pathExtension.lowercased()
            let j2kExts: Set<String> = ["j2k", "jp2", "jpx", "jph", "j2c", "jpc"]

            if j2kExts.contains(ext) {
                let data = try Data(contentsOf: URL(fileURLWithPath: comparePath))
                let decoder = J2KDecoder()
                comparedImage = try decoder.decode(data)
            } else {
                comparedImage = try loadImage(from: comparePath)
            }

            let comparedFileSize = try fileSize(path: comparePath)

            let report = try J2KQualityMetricsEngine.computeReport(
                original: originalImage,
                compared: comparedImage,
                originalLabel: inputPath,
                comparedLabel: comparePath,
                originalFileSize: Int64(originalFileSize),
                comparedFileSize: Int64(comparedFileSize)
            )

            reports.append(report)

            // Print summary to console
            if !quiet { printReportSummary(report) }

            // Generate difference image
            let diffName = safeName(comparePath) + "_diff.png"
            let diffPath = (outputDir as NSString).appendingPathComponent(diffName)
            let diffImage = buildDifferenceImage(original: originalImage, compared: comparedImage)
            try savePNG(diffImage, to: URL(fileURLWithPath: diffPath))
            if !quiet { print("  Difference image: \(diffPath)") }

            // Generate worst-error patch
            let patchName = safeName(comparePath) + "_worst_patch.png"
            let patchPath = (outputDir as NSString).appendingPathComponent(patchName)
            let patchImage = buildWorstErrorPatch(
                original: originalImage, compared: comparedImage,
                centreX: report.worstErrorLocation.x,
                centreY: report.worstErrorLocation.y,
                patchSize: patchSize)
            try savePNG(patchImage, to: URL(fileURLWithPath: patchPath))
            if !quiet { print("  Worst-error patch: \(patchPath)") }
        }

        // Generate JSON report
        let jsonPath = (outputDir as NSString).appendingPathComponent("quality_report.json")
        let jsonData = buildJSONReport(reports)
        try jsonData.write(to: URL(fileURLWithPath: jsonPath))
        if !quiet { print("\nJSON report: \(jsonPath)") }

        // Generate Markdown summary
        let mdPath = (outputDir as NSString).appendingPathComponent("quality_report.md")
        let mdData = buildMarkdownReport(reports, originalPath: inputPath)
        try mdData.write(to: URL(fileURLWithPath: mdPath), atomically: true, encoding: .utf8)
        if !quiet { print("Markdown report: \(mdPath)") }

        if !quiet { print("\nQuality benchmark complete.") }
    }

    // MARK: - Argument Parsing

    /// Collect all file paths following `--compare` flags.
    ///
    /// Supports both `--compare a.j2k b.jp2` and `--compare a.j2k --compare b.jp2`.
    static func parseCompareFiles(_ args: [String]) -> [String] {
        var files: [String] = []
        var collecting = false
        for arg in args {
            if arg == "--compare" || arg == "-c" {
                collecting = true
                continue
            }
            if arg.hasPrefix("-") {
                collecting = false
                continue
            }
            if collecting {
                files.append(arg)
            }
        }
        return files
    }

    // MARK: - Console Output

    private static func printReportSummary(_ report: J2KQualityReport) {
        let psnrStr = report.globalPSNR.isInfinite ? "Inf (lossless)" : String(format: "%.4f dB", report.globalPSNR)
        print("  File size:         \(formatBytes(Int(report.comparedFileSize)))")
        print("  Compression ratio: \(String(format: "%.2f", report.compressionRatio)):1")
        print("  PSNR (global):     \(psnrStr)")
        print("  SSIM (global):     \(String(format: "%.6f", report.globalSSIM))")
        print("  MAE:               \(String(format: "%.6f", report.globalMAE))")
        print("  Max absolute error:\(String(format: " %d", report.globalMaxAbsoluteError))")
        print("  Bit-exact:         \(report.bitExact ? "Yes" : "No")")
        if report.componentCount > 1 {
            for cm in report.perComponent {
                let p = cm.psnr.isInfinite ? "Inf" : String(format: "%.4f", cm.psnr)
                print("    [Component \(cm.component)] PSNR: \(p) dB, SSIM: \(String(format: "%.6f", cm.ssim)), MAE: \(String(format: "%.6f", cm.mae)), MaxErr: \(cm.maxAbsoluteError)")
            }
        }
        if report.globalMaxAbsoluteError > 0 {
            print("  Worst error at:    (\(report.worstErrorLocation.x), \(report.worstErrorLocation.y)) in component \(report.worstErrorComponent)")
        }
    }

    // MARK: - JSON Report

    private static func buildJSONReport(_ reports: [J2KQualityReport]) -> Data {
        var entries: [[String: Any]] = []
        for r in reports {
            var perComp: [[String: Any]] = []
            for c in r.perComponent {
                perComp.append([
                    "component": c.component,
                    "psnr": c.psnr.isInfinite ? "Inf" as Any : c.psnr as Any,
                    "ssim": c.ssim,
                    "mse": c.mse,
                    "mae": c.mae,
                    "maxAbsoluteError": c.maxAbsoluteError,
                    "bitExact": c.bitExact,
                ])
            }
            entries.append([
                "original": r.originalLabel,
                "compared": r.comparedLabel,
                "width": r.width,
                "height": r.height,
                "componentCount": r.componentCount,
                "originalFileSizeBytes": r.originalFileSize,
                "comparedFileSizeBytes": r.comparedFileSize,
                "compressionRatio": r.compressionRatio,
                "globalPSNR": r.globalPSNR.isInfinite ? "Inf" as Any : r.globalPSNR as Any,
                "globalSSIM": r.globalSSIM,
                "globalMSE": r.globalMSE,
                "globalMAE": r.globalMAE,
                "globalMaxAbsoluteError": r.globalMaxAbsoluteError,
                "bitExact": r.bitExact,
                "worstErrorLocation": ["x": r.worstErrorLocation.x, "y": r.worstErrorLocation.y],
                "worstErrorComponent": r.worstErrorComponent,
                "perComponent": perComp,
            ])
        }

        let root: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "engine": "J2KSwift Quality Benchmark",
            "comparisons": entries,
        ]

        let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return data ?? Data()
    }

    // MARK: - Markdown Report

    private static func buildMarkdownReport(_ reports: [J2KQualityReport], originalPath: String) -> String {
        var md = """
        # J2KSwift Quality Benchmark Report

        **Generated:** \(ISO8601DateFormatter().string(from: Date()))

        ## Original Image

        | Property | Value |
        |----------|-------|
        | Path | `\(originalPath)` |

        """

        if let first = reports.first {
            md += """
            | Dimensions | \(first.width)×\(first.height) |
            | Components | \(first.componentCount) |
            | File size | \(formatBytes(Int(first.originalFileSize))) |

            ## Comparison Summary

            | File | Size | Ratio | PSNR (dB) | SSIM | MAE | Max Error | Bit-exact |
            |------|------|-------|-----------|------|-----|-----------|-----------|

            """
        }

        for r in reports {
            let psnr = r.globalPSNR.isInfinite ? "Inf" : String(format: "%.2f", r.globalPSNR)
            let name = URL(fileURLWithPath: r.comparedLabel).lastPathComponent
            md += "| `\(name)` | \(formatBytes(Int(r.comparedFileSize))) | \(String(format: "%.2f", r.compressionRatio)):1 | \(psnr) | \(String(format: "%.6f", r.globalSSIM)) | \(String(format: "%.6f", r.globalMAE)) | \(r.globalMaxAbsoluteError) | \(r.bitExact ? "Yes" : "No") |\n"
        }

        md += "\n## Detailed Results\n\n"

        for (idx, r) in reports.enumerated() {
            let name = URL(fileURLWithPath: r.comparedLabel).lastPathComponent
            md += "### \(idx + 1). \(name)\n\n"
            md += "| Metric | Global |"
            for c in r.perComponent { md += " Component \(c.component) |" }
            md += "\n|--------|--------|"
            for _ in r.perComponent { md += "---|" }
            md += "\n"

            let fmtP = { (v: Double) -> String in v.isInfinite ? "Inf" : String(format: "%.4f", v) }
            let fmtF = { (v: Double) -> String in String(format: "%.6f", v) }

            md += "| PSNR (dB) | \(fmtP(r.globalPSNR)) |"
            for c in r.perComponent { md += " \(fmtP(c.psnr)) |" }
            md += "\n"
            md += "| SSIM | \(fmtF(r.globalSSIM)) |"
            for c in r.perComponent { md += " \(fmtF(c.ssim)) |" }
            md += "\n"
            md += "| MSE | \(fmtF(r.globalMSE)) |"
            for c in r.perComponent { md += " \(fmtF(c.mse)) |" }
            md += "\n"
            md += "| MAE | \(fmtF(r.globalMAE)) |"
            for c in r.perComponent { md += " \(fmtF(c.mae)) |" }
            md += "\n"
            md += "| Max Error | \(r.globalMaxAbsoluteError) |"
            for c in r.perComponent { md += " \(c.maxAbsoluteError) |" }
            md += "\n"

            if r.globalMaxAbsoluteError > 0 {
                md += "\n**Worst error location:** (\(r.worstErrorLocation.x), \(r.worstErrorLocation.y)) in component \(r.worstErrorComponent)\n"
            }

            let safeCmp = safeName(r.comparedLabel)
            md += "\n**Difference image:** `\(safeCmp)_diff.png`\n"
            md += "\n**Worst-error patch:** `\(safeCmp)_worst_patch.png`\n\n"
        }

        return md
    }

    // MARK: - Difference Image

    /// Build an absolute-difference image, scaled for visibility.
    ///
    /// Each pixel is `|original − compared| × scale`, where scale is chosen so
    /// the maximum difference maps to 255.
    static func buildDifferenceImage(original: J2KImage, compared: J2KImage) -> J2KImage {
        let width = original.width
        let height = original.height

        var diffComponents: [J2KComponent] = []

        for ci in 0..<original.componentCount {
            let diffs = J2KQualityMetricsEngine.pixelDifferences(
                original: original.components[ci],
                compared: compared.components[ci])

            // Find max absolute difference for scaling
            var maxDiff = 0
            for d in diffs {
                let ad = abs(d)
                if ad > maxDiff { maxDiff = ad }
            }

            let scale: Double = maxDiff > 0 ? 255.0 / Double(maxDiff) : 1.0
            var data = Data(count: width * height)
            for i in 0..<diffs.count {
                let v = min(255, Int(Double(abs(diffs[i])) * scale + 0.5))
                data[i] = UInt8(v)
            }

            diffComponents.append(J2KComponent(
                index: ci, bitDepth: 8, width: width, height: height, data: data))
        }

        return J2KImage(width: width, height: height, components: diffComponents,
                        colorSpace: original.componentCount == 1 ? .grayscale : .sRGB)
    }

    // MARK: - Worst-Error Patch

    /// Extract a patch centred on the worst-error pixel, containing both
    /// original and compared side-by-side, plus a scaled difference below.
    ///
    /// Layout (3 rows × patchSize):
    ///   Row 0: original patch
    ///   Row 1: compared patch
    ///   Row 2: scaled difference
    static func buildWorstErrorPatch(
        original: J2KImage, compared: J2KImage,
        centreX: Int, centreY: Int,
        patchSize: Int
    ) -> J2KImage {
        let half = patchSize / 2
        let startX = max(0, min(centreX - half, original.width - patchSize))
        let startY = max(0, min(centreY - half, original.height - patchSize))
        let pw = min(patchSize, original.width - startX)
        let ph = min(patchSize, original.height - startY)

        let outWidth = pw
        let outHeight = ph * 3  // original + compared + difference

        var patchComponents: [J2KComponent] = []

        for ci in 0..<original.componentCount {
            let origComp = original.components[ci]
            let compComp = compared.components[ci]
            let bps = origComp.bitDepth <= 8 ? 1 : 2

            var data = Data(count: outWidth * outHeight)

            // Find max diff in patch for scaling
            var maxDiff = 0
            for dy in 0..<ph {
                for dx in 0..<pw {
                    let idx = (startY + dy) * original.width + (startX + dx)
                    let o = readSampleValue(origComp.data, index: idx, bytesPerSample: bps)
                    let c = readSampleValue(compComp.data, index: idx, bytesPerSample: bps)
                    let ad = abs(o - c)
                    if ad > maxDiff { maxDiff = ad }
                }
            }
            let scale: Double = maxDiff > 0 ? 255.0 / Double(maxDiff) : 1.0

            for dy in 0..<ph {
                for dx in 0..<pw {
                    let srcIdx = (startY + dy) * original.width + (startX + dx)
                    let o = readSampleValue(origComp.data, index: srcIdx, bytesPerSample: bps)
                    let c = readSampleValue(compComp.data, index: srcIdx, bytesPerSample: bps)

                    let origVal = bps == 1 ? UInt8(clamping: o) : UInt8(clamping: o >> (origComp.bitDepth - 8))
                    let compVal = bps == 1 ? UInt8(clamping: c) : UInt8(clamping: c >> (origComp.bitDepth - 8))
                    let diffVal = UInt8(clamping: min(255, Int(Double(abs(o - c)) * scale + 0.5)))

                    // Row 0: original
                    data[dy * outWidth + dx] = origVal
                    // Row 1: compared
                    data[(ph + dy) * outWidth + dx] = compVal
                    // Row 2: difference
                    data[(2 * ph + dy) * outWidth + dx] = diffVal
                }
            }

            patchComponents.append(J2KComponent(
                index: ci, bitDepth: 8, width: outWidth, height: outHeight, data: data))
        }

        return J2KImage(width: outWidth, height: outHeight, components: patchComponents,
                        colorSpace: original.componentCount == 1 ? .grayscale : .sRGB)
    }

    // MARK: - Helpers

    private static func readSampleValue(_ data: Data, index: Int, bytesPerSample: Int) -> Int {
        if bytesPerSample == 1 {
            return index < data.count ? Int(data[index]) : 0
        } else {
            let idx = index * 2
            if idx + 1 < data.count {
                return Int(data[idx]) | (Int(data[idx + 1]) << 8)
            }
            return 0
        }
    }

    private static func fileSize(path: String) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        return (attrs[.size] as? Int) ?? 0
    }

    /// Derive a filesystem-safe name from a path (for output files).
    private static func safeName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return name.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
    }

    // MARK: - Help

    private static func printQualityBenchmarkHelp() {
        print("""
        j2k benchmark --compare — Quality analysis and comparison

        USAGE:
            j2k benchmark -i <original> --compare <encoded...> [options]

        DESCRIPTION:
            Compares one or more encoded images against an original reference,
            computing quality metrics and generating visual reports.

        OPTIONS:
            -i, --input PATH            Original (reference) image
            --compare FILE [FILE...]    One or more encoded files to compare
            -o, --output DIR            Output directory (default: benchmark_report)
            --patch-size N              Worst-error patch size in pixels (default: 64)
            --quiet                     Suppress console output

        METRICS:
            PSNR     Peak Signal-to-Noise Ratio (dB), global and per-channel
            SSIM     Structural Similarity Index (0–1)
            MAE      Mean Absolute Error
            MaxErr   Maximum Absolute Error

        OUTPUTS:
            quality_report.json         Full metrics in JSON format
            quality_report.md           Human-readable Markdown summary
            <name>_diff.png             Absolute difference image (scaled)
            <name>_worst_patch.png      Patch around worst-error pixel

        SUPPORTED FORMATS:
            Input:  PGM, PPM, PNG, TIFF, BMP, DICOM
            Compare: J2K, JP2, JPX, JPH, PGM, PPM, PNG, TIFF, BMP

        EXAMPLES:
            j2k benchmark -i original.bmp --compare output.j2k
            j2k benchmark -i ref.png --compare a.jp2 b.jp2 c.j2k -o results
            j2k benchmark -i photo.ppm --compare encoded.j2k --patch-size 128
        """)
    }
}
