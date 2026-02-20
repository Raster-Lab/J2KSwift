//
// J2KNeonEntropyTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec

/// Tests for ARM NEON SIMD-optimised entropy coding operations.
///
/// These tests validate correctness of NEON-accelerated MQ-coder context
/// formation, bit-plane coding, significance propagation, and run-length
/// detection. Tests run on all platforms; NEON paths are exercised on ARM64.
final class J2KNeonEntropyTests: XCTestCase {

    // MARK: - Capability Detection

    func testNeonEntropyCodingCapabilityDetection() {
        let cap = NeonEntropyCodingCapability.detect()
        #if arch(arm64)
        XCTAssertTrue(cap.isAvailable, "NEON should be available on ARM64")
        XCTAssertEqual(cap.vectorWidth, 4)
        #else
        XCTAssertFalse(cap.isAvailable, "NEON should not be available on non-ARM64")
        XCTAssertEqual(cap.vectorWidth, 1)
        #endif
    }

    // MARK: - Context Label Computation

    func testBatchContextLabelsNoNeighbours() {
        let formation = NeonContextFormation()
        // 4×4 grid, all insignificant
        let state = [Int32](repeating: 0, count: 16)
        let result = formation.batchContextLabels(
            significanceState: state, width: 4, rowOffset: 0, length: 16
        )
        XCTAssertEqual(result, [Int32](repeating: 0, count: 16))
    }

    func testBatchContextLabelsWithNeighbours() {
        let formation = NeonContextFormation()
        // 4×4 grid with centre coefficient significant
        var state = [Int32](repeating: 0, count: 16)
        state[5] = 1  // Row 1, Col 1

        // Check neighbours of index 6 (Row 1, Col 2): left neighbour is significant
        let result = formation.batchContextLabels(
            significanceState: state, width: 4, rowOffset: 0, length: 16
        )
        // Index 6 should have h=1 (left neighbour significant)
        XCTAssertTrue(result[6] & 0x3 >= 1,
            "Index 6 should have horizontal contribution from neighbour at 5")

        // Index 1 should have diagonal contribution from index 5
        XCTAssertTrue(result[1] > 0,
            "Index 1 should have some contribution from diagonal neighbour at 5")
    }

    func testBatchContextLabelsHorizontalContribution() {
        let formation = NeonContextFormation()
        // 4×1 grid: [1, 0, 1, 0]
        let state: [Int32] = [1, 0, 1, 0]
        let result = formation.batchContextLabels(
            significanceState: state, width: 4, rowOffset: 0, length: 4
        )
        // Index 1 has both left (index 0) and right (index 2) significant → h = 2
        let hContrib = result[1] & 0x3
        XCTAssertEqual(hContrib, 2, "Index 1 should have h=2 from both horizontal neighbours")
    }

    func testBatchContextLabelsVerticalContribution() {
        let formation = NeonContextFormation()
        // 3×4 grid
        var state = [Int32](repeating: 0, count: 12)
        state[1] = 1   // Row 0, Col 1
        state[9] = 1   // Row 2, Col 1

        let result = formation.batchContextLabels(
            significanceState: state, width: 4, rowOffset: 0, length: 12
        )
        // Index 5 (Row 1, Col 1): above and below significant → v = 2
        let vContrib = (result[5] >> 2) & 0x3
        XCTAssertEqual(vContrib, 2, "Index 5 should have v=2 from vertical neighbours")
    }

    func testBatchContextLabelsEmptyInput() {
        let formation = NeonContextFormation()
        let result = formation.batchContextLabels(
            significanceState: [], width: 4, rowOffset: 0, length: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testBatchContextLabelsNonMultipleOfFour() {
        let formation = NeonContextFormation()
        // 5 elements
        let state: [Int32] = [1, 0, 0, 0, 1]
        let result = formation.batchContextLabels(
            significanceState: state, width: 5, rowOffset: 0, length: 5
        )
        XCTAssertEqual(result.count, 5)
        // Index 1: left neighbour (0) is significant → h >= 1
        XCTAssertTrue(result[1] & 0x3 >= 1)
    }

    // MARK: - Significance Propagation

    func testSignificancePropagationCandidates() {
        let coder = NeonBitPlaneCoder()
        // 4×4 grid with one significant coefficient
        var state = [Int32](repeating: 0, count: 16)
        state[5] = 1  // Row 1, Col 1

        let result = coder.significancePropagationCandidates(
            significanceState: state, width: 4, rowOffset: 0, length: 16
        )

        // Index 5 is already significant → should not be a candidate
        XCTAssertEqual(result[5], 0, "Already-significant should not be a candidate")

        // Neighbours of index 5 should be candidates
        XCTAssertEqual(result[1], 1, "Above neighbour should be candidate")
        XCTAssertEqual(result[4], 1, "Left neighbour should be candidate")
        XCTAssertEqual(result[6], 1, "Right neighbour should be candidate")
        XCTAssertEqual(result[9], 1, "Below neighbour should be candidate")
    }

    func testSignificancePropagationNoSignificant() {
        let coder = NeonBitPlaneCoder()
        let state = [Int32](repeating: 0, count: 16)
        let result = coder.significancePropagationCandidates(
            significanceState: state, width: 4, rowOffset: 0, length: 16
        )
        XCTAssertEqual(result, [Int32](repeating: 0, count: 16))
    }

    func testSignificancePropagationAllSignificant() {
        let coder = NeonBitPlaneCoder()
        let state = [Int32](repeating: 1, count: 16)
        let result = coder.significancePropagationCandidates(
            significanceState: state, width: 4, rowOffset: 0, length: 16
        )
        // All already significant → no candidates
        XCTAssertEqual(result, [Int32](repeating: 0, count: 16))
    }

    func testSignificancePropagationEmpty() {
        let coder = NeonBitPlaneCoder()
        let result = coder.significancePropagationCandidates(
            significanceState: [], width: 4, rowOffset: 0, length: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Magnitude Refinement

    func testMagnitudeRefinementBits() {
        let coder = NeonBitPlaneCoder()
        let coefficients: [Int32] = [15, -10, 7, 20, 3, -8, 12, -1]
        let significance: [Int32] = [1, 1, 0, 1, 0, 1, 1, 0]

        let result = coder.magnitudeRefinementBits(
            coefficients: coefficients,
            significanceState: significance,
            bitPlane: 2
        )

        // Only significant coefficients should have refinement bits
        XCTAssertEqual(result[2], 0, "Non-significant should have 0 refinement")
        XCTAssertEqual(result[4], 0, "Non-significant should have 0 refinement")
        XCTAssertEqual(result[7], 0, "Non-significant should have 0 refinement")

        // Significant coefficients: bit at plane 2 of abs(coeff)
        XCTAssertEqual(result[0], (abs(15) >> 2) & 1)  // 15 = 0b1111, bit 2 = 1
        XCTAssertEqual(result[1], (abs(-10) >> 2) & 1)  // 10 = 0b1010, bit 2 = 1
        XCTAssertEqual(result[3], (abs(20) >> 2) & 1)   // 20 = 0b10100, bit 2 = 1
    }

    func testMagnitudeRefinementEmpty() {
        let coder = NeonBitPlaneCoder()
        let result = coder.magnitudeRefinementBits(
            coefficients: [], significanceState: [], bitPlane: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Significance Update

    func testUpdateSignificance() {
        let coder = NeonBitPlaneCoder()
        var state: [Int32] = [0, 0, 0, 0, 1, 0, 0, 0]
        let coefficients: [Int32] = [8, 3, 0, 12, 5, 4, 1, 7]

        coder.updateSignificance(
            significanceState: &state,
            coefficients: coefficients,
            bitPlane: 3
        )

        // Bit 3 of abs(8) = 1 → should become significant
        XCTAssertEqual(state[0], 1, "abs(8) has bit 3 set")
        // Bit 3 of abs(3) = 0 → should stay insignificant
        XCTAssertEqual(state[1], 0, "abs(3) does not have bit 3 set")
        // Index 4 was already significant → should stay significant
        XCTAssertEqual(state[4], 1, "Already significant should stay")
        // Bit 3 of abs(12) = 1 → should become significant
        XCTAssertEqual(state[3], 1, "abs(12) has bit 3 set")
    }

    func testUpdateSignificancePreservesExisting() {
        let coder = NeonBitPlaneCoder()
        var state: [Int32] = [1, 1, 1, 1]
        let coefficients: [Int32] = [0, 0, 0, 0]

        coder.updateSignificance(
            significanceState: &state,
            coefficients: coefficients,
            bitPlane: 0
        )

        // All already significant should stay significant
        XCTAssertEqual(state, [1, 1, 1, 1])
    }

    // MARK: - Sign Context

    func testSignContextComputation() {
        let modelling = NeonContextModelling()
        // 4×4 grid with known signs
        var coefficients = [Int32](repeating: 0, count: 16)
        var significance = [Int32](repeating: 0, count: 16)

        coefficients[4] = 10   // Row 1, Col 0, positive
        significance[4] = 1
        coefficients[6] = -10  // Row 1, Col 2, negative
        significance[6] = 1

        let result = modelling.batchSignContext(
            coefficients: coefficients,
            significanceState: significance,
            width: 4,
            rowOffset: 0,
            length: 16
        )

        // Index 5 (Row 1, Col 1): left positive, right negative → h cancels → 0
        XCTAssertEqual(result[5], 0, "Left positive + right negative should cancel")
    }

    func testSignContextEmpty() {
        let modelling = NeonContextModelling()
        let result = modelling.batchSignContext(
            coefficients: [], significanceState: [],
            width: 4, rowOffset: 0, length: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Run-Length Detection

    func testDetectInsignificantRuns() {
        let modelling = NeonContextModelling()
        let state: [Int32] = [0, 0, 0, 0, 1, 0, 0, 0]

        let result = modelling.detectInsignificantRuns(
            significanceState: state, length: 8, offset: 0
        )

        // First 4 are all zero → should be flagged as run
        XCTAssertEqual(result[0], 1)
        XCTAssertEqual(result[1], 1)
        XCTAssertEqual(result[2], 1)
        XCTAssertEqual(result[3], 1)

        // Second group has a significant coefficient at index 4
        XCTAssertEqual(result[4], 0, "Significant coefficient should not be in run")
    }

    func testDetectInsignificantRunsAllSignificant() {
        let modelling = NeonContextModelling()
        let state: [Int32] = [1, 1, 1, 1]
        let result = modelling.detectInsignificantRuns(
            significanceState: state, length: 4, offset: 0
        )
        XCTAssertEqual(result, [0, 0, 0, 0])
    }

    func testDetectInsignificantRunsEmpty() {
        let modelling = NeonContextModelling()
        let result = modelling.detectInsignificantRuns(
            significanceState: [], length: 0, offset: 0
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Non-Multiple-of-Four Handling

    func testContextLabelsNonMultipleOfFour() {
        let formation = NeonContextFormation()
        let state: [Int32] = [1, 0, 0, 0, 0, 1, 0]
        let result = formation.batchContextLabels(
            significanceState: state, width: 7, rowOffset: 0, length: 7
        )
        XCTAssertEqual(result.count, 7)
    }

    func testMagnitudeRefinementNonMultipleOfFour() {
        let coder = NeonBitPlaneCoder()
        let coefficients: [Int32] = [15, -10, 7, 20, 3]
        let significance: [Int32] = [1, 1, 0, 1, 0]

        let result = coder.magnitudeRefinementBits(
            coefficients: coefficients,
            significanceState: significance,
            bitPlane: 2
        )
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result[4], 0, "Non-significant should be 0")
    }
}
