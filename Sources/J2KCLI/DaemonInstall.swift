// DaemonInstall.swift
//
// v8.1.0 — `j2k daemon-install` / `daemon-uninstall` / `daemon-status`
// subcommands. Automate the launchd LaunchAgent setup that the
// v8.0.0 release notes documented as 5 manual shell steps.
//
// Install layout (per-user, no sudo):
//   - Binary:  ~/Library/Application Support/J2KSwift/j2kd
//   - Plist:   ~/Library/LaunchAgents/com.raster.j2kd.plist
//
// macOS-only — iOS/iPadOS use `J2KDecoder.preWarm()` for warm
// in-process decode (the daemon model isn't applicable on iOS).

#if os(macOS)

import Foundation
import J2KDaemonClient

extension J2KCLI {

    // MARK: - Paths

    private static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/J2KSwift",
                                    isDirectory: true)
    }

    private static var installedDaemonURL: URL {
        supportDir.appendingPathComponent("j2kd")
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.raster.j2kd.plist")
    }

    // MARK: - Plist template (embedded so the j2k binary is self-contained)

    private static func renderPlist(daemonPath: String) -> String {
        let escaped = daemonPath.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.raster.j2kd</string>
            <key>Program</key>
            <string>\(escaped)</string>
            <key>MachServices</key>
            <dict>
                <key>com.raster.j2kd</key>
                <true/>
            </dict>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>KeepAlive</key>
            <false/>
            <key>RunAtLoad</key>
            <false/>
            <key>StandardOutPath</key>
            <string>/tmp/j2kd.stdout.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/j2kd.stderr.log</string>
        </dict>
        </plist>
        """
    }

    // MARK: - Helpers

    @discardableResult
    private static func runShell(_ tool: String, _ args: [String])
        throws -> (status: Int32, stdout: String, stderr: String)
    {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        p.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    /// Locate a `j2kd` binary to install. Searches:
    ///   1. CLI-provided `--daemon-binary <path>` argument.
    ///   2. Same directory as the running `j2k` binary.
    ///   3. `.build/release/j2kd` relative to the current working directory.
    /// Returns nil if none found.
    private static func findDaemonBinary(explicitPath: String?) -> URL? {
        if let p = explicitPath {
            let url = URL(fileURLWithPath: p)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        // Sibling of running j2k binary.
        let argv0 = CommandLine.arguments[0]
        let argURL = URL(fileURLWithPath: argv0)
        // Resolve symlinks before the parent lookup so the sibling lookup
        // works when `j2k` is invoked via a symlink in PATH.
        let resolvedURL = argURL.resolvingSymlinksInPath()
        let sibling = resolvedURL.deletingLastPathComponent()
            .appendingPathComponent("j2kd")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        // .build/release/j2kd in CWD.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let buildRel = cwd.appendingPathComponent(".build/release/j2kd")
        if FileManager.default.isExecutableFile(atPath: buildRel.path) {
            return buildRel
        }
        return nil
    }

    // MARK: - daemon-install

    static func daemonInstallCommand(_ args: [String]) async throws {
        let options = parseArguments(args)
        if options["help"] != nil {
            printDaemonInstallHelp()
            return
        }

        let force = options["force"] != nil
        let explicitDaemon = options["daemon-binary"]

        // 1. Locate j2kd binary.
        guard let source = findDaemonBinary(explicitPath: explicitDaemon) else {
            print("Error: j2kd binary not found.")
            print("       Build it first:  swift build -c release --product j2kd")
            print("       Or pass --daemon-binary <path> explicitly.")
            exit(1)
        }

        // 2. Create per-user support directory.
        try FileManager.default.createDirectory(
            at: supportDir, withIntermediateDirectories: true)

        // 3. Copy binary (overwrite if --force, else error if exists).
        let dest = installedDaemonURL
        if FileManager.default.fileExists(atPath: dest.path) {
            if !force {
                print("Error: \(dest.path) already exists. Use --force to overwrite.")
                exit(1)
            }
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        // Ensure executable bit is set.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: dest.path)

        // 4. Render and write the plist.
        let plist = renderPlist(daemonPath: dest.path)
        let plistDir = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: plistDir, withIntermediateDirectories: true)
        try plist.data(using: .utf8)!.write(to: launchAgentURL, options: .atomic)

        // 5. launchctl bootstrap (modern replacement for `launchctl load`).
        // First, try unload (idempotent — ignore failure if not loaded).
        _ = try? runShell("/bin/launchctl", ["bootout",
            "gui/\(getuid())/com.raster.j2kd"])
        let loadResult = try runShell("/bin/launchctl", ["bootstrap",
            "gui/\(getuid())", launchAgentURL.path])
        if loadResult.status != 0 {
            // Fallback to legacy `launchctl load` for older macOS.
            let legacy = try runShell("/bin/launchctl",
                ["load", launchAgentURL.path])
            if legacy.status != 0 {
                print("Warning: launchctl bootstrap+load both failed:")
                if !loadResult.stderr.isEmpty { print("  bootstrap: \(loadResult.stderr)") }
                if !legacy.stderr.isEmpty { print("  load:      \(legacy.stderr)") }
                print("  Plist installed at \(launchAgentURL.path); load manually.")
                exit(1)
            }
        }

        // 6. Verify by ping.
        // Give launchd a moment to register the Mach service.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let client = J2KDaemonClient()
        if await client.isAvailable {
            print("✓ j2kd installed and reachable.")
            print("  Binary:  \(dest.path)")
            print("  Plist:   \(launchAgentURL.path)")
            print("")
            print("  Verify:  j2k daemon-ping")
            print("  Status:  j2k daemon-status")
            print("  Remove:  j2k daemon-uninstall")
        } else {
            print("⚠ j2kd installed but Mach service not yet reachable.")
            print("  Try `j2k daemon-ping` in a few seconds; the service is")
            print("  on-demand-launched by launchd on the first XPC connection.")
        }
    }

    // MARK: - daemon-uninstall

    static func daemonUninstallCommand(_ args: [String]) async throws {
        let options = parseArguments(args)
        if options["help"] != nil {
            printDaemonUninstallHelp()
            return
        }

        let keepBinary = options["keep-binary"] != nil
        var actions: [String] = []

        // 1. launchctl bootout (modern unload).
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            _ = try? runShell("/bin/launchctl",
                ["bootout", "gui/\(getuid())/com.raster.j2kd"])
            // Fallback to legacy `launchctl unload` (idempotent — ignore failure).
            _ = try? runShell("/bin/launchctl",
                ["unload", launchAgentURL.path])
            try FileManager.default.removeItem(at: launchAgentURL)
            actions.append("Removed plist:   \(launchAgentURL.path)")
        } else {
            actions.append("Plist not present (skipped): \(launchAgentURL.path)")
        }

        // 2. Remove the installed binary unless --keep-binary.
        if FileManager.default.fileExists(atPath: installedDaemonURL.path) {
            if keepBinary {
                actions.append("Kept binary (per --keep-binary): \(installedDaemonURL.path)")
            } else {
                try FileManager.default.removeItem(at: installedDaemonURL)
                actions.append("Removed binary:  \(installedDaemonURL.path)")
            }
        } else {
            actions.append("Binary not present (skipped): \(installedDaemonURL.path)")
        }

        for line in actions { print(line) }
        print("")
        print("✓ j2kd uninstalled.")
    }

    // MARK: - daemon-status

    static func daemonStatusCommand(_ args: [String]) async throws {
        let options = parseArguments(args)
        if options["help"] != nil {
            printDaemonStatusHelp()
            return
        }

        let json = options["json"] != nil

        let binaryExists = FileManager.default.fileExists(atPath: installedDaemonURL.path)
        let plistExists = FileManager.default.fileExists(atPath: launchAgentURL.path)
        let serviceLabel = "gui/\(getuid())/com.raster.j2kd"
        let printResult = try? runShell("/bin/launchctl", ["print", serviceLabel])
        let serviceLoaded = (printResult?.status == 0)

        // Real probe — `J2KDaemonClient.isAvailable` is optimistic and
        // returns true on construction. The actual round-trip via ping
        // is what determines reachability.
        let client = J2KDaemonClient()
        var pingReachable = false
        var pingPID: Int32 = 0
        var pingUptimeS: Double = 0
        var pingRttMs: Double = 0
        do {
            let t0 = Date()
            let r = try await client.ping(requestID: "daemon-status")
            pingRttMs = Date().timeIntervalSince(t0) * 1000.0
            pingPID = r.daemonPID
            pingUptimeS = r.daemonUptimeSeconds
            pingReachable = (r.echoedID == "daemon-status")
        } catch {
            pingReachable = false
        }

        if json {
            print("""
            {
              "binary_installed": \(binaryExists),
              "binary_path": "\(installedDaemonURL.path)",
              "plist_installed": \(plistExists),
              "plist_path": "\(launchAgentURL.path)",
              "service_loaded": \(serviceLoaded),
              "service_reachable": \(pingReachable),
              "daemon_pid": \(pingPID),
              "daemon_uptime_seconds": \(pingUptimeS),
              "ping_rtt_ms": \(pingRttMs)
            }
            """)
            return
        }

        func mark(_ b: Bool) -> String { b ? "✓" : "✗" }
        print("=== j2kd daemon status ===")
        print("  \(mark(binaryExists)) binary:    \(installedDaemonURL.path)")
        print("  \(mark(plistExists)) plist:     \(launchAgentURL.path)")
        print("  \(mark(serviceLoaded)) launchd:   \(serviceLabel)")
        print("  \(mark(pingReachable)) Mach service reachable (XPC ping)")
        if pingReachable {
            print(String(format: "    PID:    %d", pingPID))
            print(String(format: "    uptime: %.3f s", pingUptimeS))
            print(String(format: "    rtt:    %.3f ms", pingRttMs))
        } else {
            print("")
            print("  Hint: if all four are ✗, run `j2k daemon-install`.")
            print("        If binary+plist are ✓ but launchd/ping are ✗, the")
            print("        plist may have been removed externally — re-install.")
        }
    }

    // MARK: - Help text

    private static func printDaemonInstallHelp() {
        print("""
        Usage: j2k daemon-install [options]

        Install the j2kd XPC daemon so subsequent `j2k decode` invocations
        run at warm-process speed (no Metal cold-start tax per call).

        Options:
          --daemon-binary <path>  Explicit path to j2kd (default: search
                                  same dir as j2k, then .build/release/j2kd)
          --force                 Overwrite an existing installation
          --help                  Show this help

        Install layout (per-user, no sudo required):
          ~/Library/Application Support/J2KSwift/j2kd
          ~/Library/LaunchAgents/com.raster.j2kd.plist

        Build the daemon binary first if not already built:
          swift build -c release --product j2kd
        """)
    }

    private static func printDaemonUninstallHelp() {
        print("""
        Usage: j2k daemon-uninstall [options]

        Remove the j2kd XPC daemon and its launchd plist.

        Options:
          --keep-binary  Leave the j2kd binary in place (only remove plist)
          --help         Show this help
        """)
    }

    private static func printDaemonStatusHelp() {
        print("""
        Usage: j2k daemon-status [options]

        Report the install state of the j2kd daemon.

        Options:
          --json   Output the status as a JSON object
          --help   Show this help
        """)
    }
}

#endif
