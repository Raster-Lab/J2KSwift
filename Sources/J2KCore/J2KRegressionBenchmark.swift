//
// J2KRegressionBenchmark.swift
// J2KSwift
//
// Regression benchmark infrastructure: deterministic encode/decode measurement,
// baseline comparison, threshold checking, and JSON/Markdown report generation.
//

import Foundation

// MARK: - Dataset Manifest

/// Describes a deterministic test image for regression benchmarking.
///
/// Each entry specifies how to procedurally generate an image so that
/// benchmarks are perfectly reproducible without external files.
public struct RegressionDatasetEntry: Sendable, Codable, Equatable {
    /// Unique identifier for this dataset.
    public let id: String

    /// Human-readable description.
    public let description: String

    /// Image width in pixels.
    public let width: Int

    /// Image height in pixels.
    public let height: Int

    /// Number of colour components (1 = grey, 3 = RGB).
    public let components: Int

    /// Bit depth per component.
    public let bitDepth: Int

    /// Pattern used to generate deterministic pixel data.
    public let pattern: GeneratorPattern

    /// Whether to test with lossless encoding.
    public let testLossless: Bool

    /// Whether to test with lossy encoding.
    public let testLossy: Bool

    /// Generator pattern for reproducible image data.
    public enum GeneratorPattern: String, Sendable, Codable, CaseIterable {
        /// Smooth horizontal gradient (0→max).
        case gradient
        /// SMPTE colour bars.
        case colourBars
        /// Checkerboard pattern.
        case checkerboard
        /// Flat mid-grey.
        case flat
        /// Deterministic pseudo-random noise (LCG seeded by dataset id).
        case noise
    }
}

/// The complete dataset manifest for regression benchmarks.
public struct RegressionDatasetManifest: Sendable, Codable {
    /// Manifest format version.
    public let version: String

    /// When this manifest was last updated.
    public let lastUpdated: String

    /// The dataset entries.
    public let datasets: [RegressionDatasetEntry]

    /// The default manifest used by CI.
    public static let `default` = RegressionDatasetManifest(
        version: "1.0.0",
        lastUpdated: "2026-04-08",
        datasets: [
            RegressionDatasetEntry(
                id: "gradient-256",
                description: "256×256 RGB gradient",
                width: 256, height: 256, components: 3, bitDepth: 8,
                pattern: .gradient, testLossless: true, testLossy: true
            ),
            RegressionDatasetEntry(
                id: "bars-256",
                description: "256×256 SMPTE colour bars",
                width: 256, height: 256, components: 3, bitDepth: 8,
                pattern: .colourBars, testLossless: true, testLossy: true
            ),
            RegressionDatasetEntry(
                id: "checker-128",
                description: "128×128 RGB checkerboard",
                width: 128, height: 128, components: 3, bitDepth: 8,
                pattern: .checkerboard, testLossless: true, testLossy: true
            ),
            RegressionDatasetEntry(
                id: "flat-512",
                description: "512×512 flat mid-grey",
                width: 512, height: 512, components: 3, bitDepth: 8,
                pattern: .flat, testLossless: true, testLossy: true
            ),
            RegressionDatasetEntry(
                id: "noise-256",
                description: "256×256 pseudo-random noise",
                width: 256, height: 256, components: 3, bitDepth: 8,
                pattern: .noise, testLossless: true, testLossy: true
            ),
            RegressionDatasetEntry(
                id: "grey-gradient-256",
                description: "256×256 greyscale gradient",
                width: 256, height: 256, components: 1, bitDepth: 8,
                pattern: .gradient, testLossless: true, testLossy: true
            ),
        ]
    )
}

// MARK: - Deterministic Image Generator

/// Generates deterministic test images from dataset entries.
///
/// All generation is seeded and reproducible — no external files needed.
public struct RegressionImageGenerator: Sendable {

    public init() {}

    /// Generates raw pixel data for a dataset entry.
    ///
    /// - Parameter entry: The dataset entry describing the image.
    /// - Returns: An array of component planes, each as `[Int32]`.
    public func generate(_ entry: RegressionDatasetEntry) -> [[Int32]] {
        let count = entry.width * entry.height
        let maxVal = (1 << entry.bitDepth) - 1

        switch entry.pattern {
        case .gradient:
            return generateGradient(entry: entry, count: count, maxVal: maxVal)
        case .colourBars:
            return generateColourBars(entry: entry, count: count, maxVal: maxVal)
        case .checkerboard:
            return generateCheckerboard(entry: entry, count: count, maxVal: maxVal)
        case .flat:
            return generateFlat(entry: entry, count: count, maxVal: maxVal)
        case .noise:
            return generateNoise(entry: entry, count: count, maxVal: maxVal)
        }
    }

    private func generateGradient(
        entry: RegressionDatasetEntry, count: Int, maxVal: Int
    ) -> [[Int32]] {
        var planes = [[Int32]](repeating: [Int32](repeating: 0, count: count),
                               count: entry.components)
        for c in 0..<entry.components {
            for y in 0..<entry.height {
                for x in 0..<entry.width {
                    let val = (x * maxVal / max(entry.width - 1, 1) + c * (maxVal / 3)) % (maxVal + 1)
                    planes[c][y * entry.width + x] = Int32(val)
                }
            }
        }
        return planes
    }

    private func generateColourBars(
        entry: RegressionDatasetEntry, count: Int, maxVal: Int
    ) -> [[Int32]] {
        let m = Int32(maxVal)
        let bars: [(Int32, Int32, Int32)] = [
            (m, m, m), (m, m, 0), (0, m, m), (0, m, 0),
            (m, 0, m), (m, 0, 0), (0, 0, m), (0, 0, 0),
        ]
        var planes = [[Int32]](repeating: [Int32](repeating: 0, count: count),
                               count: min(entry.components, 3))
        let barWidth = max(entry.width / 8, 1)
        for y in 0..<entry.height {
            for x in 0..<entry.width {
                let barIdx = min(x / barWidth, 7)
                let idx = y * entry.width + x
                if entry.components >= 3 {
                    planes[0][idx] = bars[barIdx].0
                    planes[1][idx] = bars[barIdx].1
                    planes[2][idx] = bars[barIdx].2
                } else {
                    // Greyscale: use luminance
                    let (r, g, b) = bars[barIdx]
                    let lum = Int(r) * 306 + Int(g) * 601 + Int(b) * 117 + 512
                    planes[0][idx] = Int32(lum >> 10)
                }
            }
        }
        return planes
    }

    private func generateCheckerboard(
        entry: RegressionDatasetEntry, count: Int, maxVal: Int
    ) -> [[Int32]] {
        let blockSize = 16
        var planes = [[Int32]](repeating: [Int32](repeating: 0, count: count),
                               count: entry.components)
        for y in 0..<entry.height {
            for x in 0..<entry.width {
                let isWhite = ((x / blockSize) + (y / blockSize)).isMultiple(of: 2)
                let val = Int32(isWhite ? maxVal : 0)
                let idx = y * entry.width + x
                for c in 0..<entry.components {
                    planes[c][idx] = val
                }
            }
        }
        return planes
    }

    private func generateFlat(
        entry: RegressionDatasetEntry, count: Int, maxVal: Int
    ) -> [[Int32]] {
        let mid = Int32(maxVal / 2)
        return [[Int32]](repeating: [Int32](repeating: mid, count: count),
                          count: entry.components)
    }

    private func generateNoise(
        entry: RegressionDatasetEntry, count: Int, maxVal: Int
    ) -> [[Int32]] {
        // Deterministic LCG seeded from dataset id hash
        var seed: UInt64 = 0
        for ch in entry.id.utf8 {
            seed = seed &* 31 &+ UInt64(ch)
        }
        seed = seed | 1  // ensure non-zero

        var planes = [[Int32]](repeating: [Int32](repeating: 0, count: count),
                               count: entry.components)
        for c in 0..<entry.components {
            for i in 0..<count {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                planes[c][i] = Int32((seed >> 33) % UInt64(maxVal + 1))
            }
        }
        return planes
    }
}

// MARK: - Regression Metrics

/// Metrics from a single regression benchmark run.
public struct RegressionMetrics: Sendable, Codable {
    /// Dataset identifier.
    public let datasetID: String

    /// Encoding mode (lossless / lossy).
    public let mode: String

    /// Encode time in seconds.
    public let encodeTime: Double

    /// Decode time in seconds.
    public let decodeTime: Double

    /// Compressed size in bytes.
    public let compressedSize: Int

    /// Compression ratio (original / compressed).
    public let compressionRatio: Double

    /// Per-channel PSNR in dB (infinite for lossless).
    public let psnrPerChannel: [Double]

    /// Overall PSNR in dB.
    public let psnr: Double

    /// Maximum absolute error across all channels.
    public let maxAbsoluteError: Int

    /// Mean absolute error across all channels.
    public let meanAbsoluteError: Double

    /// Timestamp of the measurement.
    public let timestamp: String
}

// MARK: - Baselines & Thresholds

/// Baseline values for a single dataset + mode combination.
public struct RegressionBaseline: Sendable, Codable {
    /// Dataset identifier.
    public let datasetID: String

    /// Encoding mode.
    public let mode: String

    /// Baseline compressed size in bytes.
    public let compressedSize: Int

    /// Baseline PSNR in dB.
    public let psnr: Double

    /// Baseline max absolute error.
    public let maxAbsoluteError: Int

    /// Baseline encode time in seconds (informational — timing thresholds are relative).
    public let encodeTime: Double

    /// Baseline decode time in seconds (informational).
    public let decodeTime: Double
}

/// Threshold configuration for the regression gate.
public struct RegressionThresholds: Sendable, Codable {
    /// Maximum allowed PSNR drop in dB (e.g., 0.5 means fail if PSNR drops by >0.5 dB).
    public let maxPSNRDrop: Double

    /// Maximum allowed compressed size increase as a fraction (e.g., 0.05 = 5%).
    public let maxSizeIncrease: Double

    /// Maximum allowed encode time increase as a fraction (e.g., 0.20 = 20%).
    public let maxEncodeTimeIncrease: Double

    /// Maximum allowed decode time increase as a fraction (e.g., 0.20 = 20%).
    public let maxDecodeTimeIncrease: Double

    /// Lossless mode must have MAE = 0 (exact reconstruction).
    public let requireLosslessExact: Bool

    /// Default thresholds suitable for CI.
    public static let `default` = RegressionThresholds(
        maxPSNRDrop: 0.5,
        maxSizeIncrease: 0.05,
        maxEncodeTimeIncrease: 0.20,
        maxDecodeTimeIncrease: 0.20,
        requireLosslessExact: true
    )
}

// MARK: - Regression Checker

/// Checks current metrics against baselines and reports violations.
public struct RegressionChecker: Sendable {
    /// The thresholds to apply.
    public let thresholds: RegressionThresholds

    public init(thresholds: RegressionThresholds = .default) {
        self.thresholds = thresholds
    }

    /// A single regression violation.
    public struct Violation: Sendable, CustomStringConvertible {
        /// Which dataset caused the violation.
        public let datasetID: String
        /// Encoding mode.
        public let mode: String
        /// Which metric regressed.
        public let metric: String
        /// Baseline value.
        public let baseline: Double
        /// Current value.
        public let current: Double
        /// Threshold that was exceeded.
        public let threshold: Double

        public var description: String {
            let pct = ((current - baseline) / max(abs(baseline), 1e-9)) * 100
            return "REGRESSION [\(datasetID)/\(mode)] \(metric): " +
                   "\(formatted(baseline)) → \(formatted(current)) " +
                   "(\(String(format: "%+.1f%%", pct)), threshold: \(formatted(threshold)))"
        }

        private func formatted(_ v: Double) -> String {
            if v == Double.infinity { return "∞" }
            if abs(v) > 999 { return String(format: "%.0f", v) }
            return String(format: "%.3f", v)
        }
    }

    /// Compares current metrics against a baseline.
    ///
    /// - Parameters:
    ///   - current: The current benchmark metrics.
    ///   - baseline: The baseline to compare against.
    /// - Returns: An array of violations (empty if no regressions).
    public func check(
        current: RegressionMetrics,
        baseline: RegressionBaseline
    ) -> [Violation] {
        var violations: [Violation] = []
        let id = current.datasetID
        let mode = current.mode

        // Quality: PSNR must not drop by more than threshold
        if baseline.psnr.isFinite && current.psnr.isFinite {
            let drop = baseline.psnr - current.psnr
            if drop > thresholds.maxPSNRDrop {
                violations.append(Violation(
                    datasetID: id, mode: mode, metric: "PSNR (dB)",
                    baseline: baseline.psnr, current: current.psnr,
                    threshold: thresholds.maxPSNRDrop
                ))
            }
        }

        // Size: compressed size must not grow by more than threshold
        let sizeGrowth = Double(current.compressedSize - baseline.compressedSize)
                         / max(Double(baseline.compressedSize), 1)
        if sizeGrowth > thresholds.maxSizeIncrease {
            violations.append(Violation(
                datasetID: id, mode: mode, metric: "Compressed size (bytes)",
                baseline: Double(baseline.compressedSize),
                current: Double(current.compressedSize),
                threshold: thresholds.maxSizeIncrease
            ))
        }

        // Lossless exactness
        if thresholds.requireLosslessExact && mode == "lossless" {
            if current.maxAbsoluteError != 0 {
                violations.append(Violation(
                    datasetID: id, mode: mode, metric: "Lossless MAE",
                    baseline: 0, current: Double(current.maxAbsoluteError),
                    threshold: 0
                ))
            }
        }

        // Timing regressions (only flag, don't hard-fail by default in CI
        // because timing varies across machines)
        if baseline.encodeTime > 0 {
            let encGrowth = (current.encodeTime - baseline.encodeTime) / baseline.encodeTime
            if encGrowth > thresholds.maxEncodeTimeIncrease {
                violations.append(Violation(
                    datasetID: id, mode: mode, metric: "Encode time (s)",
                    baseline: baseline.encodeTime, current: current.encodeTime,
                    threshold: thresholds.maxEncodeTimeIncrease
                ))
            }
        }
        if baseline.decodeTime > 0 {
            let decGrowth = (current.decodeTime - baseline.decodeTime) / baseline.decodeTime
            if decGrowth > thresholds.maxDecodeTimeIncrease {
                violations.append(Violation(
                    datasetID: id, mode: mode, metric: "Decode time (s)",
                    baseline: baseline.decodeTime, current: current.decodeTime,
                    threshold: thresholds.maxDecodeTimeIncrease
                ))
            }
        }

        return violations
    }
}

// MARK: - Report Generation

/// Generates JSON and Markdown regression reports.
public struct RegressionReportGenerator: Sendable {

    public init() {}

    /// Generates a JSON report from regression metrics.
    ///
    /// - Parameters:
    ///   - metrics: The measured metrics.
    ///   - violations: Any threshold violations detected.
    ///   - thresholds: The thresholds that were applied.
    /// - Returns: JSON data.
    public func generateJSON(
        metrics: [RegressionMetrics],
        violations: [RegressionChecker.Violation],
        thresholds: RegressionThresholds
    ) throws -> Data {
        let report = JSONReport(
            version: "1.0.0",
            timestamp: iso8601Now(),
            passed: violations.isEmpty,
            totalDatasets: metrics.count,
            violationCount: violations.count,
            thresholds: thresholds,
            metrics: metrics,
            violations: violations.map { v in
                JSONViolation(
                    datasetID: v.datasetID,
                    mode: v.mode,
                    metric: v.metric,
                    baseline: v.baseline,
                    current: v.current,
                    threshold: v.threshold
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    /// Generates a Markdown summary from regression metrics.
    ///
    /// - Parameters:
    ///   - metrics: The measured metrics.
    ///   - violations: Any threshold violations detected.
    ///   - thresholds: The thresholds that were applied.
    /// - Returns: Markdown string.
    public func generateMarkdown(
        metrics: [RegressionMetrics],
        violations: [RegressionChecker.Violation],
        thresholds: RegressionThresholds
    ) -> String {
        var lines: [String] = []
        let passed = violations.isEmpty
        let icon = passed ? "✅" : "❌"

        lines.append("# J2KSwift Regression Report")
        lines.append("")
        lines.append("**Status:** \(icon) \(passed ? "PASSED" : "FAILED")")
        lines.append("**Date:** \(iso8601Now())")
        lines.append("**Datasets:** \(metrics.count)")
        lines.append("**Violations:** \(violations.count)")
        lines.append("")

        // Thresholds
        lines.append("## Thresholds")
        lines.append("")
        lines.append("| Metric | Threshold |")
        lines.append("|--------|-----------|")
        lines.append("| Max PSNR drop | \(String(format: "%.1f", thresholds.maxPSNRDrop)) dB |")
        lines.append("| Max size increase | \(String(format: "%.0f%%", thresholds.maxSizeIncrease * 100)) |")
        lines.append("| Max encode time increase | \(String(format: "%.0f%%", thresholds.maxEncodeTimeIncrease * 100)) |")
        lines.append("| Max decode time increase | \(String(format: "%.0f%%", thresholds.maxDecodeTimeIncrease * 100)) |")
        lines.append("| Lossless exact | \(thresholds.requireLosslessExact ? "Yes" : "No") |")
        lines.append("")

        // Violations
        if !violations.isEmpty {
            lines.append("## Violations")
            lines.append("")
            lines.append("| Dataset | Mode | Metric | Baseline | Current | Threshold |")
            lines.append("|---------|------|--------|----------|---------|-----------|")
            for v in violations {
                lines.append("| \(v.datasetID) | \(v.mode) | \(v.metric) | " +
                    "\(fmtVal(v.baseline)) | \(fmtVal(v.current)) | \(fmtVal(v.threshold)) |")
            }
            lines.append("")
        }

        // Results table
        lines.append("## Results")
        lines.append("")
        lines.append("| Dataset | Mode | Enc (ms) | Dec (ms) | Size (B) | Ratio | PSNR (dB) | MAE |")
        lines.append("|---------|------|----------|----------|----------|-------|-----------|-----|")
        for m in metrics {
            let psnrStr = m.psnr.isInfinite ? "∞" : String(format: "%.2f", m.psnr)
            lines.append("| \(m.datasetID) | \(m.mode) | " +
                "\(String(format: "%.1f", m.encodeTime * 1000)) | " +
                "\(String(format: "%.1f", m.decodeTime * 1000)) | " +
                "\(m.compressedSize) | " +
                "\(String(format: "%.2f", m.compressionRatio)) | " +
                "\(psnrStr) | \(String(format: "%.2f", m.meanAbsoluteError)) |")
        }
        lines.append("")

        // Per-channel PSNR
        let multiChannel = metrics.filter { $0.psnrPerChannel.count > 1 }
        if !multiChannel.isEmpty {
            lines.append("## Per-Channel PSNR")
            lines.append("")
            lines.append("| Dataset | Mode | R (dB) | G (dB) | B (dB) | Spread (dB) |")
            lines.append("|---------|------|--------|--------|--------|-------------|")
            for m in multiChannel {
                let chs = m.psnrPerChannel
                let vals = chs.map { $0.isInfinite ? "∞" : String(format: "%.2f", $0) }
                let finites = chs.filter { $0.isFinite }
                let spread = finites.isEmpty ? 0 :
                    (finites.max()! - finites.min()!)
                let spreadStr = chs.allSatisfy({ $0.isInfinite }) ? "0.00" :
                    String(format: "%.2f", spread)
                let r = vals.count > 0 ? vals[0] : "-"
                let g = vals.count > 1 ? vals[1] : "-"
                let b = vals.count > 2 ? vals[2] : "-"
                lines.append("| \(m.datasetID) | \(m.mode) | \(r) | \(g) | \(b) | \(spreadStr) |")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func iso8601Now() -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]
        return df.string(from: Date())
    }

    private func fmtVal(_ v: Double) -> String {
        if v == Double.infinity { return "∞" }
        if abs(v) >= 10000 { return String(format: "%.0f", v) }
        return String(format: "%.3f", v)
    }
}

// MARK: - JSON Report Codable Types

struct JSONReport: Codable, Sendable {
    let version: String
    let timestamp: String
    let passed: Bool
    let totalDatasets: Int
    let violationCount: Int
    let thresholds: RegressionThresholds
    let metrics: [RegressionMetrics]
    let violations: [JSONViolation]
}

struct JSONViolation: Codable, Sendable {
    let datasetID: String
    let mode: String
    let metric: String
    let baseline: Double
    let current: Double
    let threshold: Double
}

// MARK: - Quality Metrics Helpers

/// Computes quality metrics between original and reconstructed component data.
public struct QualityMetricsCalculator: Sendable {

    public init() {}

    /// Computes PSNR between two component planes.
    ///
    /// - Parameters:
    ///   - original: Original pixel values.
    ///   - reconstructed: Decoded pixel values.
    ///   - bitDepth: Bit depth (used for peak value).
    /// - Returns: PSNR in dB (infinity if MSE = 0).
    public func psnr(
        original: [Int32], reconstructed: [Int32], bitDepth: Int
    ) -> Double {
        let mseVal = mse(original, reconstructed)
        guard mseVal > 0 else { return Double.infinity }
        let peak = Double((1 << bitDepth) - 1)
        return 10.0 * log10((peak * peak) / mseVal)
    }

    /// Mean squared error.
    public func mse(_ a: [Int32], _ b: [Int32]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum: Double = 0
        for i in 0..<a.count {
            let d = Double(a[i]) - Double(b[i])
            sum += d * d
        }
        return sum / Double(a.count)
    }

    /// Maximum absolute error.
    public func maxAbsoluteError(_ a: [Int32], _ b: [Int32]) -> Int {
        guard a.count == b.count else { return 0 }
        var maxErr: Int32 = 0
        for i in 0..<a.count {
            maxErr = max(maxErr, abs(a[i] - b[i]))
        }
        return Int(maxErr)
    }

    /// Mean absolute error.
    public func meanAbsoluteError(_ a: [Int32], _ b: [Int32]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum: Int64 = 0
        for i in 0..<a.count {
            sum += Int64(abs(a[i] - b[i]))
        }
        return Double(sum) / Double(a.count)
    }
}
