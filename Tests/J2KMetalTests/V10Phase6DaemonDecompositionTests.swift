// V10Phase6DaemonDecompositionTests.swift
//
// v10.0-research Phase 6: decompose the v9.5.0 daemon-encode win into
// "cold-start avoidance" vs "IPC overhead" vs "actual encode time."
//
// Three measurements per fixture, all in one session for apples-to-apples:
//   1. Cold CLI            — Process(j2k encode) per call; pays fork+exec
//                            + library init + encode
//   2. Warm daemon CLI     — Process(j2k encode --daemon); pays fork+exec
//                            + XPC marshal + warm-daemon-side encode
//   3. Warm in-process     — J2KEncoder().encode() in the test process;
//                            pays nothing per call after warmup
//
// Useful deltas:
//   cold CLI − warm in-proc  = total cold-start cost per CLI call
//   warm daemon − warm in-proc = NSXPC fork+exec + marshal overhead
//   cold CLI − warm daemon   = the daemon's headline saving
//
// Run with:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test -c release --filter V10Phase6DaemonDecompositionTests

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10Phase6DaemonDecompositionTests: XCTestCase {

    private let j2kBinary = "/Users/raster/Documents/raster/J2KSwift/.build/release/j2k"
    private let fixtureDir = "/Users/raster/Documents/raster/J2KSwift/Tests/Fixtures/CrossCodec"

    private struct CorpusFixture {
        let label: String
        let stem: String   // filename stem; .pgm appended for source
    }

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "PX 2459×1316", stem: "px_study_001_instance_000001"),
        CorpusFixture(label: "DX 2800×2288", stem: "dx_study_002_instance_000001"),
    ]

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: fixtureDir).appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    /// Runs `j2k encode` as a subprocess. Returns elapsed ms or nil on failure.
    private func subprocessEncodeMs(srcPath: String, dstPath: String,
                                     useDaemon: Bool) throws -> Double? {
        try? FileManager.default.removeItem(atPath: dstPath)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: j2kBinary)
        var args = ["encode", "-i", srcPath, "-o", dstPath,
                    "--htj2k", "--lossless", "--quiet"]
        if useDaemon { args.append("--daemon") }
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        let t0 = Date()
        try proc.run()
        proc.waitUntilExit()
        let elapsed = Date().timeIntervalSince(t0) * 1000.0
        guard proc.terminationStatus == 0,
              FileManager.default.fileExists(atPath: dstPath) else { return nil }
        return elapsed
    }

    func testDecomposeDaemonWin_M2() async throws {
        #if DEBUG
        print("⚠️  Phase 6 in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter V10Phase6DaemonDecompositionTests")
        #endif

        guard FileManager.default.fileExists(atPath: j2kBinary) else {
            print("j2k binary not found at \(j2kBinary) — run `swift build -c release --product j2k` first.")
            return
        }

        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        let runs = 5
        let warmups = 2

        struct Cell {
            let label: String
            let coldCLI: Double
            let warmDaemon: Double
            let warmInProc: Double
        }
        var cells: [Cell] = []

        for fix in Self.corpus {
            let srcPath = "\(fixtureDir)/\(fix.stem).pgm"
            let dstPath = "/tmp/v10_phase6_\(fix.stem).j2k"

            guard FileManager.default.fileExists(atPath: srcPath) else {
                print("missing fixture: \(srcPath); skipping")
                continue
            }
            guard let image = loadPGM16("\(fix.stem).pgm") else {
                print("failed to parse fixture: \(fix.stem); skipping")
                continue
            }

            // === Cold CLI: each run is a fresh j2k subprocess. No
            // explicit warmup is meaningful since each invocation is
            // a fresh process, but we discard the first run to absorb
            // page-cache priming.
            _ = try subprocessEncodeMs(srcPath: srcPath, dstPath: dstPath, useDaemon: false)
            var coldSamples: [Double] = []
            for _ in 0..<runs {
                if let ms = try subprocessEncodeMs(srcPath: srcPath, dstPath: dstPath, useDaemon: false) {
                    coldSamples.append(ms)
                }
            }

            // === Warm daemon CLI: same but with --daemon. Pre-warm
            // the daemon side by issuing 2 calls before timed runs.
            for _ in 0..<warmups {
                _ = try subprocessEncodeMs(srcPath: srcPath, dstPath: dstPath, useDaemon: true)
            }
            var daemonSamples: [Double] = []
            for _ in 0..<runs {
                if let ms = try subprocessEncodeMs(srcPath: srcPath, dstPath: dstPath, useDaemon: true) {
                    daemonSamples.append(ms)
                }
            }

            // === Warm in-process: J2KEncoder reused; 2 warmups
            // discarded; 5 timed runs.
            for _ in 0..<warmups {
                _ = try await encoder.encode(image)
            }
            var inProcSamples: [Double] = []
            for _ in 0..<runs {
                let t0 = Date()
                _ = try await encoder.encode(image)
                inProcSamples.append(Date().timeIntervalSince(t0) * 1000.0)
            }

            func median(_ a: [Double]) -> Double {
                guard !a.isEmpty else { return -1 }
                let s = a.sorted()
                return s[s.count / 2]
            }

            cells.append(Cell(
                label: fix.label,
                coldCLI: median(coldSamples),
                warmDaemon: median(daemonSamples),
                warmInProc: median(inProcSamples)))
        }

        XCTAssertFalse(cells.isEmpty, "No corpus fixtures resolved.")

        print()
        print("=== v10.0 Phase 6 — daemon-encode win decomposition on M2 ===")
        print("    (release, n=\(runs) median per mode, warmups=\(warmups), same-session)")
        print()
        print("## Three-way wall measurement")
        print()
        print("| Fixture | Cold CLI | Warm daemon CLI | Warm in-proc |")
        print("|---|---:|---:|---:|")
        for c in cells {
            print(String(format: "| %@ | %6.2f ms | %6.2f ms | %6.2f ms |",
                c.label, c.coldCLI, c.warmDaemon, c.warmInProc))
        }

        print()
        print("## Decomposition")
        print()
        print("| Fixture | cold − inProc (total cold-start) | daemon − inProc (XPC overhead) | cold − daemon (daemon headline) |")
        print("|---|---:|---:|---:|")
        for c in cells {
            let totalCold = c.coldCLI - c.warmInProc
            let xpcOverhead = c.warmDaemon - c.warmInProc
            let daemonHeadline = c.coldCLI - c.warmDaemon
            print(String(format: "| %@ | %+6.2f ms | %+6.2f ms | %+6.2f ms |",
                c.label, totalCold, xpcOverhead, daemonHeadline))
        }

        print()
        print("Reading the table:")
        print("  - 'total cold-start' is what each fresh j2k CLI invocation pays for")
        print("    library init + Metal touch + per-call setup that the daemon process")
        print("    has already done at launch.")
        print("  - 'XPC overhead' is the cost of going through the daemon path vs")
        print("    encoding directly in your process. Positive = daemon is SLOWER")
        print("    than warm in-proc (so SDK consumers should NOT use the daemon).")
        print("    Negative = daemon is FASTER than warm in-proc (the M4 v9.2 Path B")
        print("    finding suggested this on M4; this Phase 6 measures whether it")
        print("    holds on M2).")
        print("  - 'daemon headline' is what the v9.5.0 release narrative quotes:")
        print("    cold-CLI wall reduction by adopting `j2k --daemon`.")
    }
}
