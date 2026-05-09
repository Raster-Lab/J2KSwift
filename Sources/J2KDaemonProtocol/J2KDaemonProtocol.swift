// J2KDaemonProtocol.swift
//
// v8 Phase 6.3 — XPC protocol shared between the `j2kd` daemon
// (`Sources/J2KDaemon`) and the `j2k` CLI client (which connects
// to the daemon when available, falling back to in-process decode
// otherwise).
//
// **macOS-only**: XPC is a macOS framework. The protocol module
// is gated `#if os(macOS)` at the type level so that iOS targets
// can still link against the umbrella package without the
// daemon-related types.
//
// **Skeleton scope (Phase 6.3)**: this protocol exposes only a
// `ping(reply:)` method — enough to prove the Mach service
// round-trip plumbing works end-to-end. The decode RPC (Phase
// 6.4), shared-memory marshalling for large images (Phase 6.5),
// and lifecycle management (Phase 6.6) extend this protocol
// without breaking compatibility — `@objc` protocols are
// versionable, and additional methods can ship as protocol
// extensions or as a v2 protocol.

import Foundation

#if os(macOS)

/// The Mach service name the daemon registers with launchd.
///
/// The CLI client uses this to look up the daemon via
/// `NSXPCConnection(machServiceName:)`. Hard-coded here so both
/// daemon and client agree without configuration.
///
/// Convention: reverse-DNS, two-segment scope (`raster.j2kd`).
public let J2KDaemonMachServiceName = "com.raster.j2kd"

/// Communication protocol between the `j2k` CLI client and the
/// `j2kd` daemon.
///
/// Marked `@objc` because `NSXPCConnection` requires Objective-C-
/// compatible protocols (XPC marshals via the runtime). Methods
/// are async-style (callback-based) per the XPC convention —
/// the connection serialises invocations.
///
/// Phase 6.3 surface is intentionally minimal: a `ping` method
/// that takes a request id (so the client can match requests to
/// responses if it pipelines) and returns a small string + the
/// daemon's PID + uptime.
@objc public protocol J2KDaemonProtocol {
    /// Ping the daemon. Returns a small payload that proves the
    /// round-trip worked AND identifies which daemon process
    /// answered (handy for diagnosing zombies + multi-instance
    /// races).
    ///
    /// - Parameters:
    ///   - requestID: client-supplied identifier echoed in the reply.
    ///   - reply: closure invoked on the connection's reply queue
    ///     with `(echoedID, daemonPID, daemonUptimeSeconds)`.
    func ping(
        requestID: String,
        reply: @escaping (_ echoedID: String,
                          _ daemonPID: Int32,
                          _ daemonUptimeSeconds: Double) -> Void)
}

#endif // os(macOS)
