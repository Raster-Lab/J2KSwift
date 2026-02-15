/// # J2KThreadPool
///
/// Thread pool for parallelizing JPEG 2000 encoding and decoding operations.
///
/// This module provides a configurable thread pool built on Swift concurrency
/// for parallel processing of tiles, code-blocks, and other independent units
/// in the JPEG 2000 pipeline.

import Foundation

/// Configuration for the thread pool.
internal struct J2KThreadPoolConfiguration: Sendable {
    /// Maximum number of concurrent workers.
    internal let maxConcurrency: Int

    /// Creates a new thread pool configuration.
    ///
    /// - Parameter maxConcurrency: Maximum concurrent workers (default: system processor count).
    internal init(maxConcurrency: Int = ProcessInfo.processInfo.processorCount) {
        self.maxConcurrency = max(1, maxConcurrency)
    }
}

/// A thread pool for parallelizing JPEG 2000 pipeline operations.
///
/// `J2KThreadPool` distributes independent work items across multiple
/// concurrent workers using Swift structured concurrency. It is designed
/// for coarse-grained parallelism such as tile-level or component-level
/// processing.
///
/// Example:
/// ```swift
/// let pool = J2KThreadPool()
/// let results = try await pool.parallelMap(tiles) { tile in
///     try processTile(tile)
/// }
/// ```
internal actor J2KThreadPool {
    /// The pool configuration.
    internal let configuration: J2KThreadPoolConfiguration

    /// Number of tasks submitted.
    private var submittedCount: Int = 0

    /// Number of tasks completed.
    private var completedCount: Int = 0

    /// Creates a new thread pool.
    ///
    /// - Parameter configuration: The pool configuration (default: default configuration).
    internal init(configuration: J2KThreadPoolConfiguration = J2KThreadPoolConfiguration()) {
        self.configuration = configuration
    }

    /// Processes items in parallel, returning results in the same order as input.
    ///
    /// The work is distributed across up to `maxConcurrency` concurrent workers.
    /// Results maintain the same ordering as the input array.
    ///
    /// - Parameters:
    ///   - items: The items to process.
    ///   - transform: The transformation to apply to each item.
    /// - Returns: The transformed results in input order.
    /// - Throws: The first error encountered during processing.
    internal func parallelMap<Input: Sendable, Output: Sendable>(
        _ items: [Input],
        transform: @Sendable @escaping (Input) throws -> Output
    ) async throws -> [Output] {
        guard !items.isEmpty else { return [] }
        submittedCount += items.count

        let maxConcurrency = configuration.maxConcurrency

        // For small workloads, process sequentially
        if items.count <= 1 || maxConcurrency <= 1 {
            let results = try items.map(transform)
            completedCount += items.count
            return results
        }

        // Process in parallel using task groups
        let results = try await withThrowingTaskGroup(
            of: (Int, Output).self,
            returning: [Output].self
        ) { group in
            // Limit concurrency by batching submissions
            var nextIndex = 0
            var collectedResults: [(Int, Output)] = []
            collectedResults.reserveCapacity(items.count)

            // Submit initial batch
            let initialBatch = min(maxConcurrency, items.count)
            for index in 0..<initialBatch {
                let item = items[index]
                group.addTask {
                    let result = try transform(item)
                    return (index, result)
                }
            }
            nextIndex = initialBatch

            // Process results and submit more work
            for try await (index, result) in group {
                collectedResults.append((index, result))

                if nextIndex < items.count {
                    let item = items[nextIndex]
                    let capturedIndex = nextIndex
                    group.addTask {
                        let result = try transform(item)
                        return (capturedIndex, result)
                    }
                    nextIndex += 1
                }
            }

            // Sort by original index to maintain order
            collectedResults.sort { $0.0 < $1.0 }
            return collectedResults.map(\.1)
        }

        completedCount += items.count
        return results
    }

    /// Processes items in parallel without returning results.
    ///
    /// - Parameters:
    ///   - items: The items to process.
    ///   - operation: The operation to apply to each item.
    /// - Throws: The first error encountered during processing.
    internal func parallelForEach<Input: Sendable>(
        _ items: [Input],
        operation: @Sendable @escaping (Input) throws -> Void
    ) async throws {
        _ = try await parallelMap(items) { item -> Int in
            try operation(item)
            return 0
        }
    }

    /// Returns statistics about the thread pool.
    internal var statistics: (submitted: Int, completed: Int, maxConcurrency: Int) {
        (submitted: submittedCount, completed: completedCount, maxConcurrency: configuration.maxConcurrency)
    }

    /// Resets the pool statistics.
    internal func resetStatistics() {
        submittedCount = 0
        completedCount = 0
    }
}
