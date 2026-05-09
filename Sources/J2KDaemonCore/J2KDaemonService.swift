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
import J2KCore
import J2KCodec
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

    /// Optional activity tracker — when set, every method
    /// touches the tracker so the daemon's idle-timeout clock
    /// resets on each successful request. Set this from the
    /// daemon executable's startup code; nil in tests that
    /// don't care about lifecycle.
    public let activityTracker: J2KDaemonActivityTracker?

    public override init() {
        self.activityTracker = nil
        super.init()
    }

    public init(activityTracker: J2KDaemonActivityTracker?) {
        self.activityTracker = activityTracker
        super.init()
    }

    public func ping(
        requestID: String,
        reply: @escaping (String, Int32, Double) -> Void
    ) {
        activityTracker?.touch()
        let pid = ProcessInfo.processInfo.processIdentifier
        let uptime = Date().timeIntervalSince(J2KDaemonService.startTime)
        reply(requestID, pid, uptime)
    }

    /// v8 Phase 6.5 — decode a codestream using the daemon's
    /// long-lived warm Metal session. The first call in the
    /// daemon's lifetime pays Metal cold-start; every
    /// subsequent call uses the cached session — that's the
    /// whole point of having a daemon.
    public func decode(
        codestream: Data,
        reply: @escaping (Bool, Int32, Int32, Int32, Bool, Int32, Bool, Data, String?) -> Void
    ) {
        activityTracker?.touch()
        // Wrap the non-Sendable @objc reply closure in a class
        // that is @unchecked Sendable so we can transfer it to
        // a Task. NSXPCConnection's reply contract guarantees
        // thread-safety per-call (the closure can be invoked
        // from any thread), so wrapping in @unchecked Sendable
        // is safe.
        let replyBox = ReplyBox(reply)
        Task.detached {
            do {
                // Pre-warm if not already done. preWarm() is
                // idempotent — subsequent calls are no-ops.
                await J2KDecoder.preWarm()
                let decoder = J2KDecoder()
                let image = try await decoder.decode(codestream)

                // Marshal the FIRST component's bytes (Phase
                // 6.5 ships single-component support; multi-
                // component is Phase 6.5b).
                guard let comp0 = image.components.first else {
                    replyBox.reply(false, 0, 0, 0, false, 0, false, Data(),
                          "decoded image has zero components")
                    return
                }
                replyBox.reply(
                    true,
                    Int32(image.width),
                    Int32(image.height),
                    Int32(comp0.bitDepth),
                    comp0.signed,
                    Int32(image.components.count),
                    comp0.sampleByteOrder == .bigEndian,
                    comp0.data,
                    nil
                )
            } catch {
                replyBox.reply(false, 0, 0, 0, false, 0, false, Data(),
                      "decode failed: \(error)")
            }
        }
    }
}

/// Internal Sendable wrapper for the XPC reply closure. Safe
/// because NSXPCConnection's reply contract is thread-safe.
private final class ReplyBox: @unchecked Sendable {
    let reply: (Bool, Int32, Int32, Int32, Bool, Int32, Bool, Data, String?) -> Void
    init(_ reply: @escaping (Bool, Int32, Int32, Int32, Bool, Int32, Bool, Data, String?) -> Void) {
        self.reply = reply
    }
}

/// `NSXPCListenerDelegate` — accepts every incoming connection,
/// wires up the exported object, resumes the connection.
///
/// **v8 Phase 6.6**: when constructed with an
/// `activityTracker`, every accepted connection's exported
/// service shares the same tracker so the daemon's idle-
/// timeout clock resets on each XPC request.
public final class J2KDaemonListenerDelegate: NSObject, NSXPCListenerDelegate {
    public let activityTracker: J2KDaemonActivityTracker?

    public override init() {
        self.activityTracker = nil
        super.init()
    }

    public init(activityTracker: J2KDaemonActivityTracker?) {
        self.activityTracker = activityTracker
        super.init()
    }

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection conn: NSXPCConnection
    ) -> Bool {
        let exported = J2KDaemonService(activityTracker: activityTracker)
        conn.exportedInterface = NSXPCInterface(with: J2KDaemonProtocol.self)
        conn.exportedObject = exported
        conn.resume()
        return true
    }
}

#endif // os(macOS)
