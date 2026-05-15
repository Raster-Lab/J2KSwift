// v10.1-research Phase D1 — MagSgn per-read-call microbench.
//
// Compares the scalar C MagSgn decoder (`j2knhd_magsgn`) against the
// Swift reference (`HTMagSgnDecoderConformant`, scalar path pinned)
// on identical byte streams. Reports per-read median ns for both.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_1_MagSgnMicrobench: XCTestCase {

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

    private static func benchSwift(_ bytes: [UInt8], widths: [Int], streams: Int) -> Stats {
        let prevV74 = HTMagSgnDecoderConformant.neonRefillEnabled
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        HTMagSgnDecoderConformant.neonRefillEnabled = false
        HTMagSgnDecoderConformant.swarRefill8Enabled = false
        defer {
            HTMagSgnDecoderConformant.neonRefillEnabled = prevV74
            HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8
        }
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = HTMagSgnDecoderConformant(bytes: bytes)
            for w in widths {
                _ = dec.read(count: w)
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    private static func benchC(_ bytes: [UInt8], widths: [Int], streams: Int) -> Stats {
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = j2knhd_magsgn()
            bytes.withUnsafeBufferPointer { buf in
                j2knhd_magsgn_init(&dec, buf.baseAddress, buf.count)
                for w in widths {
                    _ = j2knhd_magsgn_read(&dec, Int32(w))
                }
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    private static func makeWidths(count: Int, seed: UInt64) -> [Int] {
        var state = seed | 1
        var widths: [Int] = []
        widths.reserveCapacity(count)
        for _ in 0..<count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            widths.append(Int((state >> 28) & 0x0F) + 1)  // 1..16 width
        }
        return widths
    }

    private static func benchSwiftProduction(_ bytes: [UInt8], widths: [Int], streams: Int) -> Stats {
        // Run with Swift production-default flags (v7.4 4-byte SWAR refill,
        // 8-byte SWAR opt-in OFF). Apples-to-apples against the *current
        // production hot path*, not the scalar reference.
        let prevV74 = HTMagSgnDecoderConformant.neonRefillEnabled
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        HTMagSgnDecoderConformant.neonRefillEnabled = true
        HTMagSgnDecoderConformant.swarRefill8Enabled = false
        defer {
            HTMagSgnDecoderConformant.neonRefillEnabled = prevV74
            HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8
        }
        var samples: [Double] = []
        samples.reserveCapacity(streams)
        for _ in 0..<streams {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var dec = HTMagSgnDecoderConformant(bytes: bytes)
            for w in widths {
                _ = dec.read(count: w)
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - t0))
        }
        return summarise(samples)
    }

    func testPhaseD1_magsgnMicrobench() {
        let sparse  = [UInt8](repeating: 0x00, count: 256)
        let dense   = [UInt8](repeating: 0xFF, count: 256)
        let random  = Self.makeRandomBytes(count: 256, seed: 0xABCDEF1234567890)
        let widths  = Self.makeWidths(count: 64, seed: 0xC0FFEE)
        // Warmups
        for _ in 0..<2 {
            _ = Self.benchSwift(sparse, widths: widths, streams: 200)
            _ = Self.benchC(sparse, widths: widths, streams: 200)
        }
        struct Row {
            let label: String
            let swiftScalar: Stats
            let swiftProd: Stats
            let c: Stats
            let ratioVsScalar: Double
            let ratioVsProd: Double
        }
        var rows: [Row] = []
        let streams = 5_000
        for (label, bytes) in [
            ("sparse 256B (00s)", sparse),
            ("dense 256B (FFs)", dense),
            ("random 256B",      random)
        ] {
            let sScalar = Self.benchSwift(bytes, widths: widths, streams: streams)
            let sProd   = Self.benchSwiftProduction(bytes, widths: widths, streams: streams)
            let c = Self.benchC(bytes, widths: widths, streams: streams)
            rows.append(Row(label: label,
                            swiftScalar: sScalar,
                            swiftProd: sProd,
                            c: c,
                            ratioVsScalar: sScalar.median / c.median,
                            ratioVsProd: sProd.median / c.median))
        }
        print("")
        print("=== V10_1_MAGSGN_MICROBENCH_BEGIN ===")
        print("MagSgn read-path per-call cost — Swift HTMagSgnDecoderConformant (scalar pinned) vs scalar C j2knhd_magsgn")
        print("M2 release, \(widths.count) read() calls per stream (widths 1..16), \(streams) streams sampled per row")
        print("")
        print("| Corpus | Swift scalar ns/stream | scalar ns/call | Swift prod ns/stream | prod ns/call | C ns/stream | C ns/call | C/scalar | C/prod |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let scalarPerCall = r.swiftScalar.median / Double(widths.count)
            let prodPerCall = r.swiftProd.median / Double(widths.count)
            let cPerCall = r.c.median / Double(widths.count)
            print(String(format: "| %@ | %.0f | %.1f | %.0f | %.1f | %.0f | %.1f | %.2fx | %.2fx |",
                         r.label,
                         r.swiftScalar.median, scalarPerCall,
                         r.swiftProd.median, prodPerCall,
                         r.c.median, cPerCall,
                         r.ratioVsScalar, r.ratioVsProd))
        }
        print("")
        let geoMean = rows.map { $0.ratioVsScalar }.reduce(1.0, *)
        let nthRoot = pow(geoMean, 1.0 / Double(rows.count))
        print(String(format: "Geometric mean speedup vs scalar Swift: %.2fx", nthRoot))
        print("Phase D1 Phase 0 gate threshold: ≥ 1.10x.")
        if nthRoot >= 1.10 {
            print("Status: PASS — MagSgn scalar C clears per-call gate.")
        } else if nthRoot >= 1.00 {
            print("Status: MARGINAL — MagSgn faster but below 10%. Reserve judgement for the full per-block end-to-end gate.")
        } else {
            print("Status: FAIL — MagSgn scalar C not faster than scalar Swift.")
        }
        print("")
        print("Note: Swift production default is v7.4 4-byte SWAR refill (`neonRefillEnabled = true`),")
        print("not the scalar path pinned here. Swift production may be 1.05-1.49x faster than the scalar")
        print("baseline above. The C path will need its own SWAR retrofit to beat Swift production —")
        print("this microbench measures the scalar-vs-scalar lever, NOT the production decode wall.")
        print("=== V10_1_MAGSGN_MICROBENCH_END ===")
        print("")
        for r in rows {
            XCTAssertGreaterThan(r.swiftScalar.median, 0)
            XCTAssertGreaterThan(r.swiftProd.median, 0)
            XCTAssertGreaterThan(r.c.median, 0)
        }
    }
}
#endif
