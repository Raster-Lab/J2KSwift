//
// JPIPClient.swift
// J2KSwift
//
/// JPIP client command — connect to a JPIP server and retrieve images.

import Foundation
import J2KCore
import J2KCodec
@preconcurrency import JPIP

extension J2KCLI {

    /// JPIP client command: connect to a JPIP server and retrieve image data.
    static func jpipClientCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["help"] != nil {
            printJPIPClientHelp()
            return
        }

        guard let serverURL = options["server"] else {
            print("Error: Missing required argument: --server URL")
            exit(1)
        }

        guard let target = options["target"] else {
            print("Error: Missing required argument: --target NAME")
            exit(1)
        }

        let verbose = options["verbose"] != nil
        let quiet = options["quiet"] != nil
        let jsonOutput = options["json"] != nil
        let outputPath = options["o"] ?? options["output"]
        let interactive = options["interactive"] != nil

        // Parse region
        let region: (x: Int, y: Int, w: Int, h: Int)?
        if let regionStr = options["region"] {
            let parts = regionStr.split(separator: ",").compactMap { Int($0) }
            if parts.count == 4 {
                region = (parts[0], parts[1], parts[2], parts[3])
            } else {
                print("Error: Invalid region format. Expected x,y,w,h")
                exit(1)
            }
        } else {
            region = nil
        }

        let resolutionLevel = options["resolution-level"].flatMap { Int($0) }
        let qualityLayers = options["quality-layers"].flatMap { Int($0) }
        let _ = options["progressive"] != nil

        if !quiet {
            print("JPIP Client")
            print("  Server: \(serverURL)")
            print("  Target: \(target)")
        }

        // Create JPIP client
        guard let url = URL(string: serverURL) else {
            print("Error: Invalid server URL: \(serverURL)")
            exit(1)
        }

        let client = JPIPClient(serverURL: url)
        let startTime = Date()

        // Create session
        if verbose { print("  Creating session...") }
        _ = try await client.createSession(target: target)
        let sessionTime = Date().timeIntervalSince(startTime)
        if verbose { print("  Session created in \(String(format: "%.1f", sessionTime * 1000)) ms") }

        if interactive {
            // Interactive mode
            try await runInteractiveMode(client: client, target: target, quiet: quiet)
        } else {
            // Single request mode
            let requestStart = Date()

            let receivedImage: J2KImage
            if let r = region {
                if verbose { print("  Requesting region: \(r.x),\(r.y) \(r.w)×\(r.h)") }
                receivedImage = try await client.requestRegion(
                    imageID: target,
                    region: (x: r.x, y: r.y, width: r.w, height: r.h)
                )
            } else if let level = resolutionLevel {
                if verbose { print("  Requesting resolution level: \(level)") }
                receivedImage = try await client.requestResolutionLevel(
                    imageID: target,
                    level: level,
                    layers: qualityLayers
                )
            } else if let layers = qualityLayers {
                if verbose { print("  Requesting \(layers) quality layers") }
                receivedImage = try await client.requestProgressiveQuality(
                    imageID: target,
                    upToLayers: layers
                )
            } else {
                if verbose { print("  Requesting full image...") }
                receivedImage = try await client.requestImage(imageID: target)
            }

            let requestTime = Date().timeIntervalSince(requestStart)
            let totalTime = Date().timeIntervalSince(startTime)

            // Save if output path is provided
            if let outPath = outputPath {
                try saveImage(receivedImage, to: outPath)
                if verbose { print("  Saved to: \(outPath)") }
            }

            // Estimate received size from component data
            let receivedBytes = receivedImage.components.reduce(0) { $0 + $1.data.count }

            if jsonOutput {
                let result: [String: Any] = [
                    "server": serverURL,
                    "target": target,
                    "width": receivedImage.width,
                    "height": receivedImage.height,
                    "components": receivedImage.componentCount,
                    "bytesReceived": receivedBytes,
                    "timing": [
                        "session": sessionTime,
                        "request": requestTime,
                        "total": totalTime
                    ]
                ]
                printJSON(result)
            } else if !quiet {
                print("  Image:   \(receivedImage.width)×\(receivedImage.height), \(receivedImage.componentCount) components")
                print("  Session time:  \(String(format: "%.1f", sessionTime * 1000)) ms")
                print("  Request time:  \(String(format: "%.1f", requestTime * 1000)) ms")
                print("  Total time:    \(String(format: "%.1f", totalTime * 1000)) ms")
            }

            // Close session
            try await client.close()
        }
    }

    // MARK: - Interactive Mode

    private static func runInteractiveMode(
        client: JPIPClient,
        target: String,
        quiet: Bool
    ) async throws {
        if !quiet {
            print("")
            print("Interactive JPIP Client")
            print("Commands: region x,y,w,h | zoom N | quality N | save PATH | info | quit")
            print("")
        }

        while true {
            print("> ", terminator: "")
            guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else { break }
            let parts = line.split(separator: " ").map { String($0) }
            guard let cmd = parts.first else { continue }

            switch cmd {
            case "quit", "exit", "q":
                try await client.close()
                if !quiet { print("Session closed.") }
                return

            case "region":
                let coords = parts.dropFirst().joined(separator: " ").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if coords.count == 4 {
                    let image = try await client.requestRegion(
                        imageID: target,
                        region: (x: coords[0], y: coords[1], width: coords[2], height: coords[3])
                    )
                    let size = image.components.reduce(0) { $0 + $1.data.count }
                    print("  Received \(image.width)×\(image.height) image (\(formatBytes(size)))")
                } else {
                    print("  Usage: region x,y,w,h")
                }

            case "quality":
                if let layers = parts.dropFirst().first.flatMap({ Int($0) }) {
                    let image = try await client.requestProgressiveQuality(
                        imageID: target,
                        upToLayers: layers
                    )
                    let size = image.components.reduce(0) { $0 + $1.data.count }
                    print("  Received \(image.width)×\(image.height) (\(layers) quality layers, \(formatBytes(size)))")
                } else {
                    print("  Usage: quality N")
                }

            case "zoom":
                if let level = parts.dropFirst().first.flatMap({ Int($0) }) {
                    let image = try await client.requestResolutionLevel(
                        imageID: target,
                        level: level
                    )
                    let size = image.components.reduce(0) { $0 + $1.data.count }
                    print("  Received \(image.width)×\(image.height) (level \(level), \(formatBytes(size)))")
                } else {
                    print("  Usage: zoom N")
                }

            case "save":
                if let path = parts.dropFirst().first {
                    let image = try await client.requestImage(imageID: target)
                    try saveImage(image, to: path)
                    print("  Saved to: \(path)")
                } else {
                    print("  Usage: save PATH")
                }

            case "info":
                // Request image to show basic info (metadata API returns non-Sendable [String: Any])
                let image = try await client.requestImage(imageID: target)
                print("  Size: \(image.width)×\(image.height)")
                print("  Components: \(image.componentCount)")
                print("  Bit depth: \(image.components.first?.bitDepth ?? 0)")
                let totalBytes = image.components.reduce(0) { $0 + $1.data.count }
                print("  Data size: \(formatBytes(totalBytes))")

            case "help":
                print("  Commands:")
                print("    region x,y,w,h   Request a specific region")
                print("    zoom N            Request resolution level N")
                print("    quality N         Request N quality layers")
                print("    save PATH         Download full image and save")
                print("    info              Request image metadata")
                print("    quit              Close session and exit")

            default:
                print("  Unknown command: \(cmd). Type 'help' for commands.")
            }
        }
    }

    // MARK: - Help

    private static func printJPIPClientHelp() {
        print("""
        j2k jpip client - Connect to a JPIP server

        USAGE:
            j2k jpip client --server URL --target NAME [options]

        OPTIONS:
            --server URL                JPIP server URL
            --target NAME               Target image name on server
            -o, --output PATH           Output file for decoded image
            --region x,y,w,h            Request specific region
            --resolution-level N        Request resolution level
            --quality-layers N          Request quality layers
            --progressive               Progressive rendering
            --progressive-dir DIR       Directory for progressive frames
            --max-bandwidth BPS         Bandwidth throttle
            --session-type TYPE         stateless|stateful
            --transport PROTO           http|websocket
            --interactive               Interactive mode
            --verbose                   Verbose output
            --quiet                     Suppress output
            --json                      JSON output

        EXAMPLES:
            j2k jpip client --server http://localhost:8080 --target image.jp2 -o output.pgm
            j2k jpip client --server http://server:8080 --target image --region 0,0,256,256
            j2k jpip client --server http://server:8080 --target image --interactive
        """)
    }
}
