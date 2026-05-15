// v10.1-research Phase D1 Phase 0 — MEL per-run-call microbench.
//
// Compares the new scalar C MEL decoder (`j2knhd_mel`) against the
// Swift reference (`HTMELDecoderConformant`) on identical byte
// streams. Reports per-run-call median ns for both paths.
//
// Gate (Phase D1 Phase 0): if scalar C ≥ 10% faster than Swift
// per-run, the structural Swift/C boundary cost on the decoder side
// is real and the rest of the per-block port (VLC reverse-reader,
// MagSgn) is worth committing to. If not, the lever ceiling on
// decode is structural and the multi-week port should not start.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_1_MELMicrobench: XCTestCase {

    private static func makeRandomBytes(count: Int, seed: UInt64) -> [UInt8] {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            bytes[i] = UInt8((state >> 32) & 0xFF)
        }
        return bytes
    }

    private struct Stats {
        let median: Double
        let min: Double
        let p99: Double
    }

    private static func summarise(_ samples: [Double]) -> Stats {
        let sorted = samples.sorted()
        let med = sorted[sorted.count / 2]
        let p99idx = Int(Double(sorted.count - 1) * 0.99)
        return Stats(median: med, min: sorted.first!, p99: sorted[p99idx])
    }

    private static func benchSwift(_ bytes: [UInt8], runsPerStream: Int, streams: Int) -> Stats {
        // Per-stream sample: total time for runsPerStream nextRun()
        // calls. Divided by runsPerStream at print-time for the
        // per-run number. Sample stream `streams` times.
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = HTMELDecoderConformant(bytes: bytes)
            for _ in 0..<runsPerStream {
                _ = dec.nextRun()
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    private static func benchC(_ bytes: [UInt8], runsPerStream: Int, streams: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = j2knhd_mel()
            bytes.withUnsafeBufferPointer { buf in
                j2knhd_mel_init(&dec, buf.baseAddress, buf.count)
                for _ in 0..<runsPerStream {
                    _ = j2knhd_mel_next_run(&dec)
                }
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    func testPhaseD1Phase0_melMicrobench() {
        // Three representative input shapes:
        //   - "sparse" (mostly zero bytes): MEL emits long runs with
        //     state climbing toward 12.
        //   - "dense" (mostly FF bytes): every byte triggers the
        //     unstuff path; refill cost dominates.
        //   - "random uniform": balanced MEL state-machine traversal.
        let sparse  = [UInt8](repeating: 0x00, count: 256)
        let dense   = [UInt8](repeating: 0xFF, count: 256)
        let random  = Self.makeRandomBytes(count: 256, seed: 0xABCDEF1234567890)

        // Warmups (2 untimed full passes for each path).
        for _ in 0..<2 {
            _ = Self.benchSwift(sparse, runsPerStream: 64, streams: 100)
            _ = Self.benchC(sparse, runsPerStream: 64, streams: 100)
        }

        struct Row {
            let label: String
            let swift: Stats
            let c: Stats
            let ratio: Double
        }
        var rows: [Row] = []
        let runs = 64
        let streams = 5_000   // enough samples to make median stable
        for (label, bytes) in [
            ("sparse 256B (00s)", sparse),
            ("dense 256B (FFs)", dense),
            ("random 256B",      random)
        ] {
            let s = Self.benchSwift(bytes, runsPerStream: runs, streams: streams)
            let c = Self.benchC(bytes, runsPerStream: runs, streams: streams)
            rows.append(Row(label: label, swift: s, c: c, ratio: s.median / c.median))
        }

        print("")
        print("=== V10_1_MEL_MICROBENCH_BEGIN ===")
        print("MEL state-machine per-run cost — Swift HTMELDecoderConformant vs scalar C j2knhd_mel")
        print("M2 release, \(runs) nextRun() calls per stream, \(streams) streams sampled per row")
        print("")
        print("| Corpus | Swift median ns/stream | Swift ns/call | C median ns/stream | C ns/call | Speedup |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            let swiftPerCall = r.swift.median / Double(runs)
            let cPerCall = r.c.median / Double(runs)
            let speedup = String(format: "%.2fx", r.ratio)
            print(String(format: "| %@ | %.0f | %.1f | %.0f | %.1f | %@ |",
                         r.label, r.swift.median, swiftPerCall, r.c.median, cPerCall, speedup))
        }
        print("")
        print("Phase D1 Phase 0 gate for MEL: C ≥ 10% faster (ratio ≥ 1.10×).")
        let geoMean = rows.map { $0.ratio }.reduce(1.0, *)
        let nthRoot = pow(geoMean, 1.0 / Double(rows.count))
        print(String(format: "Geometric mean speedup: %.2fx", nthRoot))
        if nthRoot >= 1.10 {
            print("Status: PASS — MEL port clears the per-run gate. Proceed to VLC reverse-reader.")
        } else if nthRoot >= 1.00 {
            print("Status: MARGINAL — MEL port faster but below 10% threshold. The Swift state machine is already tight; defer to the per-block end-to-end gate to decide go/no-go on the full port.")
        } else {
            print("Status: FAIL — Scalar C MEL is not faster than Swift. The decode-side Swift/C boundary cost is not the lever the encoder benefited from. Close Phase D1 here.")
        }
        print("=== V10_1_MEL_MICROBENCH_END ===")
        print("")

        // Sanity: both paths must have produced non-zero timings.
        for r in rows {
            XCTAssertGreaterThan(r.swift.median, 0)
            XCTAssertGreaterThan(r.c.median, 0)
        }
    }
}
#endif
