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

    /// **v8 Phase 6.5** — decode a JPEG 2000 codestream via the
    /// daemon. The daemon holds a long-lived warm
    /// `J2KMetalSession.processShared`, so single-shot CLI
    /// callers get warm-decode performance without paying
    /// per-process Metal cold-start.
    ///
    /// Reply tuple shape (NSXPCInterface marshalling
    /// constraints — only @objc-compatible types):
    /// - `success`: `true` if decode succeeded, `false` if any
    ///   error occurred (check `errorMessage`)
    /// - `width`, `height`: pixel dimensions
    /// - `bitDepth`: bits per sample (e.g. 8, 12, 16)
    /// - `signed`: whether components are signed
    /// - `componentCount`: number of components (1 = grayscale,
    ///   3 = RGB, etc.)
    /// - `bigEndian`: byte order of the pixel data buffer (true
    ///   = big-endian, the J2KSwift convention for ≥9-bit data)
    /// - `pixelData`: raw decoded bytes for the FIRST component.
    ///   Multi-component decodes pack components sequentially:
    ///   width*height*bytesPerSample for component 0, then
    ///   component 1, etc.
    /// - `errorMessage`: nil on success, error description on
    ///   failure
    ///
    /// **Marshalling**: the codestream and pixel data are
    /// transmitted as `Data` payloads via XPC's standard
    /// dictionary marshalling. For large images (e.g. DX 12.7 MB
    /// codestream → 33 MB decoded pixels), XPC's automatic
    /// out-of-line marshalling kicks in — no need for explicit
    /// `xpc_shmem`. Phase 6.5 measures whether this is fast
    /// enough; Phase 6.5b will add `xpc_shmem` if XPC's
    /// auto-marshalling is the bottleneck.
    ///
    /// - Parameters:
    ///   - codestream: the JPEG 2000 codestream bytes (J2K, JP2,
    ///     or HTJ2K).
    ///   - reply: closure invoked on the connection's reply
    ///     queue with the result tuple.
    func decode(
        codestream: Data,
        reply: @escaping (_ success: Bool,
                          _ width: Int32,
                          _ height: Int32,
                          _ bitDepth: Int32,
                          _ signed: Bool,
                          _ componentCount: Int32,
                          _ bigEndian: Bool,
                          _ pixelData: Data,
                          _ errorMessage: String?) -> Void)
}

#endif // os(macOS)
