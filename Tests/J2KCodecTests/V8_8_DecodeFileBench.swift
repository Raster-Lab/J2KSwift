// V8_8_DecodeFileBench.swift
//
// v8.8 (research) — A/B for the new decodeFile API vs the
// existing Data-based decode call. The decomposition probe
// (V8_8_DaemonOverheadDecomposition) showed 6.29 ms daemon
// overhead on DX, 99% of it in bytes-transfer + serialisation.
// decodeFile passes file paths instead of Data; daemon reads
// via mmap and writes the result directly to disk.

#if os(macOS)

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KDaemonClient

final class V8_8_DecodeFileBench: XCTestCase {

    @inline(never)
    private func errlog(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }

    func testDecodeFile_vs_DecodeData_DX() async throws {
        let codestreamPath = "/tmp/v8_1_2_bench/dx_study_002_instance_000001.j2k"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: codestreamPath),
                          "DX codestream missing; run cross-codec encode first")
        let outputPath = "/tmp/v8_8_decodeFile_out.bin"

        let codestreamData = try Data(contentsOf: URL(fileURLWithPath: codestreamPath))

        let client = J2KDaemonClient()
        let isAvail = await client.isAvailable
        XCTAssertTrue(isAvail, "daemon must be reachable")

        // Pre-warm daemon-side Metal session AND the new decodeFile path.
        for _ in 0..<3 {
            _ = try? await client.decode(codestreamData)
            _ = try? await client.decodeFile(codestreamPath: codestreamPath, outputPath: outputPath)
        }

        let runs = 12

        // Path A: existing decode(Data) — Data over XPC both ways.
        var dataSamples: [Double] = []
        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            _ = try await client.decode(codestreamData)
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            dataSamples.append(Double(dt) / 1_000_000.0)
        }
        dataSamples.sort()

        // Path B: new decodeFile(path:path:) — paths over XPC.
        var fileSamples: [Double] = []
        for _ in 0..<runs {
            let t0 = DispatchTime.now()
            _ = try await client.decodeFile(codestreamPath: codestreamPath, outputPath: outputPath)
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            fileSamples.append(Double(dt) / 1_000_000.0)
        }
        fileSamples.sort()

        // In-process baseline.
        var inProcessSamples: [Double] = []
        for _ in 0..<6 {
            let t0 = DispatchTime.now()
            let dec = J2KDecoder()
            _ = try await dec.decode(codestreamData)
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            inProcessSamples.append(Double(dt) / 1_000_000.0)
        }
        inProcessSamples.sort()

        let dataMed = dataSamples[runs / 2]
        let fileMed = fileSamples[runs / 2]
        let inProcMed = inProcessSamples[inProcessSamples.count / 2]

        errlog("")
        errlog("=== v8.8 — decodeFile vs decode(Data) on DX 2800x2288 ===")
        errlog(String(format: "  decode(Data) [old]:        median %.3f ms (n=%d)", dataMed, runs))
        errlog(String(format: "  decodeFile(path:) [new]:   median %.3f ms (n=%d)", fileMed, runs))
        errlog(String(format: "  in-process baseline:       median %.3f ms (n=10)", inProcMed))
        errlog("")
        errlog(String(format: "  Δ (decode - decodeFile):     %+.3f ms savings", dataMed - fileMed))
        errlog(String(format: "  Δ (decodeFile - in-process): %+.3f ms remaining overhead", fileMed - inProcMed))
        errlog("")
        if fileMed < dataMed {
            errlog("  ⇒ decodeFile is FASTER than decode(Data) by \(String(format: "%.2f", dataMed - fileMed)) ms")
        } else {
            errlog("  ⇒ decodeFile DID NOT win.")
        }

        // Sanity-check: the file at outputPath has the expected size.
        // DX 2800x2288 at 12-bit unsigned → 2 bytes/sample (UInt16-equivalent
        // when written via J2KComponent.data).
        let expectedBytes = 2800 * 2288 * 2  // 12.8 MB
        let actualBytes = (try FileManager.default.attributesOfItem(atPath: outputPath)[.size] as? Int) ?? 0
        XCTAssertEqual(actualBytes, expectedBytes, "outputPath should contain DX-sized pixel data")

        await client.close()
    }
}

#endif
