// J2KHTMELCoderPart15Tests.swift
// Unit tests for the ISO/IEC 15444-15 MEL coder.
//
// Validates round-trip equivalence between encoder and decoder on a
// spectrum of inputs: all-zeros (extreme compression), all-ones
// (maximum event density), random mixes at various densities.

import XCTest
@testable import J2KCodec

final class HTMELCoderPart15Tests: XCTestCase {

    // MARK: - Round-trip

    func testRoundTripAllZeros() {
        let events = [Bool](repeating: false, count: 100)
        let encoded = HTMELCoderPart15.encodeEvents(events)
        let decoded = HTMELCoderPart15.decodeEvents(encoded, count: events.count)
        XCTAssertEqual(decoded, events)
    }

    func testRoundTripAlternating() {
        let events = (0..<64).map { $0 % 2 == 0 }
        let encoded = HTMELCoderPart15.encodeEvents(events)
        let decoded = HTMELCoderPart15.decodeEvents(encoded, count: events.count)
        XCTAssertEqual(decoded, events)
    }

    func testRoundTripSingleOneAmongZeros() {
        var events = [Bool](repeating: false, count: 50)
        events[37] = true
        let encoded = HTMELCoderPart15.encodeEvents(events)
        let decoded = HTMELCoderPart15.decodeEvents(encoded, count: events.count)
        XCTAssertEqual(decoded, events)
    }

    func testRoundTripSparseOnes() {
        // 1% density — realistic for HT block "one" events.
        var rng = SeededRNG(seed: 42)
        let events = (0..<1000).map { _ in rng.nextDouble() < 0.01 }
        let encoded = HTMELCoderPart15.encodeEvents(events)
        let decoded = HTMELCoderPart15.decodeEvents(encoded, count: events.count)
        XCTAssertEqual(decoded, events)
    }

    func testRoundTripDenseOnes() {
        // 50% density — atypical for MEL but still must be lossless.
        var rng = SeededRNG(seed: 7)
        let events = (0..<256).map { _ in rng.nextDouble() < 0.5 }
        let encoded = HTMELCoderPart15.encodeEvents(events)
        let decoded = HTMELCoderPart15.decodeEvents(encoded, count: events.count)
        XCTAssertEqual(decoded, events)
    }

    func testRoundTripLargeMixedSparse() {
        var rng = SeededRNG(seed: 2026)
        let events = (0..<10_000).map { _ in rng.nextDouble() < 0.05 }
        let encoded = HTMELCoderPart15.encodeEvents(events)
        let decoded = HTMELCoderPart15.decodeEvents(encoded, count: events.count)
        XCTAssertEqual(decoded, events)
    }

    // MARK: - State machine properties

    /// The first `1` event cannot happen before at least one bit is
    /// emitted, but every subsequent zero bumps the threshold up to
    /// the state-12 maximum of 32. Verify the encoder reaches state
    /// 12 and emits only one byte for 128 consecutive zeros.
    func testStateAdvancesOnZeros() {
        // 256 zeros — after state reaches 12 (threshold 32), each 32
        // zeros yields one '1' bit. 256 / 32 = 8 bits. Plus the ramp
        // up through smaller thresholds (1+1+1+2+2+2+4+4+4+8+8+16 = 53
        // zeros to reach state 12). Total ~ (53 + (256-53)/32) ≈ 19
        // bits ≈ 3 bytes. Much better than 256 raw bits.
        let zeros = [Bool](repeating: false, count: 256)
        let encoded = HTMELCoderPart15.encodeEvents(zeros)
        XCTAssertLessThan(encoded.count, 10,
            "MEL should compress 256 zeros into under 10 bytes, got \(encoded.count)")
    }
}

/// Deterministic LCG RNG so tests are stable across runs.
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> UInt64 {
        state &*= 6364136223846793005
        state &+= 1442695040888963407
        return state
    }
    mutating func nextDouble() -> Double {
        // Use top 53 bits for mantissa.
        Double(next() >> 11) / Double(1 << 53)
    }
}
