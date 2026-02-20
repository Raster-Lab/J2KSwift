//
// J2KModuleConcurrencyTests.swift
// J2KSwift
//
// Concurrency stress tests for Week 238-239 module-by-module migration.
// Verifies that types across all modules are concurrent-safe under
// Swift 6.2 strict concurrency.
//

import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class J2KModuleConcurrencyTests: XCTestCase {

    // MARK: - ParallelResultCollector (Mutex-based) Tests

    /// Verify concurrent append to ParallelResultCollector.
    func testParallelResultCollectorConcurrentAppend() {
        let collector = ParallelResultCollector<Int>(capacity: 100)
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            collector.append(contentsOf: [index])
        }

        let results = collector.results
        XCTAssertEqual(results.count, iterations)
        // All values 0..<100 should be present (order may vary)
        XCTAssertEqual(Set(results).count, iterations)
    }

    /// Verify concurrent error recording.
    func testParallelResultCollectorConcurrentErrors() {
        let collector = ParallelResultCollector<Int>(capacity: 10)

        DispatchQueue.concurrentPerform(iterations: 50) { index in
            collector.recordError(J2KError.invalidParameter("Error \(index)"))
        }

        // Only the first error should be recorded
        XCTAssertNotNil(collector.firstError)
    }

    /// Verify Sendable conformance of ParallelResultCollector.
    func testParallelResultCollectorSendable() {
        let collector: any Sendable = ParallelResultCollector<Int>(capacity: 0)
        XCTAssertNotNil(collector)
    }

    /// Verify mixed concurrent reads and writes.
    func testParallelResultCollectorConcurrentReadWrite() {
        let collector = ParallelResultCollector<(Int, Int)>(capacity: 50)

        DispatchQueue.concurrentPerform(iterations: 50) { index in
            if index % 2 == 0 {
                collector.append(contentsOf: [(index, index * 2)])
            } else {
                _ = collector.results
                _ = collector.firstError
            }
        }

        // 25 even indices should have appended
        XCTAssertEqual(collector.results.count, 25)
    }

    // MARK: - J2KIncrementalDecoder (Mutex-based) Tests

    /// Verify concurrent append to J2KIncrementalDecoder.
    func testIncrementalDecoderConcurrentAppend() {
        let decoder = J2KIncrementalDecoder()
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let data = Data([UInt8(index % 256)])
            decoder.append(data)
        }

        XCTAssertEqual(decoder.bufferSize(), iterations)
    }

    /// Verify concurrent read/write access.
    func testIncrementalDecoderConcurrentReadWrite() {
        let decoder = J2KIncrementalDecoder()

        DispatchQueue.concurrentPerform(iterations: 50) { index in
            if index % 3 == 0 {
                decoder.append(Data([UInt8(index % 256)]))
            } else if index % 3 == 1 {
                _ = decoder.bufferSize()
            } else {
                _ = decoder.canDecode()
            }
        }

        // Should not crash or deadlock
        XCTAssertGreaterThanOrEqual(decoder.bufferSize(), 0)
    }

    /// Verify Sendable conformance of J2KIncrementalDecoder.
    func testIncrementalDecoderSendable() {
        let decoder: any Sendable = J2KIncrementalDecoder()
        XCTAssertNotNil(decoder)
    }

    /// Verify concurrent reset and append operations.
    func testIncrementalDecoderConcurrentResetAppend() {
        let decoder = J2KIncrementalDecoder()

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index % 10 == 0 {
                decoder.reset()
            } else {
                decoder.append(Data([UInt8(index % 256)]))
            }
        }

        // Should not crash or deadlock
        _ = decoder.bufferSize()
        _ = decoder.isComplete()
        XCTAssert(true, "Concurrent reset/append handled safely")
    }

    // MARK: - J2KCodec Module Sendable Tests

    /// Verify that encoder pipeline types are Sendable.
    func testEncoderPipelineTypesSendable() {
        let _: any Sendable = EncodingStage.preprocessing
        let _: any Sendable = EncoderProgressUpdate(
            stage: .waveletTransform,
            progress: 0.5,
            overallProgress: 0.3
        )
        XCTAssert(true, "Encoder pipeline types are Sendable")
    }

    /// Verify J2KTranscoder types are Sendable.
    func testTranscoderTypesSendable() {
        let _: any Sendable = TranscodingDirection.legacyToHT
        let _: any Sendable = TranscodingStage.parsing
        let _: any Sendable = HTCodingMode.ht
        XCTAssert(true, "Transcoder types are Sendable")
    }

    // MARK: - Cross-Module Concurrent Access

    /// Verify that codec types can be safely shared across tasks.
    func testCodecTypesInTaskGroup() async throws {
        let decoder = J2KIncrementalDecoder()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    decoder.append(Data([UInt8(i)]))
                }
            }
        }

        XCTAssertEqual(decoder.bufferSize(), 20)
    }

    /// Verify ParallelResultCollector works correctly in TaskGroup.
    func testParallelResultCollectorInTaskGroup() async throws {
        let collector = ParallelResultCollector<String>(capacity: 20)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    collector.append(contentsOf: ["Task-\(i)"])
                }
            }
        }

        XCTAssertEqual(collector.results.count, 20)
        XCTAssertNil(collector.firstError)
    }
}
