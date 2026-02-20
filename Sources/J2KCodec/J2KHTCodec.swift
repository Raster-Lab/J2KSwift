//
// J2KHTCodec.swift
// J2KSwift
//
/// # HTJ2K Codec
///
/// High-level integration of HTJ2K (High-Throughput JPEG 2000) encoding and
/// decoding into the JPEG 2000 pipeline as specified in ISO/IEC 15444-15.
///
/// HTJ2K provides significantly faster encoding and decoding throughput compared
/// to legacy JPEG 2000, while maintaining compatibility with the JPEG 2000
/// codestream structure. The key difference is the replacement of EBCOT Tier-1
/// coding with the FBCOT (Fast Block Coder with Optimized Truncation) algorithm.
///
/// ## Mixed Codestream Support
///
/// ISO/IEC 15444-15 allows mixing legacy EBCOT and HT code-blocks within the
/// same codestream. This is signaled via the CAP marker segment in the main header,
/// with the specific mode indicated in the COD/COC marker segments.
///
/// ## Topics
///
/// ### Encoding
/// - ``HTJ2KEncoder``
///
/// ### Decoding
/// - ``HTJ2KDecoder``
///
/// ### Configuration
/// - ``HTJ2KConfiguration``
///
/// ### Conformance
/// - ``HTJ2KConformanceValidator``

import Foundation
import J2KCore

// MARK: - HTJ2K Configuration

/// Configuration for HTJ2K encoding and decoding.
///
/// Controls the behavior of the HTJ2K codec, including the coding mode,
/// quality settings, and mixed-mode support.
struct HTJ2KConfiguration: Sendable {
    /// The block coding mode to use for encoding.
    ///
    /// Determines whether to use HT (fast) or legacy (compatible) block coding.
    let codingMode: HTCodingMode

    /// Whether to allow mixed legacy and HT code-blocks in the codestream.
    ///
    /// When `true`, the encoder may use different coding modes for different
    /// code-blocks based on content characteristics.
    let allowMixedMode: Bool

    /// The target quality (0.0 to 1.0) for lossy encoding.
    let quality: Double

    /// Whether to use lossless encoding.
    let lossless: Bool

    /// Maximum number of quality layers.
    let qualityLayers: Int

    /// The number of decomposition levels for wavelet transform.
    let decompositionLevels: Int

    /// Code-block width (must be a power of 2, typically 32 or 64).
    let codeBlockWidth: Int

    /// Code-block height (must be a power of 2, typically 32 or 64).
    let codeBlockHeight: Int

    /// Creates a new HTJ2K configuration.
    ///
    /// - Parameters:
    ///   - codingMode: The block coding mode (default: `.ht`).
    ///   - allowMixedMode: Allow mixed coding modes (default: `false`).
    ///   - quality: Target quality 0.0–1.0 (default: `0.9`).
    ///   - lossless: Use lossless encoding (default: `false`).
    ///   - qualityLayers: Number of quality layers (default: `1`).
    ///   - decompositionLevels: Wavelet decomposition levels (default: `5`).
    ///   - codeBlockWidth: Code-block width (default: `64`).
    ///   - codeBlockHeight: Code-block height (default: `64`).
    init(
        codingMode: HTCodingMode = .ht,
        allowMixedMode: Bool = false,
        quality: Double = 0.9,
        lossless: Bool = false,
        qualityLayers: Int = 1,
        decompositionLevels: Int = 5,
        codeBlockWidth: Int = 64,
        codeBlockHeight: Int = 64
    ) {
        self.codingMode = codingMode
        self.allowMixedMode = allowMixedMode
        self.quality = max(0.0, min(1.0, quality))
        self.lossless = lossless
        self.qualityLayers = max(1, qualityLayers)
        self.decompositionLevels = max(0, min(32, decompositionLevels))
        self.codeBlockWidth = Self.clampToValidBlockSize(codeBlockWidth)
        self.codeBlockHeight = Self.clampToValidBlockSize(codeBlockHeight)
    }

    /// Default HTJ2K configuration for high-throughput encoding.
    static let `default` = HTJ2KConfiguration()

    /// Lossless HTJ2K configuration using reversible transform.
    static let lossless = HTJ2KConfiguration(lossless: true)

    /// Configuration for maximum throughput (larger code-blocks, single layer).
    static let maxThroughput = HTJ2KConfiguration(
        qualityLayers: 1,
        codeBlockWidth: 64,
        codeBlockHeight: 64
    )

    /// Configuration that uses legacy EBCOT for maximum compatibility.
    static let legacyCompatible = HTJ2KConfiguration(codingMode: .legacy)

    /// Clamps a value to the nearest valid code-block size (power of 2, 4–1024).
    private static func clampToValidBlockSize(_ size: Int) -> Int {
        let clamped = max(4, min(1024, size))
        // Round to nearest power of 2
        var power = 4
        while power < clamped {
            power *= 2
        }
        return power
    }
}

// MARK: - HTJ2K Encoder

/// HTJ2K encoder for high-throughput JPEG 2000 encoding.
///
/// The encoder performs the complete HTJ2K encoding pipeline:
/// 1. Color transform (RCT for lossless, ICT for lossy)
/// 2. Wavelet transform (5/3 for lossless, 9/7 for lossy)
/// 3. Quantization (for lossy mode)
/// 4. HT block coding (FBCOT) or legacy EBCOT
/// 5. Tier-2 packet formation
///
/// Example:
/// ```swift
/// let config = HTJ2KConfiguration(codingMode: .ht, quality: 0.85)
/// let encoder = HTJ2KEncoder(configuration: config)
/// let codeBlocks = try encoder.encodeCodeBlocks(coefficients: waveletCoeffs,
///                                               width: 64, height: 64,
///                                               subband: .hh)
/// ```
struct HTJ2KEncoder: Sendable {
    /// The HTJ2K configuration.
    let configuration: HTJ2KConfiguration

    /// Creates a new HTJ2K encoder.
    ///
    /// - Parameter configuration: The encoding configuration.
    init(configuration: HTJ2KConfiguration = .default) {
        self.configuration = configuration
    }

    /// Encodes wavelet coefficients for a code-block using HTJ2K or legacy coding.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients in raster order.
    ///   - width: The code-block width.
    ///   - height: The code-block height.
    ///   - subband: The wavelet subband.
    /// - Returns: An ``HTEncodedResult`` with the coded data and metadata.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeCodeBlocks(
        coefficients: [Int],
        width: Int,
        height: Int,
        subband: J2KSubband
    ) throws -> HTEncodedResult {
        guard !coefficients.isEmpty else {
            throw J2KError.encodingError("Empty coefficient array")
        }
        guard width > 0 && height > 0 else {
            throw J2KError.encodingError("Invalid block dimensions: \(width)x\(height)")
        }

        switch configuration.codingMode {
        case .ht:
            return try encodeHT(
                coefficients: coefficients,
                width: width,
                height: height,
                subband: subband
            )
        case .legacy:
            return try encodeLegacy(
                coefficients: coefficients,
                width: width,
                height: height,
                subband: subband
            )
        }
    }

    /// Generates the CAP marker segment for HTJ2K codestreams.
    ///
    /// The CAP marker signals HTJ2K capability and must appear in the main
    /// header before the COD marker segment.
    ///
    /// - Returns: The CAP marker segment data.
    func generateCAPMarkerData() -> Data {
        var data = Data()

        // Pcap (4 bytes): Part 15 capability bit
        // Bit 14 (from MSB) = HT code-block style
        var pcap: UInt32 = 0
        if configuration.codingMode == .ht || configuration.allowMixedMode {
            pcap |= (1 << 17) // Part 15 bit (bit 14 in zero-indexed from MSB of 32-bit value)
        }
        data.append(UInt8((pcap >> 24) & 0xFF))
        data.append(UInt8((pcap >> 16) & 0xFF))
        data.append(UInt8((pcap >> 8) & 0xFF))
        data.append(UInt8(pcap & 0xFF))

        // Ccap_i (2 bytes per part): extended capability for Part 15
        if configuration.codingMode == .ht || configuration.allowMixedMode {
            // Bit 0: HT code-blocks are present
            // Bit 1: Mixed HT and Part 1 code-blocks allowed
            var ccap: UInt16 = 0x0001
            if configuration.allowMixedMode {
                ccap |= 0x0002
            }
            data.append(UInt8((ccap >> 8) & 0xFF))
            data.append(UInt8(ccap & 0xFF))
        }

        return data
    }

    /// Generates the CPF marker segment for HTJ2K codestreams.
    ///
    /// The CPF (Corresponding Profile) marker specifies the profile to which the
    /// codestream conforms, including HTJ2K-specific profiles defined in ISO/IEC 15444-15.
    ///
    /// - Returns: The CPF marker segment data.
    func generateCPFMarkerData() -> Data {
        var data = Data()

        // Pcpf (2 bytes): Profile capability
        // Bits 0-14: Profile number
        // Bit 15: 0 = Part 1 profile, 1 = Part 15 (HTJ2K) profile
        var pcpf: UInt16 = 0

        if configuration.codingMode == .ht || configuration.allowMixedMode {
            // HTJ2K profile
            pcpf |= 0x8000 // Bit 15 = 1 for Part 15 profile

            // Profile numbers for HTJ2K (ISO/IEC 15444-15):
            // 0: HTJ2K reversible (lossless)
            // 1: HTJ2K irreversible (lossy)
            // 2: HTJ2K broadcast (specialized)
            if configuration.lossless {
                pcpf |= 0x0000 // Profile 0: HTJ2K reversible
            } else {
                pcpf |= 0x0001 // Profile 1: HTJ2K irreversible
            }
        } else {
            // Legacy JPEG 2000 Part 1 profile
            // 0: Profile 0 (basic)
            // 1: Profile 1 (extended)
            // 2: Profile 2 (broadcast)
            if configuration.lossless {
                pcpf |= 0x0000 // Profile 0: basic (works for lossless)
            } else {
                pcpf |= 0x0001 // Profile 1: extended (works for lossy)
            }
        }

        data.append(UInt8((pcpf >> 8) & 0xFF))
        data.append(UInt8(pcpf & 0xFF))

        return data
    }

    /// Encodes using the HT block coder (FBCOT).
    private func encodeHT(
        coefficients: [Int],
        width: Int,
        height: Int,
        subband: J2KSubband
    ) throws -> HTEncodedResult {
        let encoder = HTBlockEncoder(width: width, height: height, subband: subband)

        // Determine the most significant bit-plane
        let maxMag = coefficients.map { abs($0) }.max() ?? 0
        let topBitPlane: Int
        if maxMag > 0 {
            topBitPlane = Int(log2(Double(maxMag)))
        } else {
            topBitPlane = 0
        }

        // Encode cleanup pass
        let cleanupBlock = try encoder.encodeCleanup(
            coefficients: coefficients,
            bitPlane: topBitPlane
        )

        // Build significance state from cleanup pass
        var significanceState = [Bool](repeating: false, count: width * height)
        for i in 0..<coefficients.count where (abs(coefficients[i]) >> topBitPlane) & 1 != 0 {
            significanceState[i] = true
        }

        // Encode refinement passes for lower bit-planes
        var sigPropPasses: [Data] = []
        var magRefPasses: [Data] = []

        for bp in stride(from: topBitPlane - 1, through: 0, by: -1) {
            let sigPropData = try encoder.encodeSigProp(
                coefficients: coefficients,
                significanceState: significanceState,
                bitPlane: bp
            )
            sigPropPasses.append(sigPropData)

            let magRefData = try encoder.encodeMagRef(
                coefficients: coefficients,
                significanceState: significanceState,
                bitPlane: bp
            )
            magRefPasses.append(magRefData)

            // Update significance state
            for i in 0..<coefficients.count where (abs(coefficients[i]) >> bp) & 1 != 0 {
                significanceState[i] = true
            }
        }

        return HTEncodedResult(
            codingMode: .ht,
            cleanupPass: cleanupBlock,
            sigPropPasses: sigPropPasses,
            magRefPasses: magRefPasses,
            zeroBitPlanes: max(0, 31 - topBitPlane),
            totalPasses: 1 + sigPropPasses.count + magRefPasses.count
        )
    }

    /// Encodes using the legacy EBCOT block coder for compatibility.
    private func encodeLegacy(
        coefficients: [Int],
        width: Int,
        height: Int,
        subband: J2KSubband
    ) throws -> HTEncodedResult {
        // Use legacy BitPlaneCoder for Part 1 compatibility
        let coder = BitPlaneCoder(
            width: width,
            height: height,
            subband: subband,
            options: .default
        )

        // Determine bit depth from maximum magnitude
        let maxMag = coefficients.map { abs($0) }.max() ?? 0
        let bitDepth = maxMag > 0 ? Int(log2(Double(maxMag))) + 1 : 1

        let coeffsInt32 = coefficients.map { Int32($0) }
        let result = try coder.encode(coefficients: coeffsInt32, bitDepth: bitDepth)

        // Wrap legacy result in HTEncodedResult
        let cleanupBlock = HTEncodedBlock(
            codedData: result.data,
            passType: .htCleanup,
            melLength: 0,
            vlcLength: 0,
            magsgnLength: result.data.count,
            bitPlane: bitDepth,
            width: width,
            height: height
        )

        return HTEncodedResult(
            codingMode: .legacy,
            cleanupPass: cleanupBlock,
            sigPropPasses: [],
            magRefPasses: [],
            zeroBitPlanes: result.zeroBitPlanes,
            totalPasses: result.passCount
        )
    }
}

// MARK: - HTJ2K Decoder

/// HTJ2K decoder for high-throughput JPEG 2000 decoding.
///
/// The decoder reverses the HTJ2K encoding pipeline to reconstruct wavelet
/// coefficients from coded data. It supports both HT and legacy code-blocks,
/// enabling decoding of mixed codestreams.
///
/// Example:
/// ```swift
/// let decoder = HTJ2KDecoder()
/// let coefficients = try decoder.decodeCodeBlocks(from: encodedResult,
///                                                 width: 64, height: 64,
///                                                 subband: .hh)
/// ```
struct HTJ2KDecoder: Sendable {
    /// Decodes wavelet coefficients from an HTJ2K-encoded result.
    ///
    /// Automatically handles both HT and legacy coded data based on the
    /// coding mode specified in the encoded result.
    ///
    /// - Parameters:
    ///   - result: The encoded result to decode.
    ///   - width: The code-block width.
    ///   - height: The code-block height.
    ///   - subband: The wavelet subband.
    /// - Returns: The decoded wavelet coefficients in raster order.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    func decodeCodeBlocks(
        from result: HTEncodedResult,
        width: Int,
        height: Int,
        subband: J2KSubband
    ) throws -> [Int] {
        switch result.codingMode {
        case .ht:
            return try decodeHT(
                result: result,
                width: width,
                height: height,
                subband: subband
            )
        case .legacy:
            return try decodeLegacy(
                result: result,
                width: width,
                height: height,
                subband: subband
            )
        }
    }

    /// Parses a CAP marker segment to determine HTJ2K capabilities.
    ///
    /// - Parameter data: The CAP marker segment data.
    /// - Returns: A tuple indicating HT support and mixed-mode support.
    /// - Throws: ``J2KError/decodingError(_:)`` if the marker data is invalid.
    func parseCAPMarker(data: Data) throws -> (htSupported: Bool, mixedMode: Bool) {
        guard data.count >= 4 else {
            throw J2KError.decodingError("CAP marker data too short")
        }

        let pcap = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 |
                   UInt32(data[2]) << 8 | UInt32(data[3])

        let htSupported = (pcap & (1 << 17)) != 0

        var mixedMode = false
        if htSupported && data.count >= 6 {
            let ccap = UInt16(data[4]) << 8 | UInt16(data[5])
            mixedMode = (ccap & 0x0002) != 0
        }

        return (htSupported, mixedMode)
    }

    /// Parses a CPF marker segment to determine the codestream profile.
    ///
    /// The CPF marker specifies which JPEG 2000 profile the codestream conforms to,
    /// including HTJ2K-specific profiles from ISO/IEC 15444-15.
    ///
    /// - Parameter data: The CPF marker segment data.
    /// - Returns: A tuple with profile information: (isHTJ2K: Bool, profileNumber: Int, lossless: Bool).
    /// - Throws: ``J2KError/decodingError(_:)`` if the marker data is invalid.
    func parseCPFMarker(data: Data) throws -> (isHTJ2K: Bool, profileNumber: Int, lossless: Bool) {
        guard data.count >= 2 else {
            throw J2KError.decodingError("CPF marker data too short")
        }

        let pcpf = UInt16(data[0]) << 8 | UInt16(data[1])

        // Bit 15: 0 = Part 1 profile, 1 = Part 15 (HTJ2K) profile
        let isHTJ2K = (pcpf & 0x8000) != 0

        // Bits 0-14: Profile number
        let profileNumber = Int(pcpf & 0x7FFF)

        // Determine if lossless based on profile
        // For HTJ2K: Profile 0 = reversible (lossless), Profile 1 = irreversible (lossy)
        // For Part 1: Profile 0 = basic (can be either lossless or lossy)
        //
        // Note: For JPEG 2000 Part 1, the CPF marker alone cannot definitively determine
        // losslessness since Profile 0 supports both modes. The actual lossless/lossy
        // mode is determined by the COD marker's wavelet transform type (5/3 vs 9/7).
        // This function provides a best-effort heuristic based on profile number.
        let lossless = (profileNumber == 0)

        return (isHTJ2K, profileNumber, lossless)
    }

    /// Decodes HT-coded data.
    private func decodeHT(
        result: HTEncodedResult,
        width: Int,
        height: Int,
        subband: J2KSubband
    ) throws -> [Int] {
        let decoder = HTBlockDecoder(width: width, height: height, subband: subband)

        // Decode cleanup pass
        var coefficients = try decoder.decodeCleanup(from: result.cleanupPass)
        var significanceState = coefficients.map { $0 != 0 }

        // Apply refinement passes
        for i in 0..<result.sigPropPasses.count {
            let sigPropResult = try decoder.decodeSigProp(
                coefficients: coefficients,
                sigPropData: result.sigPropPasses[i],
                significanceState: significanceState,
                bitPlane: result.cleanupPass.bitPlane - 1 - i
            )
            coefficients = sigPropResult.coefficients
            significanceState = sigPropResult.significanceState

            if i < result.magRefPasses.count {
                coefficients = try decoder.decodeMagRef(
                    coefficients: coefficients,
                    magRefData: result.magRefPasses[i],
                    significanceState: significanceState,
                    bitPlane: result.cleanupPass.bitPlane - 1 - i
                )
            }
        }

        return coefficients
    }

    /// Decodes legacy EBCOT coded data.
    private func decodeLegacy(
        result: HTEncodedResult,
        width: Int,
        height: Int,
        subband: J2KSubband
    ) throws -> [Int] {
        let decoder = BitPlaneDecoder(
            width: width,
            height: height,
            subband: subband,
            options: .default
        )

        let coeffsInt32 = try decoder.decode(
            data: result.cleanupPass.codedData,
            passCount: result.totalPasses,
            bitDepth: result.cleanupPass.bitPlane,
            zeroBitPlanes: result.zeroBitPlanes
        )

        return coeffsInt32.map { Int($0) }
    }
}

// MARK: - Encoded Result

/// Represents the complete encoded output from an HTJ2K encoding operation.
///
/// Contains the cleanup pass data along with any refinement passes (SigProp
/// and MagRef), plus metadata about the coding mode and pass structure.
struct HTEncodedResult: Sendable {
    /// The coding mode used (HT or legacy).
    let codingMode: HTCodingMode

    /// The cleanup pass encoded block.
    let cleanupPass: HTEncodedBlock

    /// Significance propagation pass data for each refinement bit-plane.
    let sigPropPasses: [Data]

    /// Magnitude refinement pass data for each refinement bit-plane.
    let magRefPasses: [Data]

    /// The number of zero bit-planes above the most significant bit-plane.
    let zeroBitPlanes: Int

    /// The total number of coding passes.
    let totalPasses: Int
}

// MARK: - Conformance Validator

/// Validates HTJ2K codestreams against ISO/IEC 15444-15 requirements.
///
/// Checks structural requirements, marker segment validity, and capability
/// signaling for HTJ2K conformance.
struct HTJ2KConformanceValidator: Sendable {
    /// Validates that the codestream properly signals HTJ2K capabilities.
    ///
    /// - Parameter data: The JPEG 2000 codestream data.
    /// - Returns: A ``ConformanceResult`` with validation details.
    func validate(codestream data: Data) -> ConformanceResult {
        var issues: [String] = []
        var hasCAP = false
        var hasCOD = false

        // Check for SOC marker
        guard data.count >= 4 else {
            return ConformanceResult(
                isValid: false,
                issues: ["Codestream too short"]
            )
        }

        let socMarker = UInt16(data[0]) << 8 | UInt16(data[1])
        guard socMarker == J2KMarker.soc.rawValue else {
            return ConformanceResult(
                isValid: false,
                issues: ["Missing SOC marker"]
            )
        }

        // Scan main header for required markers
        var offset = 2
        while offset < data.count - 1 {
            let marker = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])

            if marker == J2KMarker.cap.rawValue {
                hasCAP = true
            }
            if marker == J2KMarker.cod.rawValue {
                hasCOD = true
            }
            if marker == J2KMarker.sot.rawValue || marker == J2KMarker.sod.rawValue {
                break
            }

            offset += 2
            // Skip segment length + data for markers with segments
            if let m = J2KMarker(rawValue: marker), m.hasSegment {
                if offset + 1 < data.count {
                    let length = Int(data[offset]) << 8 | Int(data[offset + 1])
                    offset += length
                } else {
                    break
                }
            }
        }

        if !hasCAP {
            issues.append("Missing CAP marker segment (required for HTJ2K)")
        }
        if !hasCOD {
            issues.append("Missing COD marker segment")
        }

        return ConformanceResult(
            isValid: issues.isEmpty,
            issues: issues
        )
    }

    /// Validates an encoded result against HTJ2K requirements.
    ///
    /// - Parameter result: The encoded result to validate.
    /// - Returns: A ``ConformanceResult`` with validation details.
    func validate(encodedResult result: HTEncodedResult) -> ConformanceResult {
        var issues: [String] = []

        if result.codingMode == .ht {
            if result.cleanupPass.codedData.isEmpty {
                issues.append("HT cleanup pass produced no data")
            }
            if result.cleanupPass.passType != .htCleanup {
                issues.append("Cleanup pass has wrong pass type")
            }
        }

        if result.totalPasses < 1 {
            issues.append("Must have at least one coding pass")
        }

        return ConformanceResult(
            isValid: issues.isEmpty,
            issues: issues
        )
    }
}

/// The result of an HTJ2K conformance validation check.
struct ConformanceResult: Sendable {
    /// Whether the validation passed.
    let isValid: Bool

    /// Descriptions of any conformance issues found.
    let issues: [String]
}

// MARK: - Benchmarking Support

/// Utility for benchmarking HTJ2K throughput against legacy JPEG 2000.
///
/// Measures encoding and decoding performance for both HT and legacy modes,
/// providing a direct comparison of throughput characteristics.
struct HTJ2KBenchmark: Sendable {
    /// Runs a throughput comparison between HT and legacy encoding.
    ///
    /// - Parameters:
    ///   - coefficients: The wavelet coefficients to encode.
    ///   - width: The code-block width.
    ///   - height: The code-block height.
    ///   - subband: The wavelet subband.
    ///   - iterations: Number of iterations for timing (default: 10).
    /// - Returns: A ``BenchmarkResult`` with timing comparisons.
    /// - Throws: ``J2KError`` if encoding fails.
    func compareEncoding(
        coefficients: [Int],
        width: Int,
        height: Int,
        subband: J2KSubband,
        iterations: Int = 10
    ) throws -> BenchmarkResult {
        let htEncoder = HTJ2KEncoder(configuration: .default)
        let legacyEncoder = HTJ2KEncoder(configuration: .legacyCompatible)

        // Warm up
        _ = try htEncoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: width, height: height, subband: subband
        )
        _ = try legacyEncoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: width, height: height, subband: subband
        )

        // Measure HT encoding
        let htStart = DispatchTime.now()
        for _ in 0..<iterations {
            _ = try htEncoder.encodeCodeBlocks(
                coefficients: coefficients,
                width: width, height: height, subband: subband
            )
        }
        let htEnd = DispatchTime.now()
        let htDuration = Double(htEnd.uptimeNanoseconds - htStart.uptimeNanoseconds) / 1_000_000_000.0

        // Measure legacy encoding
        let legacyStart = DispatchTime.now()
        for _ in 0..<iterations {
            _ = try legacyEncoder.encodeCodeBlocks(
                coefficients: coefficients,
                width: width, height: height, subband: subband
            )
        }
        let legacyEnd = DispatchTime.now()
        let legacyDuration = Double(legacyEnd.uptimeNanoseconds - legacyStart.uptimeNanoseconds) / 1_000_000_000.0

        return BenchmarkResult(
            htEncodingTime: htDuration / Double(iterations),
            legacyEncodingTime: legacyDuration / Double(iterations),
            iterations: iterations,
            blockSize: width * height
        )
    }
}

/// The result of an HTJ2K vs legacy throughput benchmark.
struct BenchmarkResult: Sendable {
    /// Average HT encoding time in seconds.
    let htEncodingTime: Double

    /// Average legacy encoding time in seconds.
    let legacyEncodingTime: Double

    /// Number of benchmark iterations.
    let iterations: Int

    /// The code-block size (width × height) in samples.
    let blockSize: Int

    /// The speedup ratio of HT over legacy (> 1.0 means HT is faster).
    var speedup: Double {
        guard htEncodingTime > 0 else { return 0 }
        return legacyEncodingTime / htEncodingTime
    }

    /// Creates a new benchmark result.
    ///
    /// - Parameters:
    ///   - htEncodingTime: Average HT encoding time.
    ///   - legacyEncodingTime: Average legacy encoding time.
    ///   - iterations: Number of iterations.
    ///   - blockSize: Code-block size in samples.
    init(
        htEncodingTime: Double,
        legacyEncodingTime: Double,
        iterations: Int,
        blockSize: Int
    ) {
        self.htEncodingTime = htEncodingTime
        self.legacyEncodingTime = legacyEncodingTime
        self.iterations = iterations
        self.blockSize = blockSize
    }
}
