// v10.1-research Phase D1 — MagSgn read-path parity oracle.
//
// Compares the scalar C MagSgn decoder (j2knhd_magsgn in
// Sources/J2KCodecNEON/j2knhd_magsgn.c) against the Swift reference
// `HTMagSgnDecoderConformant` (scalar path). Bit-exact byte-by-byte
// parity is the gate.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_1_MagSgnParityTests: XCTestCase {

    private struct ReadPlan {
        let widths: [Int]   // sequence of read(count:) widths, each in [1, 32]
    }

    private static func plan(seed: UInt64, length: Int) -> ReadPlan {
        var state = seed | 1
        var widths: [Int] = []
        widths.reserveCapacity(length)
        for _ in 0..<length {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            let w = Int((state >> 28) & 0x1F) + 1   // 1..32
            widths.append(w)
        }
        return ReadPlan(widths: widths)
    }

    private func swiftReads(_ bytes: [UInt8], plan: ReadPlan) -> [UInt32] {
        // Force scalar path; v7.4 + v8.1 refill paths are bit-exact
        // equivalent per their own A/B tests, but pinning scalar here
        // makes any port mismatch trace to the scalar reference only.
        let prevV74 = HTMagSgnDecoderConformant.neonRefillEnabled
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        HTMagSgnDecoderConformant.neonRefillEnabled = false
        HTMagSgnDecoderConformant.swarRefill8Enabled = false
        defer {
            HTMagSgnDecoderConformant.neonRefillEnabled = prevV74
            HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8
        }
        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        var out: [UInt32] = []
        out.reserveCapacity(plan.widths.count)
        for w in plan.widths {
            out.append(dec.read(count: w))
        }
        return out
    }

    private func cReads(_ bytes: [UInt8], plan: ReadPlan) -> [UInt32] {
        var dec = j2knhd_magsgn()
        var out: [UInt32] = []
        out.reserveCapacity(plan.widths.count)
        bytes.withUnsafeBufferPointer { buf in
            j2knhd_magsgn_init(&dec, buf.baseAddress, buf.count)
            for w in plan.widths {
                out.append(j2knhd_magsgn_read(&dec, Int32(w)))
            }
        }
        return out
    }

    private func assertParity(_ bytes: [UInt8], plan: ReadPlan, label: String) {
        let s = swiftReads(bytes, plan: plan)
        let c = cReads(bytes, plan: plan)
        XCTAssertEqual(s.count, c.count, "\(label): read count mismatch")
        for i in 0..<min(s.count, c.count) {
            XCTAssertEqual(s[i], c[i],
                "\(label): read[\(i)] width=\(plan.widths[i]) Swift=\(s[i]) C=\(c[i]) bytes(prefix16)=\(bytes.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
    }

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

    // MARK: - Dictionary edge cases

    func testParity_empty() {
        // Empty stream: only 0xFF padding is fed.
        assertParity([], plan: Self.plan(seed: 1, length: 32), label: "empty")
    }

    func testParity_allZeros() {
        assertParity([UInt8](repeating: 0x00, count: 32),
                     plan: Self.plan(seed: 2, length: 64), label: "all-zero")
    }

    func testParity_allFF() {
        // Every byte triggers FF-unstuff.
        assertParity([UInt8](repeating: 0xFF, count: 32),
                     plan: Self.plan(seed: 3, length: 64), label: "all-FF")
    }

    func testParity_ffAtEveryPosition() {
        // For each position k in [0..16], a stream where exactly byte k
        // is 0xFF and others are 0x55. Exercises FF-stuff at varying
        // boundaries inside the refill batch.
        for k in 0..<16 {
            var bytes = [UInt8](repeating: 0x55, count: 16)
            bytes[k] = 0xFF
            assertParity(bytes, plan: Self.plan(seed: UInt64(k) &+ 4, length: 32),
                         label: "FF-at-\(k)")
        }
    }

    func testParity_readWidthSweep() {
        // For each width w in [1..32], plan that reads N=64 times at
        // exactly that width.
        let bytes = Self.makeRandomBytes(count: 64, seed: 0xC0FFEE)
        for w in 1...32 {
            let plan = ReadPlan(widths: [Int](repeating: w, count: 64))
            assertParity(bytes, plan: plan, label: "width-\(w)")
        }
    }

    // MARK: - Random sweep

    func testParity_randomBytesRandomWidths_256Trials() {
        for trial in 0..<256 {
            let len = 1 + trial % 64
            let bytes = Self.makeRandomBytes(count: len, seed: UInt64(trial) &* 0xC2B2AE3D27D4EB4F)
            let plan = Self.plan(seed: UInt64(trial) &* 0x9E3779B97F4A7C15, length: 96)
            assertParity(bytes, plan: plan, label: "rand-\(trial)-len\(len)")
        }
    }

    func testParity_largeStreams() {
        for trial in 0..<32 {
            let len = 256 + trial * 16
            let bytes = Self.makeRandomBytes(count: len, seed: UInt64(0x5E5E5E5E5E5E5E5E) &+ UInt64(trial))
            let plan = Self.plan(seed: UInt64(trial) &+ 0xABCDEF, length: 1024)
            assertParity(bytes, plan: plan, label: "large-\(trial)-len\(len)")
        }
    }
}
#endif
