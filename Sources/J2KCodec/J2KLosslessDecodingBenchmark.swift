// J2KLosslessDecodingBenchmark.swift
// J2KSwift
//
// Benchmark comparing standard vs optimized lossless decoding
//

import Foundation
import J2KCore
@testable import J2KCodec

/// Comprehensive benchmarks for lossless decoding optimization.
///
/// Compares performance between standard and optimized implementations
/// across various image sizes and decomposition levels.
public struct J2KLosslessDecodingBenchmark {
    /// Runs all benchmarks and returns a summary report.
    public static func runAll() throws -> String {
        var report = "# Lossless Decoding Optimization Benchmark Results\n\n"
        report += "Date: \(Date())\n\n"
        report += "## Test Configuration\n"
        report += "- Platform: Swift 6\n"
        report += "- Filter: Reversible 5/3\n"
        report += "- Boundary Extension: Symmetric\n\n"

        // 1D Transform Benchmarks
        report += "## 1D Inverse Transform\n\n"
        report += try benchmark1DTransforms()
        report += "\n"

        // 2D Transform Benchmarks
        report += "## 2D Inverse Transform\n\n"
        report += try benchmark2DTransforms()
        report += "\n"

        // Multi-level Benchmarks
        report += "## Multi-level Decomposition\n\n"
        report += try benchmarkMultiLevel()
        report += "\n"

        return report
    }

    // MARK: - 1D Transform Benchmarks

    private static func benchmark1DTransforms() throws -> String {
        var report = "| Size | Standard (ms) | Optimized (ms) | Speedup |\n"
        report += "|------|---------------|----------------|----------|\n"

        let sizes = [64, 128, 256, 512, 1024, 2048]

        for size in sizes {
            let lowpass: [Int32] = (0..<size).map { Int32($0) }
            let highpass: [Int32] = (0..<(size - 1)).map { Int32($0 + 100) }

            // Standard implementation
            let standardBenchmark = J2KBenchmark(name: "Standard-1D-\(size)")
            let standardResult = try standardBenchmark.measureThrowing(iterations: 100) {
                _ = try J2KDWT1D.inverseTransform(
                    lowpass: lowpass,
                    highpass: highpass,
                    filter: .reversible53,
                    boundaryExtension: .symmetric
                )
            }

            // Optimized implementation
            let optimizer = J2KDWT1DOptimizer()
            let optimizedBenchmark = J2KBenchmark(name: "Optimized-1D-\(size)")
            let optimizedResult = try optimizedBenchmark.measureThrowing(iterations: 100) {
                _ = try optimizer.inverseTransform53Optimized(
                    lowpass: lowpass,
                    highpass: highpass,
                    boundaryExtension: .symmetric
                )
            }

            let speedup = standardResult.averageTime / optimizedResult.averageTime
            report += String(format: "| %4d | %13.3f | %14.3f | %7.2fx |\n",
                           size,
                           standardResult.averageTime * 1000,
                           optimizedResult.averageTime * 1000,
                           speedup)
        }

        return report
    }

    // MARK: - 2D Transform Benchmarks

    private static func benchmark2DTransforms() throws -> String {
        var report = "| Size | Standard (ms) | Optimized (ms) | Speedup |\n"
        report += "|------|---------------|----------------|----------|\n"

        let sizes = [(16, 16), (32, 32), (64, 64), (128, 128), (256, 256)]

        for (width, height) in sizes {
            let llSize = ((width + 1) / 2, (height + 1) / 2)

            // Create test subbands
            let ll = (0..<llSize.1).map { row in
                (0..<llSize.0).map { col in Int32(row * llSize.0 + col) }
            }
            let lh = ll
            let hl = ll
            let hh = ll

            // Standard implementation
            let standardBenchmark = J2KBenchmark(name: "Standard-2D-\(width)x\(height)")
            let standardResult = try standardBenchmark.measureThrowing(iterations: 50) {
                _ = try J2KDWT2D.inverseTransform(
                    ll: ll,
                    lh: lh,
                    hl: hl,
                    hh: hh,
                    filter: .reversible53,
                    boundaryExtension: .symmetric
                )
            }

            // Optimized implementation
            let optimizer = J2KDWT2DOptimizer()
            let optimizedBenchmark = J2KBenchmark(name: "Optimized-2D-\(width)x\(height)")
            let optimizedResult = try optimizedBenchmark.measureThrowing(iterations: 50) {
                _ = try optimizer.inverseTransform2DOptimized(
                    ll: ll,
                    lh: lh,
                    hl: hl,
                    hh: hh,
                    boundaryExtension: .symmetric
                )
            }

            let speedup = standardResult.averageTime / optimizedResult.averageTime
            report += String(format: "| %4dx%-3d | %13.3f | %14.3f | %7.2fx |\n",
                           width, height,
                           standardResult.averageTime * 1000,
                           optimizedResult.averageTime * 1000,
                           speedup)
        }

        return report
    }

    // MARK: - Multi-level Benchmarks

    private static func benchmarkMultiLevel() throws -> String {
        var report = "Testing multi-level decomposition reconstruction:\n\n"
        report += "| Levels | Size | Standard (ms) | Optimized (ms) | Speedup |\n"
        report += "|--------|------|---------------|----------------|----------|\n"

        let baseSize = 128
        let levels = [1, 2, 3, 4, 5]

        for numLevels in levels {
            // Create multi-level decomposition
            var currentSize = baseSize
            var decompositions: [(ll: [[Int32]], lh: [[Int32]], hl: [[Int32]], hh: [[Int32]])] = []

            for _ in 0..<numLevels {
                let subbandSize = ((currentSize + 1) / 2, (currentSize + 1) / 2)
                let ll = (0..<subbandSize.1).map { row in
                    (0..<subbandSize.0).map { col in Int32(row * subbandSize.0 + col) }
                }
                decompositions.append((ll: ll, lh: ll, hl: ll, hh: ll))
                currentSize = subbandSize.0
            }

            // Benchmark reconstruction from finest level
            let firstLevel = decompositions[0]

            // Standard implementation
            let standardBenchmark = J2KBenchmark(name: "Standard-ML\(numLevels)")
            let standardResult = try standardBenchmark.measureThrowing(iterations: 20) {
                _ = try J2KDWT2D.inverseTransform(
                    ll: firstLevel.ll,
                    lh: firstLevel.lh,
                    hl: firstLevel.hl,
                    hh: firstLevel.hh,
                    filter: .reversible53,
                    boundaryExtension: .symmetric
                )
            }

            // Optimized implementation
            let optimizer = J2KDWT2DOptimizer()
            let optimizedBenchmark = J2KBenchmark(name: "Optimized-ML\(numLevels)")
            let optimizedResult = try optimizedBenchmark.measureThrowing(iterations: 20) {
                _ = try optimizer.inverseTransform2DOptimized(
                    ll: firstLevel.ll,
                    lh: firstLevel.lh,
                    hl: firstLevel.hl,
                    hh: firstLevel.hh,
                    boundaryExtension: .symmetric
                )
            }

            let speedup = standardResult.averageTime / optimizedResult.averageTime
            let reconstructedSize = baseSize / (1 << (numLevels - 1))

            report += String(format: "| %6d | %4d | %13.3f | %14.3f | %7.2fx |\n",
                           numLevels,
                           reconstructedSize,
                           standardResult.averageTime * 1000,
                           optimizedResult.averageTime * 1000,
                           speedup)
        }

        return report
    }

    // MARK: - Summary Statistics

    public static func printSummary() throws {
        print(try runAll())
    }
}
