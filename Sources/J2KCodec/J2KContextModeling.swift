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
    public var initialState: UInt8 {
        switch self {
        case .sigPropLL_LH_0, .sigPropLL_LH_1h, .sigPropLL_LH_1v, .sigPropLL_LH_2,
             .sigPropLL_LH_1d, .sigPropHL_h, .sigPropHL_v, .sigPropHH_h, .sigPropHH_v:
            return 4 // Low probability initial state
        case .signHnegVneg, .signH0Vneg, .signHposVneg, .signHnegV0, .signH0V0:
            return 0 // Uniform initial state for sign
        case .magRef1:
            return 6 // Higher probability for first refinement
        case .magRef2noSig, .magRef2sig:
            return 3 // Medium probability
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
    
    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    /// The coefficient has become significant (non-zero bit found).
    public static let significant = CoefficientState(rawValue: 1 << 0)
    
    /// The coefficient was coded in the current bit-plane.
    public static let codedThisPass = CoefficientState(rawValue: 1 << 1)
    
    /// The sign of the coefficient (if significant): false = positive, true = negative.
    public static let signBit = CoefficientState(rawValue: 1 << 2)
    
    /// The coefficient has been visited in a magnitude refinement pass.
    public static let refinementVisited = CoefficientState(rawValue: 1 << 3)
    
    /// The coefficient is in the current cleanup pass's stripe.
    public static let inStripe = CoefficientState(rawValue: 1 << 4)
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
        return horizontal + vertical + diagonal
    }
    
    /// Whether any neighbors are significant.
    var hasAny: Bool {
        return total > 0
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
    
    /// Creates a context modeler for the specified subband.
    ///
    /// - Parameter subband: The wavelet subband type.
    init(subband: J2KSubband) {
        self.subband = subband
    }
    
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
    /// Optimized to remove redundant branches and simplify logic.
    private func significanceContextHL(h: Int, v: Int, d: Int) -> EBCOTContext {
        // Vertical neighbor presence has priority in HL subband
        if v >= 1 {
            // Any vertical neighbor: use HL_v context (or HL_h if horizontal also present)
            return h >= 1 ? .sigPropHL_h : .sigPropHL_v
        } else if h >= 2 {
            return .sigPropHL_h
        } else if h == 1 {
            return d >= 1 ? .sigPropHL_h : .sigPropLL_LH_1d
        } else if d >= 2 {
            return .sigPropLL_LH_2
        } else if d == 1 {
            return .sigPropLL_LH_1d
        } else {
            return .sigPropLL_LH_0
        }
    }
    
    /// Context formation for LH (and LL) subband (vertical details).
    /// Optimized to remove redundant branches and simplify logic.
    private func significanceContextLH(h: Int, v: Int, d: Int) -> EBCOTContext {
        // Horizontal neighbor presence has priority in LH subband
        if h >= 1 {
            // Horizontal neighbor present
            return v >= 1 ? .sigPropLL_LH_2 : .sigPropLL_LH_1h
        } else if v >= 2 {
            return .sigPropLL_LH_2
        } else if v == 1 {
            // Single vertical neighbor, same context regardless of diagonal
            return .sigPropLL_LH_1v
        } else if d >= 2 {
            return .sigPropLL_LH_2
        } else if d == 1 {
            return .sigPropLL_LH_1d
        } else {
            return .sigPropLL_LH_0
        }
    }
    
    /// Context formation for HH subband.
    ///
    /// Per ISO/IEC 15444-1, Table D.1, orient=3 (HH):
    /// The context depends on diagonal count (d) as primary key
    /// and h+v sum as secondary key.
    private func significanceContextHH(h: Int, v: Int, d: Int) -> EBCOTContext {
        let hv = h + v
        
        if d >= 3 {
            // d >= 3 → context 8
            return .sigPropHH_v
        } else if d == 2 {
            if hv >= 1 {
                // d=2, hv>=1 → context 7
                return .sigPropHH_h
            } else {
                // d=2, hv=0 → context 6
                return .sigPropHL_v
            }
        } else if d == 1 {
            if hv >= 2 {
                // d=1, hv>=2 → context 5
                return .sigPropHL_h
            } else if hv == 1 {
                // d=1, hv=1 → context 4
                return .sigPropLL_LH_1d
            } else {
                // d=1, hv=0 → context 3
                return .sigPropLL_LH_2
            }
        } else {
            // d == 0
            if hv >= 2 {
                // d=0, hv>=2 → context 2
                return .sigPropLL_LH_1v
            } else if hv == 1 {
                // d=0, hv=1 → context 1
                return .sigPropLL_LH_1h
            } else {
                // d=0, hv=0 → context 0
                return .sigPropLL_LH_0
            }
        }
    }
    
    /// Computes the sign coding context for a coefficient.
    ///
    /// The sign context depends on the signs of significant horizontal and
    /// vertical neighbors. The context is symmetric with an XOR sign prediction.
    /// Optimized to reduce branching and simplify XOR logic.
    ///
    /// - Parameter neighbors: The contribution from neighboring coefficients.
    /// - Returns: A tuple containing the context label and the sign prediction (XOR bit).
    func signContext(neighbors: NeighborContribution) -> (context: EBCOTContext, xorBit: Bool) {
        let hSign = neighbors.horizontalSign
        let vSign = neighbors.verticalSign
        
        // XOR prediction is true when exactly one contribution is negative
        let xorBit = (hSign < 0) != (vSign < 0)
        
        // Normalize contributions to -1, 0, +1 and map to context
        let hContrib = hSign == 0 ? 0 : (hSign > 0 ? 1 : -1)
        let vContrib = vSign == 0 ? 0 : (vSign > 0 ? 1 : -1)
        
        let context = signContextFromContributions(h: hContrib, v: vContrib)
        
        return (context, xorBit)
    }
    
    /// Maps sign contributions to context label.
    private func signContextFromContributions(h: Int, v: Int) -> EBCOTContext {
        // Context is symmetric around (0,0)
        // We use absolute values and track the XOR prediction separately
        
        if h == 0 {
            if v == 0 {
                return .signH0V0
            } else {
                // v is non-zero, already normalized
                return .signH0Vneg
            }
        } else if h > 0 {
            if v > 0 {
                return .signH0V0 // Both positive, symmetric to both negative
            } else if v < 0 {
                return .signHposVneg
            } else {
                return .signHnegV0 // Symmetric
            }
        } else {
            // h < 0
            if v > 0 {
                return .signHposVneg // Symmetric to HnegVneg
            } else if v < 0 {
                return .signHnegVneg
            } else {
                return .signHnegV0
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
        if firstRefinement {
            return .magRef1
        } else if neighborsWereSignificant {
            return .magRef2sig
        } else {
            return .magRef2noSig
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
    
    /// Creates a neighbor calculator for the specified code-block dimensions.
    ///
    /// - Parameters:
    ///   - width: The width of the code-block.
    ///   - height: The height of the code-block.
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
    
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
/// initialized with appropriate probability estimates.
struct ContextStateArray: Sendable {
    /// The MQ contexts for each EBCOT context label.
    var contexts: [MQContext]
    
    /// Creates a new context state array with default initialization.
    init() {
        contexts = EBCOTContext.allCases.map { ebcotCtx in
            MQContext(stateIndex: ebcotCtx.initialState, mps: false)
        }
    }
    
    /// Accesses the MQ context for the specified EBCOT context label.
    subscript(context: EBCOTContext) -> MQContext {
        get { contexts[Int(context.rawValue)] }
        set { contexts[Int(context.rawValue)] = newValue }
    }
    
    /// Resets all contexts to their initial states.
    mutating func reset() {
        for (index, ebcotCtx) in EBCOTContext.allCases.enumerated() {
            contexts[index] = MQContext(stateIndex: ebcotCtx.initialState, mps: false)
        }
    }
}
