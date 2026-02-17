// J2KAccelerateBenchmarks.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KAccelerate
import J2KCore

/// Comprehensive benchmarks for hardware-accelerated DWT operations.
///
/// These benchmarks measure performance across different optimization strategies:
/// - Standard (sequential) implementation
/// - SIMD-optimized lifting steps
/// - Parallel processing with Swift Concurrency
/// - Cache-optimized with matrix transpose
///
/// Run with: swift test --filter J2KAccelerateBenchmarks
final class J2KAccelerateBenchmarks: XCTestCase {
    // MARK: - 1D Transform Benchmarks

    func testBenchmark1DTransformSmall() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let size = 256
        let signal = (0..<size).map { Double($0) }

        measure {
            do {
                for _ in 0..<100 {
                    _ = try dwt.forwardTransform97(signal: signal, boundaryExtension: .symmetric)
                }
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmark1DTransformMedium() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let size = 2048
        let signal = (0..<size).map { Double($0) }

        measure {
            do {
                for _ in 0..<10 {
                    _ = try dwt.forwardTransform97(signal: signal, boundaryExtension: .symmetric)
                }
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmark1DTransformLarge() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let size = 16384
        let signal = (0..<size).map { Double($0) }

        measure {
            do {
                _ = try dwt.forwardTransform97(signal: signal, boundaryExtension: .symmetric)
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmark1DRoundTrip() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let size = 1024
        let signal = (0..<size).map { Double($0) }

        measure {
            do {
                for _ in 0..<10 {
                    let (low, high) = try dwt.forwardTransform97(signal: signal, boundaryExtension: .symmetric)
                    _ = try dwt.inverseTransform97(lowpass: low, highpass: high, boundaryExtension: .symmetric)
                }
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - 2D Transform Benchmarks

    func testBenchmark2DTransformSmall() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 128
        let height = 128
        let data = (0..<(width * height)).map { Double($0) }

        measure {
            do {
                for _ in 0..<10 {
                    _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 1)
                }
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmark2DTransformMedium() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 512
        let height = 512
        let data = (0..<(width * height)).map { Double($0 % 256) }

        measure {
            do {
                _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 3)
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmark2DTransformLarge() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 1024
        let height = 1024
        let data = (0..<(width * height)).map { Double($0 % 256) }

        measure {
            do {
                _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 5)
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmark2DRoundTrip() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 256
        let height = 256
        let data = (0..<(width * height)).map { Double($0 % 256) }

        measure {
            do {
                let decompositions = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 3)
                _ = try dwt.inverseTransform2D(decompositions: decompositions, width: width, height: height)
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - Parallel Processing Benchmarks

    func testBenchmarkParallelTransform() async throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 512
        let height = 512
        let data = (0..<(width * height)).map { Double($0 % 256) }

        // Note: XCTest measure blocks don't support async operations well
        // So we measure manually
        let start = Date()
        for _ in 0..<3 {
            _ = try await dwt.forwardTransform2DParallel(
                data: data,
                width: width,
                height: height,
                levels: 3,
                maxConcurrentTasks: 8
            )
        }
        let time = Date().timeIntervalSince(start)
        print("Parallel transform (3 iterations): \(String(format: "%.3f", time))s")
        print("Average: \(String(format: "%.4f", time / 3.0))s")
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmarkParallelVsSequential() async throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 512
        let height = 512
        let data = (0..<(width * height)).map { Double($0 % 256) }

        // Sequential
        let sequentialStart = Date()
        for _ in 0..<3 {
            _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 3)
        }
        let sequentialTime = Date().timeIntervalSince(sequentialStart)

        // Parallel
        let parallelStart = Date()
        for _ in 0..<3 {
            _ = try await dwt.forwardTransform2DParallel(data: data, width: width, height: height, levels: 3)
        }
        let parallelTime = Date().timeIntervalSince(parallelStart)

        let speedup = sequentialTime / parallelTime
        print("Parallel speedup: \(String(format: "%.2f", speedup))x")
        print("Sequential: \(String(format: "%.3f", sequentialTime))s")
        print("Parallel: \(String(format: "%.3f", parallelTime))s")

        // On multi-core systems, parallel should be faster
        // Note: May not show speedup in CI environments with limited cores
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - Cache Optimization Benchmarks

    func testBenchmarkCacheOptimizedTransform() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 512
        let height = 512
        let data = (0..<(width * height)).map { Double($0 % 256) }

        measure {
            do {
                _ = try dwt.forwardTransform2DCacheOptimized(data: data, width: width, height: height, levels: 3)
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmarkCacheOptimizedVsStandard() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 512
        let height = 512
        let data = (0..<(width * height)).map { Double($0 % 256) }

        // Standard
        let standardStart = Date()
        for _ in 0..<5 {
            _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 3)
        }
        let standardTime = Date().timeIntervalSince(standardStart)

        // Cache-optimized
        let optimizedStart = Date()
        for _ in 0..<5 {
            _ = try dwt.forwardTransform2DCacheOptimized(data: data, width: width, height: height, levels: 3)
        }
        let optimizedTime = Date().timeIntervalSince(optimizedStart)

        let speedup = standardTime / optimizedTime
        print("Cache optimization speedup: \(String(format: "%.2f", speedup))x")
        print("Standard: \(String(format: "%.3f", standardTime))s")
        print("Cache-optimized: \(String(format: "%.3f", optimizedTime))s")
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - Multi-level Decomposition Benchmarks

    func testBenchmarkMultiLevelDecomposition() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 1024
        let height = 1024
        let data = (0..<(width * height)).map { Double($0 % 256) }

        for levels in [1, 3, 5, 7] {
            let start = Date()
            _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: levels)
            let time = Date().timeIntervalSince(start)
            print("Levels: \(levels), Time: \(String(format: "%.3f", time))s")
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - Memory Efficiency Benchmarks

    func testBenchmarkMemoryEfficiency() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()

        // Test various sizes to measure memory scaling
        let sizes = [(256, 256), (512, 512), (1024, 1024)]

        for (width, height) in sizes {
            let data = (0..<(width * height)).map { Double($0 % 256) }

            let start = Date()
            _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 5)
            let time = Date().timeIntervalSince(start)

            let megapixels = Double(width * height) / 1_000_000.0
            let timePerMegapixel = time / megapixels

            print("Size: \(width)×\(height), Time: \(String(format: "%.3f", time))s, Time/MP: \(String(format: "%.3f", timePerMegapixel))s")
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - Comparison with Software Implementation

    func testBenchmarkHardwareVsSoftwareSpeedup() throws {
        #if canImport(Accelerate)
        // This test compares hardware-accelerated vs software implementation
        // to measure the actual speedup from hardware acceleration

        let dwt = J2KDWTAccelerated()
        let width = 256
        let height = 256
        let data = (0..<(width * height)).map { Double($0 % 256) }

        // Hardware-accelerated
        let hwStart = Date()
        for _ in 0..<10 {
            _ = try dwt.forwardTransform2D(data: data, width: width, height: height, levels: 3)
        }
        let hwTime = Date().timeIntervalSince(hwStart)

        print("Hardware-accelerated time: \(String(format: "%.3f", hwTime))s")
        print("Average per transform: \(String(format: "%.4f", hwTime / 10.0))s")

        // Note: Would need to import J2KCodec's software implementation to compare
        // For now, just report hardware performance
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - ICT Benchmarks

    func testBenchmarkICTForwardSmall() throws {
        #if canImport(Accelerate)
        let ict = J2KColorTransform()
        let count = 256 * 256
        let red = (0..<count).map { Double($0 % 256) / 255.0 }
        let green = (0..<count).map { Double(($0 + 85) % 256) / 255.0 }
        let blue = (0..<count).map { Double(($0 + 170) % 256) / 255.0 }

        measure {
            do {
                for _ in 0..<10 {
                    _ = try ict.forwardICT(red: red, green: green, blue: blue)
                }
            } catch {
                XCTFail("ICT failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmarkICTForwardLarge() throws {
        #if canImport(Accelerate)
        let ict = J2KColorTransform()
        let count = 1024 * 1024
        let red = (0..<count).map { Double($0 % 256) / 255.0 }
        let green = (0..<count).map { Double(($0 + 85) % 256) / 255.0 }
        let blue = (0..<count).map { Double(($0 + 170) % 256) / 255.0 }

        measure {
            do {
                _ = try ict.forwardICT(red: red, green: green, blue: blue)
            } catch {
                XCTFail("ICT failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testBenchmarkICTRoundTrip() throws {
        #if canImport(Accelerate)
        let ict = J2KColorTransform()
        let count = 512 * 512
        let red = (0..<count).map { Double($0 % 256) / 255.0 }
        let green = (0..<count).map { Double(($0 + 85) % 256) / 255.0 }
        let blue = (0..<count).map { Double(($0 + 170) % 256) / 255.0 }

        measure {
            do {
                for _ in 0..<5 {
                    let (y, cb, cr) = try ict.forwardICT(red: red, green: green, blue: blue)
                    _ = try ict.inverseICT(y: y, cb: cb, cr: cr)
                }
            } catch {
                XCTFail("ICT failed: \(error)")
            }
        }
        #else
        throw XCTSkip("Accelerate framework not available")
        #endif
    }
}
