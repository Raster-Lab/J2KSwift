// v10.1-research Phase D1 — VLC reverse-reader parity oracle.
//
// Compares the scalar C VLC reverse-reader (`j2knhd_vlc` in
// Sources/J2KCodecNEON/j2knhd_vlc.c) against the Swift reference
// `VLCReverseReader` driven through `VLCReverseReaderTesting`'s
// new `runScalarReadPlan` / `runScalarPeekConsumePlan` helpers.
//
// The Swift reference is the SCALAR refill path (production on
// v9.5.2). The v7.4 SWAR `refillBatched` is bit-exact equivalent
// and opt-in; the C port mirrors only the scalar path.

#if os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
import J2KCodecNEON

final class V10_1_VLCParityTests: XCTestCase {

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

    // MARK: - read() parity

    private func cReadPlan(_ bytes: [UInt8], scup: Int, widths: [Int]) -> [UInt64] {
        var dec = j2knhd_vlc()
        bytes.withUnsafeBufferPointer { buf in
            j2knhd_vlc_init(&dec, buf.baseAddress, buf.count, Int32(scup))
        }
        var out: [UInt64] = []
        out.reserveCapacity(widths.count)
        for w in widths {
            out.append(j2knhd_vlc_read(&dec, Int32(w)))
        }
        return out
    }

    private func assertReadParity(
        _ bytes: [UInt8], scup: Int, widths: [Int], label: String
    ) {
        let s = VLCReverseReaderTesting.runScalarReadPlan(
            bytes: bytes, scup: scup, widths: widths)
        let c = cReadPlan(bytes, scup: scup, widths: widths)
        XCTAssertEqual(s.count, c.count, "\(label): read count mismatch")
        for i in 0..<min(s.count, c.count) {
            XCTAssertEqual(s[i], c[i],
                "\(label): read[\(i)] width=\(widths[i]) Swift=\(String(s[i], radix: 16)) C=\(String(c[i], radix: 16)) bytes(prefix12)=\(bytes.prefix(12).map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
    }

    // MARK: - peek+consume parity

    private func cPeekConsumePlan(
        _ bytes: [UInt8], scup: Int, pairs: [(Int, Int)]
    ) -> [UInt64] {
        var dec = j2knhd_vlc()
        bytes.withUnsafeBufferPointer { buf in
            j2knhd_vlc_init(&dec, buf.baseAddress, buf.count, Int32(scup))
        }
        var out: [UInt64] = []
        out.reserveCapacity(pairs.count)
        for (peekBits, consumeBits) in pairs {
            out.append(j2knhd_vlc_peek(&dec, Int32(peekBits)))
            j2knhd_vlc_consume(&dec, Int32(consumeBits))
        }
        return out
    }

    private func assertPeekConsumeParity(
        _ bytes: [UInt8], scup: Int, pairs: [(Int, Int)], label: String
    ) {
        let s = VLCReverseReaderTesting.runScalarPeekConsumePlan(
            bytes: bytes, scup: scup, pairs: pairs)
        let c = cPeekConsumePlan(bytes, scup: scup, pairs: pairs)
        XCTAssertEqual(s.count, c.count, "\(label): pair count mismatch")
        for i in 0..<min(s.count, c.count) {
            XCTAssertEqual(s[i], c[i],
                "\(label): pair[\(i)] peek=\(pairs[i].0) consume=\(pairs[i].1) Swift=\(String(s[i], radix: 16)) C=\(String(c[i], radix: 16))")
        }
    }

    // MARK: - Dictionary edge cases — read

    func testParity_emptyScup2() {
        // scup=2 → byte_idx starts at 0, valid. Empty buffer is
        // technically invalid (we'd read past it); we test the
        // minimum scup=3 instead with 2-byte buffer.
        assertReadParity([0x00, 0x00, 0x00], scup: 3,
                         widths: [4, 4, 4, 4, 8, 8, 16],
                         label: "scup-3-zeros")
    }

    func testParity_allZeros() {
        // Init consumes high nibble of bytes[scup-2] = 0x00 → 0 bits.
        // Refill drains zero bytes. Every read returns 0.
        let bytes = [UInt8](repeating: 0x00, count: 24)
        assertReadParity(bytes, scup: 16,
                         widths: [1, 2, 4, 8, 12, 16, 24, 32],
                         label: "all-zero scup=16")
    }

    func testParity_allFF() {
        // Init consumes high nibble of 0xFF: high_nibble = 0xF, top 3
        // bits == 0x7 → t=1, val = 0xF & 0x7 = 0x7, tmp=0x7, bits=3,
        // unstuff = (0x7 > 0x8) = false. Then refill reads 0xFF bytes
        // with FF-stuff transitions.
        let bytes = [UInt8](repeating: 0xFF, count: 24)
        assertReadParity(bytes, scup: 16,
                         widths: [1, 2, 4, 8, 12, 16, 24, 32],
                         label: "all-FF scup=16")
    }

    func testParity_8FBoundary() {
        // 0x8F is the boundary — exactly 0x8F does NOT trigger
        // unstuff (test is byte > 0x8F). 0x90 does. Exercise both.
        let bytes: [UInt8] = [0x8F, 0x90, 0x91, 0x7F, 0xFF, 0xFF, 0x00, 0x55, 0xAA, 0xCC, 0x33, 0x44]
        assertReadParity(bytes, scup: 10,
                         widths: [1, 2, 3, 4, 5, 6, 7, 8, 10, 16, 20, 32],
                         label: "8F-boundary")
    }

    func testParity_FFStuffPattern() {
        // Specific pattern that exercises the (prior>0x8F + cur 0x7F)
        // FF-stuff trigger.
        let bytes: [UInt8] = [0xFF, 0x7F, 0xFF, 0xFF, 0x91, 0x7F, 0x55, 0x80, 0x8F, 0x90, 0xFF, 0xFF]
        assertReadParity(bytes, scup: 10,
                         widths: [1, 2, 4, 7, 8, 13, 16, 24, 32],
                         label: "FF-stuff pattern")
    }

    // MARK: - Random sweep — read

    func testParity_randomReadPlans_256Trials() {
        for trial in 0..<256 {
            let len = 4 + trial % 96      // scup will be 3 ≤ scup ≤ len
            let bytes = Self.makeRandomBytes(
                count: len, seed: UInt64(trial) &* 0xC2B2AE3D27D4EB4F)
            let scup = 2 + (trial % (len - 2))
            // Random widths in [1, 32] derived from a different seed.
            var widthState = UInt64(trial) &* 0x9E3779B97F4A7C15 | 1
            var widths: [Int] = []
            widths.reserveCapacity(40)
            for _ in 0..<40 {
                widthState &*= 6364136223846793005
                widthState &+= 1442695040888963407
                widths.append(1 + Int(widthState >> 27) % 32)
            }
            assertReadParity(bytes, scup: scup, widths: widths,
                             label: "rand-\(trial)-len\(len)-scup\(scup)")
        }
    }

    // MARK: - peek+consume parity

    func testParity_peekConsume_uniformPattern() {
        let bytes: [UInt8] = [0xCC, 0x33, 0xAA, 0x55, 0xFF, 0x7F, 0x00, 0x80, 0x91, 0x6E, 0xDA, 0x24]
        // Real decoder pattern: peek 7 bits, derive cwd_len in [1, 7],
        // consume cwd_len. Vary cwd_len to exercise different consume
        // depths against the same peek.
        let pairs: [(Int, Int)] = [
            (7, 1), (7, 2), (7, 3), (7, 4), (7, 5), (7, 6), (7, 7),
            (8, 4), (16, 12), (32, 16), (32, 1), (32, 0)
        ]
        assertPeekConsumeParity(bytes, scup: 10, pairs: pairs,
                                label: "peek-consume uniform")
    }

    func testParity_peekConsume_randomSweep() {
        for trial in 0..<128 {
            let len = 8 + trial % 64
            let bytes = Self.makeRandomBytes(
                count: len, seed: UInt64(trial) &* 0xF5A6B7C8D9E0F123)
            let scup = 3 + (trial % (len - 3))
            // Generate 32 (peek, consume) pairs.
            var st = UInt64(trial) &* 0x123456789ABCDEF1 | 1
            var pairs: [(Int, Int)] = []
            pairs.reserveCapacity(32)
            for _ in 0..<32 {
                st &*= 6364136223846793005
                st &+= 1442695040888963407
                let peek = 1 + Int(st >> 27) % 32
                st &*= 6364136223846793005
                st &+= 1442695040888963407
                let consume = Int(st >> 28) % (peek + 1)   // 0..peek
                pairs.append((peek, consume))
            }
            assertPeekConsumeParity(
                bytes, scup: scup, pairs: pairs,
                label: "peek-consume rand-\(trial)-len\(len)-scup\(scup)")
        }
    }
}
#endif
