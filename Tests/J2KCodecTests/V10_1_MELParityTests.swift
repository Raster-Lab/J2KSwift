// v10.1-research Phase D1 Phase 0 — MEL state-machine parity oracle.
//
// Compares the new scalar C MEL decoder (j2knhd_mel in
// Sources/J2KCodecNEON/j2knhd_mel.c) against the Swift reference
// `HTMELDecoderConformant` over random byte streams and dictionary
// edge cases. Bit-exact byte-by-byte parity is the gate for proceeding
// past Phase 0 on this state machine.
//
// Companion to V10_1_DecodeBlockMicrobench (which establishes the
// Swift baseline) and V10_1_DECODE_C_PORT_PROBE.md (which defines the
// overall ≥10% per-block speedup gate).

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_1_MELParityTests: XCTestCase {

    /// Extract `count` packed run values from `bytes` using the Swift
    /// reference decoder.
    private func swiftRuns(_ bytes: [UInt8], count: Int) -> [Int] {
        var dec = HTMELDecoderConformant(bytes: bytes)
        var runs: [Int] = []
        runs.reserveCapacity(count)
        for _ in 0..<count {
            runs.append(dec.nextRun())
        }
        return runs
    }

    /// Extract `count` packed run values from `bytes` using the C
    /// scalar decoder.
    private func cRuns(_ bytes: [UInt8], count: Int) -> [Int64] {
        var dec = j2knhd_mel()
        bytes.withUnsafeBufferPointer { buf in
            j2knhd_mel_init(&dec, buf.baseAddress, buf.count)
        }
        var runs: [Int64] = []
        runs.reserveCapacity(count)
        for _ in 0..<count {
            runs.append(j2knhd_mel_next_run(&dec))
        }
        return runs
    }

    private func assertParity(_ bytes: [UInt8], count: Int, label: String) {
        let s = swiftRuns(bytes, count: count)
        let c = cRuns(bytes, count: count)
        XCTAssertEqual(s.count, c.count, "\(label): run count mismatch")
        for i in 0..<min(s.count, c.count) {
            XCTAssertEqual(Int64(s[i]), c[i],
                "\(label): run[\(i)] Swift=\(s[i]) C=\(c[i]) bytes=\(bytes.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
    }

    // MARK: - Dictionary edge cases

    func testParity_emptyBytes() {
        assertParity([], count: 16, label: "empty")
    }

    func testParity_allZeros() {
        assertParity([UInt8](repeating: 0x00, count: 16), count: 32, label: "all-zero")
    }

    func testParity_allFF() {
        // All-0xFF triggers the unstuff path on every byte. Exercise
        // the FF-stuff rule end-to-end.
        assertParity([UInt8](repeating: 0xFF, count: 16), count: 32, label: "all-FF")
    }

    func testParity_singleByte() {
        for b in [UInt8](0...255) {
            assertParity([b], count: 8, label: String(format: "single-%02x", b))
        }
    }

    func testParity_zeroFFAlternating() {
        var bytes: [UInt8] = []
        for _ in 0..<32 {
            bytes.append(0x00)
            bytes.append(0xFF)
        }
        assertParity(bytes, count: 64, label: "00/FF alternating")
    }

    func testParity_FFZeroAlternating() {
        var bytes: [UInt8] = []
        for _ in 0..<32 {
            bytes.append(0xFF)
            bytes.append(0x00)
        }
        assertParity(bytes, count: 64, label: "FF/00 alternating")
    }

    // MARK: - Random sweep

    private func makeRandomBytes(count: Int, seed: UInt64) -> [UInt8] {
        var state = seed | 1
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            state &*= 6364136223846793005
            state &+= 1442695040888963407
            bytes[i] = UInt8((state >> 32) & 0xFF)
        }
        return bytes
    }

    func testParity_randomSweep_256Trials() {
        for trial in 0..<256 {
            let len = 1 + trial % 64    // 1..64 bytes per trial
            let bytes = makeRandomBytes(count: len, seed: UInt64(trial) &* 0xC2B2AE3D27D4EB4F)
            assertParity(bytes, count: 64, label: "rand-\(trial)-len\(len)")
        }
    }

    /// Larger random streams stressing the refill loop multiple times.
    func testParity_randomSweep_largeStreams() {
        for trial in 0..<64 {
            let len = 128 + trial * 8
            let bytes = makeRandomBytes(count: len, seed: UInt64(0x9E3779B97F4A7C15) &+ UInt64(trial))
            assertParity(bytes, count: 512, label: "rand-large-\(trial)-len\(len)")
        }
    }

    // MARK: - Per-byte sweep (deterministic coverage of single-byte streams)

    func testParity_singleByteWithEvery2ByteSuffix() {
        // 256 single bytes × 4 different 1-byte suffixes (00, 55, AA, FF).
        // Exercises FF-unstuff transitions at the second byte.
        for first in [UInt8](0...255) {
            for second in [UInt8]([0x00, 0x55, 0xAA, 0xFF]) {
                let bytes: [UInt8] = [first, second]
                assertParity(bytes, count: 12,
                             label: String(format: "pair-%02x-%02x", first, second))
            }
        }
    }
}
#endif
