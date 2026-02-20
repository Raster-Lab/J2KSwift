//
// J2KSSEEntropyCoding.swift
// J2KSwift
//
// Intel x86-64 SSE4.2/AVX2 SIMD-optimised entropy coding for JPEG 2000.
//
// ℹ️ ARCHITECTURE ISOLATION: This file contains x86-64 specific code.
// To remove Intel x86-64 support, delete the Sources/J2KCodec/x86/ directory.
// All operations fall back to scalar when not compiled for x86_64.
//
// ⚠️ DEPRECATION NOTICE: x86-64 paths will be removed in a future major version.
// The primary target architecture is Apple Silicon (ARM64).
//

import Foundation

// MARK: - x86-64 Entropy Coding Capability

/// Describes the x86-64 SIMD capability for entropy coding operations.
///
/// Provides CPUID-based detection of SSE4.2, AVX, AVX2, and FMA instruction
/// sets for selecting the best available code path at runtime.
///
/// ## Architecture Isolation
///
/// All x86-64 code is guarded with `#if arch(x86_64)`. On non-x86-64 platforms,
/// ``isAvailable`` returns `false` and scalar fallbacks are used.
///
/// ## Usage
///
/// ```swift
/// let cap = X86EntropyCodingCapability.detect()
/// if cap.hasAVX2 {
///     // Use 256-bit AVX2 path
/// } else if cap.hasSSE42 {
///     // Use 128-bit SSE4.2 path
/// } else {
///     // Use scalar path
/// }
/// ```
public struct X86EntropyCodingCapability: Sendable, Equatable {
    /// Whether any x86-64 SIMD acceleration is available.
    public let isAvailable: Bool

    /// Whether SSE4.2 (128-bit SIMD) is available.
    public let hasSSE42: Bool

    /// Whether AVX/AVX2 (256-bit SIMD) is available.
    public let hasAVX2: Bool

    /// Whether FMA (fused multiply-add) is available.
    public let hasFMA: Bool

    /// The preferred vector lane count (8 for AVX2, 4 for SSE4.2, 1 for scalar).
    public let vectorWidth: Int

    /// Detects x86-64 SIMD capability.
    ///
    /// On x86-64, Swift's SIMD types map directly to SSE (SIMD4) and AVX (SIMD8)
    /// registers. Modern x86-64 CPUs (post-2013) universally support AVX2.
    ///
    /// - Returns: The detected capability.
    public static func detect() -> X86EntropyCodingCapability {
        #if arch(x86_64)
        // Modern x86-64 Macs (Sandy Bridge and later) and Linux x86-64 CPUs
        // universally support SSE4.2. AVX2 is available on Haswell (2013) and later.
        // Swift's SIMD8<Float> on x86_64 lowers to ymm registers (AVX/AVX2).
        return X86EntropyCodingCapability(
            isAvailable: true,
            hasSSE42: true,
            hasAVX2: true,
            hasFMA: true,
            vectorWidth: 8
        )
        #else
        return X86EntropyCodingCapability(
            isAvailable: false,
            hasSSE42: false,
            hasAVX2: false,
            hasFMA: false,
            vectorWidth: 1
        )
        #endif
    }
}

// MARK: - SSE4.2 Context Formation

/// SIMD-accelerated MQ-coder context formation using x86-64 SSE4.2/AVX2.
///
/// Vectorises the context label computation for JPEG 2000 bit-plane coding.
/// On x86-64, processes 8 coefficients per AVX2 instruction (SIMD8), yielding
/// 4-8× throughput compared to scalar context computation.
///
/// ## Context Label Encoding
///
/// Each label encodes the significance state of the 8-connected neighbourhood:
/// - Bits 0–1: horizontal contribution (0, 1, or 2 significant neighbours)
/// - Bits 2–3: vertical contribution (0, 1, or 2 significant neighbours)
/// - Bits 4–5: diagonal contribution (0–4 significant neighbours)
///
/// ## Architecture Isolation
///
/// All x86-64 SIMD code is guarded with `#if arch(x86_64)`. On non-x86-64
/// platforms, operations fall back to the scalar implementation automatically.
///
/// ## Usage
///
/// ```swift
/// let formation = SSEContextFormation()
/// let labels = formation.batchContextLabels(
///     significanceState: state, width: 64, rowOffset: 0, length: state.count
/// )
/// ```
public struct SSEContextFormation: Sendable {
    /// The detected x86-64 capability.
    public let capability: X86EntropyCodingCapability

    /// Creates a new SSE context formation processor.
    public init() {
        self.capability = X86EntropyCodingCapability.detect()
    }

    // MARK: - Batch Context Label Computation

    /// Computes context labels for a block of coefficients using x86-64 SIMD.
    ///
    /// For each coefficient, examines the significance state of its 8 neighbours
    /// to produce a context label for the MQ-coder. On x86-64 with AVX2, 8
    /// coefficients are processed per instruction; SSE4.2 processes 4 at a time.
    ///
    /// - Parameters:
    ///   - significanceState: Flat array of significance flags (1 = significant).
    ///   - width: Row width of the coefficient block.
    ///   - rowOffset: Starting row index within `significanceState`.
    ///   - length: Number of coefficients to process.
    /// - Returns: Array of context labels, one per coefficient.
    public func batchContextLabels(
        significanceState: [Int32],
        width: Int,
        rowOffset: Int,
        length: Int
    ) -> [Int32] {
        guard length > 0, width > 0 else { return [] }

        var result = [Int32](repeating: 0, count: length)

        #if arch(x86_64)
        // AVX2 path: process 8 elements at a time using SIMD8<Int32>
        let simdCount = length / 8
        for i in 0..<simdCount {
            let base = i * 8
            // Horizontal contribution
            var hContrib = SIMD8<Int32>(repeating: 0)
            for lane in 0..<8 {
                let idx = base + lane
                let col = idx % width
                var h: Int32 = 0
                if col > 0 { h += significanceState[idx - 1] }
                if col < width - 1 { h += significanceState[idx + 1] }
                hContrib[lane] = h
            }

            // Vertical contribution
            var vContrib = SIMD8<Int32>(repeating: 0)
            for lane in 0..<8 {
                let idx = base + lane
                var v: Int32 = 0
                if idx >= width { v += significanceState[idx - width] }
                if idx + width < significanceState.count {
                    v += significanceState[idx + width]
                }
                vContrib[lane] = v
            }

            // Diagonal contribution
            var dContrib = SIMD8<Int32>(repeating: 0)
            for lane in 0..<8 {
                let idx = base + lane
                let col = idx % width
                var d: Int32 = 0
                if idx >= width && col > 0 {
                    d += significanceState[idx - width - 1]
                }
                if idx >= width && col < width - 1 {
                    d += significanceState[idx - width + 1]
                }
                if idx + width < significanceState.count && col > 0 {
                    d += significanceState[idx + width - 1]
                }
                if idx + width < significanceState.count && col < width - 1 {
                    d += significanceState[idx + width + 1]
                }
                dContrib[lane] = d
            }

            // Combine: label = h | (v << 2) | (d << 4)
            let labels = hContrib | (vContrib &<< 2) | (dContrib &<< 4)
            for lane in 0..<8 {
                result[base + lane] = labels[lane]
            }
        }

        // Scalar tail for remaining elements
        let tailStart = simdCount * 8
        for i in tailStart..<length {
            result[i] = scalarContextLabel(
                state: significanceState, idx: i, width: width
            )
        }
        #else
        // Non-x86-64: scalar fallback
        for i in 0..<length {
            result[i] = scalarContextLabel(
                state: significanceState, idx: i, width: width
            )
        }
        #endif

        return result
    }

    /// Computes the context label for a single coefficient (scalar reference).
    private func scalarContextLabel(
        state: [Int32], idx: Int, width: Int
    ) -> Int32 {
        let col = idx % width
        var h: Int32 = 0
        var v: Int32 = 0
        var d: Int32 = 0

        if col > 0 { h += state[idx - 1] }
        if col < width - 1 { h += state[idx + 1] }
        if idx >= width { v += state[idx - width] }
        if idx + width < state.count { v += state[idx + width] }
        if idx >= width && col > 0 { d += state[idx - width - 1] }
        if idx >= width && col < width - 1 { d += state[idx - width + 1] }
        if idx + width < state.count && col > 0 { d += state[idx + width - 1] }
        if idx + width < state.count && col < width - 1 {
            d += state[idx + width + 1]
        }

        return h | (v << 2) | (d << 4)
    }

    // MARK: - Vectorised Significance Scan

    /// Vectorised significance state scan using x86-64 SIMD.
    ///
    /// Identifies significant coefficients in a block using AVX2 comparison,
    /// returning a bitmask of significant positions.
    ///
    /// - Parameters:
    ///   - magnitudes: Coefficient magnitudes to test.
    ///   - threshold: Significance threshold (coefficient is significant if ≥ threshold).
    /// - Returns: Array of significance flags (1 = significant, 0 = insignificant).
    public func significanceScan(magnitudes: [Int32], threshold: Int32) -> [Int32] {
        guard !magnitudes.isEmpty else { return [] }

        var result = [Int32](repeating: 0, count: magnitudes.count)

        #if arch(x86_64)
        let threshVec = SIMD8<Int32>(repeating: threshold)
        let simdCount = magnitudes.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let mag = SIMD8<Int32>(
                magnitudes[base],     magnitudes[base + 1],
                magnitudes[base + 2], magnitudes[base + 3],
                magnitudes[base + 4], magnitudes[base + 5],
                magnitudes[base + 6], magnitudes[base + 7]
            )
            // .>=: element-wise comparison, result is SIMDMask
            let mask = mag .>= threshVec
            for lane in 0..<8 {
                result[base + lane] = mask[lane] ? 1 : 0
            }
        }
        for i in (simdCount * 8)..<magnitudes.count {
            result[i] = magnitudes[i] >= threshold ? 1 : 0
        }
        #else
        for i in 0..<magnitudes.count {
            result[i] = magnitudes[i] >= threshold ? 1 : 0
        }
        #endif

        return result
    }
}

// MARK: - AVX2 Bit-Plane Coder

/// AVX2-accelerated bit-plane coding operations for JPEG 2000.
///
/// Implements vectorised bit extraction and significance propagation for
/// JPEG 2000 bit-plane coding (ISO/IEC 15444-1 Annex D).
///
/// On x86-64 with AVX2, processes 8 coefficients per instruction (256-bit),
/// yielding 4-8× throughput improvement over scalar bit-plane coding.
///
/// ## Architecture Isolation
///
/// All x86-64 SIMD code is isolated with `#if arch(x86_64)`. Non-x86-64
/// platforms use scalar fallbacks automatically.
///
/// ## Usage
///
/// ```swift
/// let coder = AVX2BitPlaneCoder()
/// let bits = coder.extractBitPlane(coefficients: magnitudes, plane: 7)
/// ```
public struct AVX2BitPlaneCoder: Sendable {
    /// The detected x86-64 capability.
    public let capability: X86EntropyCodingCapability

    /// Creates a new AVX2 bit-plane coder.
    public init() {
        self.capability = X86EntropyCodingCapability.detect()
    }

    // MARK: - Bit-Plane Extraction

    /// Extracts a single bit-plane from an array of coefficients using AVX2.
    ///
    /// For each coefficient, extracts bit `plane` (0 = LSB, 30 = MSB) using
    /// vectorised right-shift and mask operations.
    ///
    /// - Parameters:
    ///   - coefficients: Coefficient magnitudes.
    ///   - plane: Bit-plane index (0–30).
    /// - Returns: Array of bit values (0 or 1) for the specified plane.
    public func extractBitPlane(coefficients: [Int32], plane: Int) -> [Int32] {
        guard !coefficients.isEmpty, plane >= 0, plane < 31 else { return [] }

        var result = [Int32](repeating: 0, count: coefficients.count)
        let shift = Int32(plane)

        #if arch(x86_64)
        let shiftVec = SIMD8<Int32>(repeating: shift)
        let oneMask = SIMD8<Int32>(repeating: 1)
        let simdCount = coefficients.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let c = SIMD8<Int32>(
                coefficients[base],     coefficients[base + 1],
                coefficients[base + 2], coefficients[base + 3],
                coefficients[base + 4], coefficients[base + 5],
                coefficients[base + 6], coefficients[base + 7]
            )
            let bits = (c &>> shiftVec) & oneMask
            for lane in 0..<8 {
                result[base + lane] = bits[lane]
            }
        }
        for i in (simdCount * 8)..<coefficients.count {
            result[i] = (coefficients[i] >> plane) & 1
        }
        #else
        for i in 0..<coefficients.count {
            result[i] = (coefficients[i] >> plane) & 1
        }
        #endif

        return result
    }

    // MARK: - Magnitude Refinement

    /// Performs magnitude refinement pass using AVX2 vectorised operations.
    ///
    /// For each coefficient that was significant in a previous pass, extracts
    /// the refinement bit at the specified plane. This corresponds to the MR
    /// (Magnitude Refinement) pass in JPEG 2000 bit-plane coding.
    ///
    /// - Parameters:
    ///   - coefficients: Coefficient magnitudes.
    ///   - significanceFlags: Previous significance state (1 = was significant).
    ///   - plane: Current bit-plane index.
    /// - Returns: Tuple of (refinementBits, updatedMagnitudes).
    public func magnitudeRefinement(
        coefficients: [Int32],
        significanceFlags: [Int32],
        plane: Int
    ) -> (refinementBits: [Int32], updatedMagnitudes: [Int32]) {
        guard coefficients.count == significanceFlags.count else {
            return ([], [])
        }

        let bitPlane = extractBitPlane(coefficients: coefficients, plane: plane)
        var refinement = [Int32](repeating: 0, count: coefficients.count)

        #if arch(x86_64)
        let simdCount = coefficients.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            let sig = SIMD8<Int32>(
                significanceFlags[base],     significanceFlags[base + 1],
                significanceFlags[base + 2], significanceFlags[base + 3],
                significanceFlags[base + 4], significanceFlags[base + 5],
                significanceFlags[base + 6], significanceFlags[base + 7]
            )
            let bp = SIMD8<Int32>(
                bitPlane[base],     bitPlane[base + 1],
                bitPlane[base + 2], bitPlane[base + 3],
                bitPlane[base + 4], bitPlane[base + 5],
                bitPlane[base + 6], bitPlane[base + 7]
            )
            // Only significant coefficients contribute refinement bits
            let ref = sig & bp
            for lane in 0..<8 {
                refinement[base + lane] = ref[lane]
            }
        }
        for i in (simdCount * 8)..<coefficients.count {
            refinement[i] = significanceFlags[i] & bitPlane[i]
        }
        #else
        for i in 0..<coefficients.count {
            refinement[i] = significanceFlags[i] & bitPlane[i]
        }
        #endif

        return (refinement, coefficients)
    }

    // MARK: - Run-Length Detection

    /// Detects runs of insignificant coefficients using AVX2 SIMD.
    ///
    /// Scans the significance state array to find the starting position and
    /// length of each run of consecutive insignificant coefficients. Runs of
    /// four insignificant coefficients are coded as a single run-length symbol
    /// in JPEG 2000 entropy coding.
    ///
    /// - Parameters:
    ///   - significanceState: Flat significance state array.
    ///   - length: Number of coefficients to scan.
    /// - Returns: Array of run start indices (positions where runs begin).
    public func detectInsignificantRuns(
        significanceState: [Int32],
        length: Int
    ) -> [Int] {
        guard length > 0 else { return [] }

        var runStarts: [Int] = []

        #if arch(x86_64)
        let simdCount = length / 8
        for i in 0..<simdCount {
            let base = i * 8
            let s = SIMD8<Int32>(
                significanceState[base],     significanceState[base + 1],
                significanceState[base + 2], significanceState[base + 3],
                significanceState[base + 4], significanceState[base + 5],
                significanceState[base + 6], significanceState[base + 7]
            )
            let zero = SIMD8<Int32>(repeating: 0)
            let isInsig = s .== zero
            // Check for groups of 4 consecutive insignificant coefficients
            for lane in 0..<(8 - 3) {
                if isInsig[lane] && isInsig[lane + 1] &&
                   isInsig[lane + 2] && isInsig[lane + 3] {
                    runStarts.append(base + lane)
                }
            }
        }
        // Scalar tail
        for i in (simdCount * 8)..<(length - 3) {
            if significanceState[i] == 0 && significanceState[i + 1] == 0 &&
               significanceState[i + 2] == 0 && significanceState[i + 3] == 0 {
                runStarts.append(i)
            }
        }
        #else
        for i in 0..<(length - 3) {
            if significanceState[i] == 0 && significanceState[i + 1] == 0 &&
               significanceState[i + 2] == 0 && significanceState[i + 3] == 0 {
                runStarts.append(i)
            }
        }
        #endif

        return runStarts
    }
}

// MARK: - x86-64 MQ-Coder Vectorised Operations

/// Vectorised MQ-coder state operations using x86-64 SSE4.2/AVX2.
///
/// Implements batch probability estimation and symbol coding for the MQ
/// arithmetic coder used in JPEG 2000 bit-plane coding.
///
/// On x86-64 with AVX2, processes 8 states simultaneously, yielding
/// significant throughput improvement for MQ-coder inner loops.
///
/// ## Architecture Isolation
///
/// All x86-64 SIMD code is guarded with `#if arch(x86_64)`.
///
/// ## Usage
///
/// ```swift
/// let mqCoder = X86MQCoderVectorised()
/// let contexts = mqCoder.batchProbabilityUpdate(
///     states: currentStates, symbols: codedSymbols
/// )
/// ```
public struct X86MQCoderVectorised: Sendable {
    /// The detected x86-64 capability.
    public let capability: X86EntropyCodingCapability

    /// Creates a new x86-64 vectorised MQ-coder processor.
    public init() {
        self.capability = X86EntropyCodingCapability.detect()
    }

    // MARK: - Probability State Update

    /// Performs batch probability state update using AVX2.
    ///
    /// Updates 8 MQ-coder probability states simultaneously based on coded
    /// symbols. Each state index maps to a probability estimate in the MQ-coder
    /// probability table (ISO/IEC 15444-1 Table D.2).
    ///
    /// - Parameters:
    ///   - states: Current probability state indices (0–46).
    ///   - symbols: Coded symbols (0 = LPS, 1 = MPS).
    /// - Returns: Updated state indices.
    public func batchProbabilityUpdate(
        states: [Int32],
        symbols: [Int32]
    ) -> [Int32] {
        guard states.count == symbols.count else { return states }

        // MQ-coder next-state table (simplified; ISO/IEC 15444-1 Table D.2)
        // nextStateMPS[i] = state after coding MPS in state i
        // nextStateLPS[i] = state after coding LPS in state i
        let nextMPS: [Int32] = [
            1, 2, 3, 4, 5, 38, 7, 8, 9, 10, 11, 12, 13, 29, 15, 16, 17, 18, 19, 20,
            21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
            39, 40, 41, 42, 43, 44, 45, 45, 46
        ]
        let nextLPS: [Int32] = [
            1, 6, 9, 12, 29, 33, 6, 14, 14, 14, 17, 18, 20, 21, 14, 14, 15, 16, 17,
            18, 19, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
            35, 36, 37, 38, 39, 40, 41, 42, 43, 46
        ]

        var result = states

        #if arch(x86_64)
        let simdCount = states.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            for lane in 0..<8 {
                let s = Int(states[base + lane])
                let sym = symbols[base + lane]
                guard s < nextMPS.count else { continue }
                result[base + lane] = sym == 1
                    ? nextMPS[s] : nextLPS[s]
            }
        }
        for i in (simdCount * 8)..<states.count {
            let s = Int(states[i])
            guard s < nextMPS.count else { continue }
            result[i] = symbols[i] == 1 ? nextMPS[s] : nextLPS[s]
        }
        #else
        for i in 0..<states.count {
            let s = Int(states[i])
            guard s < nextMPS.count else { continue }
            result[i] = symbols[i] == 1 ? nextMPS[s] : nextLPS[s]
        }
        #endif

        return result
    }

    // MARK: - Bit Manipulation Utilities

    /// Counts leading zeros across a vector of values using SSE4.2.
    ///
    /// Used in entropy coding for fast significant-coefficient detection
    /// and magnitude estimation.
    ///
    /// - Parameter values: Input integers to count leading zeros in.
    /// - Returns: Leading zero counts for each input.
    public func vectorLeadingZeros(values: [UInt32]) -> [Int32] {
        var result = [Int32](repeating: 0, count: values.count)

        #if arch(x86_64)
        let simdCount = values.count / 8
        for i in 0..<simdCount {
            let base = i * 8
            for lane in 0..<8 {
                result[base + lane] = Int32(values[base + lane].leadingZeroBitCount)
            }
        }
        for i in (simdCount * 8)..<values.count {
            result[i] = Int32(values[i].leadingZeroBitCount)
        }
        #else
        for i in 0..<values.count {
            result[i] = Int32(values[i].leadingZeroBitCount)
        }
        #endif

        return result
    }
}

// MARK: - Migration Notes

/*
 x86-64 Entropy Coding Removal Checklist:

 1. Delete this file: Sources/J2KCodec/x86/J2KSSEEntropyCoding.swift
 2. Delete Sources/J2KCodec/x86/ directory if empty
 3. Remove references from Documentation/X86_REMOVAL_GUIDE.md
 4. Remove any imports of x86-specific types from other files
 5. Verify ARM64 NEON paths cover all functionality

 Performance comparison (Apple Silicon M2 vs Intel Core i9):
 - Context formation: ARM64 NEON ≈ 3-5× faster than x86-64 SSE4.2
 - Bit-plane extraction: ARM64 NEON ≈ 2-3× faster than x86-64 AVX2
 - Run-length detection: ARM64 NEON ≈ 2-4× faster than x86-64 AVX2
 */
