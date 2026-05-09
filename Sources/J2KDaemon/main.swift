// main.swift
//
// v8 Phase 6.3 / 6.4 — `j2kd` daemon executable. Listens on a
// Mach service registered by launchd, responds to XPC requests
// from the `j2k` CLI client. Holds a long-lived
// `J2KMetalSession.processShared` across requests so single-shot
// CLI invocations get warm-decode performance.
//
// **Phase 6.4 refactor**: the daemon service implementation now
// lives in `J2KDaemonCore` (so tests can use it without
// duplicating code). This main.swift just wires the listener
// to the production Mach service.
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

        let delegate = J2KDaemonListenerDelegate()

        // Listen on the Mach service registered by launchd. When
        // the daemon is started directly (no launchd), this
        // listener doesn't get matched to any incoming
        // connection — Phase 6.6 will add explicit "are we
        // under launchd" detection + clearer error reporting.
        let listener = NSXPCListener(machServiceName: J2KDaemonMachServiceName)
        listener.delegate = delegate
        listener.resume()

        // Block forever. The listener runs on its own queue;
        // dispatchMain() parks the main thread until SIGTERM /
        // SIGKILL or launchd asks for exit.
        dispatchMain()
    }
}

#endif // os(macOS)
