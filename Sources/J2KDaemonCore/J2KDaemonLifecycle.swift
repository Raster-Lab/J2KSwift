// J2KDaemonLifecycle.swift
//
// v8 Phase 6.6 — daemon lifecycle: idle-timeout + signal handling.
//
// **Idle timeout**: the daemon tracks the timestamp of the last
// successful XPC request. A timer (defaulting to 5-minute
// interval) checks whether the gap between now and last-activity
// exceeds the configured timeout (defaulting to 10 minutes).
// When it does, the daemon exits cleanly via `exit(0)` — launchd
// will re-spawn it on the next client connection.
//
// **Signal handling**: SIGTERM and SIGINT are caught and trigger
// a graceful exit. Allows clean shutdown via `launchctl unload`,
// `kill -TERM`, or Ctrl-C if the daemon was launched directly.

#if os(macOS)

import Foundation
import Dispatch

/// Tracks daemon-side activity for idle-timeout decisions.
/// Thread-safe via NSLock.
public final class J2KDaemonActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastActivity: Date

    public init() {
        self._lastActivity = Date()
    }

    /// Mark a request as having been served. Call this from
    /// every protocol method's reply path.
    public func touch() {
        lock.lock()
        _lastActivity = Date()
        lock.unlock()
    }

    /// Seconds since the most recent `touch()`.
    public var idleSeconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(_lastActivity)
    }
}

/// Lifecycle controller — installs an idle-timeout timer and
/// signal handlers. Construct once at daemon startup; the
/// controller retains itself via the dispatch sources.
public final class J2KDaemonLifecycle: @unchecked Sendable {

    public let tracker: J2KDaemonActivityTracker

    /// Idle timeout in seconds — after this much time without
    /// XPC activity, the daemon exits cleanly. Default 600 s
    /// (10 minutes).
    public let idleTimeoutSeconds: TimeInterval

    /// How often the idle check runs. Default 60 s.
    public let checkIntervalSeconds: TimeInterval

    /// Optional override exit handler for testing. When set,
    /// called instead of `exit(0)` so unit tests can verify the
    /// timeout fires without terminating the test process.
    public var exitHandler: (() -> Void)?

    private var idleTimer: DispatchSourceTimer?
    private var sigtermSource: DispatchSourceSignal?
    private var sigintSource: DispatchSourceSignal?

    public init(
        tracker: J2KDaemonActivityTracker = J2KDaemonActivityTracker(),
        idleTimeoutSeconds: TimeInterval = 600,
        checkIntervalSeconds: TimeInterval = 60
    ) {
        self.tracker = tracker
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.checkIntervalSeconds = checkIntervalSeconds
    }

    /// Start the idle timer + install signal handlers. Call
    /// once at daemon startup, before `dispatchMain()`.
    public func start() {
        startIdleTimer()
        installSignalHandlers()
    }

    private func startIdleTimer() {
        let queue = DispatchQueue(label: "com.raster.j2kd.lifecycle", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + checkIntervalSeconds,
                       repeating: checkIntervalSeconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.tracker.idleSeconds >= self.idleTimeoutSeconds {
                self.exit(reason: "idle for \(Int(self.tracker.idleSeconds))s; exceeded timeout \(Int(self.idleTimeoutSeconds))s")
            }
        }
        timer.resume()
        self.idleTimer = timer
    }

    private func installSignalHandlers() {
        // Ignore the OS-default signal disposition (so it
        // doesn't terminate the process) before installing the
        // dispatch source.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let queue = DispatchQueue(label: "com.raster.j2kd.signals", qos: .utility)

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        sigterm.setEventHandler { [weak self] in
            self?.exit(reason: "SIGTERM received")
        }
        sigterm.resume()
        self.sigtermSource = sigterm

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        sigint.setEventHandler { [weak self] in
            self?.exit(reason: "SIGINT received")
        }
        sigint.resume()
        self.sigintSource = sigint
    }

    private func exit(reason: String) {
        let stderr = FileHandle.standardError
        let line = "[j2kd] exiting: \(reason)\n"
        if let data = line.data(using: .utf8) {
            try? stderr.write(contentsOf: data)
        }
        if let exitHandler = self.exitHandler {
            exitHandler()
        } else {
            Foundation.exit(0)
        }
    }
}

#endif // os(macOS)
