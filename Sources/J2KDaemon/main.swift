// main.swift
//
// v8 Phase 6.3 — `j2kd` daemon executable. Listens on a Mach
// service registered by launchd, responds to XPC requests from
// the `j2k` CLI client. Holds a long-lived `J2KMetalSession.processShared`
// across requests so single-shot CLI invocations get warm-decode
// performance.
//
// **Phase 6.3 skeleton scope**: implements only the `ping`
// method from `J2KDaemonProtocol`. The decode RPC, shared-memory
// marshalling, and lifecycle management land in Phase 6.4-6.6.
//
// **macOS-only**: this entire executable is gated `#if os(macOS)`.
// On other platforms the binary is empty (it shouldn't even be
// built on iOS — Package.swift gates the executableTarget).
//
// **Lifecycle (skeleton — Phase 6.6 will refine)**:
// - launchd starts the daemon on-demand when the first client
//   connection arrives at the Mach service
// - daemon stays running across client connections (no per-
//   request fork)
// - daemon exits on signal or when launchd asks (no idle-timeout
//   logic yet — Phase 6.6)

#if os(macOS)

import Foundation
import J2KDaemonProtocol

/// Daemon implementation of `J2KDaemonProtocol`. Each XPC
/// connection gets its own instance (NSXPCConnection's per-
/// connection exportedObject contract); `daemonStartTime` lives
/// on the listener-level singleton so all connections see the
/// same daemon-side uptime.
final class J2KDaemonService: NSObject, J2KDaemonProtocol {

    /// Process-global daemon start time, used to compute uptime
    /// in `ping` replies. Captured at module init.
    nonisolated(unsafe) static let startTime: Date = Date()

    func ping(
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
final class J2KDaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection conn: NSXPCConnection
    ) -> Bool {
        let exported = J2KDaemonService()
        conn.exportedInterface = NSXPCInterface(with: J2KDaemonProtocol.self)
        conn.exportedObject = exported
        // Phase 6.6 will add invalidationHandler (idle-timeout
        // bookkeeping) and interruptionHandler (cleanup of any
        // per-connection state).
        conn.resume()
        return true
    }
}

@main
struct J2KDaemonMain {
    static func main() {
        // Force the start-time singleton to evaluate before main()
        // returns so the first ping has a sensible uptime.
        _ = J2KDaemonService.startTime

        let delegate = J2KDaemonListenerDelegate()

        // Listen on the Mach service registered by launchd. When the
        // daemon is started directly (no launchd), this fails silently
        // — Phase 6.4 / 6.6 will add an explicit "are we under launchd"
        // check + clear error reporting.
        let listener = NSXPCListener(machServiceName: J2KDaemonMachServiceName)
        listener.delegate = delegate
        listener.resume()

        // Block forever. The listener runs on its own queue;
        // dispatchMain() parks the main thread until SIGTERM / SIGKILL.
        dispatchMain()
    }
}

#endif // os(macOS)
