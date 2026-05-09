// DaemonPing.swift
//
// v8 Phase 6.4 — `j2k daemon-ping` subcommand. Connects to the
// `j2kd` daemon via the J2KDaemonClient, sends a ping, prints
// the reply. Exits 0 on success, 1 if the daemon is unreachable.
//
// Usage:
//
//   j2k daemon-ping                          # default request id (UUID)
//   j2k daemon-ping --request-id my-id       # custom request id
//   j2k daemon-ping --timeout 2.0            # wait up to 2 seconds
//
// macOS-only.

#if os(macOS)

import Foundation
import J2KDaemonClient

extension J2KCLI {

    static func daemonPingCommand(_ args: [String]) async throws {
        let options = parseArguments(args)
        if options["help"] != nil {
            printDaemonPingHelp()
            return
        }

        let requestID = options["request-id"] ?? UUID().uuidString
        let jsonOutput = options["json"] != nil

        let client = J2KDaemonClient()
        let available = await client.isAvailable
        if !available {
            if jsonOutput {
                print("{\"available\":false,\"error\":\"daemon Mach service not registered\"}")
            } else {
                print("daemon: unavailable")
                print("(install the launchd plist from Resources/launchd/com.raster.j2kd.plist to enable)")
            }
            exit(1)
        }

        do {
            let t0 = Date()
            let result = try await client.ping(requestID: requestID)
            let rttMs = Date().timeIntervalSince(t0) * 1000.0

            if jsonOutput {
                print(String(format: "{\"available\":true,\"echoedID\":\"%@\",\"daemonPID\":%d,\"daemonUptimeSeconds\":%.3f,\"rttMs\":%.3f}",
                    result.echoedID, result.daemonPID, result.daemonUptimeSeconds, rttMs))
            } else {
                print("daemon: available")
                print("  PID:                 \(result.daemonPID)")
                print(String(format: "  uptime:              %.3f seconds", result.daemonUptimeSeconds))
                print(String(format: "  ping round-trip:     %.3f ms", rttMs))
                print("  echoed request id:   \(result.echoedID)")
            }
        } catch {
            if jsonOutput {
                print("{\"available\":false,\"error\":\"\(error)\"}")
            } else {
                print("daemon: ping failed — \(error)")
                print("(daemon may have crashed mid-call, or Mach service not yet up)")
            }
            exit(1)
        }
    }

    static func printDaemonPingHelp() {
        print("""
        Usage: j2k daemon-ping [options]

        Pings the j2kd XPC daemon via its registered Mach service
        (com.raster.j2kd) and prints the reply. macOS-only.

        Options:
          --request-id ID          Custom request ID (default: random UUID)
          --json                   Print result as JSON instead of human-readable
          --quiet                  (ignored — present for shell-script symmetry)
          -h, --help               Show this help

        Exit codes:
          0   daemon reachable, ping round-tripped successfully
          1   daemon unavailable OR ping failed

        See Resources/launchd/com.raster.j2kd.plist for install steps.
        """)
    }
}

#endif // os(macOS)
