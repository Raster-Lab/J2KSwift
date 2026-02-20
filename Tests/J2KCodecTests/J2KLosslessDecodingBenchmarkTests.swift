//
// J2KLosslessDecodingBenchmarkTests.swift
// J2KSwift
//
// J2KLosslessDecodingBenchmarkTests.swift
// J2KSwift
//
// Test runner for lossless decoding benchmarks
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KLosslessDecodingBenchmarkTests: XCTestCase {
    override class var defaultTestSuite: XCTestSuite { XCTestSuite(name: "J2KLosslessDecodingBenchmarkTests (Disabled)") }

    /// Runs the full benchmark suite and prints results.
    func testRunBenchmarkSuite() throws {
        // This test runs the benchmark and prints results to console
        // It's marked as a test so it can be run easily, but it's really a benchmark runner

        let report = try J2KLosslessDecodingBenchmark.runAll()
        print("\n" + report + "\n")

        // The test always passes - it's just for running benchmarks
        XCTAssertTrue(true)
    }

    /// Quick smoke test to verify benchmarks can run.
    func testBenchmarkSmoke() throws {
        // Just verify the benchmark infrastructure works
        let optimizer = J2KDWT1DOptimizer()
        let lowpass: [Int32] = [10, 20, 30, 40]
        let highpass: [Int32] = [5, 15, 25]

        let benchmark = J2KBenchmark(name: "Smoke Test")
        let result = try benchmark.measureThrowing(iterations: 10) {
            _ = try optimizer.inverseTransform53Optimized(
                lowpass: lowpass,
                highpass: highpass,
                boundaryExtension: .symmetric
            )
        }

        // Should complete successfully
        XCTAssertGreaterThan(result.times.count, 0)
        XCTAssertGreaterThan(result.averageTime, 0)
    }
}
