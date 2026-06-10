//
// JPIPServer.swift
// J2KSwift
//
/// JPIP server command — start a JPIP streaming server for JPEG 2000 images.

import Foundation
import J2KCore
import J2KCodec
import JPIP

extension J2KCLI {

    /// JPIP server command: start a JPIP streaming server.
    static func jpipServerCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printJPIPServerHelp()
            return
        }

        let port = Int(options["port"] ?? "8080") ?? 8080
        let host = options["host"] ?? "0.0.0.0"
        let verbose = options["verbose"] != nil
        let quiet = options["quiet"] != nil

        let maxSessions = Int(options["max-sessions"] ?? "10") ?? 10
        let sessionTimeout = Int(options["session-timeout"] ?? "300") ?? 300

        // Determine data source
        let dataDir = options["data-dir"]
        let singleFile = options["single-file"]

        guard dataDir != nil || singleFile != nil else {
            print("Error: Specify --data-dir DIR or --single-file PATH")
            exit(1)
        }

        if !quiet {
            print("Starting JPIP Server...")
            print("  Host:            \(host)")
            print("  Port:            \(port)")
            print("  Max Sessions:    \(maxSessions)")
            print("  Session Timeout: \(sessionTimeout)s")
        }

        // Build server configuration
        let serverConfig = JPIPServer.Configuration(
            maxClients: maxSessions,
            sessionTimeout: TimeInterval(sessionTimeout)
        )

        let server = JPIPServer(port: port, configuration: serverConfig)

        // Register images
        if let dir = dataDir {
            let fm = FileManager.default
            let files = try fm.contentsOfDirectory(atPath: dir)
            let j2kFiles = files.filter { name in
                let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
                return ext == "j2k" || ext == "jp2" || ext == "jpx" || ext == "jph"
            }

            for filename in j2kFiles.sorted() {
                let path = (dir as NSString).appendingPathComponent(filename)
                let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
                let url = URL(fileURLWithPath: path)
                try await server.registerImage(name: name, at: url)
                if verbose { print("  Registered: \(name) (\(filename))") }
            }

            if !quiet { print("  Images registered: \(j2kFiles.count)") }
        } else if let file = singleFile {
            let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
            let url = URL(fileURLWithPath: file)
            try await server.registerImage(name: name, at: url)
            if !quiet { print("  Serving: \(name)") }
        }

        if !quiet {
            print("")
            print("JPIP server listening on \(host):\(port)")
            print("Press Ctrl+C to stop")
        }

        // Start the server
        try await server.start()

        // Keep running until interrupted
        // Set up signal handling for graceful shutdown
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        sigintSource.setEventHandler {
            if !quiet { print("\nShutting down JPIP server...") }
            Task {
                try? await server.stop()
                if !quiet { print("Server stopped.") }
                exit(0)
            }
        }
        sigintSource.resume()

        let sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        sigTermSource.setEventHandler {
            if !quiet { print("\nShutting down JPIP server...") }
            Task {
                try? await server.stop()
                exit(0)
            }
        }
        sigTermSource.resume()

        // Keep the server alive
        while true {
            try await Task.sleep(for: .seconds(60))

            if verbose {
                let stats = await server.getStatistics()
                let sessions = await server.getActiveSessionCount()
                print("  Active sessions: \(sessions), Stats: \(stats)")
            }
        }
    }

    // MARK: - Help

    private static func printJPIPServerHelp() {
        print("""
        j2k jpip server - Start a JPIP streaming server

        USAGE:
            j2k jpip server [options]

        OPTIONS:
            --port N                    Listening port (default: 8080)
            --host ADDRESS              Bind address (default: 0.0.0.0)
            --data-dir DIR              Directory of JPEG 2000 files to serve
            --single-file PATH          Serve a single JPEG 2000 file
            --max-sessions N            Maximum concurrent sessions (default: 10)
            --session-timeout SECONDS   Session idle timeout (default: 300)
            --transport http|websocket  Transport protocol
            --tls-cert PATH             TLS certificate file
            --tls-key PATH              TLS private key file
            --access-log PATH           Access log file
            --mode 2d|3d                Serving mode (default: 2d)
            --verbose                   Verbose output
            --quiet                     Suppress output

        EXAMPLES:
            j2k jpip server --data-dir ./images/ --port 8080
            j2k jpip server --single-file image.jp2 --port 9090
            j2k jpip server --data-dir ./images/ --max-sessions 20 --verbose
        """)
    }
}

// MARK: - JPIP Server Configuration (local helper)

/// Configuration for the JPIP server.
struct JPIPServerConfiguration: Sendable {
    let port: Int
    let maxSessions: Int
    let sessionTimeout: TimeInterval

    init(port: Int = 8080, maxSessions: Int = 10, sessionTimeout: TimeInterval = 300) {
        self.port = port
        self.maxSessions = maxSessions
        self.sessionTimeout = sessionTimeout
    }
}
