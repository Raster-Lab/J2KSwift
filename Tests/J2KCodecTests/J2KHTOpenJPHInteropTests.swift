// J2KHTOpenJPHInteropTests.swift
// OpenJPH subprocess interop harness — the skeleton for M7's
// bidirectional cross-codec validation.
//
// Automation rides on two subprocess entry points shipped with
// OpenJPH 0.26+:
//   /opt/homebrew/bin/ojph_compress
//   /opt/homebrew/bin/ojph_expand
//
// Full encode→OpenJPH-decode and OpenJPH-encode→decode flows need
// J2KSwift's codestream pipeline wired to the Part-15 block coder
// first (see docs/HTJ2K_PART15_OPENJPH_VALIDATION.md). Until that
// lands, this test only verifies the tooling is present and the
// OpenJPH self round-trip (which is independent of J2KSwift) works —
// serving as a smoke test for the gate's prerequisites.

import XCTest
import Foundation
@testable import J2KCodec

final class HTOpenJPHInteropTests: XCTestCase {

    private let ojphCompress = "/opt/homebrew/bin/ojph_compress"
    private let ojphExpand   = "/opt/homebrew/bin/ojph_expand"

    /// Skip rather than fail when the OpenJPH CLI is missing — these
    /// tests exist to prove the cross-codec path WHEN OpenJPH is
    /// installed.
    private func skipIfMissing() throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: ojphCompress),
              fm.isExecutableFile(atPath: ojphExpand) else {
            throw XCTSkip("OpenJPH CLI not found — M7 harness skipped")
        }
    }

    /// Write a tiny synthetic 8-bit PGM so tests are self-contained.
    private func writeTinyPGM(to url: URL, width: Int, height: Int) throws {
        var bytes = [UInt8]()
        let header = "P5\n\(width) \(height)\n255\n"
        bytes.append(contentsOf: Array(header.utf8))
        for i in 0..<(width * height) {
            // Smooth gradient — compresses well with both codecs and
            // makes PSNR diffs easy to spot if there's a problem.
            bytes.append(UInt8(i % 256))
        }
        try Data(bytes).write(to: url)
    }

    /// Invoke an executable and return (exit code, stdout+stderr).
    @discardableResult
    private func runProcess(_ path: String, args: [String]) throws
        -> (code: Int32, output: String)
    {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (proc.terminationStatus,
                String(data: data, encoding: .utf8) ?? "")
    }

    /// Gate prerequisite: OpenJPH self round-trip on a 16x16 PGM.
    /// If this fails, the environment is not ready for M7.
    func testOpenJPHSelfRoundTrip() throws {
        try skipIfMissing()
        let tmp = FileManager.default.temporaryDirectory
        let pgmIn = tmp.appendingPathComponent("ojph_in.pgm")
        let j2c   = tmp.appendingPathComponent("ojph.j2c")
        let pgmOut = tmp.appendingPathComponent("ojph_out.pgm")
        defer {
            try? FileManager.default.removeItem(at: pgmIn)
            try? FileManager.default.removeItem(at: j2c)
            try? FileManager.default.removeItem(at: pgmOut)
        }

        try writeTinyPGM(to: pgmIn, width: 16, height: 16)

        let compress = try runProcess(ojphCompress, args: [
            "-i", pgmIn.path, "-o", j2c.path,
            "-num_decomps", "1", "-block_size", "{16,16}",
            "-reversible", "true"
        ])
        XCTAssertEqual(compress.code, 0,
                       "ojph_compress failed: \(compress.output)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: j2c.path))

        let expand = try runProcess(ojphExpand, args: [
            "-i", j2c.path, "-o", pgmOut.path
        ])
        XCTAssertEqual(expand.code, 0,
                       "ojph_expand failed: \(expand.output)")

        // Verify bit-exact round-trip of the reversible path.
        let inData  = try Data(contentsOf: pgmIn)
        let outData = try Data(contentsOf: pgmOut)
        XCTAssertEqual(inData, outData,
            "OpenJPH lossless round-trip should be bit-exact")
    }
}
