/// # JPIPServerComponentTests
///
/// Tests for JPIP server components (session, queue, throttle).

import XCTest
@testable import JPIP
import J2KCore

final class JPIPServerComponentTests: XCTestCase {
    
    // MARK: - Server Session Tests
    
    func testServerSessionInitialization() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        XCTAssertEqual(session.sessionID, "session-1")
        XCTAssertEqual(session.channelID, "cid-1")
        XCTAssertEqual(session.target, "test.jp2")
        XCTAssertEqual(await session.totalBytesSent, 0)
        XCTAssertEqual(await session.totalRequests, 0)
    }
    
    func testServerSessionActivity() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        let initialActivity = await session.lastActivity
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await session.updateActivity()
        let updatedActivity = await session.lastActivity
        
        XCTAssertGreaterThan(updatedActivity, initialActivity)
    }
    
    func testServerSessionRecordRequest() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        await session.recordRequest(bytesSent: 1024)
        
        XCTAssertEqual(await session.totalRequests, 1)
        XCTAssertEqual(await session.totalBytesSent, 1024)
        
        await session.recordRequest(bytesSent: 2048)
        
        XCTAssertEqual(await session.totalRequests, 2)
        XCTAssertEqual(await session.totalBytesSent, 3072)
    }
    
    func testServerSessionDataBinTracking() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 123,
            data: Data("test".utf8),
            isComplete: true
        )
        
        XCTAssertFalse(await session.hasDataBin(binClass: .precinct, binID: 123))
        
        await session.recordSentDataBin(dataBin)
        
        XCTAssertTrue(await session.hasDataBin(binClass: .precinct, binID: 123))
    }
    
    func testServerSessionMetadata() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        await session.setMetadata("resolution", value: "1024x768")
        
        let value = await session.getMetadata("resolution") as? String
        XCTAssertEqual(value, "1024x768")
    }
    
    func testServerSessionTimeout() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        // Should not be timed out immediately
        let notTimedOut = await session.hasTimedOut(timeout: 10.0)
        XCTAssertFalse(notTimedOut)
        
        // Should be timed out with very short timeout
        let timedOut = await session.hasTimedOut(timeout: 0.0)
        XCTAssertTrue(timedOut)
    }
    
    func testServerSessionClose() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        await session.setMetadata("key", value: "value")
        
        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 1,
            data: Data("test".utf8),
            isComplete: true
        )
        await session.recordSentDataBin(dataBin)
        
        await session.close()
        
        // Cache should be cleared
        let hasData = await session.hasDataBin(binClass: .precinct, binID: 1)
        XCTAssertFalse(hasData)
        
        let metadata = await session.getMetadata("key")
        XCTAssertNil(metadata)
    }
    
    func testServerSessionInfo() async throws {
        let session = JPIPServerSession(
            sessionID: "session-1",
            channelID: "cid-1",
            target: "test.jp2"
        )
        
        await session.recordRequest(bytesSent: 512)
        
        let info = await session.getInfo()
        
        XCTAssertEqual(info["sessionID"] as? String, "session-1")
        XCTAssertEqual(info["channelID"] as? String, "cid-1")
        XCTAssertEqual(info["target"] as? String, "test.jp2")
        XCTAssertEqual(info["totalRequests"] as? Int, 1)
        XCTAssertEqual(info["totalBytesSent"] as? Int, 512)
    }
    
    // MARK: - Request Queue Tests
    
    func testRequestQueueInitialization() async throws {
        let queue = JPIPRequestQueue(maxSize: 100)
        
        let queueSize = await queue.size; XCTAssertEqual(queueSize, 0)
        let isEmpty = await queue.isEmpty; XCTAssertTrue(isEmpty)
        let isFull = await queue.isFull; XCTAssertFalse(isFull)
    }
    
    func testRequestQueueEnqueue() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        let request = JPIPRequest(target: "test.jp2")
        try await queue.enqueue(request, priority: 50)
        
        let queueSize = await queue.size; XCTAssertEqual(queueSize, 1)
        let isEmpty = await queue.isEmpty; XCTAssertFalse(isEmpty)
    }
    
    func testRequestQueueDequeue() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        let request = JPIPRequest(target: "test.jp2")
        try await queue.enqueue(request, priority: 50)
        
        let dequeued = await queue.dequeue()
        
        XCTAssertNotNil(dequeued)
        XCTAssertEqual(dequeued?.target, "test.jp2")
        let queueSize = await queue.size; XCTAssertEqual(queueSize, 0)
    }
    
    func testRequestQueuePriority() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        // Enqueue with different priorities
        let lowPriority = JPIPRequest(target: "low.jp2")
        let highPriority = JPIPRequest(target: "high.jp2")
        let mediumPriority = JPIPRequest(target: "medium.jp2")
        
        try await queue.enqueue(lowPriority, priority: 10)
        try await queue.enqueue(highPriority, priority: 100)
        try await queue.enqueue(mediumPriority, priority: 50)
        
        // Should dequeue in priority order
        let first = await queue.dequeue()
        XCTAssertEqual(first?.target, "high.jp2")
        
        let second = await queue.dequeue()
        XCTAssertEqual(second?.target, "medium.jp2")
        
        let third = await queue.dequeue()
        XCTAssertEqual(third?.target, "low.jp2")
    }
    
    func testRequestQueueFull() async throws {
        let queue = JPIPRequestQueue(maxSize: 2)
        
        let request1 = JPIPRequest(target: "test1.jp2")
        let request2 = JPIPRequest(target: "test2.jp2")
        let request3 = JPIPRequest(target: "test3.jp2")
        
        try await queue.enqueue(request1, priority: 50)
        try await queue.enqueue(request2, priority: 50)
        
        let isFull = await queue.isFull
        XCTAssertTrue(isFull)
        
        // Should throw when full
        do {
            try await queue.enqueue(request3, priority: 50)
            XCTFail("Should have thrown queue full error")
        } catch {
            // Expected
        }
    }
    
    func testRequestQueueClear() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        for i in 1...5 {
            let request = JPIPRequest(target: "test\(i).jp2")
            try await queue.enqueue(request, priority: 50)
        }
        
        let queueSize = await queue.size; XCTAssertEqual(queueSize, 5)
        
        await queue.clear()
        
        let queueSizeAfter = await queue.size
        XCTAssertEqual(queueSizeAfter, 0)
        
        let isEmpty = await queue.isEmpty
        XCTAssertTrue(isEmpty)
    }
    
    func testRequestQueuePeekPriority() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        let priorityNil = await queue.peekPriority()
        XCTAssertNil(priorityNil)
        
        let request = JPIPRequest(target: "test.jp2")
        try await queue.enqueue(request, priority: 75)
        
        let priority = await queue.peekPriority()
        XCTAssertEqual(priority, 75)
        
        // Peeking should not dequeue
        let size = await queue.size
        XCTAssertEqual(size, 1)
    }
    
    func testRequestQueueGetRequestsForTarget() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        let request1 = JPIPRequest(target: "test1.jp2")
        let request2 = JPIPRequest(target: "test2.jp2")
        let request3 = JPIPRequest(target: "test1.jp2")
        
        try await queue.enqueue(request1, priority: 50)
        try await queue.enqueue(request2, priority: 50)
        try await queue.enqueue(request3, priority: 50)
        
        let requests = await queue.getRequests(for: "test1.jp2")
        XCTAssertEqual(requests.count, 2)
    }
    
    func testRequestQueueRemoveRequestsForTarget() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        let request1 = JPIPRequest(target: "test1.jp2")
        let request2 = JPIPRequest(target: "test2.jp2")
        let request3 = JPIPRequest(target: "test1.jp2")
        
        try await queue.enqueue(request1, priority: 50)
        try await queue.enqueue(request2, priority: 50)
        try await queue.enqueue(request3, priority: 50)
        
        let removed = await queue.removeRequests(for: "test1.jp2")
        XCTAssertEqual(removed, 2)
        
        let size = await queue.size
        XCTAssertEqual(size, 1)
    }
    
    func testRequestQueueStatistics() async throws {
        let queue = JPIPRequestQueue(maxSize: 10)
        
        let request1 = JPIPRequest(target: "test1.jp2")
        let request2 = JPIPRequest(target: "test2.jp2")
        
        try await queue.enqueue(request1, priority: 50)
        _ = await queue.dequeue()
        try await queue.enqueue(request2, priority: 50)
        
        let stats = await queue.getStatistics()
        
        XCTAssertEqual(stats.totalEnqueued, 2)
        XCTAssertEqual(stats.totalDequeued, 1)
        XCTAssertEqual(stats.currentSize, 1)
    }
    
    // MARK: - Bandwidth Throttle Tests
    
    func testBandwidthThrottleInitialization() async throws {
        let throttle = JPIPBandwidthThrottle(
            globalLimit: 1_000_000,
            perClientLimit: 100_000
        )
        
        let stats = await throttle.getStatistics()
        XCTAssertEqual(stats.totalBytesSent, 0)
        XCTAssertEqual(stats.globalThrottles, 0)
        XCTAssertEqual(stats.clientThrottles, 0)
    }
    
    func testBandwidthThrottleCanSend() async throws {
        let throttle = JPIPBandwidthThrottle(
            globalLimit: nil,
            perClientLimit: nil
        )
        
        // With no limits, should always be able to send
        let canSend = await throttle.canSend(clientID: "client-1", bytes: 1024)
        XCTAssertTrue(canSend)
    }
    
    func testBandwidthThrottleRecordSent() async throws {
        let throttle = JPIPBandwidthThrottle()
        
        await throttle.recordSent(clientID: "client-1", bytes: 1024)
        await throttle.recordSent(clientID: "client-1", bytes: 2048)
        
        let stats = await throttle.getStatistics()
        XCTAssertEqual(stats.totalBytesSent, 3072)
        XCTAssertEqual(stats.activeClients, 1)
    }
    
    func testBandwidthThrottlePerClientLimit() async throws {
        let throttle = JPIPBandwidthThrottle(
            globalLimit: nil,
            perClientLimit: 1000 // Very low limit
        )
        
        // First request should succeed
        let canSend1 = await throttle.canSend(clientID: "client-1", bytes: 500)
        XCTAssertTrue(canSend1)
        
        // Large request should fail
        let canSend2 = await throttle.canSend(clientID: "client-1", bytes: 10000)
        XCTAssertFalse(canSend2)
    }
    
    func testBandwidthThrottleRemoveClient() async throws {
        let throttle = JPIPBandwidthThrottle()
        
        await throttle.recordSent(clientID: "client-1", bytes: 1024)
        await throttle.recordSent(clientID: "client-2", bytes: 1024)
        
        var stats = await throttle.getStatistics()
        XCTAssertEqual(stats.activeClients, 2)
        
        await throttle.removeClient("client-1")
        
        stats = await throttle.getStatistics()
        XCTAssertEqual(stats.activeClients, 1)
    }
    
    func testBandwidthThrottleResetStatistics() async throws {
        let throttle = JPIPBandwidthThrottle()
        
        await throttle.recordSent(clientID: "client-1", bytes: 1024)
        
        var stats = await throttle.getStatistics()
        XCTAssertEqual(stats.totalBytesSent, 1024)
        
        await throttle.resetStatistics()
        
        stats = await throttle.getStatistics()
        XCTAssertEqual(stats.totalBytesSent, 0)
    }
    
    func testBandwidthThrottleClearClients() async throws {
        let throttle = JPIPBandwidthThrottle()
        
        await throttle.recordSent(clientID: "client-1", bytes: 1024)
        await throttle.recordSent(clientID: "client-2", bytes: 1024)
        
        await throttle.clearClients()
        
        let stats = await throttle.getStatistics()
        XCTAssertEqual(stats.activeClients, 0)
    }
    
    func testBandwidthThrottleGetAvailableBandwidth() async throws {
        let throttle = JPIPBandwidthThrottle(
            globalLimit: nil,
            perClientLimit: 1000
        )
        
        // Before recording any client, available bandwidth should be nil or max
        _ = await throttle.canSend(clientID: "client-1", bytes: 100)
        
        let available = await throttle.getAvailableBandwidth(for: "client-1")
        // Should have some tokens available after consuming 100
        XCTAssertNotNil(available)
    }
}
