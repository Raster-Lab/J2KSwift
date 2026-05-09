// J2KDaemonService.swift
//
// v8 Phase 6.4 — `J2KDaemonProtocol` implementation extracted
// to a shared library so the daemon executable AND the test
// suite can both use it without duplicating code.
//
// macOS-only. Linked by `Sources/J2KDaemon/` (the executable)
// and by `Tests/J2KDaemonTests/` (round-trip in-process tests
// via NSXPCListener.anonymous()).

#if os(macOS)

import Foundation
import J2KDaemonProtocol

/// Daemon-side implementation of `J2KDaemonProtocol`. Each XPC
/// connection gets its own instance (NSXPCConnection's per-
/// connection `exportedObject` contract); `daemonStartTime` lives
/// at the type level so all connections see the same daemon-side
/// uptime.
public final class J2KDaemonService: NSObject, J2KDaemonProtocol {

    /// Process-global daemon start time, used to compute uptime
    /// in `ping` replies. Captured at type init.
    nonisolated(unsafe) public static let startTime: Date = Date()

    public override init() {
        super.init()
    }

    public func ping(
        requestID: String,
        reply: @escaping (String, Int32, Double) -> Void
    ) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let uptime = Date().timeIntervalSince(J2KDaemonService.startTime)
        reply(requestID, pid, uptime)
    }
}

/// `NSXPCListenerDelegate` — accepts every incoming connection,
/// wires up the exported object, resumes the connection.
///
/// Phase 6.6 will add `interruptionHandler` (per-connection
/// state cleanup) and `invalidationHandler` (idle-timeout
/// bookkeeping).
public final class J2KDaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    public override init() {
        super.init()
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection conn: NSXPCConnection
    ) -> Bool {
        let exported = J2KDaemonService()
        conn.exportedInterface = NSXPCInterface(with: J2KDaemonProtocol.self)
        conn.exportedObject = exported
        conn.resume()
        return true
    }
}

#endif // os(macOS)
