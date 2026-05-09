// main.swift
//
// v8 Phase 6.3 / 6.4 / 6.6 — `j2kd` daemon executable.
//
// Listens on a Mach service registered by launchd, responds to
// XPC requests from the `j2k` CLI client. Holds a long-lived
// `J2KMetalSession.processShared` across requests so single-shot
// CLI invocations get warm-decode performance.
//
// **Phase 6.6 lifecycle**:
// - Idle-timeout: exits cleanly after 10 min of no activity
//   (configurable via env var `J2KD_IDLE_TIMEOUT_SECONDS`).
//   launchd will re-spawn on the next client connection.
// - Signal handling: SIGTERM / SIGINT trigger a graceful
//   exit (allows clean shutdown via `launchctl unload` or
//   `kill -TERM`).
//
// **macOS-only**: this entire executable is gated `#if os(macOS)`.

#if os(macOS)

import Foundation
import J2KDaemonProtocol
import J2KDaemonCore

@main
struct J2KDaemonMain {
    static func main() {
        // Force the start-time singleton to evaluate before main()
        // returns so the first ping has a sensible uptime.
        _ = J2KDaemonService.startTime

        // Phase 6.6 lifecycle — idle-timeout (default 10 min;
        // override via J2KD_IDLE_TIMEOUT_SECONDS env var) +
        // signal handlers for graceful shutdown.
        let idleTimeout: TimeInterval = {
            if let raw = ProcessInfo.processInfo.environment["J2KD_IDLE_TIMEOUT_SECONDS"],
               let parsed = TimeInterval(raw),
               parsed > 0 {
                return parsed
            }
            return 600  // 10 minutes default
        }()
        let lifecycle = J2KDaemonLifecycle(idleTimeoutSeconds: idleTimeout)
        lifecycle.start()

        // Listener delegate shares the lifecycle's activity
        // tracker — every XPC request touches it, resetting the
        // idle clock.
        let delegate = J2KDaemonListenerDelegate(
            activityTracker: lifecycle.tracker)

        // Listen on the Mach service registered by launchd.
        let listener = NSXPCListener(machServiceName: J2KDaemonMachServiceName)
        listener.delegate = delegate
        listener.resume()

        // Block forever. The listener runs on its own queue;
        // dispatchMain() parks the main thread until SIGTERM /
        // SIGKILL or launchd asks for exit (or idle-timeout
        // fires).
        dispatchMain()
    }
}

#endif // os(macOS)
