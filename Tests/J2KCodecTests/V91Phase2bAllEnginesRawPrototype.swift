// V91Phase2bAllEnginesRawPrototype.swift
//
// v9.1 Path B Phase 2b — raw-pointer prototypes for MEL + VLC engines
// (extending Phase 2a's MagSgn-only validation).
//
// Phase 2a showed raw-pointer MagSgn scales near-linearly across 12
// workers while Array-backed MagSgn inflates by ~40%. The MagSgn
// engine alone is the smallest of the three byte-emit paths. Phase 2b
// extends the architecture to:
//
//   - HTMELEncoderRawPrototype       (mirrors HTMELEncoderConformant)
//   - HTReverseBitEmitterRawPrototype (mirrors HTReverseBitEmitter-
//                                       Conformant — VLC engine)
//
// Plus a triple-engine A/B that combines all three raw engines in the
// same pattern as the actual HTBlockEncoderConformant.encode (multiple
// magsgn + mel + vlc emits per block).
//
// If the triple-engine raw A/B shows a much larger per-block-wall
// reduction than the single-engine MagSgn A/B from 2a, the contention
// hypothesis is fully validated AND the full Phase 2 fix is on track
// to close 30-50% of the corpus DX wall.

import XCTest
@testable import J2KCodec

// MARK: - MEL raw-pointer prototype

/// Forward bit emitter using a caller-owned raw buffer. Mirror of
/// `HTForwardBitEmitterConformant`.
struct HTForwardBitEmitterRawPrototype {
    let buf: UnsafeMutablePointer<UInt8>
    let capacity: Int
    var idx: Int = 0
    var tmp: Int = 0
    var remainingBits: Int = 8

    init(buf: UnsafeMutablePointer<UInt8>, capacity: Int) {
        self.buf = buf
        self.capacity = capacity
    }

    mutating func reset() {
        idx = 0
        tmp = 0
        remainingBits = 8
    }

    @inline(__always)
    mutating func emit(bit: Int) {
        tmp = (tmp << 1) | (bit & 1)
        remainingBits -= 1
        if remainingBits == 0 {
            let byte = UInt8(tmp & 0xFF)
            buf[idx] = byte
            idx &+= 1
            remainingBits = (byte == 0xFF) ? 7 : 8
            tmp = 0
        }
    }

    mutating func finishCount() -> Int {
        if remainingBits != 8 {
            tmp <<= remainingBits
            buf[idx] = UInt8(tmp & 0xFF)
            idx &+= 1
            tmp = 0
            remainingBits = 8
        }
        return idx
    }
}

/// MEL encoder using a caller-owned raw buffer for the underlying
/// forward bit emitter.
struct HTMELEncoderRawPrototype {
    var emitter: HTForwardBitEmitterRawPrototype
    var state: Int = 0
    var run: Int = 0
    var threshold: Int = 1

    init(buf: UnsafeMutablePointer<UInt8>, capacity: Int) {
        self.emitter = HTForwardBitEmitterRawPrototype(buf: buf, capacity: capacity)
    }

    mutating func reset() {
        emitter.reset()
        state = 0
        run = 0
        threshold = 1
    }

    @inline(__always)
    mutating func encode(eventIsOne: Bool) {
        if !eventIsOne {
            run += 1
            if run >= threshold {
                emitter.emit(bit: 1)
                run = 0
                state = min(12, state + 1)
                threshold = 1 << melExpConformant[state]
            }
        } else {
            emitter.emit(bit: 0)
            var t = melExpConformant[state]
            while t > 0 {
                t -= 1
                emitter.emit(bit: (run >> t) & 1)
            }
            run = 0
            state = max(0, state - 1)
            threshold = 1 << melExpConformant[state]
        }
    }

    mutating func finishCount() -> Int {
        if run > 0 {
            emitter.emit(bit: 1)
        }
        return emitter.finishCount()
    }
}

// MARK: - VLC (reverse) raw-pointer prototype

/// Reverse bit emitter using a caller-owned raw buffer. Writes bytes
/// in the same order as `HTReverseBitEmitterConformant.emittedReversed`
/// (sentinel-first, then growing forward in memory). The final on-wire
/// byte order is reversed by `finishReversed()`.
struct HTReverseBitEmitterRawPrototype {
    let buf: UnsafeMutablePointer<UInt8>
    let capacity: Int
    var idx: Int = 1  // [0]=0xFF sentinel already placed by reset()
    var tmp: Int = 0x0F
    var usedBits: Int = 4
    var lastGreaterThan8F: Bool = true

    init(buf: UnsafeMutablePointer<UInt8>, capacity: Int) {
        self.buf = buf
        self.capacity = capacity
        buf[0] = 0xFF
    }

    mutating func reset() {
        idx = 1
        buf[0] = 0xFF
        tmp = 0x0F
        usedBits = 4
        lastGreaterThan8F = true
    }

    @inline(__always)
    mutating func encode(codeword: Int, count: Int) {
        var cwd = codeword
        var len = count
        while len > 0 {
            let stuffPenalty = lastGreaterThan8F ? 1 : 0
            let availBits = 8 - stuffPenalty - usedBits
            let take = min(availBits, len)
            if take > 0 {
                let mask = (1 << take) - 1
                tmp |= (cwd & mask) << usedBits
                usedBits += take
                cwd >>= take
                len -= take
            }
            let remainingAfter = availBits - take
            if remainingAfter == 0 {
                if lastGreaterThan8F && tmp != 0x7F {
                    lastGreaterThan8F = false
                    continue
                }
                buf[idx] = UInt8(tmp & 0xFF)
                idx &+= 1
                lastGreaterThan8F = tmp > 0x8F
                tmp = 0
                usedBits = 0
            }
        }
    }

    /// Returns the count of bytes in the reversed (on-wire) order.
    /// Caller can use `Array(UnsafeBufferPointer(start: buf, count: idx)).reversed()`.
    mutating func finishCount() -> Int {
        if usedBits > 0 {
            buf[idx] = UInt8(tmp & 0xFF)
            idx &+= 1
            tmp = 0
            usedBits = 0
        }
        return idx
    }
}

// MARK: - Tests

final class V91Phase2bAllEnginesRawPrototype: XCTestCase {

    /// Bit-exactness sweep: MEL raw == MEL Array on random event sequences.
    func testMELRawBitExactVsArray() throws {
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
        var rng = SplitMix64(state: 0xDEAD_BEEF_C0DE)
        let bufCap = 16 * 1024
        let bufPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
        defer { bufPtr.deallocate() }

        for trial in 0..<100 {
            let n = 100 + Int(rng.next() & 0xFF)
            var events: [Bool] = []
            for _ in 0..<n {
                events.append((rng.next() & 0x3) == 0)  // ~25% one-events
            }
            // Array variant
            var arrayMel = HTMELEncoderConformant()
            for e in events { arrayMel.encode(eventIsOne: e) }
            let arrayBytes = arrayMel.finish()
            // Raw variant
            var rawMel = HTMELEncoderRawPrototype(buf: bufPtr, capacity: bufCap)
            for e in events { rawMel.encode(eventIsOne: e) }
            let rawCount = rawMel.finishCount()
            let rawBytes = Array(UnsafeBufferPointer(start: bufPtr, count: rawCount))
            XCTAssertEqual(arrayBytes, rawBytes, "MEL trial \(trial): bytes differ (n=\(n))")
        }
    }

    /// Bit-exactness sweep: VLC raw (reversed) == VLC Array on random codewords.
    func testVLCRawBitExactVsArray() throws {
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
        var rng = SplitMix64(state: 0xFACE_FEED_2026)
        let bufCap = 16 * 1024
        let bufPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
        defer { bufPtr.deallocate() }

        for trial in 0..<100 {
            let n = 100 + Int(rng.next() & 0xFF)
            var ops: [(Int, Int)] = []
            for _ in 0..<n {
                let bits = Int(rng.next() & 0xF) + 1  // 1-16 bits
                let mask = (1 << bits) - 1
                let cw = Int(truncatingIfNeeded: rng.next()) & mask
                ops.append((cw, bits))
            }
            // Array variant
            var arrayVlc = HTReverseBitEmitterConformant()
            for (cw, n) in ops { arrayVlc.encode(codeword: cw, count: n) }
            let arrayBytes = arrayVlc.finish()
            // Raw variant
            var rawVlc = HTReverseBitEmitterRawPrototype(buf: bufPtr, capacity: bufCap)
            for (cw, n) in ops { rawVlc.encode(codeword: cw, count: n) }
            let rawCount = rawVlc.finishCount()
            // The raw variant produces bytes in "emittedReversed" order
            // (sentinel-first). Match Array variant's `.reversed()`.
            let rawBytes = Array(UnsafeBufferPointer(start: bufPtr, count: rawCount)).reversed()
            let rawBytesArray = Array(rawBytes)
            XCTAssertEqual(arrayBytes, rawBytesArray, "VLC trial \(trial): bytes differ (n=\(n))")
        }
    }

    /// Triple-engine A/B: drive all three engines with the same workload
    /// pattern as a real block encode, in N concurrent workers. Compares
    /// per-block-wall scaling between Array-backed and RawPtr-backed
    /// versions.
    func testTripleEngineConcurrentAB() async throws {
        // Roughly mimic the per-block calls counted in V91Phase0EncoderProfileTests
        // on a typical DX block: 800 magsgn (14 bit avg), 700 vlc tuple (5 bit avg),
        // 750 vlc UVLC (3 bit avg), 13 mel events.
        let magsgnOps = 800
        let vlcTupleOps = 700
        let vlcUVLCOps = 750
        let melEvents = 13
        let blocksPerWorker = 500
        let workerCounts = [1, 2, 4, 6, 8, 12]

        struct Row {
            let variant: String
            let workers: Int
            let medianPerBlockNs: UInt64
            let throughputBlocksPerSec: Double
        }
        var rows: [Row] = []

        // ---- Variant A: Array-backed all three engines ----
        for workerCount in workerCounts {
            let wallStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let allSamples = await withTaskGroup(of: [UInt64].self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        var magsgn = HTMagSgnEncoderConformant()
                        var mel = HTMELEncoderConformant()
                        var vlc = HTReverseBitEmitterConformant()
                        var samples: [UInt64] = []
                        samples.reserveCapacity(blocksPerWorker)
                        for _ in 0..<blocksPerWorker {
                            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            magsgn.reset()
                            mel.reset()
                            vlc.reset()
                            for i in 0..<magsgnOps {
                                magsgn.encode(codeword: UInt32(i & 0x3FFF), count: 14)
                            }
                            for i in 0..<vlcTupleOps {
                                vlc.encode(codeword: i & 0x1F, count: 5)
                            }
                            for i in 0..<vlcUVLCOps {
                                vlc.encode(codeword: i & 0x7, count: 3)
                            }
                            for i in 0..<melEvents {
                                mel.encode(eventIsOne: (i & 1) == 0)
                            }
                            _ = magsgn.finish()
                            _ = mel.finish()
                            _ = vlc.finish()
                            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            samples.append(t1 &- t0)
                        }
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

        // ---- Variant B: RawPtr all three engines ----
        for workerCount in workerCounts {
            let wallStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let allSamples = await withTaskGroup(of: [UInt64].self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        let bufCap = 16 * 1024
                        let magsgnBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
                        let melBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
                        let vlcBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufCap)
                        defer {
                            magsgnBuf.deallocate()
                            melBuf.deallocate()
                            vlcBuf.deallocate()
                        }
                        var magsgn = HTMagSgnEncoderRawPrototype(buf: magsgnBuf, capacity: bufCap)
                        var mel = HTMELEncoderRawPrototype(buf: melBuf, capacity: bufCap)
                        var vlc = HTReverseBitEmitterRawPrototype(buf: vlcBuf, capacity: bufCap)
                        var samples: [UInt64] = []
                        samples.reserveCapacity(blocksPerWorker)
                        for _ in 0..<blocksPerWorker {
                            let t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            magsgn.reset()
                            mel.reset()
                            vlc.reset()
                            for i in 0..<magsgnOps {
                                magsgn.encode(codeword: UInt32(i & 0x3FFF), count: 14)
                            }
                            for i in 0..<vlcTupleOps {
                                vlc.encode(codeword: i & 0x1F, count: 5)
                            }
                            for i in 0..<vlcUVLCOps {
                                vlc.encode(codeword: i & 0x7, count: 3)
                            }
                            for i in 0..<melEvents {
                                mel.encode(eventIsOne: (i & 1) == 0)
                            }
                            _ = magsgn.finishCount()
                            _ = mel.finishCount()
                            _ = vlc.finishCount()
                            let t1 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
                            samples.append(t1 &- t0)
                        }
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
        print("=== v9.1 Phase 2b — triple-engine concurrent A/B ===")
        print()
        print("Realistic per-block workload mirroring corpus DX call distribution:")
        print("  magsgn=\(magsgnOps)×14b  vlc-tuple=\(vlcTupleOps)×5b  vlc-uvlc=\(vlcUVLCOps)×3b  mel=\(melEvents)")
        print("\(blocksPerWorker) blocks per worker.")
        print()
        print("| variant | workers | median ns/block | blocks/sec | × vs 1 |")
        print("|---------|--------:|----------------:|-----------:|-------:|")
        var arrayBaseline: Double = 1
        var rawBaseline: Double = 1
        for r in rows {
            if r.variant == "Array" && r.workers == 1 { arrayBaseline = r.throughputBlocksPerSec }
            if r.variant == "RawPtr" && r.workers == 1 { rawBaseline = r.throughputBlocksPerSec }
        }
        for r in rows {
            let baseline = r.variant == "Array" ? arrayBaseline : rawBaseline
            print(String(format: "| %7@ | %7d | %15llu | %10.0f | %6.2f× |",
                r.variant as NSString, r.workers, r.medianPerBlockNs,
                r.throughputBlocksPerSec, r.throughputBlocksPerSec / baseline))
        }
        print()
        print("Interpretation:")
        print("  - If RawPtr ns/block stays close to its 1-worker value at 6+ workers")
        print("    while Array inflates noticeably, the Phase 2 fix is fully validated.")
        print("  - The corpus DX measurement showed 308 µs/block. If this triple-engine")
        print("    A/B reproduces that magnitude on Array variant + brings it down on")
        print("    RawPtr, we've proven the full integration will close the corpus gap.")
    }
}
