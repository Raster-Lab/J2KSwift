// J2KDaemonProtocolRoundTripTests.swift
//
// v8 Phase 6.3 / 6.4 — skeleton in-process round-trip test for
// the `J2KDaemonProtocol`. Validates the XPC protocol surface +
// listener delegate machinery without needing an installed
// launchd Mach service.
//
// **Phase 6.4 refactor**: now imports `J2KDaemonCore` rather
// than duplicating the service implementation locally.
// Eliminates the test-only `TestJ2KDaemonService` class.
//
// What this DOESN'T test (deferred to Phase 6.5-6.6):
//   - launchd integration (real Mach service registration)
//   - Cross-process IPC (this test is in-process via anonymous endpoint)
//   - Daemon process lifecycle (idle timeout, signal handling)
//   - Decode RPC (Phase 6.5)
//   - Shared-memory marshalling for large images (Phase 6.5)

#if os(macOS)

import XCTest
import Foundation
import J2KDaemonProtocol
import J2KDaemonCore

final class J2KDaemonProtocolRoundTripTests: XCTestCase {

    /// Validates that a client connected to an in-process
    /// `NSXPCListener.anonymous()` can call `ping` and receive
    /// the expected reply tuple. This is the load-bearing
    /// contract test for Phase 6.3.
    func testPingRoundTrip_AnonymousInProcess() async throws {
        let listener = NSXPCListener.anonymous()
        let delegate = J2KDaemonListenerDelegate()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }

        // Connect to the anonymous listener via its endpoint
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: J2KDaemonProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        // Issue the ping. The continuation is the bridge from
        // XPC's callback-based reply to async/await.
        let result = await withCheckedContinuation { (cont: CheckedContinuation<(String, Int32, Double), Never>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                XCTFail("XPC error: \(error)")
                cont.resume(returning: ("error", 0, 0))
            } as? J2KDaemonProtocol
            guard let proxy else {
                XCTFail("remoteObjectProxy is nil")
                cont.resume(returning: ("nil-proxy", 0, 0))
                return
            }
            proxy.ping(requestID: "phase-6.4-skeleton") { id, pid, uptime in
                cont.resume(returning: (id, pid, uptime))
            }
        }

        // Validate the reply shape
        XCTAssertEqual(result.0, "phase-6.4-skeleton",
            "echoedID must match the request id verbatim")
        XCTAssertGreaterThan(result.1, 0,
            "daemonPID must be the test process's PID (positive)")
        XCTAssertGreaterThanOrEqual(result.2, 0,
            "daemonUptimeSeconds must be non-negative")
        XCTAssertLessThan(result.2, 60,
            "daemonUptimeSeconds should be small in a fresh test (< 60 s)")
    }

    /// Validates that the Mach service name constant is non-empty
    /// and correctly-shaped (reverse-DNS).
    func testMachServiceNameShape() {
        XCTAssertFalse(J2KDaemonMachServiceName.isEmpty)
        XCTAssertTrue(J2KDaemonMachServiceName.contains("."),
            "Mach service names should be reverse-DNS")
        XCTAssertTrue(J2KDaemonMachServiceName.hasPrefix("com."),
            "use a real organisation prefix")
    }

    /// Validates that the protocol is `@objc`-compatible (XPC
    /// requires Obj-C runtime visibility for proxying).
    func testProtocolIsObjCMarshalable() {
        let interface = NSXPCInterface(with: J2KDaemonProtocol.self)
        XCTAssertNotNil(interface,
            "NSXPCInterface(with:) must succeed — proves the protocol is @objc")
    }
}

#endif // os(macOS)
