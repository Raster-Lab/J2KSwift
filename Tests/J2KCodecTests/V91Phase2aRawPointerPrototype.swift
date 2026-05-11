// V91Phase2aRawPointerPrototype.swift
//
// v9.1 Path B Phase 2a — raw-pointer engine prototype + concurrent A/B.
//
// Phase 2 concurrent-contention probe showed per-block wall inflates
// 5× from 39 µs (1 worker) to 187 µs (6+ workers). Hypothesis: heap
// allocator + ARC contention on Swift `[UInt8]` arrays used inside
// the three engines (HTMagSgnEncoderConformant, HTMELEncoderConformant,
// HTReverseBitEmitterConformant).
//
// This prototype builds a minimal raw-pointer MagSgn encoder (the
// smallest of the three engines) that does the SAME bit-emission work
// but writes to a pre-allocated `UnsafeMutableBufferPointer<UInt8>`
// instead of an Array. It runs the same concurrent worker-count sweep
// and compares the inflation curve.
//
// If raw-pointer MagSgn shows FLAT scaling (or close to it) where the
// Array-backed version showed 5× inflation, the contention hypothesis
// is positively validated AND we have a concrete path to Phase 2 fix.

import XCTest
@testable import J2KCodec

/// Raw-pointer MagSgn encoder prototype. Mirrors the bit-packing
/// semantics of `HTMagSgnEncoderConformant` but stores bytes in a
/// pre-allocated `UnsafeMutableBufferPointer` instead of a Swift
/// `[UInt8]`. The caller owns the buffer's allocation.
struct HTMagSgnEncoderRawPrototype {
    let buf: UnsafeMutablePointer<UInt8>
    let capacity: Int
    var idx: Int = 0
    var tmp: UInt32 = 0
    var usedBits: Int = 0
    var maxBits: Int = 8

    init(buf: UnsafeMutablePointer<UInt8>, capacity: Int) {
        self.buf = buf
        self.capacity = capacity
    }

    mutating func reset() {
        idx = 0
        tmp = 0
        usedBits = 0
        maxBits = 8
    }

    @inline(__always)
    mutating func encode(codeword: UInt32, count: Int) {
        var cwd = codeword
        var len = count
        while len > 0 {
            let take = min(maxBits - usedBits, len)
            let mask: UInt32 = (take >= 32) ? ~UInt32(0) : ((UInt32(1) << take) - 1)
            tmp |= (cwd & mask) << usedBits
            usedBits += take
            cwd >>= take
            len -= take
            if usedBits >= maxBits {
                let byte = UInt8(tmp & 0xFF)
                buf[idx] = byte
                idx &+= 1
                maxBits = (byte == 0xFF) ? 7 : 8
                tmp = 0
                usedBits = 0
            }
        }
    }

    /// Returns the count of bytes written (raw pointer; caller copies if needed).
    mutating func finishCount() -> Int {
        if usedBits != 0 {
            let padBits = maxBits - usedBits
            let padMask: UInt32 = (padBits >= 32) ? ~UInt32(0)
                                                  : ((UInt32(1) << padBits) - 1)
            tmp |= padMask << usedBits
            let byte = UInt8(tmp & 0xFF)
            if byte != 0xFF {
                buf[idx] = byte
                idx &+= 1
            }
            tmp = 0
            usedBits = 0
            maxBits = 8
        } else if maxBits == 7 {
            // ms_terminate rollback.
            idx &-= 1
            maxBits = 8
        }
        return idx
    }
}

final class V91Phase2aRawPointerPrototype: XCTestCase {

    /// Bit-exactness check: the raw-pointer prototype must produce the
    /// SAME bytes as the Array-backed engine for every input sequence.
    func testRawPointerProducesIdenticalBytes() throws {
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: 0xDEAD_C0FFEE_42_42)

        let bufCap = 16 * 1024
        let bufPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
        defer { bufPtr.deallocate() }

        for trial in 0..<200 {
            // Generate random codeword/count sequence (200 emits per trial).
            var ops: [(UInt32, Int)] = []
            for _ in 0..<200 {
                let bits = Int(rng.next() & 0x1F) + 1  // 1-32 bits
                let mask: UInt32 = bits >= 32 ? ~UInt32(0) : (UInt32(1) << bits) - 1
                let cw = UInt32(truncatingIfNeeded: rng.next()) & mask
                ops.append((cw, bits))
            }

            // Encode via Array-backed engine.
            var arrayEnc = HTMagSgnEncoderConformant()
            for (cw, n) in ops { arrayEnc.encode(codeword: cw, count: n) }
            let arrayBytes = arrayEnc.finish()

            // Encode via raw-pointer prototype.
            var rawEnc = HTMagSgnEncoderRawPrototype(buf: bufPtr, capacity: bufCap)
            for (cw, n) in ops { rawEnc.encode(codeword: cw, count: n) }
            let rawCount = rawEnc.finishCount()
            let rawBytes = Array(UnsafeBufferPointer(start: bufPtr, count: rawCount))

            XCTAssertEqual(arrayBytes, rawBytes, "Trial \(trial): bytes differ")
        }
    }

    /// Concurrent A/B: run the same workload through Array-backed vs
    /// raw-pointer encoders, scaling worker count, and compare the
    /// per-block-wall inflation curves.
    func testConcurrentABScaling() async throws {
        let bytesPerBlock = 4_000  // ~sparse-block magsgn output size
        let opsPerBlock = 500       // 200 sig samples × ~2.5 emits each
        let blocksPerWorker = 1_000
        let workerCounts = [1, 2, 4, 6, 8, 12]

        struct Row {
            let variant: String
            let workers: Int
            let medianPerBlockNs: UInt64
            let throughputBlocksPerSec: Double
        }
        var rows: [Row] = []

        // Synthetic op sequence (same for all workers / variants).
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: 0xCAFE_F00D)
        var ops: [(UInt32, Int)] = []
        for _ in 0..<opsPerBlock {
            let bits = Int(rng.next() & 0xF) + 1  // 1-16 bits typical
            let mask: UInt32 = (UInt32(1) << bits) - 1
            let cw = UInt32(truncatingIfNeeded: rng.next()) & mask
            ops.append((cw, bits))
        }

        // ---- Variant A: Array-backed engine ----
        for workerCount in workerCounts {
            let opsCopy = ops
            let bs = bytesPerBlock
            let wallStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let allSamples = await withTaskGroup(of: [UInt64].self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        var enc = HTMagSgnEncoderConformant()
                        var samples: [UInt64] = []
                        samples.reserveCapacity(blocksPerWorker)
                        for _ in 0..<blocksPerWorker {
                            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            enc.reset()
                            for (cw, n) in opsCopy { enc.encode(codeword: cw, count: n) }
                            _ = enc.finish()
                            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            samples.append(t1 &- t0)
                        }
                        _ = bs  // anti-DCE
                        return samples
                    }
                }
                var collected: [UInt64] = []
                for await sub in group { collected.append(contentsOf: sub) }
                return collected
            }
            let wallEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            var sorted = allSamples
            sorted.sort()
            let median = sorted[sorted.count / 2]
            let totalWallSec = Double(wallEnd &- wallStart) / 1_000_000_000.0
            let totalBlocks = workerCount * blocksPerWorker
            rows.append(Row(
                variant: "Array",
                workers: workerCount,
                medianPerBlockNs: median,
                throughputBlocksPerSec: Double(totalBlocks) / totalWallSec))
        }

        // ---- Variant B: Raw-pointer engine ----
        for workerCount in workerCounts {
            let opsCopy = ops
            let bs = bytesPerBlock
            let wallStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let allSamples = await withTaskGroup(of: [UInt64].self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        // Per-worker raw buffer (16 KB).
                        let bufCap = 16 * 1024
                        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
                        defer { buf.deallocate() }
                        var enc = HTMagSgnEncoderRawPrototype(buf: buf, capacity: bufCap)
                        var samples: [UInt64] = []
                        samples.reserveCapacity(blocksPerWorker)
                        for _ in 0..<blocksPerWorker {
                            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            enc.reset()
                            for (cw, n) in opsCopy { enc.encode(codeword: cw, count: n) }
                            _ = enc.finishCount()
                            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            samples.append(t1 &- t0)
                        }
                        _ = bs
                        return samples
                    }
                }
                var collected: [UInt64] = []
                for await sub in group { collected.append(contentsOf: sub) }
                return collected
            }
            let wallEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            var sorted = allSamples
            sorted.sort()
            let median = sorted[sorted.count / 2]
            let totalWallSec = Double(wallEnd &- wallStart) / 1_000_000_000.0
            let totalBlocks = workerCount * blocksPerWorker
            rows.append(Row(
                variant: "RawPtr",
                workers: workerCount,
                medianPerBlockNs: median,
                throughputBlocksPerSec: Double(totalBlocks) / totalWallSec))
        }

        print()
        print("=== v9.1 Phase 2a — Array vs RawPtr concurrent A/B ===")
        print()
        print("Synthetic \(opsPerBlock)-op encode load per block; \(blocksPerWorker) blocks/worker.")
        print()
        print("| variant | workers | median ns/block | blocks/sec | × vs 1-worker |")
        print("|---------|--------:|----------------:|-----------:|--------------:|")
        var arrayBaseline: Double = 1
        var rawBaseline: Double = 1
        for r in rows {
            if r.variant == "Array" && r.workers == 1 { arrayBaseline = r.throughputBlocksPerSec }
            if r.variant == "RawPtr" && r.workers == 1 { rawBaseline = r.throughputBlocksPerSec }
        }
        for r in rows {
            let baseline = r.variant == "Array" ? arrayBaseline : rawBaseline
            print(String(format: "| %7@ | %7d | %15llu | %10.0f | %12.2f× |",
                r.variant as NSString, r.workers, r.medianPerBlockNs,
                r.throughputBlocksPerSec, r.throughputBlocksPerSec / baseline))
        }
        print()
        print("Reads:")
        print("  - If RawPtr's ns/block stays flat with worker count while Array's")
        print("    inflates, the contention hypothesis is VALIDATED and Phase 2a's")
        print("    `UnsafeMutableBufferPointer` refactor will eliminate the corpus gap.")
        print("  - If RawPtr also inflates, contention is at a level deeper than")
        print("    Array.append (likely DRAM bandwidth or scheduler) and Path B")
        print("    requires further root-causing.")
    }
}
