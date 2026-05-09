// J2KDaemonLifecycleTests.swift
//
// v8 Phase 6.6 — exercises the daemon lifecycle controller.
// Validates the activity tracker + idle-timeout firing logic
// without actually exiting the test process (uses the
// `exitHandler` override).

#if os(macOS)

import XCTest
import Foundation
import J2KDaemonProtocol
import J2KDaemonCore

final class J2KDaemonLifecycleTests: XCTestCase {

    /// Activity tracker reports increasing idle time when not
    /// touched, and resets on touch().
    func testActivityTracker_IdleAndReset() async throws {
        let tracker = J2KDaemonActivityTracker()

        // Initially, idle should be ~0 (just constructed).
        XCTAssertLessThan(tracker.idleSeconds, 0.5)

        // Wait 200 ms — idle should grow.
        try await Task.sleep(nanoseconds: 200_000_000)
        let idleAfterWait = tracker.idleSeconds
        XCTAssertGreaterThan(idleAfterWait, 0.15)
        XCTAssertLessThan(idleAfterWait, 0.5)

        // Touch resets idle to ~0.
        tracker.touch()
        XCTAssertLessThan(tracker.idleSeconds, 0.05)
    }

    /// Lifecycle controller fires the exit handler when idle
    /// exceeds timeout. Uses a small 0.5 s timeout + 0.1 s
    /// check interval to keep the test fast. Override
    /// `exitHandler` so the test process doesn't actually
    /// exit.
    func testLifecycle_IdleTimeoutFires() async throws {
        let tracker = J2KDaemonActivityTracker()
        let lifecycle = J2KDaemonLifecycle(
            tracker: tracker,
            idleTimeoutSeconds: 0.5,
            checkIntervalSeconds: 0.1)

        let didExit = expectation(description: "exit handler fired")
        lifecycle.exitHandler = { didExit.fulfill() }

        lifecycle.start()

        // Wait up to 2 s for the idle-timeout to fire.
        await fulfillment(of: [didExit], timeout: 2.0)
    }

    /// Frequent activity prevents the idle-timeout from firing.
    /// Use a generous safety margin (2 s timeout, 0.5 s check
    /// interval, touches every 0.1 s) to avoid scheduling-jitter
    /// flakes on busy CI hosts.
    func testLifecycle_ActivityPreventsTimeout() async throws {
        let tracker = J2KDaemonActivityTracker()
        let lifecycle = J2KDaemonLifecycle(
            tracker: tracker,
            idleTimeoutSeconds: 2.0,
            checkIntervalSeconds: 0.5)

        let didExit = expectation(description: "exit handler should NOT fire")
        didExit.isInverted = true
        lifecycle.exitHandler = { didExit.fulfill() }

        lifecycle.start()

        // Touch every 100 ms for 1.2 seconds — idle never
        // reaches 2 s. Subsequent checks (at 0.5, 1.0 s) should
        // see idle <= 100 ms.
        for _ in 0..<12 {
            tracker.touch()
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        await fulfillment(of: [didExit], timeout: 0.5)
    }
}

#endif // os(macOS)
