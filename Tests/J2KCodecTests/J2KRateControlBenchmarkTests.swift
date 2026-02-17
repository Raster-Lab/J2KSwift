// J2KRateControlBenchmarkTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

/// Performance benchmarks for rate control and PCRD-opt.
final class J2KRateControlBenchmarkTests: XCTestCase {
    // MARK: - PCRD-opt Algorithm Benchmarks

    func testBenchmarkPCRDOptSmallImage() {
        let codeBlocks = createTestCodeBlocks(count: 100, passesPerBlock: 10)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 256 * 256
            )
        }
    }

    func testBenchmarkPCRDOptMediumImage() {
        let codeBlocks = createTestCodeBlocks(count: 400, passesPerBlock: 15)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 512 * 512
            )
        }
    }

    func testBenchmarkPCRDOptLargeImage() {
        let codeBlocks = createTestCodeBlocks(count: 1600, passesPerBlock: 20)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkPCRDOptVeryLargeImage() {
        let codeBlocks = createTestCodeBlocks(count: 6400, passesPerBlock: 25)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 2048 * 2048
            )
        }
    }

    // MARK: - Layer Count Benchmarks

    func testBenchmarkSingleLayer() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 1)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkThreeLayers() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkFiveLayers() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 5)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkTenLayers() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 10)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    // MARK: - Distortion Estimation Benchmarks

    func testBenchmarkNormBasedEstimation() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            layerCount: 3,
            distortionEstimation: .normBased
        )
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkMSEBasedEstimation() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            layerCount: 3,
            distortionEstimation: .mseBased
        )
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkSimplifiedEstimation() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            layerCount: 3,
            distortionEstimation: .simplified
        )
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    // MARK: - Pass Count Benchmarks

    func testBenchmarkFewPassesPerBlock() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 5)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkManyPassesPerBlock() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 30)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    // MARK: - Mode Benchmarks

    func testBenchmarkTargetBitrateMode() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkConstantQualityMode() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration.constantQuality(0.8, layerCount: 3)
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkLosslessMode() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration.lossless
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    // MARK: - Rate Matching Benchmarks

    func testBenchmarkStrictRateMatching() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            layerCount: 3,
            strictRateMatching: true
        )
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    func testBenchmarkNonStrictRateMatching() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 15)
        let config = RateControlConfiguration(
            mode: .targetBitrate(1.0),
            layerCount: 3,
            strictRateMatching: false
        )
        let rateControl = J2KRateControl(configuration: config)

        measure {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }
    }

    // MARK: - Throughput Benchmarks

    func testBenchmarkThroughputSmallBlocks() {
        let codeBlocks = createTestCodeBlocks(count: 100, passesPerBlock: 10)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 1)
        let rateControl = J2KRateControl(configuration: config)

        let benchmark = J2KBenchmark(name: "RateControl-SmallBlocks")
        let result = benchmark.measure(iterations: 100) {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 256 * 256
            )
        }

        let throughput = 100.0 / result.averageTime
        print("Rate control throughput (small blocks): \(String(format: "%.1f", throughput)) ops/sec")
        XCTAssertGreaterThan(throughput, 10) // Should process at least 10 ops/sec
    }

    func testBenchmarkThroughputLargeBlocks() {
        let codeBlocks = createTestCodeBlocks(count: 1000, passesPerBlock: 20)
        let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 1)
        let rateControl = J2KRateControl(configuration: config)

        let benchmark = J2KBenchmark(name: "RateControl-LargeBlocks")
        let result = benchmark.measure(iterations: 10) {
            _ = try? rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: 1024 * 1024
            )
        }

        let throughput = 10.0 / result.averageTime
        print("Rate control throughput (large blocks): \(String(format: "%.1f", throughput)) ops/sec")
        XCTAssertGreaterThan(throughput, 1) // Should process at least 1 op/sec
    }

    // MARK: - Scalability Benchmarks

    func testScalabilityWithCodeBlockCount() {
        let sizes = [100, 500, 1000, 2000]

        for size in sizes {
            let codeBlocks = createTestCodeBlocks(count: size, passesPerBlock: 15)
            let config = RateControlConfiguration.targetBitrate(1.0, layerCount: 3)
            let rateControl = J2KRateControl(configuration: config)

            let benchmark = J2KBenchmark(name: "RateControl-\(size)Blocks")
            let result = benchmark.measure(iterations: 5) {
                _ = try? rateControl.optimizeLayers(
                    codeBlocks: codeBlocks,
                    totalPixels: 1024 * 1024
                )
            }

            print("Time for \(size) blocks: \(String(format: "%.3f", result.averageTime * 1000)) ms")
        }
    }

    // MARK: - Helper Methods

    /// Creates test code blocks with specified properties.
    private func createTestCodeBlocks(
        count: Int,
        passesPerBlock: Int,
        dataSize: Int = 100
    ) -> [J2KCodeBlock] {
        var blocks = [J2KCodeBlock]()

        for i in 0..<count {
            let data = Data(count: dataSize)

            let block = J2KCodeBlock(
                index: i,
                x: (i % 32) * 64,
                y: (i / 32) * 64,
                width: 64,
                height: 64,
                subband: .ll,
                data: data,
                passeCount: passesPerBlock,
                zeroBitPlanes: 2
            )

            blocks.append(block)
        }

        return blocks
    }
}
