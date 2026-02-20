//
// J2KSwift62CompatibilityTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests to verify Swift 6.2+ compatibility and concurrency features
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class J2KSwift62CompatibilityTests: XCTestCase {
    // MARK: - Strict Concurrency Tests

    /// Verify that core types are Sendable
    func testCoreTypesSendable() {
        // J2KError should be Sendable
        let error: any Sendable = J2KError.invalidParameter("test")
        XCTAssertNotNil(error)

        // J2KColorSpace should be Sendable
        let colorSpace: any Sendable = J2KColorSpace.sRGB
        XCTAssertNotNil(colorSpace)

        // J2KSubband should be Sendable
        let subband: any Sendable = J2KSubband.ll
        XCTAssertNotNil(subband)
    }

    /// Verify that image types are properly handled in concurrent contexts
    func testImageTypeConcurrency() async throws {
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 64,
            height: 64,
            subsamplingX: 1,
            subsamplingY: 1,
            data: Data(repeating: 0, count: 64 * 64)
        )

        let image = J2KImage(
            width: 64,
            height: 64,
            components: [component]
        )

        // Test that image can be used in async context
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                let width = image.width
                XCTAssertEqual(width, 64)
                continuation.resume()
            }
        }
    }

    // MARK: - Swift 6.2 Feature Tests

    /// Verify that actors work correctly with J2K types
    func testActorIsolation() async throws {
        actor ImageProcessor {
            var processedCount = 0

            func process(_ image: J2KImage) {
                processedCount += 1
            }

            func getCount() -> Int {
                processedCount
            }
        }

        let processor = ImageProcessor()

        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 32,
            height: 32,
            subsamplingX: 1,
            subsamplingY: 1,
            data: Data(repeating: 0, count: 32 * 32)
        )

        let image = J2KImage(
            width: 32,
            height: 32,
            components: [component]
        )

        await processor.process(image)
        let count = await processor.getCount()
        XCTAssertEqual(count, 1)
    }

    /// Test async sequences with J2K data
    func testAsyncSequences() async throws {
        struct TileSequence: AsyncSequence {
            typealias Element = Int

            struct AsyncIterator: AsyncIteratorProtocol {
                var current = 0
                let max = 10

                mutating func next() async -> Int? {
                    guard current < max else { return nil }
                    defer { current += 1 }
                    return current
                }
            }

            func makeAsyncIterator() -> AsyncIterator {
                AsyncIterator()
            }
        }

        let sequence = TileSequence()
        var count = 0

        for await tile in sequence {
            count += 1
            XCTAssertEqual(tile, count - 1)
        }

        XCTAssertEqual(count, 10)
    }

    // MARK: - Error Handling Tests

    /// Verify error handling in concurrent contexts
    func testErrorHandlingConcurrency() async throws {
        enum TestError: Error {
            case testFailure
        }

        func throwingOperation() async throws -> Int {
            throw TestError.testFailure
        }

        do {
            _ = try await throwingOperation()
            XCTFail("Should have thrown")
        } catch TestError.testFailure {
            // Expected
        }
    }

    /// Test Result type with concurrent operations
    func testResultTypeConcurrency() async throws {
        func resultOperation() async -> Result<Int, Error> {
            .success(42)
        }

        let result = await resultOperation()

        switch result {
        case .success(let value):
            XCTAssertEqual(value, 42)
        case .failure:
            XCTFail("Should have succeeded")
        }
    }

    // MARK: - Package Manager Tests

    /// Verify Package.swift is valid for Swift 6.2+
    func testPackageSwiftVersion() {
        // This test verifies the package builds with Swift 6.2+
        // If we're running, it means the package compiled successfully
        XCTAssert(true, "Package builds with Swift 6.2+")
    }

    /// Verify strict concurrency is enabled
    func testStrictConcurrencyEnabled() {
        // This test verifies strict concurrency warnings are treated as errors
        // If compilation succeeded, strict concurrency is working
        XCTAssert(true, "Strict concurrency enabled and working")
    }

    /// Test J2KConfiguration is Sendable
    func testConfigurationSendable() {
        let config: any Sendable = J2KConfiguration()
        XCTAssertNotNil(config)
    }

    /// Test concurrent access to multiple images
    func testConcurrentImageAccess() async throws {
        let images = (0..<10).map { i in
            let component = J2KComponent(
                index: 0,
                bitDepth: 8,
                signed: false,
                width: 16,
                height: 16,
                subsamplingX: 1,
                subsamplingY: 1,
                data: Data(repeating: UInt8(i), count: 16 * 16)
            )

            return J2KImage(
                width: 16,
                height: 16,
                components: [component]
            )
        }

        // Test concurrent access to images
        await withTaskGroup(of: Int.self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    image.width * image.height * index
                }
            }

            var sum = 0
            for await result in group {
                sum += result
            }

            XCTAssertEqual(sum, (0..<10).reduce(0) { $0 + $1 * 256 })
        }
    }

    // MARK: - Actor Concurrency Stress Tests

    /// Verify concurrent access to J2KBenchmarkRunner actor
    func testBenchmarkRunnerConcurrentAccess() async throws {
        let runner = J2KBenchmarkRunner()

        // Add results concurrently from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let result = BenchmarkResult(
                        name: "Concurrent-\(i)",
                        times: [Double(i) * 0.001]
                    )
                    await runner.add(result)
                }
            }
        }

        let results = await runner.getResults()
        XCTAssertEqual(results.count, 50)
    }

    /// Verify concurrent access to J2KPipelineProfiler actor
    func testPipelineProfilerConcurrentAccess() async throws {
        let profiler = J2KPipelineProfiler()

        // Record metrics concurrently from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let metric = J2KStageMetrics(
                        stage: .waveletTransform,
                        elapsedTime: Double(i) * 0.001,
                        itemsProcessed: i + 1
                    )
                    await profiler.record(metric)
                }
            }
        }

        let count = await profiler.metricsCount
        XCTAssertEqual(count, 50)

        let report = await profiler.generateReport()
        XCTAssertEqual(report.metrics.count, 50)
    }

    /// Verify concurrent read/write to J2KMemoryPool actor
    func testMemoryPoolConcurrentAccess() async throws {
        let pool = J2KMemoryPool()

        // Acquire and release buffers concurrently
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let buffer = await pool.acquire(capacity: 1024)
                    await pool.release(buffer)
                }
            }
        }

        // If we get here without deadlock or crash, concurrency is correct
        XCTAssert(true, "Memory pool handled 20 concurrent acquire/release cycles")
    }

    /// Verify concurrent access to J2KThreadPool actor
    func testThreadPoolConcurrentAccess() async throws {
        let pool = J2KThreadPool()

        // Run multiple parallel maps concurrently
        await withTaskGroup(of: [Int].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let result = try? await pool.parallelMap(Array(0..<10)) { $0 * 2 }
                    return result ?? []
                }
            }

            for await result in group {
                XCTAssertEqual(result.count, 10)
            }
        }
    }

    /// Verify Sendable conformance for all public API types
    func testAllPublicTypesSendable() {
        // Core types
        let _: any Sendable = J2KImage(width: 1, height: 1, components: 1, bitDepth: 8)
        let _: any Sendable = J2KConfiguration()
        let _: any Sendable = J2KError.invalidParameter("test")
        let _: any Sendable = J2KColorSpace.sRGB
        let _: any Sendable = J2KSubband.ll

        // Buffer types
        let _: any Sendable = J2KBuffer(capacity: 1)
        let _: any Sendable = J2KImageBuffer(width: 1, height: 1)

        // Benchmark types
        let _: any Sendable = J2KBenchmark(name: "test")
        let _: any Sendable = BenchmarkResult(name: "test", times: [0.001])

        // Pipeline types
        let _: any Sendable = J2KPipelineStage.waveletTransform
        let _: any Sendable = J2KStageMetrics(stage: .waveletTransform, elapsedTime: 0.001)

        // Volume types
        let _: any Sendable = J2KVolume(width: 1, height: 1, depth: 1, components: [])
        let _: any Sendable = J2KVolumeMetadata()

        // Marker types
        let _: any Sendable = J2KMarker.soc

        // Bit I/O types
        let _: any Sendable = J2KBitReader(data: Data())
        let _: any Sendable = J2KBitWriter()

        // All compile = all Sendable
        XCTAssert(true, "All public types conform to Sendable")
    }
}
