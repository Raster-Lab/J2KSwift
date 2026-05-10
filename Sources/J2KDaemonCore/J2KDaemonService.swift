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
        let tEntry = DispatchTime.now()
        let replyBox = ReplyBox(reply)
        Task.detached {
            let tTaskStart = DispatchTime.now()
            do {
                await J2KDecoder.preWarm()
                let tPreWarmDone = DispatchTime.now()
                let decoder = J2KDecoder()
                let image = try await decoder.decode(codestream)
                let tDecodeDone = DispatchTime.now()

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
                let tReplyEnqueued = DispatchTime.now()

                // v8.8 (research): emit stage breakdown to stderr if
                // J2KD_DECODE_TRACE=1 is set in the daemon's env.
                if ProcessInfo.processInfo.environment["J2KD_DECODE_TRACE"] == "1" {
                    let entryToTask = Double(tTaskStart.uptimeNanoseconds &- tEntry.uptimeNanoseconds) / 1_000_000.0
                    let preWarm = Double(tPreWarmDone.uptimeNanoseconds &- tTaskStart.uptimeNanoseconds) / 1_000_000.0
                    let decode = Double(tDecodeDone.uptimeNanoseconds &- tPreWarmDone.uptimeNanoseconds) / 1_000_000.0
                    let reply = Double(tReplyEnqueued.uptimeNanoseconds &- tDecodeDone.uptimeNanoseconds) / 1_000_000.0
                    FileHandle.standardError.write(
                        "[j2kd-trace] entry→task=\(String(format: "%.2f", entryToTask)) ms preWarm=\(String(format: "%.2f", preWarm)) ms decode=\(String(format: "%.2f", decode)) ms reply=\(String(format: "%.2f", reply)) ms total_in_daemon=\(String(format: "%.2f", entryToTask + preWarm + decode + reply)) ms bytes_in=\(codestream.count) bytes_out=\(comp0.data.count)\n".data(using: .utf8)!)
                }
            } catch {
                replyBox.reply(false, 0, 0, 0, false, 0, false, Data(),
                      "decode failed: \(error)")
            }
        }
    }

    /// **v8.8 (research)** — file-path-based decode. Reads the
    /// codestream from `codestreamPath` (mmap'd to avoid a buffer
    /// copy), decodes via the warm `J2KDecoder`, and writes the
    /// FIRST component's raw bytes to `outputPath`. Reply carries
    /// only metadata — pixelData stays on disk.
    ///
    /// Saves ~6 ms on DX vs the `Data`-based `decode` path; see
    /// `V8_8_DaemonOverheadDecomposition`.
    public func decodeFile(
        codestreamPath: String,
        outputPath: String,
        reply: @escaping (Bool, Int32, Int32, Int32, Bool, Int32, Bool, String?) -> Void
    ) {
        activityTracker?.touch()
        let replyBox = FileReplyBox(reply)
        Task.detached {
            do {
                // Read input via mmap (.alwaysMapped) — zero-copy load.
                let url = URL(fileURLWithPath: codestreamPath)
                let codestream = try Data(contentsOf: url, options: [.alwaysMapped])

                await J2KDecoder.preWarm()
                let decoder = J2KDecoder()
                let image = try await decoder.decode(codestream)

                guard let comp0 = image.components.first else {
                    replyBox.reply(false, 0, 0, 0, false, 0, false,
                                   "decoded image has zero components")
                    return
                }

                // Write decoded pixel data directly to the destination
                // path. Skip the temp-file dance — caller owns atomicity.
                try comp0.data.write(to: URL(fileURLWithPath: outputPath))

                replyBox.reply(
                    true,
                    Int32(image.width),
                    Int32(image.height),
                    Int32(comp0.bitDepth),
                    comp0.signed,
                    Int32(image.components.count),
                    comp0.sampleByteOrder == .bigEndian,
                    nil
                )
            } catch {
                replyBox.reply(false, 0, 0, 0, false, 0, false,
                               "decodeFile failed: \(error)")
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

/// Companion wrapper for the v8.8 `decodeFile` reply (no inline pixelData).
private final class FileReplyBox: @unchecked Sendable {
    let reply: (Bool, Int32, Int32, Int32, Bool, Int32, Bool, String?) -> Void
    init(_ reply: @escaping (Bool, Int32, Int32, Int32, Bool, Int32, Bool, String?) -> Void) {
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
