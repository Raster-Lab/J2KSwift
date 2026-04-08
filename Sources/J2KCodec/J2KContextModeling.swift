//
// J2KContextModeling.swift
// J2KSwift
//
/// # Context Modeling
///
/// Context formation for JPEG 2000 EBCOT bit-plane coding.
///
/// The EBCOT algorithm uses context modeling to adapt the arithmetic coder
/// to local statistics. Contexts are formed based on the significance state
/// of neighboring coefficients, providing efficient compression by exploiting
/// spatial correlation.
///
/// ## Topics
///
/// ### Context Labels
/// - ``EBCOTContext``
///
/// ### Context Formation
/// - ``ContextModeler``

import Foundation
import J2KCore

// MARK: - EBCOT Context Labels

/// Context labels used in EBCOT bit-plane coding.
///
/// The JPEG 2000 standard defines 19 context labels (0-18) that are used
/// for different coding scenarios. These contexts allow the arithmetic
/// coder to maintain separate probability estimates for different situations.
enum EBCOTContext: UInt8, Sendable, CaseIterable {
    // MARK: - Significance Propagation Contexts (0-8)

    /// Zero contribution context for LL/LH subbands.
    case sigPropLL_LH_0 = 0

    /// One horizontal contribution for LL/LH subbands.
    case sigPropLL_LH_1h = 1

    /// One vertical contribution for LL/LH subbands.
    case sigPropLL_LH_1v = 2

    /// Two contributions for LL/LH subbands.
    case sigPropLL_LH_2 = 3

    /// One diagonal contribution for LL/LH subbands.
    case sigPropLL_LH_1d = 4

    /// Horizontal edge context for HL subband.
    case sigPropHL_h = 5

    /// Vertical edge context for HL subband.
    case sigPropHL_v = 6

    /// Horizontal edge context for HH subband.
    case sigPropHH_h = 7

    /// Vertical edge context for HH subband.
    case sigPropHH_v = 8

    // MARK: - Sign Coding Contexts (9-13)

    /// Sign context: horizontal negative, vertical negative.
    case signHnegVneg = 9

    /// Sign context: horizontal zero, vertical negative.
    case signH0Vneg = 10

    /// Sign context: horizontal positive, vertical negative.
    case signHposVneg = 11

    /// Sign context: horizontal negative, vertical zero.
    case signHnegV0 = 12

    /// Sign context: horizontal zero, vertical zero/positive or XOR.
    case signH0V0 = 13

    // MARK: - Magnitude Refinement Contexts (14-16)

    /// First magnitude refinement pass.
    case magRef1 = 14

    /// Second magnitude refinement pass (no significant neighbors).
    case magRef2noSig = 15

    /// Second+ magnitude refinement pass (has significant neighbors).
    case magRef2sig = 16

    // MARK: - Cleanup Pass Contexts (17-18)

    /// Run-length context for cleanup pass.
    case runLength = 17

    /// Uniform context for cleanup pass.
    case uniform = 18

    /// The initial context state index for this context label.
    ///
    /// Per ISO 15444-1 and OpenJPEG's `opj_mqc_reset_enc`:
    /// Only context 0 (ZC), 17 (AGG), and 18 (UNI) get non-zero initial states.
    /// All other contexts default to state 0.
    var initialState: UInt8 {
        switch self {
        case .sigPropLL_LH_0:
            return 4 // T1_CTXNO_ZC initialized to state 4
        case .sigPropLL_LH_1h, .sigPropLL_LH_1v, .sigPropLL_LH_2,
             .sigPropLL_LH_1d, .sigPropHL_h, .sigPropHL_v, .sigPropHH_h, .sigPropHH_v:
            return 0 // Default state
        case .signHnegVneg, .signH0Vneg, .signHposVneg, .signHnegV0, .signH0V0:
            return 0 // Default state
        case .magRef1, .magRef2noSig, .magRef2sig:
            return 0 // Default state
        case .runLength:
            return 3 // Medium probability for run-length
        case .uniform:
            return 46 // Uniform probability
        }
    }
}

// MARK: - Coefficient State

/// Flags representing the state of a coefficient during bit-plane coding.
struct CoefficientState: OptionSet, Sendable {
    let rawValue: UInt8

    /// The coefficient has become significant (non-zero bit found).
    static let significant = CoefficientState(rawValue: 1 << 0)

    /// The coefficient was coded in the current bit-plane.
    static let codedThisPass = CoefficientState(rawValue: 1 << 1)

    /// The sign of the coefficient (if significant): false = positive, true = negative.
    static let signBit = CoefficientState(rawValue: 1 << 2)

    /// The coefficient has been visited in a magnitude refinement pass.
    static let refinementVisited = CoefficientState(rawValue: 1 << 3)

    /// The coefficient is in the current cleanup pass's stripe.
    static let inStripe = CoefficientState(rawValue: 1 << 4)
}

// MARK: - Neighbor Contribution

/// Contribution from neighboring coefficients for context formation.
struct NeighborContribution: Sendable {
    /// Number of significant horizontal neighbors (0-2).
    var horizontal: Int

    /// Number of significant vertical neighbors (0-2).
    var vertical: Int

    /// Number of significant diagonal neighbors (0-4).
    var diagonal: Int

    /// Sign of horizontal neighbors: -1 (all negative), 0 (mixed/none), +1 (all positive).
    var horizontalSign: Int

    /// Sign of vertical neighbors: -1 (all negative), 0 (mixed/none), +1 (all positive).
    var verticalSign: Int

    /// Creates a neighbor contribution with zero values.
    init() {
        self.horizontal = 0
        self.vertical = 0
        self.diagonal = 0
        self.horizontalSign = 0
        self.verticalSign = 0
    }

    /// Creates a neighbor contribution with the specified values.
    init(horizontal: Int, vertical: Int, diagonal: Int,
         horizontalSign: Int = 0, verticalSign: Int = 0) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.diagonal = diagonal
        self.horizontalSign = horizontalSign
        self.verticalSign = verticalSign
    }

    /// Total number of significant neighbors.
    var total: Int {
        horizontal + vertical + diagonal
    }

    /// Whether any neighbors are significant.
    var hasAny: Bool {
        total > 0
    }
}

// MARK: - Context Modeler

/// Forms contexts for EBCOT bit-plane coding based on neighbor states.
///
/// The context modeler examines the significance state of neighboring coefficients
/// and computes the appropriate context label for coding each coefficient.
/// Different subbands (LL, HL, LH, HH) use different context formation rules.
struct ContextModeler: Sendable {
    /// The subband type for context formation.
    let subband: J2KSubband

    /// Computes the significance coding context for a coefficient.
    ///
    /// The context depends on the subband type and the significance state
    /// of the 8 neighbors (horizontal, vertical, and diagonal).
    ///
    /// - Parameter neighbors: The contribution from neighboring coefficients.
    /// - Returns: The context label for significance coding.
    func significanceContext(neighbors: NeighborContribution) -> EBCOTContext {
        let h = neighbors.horizontal
        let v = neighbors.vertical
        let d = neighbors.diagonal

        switch subband {
        case .hl:
            // HL subband: horizontal details, prefer vertical context
            return significanceContextHL(h: h, v: v, d: d)

        case .lh:
            // LH subband: vertical details, prefer horizontal context
            return significanceContextLH(h: h, v: v, d: d)

        case .hh:
            // HH subband: diagonal details
            return significanceContextHH(h: h, v: v, d: d)

        case .ll:
            // LL subband: same as LH
            return significanceContextLH(h: h, v: v, d: d)
        }
    }

    /// Context formation for HL subband (horizontal details).
    /// ISO 15444-1 Table D.1 for HL: vertical neighbors have priority.
    private func significanceContextHL(h: Int, v: Int, d: Int) -> EBCOTContext {
        if v >= 2 {
            return .sigPropHH_v           // context 8
        } else if v == 1 {
            if h >= 1 {
                return .sigPropHH_h       // context 7
            } else if d >= 1 {
                return .sigPropHL_v       // context 6
            } else {
                return .sigPropHL_h       // context 5
            }
        } else {  // v == 0
            if h >= 2 {
                return .sigPropLL_LH_1d   // context 4
            } else if h == 1 {
                return .sigPropLL_LH_2    // context 3
            } else if d >= 2 {
                return .sigPropLL_LH_1v   // context 2
            } else if d == 1 {
                return .sigPropLL_LH_1h   // context 1
            } else {
                return .sigPropLL_LH_0    // context 0
            }
        }
    }

    /// Context formation for LH (and LL) subband (vertical details).
    /// ISO 15444-1 Table D.1 for LL/LH: horizontal neighbors have priority.
    private func significanceContextLH(h: Int, v: Int, d: Int) -> EBCOTContext {
        if h >= 2 {
            return .sigPropHH_v           // context 8
        } else if h == 1 {
            if v >= 1 {
                return .sigPropHH_h       // context 7
            } else if d >= 1 {
                return .sigPropHL_v       // context 6
            } else {
                return .sigPropHL_h       // context 5
            }
        } else {  // h == 0
            if v >= 2 {
                return .sigPropLL_LH_1d   // context 4
            } else if v == 1 {
                return .sigPropLL_LH_2    // context 3
            } else if d >= 2 {
                return .sigPropLL_LH_1v   // context 2
            } else if d == 1 {
                return .sigPropLL_LH_1h   // context 1
            } else {
                return .sigPropLL_LH_0    // context 0
            }
        }
    }

    /// Context formation for HH subband.
    /// ISO 15444-1 Table D.1 for HH: diagonal neighbors have priority.
    private func significanceContextHH(h: Int, v: Int, d: Int) -> EBCOTContext {
        let hv = h + v

        if d >= 3 {
            return .sigPropHH_v           // context 8
        } else if d == 2 {
            if hv >= 1 {
                return .sigPropHH_h       // context 7
            } else {
                return .sigPropHL_v       // context 6
            }
        } else if d == 1 {
            if hv >= 2 {
                return .sigPropHL_h       // context 5
            } else if hv == 1 {
                return .sigPropLL_LH_1d   // context 4
            } else {
                return .sigPropLL_LH_2    // context 3
            }
        } else {
            // d == 0
            if hv >= 2 {
                return .sigPropLL_LH_1v   // context 2
            } else if hv == 1 {
                return .sigPropLL_LH_1h   // context 1
            } else {
                return .sigPropLL_LH_0    // context 0
            }
        }
    }

    /// Computes the sign coding context for a coefficient.
    ///
    /// The sign context depends on the signs of significant horizontal and
    /// vertical neighbors. The context is symmetric with an XOR sign prediction.
    /// Optimised to reduce branching and simplify XOR logic.
    ///
    /// - Parameter neighbors: The contribution from neighboring coefficients.
    /// - Returns: A tuple containing the context label and the sign prediction (XOR bit).
    func signContext(neighbors: NeighborContribution) -> (context: EBCOTContext, xorBit: Bool) {
        let hSign = neighbors.horizontalSign
        let vSign = neighbors.verticalSign

        // Normalise contributions to -1, 0, +1
        let hContrib = hSign == 0 ? 0 : (hSign > 0 ? 1 : -1)
        let vContrib = vSign == 0 ? 0 : (vSign > 0 ? 1 : -1)

        // XOR sign prediction per ISO 15444-1 Table D.3:
        // Flip when h < 0, or when h == 0 and v < 0
        let xorBit = hContrib < 0 || (hContrib == 0 && vContrib < 0)

        let context = signContextFromContributions(h: hContrib, v: vContrib)

        return (context, xorBit)
    }

    /// Maps sign contributions to context label per ISO 15444-1 Table D.3.
    ///
    /// Canonicalizes by flipping signs so h >= 0 (and if h == 0, v >= 0),
    /// then maps to one of five sign contexts (raw values 9-13).
    private func signContextFromContributions(h: Int, v: Int) -> EBCOTContext {
        // Canonicalize: flip so h >= 0, and if h == 0 then v >= 0
        var hc = h, vc = v
        if hc < 0 { hc = -hc; vc = -vc }
        if hc == 0 && vc < 0 { vc = -vc }

        // Map canonical (hc, vc) to context
        if hc == 0 {
            if vc == 0 {
                return .signHnegVneg   // context 9: both zero
            } else {
                return .signH0Vneg     // context 10: h=0, v nonzero
            }
        } else {
            // hc >= 1
            if vc > 0 {
                return .signH0V0       // context 13: same-sign nonzero
            } else if vc < 0 {
                return .signHposVneg   // context 11: opposite-sign nonzero
            } else {
                return .signHnegV0     // context 12: h nonzero, v=0
            }
        }
    }

    /// Computes the magnitude refinement context.
    ///
    /// The context depends on whether this is the first refinement of the coefficient
    /// and whether any neighbors were significant when the coefficient first became significant.
    ///
    /// - Parameters:
    ///   - firstRefinement: True if this is the first magnitude refinement for this coefficient.
    ///   - neighborsWereSignificant: True if neighbors were significant when this coefficient became significant.
    /// - Returns: The context label for magnitude refinement.
    func magnitudeRefinementContext(
        firstRefinement: Bool,
        neighborsWereSignificant: Bool
    ) -> EBCOTContext {
        if !firstRefinement {
            return .magRef2sig       // context 16: subsequent refinement (always)
        } else if neighborsWereSignificant {
            return .magRef2noSig     // context 15: first refinement with significant neighbors
        } else {
            return .magRef1          // context 14: first refinement without significant neighbors
        }
    }
}

// MARK: - Neighbor Calculator

/// Calculates neighbor contributions for a coefficient in a code-block.
///
/// This helper computes the significance and sign contributions from the 8
/// neighbors of a coefficient, handling boundary conditions.
struct NeighborCalculator: Sendable {
    /// The width of the code-block.
    let width: Int

    /// The height of the code-block.
    let height: Int

    /// Calculates the neighbor contribution for a coefficient.
    ///
    /// This method is performance-critical and called once per coefficient per coding pass.
    /// Optimizations include:
    /// - Caching row offsets to avoid repeated multiplication
    /// - Hoisting sign array check outside loops
    /// - Minimizing redundant boundary checks
    ///
    /// - Parameters:
    ///   - x: The x-coordinate of the coefficient.
    ///   - y: The y-coordinate of the coefficient.
    ///   - states: The state array for all coefficients.
    ///   - signs: Optional sign array for sign contribution calculation.
    /// - Returns: The neighbor contribution.
    func calculate(
        x: Int,
        y: Int,
        states: [CoefficientState],
        signs: [Bool]? = nil
    ) -> NeighborContribution {
        var contribution = NeighborContribution()

        // Pre-compute row offsets to avoid repeated multiplication
        let currentRowOffset = y * width
        let topRowOffset = (y - 1) * width
        let bottomRowOffset = (y + 1) * width

        // Check boundary conditions
        let hasLeft = x > 0
        let hasRight = x < width - 1
        let hasTop = y > 0
        let hasBottom = y < height - 1

        // Branch on sign array presence once to avoid repeated optional checks
        if let signs = signs {
            // With sign tracking

            // Horizontal neighbors
            if hasLeft {
                let idx = currentRowOffset + (x - 1)
                if states[idx].contains(.significant) {
                    contribution.horizontal += 1
                    contribution.horizontalSign += signs[idx] ? -1 : 1
                }
            }
            if hasRight {
                let idx = currentRowOffset + (x + 1)
                if states[idx].contains(.significant) {
                    contribution.horizontal += 1
                    contribution.horizontalSign += signs[idx] ? -1 : 1
                }
            }

            // Vertical neighbors
            if hasTop {
                let idx = topRowOffset + x
                if states[idx].contains(.significant) {
                    contribution.vertical += 1
                    contribution.verticalSign += signs[idx] ? -1 : 1
                }
            }
            if hasBottom {
                let idx = bottomRowOffset + x
                if states[idx].contains(.significant) {
                    contribution.vertical += 1
                    contribution.verticalSign += signs[idx] ? -1 : 1
                }
            }

            // Diagonal neighbors (signs not tracked for diagonals)
            if hasTop && hasLeft {
                let idx = topRowOffset + (x - 1)
                if states[idx].contains(.significant) {
                    contribution.diagonal += 1
                }
            }
            if hasTop && hasRight {
                let idx = topRowOffset + (x + 1)
                if states[idx].contains(.significant) {
                    contribution.diagonal += 1
                }
            }
            if hasBottom && hasLeft {
                let idx = bottomRowOffset + (x - 1)
                if states[idx].contains(.significant) {
                    contribution.diagonal += 1
                }
            }
            if hasBottom && hasRight {
                let idx = bottomRowOffset + (x + 1)
                if states[idx].contains(.significant) {
                    contribution.diagonal += 1
                }
            }
        } else {
            // Without sign tracking (faster path)

            // Horizontal neighbors
            if hasLeft && states[currentRowOffset + (x - 1)].contains(.significant) {
                contribution.horizontal += 1
            }
            if hasRight && states[currentRowOffset + (x + 1)].contains(.significant) {
                contribution.horizontal += 1
            }

            // Vertical neighbors
            if hasTop && states[topRowOffset + x].contains(.significant) {
                contribution.vertical += 1
            }
            if hasBottom && states[bottomRowOffset + x].contains(.significant) {
                contribution.vertical += 1
            }

            // Diagonal neighbors
            if hasTop && hasLeft && states[topRowOffset + (x - 1)].contains(.significant) {
                contribution.diagonal += 1
            }
            if hasTop && hasRight && states[topRowOffset + (x + 1)].contains(.significant) {
                contribution.diagonal += 1
            }
            if hasBottom && hasLeft && states[bottomRowOffset + (x - 1)].contains(.significant) {
                contribution.diagonal += 1
            }
            if hasBottom && hasRight && states[bottomRowOffset + (x + 1)].contains(.significant) {
                contribution.diagonal += 1
            }
        }

        return contribution
    }
}

// MARK: - Context State Array

/// Manages the context states for MQ coding.
///
/// This type holds the MQ contexts for all 19 EBCOT context labels,
/// initialised with appropriate probability estimates.
struct ContextStateArray: Sendable {
    /// The MQ contexts for each EBCOT context label.
    var contexts: [MQContext]

    /// Creates a new context state array with default initialisation.
    init() {
        contexts = EBCOTContext.allCases.map { ebcotCtx in
            MQContext(stateIndex: ebcotCtx.initialState, mps: false)
        }
    }

    /// Accesses the MQ context for the specified EBCOT context label.
    subscript(context: EBCOTContext) -> MQContext {
        get {
            EBCOTDebugTrace.shared.currentContextLabel = Int(context.rawValue)
            return contexts[Int(context.rawValue)]
        }
        set { contexts[Int(context.rawValue)] = newValue }
    }

    /// Resets all contexts to their initial states.
    mutating func reset() {
        for (index, ebcotCtx) in EBCOTContext.allCases.enumerated() {
            contexts[index] = MQContext(stateIndex: ebcotCtx.initialState, mps: false)
        }
    }
}
