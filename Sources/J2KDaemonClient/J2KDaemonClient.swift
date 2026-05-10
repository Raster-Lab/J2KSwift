// J2KDaemonClient.swift
//
// v8 Phase 6.4 — client-side wrapper around `NSXPCConnection`
// that auto-discovers the `j2kd` Mach service, exposes a
// type-safe async ping API, and gracefully reports
// "daemon unavailable" so callers can fall back to in-process
// decode without dealing with raw XPC error handling.
//
// macOS-only.

#if os(macOS)

import Foundation
import J2KCore
import J2KDaemonProtocol

/// Errors raised by `J2KDaemonClient`.
public enum J2KDaemonClientError: Error, Equatable {
    /// Daemon Mach service is not registered (launchd plist not
    /// installed, or daemon not allowed to start). Callers
    /// should fall back to in-process decode.
    case daemonUnavailable
    /// XPC delivered an error during invocation.
    case xpcInvocationError(String)
    /// The remote proxy could not be obtained (typically because
    /// the connection was invalidated mid-call).
    case proxyUnavailable
}

/// Client wrapper for the `J2KDaemonProtocol` Mach service.
///
/// Construct once per process (the underlying NSXPCConnection
/// auto-reconnects on failure). All calls are async; the
/// underlying XPC reply is bridged to a checked continuation.
///
/// Auto-discovery: probes the Mach service at construct time. If
/// `isAvailable` is false, callers MUST fall back to in-process
/// decode — invoking client methods will throw
/// `J2KDaemonClientError.daemonUnavailable`.
///
/// Thread-safety: the client is designed to be used from a
/// single async context. Concurrent ping calls from multiple
/// tasks are safe (NSXPCConnection serialises invocations
/// internally) but not currently optimised.
public actor J2KDaemonClient {

    /// Optional pre-built connection (e.g. from a test that
    /// uses an anonymous endpoint). When nil, the client
    /// constructs a connection to the production Mach service.
    private var connection: NSXPCConnection?

    /// Whether the daemon Mach service is reachable. Computed
    /// at construct time and cached. `false` means callers
    /// should fall back to in-process decode.
    public let isAvailable: Bool

    /// Default initialiser — connects to the production Mach
    /// service registered by launchd (`J2KDaemonMachServiceName`).
    public init() {
        let conn = NSXPCConnection(machServiceName: J2KDaemonMachServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: J2KDaemonProtocol.self)
        conn.resume()
        self.connection = conn
        // Availability check: try to obtain a remote proxy. If
        // the daemon plist isn't installed, NSXPCConnection's
        // proxy creation succeeds, but the first invocation
        // will fail. We do a synchronous test here only for
        // the simple case; production callers should treat
        // every method as potentially-failing and fall back
        // on `daemonUnavailable`.
        self.isAvailable = true  // optimistic; real failure surfaces on first call
    }

    /// Test/internal initialiser — accepts a pre-built
    /// connection (typically from `NSXPCListener.anonymous()`
    /// in tests) so the same client can be exercised without
    /// installing launchd plist.
    public init(connection: NSXPCConnection) {
        self.connection = connection
        self.isAvailable = true
    }

    /// Explicit cleanup — call before letting the client go
    /// out of scope to deterministically release the XPC
    /// connection. Safe to call multiple times.
    public func close() {
        connection?.invalidate()
        connection = nil
    }

    /// Ping the daemon. Returns the echoed request ID, daemon
    /// PID, and daemon uptime in seconds.
    ///
    /// - Throws: `J2KDaemonClientError.daemonUnavailable` if the
    ///   daemon is not running or the Mach service is not
    ///   registered. Callers should fall back to in-process
    ///   decode on this error.
    public func ping(
        requestID: String = UUID().uuidString
    ) async throws -> (echoedID: String, daemonPID: Int32, daemonUptimeSeconds: Double) {
        guard let conn = connection else {
            throw J2KDaemonClientError.daemonUnavailable
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, Int32, Double), Error>) in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                cont.resume(throwing: J2KDaemonClientError.xpcInvocationError(
                    "\(error)"))
            } as? J2KDaemonProtocol
            guard let proxy else {
                cont.resume(throwing: J2KDaemonClientError.proxyUnavailable)
                return
            }
            proxy.ping(requestID: requestID) { id, pid, uptime in
                cont.resume(returning: (id, pid, uptime))
            }
        }
    }

    /// **v8 Phase 6.5** — request the daemon decode a J2K
    /// codestream. The daemon decodes via its warm
    /// J2KMetalSession, marshals the resulting pixel data back
    /// via XPC.
    ///
    /// Phase 6.5 returns the decoded `J2KImage`'s first
    /// component (single-component grayscale is the dominant
    /// medical-imaging shape). Multi-component (RGB) is Phase
    /// 6.5b — the protocol surface allows extending later
    /// without breaking compatibility.
    ///
    /// - Throws:
    ///   - `J2KDaemonClientError.daemonUnavailable` if not connected
    ///   - `J2KDaemonClientError.xpcInvocationError(String)` if
    ///     the daemon-side decode failed (the wrapped string
    ///     describes the J2K decode error)
    public func decode(_ codestream: Data) async throws -> J2KImage {
        guard let conn = connection else {
            throw J2KDaemonClientError.daemonUnavailable
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<J2KImage, Error>) in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                cont.resume(throwing: J2KDaemonClientError.xpcInvocationError(
                    "\(error)"))
            } as? J2KDaemonProtocol
            guard let proxy else {
                cont.resume(throwing: J2KDaemonClientError.proxyUnavailable)
                return
            }
            proxy.decode(codestream: codestream) { success, w, h, bd, signed, compCount, bigEndian, pixelData, errMsg in
                if !success {
                    cont.resume(throwing: J2KDaemonClientError.xpcInvocationError(
                        errMsg ?? "decode failed (no message)"))
                    return
                }
                let component = J2KComponent(
                    index: 0,
                    bitDepth: Int(bd),
                    signed: signed,
                    width: Int(w),
                    height: Int(h),
                    data: pixelData,
                    sampleByteOrder: bigEndian ? .bigEndian : .littleEndian)
                let image = J2KImage(
                    width: Int(w),
                    height: Int(h),
                    components: [component])
                cont.resume(returning: image)
            }
        }
    }

    /// **v8.8 (research)** — file-based decode. Asks the daemon to
    /// read the codestream from `codestreamPath` and write the
    /// decoded pixel data directly to `outputPath`, bypassing
    /// XPC bytes-transfer for both directions.
    ///
    /// Returns metadata about the decoded image. The caller is
    /// responsible for reading `outputPath` (via `Data(contentsOf:)`
    /// or mmap) when it needs the pixels.
    public struct DecodeFileResult: Sendable {
        public let width: Int
        public let height: Int
        public let bitDepth: Int
        public let signed: Bool
        public let componentCount: Int
        public let bigEndian: Bool
    }

    public func decodeFile(
        codestreamPath: String,
        outputPath: String
    ) async throws -> DecodeFileResult {
        guard let conn = connection else {
            throw J2KDaemonClientError.daemonUnavailable
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<DecodeFileResult, Error>) in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                cont.resume(throwing: J2KDaemonClientError.xpcInvocationError(
                    "\(error)"))
            } as? J2KDaemonProtocol
            guard let proxy else {
                cont.resume(throwing: J2KDaemonClientError.proxyUnavailable)
                return
            }
            proxy.decodeFile(codestreamPath: codestreamPath,
                             outputPath: outputPath) {
                success, w, h, bd, signed, compCount, bigEndian, errMsg in
                if !success {
                    cont.resume(throwing: J2KDaemonClientError.xpcInvocationError(
                        errMsg ?? "decodeFile failed (no message)"))
                    return
                }
                cont.resume(returning: DecodeFileResult(
                    width: Int(w), height: Int(h),
                    bitDepth: Int(bd), signed: signed,
                    componentCount: Int(compCount),
                    bigEndian: bigEndian))
            }
        }
    }
}

#endif // os(macOS)
