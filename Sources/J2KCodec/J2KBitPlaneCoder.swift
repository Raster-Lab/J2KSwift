//
// J2KBitPlaneCoder.swift
// J2KSwift
//
/// # Bit-Plane Coder
///
/// Implementation of the EBCOT bit-plane coding algorithm for JPEG 2000.
///
/// The EBCOT (Embedded Block Coding with Optimised Truncation) algorithm encodes
/// wavelet coefficients using three coding passes per bit-plane:
/// 1. Significance Propagation Pass (SPP)
/// 2. Magnitude Refinement Pass (MRP)
/// 3. Cleanup Pass (CP)
///
/// ## Topics
///
/// ### Encoding
/// - ``BitPlaneCoder``
///
/// ### Decoding
/// - ``BitPlaneDecoder``

import Foundation
import J2KCore

// MARK: - Debug Tracing

/// Controls whether EBCOT debug tracing code is compiled in.
/// Set to `true` only when debugging RLC / encoder-decoder mismatches.
/// When `false`, ALL trace calls are compiled out by the optimiser (even
/// in debug builds the branches are trivially dead-stripped).
#if EBCOT_DEBUG_TRACE
@usableFromInline let ebcotTraceEnabled = true
#else
@usableFromInline let ebcotTraceEnabled = false
#endif

/// Temporary debug tracing for RLC investigation
final class EBCOTDebugTrace: @unchecked Sendable {
    static let shared = EBCOTDebugTrace()
    var enabled = false
    var encodeOps: [(String, Int, Int)] = []
    var decodeOps: [(String, Int, Int)] = []
    var encodeMQStates: [(UInt32, UInt32)] = []
    var decodeMQStates: [(UInt32, UInt32)] = []
    
    // Per-pass MQ state snapshots
    var encoderPassStates: [(pass: Int, a: UInt32, c: UInt32, opCount: Int)] = []
    var decoderPassStates: [(pass: Int, a: UInt32, c: UInt32, opCount: Int)] = []
    
    // States snapshots keyed by "pass_N" 
    var encoderStatesSnapshots: [String: [UInt8]] = [:]  // key -> significant flags
    var decoderStatesSnapshots: [String: [UInt8]] = [:]
    
    // Per-symbol MQ trace: (opCount, ctxState, symbol, A, outputOrPos, C)
    var encoderSymbols: [(Int, Int, Bool, UInt32, UInt32, UInt32)] = []
    var decoderSymbols: [(Int, Int, Bool, UInt32, UInt32, UInt32)] = []
    
    // Current context label being encoded/decoded
    var currentContextLabel: Int = -1
    
    func reset() {
        encodeOps = []
        decodeOps = []
        encodeMQStates = []
        decodeMQStates = []
        encoderPassStates = []
        decoderPassStates = []
        encoderStatesSnapshots = [:]
        decoderStatesSnapshots = [:]
        encoderSymbols = []
        decoderSymbols = []
        encoderContextStates = [:]
        decoderContextStates = [:]
    }
    
    func logEncode(_ op: String, x: Int, y: Int, a: UInt32 = 0, c: UInt32 = 0) {
        guard enabled else { return }
        encodeOps.append((op, x, y))
        encodeMQStates.append((a, c))
    }
    
    func logDecode(_ op: String, x: Int, y: Int, a: UInt32 = 0, c: UInt32 = 0) {
        guard enabled else { return }
        decodeOps.append((op, x, y))
        decodeMQStates.append((a, c))
    }
    
    func logEncoderPassEnd(pass: Int, a: UInt32, c: UInt32, opCount: Int) {
        guard enabled else { return }
        encoderPassStates.append((pass, a, c, opCount))
    }
    
    func logDecoderPassEnd(pass: Int, a: UInt32, c: UInt32, opCount: Int) {
        guard enabled else { return }
        decoderPassStates.append((pass, a, c, opCount))
    }
    
    // Context state snapshots at pass boundaries
    var encoderContextStates: [Int: [(Int, Bool)]] = [:]  // pass -> [(stateIndex, mps)]
    var decoderContextStates: [Int: [(Int, Bool)]] = [:]
    
    func saveEncoderContexts(_ pass: Int, _ contexts: ContextStateArray) {
        guard enabled else { return }
        encoderContextStates[pass] = contexts.contexts.map { (Int($0.stateIndex), $0.mps) }
    }
    
    func saveDecoderContexts(_ pass: Int, _ contexts: ContextStateArray) {
        guard enabled else { return }
        decoderContextStates[pass] = contexts.contexts.map { (Int($0.stateIndex), $0.mps) }
    }
    
    func saveEncoderStates(_ key: String, _ states: [CoefficientState]) {
        guard enabled else { return }
        encoderStatesSnapshots[key] = states.map { s in
            var v: UInt8 = 0
            if s.contains(.significant) { v |= 1 }
            if s.contains(.signBit) { v |= 2 }
            return v
        }
    }
    
    func saveDecoderStates(_ key: String, _ states: [CoefficientState]) {
        guard enabled else { return }
        decoderStatesSnapshots[key] = states.map { s in
            var v: UInt8 = 0
            if s.contains(.significant) { v |= 1 }
            if s.contains(.signBit) { v |= 2 }
            return v
        }
    }
}

// MARK: - Coding Pass Type

/// The type of coding pass in EBCOT bit-plane coding.
enum CodingPassType: Sendable {
    /// Significance propagation pass.
    case significancePropagation

    /// Magnitude refinement pass.
    case magnitudeRefinement

    /// Cleanup pass.
    case cleanup
}

// MARK: - Coding Options

/// Configuration options for bit-plane coding.
///
/// These options control the encoding behavior, including bypass mode and termination.
struct CodingOptions: Sendable {
    /// Enable selective arithmetic coding bypass mode.
    ///
    /// When enabled, magnitude refinement passes after a certain bit-plane
    /// use raw (bypass) mode instead of context-adaptive arithmetic coding.
    let bypassEnabled: Bool

    /// The bit-plane index at which to start using bypass mode.
    ///
    /// Only applies when `bypassEnabled` is true. Bypass mode is used for
    /// magnitude refinement passes in bit-planes less than this threshold.
    /// A value of 0 disables bypass mode effectively.
    let bypassThreshold: Int

    /// The termination mode for arithmetic coding.
    ///
    /// Controls how the MQ-coder terminates its encoded output. Different
    /// modes offer trade-offs between compression efficiency and error resilience.
    let terminationMode: TerminationMode

    /// Use ISO/IEC 15444-1 compliant RLC position encoding.
    ///
    /// When true, uses 2-bit UNIFORM context to encode the position of the first
    /// significant coefficient in an RLC-eligible stripe column. When false, uses
    /// the legacy fallthrough approach where each coefficient is individually tested.
    let useISOPositionEncoding: Bool

    /// Whether to reset the encoder after each coding pass (predictable termination).
    ///
    /// When enabled, the encoder state is reset after each coding pass,
    /// allowing independent decoding of each pass. This is automatically
    /// enabled when `terminationMode` is `.predictable`.
    var resetOnEachPass: Bool {
        terminationMode == .predictable
    }

    /// Creates new coding options.
    ///
    /// - Parameters:
    ///   - bypassEnabled: Enable bypass mode (default: false).
    ///   - bypassThreshold: Bit-plane threshold for bypass (default: 0).
    ///   - terminationMode: The termination mode (default: `.default`).
    ///   - useISOPositionEncoding: Use ISO RLC position encoding (default: false).
    init(
        bypassEnabled: Bool = false,
        bypassThreshold: Int = 0,
        terminationMode: TerminationMode = .default,
        useISOPositionEncoding: Bool = true
    ) {
        self.bypassEnabled = bypassEnabled
        self.bypassThreshold = max(0, bypassThreshold)
        self.terminationMode = terminationMode
        self.useISOPositionEncoding = useISOPositionEncoding
    }

    /// Default coding options (no bypass, default termination).
    static let `default` = CodingOptions()

    /// Typical bypass configuration for improved speed.
    ///
    /// Enables bypass mode for magnitude refinement passes in the lower 4 bit-planes.
    static let fastEncoding = CodingOptions(bypassEnabled: true, bypassThreshold: 4)

    /// Predictable termination for error resilience.
    ///
    /// Each coding pass can be independently decoded, enabling error resilience
    /// and parallel decoding at the cost of compression efficiency.
    static let errorResilient = CodingOptions(terminationMode: .predictable)

    /// Near-optimal termination for better compression.
    ///
    /// Uses a tighter termination sequence to minimise wasted bits.
    static let optimalCompression = CodingOptions(terminationMode: .nearOptimal)
}

// MARK: - Bit-Plane Coder

/// Encodes wavelet coefficients using EBCOT bit-plane coding.
///
/// The bit-plane coder processes coefficients from most significant to least
/// significant bit-plane. Each bit-plane is coded in three passes that handle
/// different coefficient states efficiently.
///
/// ## Example
///
/// ```swift
/// var coder = BitPlaneCoder(width: 32, height: 32, subband: .ll)
/// let coefficients: [Int32] = ... // Wavelet coefficients
/// let encoded = try coder.encode(coefficients: coefficients, bitDepth: 12)
/// ```
struct BitPlaneCoder: Sendable {
    /// The width of the code-block.
    let width: Int

    /// The height of the code-block.
    let height: Int

    /// The subband type for context formation.
    let subband: J2KSubband

    /// The context modeler for this subband.
    private let contextModeler: ContextModeler

    /// The neighbor calculator.
    private let neighborCalculator: NeighborCalculator

    /// Coding options for this encoder.
    private let options: CodingOptions

    /// Creates a new bit-plane coder for the specified dimensions and subband.
    ///
    /// - Parameters:
    ///   - width: The width of the code-block in samples.
    ///   - height: The height of the code-block in samples.
    ///   - subband: The wavelet subband type.
    ///   - options: Coding options (default: `.default`).
    init(width: Int, height: Int, subband: J2KSubband, options: CodingOptions = .default) {
        self.width = width
        self.height = height
        self.subband = subband
        self.contextModeler = ContextModeler(subband: subband)
        self.neighborCalculator = NeighborCalculator(width: width, height: height)
        self.options = options
    }

    /// Encodes wavelet coefficients using EBCOT bit-plane coding.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients to encode.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - maxPasses: Maximum number of coding passes to generate (optional).
    /// - Returns: A tuple containing the encoded data, the number of coding passes,
    ///   the number of zero bit-planes, per-pass segment lengths, cumulative per-pass byte counts,
    ///   and cumulative per-pass distortion decrements.
    /// - Throws: ``J2KError`` if encoding fails.
    func encode(
        coefficients: [Int32],
        bitDepth: Int,
        maxPasses: Int? = nil
    ) throws -> (data: Data, passCount: Int, zeroBitPlanes: Int, passSegmentLengths: [Int], cumulativePassBytes: [Int], cumulativePassDistortion: [Double], perPassSnapshotData: [Data]) {
        guard coefficients.count == width * height else {
            throw J2KError.invalidParameter("Coefficient count mismatch")
        }

        // Find the number of zero bit-planes (MSBs that are all zero)
        let (magnitudes, signs) = separateMagnitudesAndSigns(coefficients)
        let maxMagnitude = magnitudes.max() ?? 0
        let activeBitPlanes = maxMagnitude > 0 ? Int(log2(Double(maxMagnitude))) + 1 : 0
        let zeroBitPlanes = max(0, bitDepth - activeBitPlanes)

        if ProcessInfo.processInfo.environment["J2K_DUMP_PASSES"] != nil {
            print("EBCOT: w=\(width) h=\(height) bitDepth=\(bitDepth) maxMag=\(maxMagnitude) active=\(activeBitPlanes) zbp=\(zeroBitPlanes) maxPassLimit=\(maxPasses ?? (3 * activeBitPlanes))")
        }

        // Initialise state arrays
        var states = [CoefficientState](repeating: [], count: width * height)
        var firstRefineFlags = [Bool](repeating: false, count: width * height)
        let signArray = signs

        // Initialise MQ encoder and contexts
        var encoder = MQEncoder()
        var contextStates = ContextStateArray()

        // When bypass mode is enabled, per-pass segments are required for bypass
        // bit-planes to separate MQ-coded and raw-coded data per JPEG 2000 standard.
        let usePerPassSegments = options.resetOnEachPass || options.bypassEnabled

        // Track cumulative byte count after each pass for rate control truncation.
        // In non-per-pass mode, we use the MQ encoder's approximate byte position.
        var cumulativePassBytes: [Int] = []

        // Per-pass terminated MQ data for correct truncation.
        // Each entry is a properly terminated copy of the MQ byte stream
        // at that pass boundary, avoiding carry-corrupted prefixes of
        // the final stream.
        var perPassSnapshotData: [Data] = []

        // Per-pass actual distortion tracking for accurate PCRD.
        // cumulativeDistReduction[i] = total squared-error reduction achieved
        // by including passes 0..i (vs. zero reconstruction).
        var cumulativePassDistortion: [Double] = []
        // Per-coefficient current reconstruction magnitude
        var recon = [UInt32](repeating: 0, count: width * height)
        var cumulativeDistReduction: Double = 0.0

        // For per-pass termination, we collect pass data separately
        var passDataSegments: [Data] = []
        var runningSegmentTotal = 0

        var passCount = 0
        let maxPassLimit = maxPasses ?? (3 * activeBitPlanes)

        // Process each bit-plane from MSB to LSB
        for bitPlane in stride(from: activeBitPlanes - 1, through: 0, by: -1) {
            let bitMask: UInt32 = 1 << bitPlane

            // Determine if bypass mode should be used for this bit-plane
            let useBypass = options.bypassEnabled && bitPlane < options.bypassThreshold

            // Per ISO 15444-1 Annex D: the first coding pass of the most
            // significant bit-plane is the cleanup pass only.
            let isFirstBitPlane = (bitPlane == activeBitPlanes - 1)

            // Pass 1: Significance Propagation Pass (skip for MSB bit-plane)
            if !isFirstBitPlane && passCount < maxPassLimit {
                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logEncode("=== SIGPROP bitPlane=\(bitPlane) pass=\(passCount) ===", x: -1, y: -1) }
                encodeSignificancePropagationPass(
                    magnitudes: magnitudes,
                    signs: signArray,
                    states: &states,
                    bitMask: bitMask,
                    encoder: &encoder,
                    contexts: &contextStates
                )
                if ebcotTraceEnabled && EBCOTDebugTrace.shared.enabled {
                    let sigCount = states.filter { $0.contains(.significant) }.count
                    var sigHash: UInt64 = 0
                    for (i, s) in states.enumerated() {
                        if s.contains(.significant) {
                            sigHash = sigHash &+ UInt64(i &* 2654435761)
                        }
                    }
                    EBCOTDebugTrace.shared.logEncode("POST_SIGPROP sig=\(sigCount) hash=\(sigHash)", x: -1, y: -1)
                    EBCOTDebugTrace.shared.saveEncoderStates("sigprop_bp\(bitPlane)", states)
                }
                if ebcotTraceEnabled {
                    EBCOTDebugTrace.shared.logEncoderPassEnd(pass: passCount, a: encoder.debugA, c: encoder.debugC, opCount: encoder.operationCount)
                    EBCOTDebugTrace.shared.saveEncoderContexts(passCount, contextStates)
                }
                passCount += 1

                // For per-pass mode, finish and reset after each pass
                if usePerPassSegments {
                    let passData = encoder.finish(mode: options.terminationMode)
                    passDataSegments.append(passData)
                    encoder.reset()
                    contextStates.reset()
                    runningSegmentTotal += passData.count
                    cumulativePassBytes.append(runningSegmentTotal)
                } else {
                    // Snapshot the MQ encoder to get exact byte count at this
                    // truncation point. MQEncoder is a value type so the copy
                    // is independent; finishing the snapshot doesn't affect
                    // the live encoder.
                    var snapshot = encoder
                    let snapshotData = snapshot.finish(mode: options.terminationMode)
                    cumulativePassBytes.append(snapshotData.count)
                    perPassSnapshotData.append(snapshotData)
                }
                // Distortion: newly significant coefficients from SPP
                let sppDelta = computeNewSignificanceDistortion(
                    states: &states, magnitudes: magnitudes,
                    recon: &recon, bitPlane: bitPlane
                )
                cumulativeDistReduction += sppDelta
                cumulativePassDistortion.append(cumulativeDistReduction)
            }

            // Pass 2: Magnitude Refinement Pass (skip for MSB bit-plane)
            if !isFirstBitPlane && passCount < maxPassLimit {
                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logEncode("=== MAGREF bitPlane=\(bitPlane) pass=\(passCount) ===", x: -1, y: -1) }
                if useBypass {
                    // Use separate raw bypass encoder for bypass mode
                    var bypassEncoder = RawBypassEncoder()
                    encodeMagnitudeRefinementPassBypass(
                        magnitudes: magnitudes,
                        states: &states,
                        firstRefineFlags: &firstRefineFlags,
                        bitMask: bitMask,
                        bypassEncoder: &bypassEncoder
                    )
                    passCount += 1
                    let passData = bypassEncoder.finish()
                    passDataSegments.append(passData)
                    runningSegmentTotal += passData.count
                    cumulativePassBytes.append(runningSegmentTotal)
                    // Distortion: refined coefficients from bypass MRP
                    let mrpDelta = computeRefinementDistortion(
                        states: &states, magnitudes: magnitudes,
                        recon: &recon, bitPlane: bitPlane
                    )
                    cumulativeDistReduction += mrpDelta
                    cumulativePassDistortion.append(cumulativeDistReduction)
                } else {
                    encodeMagnitudeRefinementPass(
                        magnitudes: magnitudes,
                        states: &states,
                        firstRefineFlags: &firstRefineFlags,
                        bitMask: bitMask,
                        encoder: &encoder,
                        contexts: &contextStates,
                        useBypass: false
                    )
                    if ebcotTraceEnabled && EBCOTDebugTrace.shared.enabled {
                        let sigCount = states.filter { $0.contains(.significant) }.count
                        EBCOTDebugTrace.shared.logEncode("POST_MAGREF sig=\(sigCount)", x: -1, y: -1)
                    }
                    if ebcotTraceEnabled {
                        EBCOTDebugTrace.shared.logEncoderPassEnd(pass: passCount, a: encoder.debugA, c: encoder.debugC, opCount: encoder.operationCount)
                        EBCOTDebugTrace.shared.saveEncoderContexts(passCount, contextStates)
                    }
                    passCount += 1

                    // For per-pass mode, finish and reset after each pass
                    if usePerPassSegments {
                        let passData = encoder.finish(mode: options.terminationMode)
                        passDataSegments.append(passData)
                        encoder.reset()
                        contextStates.reset()
                        runningSegmentTotal += passData.count
                        cumulativePassBytes.append(runningSegmentTotal)
                    } else {
                        var snapshot = encoder
                        let snapshotData = snapshot.finish(mode: options.terminationMode)
                        cumulativePassBytes.append(snapshotData.count)
                        perPassSnapshotData.append(snapshotData)
                    }
                    // Distortion: refined coefficients from MRP
                    let mrpDelta2 = computeRefinementDistortion(
                        states: &states, magnitudes: magnitudes,
                        recon: &recon, bitPlane: bitPlane
                    )
                    cumulativeDistReduction += mrpDelta2
                    cumulativePassDistortion.append(cumulativeDistReduction)
                }
            }

            // Pass 3: Cleanup Pass
            if passCount < maxPassLimit {
                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logEncode("=== CLEANUP bitPlane=\(bitPlane) pass=\(passCount) ===", x: -1, y: -1) }
                encodeCleanupPass(
                    magnitudes: magnitudes,
                    signs: signArray,
                    states: &states,
                    bitMask: bitMask,
                    encoder: &encoder,
                    contexts: &contextStates
                )
                // Count significant coefficients after cleanup
                if ebcotTraceEnabled && EBCOTDebugTrace.shared.enabled {
                    let sigCount = states.filter { $0.contains(.significant) }.count
                    let sbitCount = states.filter { $0.contains(.signBit) }.count
                    var sigHash: UInt64 = 0
                    for (i, s) in states.enumerated() {
                        if s.contains(.significant) {
                            sigHash = sigHash &+ UInt64(i &* 2654435761)
                        }
                    }
                    EBCOTDebugTrace.shared.logEncode("POST_CLEANUP sig=\(sigCount) sbit=\(sbitCount) hash=\(sigHash)", x: -1, y: -1)
                    EBCOTDebugTrace.shared.saveEncoderStates("cleanup_bp\(bitPlane)", states)
                }
                if ebcotTraceEnabled {
                    EBCOTDebugTrace.shared.logEncoderPassEnd(pass: passCount, a: encoder.debugA, c: encoder.debugC, opCount: encoder.operationCount)
                    EBCOTDebugTrace.shared.saveEncoderContexts(passCount, contextStates)
                }
                passCount += 1

                // For per-pass mode, finish and reset after each pass
                if usePerPassSegments {
                    let passData = encoder.finish(mode: options.terminationMode)
                    passDataSegments.append(passData)
                    encoder.reset()
                    contextStates.reset()
                    runningSegmentTotal += passData.count
                    cumulativePassBytes.append(runningSegmentTotal)
                } else {
                    var snapshot = encoder
                    let snapshotData = snapshot.finish(mode: options.terminationMode)
                    cumulativePassBytes.append(snapshotData.count)
                    perPassSnapshotData.append(snapshotData)
                }
                // Distortion: newly significant coefficients from CUP
                let cupDelta = computeNewSignificanceDistortion(
                    states: &states, magnitudes: magnitudes,
                    recon: &recon, bitPlane: bitPlane
                )
                cumulativeDistReduction += cupDelta
                cumulativePassDistortion.append(cumulativeDistReduction)
            }

            // Clear coded-this-pass flags for next bit-plane (batch bitwise)
            let clearMask = ~CoefficientState.codedThisPass.rawValue
            states.withUnsafeMutableBufferPointer { buf in
                for i in 0..<buf.count {
                    buf[i] = CoefficientState(rawValue: buf[i].rawValue & clearMask)
                }
            }
        }

        // Finish encoding
        let encodedData: Data
        var segmentLengths: [Int] = []
        if usePerPassSegments {
            // Concatenate all pass data segments
            var combinedData = Data()
            for segment in passDataSegments {
                segmentLengths.append(segment.count)
                combinedData.append(segment)
            }
            encodedData = combinedData
        } else {
            // Single termination at the end
            encodedData = encoder.finish(mode: options.terminationMode)
            // Snapshot-based byte estimation already gives exact truncation
            // sizes (each pass snapshot terminates a copy of the MQ encoder),
            // so no rescaling is needed. Just clamp the last entry to the
            // actual final size for safety.
            if let last = cumulativePassBytes.indices.last {
                cumulativePassBytes[last] = encodedData.count
            }
        }

        if ProcessInfo.processInfo.environment["J2K_DUMP_PASSES"] != nil {
            print("EBCOT_RESULT: passCount=\(passCount) dataBytes=\(encodedData.count) zbp=\(zeroBitPlanes)")
        }

        return (encodedData, passCount, zeroBitPlanes, segmentLengths, cumulativePassBytes, cumulativePassDistortion, perPassSnapshotData)
    }

    /// Separates coefficients into magnitudes and signs.
    private func separateMagnitudesAndSigns(_ coefficients: [Int32]) -> ([UInt32], [Bool]) {
        let count = coefficients.count
        var magnitudes = [UInt32](repeating: 0, count: count)
        var signs = [Bool](repeating: false, count: count)

        // SIMD-optimised path: process 4 coefficients at a time using SIMD4
        let simdCount = count / 4
        let remainder = count % 4

        coefficients.withUnsafeBufferPointer { coeffPtr in
            magnitudes.withUnsafeMutableBufferPointer { magPtr in
                signs.withUnsafeMutableBufferPointer { signPtr in
                    let coeffBase = coeffPtr.baseAddress!
                    let magBase = magPtr.baseAddress!
                    let signBase = signPtr.baseAddress!

                    for i in 0..<simdCount {
                        let offset = i * 4
                        // Load 4 coefficients into SIMD vector
                        let v = SIMD4<Int32>(
                            coeffBase[offset],
                            coeffBase[offset + 1],
                            coeffBase[offset + 2],
                            coeffBase[offset + 3]
                        )

                        // Compute absolute values using SIMD
                        let negative = v .< SIMD4<Int32>.zero
                        let absV = v.replacing(with: SIMD4<Int32>.zero &- v, where: negative)

                        // Store magnitudes
                        magBase[offset] = UInt32(bitPattern: absV[0])
                        magBase[offset + 1] = UInt32(bitPattern: absV[1])
                        magBase[offset + 2] = UInt32(bitPattern: absV[2])
                        magBase[offset + 3] = UInt32(bitPattern: absV[3])

                        // Store signs
                        signBase[offset] = negative[0]
                        signBase[offset + 1] = negative[1]
                        signBase[offset + 2] = negative[2]
                        signBase[offset + 3] = negative[3]
                    }

                    // Handle remainder
                    let remStart = simdCount * 4
                    for i in 0..<remainder {
                        let idx = remStart + i
                        let coeff = coeffBase[idx]
                        if coeff < 0 {
                            magBase[idx] = UInt32(-coeff)
                            signBase[idx] = true
                        } else {
                            magBase[idx] = UInt32(coeff)
                            signBase[idx] = false
                        }
                    }
                }
            }
        }

        return (magnitudes, signs)
    }

    // MARK: - Significance Propagation Pass

    /// Encodes the significance propagation pass.
    ///
    /// This pass codes coefficients that are not yet significant but have at least
    /// one significant neighbor. It exploits the spatial correlation between
    /// neighboring coefficients.
    private func encodeSignificancePropagationPass(
        magnitudes: [UInt32],
        signs: [Bool],
        states: inout [CoefficientState],
        bitMask: UInt32,
        encoder: inout MQEncoder,
        contexts: inout ContextStateArray
    ) {
        let stripeHeight = 4
        let w = width
        let h = height

        magnitudes.withUnsafeBufferPointer { magBuf in
            signs.withUnsafeBufferPointer { signBuf in
                states.withUnsafeMutableBufferPointer { stateBuf in
                    let magPtr = magBuf.baseAddress!
                    let signPtr = signBuf.baseAddress!
                    let statePtr = stateBuf.baseAddress!

                    for stripeY in stride(from: 0, to: h, by: stripeHeight) {
                        let stripeEnd = min(stripeY + stripeHeight, h)

                        for x in 0..<w {
                            for y in stripeY..<stripeEnd {
                                let idx = y &* w &+ x

                                let st = statePtr[idx]
                                if st.contains(.significant) || st.contains(.codedThisPass) {
                                    continue
                                }

                                let neighbors = neighborCalculator.calculateUnsafe(
                                    x: x, y: y,
                                    states: statePtr,
                                    signs: signPtr,
                                    hasSigns: true
                                )

                                guard neighbors.hasAny else { continue }

                                let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                                let isSignificant = (magPtr[idx] & bitMask) != 0

                                encoder.encode(symbol: isSignificant, context: &contexts[sigContext])

                                if isSignificant {
                                    let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                                    let signBit = signPtr[idx]
                                    let codedSign = signBit != xorBit
                                    encoder.encode(symbol: codedSign, context: &contexts[signContext])

                                    statePtr[idx].insert(.significant)
                                    if signBit {
                                        statePtr[idx].insert(.signBit)
                                    }
                                }

                                statePtr[idx].insert(.codedThisPass)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Magnitude Refinement Pass

    /// Encodes the magnitude refinement pass.
    ///
    /// This pass refines the magnitude of coefficients that are already significant
    /// by coding additional bits from subsequent bit-planes. Can use bypass mode
    /// for improved encoding speed.
    ///
    /// - Parameters:
    ///   - magnitudes: The coefficient magnitudes.
    ///   - states: The coefficient states.
    ///   - firstRefineFlags: Flags indicating first refinement for each coefficient.
    ///   - bitMask: The bit mask for this bit-plane.
    ///   - encoder: The MQ encoder.
    ///   - contexts: The context states.
    ///   - useBypass: Whether to use bypass (raw) mode instead of arithmetic coding.
    private func encodeMagnitudeRefinementPass(
        magnitudes: [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        bitMask: UInt32,
        encoder: inout MQEncoder,
        contexts: inout ContextStateArray,
        useBypass: Bool = false
    ) {
        let stripeHeight = 4
        let w = width
        let h = height

        magnitudes.withUnsafeBufferPointer { magBuf in
            states.withUnsafeMutableBufferPointer { stateBuf in
                firstRefineFlags.withUnsafeMutableBufferPointer { refineBuf in
                    let magPtr = magBuf.baseAddress!
                    let statePtr = stateBuf.baseAddress!
                    let refinePtr = refineBuf.baseAddress!

                    for stripeY in stride(from: 0, to: h, by: stripeHeight) {
                        let stripeEnd = min(stripeY + stripeHeight, h)

                        for x in 0..<w {
                            for y in stripeY..<stripeEnd {
                                let idx = y &* w &+ x

                                let st = statePtr[idx]
                                guard st.contains(.significant) else { continue }
                                guard !st.contains(.codedThisPass) else { continue }

                                let bitValue = (magPtr[idx] & bitMask) != 0

                                if useBypass {
                                    encoder.encodeBypass(symbol: bitValue)
                                } else {
                                    let isFirstRefinement = !refinePtr[idx]

                                    let neighbors = neighborCalculator.calculateUnsafe(
                                        x: x, y: y,
                                        states: statePtr,
                                        signs: nil,
                                        hasSigns: false
                                    )
                                    let hasSignificantNeighbors = neighbors.hasAny

                                    let magContext = contextModeler.magnitudeRefinementContext(
                                        firstRefinement: isFirstRefinement,
                                        neighborsWereSignificant: hasSignificantNeighbors
                                    )

                                    encoder.encode(symbol: bitValue, context: &contexts[magContext])
                                }

                                if !refinePtr[idx] {
                                    refinePtr[idx] = true
                                }

                                statePtr[idx].insert(.codedThisPass)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Encodes the magnitude refinement pass using raw bypass coding.
    ///
    /// This method uses a separate `RawBypassEncoder` to write raw bits directly
    /// without context-adaptive arithmetic coding, providing faster encoding.
    ///
    /// - Parameters:
    ///   - magnitudes: The coefficient magnitudes.
    ///   - states: The coefficient states.
    ///   - firstRefineFlags: Flags indicating first refinement for each coefficient.
    ///   - bitMask: The bit mask for this bit-plane.
    ///   - bypassEncoder: The raw bypass encoder.
    private func encodeMagnitudeRefinementPassBypass(
        magnitudes: [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        bitMask: UInt32,
        bypassEncoder: inout RawBypassEncoder
    ) {
        // JPEG 2000 requires stripe-based column-major scan order
        let stripeHeight = 4

        for stripeY in stride(from: 0, to: height, by: stripeHeight) {
            let stripeEnd = min(stripeY + stripeHeight, height)

            for x in 0..<width {
                for y in stripeY..<stripeEnd {
                    let idx = y * width + x

                    guard states[idx].contains(.significant) else { continue }
                    guard !states[idx].contains(.codedThisPass) else { continue }

                    let bitValue = (magnitudes[idx] & bitMask) != 0
                    bypassEncoder.encode(symbol: bitValue)

                    if !firstRefineFlags[idx] {
                        firstRefineFlags[idx] = true
                    }

                    states[idx].insert(.codedThisPass)
                }
            }
        }
    }

    // MARK: - Cleanup Pass

    /// Encodes the cleanup pass.
    ///
    /// This pass codes all remaining coefficients that were not coded in the
    /// significance propagation or magnitude refinement passes. It uses run-length
    /// coding for efficiency when processing stripes of 4 rows.
    private func encodeCleanupPass(
        magnitudes: [UInt32],
        signs: [Bool],
        states: inout [CoefficientState],
        bitMask: UInt32,
        encoder: inout MQEncoder,
        contexts: inout ContextStateArray
    ) {
        let stripeHeight = 4
        let w = width
        let h = height

        magnitudes.withUnsafeBufferPointer { magBuf in
            signs.withUnsafeBufferPointer { signBuf in
                states.withUnsafeMutableBufferPointer { stateBuf in
                    let magPtr = magBuf.baseAddress!
                    let signPtr = signBuf.baseAddress!
                    let statePtr = stateBuf.baseAddress!

        for stripeY in stride(from: 0, to: h, by: stripeHeight) {
            let stripeEnd = min(stripeY + stripeHeight, h)

            for x in 0..<w {
                let eligible = isEligibleForRunLengthCodingUnsafe(
                    x: x,
                    stripeStart: stripeY,
                    stripeEnd: stripeEnd,
                    states: statePtr
                )
                
                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logEncode("elig=\(eligible)", x: x, y: stripeY) }

                if eligible {
                    let hasSignificant = anyBecomeSignificantUnsafe(
                        x: x,
                        stripeStart: stripeY,
                        stripeEnd: stripeEnd,
                        magnitudes: magPtr,
                        bitMask: bitMask
                    )

                    encoder.encode(symbol: hasSignificant, context: &contexts[.runLength])

                    if !hasSignificant {
                        for y in stripeY..<stripeEnd {
                            let idx = y &* w &+ x
                            statePtr[idx].insert(.codedThisPass)
                        }
                        continue
                    }

                    if options.useISOPositionEncoding {
                        var firstSigPos = 0
                        for i in 0..<(stripeEnd - stripeY) {
                            let idx = (stripeY &+ i) &* w &+ x
                            if (magPtr[idx] & bitMask) != 0 {
                                firstSigPos = i
                                break
                            }
                        }

                        encoder.encode(symbol: (firstSigPos & 0x02) != 0, context: &contexts[.uniform])
                        encoder.encode(symbol: (firstSigPos & 0x01) != 0, context: &contexts[.uniform])

                        for i in 0..<firstSigPos {
                            let idx = (stripeY &+ i) &* w &+ x
                            statePtr[idx].insert(.codedThisPass)
                        }

                        let firstIdx = (stripeY &+ firstSigPos) &* w &+ x
                        let firstNeighbors = neighborCalculator.calculateUnsafe(
                            x: x, y: stripeY + firstSigPos,
                            states: statePtr,
                            signs: signPtr,
                            hasSigns: true
                        )
                        let (firstSignCtx, firstXorBit) = contextModeler.signContext(neighbors: firstNeighbors)
                        let firstSignBit = signPtr[firstIdx]
                        let firstCodedSign = firstSignBit != firstXorBit
                        encoder.encode(symbol: firstCodedSign, context: &contexts[firstSignCtx])

                        statePtr[firstIdx].insert(.significant)
                        if firstSignBit {
                            statePtr[firstIdx].insert(.signBit)
                        }
                        statePtr[firstIdx].insert(.codedThisPass)

                        for y in (stripeY + firstSigPos + 1)..<stripeEnd {
                            let idx = y &* w &+ x

                            let st = statePtr[idx]
                            if st.contains(.codedThisPass) || st.contains(.significant) {
                                continue
                            }

                            let neighbors = neighborCalculator.calculateUnsafe(
                                x: x, y: y,
                                states: statePtr,
                                signs: signPtr,
                                hasSigns: true
                            )

                            let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                            let isSignificant = (magPtr[idx] & bitMask) != 0
                            encoder.encode(symbol: isSignificant, context: &contexts[sigContext])

                            if isSignificant {
                                let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                                let signBit = signPtr[idx]
                                let codedSign = signBit != xorBit
                                encoder.encode(symbol: codedSign, context: &contexts[signContext])

                                statePtr[idx].insert(.significant)
                                if signBit {
                                    statePtr[idx].insert(.signBit)
                                }
                            }

                            statePtr[idx].insert(.codedThisPass)
                        }
                        continue
                    }
                }

                for y in stripeY..<stripeEnd {
                    let idx = y &* w &+ x

                    let st = statePtr[idx]
                    if st.contains(.codedThisPass) || st.contains(.significant) {
                        if ebcotTraceEnabled { EBCOTDebugTrace.shared.logEncode("skip(coded/sig)", x: x, y: y) }
                        continue
                    }

                    let neighbors = neighborCalculator.calculateUnsafe(
                        x: x, y: y,
                        states: statePtr,
                        signs: signPtr,
                        hasSigns: true
                    )

                    let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                    let isSignificant = (magPtr[idx] & bitMask) != 0

                    encoder.encode(symbol: isSignificant, context: &contexts[sigContext])
                    if ebcotTraceEnabled { EBCOTDebugTrace.shared.logEncode("sig(\(isSignificant),ctx=\(sigContext.rawValue))", x: x, y: y) }

                    if isSignificant {
                        let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                        let signBit = signPtr[idx]
                        let codedSign = signBit != xorBit
                        encoder.encode(symbol: codedSign, context: &contexts[signContext])
                        if ebcotTraceEnabled { EBCOTDebugTrace.shared.logEncode("sign(s=\(signBit),mq=\(codedSign),xor=\(xorBit),ctx=\(signContext.rawValue))", x: x, y: y) }

                        statePtr[idx].insert(.significant)
                        if signBit {
                            statePtr[idx].insert(.signBit)
                        }
                    }

                    statePtr[idx].insert(.codedThisPass)
                }
            }
        }

                } // stateBuf
            } // signBuf
        } // magBuf
    }

    /// Checks if a column is eligible for run-length coding.
    ///
    /// A column is eligible if all coefficients are not yet significant,
    /// not already coded, and have no significant neighbors.
    private func isEligibleForRunLengthCoding(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: [CoefficientState]
    ) -> Bool {
        // RLC only applies to full 4-row stripes per ISO 15444-1 D.3.7
        guard stripeEnd - stripeStart == 4 else { return false }

        for y in stripeStart..<stripeEnd {
            let idx = y * width + x

            // Can't use RLC if any coefficient is already significant or coded
            if states[idx].contains(.significant) || states[idx].contains(.codedThisPass) {
                return false
            }

            // Can't use RLC if any neighbor is significant
            let neighbors = neighborCalculator.calculate(x: x, y: y, states: states)
            if neighbors.hasAny {
                return false
            }
        }

        return true
    }

    /// Unsafe version of RLC eligibility check for use within withUnsafeMutableBufferPointer.
    @inline(__always)
    private func isEligibleForRunLengthCodingUnsafe(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: UnsafeMutablePointer<CoefficientState>
    ) -> Bool {
        guard stripeEnd - stripeStart == 4 else { return false }
        let w = width

        for y in stripeStart..<stripeEnd {
            let idx = y &* w &+ x
            let st = states[idx]
            if st.contains(.significant) || st.contains(.codedThisPass) {
                return false
            }
            let neighbors = neighborCalculator.calculateUnsafe(
                x: x, y: y,
                states: states,
                signs: nil,
                hasSigns: false
            )
            if neighbors.hasAny {
                return false
            }
        }
        return true
    }

    /// Unsafe version of significance check for use within withUnsafeBufferPointer.
    @inline(__always)
    private func anyBecomeSignificantUnsafe(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        magnitudes: UnsafePointer<UInt32>,
        bitMask: UInt32
    ) -> Bool {
        let w = width
        for y in stripeStart..<stripeEnd {
            let idx = y &* w &+ x
            if (magnitudes[idx] & bitMask) != 0 {
                return true
            }
        }
        return false
    }

    /// Checks if any coefficient in a column becomes significant at this bit-plane.
    private func anyBecomeSignificant(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        magnitudes: [UInt32],
        bitMask: UInt32
    ) -> Bool {
        for y in stripeStart..<stripeEnd {
            let idx = y * width + x
            if (magnitudes[idx] & bitMask) != 0 {
                return true
            }
        }
        return false
    }

    /// Checks if run-length coding can be used for a column in a stripe (legacy method for encoder).
    ///
    /// This checks both eligibility AND that no coefficients become significant.
    /// Kept for backwards compatibility but prefer using isEligibleForRunLengthCoding + anyBecomeSignificant.
    private func canUseRunLengthCoding(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: [CoefficientState],
        magnitudes: [UInt32],
        bitMask: UInt32
    ) -> Bool {
        isEligibleForRunLengthCoding(
            x: x, stripeStart: stripeStart,
            stripeEnd: stripeEnd, states: states) &&
        !anyBecomeSignificant(
            x: x, stripeStart: stripeStart,
            stripeEnd: stripeEnd,
            magnitudes: magnitudes, bitMask: bitMask)
    }

    // MARK: - Distortion Helpers

    /// Computes distortion reduction for newly significant coefficients coded in this pass.
    ///
    /// Updates reconstruction values for coefficients that became significant.
    /// Used after SPP and Cleanup passes.
    @inline(__always)
    private func computeNewSignificanceDistortion(
        states: inout [CoefficientState],
        magnitudes: [UInt32],
        recon: inout [UInt32],
        bitPlane: Int
    ) -> Double {
        let count = states.count
        let halfBit: UInt32 = bitPlane > 0 ? UInt32(1 << (bitPlane - 1)) : 0
        let reconVal = UInt32(1 << bitPlane) | halfBit
        let codedAndSig = CoefficientState.codedThisPass.rawValue | CoefficientState.significant.rawValue
        return states.withUnsafeMutableBufferPointer { statesBuf in
            magnitudes.withUnsafeBufferPointer { magBuf in
                recon.withUnsafeMutableBufferPointer { reconBuf in
                    var delta: Double = 0
                    for i in 0..<count {
                        let raw = statesBuf[i].rawValue
                        if (raw & codedAndSig) == codedAndSig && reconBuf[i] == 0 {
                            reconBuf[i] = reconVal
                            let m = Int64(magBuf[i])
                            let e = m - Int64(reconVal)
                            delta += Double(m &* m &- e &* e)
                        }
                    }
                    return delta
                }
            }
        }
    }

    /// Computes distortion reduction for refined coefficients coded in this pass.
    ///
    /// Updates reconstruction values for coefficients that were already significant
    /// and got their magnitude refined. Used after MRP passes.
    @inline(__always)
    private func computeRefinementDistortion(
        states: inout [CoefficientState],
        magnitudes: [UInt32],
        recon: inout [UInt32],
        bitPlane: Int
    ) -> Double {
        let count = states.count
        let halfBit: UInt32 = bitPlane > 0 ? UInt32(1 << (bitPlane - 1)) : 0
        let clearMask = ~UInt32((1 << (bitPlane + 1)) - 1)
        let bitVal = UInt32(1 << bitPlane)
        let codedAndSig = CoefficientState.codedThisPass.rawValue | CoefficientState.significant.rawValue
        return states.withUnsafeMutableBufferPointer { statesBuf in
            magnitudes.withUnsafeBufferPointer { magBuf in
                recon.withUnsafeMutableBufferPointer { reconBuf in
                    var delta: Double = 0
                    for i in 0..<count {
                        let raw = statesBuf[i].rawValue
                        if (raw & codedAndSig) == codedAndSig && reconBuf[i] > 0 {
                            let oldErr = Int64(magBuf[i]) - Int64(reconBuf[i])
                            let high = reconBuf[i] & clearMask
                            reconBuf[i] = high | (magBuf[i] & bitVal) | halfBit
                            let newErr = Int64(magBuf[i]) - Int64(reconBuf[i])
                            delta += Double(oldErr &* oldErr &- newErr &* newErr)
                        }
                    }
                    return delta
                }
            }
        }
    }
}

// MARK: - Bit-Plane Decoder

/// Decodes wavelet coefficients using EBCOT bit-plane decoding.
///
/// The bit-plane decoder reverses the encoding process, reconstructing
/// wavelet coefficients from the compressed bitstream.
struct BitPlaneDecoder: Sendable {
    /// The width of the code-block.
    let width: Int

    /// The height of the code-block.
    let height: Int

    /// The subband type for context formation.
    let subband: J2KSubband

    /// The context modeler for this subband.
    private let contextModeler: ContextModeler

    /// The neighbor calculator.
    private let neighborCalculator: NeighborCalculator

    /// Coding options for this decoder.
    private let options: CodingOptions

    /// Creates a new bit-plane decoder for the specified dimensions and subband.
    ///
    /// - Parameters:
    ///   - width: The width of the code-block in samples.
    ///   - height: The height of the code-block in samples.
    ///   - subband: The wavelet subband type.
    ///   - options: Coding options (default: `.default`).
    init(width: Int, height: Int, subband: J2KSubband, options: CodingOptions = .default) {
        self.width = width
        self.height = height
        self.subband = subband
        self.contextModeler = ContextModeler(subband: subband)
        self.neighborCalculator = NeighborCalculator(width: width, height: height)
        self.options = options
    }

    /// Decodes wavelet coefficients from EBCOT encoded data.
    ///
    /// - Parameters:
    ///   - data: The encoded data.
    ///   - passCount: The number of coding passes to decode.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - zeroBitPlanes: The number of zero bit-planes.
    ///   - passSegmentLengths: Per-pass segment byte lengths for predictable termination (empty for default).
    ///   - irreversible: Whether this uses irreversible (9/7) transform. When true, coefficients
    ///     use bpno_plus_one scale (shifted left by 1) matching OPJ's approach, and the caller
    ///     must apply ×0.5 during dequantization.
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    func decode(
        data: Data,
        passCount: Int,
        bitDepth: Int,
        zeroBitPlanes: Int,
        passSegmentLengths: [Int] = [],
        irreversible: Bool = false
    ) throws -> [Int32] {
        // Initialise coefficient arrays
        var magnitudes = [UInt32](repeating: 0, count: width * height)
        var signs = [Bool](repeating: false, count: width * height)
        var states = [CoefficientState](repeating: [], count: width * height)
        var firstRefineFlags = [Bool](repeating: false, count: width * height)
        // Per-coefficient half-bit for midpoint reconstruction (OPJ "oneplushalf").
        // When a coefficient becomes significant at bit plane B, halfBits[i] = 1 << (B-1).
        // When a magnitude refinement pass decodes bit plane B, halfBits[i] is updated
        // to 1 << (B-1) (or 0 if B==0), centering the value for unresolved lower bits.
        var halfBits = [UInt32](repeating: 0, count: width * height)

        // Determine if we need per-pass segment decoding
        let usePerPassSegments = !passSegmentLengths.isEmpty

        // For per-pass segments, split data into individual segments
        var passSegments: [Data] = []
        if usePerPassSegments {
            let totalSegmentLength = passSegmentLengths.reduce(0, +)
            guard totalSegmentLength <= data.count else {
                throw J2KError.invalidParameter(
                    "Pass segment lengths total (\(totalSegmentLength)) exceeds data size (\(data.count))"
                )
            }
            var offset = 0
            for length in passSegmentLengths {
                let end = offset + length
                passSegments.append(Data(data[offset..<end]))
                offset = end
            }
        }

        // Initialise MQ decoder and contexts
        var decoder = MQDecoder(data: Data())  // Will be replaced before first use
        var contextStates = ContextStateArray()
        var passSegmentIndex = 0

        if !usePerPassSegments {
            decoder = MQDecoder(data: data)
        }

        let activeBitPlanes = bitDepth - zeroBitPlanes
        var passesDecoded = 0



        // Process each bit-plane from MSB to LSB.
        // For irreversible (9/7) transform, use bpno_plus_one (= bitPlane + 1) for
        // bit masks, matching OPJ's approach. This ensures that at bitPlane=0,
        // halfBitMask=1 (not 0), so the midpoint reconstruction correctly adds 0.5
        // after the ×0.5 dequantization factor applied by the caller.
        // For reversible (5/3) transform, use standard bit plane indexing.
        let bpnoShift = irreversible ? 1 : 0
        for bitPlane in stride(from: activeBitPlanes - 1, through: 0, by: -1) {
            let bitMask: UInt32 = 1 << (bitPlane + bpnoShift)
            let halfBitMask: UInt32
            if irreversible {
                halfBitMask = 1 << bitPlane
            } else {
                halfBitMask = bitPlane > 0 ? (1 << (bitPlane - 1)) : 0
            }

            // Determine if bypass mode should be used for this bit-plane
            let useBypass = options.bypassEnabled && bitPlane < options.bypassThreshold

            // Per ISO 15444-1 Annex D, the MSB (first) bit plane starts with
            // Cleanup only — SigProp and MagRef are skipped.
            let isFirstBitPlane = (bitPlane == activeBitPlanes - 1)

            // Pass 1: Significance Propagation Pass (skip for MSB bit plane)
            if !isFirstBitPlane && passesDecoded < passCount {
                // Load segment for this pass if using per-pass segments
                if usePerPassSegments {
                    guard passSegmentIndex < passSegments.count else {
                        // Not enough pass segments - cannot decode further
                        break
                    }
                    decoder = MQDecoder(data: passSegments[passSegmentIndex])
                    contextStates.reset()
                    passSegmentIndex += 1
                }

                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logDecode("=== SIGPROP bitPlane=\(bitPlane) pass=\(passesDecoded) ===", x: -1, y: -1) }
                decodeSignificancePropagationPass(
                    magnitudes: &magnitudes,
                    signs: &signs,
                    states: &states,
                    halfBits: &halfBits,
                    bitMask: bitMask,
                    halfBitMask: halfBitMask,
                    decoder: &decoder,
                    contexts: &contextStates
                )
                if EBCOTDebugTrace.shared.enabled {
                    let sigCount = states.filter { $0.contains(.significant) }.count
                    var sigHash: UInt64 = 0
                    for (i, s) in states.enumerated() {
                        if s.contains(.significant) {
                            sigHash = sigHash &+ UInt64(i &* 2654435761)
                        }
                    }
                    EBCOTDebugTrace.shared.logDecode("POST_SIGPROP sig=\(sigCount) hash=\(sigHash)", x: -1, y: -1)
                    EBCOTDebugTrace.shared.saveDecoderStates("sigprop_bp\(bitPlane)", states)
                }
                if ebcotTraceEnabled {
                    EBCOTDebugTrace.shared.logDecoderPassEnd(pass: passesDecoded, a: decoder.debugA, c: decoder.debugC, opCount: decoder.operationCount)
                    EBCOTDebugTrace.shared.saveDecoderContexts(passesDecoded, contextStates)
                }
                passesDecoded += 1
            }

            // Pass 2: Magnitude Refinement Pass (skip for MSB bit plane)
            if !isFirstBitPlane && passesDecoded < passCount {
                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logDecode("=== MAGREF bitPlane=\(bitPlane) pass=\(passesDecoded) ===", x: -1, y: -1) }
                if useBypass {
                    guard usePerPassSegments, passSegmentIndex < passSegments.count else {
                        // Not enough pass segments for bypass mode - cannot decode further
                        break
                    }
                    // Use separate raw bypass decoder for bypass mode
                    var bypassDecoder = RawBypassDecoder(data: passSegments[passSegmentIndex])
                    passSegmentIndex += 1
                    decodeMagnitudeRefinementPassBypass(
                        magnitudes: &magnitudes,
                        states: &states,
                        firstRefineFlags: &firstRefineFlags,
                        halfBits: &halfBits,
                        bitMask: bitMask,
                        halfBitMask: halfBitMask,
                        bypassDecoder: &bypassDecoder
                    )
                } else {
                    // Load segment for this pass if using per-pass segments
                    if usePerPassSegments {
                        guard passSegmentIndex < passSegments.count else {
                            // Not enough pass segments - cannot decode further
                            break
                        }
                        decoder = MQDecoder(data: passSegments[passSegmentIndex])
                        contextStates.reset()
                        passSegmentIndex += 1
                    }

                    decodeMagnitudeRefinementPass(
                        magnitudes: &magnitudes,
                        states: &states,
                        firstRefineFlags: &firstRefineFlags,
                        halfBits: &halfBits,
                        bitMask: bitMask,
                        halfBitMask: halfBitMask,
                        decoder: &decoder,
                        contexts: &contextStates,
                        useBypass: false
                    )
                }
                if ebcotTraceEnabled {
                    EBCOTDebugTrace.shared.logDecoderPassEnd(pass: passesDecoded, a: decoder.debugA, c: decoder.debugC, opCount: decoder.operationCount)
                    EBCOTDebugTrace.shared.saveDecoderContexts(passesDecoded, contextStates)
                }
                passesDecoded += 1
            }

            // Pass 3: Cleanup Pass
            if passesDecoded < passCount {
                // Load segment for this pass if using per-pass segments
                if usePerPassSegments {
                    guard passSegmentIndex < passSegments.count else {
                        // Not enough pass segments - cannot decode further
                        break
                    }
                    decoder = MQDecoder(data: passSegments[passSegmentIndex])
                    contextStates.reset()
                    passSegmentIndex += 1
                }

                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logDecode("=== CLEANUP bitPlane=\(bitPlane) pass=\(passesDecoded) ===", x: -1, y: -1) }
                decodeCleanupPass(
                    magnitudes: &magnitudes,
                    signs: &signs,
                    states: &states,
                    halfBits: &halfBits,
                    bitMask: bitMask,
                    halfBitMask: halfBitMask,
                    decoder: &decoder,
                    contexts: &contextStates
                )
                // Count significant coefficients after cleanup
                if ebcotTraceEnabled && EBCOTDebugTrace.shared.enabled {
                    let sigCount = states.filter { $0.contains(.significant) }.count
                    let sbitCount = states.filter { $0.contains(.signBit) }.count
                    var sigHash: UInt64 = 0
                    for (i, s) in states.enumerated() {
                        if s.contains(.significant) {
                            sigHash = sigHash &+ UInt64(i &* 2654435761)
                        }
                    }
                    EBCOTDebugTrace.shared.logDecode("POST_CLEANUP sig=\(sigCount) sbit=\(sbitCount) hash=\(sigHash)", x: -1, y: -1)
                    EBCOTDebugTrace.shared.saveDecoderStates("cleanup_bp\(bitPlane)", states)
                }
                if ebcotTraceEnabled {
                    EBCOTDebugTrace.shared.logDecoderPassEnd(pass: passesDecoded, a: decoder.debugA, c: decoder.debugC, opCount: decoder.operationCount)
                    EBCOTDebugTrace.shared.saveDecoderContexts(passesDecoded, contextStates)
                }
                passesDecoded += 1
            }

            // Clear coded-this-pass flags for next bit-plane (batch bitwise)
            let decoderClearMask = ~CoefficientState.codedThisPass.rawValue
            states.withUnsafeMutableBufferPointer { buf in
                for i in 0..<buf.count {
                    buf[i] = CoefficientState(rawValue: buf[i].rawValue & decoderClearMask)
                }
            }
        }

        // Reconstruct signed coefficients with per-coefficient midpoint reconstruction.
        // Each significant coefficient has a half-bit set at the bit plane below the
        // lowest decoded plane, centering the value in the unresolved range.
        // The halfBits array tracks this per the OPJ "oneplushalf" approach.
        var coefficients = [Int32](repeating: 0, count: width * height)
        let count = coefficients.count
        magnitudes.withUnsafeBufferPointer { magBuf in
            halfBits.withUnsafeBufferPointer { halfBuf in
                signs.withUnsafeBufferPointer { signBuf in
                    coefficients.withUnsafeMutableBufferPointer { coeffBuf in
                        let mp = magBuf.baseAddress!
                        let hp = halfBuf.baseAddress!
                        let sp = signBuf.baseAddress!
                        let cp = coeffBuf.baseAddress!
                        for i in 0..<count {
                            let finalMag = mp[i] | hp[i]
                            cp[i] = sp[i] ? -Int32(bitPattern: finalMag) : Int32(bitPattern: finalMag)
                        }
                    }
                }
            }
        }

        return coefficients
    }

    // MARK: - Significance Propagation Pass (Decode)

    /// Decodes the significance propagation pass.
    private func decodeSignificancePropagationPass(
        magnitudes: inout [UInt32],
        signs: inout [Bool],
        states: inout [CoefficientState],
        halfBits: inout [UInt32],
        bitMask: UInt32,
        halfBitMask: UInt32,
        decoder: inout MQDecoder,
        contexts: inout ContextStateArray
    ) {
        let stripeHeight = 4
        let w = width
        let h = height

        magnitudes.withUnsafeMutableBufferPointer { magBuf in
            signs.withUnsafeMutableBufferPointer { signBuf in
                states.withUnsafeMutableBufferPointer { stateBuf in
                    halfBits.withUnsafeMutableBufferPointer { halfBuf in
                        let magPtr = magBuf.baseAddress!
                        let signPtr = signBuf.baseAddress!
                        let statePtr = stateBuf.baseAddress!
                        let halfPtr = halfBuf.baseAddress!

                        for stripeY in stride(from: 0, to: h, by: stripeHeight) {
                            let stripeEnd = min(stripeY + stripeHeight, h)

                            for x in 0..<w {
                                for y in stripeY..<stripeEnd {
                                    let idx = y &* w &+ x

                                    let st = statePtr[idx]
                                    if st.contains(.significant) || st.contains(.codedThisPass) {
                                        continue
                                    }

                                    let neighbors = neighborCalculator.calculateUnsafe(
                                        x: x, y: y,
                                        states: statePtr,
                                        signs: signPtr,
                                        hasSigns: true
                                    )

                                    guard neighbors.hasAny else { continue }

                                    let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                                    let isSignificant = decoder.decode(context: &contexts[sigContext])

                                    if isSignificant {
                                        let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                                        let codedSign = decoder.decode(context: &contexts[signContext])
                                        let signBit = codedSign != xorBit

                                        magPtr[idx] = magPtr[idx] | bitMask
                                        halfPtr[idx] = halfBitMask
                                        signPtr[idx] = signBit

                                        statePtr[idx].insert(.significant)
                                        if signBit {
                                            statePtr[idx].insert(.signBit)
                                        }
                                    }

                                    statePtr[idx].insert(.codedThisPass)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Magnitude Refinement Pass (Decode)

    /// Decodes the magnitude refinement pass.
    ///
    /// - Parameters:
    ///   - magnitudes: The coefficient magnitudes being reconstructed.
    ///   - states: The coefficient states.
    ///   - firstRefineFlags: Flags indicating first refinement for each coefficient.
    ///   - bitMask: The bit mask for this bit-plane.
    ///   - decoder: The MQ decoder.
    ///   - contexts: The context states.
    ///   - useBypass: Whether bypass (raw) mode was used during encoding.
    private func decodeMagnitudeRefinementPass(
        magnitudes: inout [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        halfBits: inout [UInt32],
        bitMask: UInt32,
        halfBitMask: UInt32,
        decoder: inout MQDecoder,
        contexts: inout ContextStateArray,
        useBypass: Bool = false
    ) {
        let stripeHeight = 4
        let w = width
        let h = height

        magnitudes.withUnsafeMutableBufferPointer { magBuf in
            states.withUnsafeMutableBufferPointer { stateBuf in
                firstRefineFlags.withUnsafeMutableBufferPointer { refineBuf in
                    halfBits.withUnsafeMutableBufferPointer { halfBuf in
                        let magPtr = magBuf.baseAddress!
                        let statePtr = stateBuf.baseAddress!
                        let refinePtr = refineBuf.baseAddress!
                        let halfPtr = halfBuf.baseAddress!

                        for stripeY in stride(from: 0, to: h, by: stripeHeight) {
                            let stripeEnd = min(stripeY + stripeHeight, h)

                            for x in 0..<w {
                                for y in stripeY..<stripeEnd {
                                    let idx = y &* w &+ x

                                    let st = statePtr[idx]
                                    guard st.contains(.significant) else { continue }
                                    guard !st.contains(.codedThisPass) else { continue }

                                    let bitValue: Bool
                                    if useBypass {
                                        bitValue = decoder.decodeBypass()
                                    } else {
                                        let isFirstRefinement = !refinePtr[idx]
                                        let neighbors = neighborCalculator.calculateUnsafe(
                                            x: x, y: y,
                                            states: statePtr,
                                            signs: nil,
                                            hasSigns: false
                                        )
                                        let hasSignificantNeighbors = neighbors.hasAny
                                        let magContext = contextModeler.magnitudeRefinementContext(
                                            firstRefinement: isFirstRefinement,
                                            neighborsWereSignificant: hasSignificantNeighbors
                                        )
                                        bitValue = decoder.decode(context: &contexts[magContext])
                                    }

                                    if bitValue {
                                        magPtr[idx] = magPtr[idx] | bitMask
                                    }
                                    halfPtr[idx] = halfBitMask

                                    if !refinePtr[idx] {
                                        refinePtr[idx] = true
                                    }

                                    statePtr[idx].insert(.codedThisPass)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Decodes the magnitude refinement pass using raw bypass coding.
    ///
    /// This method uses a separate `RawBypassDecoder` to read raw bits directly
    /// without context-adaptive arithmetic decoding.
    ///
    /// - Parameters:
    ///   - magnitudes: The coefficient magnitudes being reconstructed.
    ///   - states: The coefficient states.
    ///   - firstRefineFlags: Flags indicating first refinement for each coefficient.
    ///   - bitMask: The bit mask for this bit-plane.
    ///   - bypassDecoder: The raw bypass decoder.
    private func decodeMagnitudeRefinementPassBypass(
        magnitudes: inout [UInt32],
        states: inout [CoefficientState],
        firstRefineFlags: inout [Bool],
        halfBits: inout [UInt32],
        bitMask: UInt32,
        halfBitMask: UInt32,
        bypassDecoder: inout RawBypassDecoder
    ) {
        let stripeHeight = 4
        let w = width
        let h = height

        magnitudes.withUnsafeMutableBufferPointer { magBuf in
            states.withUnsafeMutableBufferPointer { stateBuf in
                firstRefineFlags.withUnsafeMutableBufferPointer { refineBuf in
                    halfBits.withUnsafeMutableBufferPointer { halfBuf in
                        let magPtr = magBuf.baseAddress!
                        let statePtr = stateBuf.baseAddress!
                        let refinePtr = refineBuf.baseAddress!
                        let halfPtr = halfBuf.baseAddress!

                        for stripeY in stride(from: 0, to: h, by: stripeHeight) {
                            let stripeEnd = min(stripeY + stripeHeight, h)

                            for x in 0..<w {
                                for y in stripeY..<stripeEnd {
                                    let idx = y &* w &+ x

                                    let st = statePtr[idx]
                                    guard st.contains(.significant) else { continue }
                                    guard !st.contains(.codedThisPass) else { continue }

                                    let bitValue = bypassDecoder.decode()

                                    if bitValue {
                                        magPtr[idx] = magPtr[idx] | bitMask
                                    }
                                    halfPtr[idx] = halfBitMask

                                    if !refinePtr[idx] {
                                        refinePtr[idx] = true
                                    }

                                    statePtr[idx].insert(.codedThisPass)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cleanup Pass (Decode)

    /// Decodes the cleanup pass.
    private func decodeCleanupPass(
        magnitudes: inout [UInt32],
        signs: inout [Bool],
        states: inout [CoefficientState],
        halfBits: inout [UInt32],
        bitMask: UInt32,
        halfBitMask: UInt32,
        decoder: inout MQDecoder,
        contexts: inout ContextStateArray
    ) {
        let stripeHeight = 4
        let w = width
        let h = height

        magnitudes.withUnsafeMutableBufferPointer { magBuf in
            signs.withUnsafeMutableBufferPointer { signBuf in
                states.withUnsafeMutableBufferPointer { stateBuf in
                    halfBits.withUnsafeMutableBufferPointer { halfBuf in
                        let magPtr = magBuf.baseAddress!
                        let signPtr = signBuf.baseAddress!
                        let statePtr = stateBuf.baseAddress!
                        let halfPtr = halfBuf.baseAddress!

                        for stripeY in stride(from: 0, to: h, by: stripeHeight) {
                            let stripeEnd = min(stripeY + stripeHeight, h)

                            for x in 0..<w {
                                let eligible = canUseRunLengthDecodingUnsafe(
                                    x: x,
                                    stripeStart: stripeY,
                                    stripeEnd: stripeEnd,
                                    states: statePtr
                                )

                                if ebcotTraceEnabled { EBCOTDebugTrace.shared.logDecode("elig=\(eligible)", x: x, y: stripeY) }

                                if eligible {
                                    let hasSignificant = decoder.decode(context: &contexts[.runLength])

                                    if !hasSignificant {
                                        for y in stripeY..<stripeEnd {
                                            statePtr[y &* w &+ x].insert(.codedThisPass)
                                        }
                                        continue
                                    }

                                    if options.useISOPositionEncoding {
                                        let bit1 = decoder.decode(context: &contexts[.uniform])
                                        let bit0 = decoder.decode(context: &contexts[.uniform])
                                        let firstSigPos = (bit1 ? 2 : 0) + (bit0 ? 1 : 0)

                                        for i in 0..<firstSigPos {
                                            statePtr[(stripeY + i) &* w &+ x].insert(.codedThisPass)
                                        }

                                        let firstIdx = (stripeY + firstSigPos) &* w &+ x
                                        let firstNeighbors = neighborCalculator.calculateUnsafe(
                                            x: x, y: stripeY + firstSigPos,
                                            states: statePtr,
                                            signs: signPtr,
                                            hasSigns: true
                                        )
                                        let (firstSignCtx, firstXorBit) = contextModeler.signContext(neighbors: firstNeighbors)
                                        let firstCodedSign = decoder.decode(context: &contexts[firstSignCtx])
                                        let firstSignBit = firstCodedSign != firstXorBit

                                        magPtr[firstIdx] = magPtr[firstIdx] | bitMask
                                        halfPtr[firstIdx] = halfBitMask
                                        signPtr[firstIdx] = firstSignBit
                                        statePtr[firstIdx].insert(.significant)
                                        if firstSignBit {
                                            statePtr[firstIdx].insert(.signBit)
                                        }
                                        statePtr[firstIdx].insert(.codedThisPass)

                                        for y in (stripeY + firstSigPos + 1)..<stripeEnd {
                                            let idx = y &* w &+ x

                                            let st = statePtr[idx]
                                            if st.contains(.codedThisPass) || st.contains(.significant) {
                                                continue
                                            }

                                            let neighbors = neighborCalculator.calculateUnsafe(
                                                x: x, y: y,
                                                states: statePtr,
                                                signs: signPtr,
                                                hasSigns: true
                                            )

                                            let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                                            let isSignificant = decoder.decode(context: &contexts[sigContext])

                                            if isSignificant {
                                                let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                                                let codedSign = decoder.decode(context: &contexts[signContext])
                                                let signBit = codedSign != xorBit

                                                magPtr[idx] = magPtr[idx] | bitMask
                                                halfPtr[idx] = halfBitMask
                                                signPtr[idx] = signBit
                                                statePtr[idx].insert(.significant)
                                                if signBit {
                                                    statePtr[idx].insert(.signBit)
                                                }
                                            }

                                            statePtr[idx].insert(.codedThisPass)
                                        }
                                        continue
                                    }
                                }

                                for y in stripeY..<stripeEnd {
                                    let idx = y &* w &+ x

                                    let st = statePtr[idx]
                                    if st.contains(.codedThisPass) || st.contains(.significant) {
                                        if ebcotTraceEnabled { EBCOTDebugTrace.shared.logDecode("skip(coded/sig)", x: x, y: y) }
                                        continue
                                    }

                                    let neighbors = neighborCalculator.calculateUnsafe(
                                        x: x, y: y,
                                        states: statePtr,
                                        signs: signPtr,
                                        hasSigns: true
                                    )

                                    let sigContext = contextModeler.significanceContext(neighbors: neighbors)
                                    let isSignificant = decoder.decode(context: &contexts[sigContext])
                                    if ebcotTraceEnabled { EBCOTDebugTrace.shared.logDecode("sig(\(isSignificant),ctx=\(sigContext.rawValue))", x: x, y: y) }

                                    if isSignificant {
                                        let (signContext, xorBit) = contextModeler.signContext(neighbors: neighbors)
                                        let codedSign = decoder.decode(context: &contexts[signContext])
                                        let signBit = codedSign != xorBit
                                        if ebcotTraceEnabled { EBCOTDebugTrace.shared.logDecode("sign(s=\(signBit),mq=\(codedSign),xor=\(xorBit),ctx=\(signContext.rawValue))", x: x, y: y) }

                                        magPtr[idx] = magPtr[idx] | bitMask
                                        halfPtr[idx] = halfBitMask
                                        signPtr[idx] = signBit

                                        statePtr[idx].insert(.significant)
                                        if signBit {
                                            statePtr[idx].insert(.signBit)
                                        }
                                    }

                                    statePtr[idx].insert(.codedThisPass)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Run-length eligibility check using unsafe state pointer.
    @inline(__always)
    private func canUseRunLengthDecodingUnsafe(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: UnsafePointer<CoefficientState>
    ) -> Bool {
        guard stripeEnd - stripeStart == 4 else { return false }
        let w = width

        for y in stripeStart..<stripeEnd {
            let idx = y &* w &+ x
            if states[idx].contains(.significant) || states[idx].contains(.codedThisPass) {
                return false
            }
            let neighbors = neighborCalculator.calculateUnsafe(
                x: x, y: y,
                states: states,
                signs: nil,
                hasSigns: false
            )
            if neighbors.hasAny {
                return false
            }
        }
        return true
    }

     /// Checks if run-length decoding can be used for a column in a stripe.
    ///
    /// This is the decoder equivalent of `isEligibleForRunLengthCoding` in the encoder.
    /// It checks eligibility based on coefficient and neighbor states.
    ///
    /// NOTE: This function must be kept in sync with BitPlaneCoder.isEligibleForRunLengthCoding
    private func canUseRunLengthDecoding(
        x: Int,
        stripeStart: Int,
        stripeEnd: Int,
        states: [CoefficientState]
    ) -> Bool {
        // This must match isEligibleForRunLengthCoding in the encoder
        // RLC only applies to full 4-row stripes per ISO 15444-1 D.3.7
        guard stripeEnd - stripeStart == 4 else { return false }

        for y in stripeStart..<stripeEnd {
            let idx = y * width + x

            // Can't use RLC if any coefficient is already significant or coded
            if states[idx].contains(.significant) || states[idx].contains(.codedThisPass) {
                return false
            }

            // Can't use RLC if any neighbor is significant
            let neighbors = neighborCalculator.calculate(x: x, y: y, states: states)
            if neighbors.hasAny {
                return false
            }
        }

        return true
    }
}

// MARK: - Code-Block Encoder

/// Encodes a complete code-block using EBCOT.
///
/// This is a high-level wrapper around the bit-plane coder that handles
/// the complete encoding of a JPEG 2000 code-block.
struct CodeBlockEncoder: Sendable {
    /// The maximum code-block width.
    static let maxWidth = 64

    /// The maximum code-block height.
    static let maxHeight = 64

    /// The default code-block width.
    static let defaultWidth = 64

    /// The default code-block height.
    static let defaultHeight = 64

    /// Encodes a code-block with default options.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in the code-block.
    ///   - width: The width of the code-block.
    ///   - height: The height of the code-block.
    ///   - subband: The subband type.
    ///   - bitDepth: The bit depth of the coefficients.
    /// - Returns: The encoded code-block data with metadata.
    /// - Throws: ``J2KError`` if encoding fails.
    func encode(
        coefficients: [Int32],
        width: Int,
        height: Int,
        subband: J2KSubband,
        bitDepth: Int
    ) throws -> J2KCodeBlock {
        try encode(
            coefficients: coefficients,
            width: width,
            height: height,
            subband: subband,
            bitDepth: bitDepth,
            options: .default
        )
    }

    /// Encodes a code-block with custom coding options.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in the code-block.
    ///   - width: The width of the code-block.
    ///   - height: The height of the code-block.
    ///   - subband: The subband type.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - options: Coding options (bypass mode, termination, etc.).
    /// - Returns: The encoded code-block data with metadata.
    /// - Throws: ``J2KError`` if encoding fails.
    func encode(
        coefficients: [Int32],
        width: Int,
        height: Int,
        subband: J2KSubband,
        bitDepth: Int,
        options: CodingOptions
    ) throws -> J2KCodeBlock {
        let coder = BitPlaneCoder(width: width, height: height, subband: subband, options: options)
        let (data, passCount, zeroBitPlanes, passSegmentLengths, cumulativePassBytes, cumulativePassDistortion, perPassSnapshotData) = try coder.encode(
            coefficients: coefficients,
            bitDepth: bitDepth
        )

        return J2KCodeBlock(
            index: 0,
            x: 0,
            y: 0,
            width: width,
            height: height,
            subband: subband,
            data: data,
            passeCount: passCount,
            zeroBitPlanes: zeroBitPlanes,
            passSegmentLengths: passSegmentLengths,
            cumulativePassBytes: cumulativePassBytes,
            cumulativePassDistortion: cumulativePassDistortion,
            perPassSnapshotData: perPassSnapshotData
        )
    }
}

// MARK: - Code-Block Decoder

/// Decodes a complete code-block using EBCOT.
///
/// This is a high-level wrapper around the bit-plane decoder that handles
/// the complete decoding of a JPEG 2000 code-block.
struct CodeBlockDecoder: Sendable {
    /// Decodes a code-block with default options.
    ///
    /// - Parameters:
    ///   - codeBlock: The encoded code-block.
    ///   - bitDepth: The bit depth of the coefficients.
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    func decode(
        codeBlock: J2KCodeBlock,
        bitDepth: Int
    ) throws -> [Int32] {
        try decode(codeBlock: codeBlock, bitDepth: bitDepth, options: .default, irreversible: false)
    }

    /// Decodes a code-block, specifying whether the transform is irreversible.
    ///
    /// - Parameters:
    ///   - codeBlock: The encoded code-block.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - irreversible: Whether this uses irreversible (9/7) transform.
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    func decode(
        codeBlock: J2KCodeBlock,
        bitDepth: Int,
        irreversible: Bool
    ) throws -> [Int32] {
        try decode(codeBlock: codeBlock, bitDepth: bitDepth, options: .default, irreversible: irreversible)
    }

    /// Decodes a code-block with custom coding options.
    ///
    /// - Parameters:
    ///   - codeBlock: The encoded code-block.
    ///   - bitDepth: The bit depth of the coefficients.
    ///   - options: Coding options that were used during encoding.
    ///   - irreversible: Whether this uses irreversible (9/7) transform.
    /// - Returns: The decoded wavelet coefficients.
    /// - Throws: ``J2KError`` if decoding fails.
    func decode(
        codeBlock: J2KCodeBlock,
        bitDepth: Int,
        options: CodingOptions,
        irreversible: Bool = false
    ) throws -> [Int32] {
        let decoder = BitPlaneDecoder(
            width: codeBlock.width,
            height: codeBlock.height,
            subband: codeBlock.subband,
            options: options
        )

        return try decoder.decode(
            data: codeBlock.data,
            passCount: codeBlock.passeCount,
            bitDepth: bitDepth,
            zeroBitPlanes: codeBlock.zeroBitPlanes,
            passSegmentLengths: codeBlock.passSegmentLengths,
            irreversible: irreversible
        )
    }
}
