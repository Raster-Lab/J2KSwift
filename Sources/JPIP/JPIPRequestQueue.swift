/// # JPIPRequestQueue
///
/// Priority-based request queue for JPIP server.

import Foundation
import J2KCore

/// A priority queue for managing JPIP requests.
///
/// Requests are queued with priorities and dequeued in priority order
/// (higher priority first). This allows the server to handle critical
/// requests (like session creation) before less critical ones.
public actor JPIPRequestQueue {
    /// A queued request with its priority.
    private struct QueuedRequest: Sendable {
        let request: JPIPRequest
        let priority: Int
        let timestamp: Date

        init(request: JPIPRequest, priority: Int) {
            self.request = request
            self.priority = priority
            self.timestamp = Date()
        }
    }

    /// The queue of pending requests.
    private var queue: [QueuedRequest]

    /// Maximum queue size.
    private let maxSize: Int

    /// Queue statistics.
    private var stats: Statistics

    /// Queue statistics.
    public struct Statistics: Sendable {
        /// Total requests enqueued.
        public var totalEnqueued: Int

        /// Total requests dequeued.
        public var totalDequeued: Int

        /// Total requests dropped (queue full).
        public var totalDropped: Int

        /// Current queue size.
        public var currentSize: Int

        /// Maximum size reached.
        public var maxSizeReached: Int

        /// Creates empty statistics.
        public init() {
            self.totalEnqueued = 0
            self.totalDequeued = 0
            self.totalDropped = 0
            self.currentSize = 0
            self.maxSizeReached = 0
        }
    }

    /// Creates a new request queue.
    ///
    /// - Parameter maxSize: Maximum number of queued requests (default: 1000).
    public init(maxSize: Int = 1000) {
        self.maxSize = maxSize
        self.queue = []
        self.stats = Statistics()

        // Pre-allocate capacity for better performance
        self.queue.reserveCapacity(min(maxSize, 100))
    }

    /// Enqueues a request with a given priority.
    ///
    /// - Parameters:
    ///   - request: The request to enqueue.
    ///   - priority: Priority value (higher = more urgent).
    /// - Throws: ``J2KError`` if the queue is full.
    public func enqueue(_ request: JPIPRequest, priority: Int) throws {
        guard queue.count < maxSize else {
            stats.totalDropped += 1
            throw J2KError.queueFull("Request queue is full (max: \(maxSize))")
        }

        let queuedRequest = QueuedRequest(request: request, priority: priority)
        queue.append(queuedRequest)

        // Sort by priority (descending) and timestamp (ascending for same priority)
        queue.sort { a, b in
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            return a.timestamp < b.timestamp
        }

        stats.totalEnqueued += 1
        stats.currentSize = queue.count
        stats.maxSizeReached = max(stats.maxSizeReached, queue.count)
    }

    /// Dequeues the highest priority request.
    ///
    /// - Returns: The highest priority request, or nil if queue is empty.
    public func dequeue() -> JPIPRequest? {
        guard !queue.isEmpty else {
            return nil
        }

        let queuedRequest = queue.removeFirst()
        stats.totalDequeued += 1
        stats.currentSize = queue.count

        return queuedRequest.request
    }

    /// Gets the current size of the queue.
    public var size: Int {
        queue.count
    }

    /// Checks if the queue is empty.
    public var isEmpty: Bool {
        queue.isEmpty
    }

    /// Checks if the queue is full.
    public var isFull: Bool {
        queue.count >= maxSize
    }

    /// Clears all requests from the queue.
    public func clear() {
        queue.removeAll(keepingCapacity: true)
        stats.currentSize = 0
    }

    /// Gets the current queue statistics.
    ///
    /// - Returns: Queue statistics.
    public func getStatistics() -> Statistics {
        stats
    }

    /// Gets the priority of the next request without dequeuing.
    ///
    /// - Returns: The priority of the next request, or nil if empty.
    public func peekPriority() -> Int? {
        queue.first?.priority
    }

    /// Gets all requests for a specific target (without removing them).
    ///
    /// - Parameter target: The target image name.
    /// - Returns: Array of requests for the target.
    public func getRequests(for target: String) -> [JPIPRequest] {
        queue.filter { $0.request.target == target }.map { $0.request }
    }

    /// Removes all requests for a specific target.
    ///
    /// - Parameter target: The target image name.
    /// - Returns: Number of requests removed.
    public func removeRequests(for target: String) -> Int {
        let countBefore = queue.count
        queue.removeAll { $0.request.target == target }
        let removed = countBefore - queue.count
        stats.currentSize = queue.count
        return removed
    }
}

extension J2KError {
    /// Creates a queue full error.
    static func queueFull(_ message: String) -> J2KError {
        .internalError("Queue full: \(message)")
    }
}
