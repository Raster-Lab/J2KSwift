//
// CompareCommandTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCLI

/// Tests for the compare command: PSNR, MSE, MAE, MaxError, bit-exact comparison.
final class CompareCommandTests: XCTestCase {

    // MARK: - Argument parsing

    func testCompareArgumentParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--reference", "original.pgm", "--distorted", "decoded.pgm"])
        XCTAssertEqual(opts["reference"], "original.pgm")
        XCTAssertEqual(opts["distorted"], "decoded.pgm")
    }

    func testCompareWithJSONOutput() {
        let opts = CLIArgumentParserTestHelper.parse(["--reference", "a.pgm", "--distorted", "b.pgm", "--json"])
        XCTAssertEqual(opts["json"], "true")
    }

    func testCompareMetricFlag() {
        let opts = CLIArgumentParserTestHelper.parse(["--metric", "psnr", "--reference", "a.pgm", "--distorted", "b.pgm"])
        XCTAssertEqual(opts["metric"], "psnr")
    }

    // MARK: - Metric computation unit tests

    func testMSEComputation() {
        // Identical images should have MSE = 0
        let ref: [UInt8] = [10, 20, 30, 40, 50]
        let dist: [UInt8] = [10, 20, 30, 40, 50]
        let mse = computeMSE(ref, dist)
        XCTAssertEqual(mse, 0.0, accuracy: 1e-10)
    }

    func testMSEComputationDifferent() {
        let ref: [UInt8] = [10, 20, 30, 40, 50]
        let dist: [UInt8] = [11, 21, 31, 41, 51]
        let mse = computeMSE(ref, dist)
        // Each sample differs by 1, so MSE = 1.0
        XCTAssertEqual(mse, 1.0, accuracy: 1e-10)
    }

    func testPSNRInfiniteForIdentical() {
        let mse = 0.0
        let psnr = mse == 0.0 ? Double.infinity : 10.0 * log10(255.0 * 255.0 / mse)
        XCTAssertTrue(psnr.isInfinite)
    }

    func testPSNRComputation() {
        let mse = 1.0
        let psnr = 10.0 * log10(255.0 * 255.0 / mse)
        // PSNR for MSE=1 with 8-bit: 10*log10(65025) ≈ 48.13
        XCTAssertEqual(psnr, 48.13, accuracy: 0.01)
    }

    func testMAEComputation() {
        let ref: [UInt8] = [10, 20, 30, 40, 50]
        let dist: [UInt8] = [12, 22, 32, 42, 52]
        let mae = computeMAE(ref, dist)
        XCTAssertEqual(mae, 2.0, accuracy: 1e-10)
    }

    func testMaxErrorComputation() {
        let ref: [UInt8] = [10, 20, 30, 40, 50]
        let dist: [UInt8] = [10, 25, 30, 40, 50]
        let maxErr = computeMaxError(ref, dist)
        XCTAssertEqual(maxErr, 5)
    }

    func testBitExactComparison() {
        let ref: [UInt8] = [10, 20, 30, 40, 50]
        let dist: [UInt8] = [10, 20, 30, 40, 50]
        XCTAssertTrue(ref == dist)
    }

    func testBitExactComparisonFails() {
        let ref: [UInt8] = [10, 20, 30, 40, 50]
        let dist: [UInt8] = [10, 20, 31, 40, 50]
        XCTAssertFalse(ref == dist)
    }

    func testCompareJSONHandlesInfinitePSNR() throws {
        let data = Data([10, 20, 30, 40])

        let original = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 2,
            height: 2,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        let reconstructed = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 2,
            height: 2,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )

        let metrics = J2KCLI.computeComponentMetrics(original: original, reconstructed: reconstructed)
        XCTAssertTrue(metrics.psnr.isInfinite)

        let payload: [String: Any] = [
            "overall": [
                "psnr": J2KCLI.jsonCompatibleMetricValue(metrics.psnr),
                "mse": metrics.mse,
                "mae": metrics.mae,
                "maxError": metrics.maxError,
                "bitExact": metrics.bitExact
            ]
        ]

        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: payload, options: []))
    }

    func testComputeComponentMetricsHandlesSlicedData() {
        let backing = Data([255, 254, 10, 20, 30, 40, 50])
        let sliced = backing[2..<7]

        let original = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 5,
            height: 1,
            subsamplingX: 1,
            subsamplingY: 1,
            data: sliced
        )
        let reconstructed = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 5,
            height: 1,
            subsamplingX: 1,
            subsamplingY: 1,
            data: sliced
        )

        let metrics = J2KCLI.computeComponentMetrics(original: original, reconstructed: reconstructed)
        XCTAssertTrue(metrics.bitExact)
        XCTAssertEqual(metrics.mse, 0, accuracy: 1e-12)
        XCTAssertEqual(metrics.mae, 0, accuracy: 1e-12)
        XCTAssertEqual(metrics.maxError, 0)
        XCTAssertTrue(metrics.psnr.isInfinite)
    }

    // MARK: - Helpers

    private func computeMSE(_ ref: [UInt8], _ dist: [UInt8]) -> Double {
        precondition(ref.count == dist.count)
        var sum = 0.0
        for i in 0..<ref.count {
            let diff = Double(ref[i]) - Double(dist[i])
            sum += diff * diff
        }
        return sum / Double(ref.count)
    }

    private func computeMAE(_ ref: [UInt8], _ dist: [UInt8]) -> Double {
        precondition(ref.count == dist.count)
        var sum = 0.0
        for i in 0..<ref.count {
            sum += abs(Double(ref[i]) - Double(dist[i]))
        }
        return sum / Double(ref.count)
    }

    private func computeMaxError(_ ref: [UInt8], _ dist: [UInt8]) -> Int {
        precondition(ref.count == dist.count)
        var maxErr = 0
        for i in 0..<ref.count {
            let err = abs(Int(ref[i]) - Int(dist[i]))
            maxErr = max(maxErr, err)
        }
        return maxErr
    }
}
