// V8_8_DaemonOverheadDecomposition.swift
//
// v8.8 (research) — decompose the j2kd daemon's warm-cache overhead.
// Cross-codec testing showed daemon DX decode at +2.34 ms vs
// in-process on warm-cache CLI loops (paired N=20). This bench
// isolates each component of that overhead so we can target the fix.
//
// Components measured:
//   1. NSXPCConnection setup (init J2KDaemonClient)
//   2. Empty XPC roundtrip (`ping` — daemon does no work)
//   3. Small-payload XPC send (~1 KB codestream input via decode)
//   4. Large-payload XPC receive (DX ~25 MB pixelData)
//   5. Full DX decode end-to-end
//
// Decision rule:
//   - If connection setup dominates → fix: amortise via shared
//     client across CLI sub-commands (one process-wide client)
//   - If receive payload dominates → fix: shared-memory result
//     transfer (mmap a temp file path instead of Data)
//   - If send payload dominates → fix: file-path based protocol

#if os(macOS)

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec
@testable import J2KDaemonClient
@testable import J2KDaemonProtocol

final class V8_8_DaemonOverheadDecomposition: XCTestCase {

    @inline(never)
    private func errlog(_ s: String) {
        FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    }

    private static func runs<T>(_ count: Int, _ body: () async throws -> T) async rethrows -> [Double] {
        var samples: [Double] = []
        for _ in 0..<count {
            let t0 = DispatchTime.now()
            _ = try await body()
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            samples.append(Double(dt) / 1_000_000.0)
        }
        return samples
    }

    func testDecomposeDaemonOverhead() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/v8_1_2_bench/dx_study_002_instance_000001.j2k"),
                          "DX codestream missing; run cross-codec encode first")

        let codestreamData = try Data(contentsOf: URL(fileURLWithPath: "/tmp/v8_1_2_bench/dx_study_002_instance_000001.j2k"))
        errlog("")
        errlog("=== v8.8 Phase 0 — j2kd daemon overhead decomposition ===")
        errlog("DX codestream: \(codestreamData.count) bytes (\(String(format: "%.2f", Double(codestreamData.count) / 1024 / 1024)) MB)")
        errlog("")

        // Component 1: NSXPCConnection setup
        var ctorSamples: [Double] = []
        for _ in 0..<10 {
            let t0 = DispatchTime.now()
            let client = J2KDaemonClient()
            let avail = await client.isAvailable
            await client.close()
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            XCTAssertTrue(avail, "daemon must be reachable for this bench")
            ctorSamples.append(Double(dt) / 1_000_000.0)
        }
        ctorSamples.sort()
        let ctorMedian = ctorSamples[ctorSamples.count / 2]
        errlog(String(format: "1. J2KDaemonClient init+isAvailable+close: median %.3f ms (n=10)", ctorMedian))

        // Persistent client for the rest.
        let client = J2KDaemonClient()
        let isAvail = await client.isAvailable
        XCTAssertTrue(isAvail, "daemon must be reachable")

        // Pre-warm a few decode calls so daemon-side Metal session is fully warm.
        for _ in 0..<3 {
            _ = try? await client.decode(codestreamData)
        }

        // Component 2: Empty XPC roundtrip (ping)
        let pingSamples = try await Self.runs(30) {
            try await client.ping(requestID: UUID().uuidString)
        }
        let pingSorted = pingSamples.sorted()
        let pingMedian = pingSorted[pingSorted.count / 2]
        errlog(String(format: "2. ping XPC empty roundtrip:               median %.3f ms (n=30)", pingMedian))

        // Component 3+4+5: Full DX decode. Subtract pingMedian to estimate
        // bytes-transfer + daemon-side decode wall.
        let decodeSamples = try await Self.runs(20) {
            _ = try await client.decode(codestreamData)
        }
        let decodeSorted = decodeSamples.sorted()
        let decodeMedian = decodeSorted[decodeSorted.count / 2]
        errlog(String(format: "3. Full daemon decode (DX 2800x2288):      median %.3f ms (n=20)", decodeMedian))
        errlog("")

        // Extra: same decode but loaded into J2KDecoder directly to get the
        // pure compute reference.
        let inProcessSamples = try await Self.runs(10) {
            let dec = J2KDecoder()
            return try await dec.decode(codestreamData)
        }
        let inProcessSorted = inProcessSamples.sorted()
        let inProcessMedian = inProcessSorted[inProcessSorted.count / 2]
        errlog(String(format: "4. In-process J2KDecoder.decode reference: median %.3f ms (n=10)", inProcessMedian))
        errlog("")

        let xpcOverhead = decodeMedian - inProcessMedian
        errlog(String(format: "Daemon overhead (decode_via_daemon - decode_in_process): %+.3f ms", xpcOverhead))
        errlog(String(format: "  - of which empty-XPC roundtrip:                           %.3f ms (\(String(format: "%.0f%%", pingMedian / xpcOverhead * 100)))", pingMedian))
        let bytesTransfer = xpcOverhead - pingMedian
        errlog(String(format: "  - of which bytes-transfer + serialisation (residual):    %.3f ms", bytesTransfer))
        errlog("")
        errlog("Comparison vs CLI warm-cache paired A/B (cross-codec report):")
        errlog("  - CLI in-process:  72.10 ms median")
        errlog("  - CLI via daemon:  74.44 ms median")
        errlog("  - CLI Δ overhead:  +2.34 ms")
        errlog("")
        errlog("If in-process J2KDecoder.decode and decoded daemon decode show similar")
        errlog("compute time, then the entire CLI delta is dominated by per-process")
        errlog("connection setup (component 1). If daemon decode is slower, then daemon-side")
        errlog("Metal session warmth is suspect.")

        await client.close()
    }
}

#endif
