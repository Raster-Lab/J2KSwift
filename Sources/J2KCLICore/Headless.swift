//
// Headless.swift
// J2KSwift
//
// Headless test-app runner for CI/CD automation.
//

import Foundation
import J2KCore

extension J2KCLI {
    /// Runs the test app in headless mode for CI/CD.
    ///
    /// Usage: `j2k testapp --headless --playlist <name> --output <path> [--format html|json|csv]`
    static func testappCommand(_ args: [String]) async throws {
        let options = parseArguments(args)

        if options["headless"] == nil {
            print("Error: --headless flag is required for the testapp command")
            exit(1)
        }

        guard let config = HeadlessRunner.parseArgs(args) else {
            print("""
            Usage: j2k testapp --headless --playlist <name> --output <path> [--format html|json|csv]

            Available playlists:
              "\(PlaylistPreset.quickSmoke.rawValue)"       — \(PlaylistPreset.quickSmoke.presetDescription)
              "\(PlaylistPreset.fullConformance.rawValue)"  — \(PlaylistPreset.fullConformance.presetDescription)
              "\(PlaylistPreset.performanceSuite.rawValue)" — \(PlaylistPreset.performanceSuite.presetDescription)
              "\(PlaylistPreset.encodeDecodeOnly.rawValue)" — \(PlaylistPreset.encodeDecodeOnly.presetDescription)
            """)
            exit(1)
        }

        print("J2KTestApp Headless Mode")
        print("Playlist : \(config.playlistName)")
        print("Output   : \(config.outputPath)")
        print("Format   : \(config.outputFormat.rawValue)")
        print("")

        let session = TestSession()
        let exitCode = await HeadlessRunner.run(config: config, session: session)

        let results = await session.results
        let passed = results.filter { $0.status == .passed }.count
        let failed = results.filter { $0.status == .failed }.count
        let total = results.count

        print("Results  : \(passed)/\(total) passed, \(failed) failed")
        print("Report   : \(config.outputPath)")

        if exitCode == .failure {
            print("FAILED")
            exit(1)
        } else {
            print("PASSED")
        }
    }
}
