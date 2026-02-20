//
// J2KSSEEntropyTests.swift
// J2KSwift
//
// Tests for Intel x86-64 SSE4.2/AVX2 entropy coding operations.
//
// These tests validate correctness of x86-64-accelerated context formation,
// bit-plane coding, run-length detection, and MQ-coder state updates.
// Tests run on all platforms; x86-64 SIMD paths are exercised on x86_64.
//
import XCTest
@testable import J2KCodec

/// Tests for Intel x86-64 SSE4.2/AVX2-accelerated entropy coding operations.
final class J2KSSEEntropyTests: XCTestCase {

    // MARK: - Capability Detection

    func testX86EntropyCodingCapabilityDetection() {
        let cap = X86EntropyCodingCapability.detect()
        #if arch(x86_64)
        XCTAssertTrue(cap.isAvailable, "x86-64 SIMD should be available on x86_64")
        XCTAssertTrue(cap.hasSSE42, "SSE4.2 should be available on modern x86-64")
        XCTAssertTrue(cap.hasAVX2, "AVX2 should be available on modern x86-64")
        XCTAssertTrue(cap.hasFMA, "FMA should be available on modern x86-64")
        XCTAssertEqual(cap.vectorWidth, 8, "AVX2 vector width should be 8 floats")
        #else
        XCTAssertFalse(cap.isAvailable, "x86-64 SIMD should not be available on non-x86_64")
        XCTAssertFalse(cap.hasSSE42)
        XCTAssertFalse(cap.hasAVX2)
        XCTAssertFalse(cap.hasFMA)
        XCTAssertEqual(cap.vectorWidth, 1)
        #endif
    }

    func testCapabilityEquality() {
        let a = X86EntropyCodingCapability.detect()
        let b = X86EntropyCodingCapability.detect()
        XCTAssertEqual(a, b, "Two detect() calls should return equal capabilities")
    }

    func testCapabilityLogicalConsistency() {
        let cap = X86EntropyCodingCapability.detect()
        // AVX2 implies SSE4.2; FMA typically paired with AVX2 on modern x86-64
        if cap.hasAVX2 {
            XCTAssertTrue(cap.hasSSE42, "AVX2 implies SSE4.2 support")
            XCTAssertTrue(cap.isAvailable, "AVX2 availability implies SIMD is available")
        }
        if cap.hasFMA {
            XCTAssertTrue(cap.hasAVX2, "FMA availability implies AVX2 on x86-64")
        }
        if !cap.isAvailable {
            XCTAssertFalse(cap.hasSSE42, "Not available implies no SSE4.2")
            XCTAssertFalse(cap.hasAVX2, "Not available implies no AVX2")
            XCTAssertFalse(cap.hasFMA, "Not available implies no FMA")
        }
    }

    // MARK: - Context Formation: Empty / Edge Cases

    func testContextFormationEmptyInput() {
        let formation = SSEContextFormation()
        let result = formation.batchContextLabels(
            significanceState: [],
            width: 4,
            rowOffset: 0,
            length: 0
        )
        XCTAssertTrue(result.isEmpty, "Empty input should produce empty output")
    }

    func testContextFormationAllZeroState() {
        let formation = SSEContextFormation()
        // 4×4 grid, all insignificant
        let state = [Int32](repeating: 0, count: 16)
        let result = formation.batchContextLabels(
            significanceState: state,
            width: 4,
            rowOffset: 0,
            length: 16
        )
        XCTAssertEqual(result, [Int32](repeating: 0, count: 16),
            "All-zero state should produce all-zero labels")
    }

    // MARK: - Context Formation: Horizontal Contribution

    func testContextFormationHorizontalBothNeighbours() {
        let formation = SSEContextFormation()
        // Row of 4: significant at positions 0 and 2
        let state: [Int32] = [1, 0, 1, 0]
        let result = formation.batchContextLabels(
            significanceState: state,
            width: 4,
            rowOffset: 0,
            length: 4
        )
        // Position 1: left=1 (index 0), right=1 (index 2) → h = 2
        let hContrib = result[1] & 0x3
        XCTAssertEqual(hContrib, 2, "Position 1 should have h=2 (both horizontal neighbours significant)")
    }

    func testContextFormationHorizontalOneNeighbour() {
        let formation = SSEContextFormation()
        // Row of 4: significant at position 0 only
        let state: [Int32] = [1, 0, 0, 0]
        let result = formation.batchContextLabels(
            significanceState: state,
            width: 4,
            rowOffset: 0,
            length: 4
        )
        // Position 1: left=1 (index 0), right=0 → h = 1
        let hContrib = result[1] & 0x3
        XCTAssertEqual(hContrib, 1, "Position 1 should have h=1 (left neighbour significant)")
    }

    // MARK: - Context Formation: Vertical Contribution

    func testContextFormationVerticalContribution() {
        let formation = SSEContextFormation()
        // 3-row × 4-col grid
        var state = [Int32](repeating: 0, count: 12)
        state[1] = 1   // Row 0, Col 1
        state[9] = 1   // Row 2, Col 1

        let result = formation.batchContextLabels(
            significanceState: state,
            width: 4,
            rowOffset: 0,
            length: 12
        )
        // Position 5 (Row 1, Col 1): above=1 (pos 1), below=1 (pos 9) → v = 2
        let vContrib = (result[5] >> 2) & 0x3
        XCTAssertEqual(vContrib, 2, "Position 5 should have v=2 (both vertical neighbours significant)")
    }

    // MARK: - Context Formation: Diagonal Contribution

    func testContextFormationDiagonalContribution() {
        let formation = SSEContextFormation()
        // 3×3 grid, diagonal corners significant
        var state = [Int32](repeating: 0, count: 9)
        state[0] = 1   // Row 0, Col 0  (top-left)
        state[2] = 1   // Row 0, Col 2  (top-right)
        state[6] = 1   // Row 2, Col 0  (bottom-left)
        state[8] = 1   // Row 2, Col 2  (bottom-right)

        let result = formation.batchContextLabels(
            significanceState: state,
            width: 3,
            rowOffset: 0,
            length: 9
        )
        // Centre position 4 (Row 1, Col 1): all 4 diagonal neighbours significant → d = 4
        let dContrib = (result[4] >> 4) & 0xF
        XCTAssertEqual(dContrib, 4, "Centre should have d=4 (all diagonal neighbours significant)")
    }

    // MARK: - Context Formation: AVX2 Width Alignment (9+ coefficients)

    func testContextFormationNineElements() {
        let formation = SSEContextFormation()
        // 9 elements in one row: exercises SIMD8 + 1 scalar tail
        let state = [Int32](repeating: 0, count: 9)
        let result = formation.batchContextLabels(
            significanceState: state,
            width: 9,
            rowOffset: 0,
            length: 9
        )
        XCTAssertEqual(result.count, 9)
        XCTAssertEqual(result, [Int32](repeating: 0, count: 9))
    }

    func testContextFormationSixteenElements() {
        let formation = SSEContextFormation()
        // 4×4 grid with some significant coefficients
        var state = [Int32](repeating: 0, count: 16)
        state[5] = 1   // Row 1, Col 1

        let result = formation.batchContextLabels(
            significanceState: state,
            width: 4,
            rowOffset: 0,
            length: 16
        )
        XCTAssertEqual(result.count, 16)
        // All results should be non-negative integers
        for (idx, label) in result.enumerated() {
            XCTAssertGreaterThanOrEqual(label, 0, "Label at \(idx) must be ≥ 0")
        }
    }

    // MARK: - Significance Scan

    func testSignificanceScanAllBelowThreshold() {
        let formation = SSEContextFormation()
        let magnitudes = [Int32](repeating: 0, count: 16)
        let result = formation.significanceScan(magnitudes: magnitudes, threshold: 1)
        XCTAssertEqual(result, [Int32](repeating: 0, count: 16))
    }

    func testSignificanceScanAllAboveThreshold() {
        let formation = SSEContextFormation()
        let magnitudes = [Int32](repeating: 10, count: 16)
        let result = formation.significanceScan(magnitudes: magnitudes, threshold: 5)
        XCTAssertEqual(result, [Int32](repeating: 1, count: 16))
    }

    func testSignificanceScanMixed() {
        let formation = SSEContextFormation()
        let magnitudes: [Int32] = [0, 5, 10, 2, 8, 1, 7, 3]
        let result = formation.significanceScan(magnitudes: magnitudes, threshold: 5)
        // Expected: [0, 1, 1, 0, 1, 0, 1, 0]
        let expected: [Int32] = [0, 1, 1, 0, 1, 0, 1, 0]
        XCTAssertEqual(result, expected)
    }

    func testSignificanceScanEmpty() {
        let formation = SSEContextFormation()
        let result = formation.significanceScan(magnitudes: [], threshold: 1)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Bit-Plane Extraction

    func testExtractBitPlaneZero() {
        let coder = AVX2BitPlaneCoder()
        let coefficients: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        let result = coder.extractBitPlane(coefficients: coefficients, plane: 0)
        let expected: [Int32] = [0, 1, 0, 1, 0, 1, 0, 1]
        XCTAssertEqual(result, expected, "Bit 0 should alternate for 0–7")
    }

    func testExtractBitPlaneOne() {
        let coder = AVX2BitPlaneCoder()
        let coefficients: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        let result = coder.extractBitPlane(coefficients: coefficients, plane: 1)
        let expected: [Int32] = [0, 0, 1, 1, 0, 0, 1, 1]
        XCTAssertEqual(result, expected, "Bit 1 should pair for 0–7")
    }

    func testExtractBitPlaneTwo() {
        let coder = AVX2BitPlaneCoder()
        let coefficients: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        let result = coder.extractBitPlane(coefficients: coefficients, plane: 2)
        let expected: [Int32] = [0, 0, 0, 0, 1, 1, 1, 1]
        XCTAssertEqual(result, expected, "Bit 2 should be 1 for values 4–7")
    }

    func testExtractBitPlaneAllOnes() {
        let coder = AVX2BitPlaneCoder()
        let coefficients = [Int32](repeating: Int32(bitPattern: 0xFFFF_FFFF) >> 1, count: 8)
        let result = coder.extractBitPlane(coefficients: coefficients, plane: 30)
        XCTAssertEqual(result, [Int32](repeating: 1, count: 8))
    }

    func testExtractBitPlaneInvalidPlane() {
        let coder = AVX2BitPlaneCoder()
        let coefficients: [Int32] = [1, 2, 3, 4]
        XCTAssertTrue(
            coder.extractBitPlane(coefficients: coefficients, plane: 31).isEmpty,
            "Plane ≥ 31 should return empty"
        )
        XCTAssertTrue(
            coder.extractBitPlane(coefficients: coefficients, plane: -1).isEmpty,
            "Negative plane should return empty"
        )
    }

    func testExtractBitPlaneLargeInput() {
        let coder = AVX2BitPlaneCoder()
        // 17 elements: exercises SIMD8 twice + 1 scalar tail
        let coefficients = (0..<17).map { Int32($0) }
        let result = coder.extractBitPlane(coefficients: coefficients, plane: 0)
        XCTAssertEqual(result.count, 17)
        for (i, bit) in result.enumerated() {
            XCTAssertEqual(bit, Int32(i) & 1, "Bit 0 at index \(i)")
        }
    }

    // MARK: - Magnitude Refinement

    func testMagnitudeRefinementAllSignificant() {
        let coder = AVX2BitPlaneCoder()
        let coefficients: [Int32] = [3, 5, 7, 9, 11, 13, 15, 17]
        let significance = [Int32](repeating: 1, count: 8)

        let (refinement, updated) = coder.magnitudeRefinement(
            coefficients: coefficients,
            significanceFlags: significance,
            plane: 0
        )

        XCTAssertEqual(refinement.count, 8)
        XCTAssertEqual(updated, coefficients, "Magnitudes should not change in refinement")
        // Bit 0 for [3,5,7,9,11,13,15,17] = [1,1,1,1,1,1,1,1]
        XCTAssertEqual(refinement, [Int32](repeating: 1, count: 8))
    }

    func testMagnitudeRefinementNoneSignificant() {
        let coder = AVX2BitPlaneCoder()
        let coefficients = [Int32](repeating: 15, count: 8)
        let significance = [Int32](repeating: 0, count: 8)

        let (refinement, _) = coder.magnitudeRefinement(
            coefficients: coefficients,
            significanceFlags: significance,
            plane: 3
        )
        XCTAssertEqual(refinement, [Int32](repeating: 0, count: 8),
            "No refinement bits for insignificant coefficients")
    }

    func testMagnitudeRefinementMismatchedLengths() {
        let coder = AVX2BitPlaneCoder()
        let (r, u) = coder.magnitudeRefinement(
            coefficients: [1, 2, 3],
            significanceFlags: [1, 0],
            plane: 0
        )
        XCTAssertTrue(r.isEmpty, "Mismatched lengths should return empty refinement")
        XCTAssertTrue(u.isEmpty, "Mismatched lengths should return empty magnitudes")
    }

    // MARK: - Run-Length Detection

    func testRunLengthDetectionAllSignificant() {
        let coder = AVX2BitPlaneCoder()
        let state = [Int32](repeating: 1, count: 16)
        let runs = coder.detectInsignificantRuns(significanceState: state, length: 16)
        XCTAssertTrue(runs.isEmpty, "No insignificant runs in all-significant state")
    }

    func testRunLengthDetectionAllInsignificant() {
        let coder = AVX2BitPlaneCoder()
        let state = [Int32](repeating: 0, count: 16)
        let runs = coder.detectInsignificantRuns(significanceState: state, length: 16)
        // Runs at positions 0,1,2,...,12 (any 4 consecutive zeros starting at those positions)
        XCTAssertFalse(runs.isEmpty, "Should detect insignificant runs in all-zero state")
        XCTAssertTrue(runs.contains(0), "Run should start at position 0")
    }

    func testRunLengthDetectionIsolated() {
        let coder = AVX2BitPlaneCoder()
        // Significant at position 4, rest insignificant
        var state = [Int32](repeating: 0, count: 16)
        state[4] = 1
        let runs = coder.detectInsignificantRuns(significanceState: state, length: 16)
        // Run starting at 0 (positions 0–3 all zero), but not at 1,2,3 (because position 4 breaks them)
        XCTAssertTrue(runs.contains(0), "Run should start at 0 (four zeros: 0,1,2,3)")
        // After position 4, runs from 5 onward exist
        XCTAssertTrue(runs.contains(5), "Run should start at 5 (positions 5–8 all zero)")
    }

    func testRunLengthDetectionEmpty() {
        let coder = AVX2BitPlaneCoder()
        let runs = coder.detectInsignificantRuns(significanceState: [], length: 0)
        XCTAssertTrue(runs.isEmpty)
    }

    // MARK: - MQ-Coder State Updates

    func testMQCoderStateBatchUpdateAllMPS() {
        let mqCoder = X86MQCoderVectorised()
        let states: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        let symbols = [Int32](repeating: 1, count: 8)  // All MPS
        let result = mqCoder.batchProbabilityUpdate(states: states, symbols: symbols)

        XCTAssertEqual(result.count, 8)
        // State 0 → MPS → state 1
        XCTAssertEqual(result[0], 1, "State 0 + MPS should advance to state 1")
        // State 5 → MPS → state 38
        XCTAssertEqual(result[5], 38, "State 5 + MPS should advance to state 38")
    }

    func testMQCoderStateBatchUpdateAllLPS() {
        let mqCoder = X86MQCoderVectorised()
        let states: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        let symbols = [Int32](repeating: 0, count: 8)  // All LPS
        let result = mqCoder.batchProbabilityUpdate(states: states, symbols: symbols)

        XCTAssertEqual(result.count, 8)
        // State 0 → LPS → state 1
        XCTAssertEqual(result[0], 1, "State 0 + LPS should transition to state 1")
    }

    func testMQCoderStateMismatchedInputs() {
        let mqCoder = X86MQCoderVectorised()
        let states: [Int32] = [0, 1, 2]
        let symbols: [Int32] = [1, 0]
        let result = mqCoder.batchProbabilityUpdate(states: states, symbols: symbols)
        // Mismatched input: returns original states
        XCTAssertEqual(result, states)
    }

    func testMQCoderStateUpdateLargeInput() {
        let mqCoder = X86MQCoderVectorised()
        // 17 elements: exercises SIMD loop twice + scalar tail
        let states = [Int32](repeating: 0, count: 17)
        let symbols = [Int32](repeating: 1, count: 17)
        let result = mqCoder.batchProbabilityUpdate(states: states, symbols: symbols)
        XCTAssertEqual(result.count, 17)
        XCTAssertEqual(result, [Int32](repeating: 1, count: 17),
            "All state-0 + MPS should advance to state 1")
    }

    // MARK: - Vector Leading Zeros

    func testVectorLeadingZerosPowerOfTwo() {
        let mqCoder = X86MQCoderVectorised()
        // leadingZeroBitCount for UInt32:
        // 1 → 31, 2 → 30, 4 → 29, 8 → 28
        let values: [UInt32] = [1, 2, 4, 8, 16, 32, 64, 128]
        let result = mqCoder.vectorLeadingZeros(values: values)
        XCTAssertEqual(result.count, 8)
        XCTAssertEqual(result[0], 31, "1 has 31 leading zeros in UInt32")
        XCTAssertEqual(result[1], 30, "2 has 30 leading zeros in UInt32")
        XCTAssertEqual(result[7], 24, "128 (2^7) has 24 leading zeros in UInt32")
    }

    func testVectorLeadingZerosMaxValue() {
        let mqCoder = X86MQCoderVectorised()
        let values: [UInt32] = [UInt32.max]
        let result = mqCoder.vectorLeadingZeros(values: values)
        XCTAssertEqual(result[0], 0, "UInt32.max has 0 leading zeros")
    }

    func testVectorLeadingZerosZero() {
        let mqCoder = X86MQCoderVectorised()
        let values: [UInt32] = [0]
        let result = mqCoder.vectorLeadingZeros(values: values)
        XCTAssertEqual(result[0], 32, "0 has 32 leading zeros in UInt32")
    }

    func testVectorLeadingZerosLargeInput() {
        let mqCoder = X86MQCoderVectorised()
        let values = [UInt32](repeating: 1, count: 17)
        let result = mqCoder.vectorLeadingZeros(values: values)
        XCTAssertEqual(result.count, 17)
        XCTAssertEqual(result, [Int32](repeating: 31, count: 17))
    }
}
