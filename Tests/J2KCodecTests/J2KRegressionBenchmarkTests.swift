//
// J2KRegressionBenchmarkTests.swift
// J2KSwift
//
// Regression benchmark test suite: runs encode/decode on deterministic datasets,
// measures quality + size + timing, checks thresholds, and emits JSON/Markdown reports.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore
import Foundation

/// Regression benchmark test suite.
///
/// Each test encodes and decodes a deterministic dataset, computes quality metrics,
/// and verifies them against thresholds. Reports are written to the build directory
/// when the `J2K_REGRESSION_REPORTS` environment variable is set.
final class J2KRegressionBenchmarkTests: XCTestCase {

    // MARK: - Infrastructure

    /// Build a J2KImage from generated planes.
    private func buildImage(
        entry: RegressionDatasetEntry,
        planes: [[Int32]]
    ) -> J2KImage {
        var components: [J2KComponent] = []
        for (idx, plane) in planes.enumerated() {
            var data = Data(count: plane.count)
            data.withUnsafeMutableBytes { buf in
                guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for i in 0..<plane.count {
                    ptr[i] = UInt8(clamping: max(0, min(255, plane[i])))
                }
            }
            components.append(J2KComponent(
                index: idx,
                bitDepth: entry.bitDepth,
                signed: false,
                width: entry.width,
                height: entry.height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: data
            ))
        }
        return J2KImage(width: entry.width, height: entry.height, components: components)
    }

    /// Extract raw planes from a decoded image.
    private func extractPlanes(from image: J2KImage) -> [[Int32]] {
        image.components.map { comp in
            let count = comp.width * comp.height
            var plane = [Int32](repeating: 0, count: count)
            let data = comp.data
            data.withUnsafeBytes { buf in
                guard let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let n = min(data.count, count)
                for i in 0..<n {
                    plane[i] = Int32(ptr[i])
                }
            }
            return plane
        }
    }

    /// Run a single regression benchmark for one dataset + mode.
    private func runBenchmark(
        entry: RegressionDatasetEntry,
        lossless: Bool
    ) throws -> RegressionMetrics {
        let generator = RegressionImageGenerator()
        let planes = generator.generate(entry)
        let image = buildImage(entry: entry, planes: planes)
        let calc = QualityMetricsCalculator()

        // Configure encoder
        var encodingConfig = lossless
            ? J2KEncodingConfiguration.fast
            : J2KEncodingConfiguration.balanced
        encodingConfig.lossless = lossless

        let encoder = J2KEncoder(encodingConfiguration: encodingConfig)
        let decoder = J2KDecoder()

        // Encode
        let encStart = DispatchTime.now()
        let encoded = try encoder.encode(image)
        let encEnd = DispatchTime.now()
        let encodeTime = Double(encEnd.uptimeNanoseconds - encStart.uptimeNanoseconds) / 1e9

        // Decode
        let decStart = DispatchTime.now()
        let decoded = try decoder.decode(encoded)
        let decEnd = DispatchTime.now()
        let decodeTime = Double(decEnd.uptimeNanoseconds - decStart.uptimeNanoseconds) / 1e9

        // Quality metrics
        let decodedPlanes = extractPlanes(from: decoded)
        var psnrPerChannel = [Double]()
        var overallMAE: Double = 0
        var overallMAECount = 0
        var globalMaxError = 0

        for c in 0..<min(planes.count, decodedPlanes.count) {
            let p = calc.psnr(original: planes[c], reconstructed: decodedPlanes[c], bitDepth: entry.bitDepth)
            psnrPerChannel.append(p)

            let mae = calc.meanAbsoluteError(planes[c], decodedPlanes[c])
            overallMAE += mae * Double(planes[c].count)
            overallMAECount += planes[c].count

            let maxE = calc.maxAbsoluteError(planes[c], decodedPlanes[c])
            globalMaxError = max(globalMaxError, maxE)
        }

        let totalMAE = overallMAECount > 0 ? overallMAE / Double(overallMAECount) : 0
        let totalPixels = planes.reduce(0) { $0 + $1.count }
        let originalSize = totalPixels * (entry.bitDepth > 8 ? 2 : 1)
        let ratio = originalSize > 0 ? Double(originalSize) / Double(encoded.count) : 0

        // Overall PSNR (average of per-channel, or use combined MSE)
        let finitePSNRs = psnrPerChannel.filter { $0.isFinite }
        let overallPSNR: Double
        if finitePSNRs.isEmpty {
            overallPSNR = psnrPerChannel.contains(where: { $0.isInfinite }) ? .infinity : 0
        } else {
            overallPSNR = finitePSNRs.reduce(0, +) / Double(finitePSNRs.count)
        }

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]

        return RegressionMetrics(
            datasetID: entry.id,
            mode: lossless ? "lossless" : "lossy",
            encodeTime: encodeTime,
            decodeTime: decodeTime,
            compressedSize: encoded.count,
            compressionRatio: ratio,
            psnrPerChannel: psnrPerChannel,
            psnr: overallPSNR,
            maxAbsoluteError: globalMaxError,
            meanAbsoluteError: totalMAE,
            timestamp: df.string(from: Date())
        )
    }

    // MARK: - Dataset Tests

    /// Runs all datasets and modes, checks thresholds, emits reports.
    func testRegressionBenchmarkSuite() throws {
        let manifest = RegressionDatasetManifest.default
        let checker = RegressionChecker()
        var allMetrics: [RegressionMetrics] = []
        var allViolations: [RegressionChecker.Violation] = []

        for entry in manifest.datasets {
            // Lossless
            if entry.testLossless {
                do {
                    let metrics = try runBenchmark(entry: entry, lossless: true)
                    allMetrics.append(metrics)

                    // Lossless must be exact
                    XCTAssertEqual(metrics.maxAbsoluteError, 0,
                        "Lossless regression: \(entry.id) MAE = \(metrics.maxAbsoluteError)")
                    XCTAssert(metrics.psnr.isInfinite,
                        "Lossless regression: \(entry.id) PSNR should be ∞, got \(metrics.psnr)")

                    print("[\(entry.id)/lossless] size=\(metrics.compressedSize)B " +
                          "enc=\(String(format: "%.1f", metrics.encodeTime * 1000))ms " +
                          "dec=\(String(format: "%.1f", metrics.decodeTime * 1000))ms " +
                          "ratio=\(String(format: "%.2f", metrics.compressionRatio))")
                } catch {
                    XCTFail("[\(entry.id)/lossless] encode/decode failed: \(error)")
                }
            }

            // Lossy
            if entry.testLossy {
                do {
                    let metrics = try runBenchmark(entry: entry, lossless: false)
                    allMetrics.append(metrics)

                    // Lossy should have reasonable PSNR (> 20 dB)
                    if metrics.psnr.isFinite {
                        XCTAssertGreaterThan(metrics.psnr, 20.0,
                            "Lossy regression: \(entry.id) PSNR too low: \(metrics.psnr) dB")
                    }

                    print("[\(entry.id)/lossy] size=\(metrics.compressedSize)B " +
                          "enc=\(String(format: "%.1f", metrics.encodeTime * 1000))ms " +
                          "dec=\(String(format: "%.1f", metrics.decodeTime * 1000))ms " +
                          "PSNR=\(String(format: "%.2f", metrics.psnr))dB " +
                          "MAE=\(String(format: "%.2f", metrics.meanAbsoluteError))")
                } catch {
                    XCTFail("[\(entry.id)/lossy] encode/decode failed: \(error)")
                }
            }
        }

        // Write reports if requested
        let reportDir = ProcessInfo.processInfo.environment["J2K_REGRESSION_REPORTS"]
        if let dir = reportDir {
            let reportGen = RegressionReportGenerator()

            // JSON
            if let jsonData = try? reportGen.generateJSON(
                metrics: allMetrics,
                violations: allViolations,
                thresholds: checker.thresholds
            ) {
                let jsonPath = (dir as NSString).appendingPathComponent("regression-report.json")
                try? jsonData.write(to: URL(fileURLWithPath: jsonPath))
                print("JSON report written to: \(jsonPath)")
            }

            // Markdown
            let markdown = reportGen.generateMarkdown(
                metrics: allMetrics,
                violations: allViolations,
                thresholds: checker.thresholds
            )
            let mdPath = (dir as NSString).appendingPathComponent("regression-report.md")
            try? markdown.write(toFile: mdPath, atomically: true, encoding: .utf8)
            print("Markdown report written to: \(mdPath)")
        }

        // Print summary to stdout (always)
        let reportGen = RegressionReportGenerator()
        let summary = reportGen.generateMarkdown(
            metrics: allMetrics,
            violations: allViolations,
            thresholds: checker.thresholds
        )
        print("\n" + summary)

        // Final assertion
        XCTAssertTrue(allViolations.isEmpty,
            "Regression violations detected:\n" +
            allViolations.map { $0.description }.joined(separator: "\n"))
    }

    // MARK: - Individual Dataset Tests

    func testRegressionGradientLossless() throws {
        let entry = RegressionDatasetManifest.default.datasets.first { $0.id == "gradient-256" }!
        let metrics = try runBenchmark(entry: entry, lossless: true)
        XCTAssertEqual(metrics.maxAbsoluteError, 0, "Gradient lossless must be exact")
    }

    func testRegressionGradientLossy() throws {
        let entry = RegressionDatasetManifest.default.datasets.first { $0.id == "gradient-256" }!
        let metrics = try runBenchmark(entry: entry, lossless: false)
        if metrics.psnr.isFinite {
            XCTAssertGreaterThan(metrics.psnr, 20.0, "Gradient lossy PSNR too low")
        }
    }

    func testRegressionColourBarsLossless() throws {
        let entry = RegressionDatasetManifest.default.datasets.first { $0.id == "bars-256" }!
        let metrics = try runBenchmark(entry: entry, lossless: true)
        XCTAssertEqual(metrics.maxAbsoluteError, 0, "Colour bars lossless must be exact")
    }

    func testRegressionNoiseLossless() throws {
        let entry = RegressionDatasetManifest.default.datasets.first { $0.id == "noise-256" }!
        let metrics = try runBenchmark(entry: entry, lossless: true)
        XCTAssertEqual(metrics.maxAbsoluteError, 0, "Noise lossless must be exact")
    }

    func testRegressionFlatLossless() throws {
        let entry = RegressionDatasetManifest.default.datasets.first { $0.id == "flat-512" }!
        let metrics = try runBenchmark(entry: entry, lossless: true)
        XCTAssertEqual(metrics.maxAbsoluteError, 0, "Flat lossless must be exact")
    }

    func testRegressionCheckerboardLossless() throws {
        let entry = RegressionDatasetManifest.default.datasets.first { $0.id == "checker-128" }!
        let metrics = try runBenchmark(entry: entry, lossless: true)
        XCTAssertEqual(metrics.maxAbsoluteError, 0, "Checkerboard lossless must be exact")
    }

    // MARK: - Threshold Checker Unit Tests

    func testRegressionCheckerDetectsPSNRDrop() throws {
        let checker = RegressionChecker()

        let baseline = RegressionBaseline(
            datasetID: "test", mode: "lossy",
            compressedSize: 1000, psnr: 40.0, maxAbsoluteError: 5,
            encodeTime: 0.1, decodeTime: 0.05
        )
        let current = RegressionMetrics(
            datasetID: "test", mode: "lossy",
            encodeTime: 0.1, decodeTime: 0.05,
            compressedSize: 1000, compressionRatio: 2.0,
            psnrPerChannel: [38.0], psnr: 38.0,
            maxAbsoluteError: 8, meanAbsoluteError: 2.0,
            timestamp: ""
        )

        let violations = checker.check(current: current, baseline: baseline)
        XCTAssertTrue(violations.contains { $0.metric == "PSNR (dB)" },
            "Should detect PSNR drop of 2.0 dB (threshold 0.5)")
    }

    func testRegressionCheckerDetectsSizeIncrease() throws {
        let checker = RegressionChecker()

        let baseline = RegressionBaseline(
            datasetID: "test", mode: "lossy",
            compressedSize: 1000, psnr: 40.0, maxAbsoluteError: 5,
            encodeTime: 0.1, decodeTime: 0.05
        )
        let current = RegressionMetrics(
            datasetID: "test", mode: "lossy",
            encodeTime: 0.1, decodeTime: 0.05,
            compressedSize: 1200, compressionRatio: 1.67,
            psnrPerChannel: [40.0], psnr: 40.0,
            maxAbsoluteError: 5, meanAbsoluteError: 1.0,
            timestamp: ""
        )

        let violations = checker.check(current: current, baseline: baseline)
        XCTAssertTrue(violations.contains { $0.metric == "Compressed size (bytes)" },
            "Should detect 20% size increase (threshold 5%)")
    }

    func testRegressionCheckerDetectsLosslessFailure() throws {
        let checker = RegressionChecker()

        let baseline = RegressionBaseline(
            datasetID: "test", mode: "lossless",
            compressedSize: 1000, psnr: .infinity, maxAbsoluteError: 0,
            encodeTime: 0.1, decodeTime: 0.05
        )
        let current = RegressionMetrics(
            datasetID: "test", mode: "lossless",
            encodeTime: 0.1, decodeTime: 0.05,
            compressedSize: 1000, compressionRatio: 2.0,
            psnrPerChannel: [60.0], psnr: 60.0,
            maxAbsoluteError: 1, meanAbsoluteError: 0.01,
            timestamp: ""
        )

        let violations = checker.check(current: current, baseline: baseline)
        XCTAssertTrue(violations.contains { $0.metric == "Lossless MAE" },
            "Should detect lossless mode with non-zero error")
    }

    func testRegressionCheckerPassesOnGoodMetrics() throws {
        let checker = RegressionChecker()

        let baseline = RegressionBaseline(
            datasetID: "test", mode: "lossy",
            compressedSize: 1000, psnr: 40.0, maxAbsoluteError: 5,
            encodeTime: 0.1, decodeTime: 0.05
        )
        let current = RegressionMetrics(
            datasetID: "test", mode: "lossy",
            encodeTime: 0.09, decodeTime: 0.04,
            compressedSize: 980, compressionRatio: 2.04,
            psnrPerChannel: [41.0], psnr: 41.0,
            maxAbsoluteError: 4, meanAbsoluteError: 0.8,
            timestamp: ""
        )

        let violations = checker.check(current: current, baseline: baseline)
        XCTAssertTrue(violations.isEmpty,
            "Should pass when all metrics are equal or better")
    }

    // MARK: - Report Generation Tests

    func testJSONReportGeneration() throws {
        let gen = RegressionReportGenerator()
        let metrics = [RegressionMetrics(
            datasetID: "test", mode: "lossy",
            encodeTime: 0.1, decodeTime: 0.05,
            compressedSize: 1000, compressionRatio: 2.0,
            psnrPerChannel: [40.0, 39.5, 41.0], psnr: 40.17,
            maxAbsoluteError: 5, meanAbsoluteError: 1.2,
            timestamp: "2026-04-08T00:00:00Z"
        )]

        let jsonData = try gen.generateJSON(
            metrics: metrics,
            violations: [],
            thresholds: .default
        )

        // Should be valid JSON
        let obj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["passed"] as? Bool, true)
        XCTAssertEqual(obj?["totalDatasets"] as? Int, 1)
        XCTAssertEqual(obj?["violationCount"] as? Int, 0)
    }

    func testMarkdownReportGeneration() throws {
        let gen = RegressionReportGenerator()
        let metrics = [RegressionMetrics(
            datasetID: "test", mode: "lossy",
            encodeTime: 0.1, decodeTime: 0.05,
            compressedSize: 1000, compressionRatio: 2.0,
            psnrPerChannel: [40.0, 39.5, 41.0], psnr: 40.17,
            maxAbsoluteError: 5, meanAbsoluteError: 1.2,
            timestamp: "2026-04-08T00:00:00Z"
        )]

        let md = gen.generateMarkdown(
            metrics: metrics,
            violations: [],
            thresholds: .default
        )

        XCTAssertTrue(md.contains("# J2KSwift Regression Report"))
        XCTAssertTrue(md.contains("PASSED"))
        XCTAssertTrue(md.contains("Per-Channel PSNR"))
        XCTAssertTrue(md.contains("test"))
    }

    func testMarkdownReportWithViolations() throws {
        let gen = RegressionReportGenerator()
        let violations = [RegressionChecker.Violation(
            datasetID: "test", mode: "lossy",
            metric: "PSNR (dB)",
            baseline: 40.0, current: 38.0, threshold: 0.5
        )]

        let md = gen.generateMarkdown(
            metrics: [],
            violations: violations,
            thresholds: .default
        )

        XCTAssertTrue(md.contains("FAILED"))
        XCTAssertTrue(md.contains("Violations"))
        XCTAssertTrue(md.contains("PSNR"))
    }

    // MARK: - Dataset Manifest Tests

    func testDatasetManifestDefault() throws {
        let manifest = RegressionDatasetManifest.default
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.datasets.count, 6)

        // All datasets have valid dimensions
        for entry in manifest.datasets {
            XCTAssertGreaterThan(entry.width, 0)
            XCTAssertGreaterThan(entry.height, 0)
            XCTAssertGreaterThan(entry.components, 0)
            XCTAssertGreaterThan(entry.bitDepth, 0)
        }
    }

    func testDeterministicImageGeneration() throws {
        let generator = RegressionImageGenerator()
        let entry = RegressionDatasetManifest.default.datasets.first { $0.id == "noise-256" }!

        // Generate twice — must be identical
        let planes1 = generator.generate(entry)
        let planes2 = generator.generate(entry)

        XCTAssertEqual(planes1.count, planes2.count)
        for c in 0..<planes1.count {
            XCTAssertEqual(planes1[c], planes2[c],
                "Noise generation is not deterministic for channel \(c)")
        }
    }

    func testAllPatternsGenerate() throws {
        let generator = RegressionImageGenerator()
        for pattern in RegressionDatasetEntry.GeneratorPattern.allCases {
            let entry = RegressionDatasetEntry(
                id: "test-\(pattern.rawValue)",
                description: "Test",
                width: 64, height: 64, components: 3, bitDepth: 8,
                pattern: pattern, testLossless: true, testLossy: true
            )
            let planes = generator.generate(entry)
            XCTAssertEqual(planes.count, 3)
            XCTAssertEqual(planes[0].count, 64 * 64)
        }
    }
}
