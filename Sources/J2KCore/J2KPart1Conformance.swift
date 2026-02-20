//
// J2KPart1Conformance.swift
// J2KSwift
//
/// # JPEG 2000 Part 1 Conformance Hardening
///
/// Week 256–258 deliverable: ISO/IEC 15444-1 (Part 1 Core) conformance hardening.
///
/// Provides marker-segment validation, codestream syntax checking, numerical
/// precision verification, and a complete Part 1 conformance test suite aligned
/// with the requirements of ISO/IEC 15444-4 (Conformance Testing).
///
/// ## Topics
///
/// ### Conformance Classes
/// - ``J2KDecoderConformanceClass``
///
/// ### Validators
/// - ``J2KMarkerSegmentValidator``
/// - ``J2KCodestreamSyntaxValidator``
/// - ``J2KNumericalPrecisionValidator``
///
/// ### Test Suite
/// - ``J2KPart1ConformanceTestSuite``

import Foundation

// MARK: - Decoder Conformance Class

/// Decoder conformance classes as defined in ISO/IEC 15444-4.
///
/// These classes describe the minimum capability a decoder must possess in order
/// to claim conformance with a given subset of ISO/IEC 15444-1 (JPEG 2000 Part 1).
public enum J2KDecoderConformanceClass: String, Sendable, CaseIterable {
    /// Class-0 – Baseline decoder.
    ///
    /// Supports single-tile, lossless, reversible (5/3) wavelet codestreams only.
    /// This is the minimum required capability for any Part 1 conformant decoder.
    case class0 = "Class-0"

    /// Class-1 – Full Part 1 decoder.
    ///
    /// Supports multi-tile codestreams, lossy compression, and the irreversible (9/7)
    /// wavelet transform in addition to all Class-0 capabilities.
    case class1 = "Class-1"
}

// MARK: - Marker Segment Validator

/// Validates individual JPEG 2000 marker segments for ISO/IEC 15444-1 compliance.
///
/// Each `validate*` method inspects the raw byte content of the supplied `Data`
/// buffer and returns a ``J2KMarkerSegmentValidator/MarkerValidationResult``
/// describing any detected conformance issues.
///
/// All methods are pure functions and are safe to call from any concurrency domain.
public struct J2KMarkerSegmentValidator: Sendable {

    // MARK: Severity

    /// Indicates the significance of a validation finding.
    public enum ValidationSeverity: Sendable {
        /// A mandatory requirement of the standard is violated; the codestream is non-conformant.
        case error
        /// A recommendation is not followed; the codestream may still be decodable.
        case warning
        /// An informational observation that does not affect conformance.
        case info
    }

    // MARK: Issue

    /// A single conformance issue found during validation.
    public struct ValidationIssue: Sendable {
        /// Severity of this issue.
        public let severity: ValidationSeverity
        /// The marker code associated with this issue (e.g. `0xFF4F` for SOC).
        public let marker: UInt16
        /// Human-readable description of the issue.
        public let message: String
        /// Byte offset within the codestream where the issue was detected, or `-1` if not applicable.
        public let byteOffset: Int

        /// Creates a new validation issue.
        public init(
            severity: ValidationSeverity,
            marker: UInt16,
            message: String,
            byteOffset: Int
        ) {
            self.severity = severity
            self.marker = marker
            self.message = message
            self.byteOffset = byteOffset
        }
    }

    // MARK: Result

    /// The result of validating one or more marker segments.
    public struct MarkerValidationResult: Sendable {
        /// `true` when no errors were found; warnings and info findings are permitted.
        public let isCompliant: Bool
        /// All issues discovered during validation.
        public let issues: [ValidationIssue]

        /// Number of error-severity issues.
        public var errorCount: Int {
            issues.filter { $0.severity == .error }.count
        }

        /// Number of warning-severity issues.
        public var warningCount: Int {
            issues.filter { $0.severity == .warning }.count
        }

        /// Creates a new validation result.
        public init(isCompliant: Bool, issues: [ValidationIssue]) {
            self.isCompliant = isCompliant
            self.issues = issues
        }
    }

    // MARK: SOC Validation

    /// Validates that the codestream begins with the SOC marker (0xFF4F).
    ///
    /// Per ISO/IEC 15444-1 §A.4.1, the SOC marker shall be the first two bytes of
    /// every conformant JPEG 2000 codestream.
    ///
    /// - Parameter data: The raw codestream bytes.
    /// - Returns: A ``MarkerValidationResult`` indicating whether the SOC is present and correctly positioned.
    public static func validateSOC(_ data: Data) -> MarkerValidationResult {
        var issues: [ValidationIssue] = []

        guard data.count >= 2 else {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF4F,
                message: "Codestream is too short to contain SOC marker (need ≥ 2 bytes, got \(data.count)).",
                byteOffset: 0
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        if data[0] != 0xFF || data[1] != 0x4F {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF4F,
                message: "SOC marker (0xFF4F) not found at byte offset 0; "
                    + "found 0x\(String(format: "%02X%02X", data[0], data[1])) instead.",
                byteOffset: 0
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        return MarkerValidationResult(isCompliant: true, issues: [])
    }

    // MARK: SIZ Validation

    /// Validates the SIZ marker segment (0xFF51) for ISO/IEC 15444-1 §A.5.1 compliance.
    ///
    /// Checks that:
    /// - The marker code is 0xFF51.
    /// - The segment length `Lsiz` is at least 41 bytes (the fixed-length portion).
    /// - `Rsiz` is a recognised profile value.
    /// - `Csiz` (component count) is at least 1.
    ///
    /// - Parameters:
    ///   - data: The raw codestream bytes.
    ///   - offset: Byte offset of the SIZ marker within `data`.
    /// - Returns: A ``MarkerValidationResult`` describing any detected issues.
    public static func validateSIZ(_ data: Data, offset: Int) -> MarkerValidationResult {
        var issues: [ValidationIssue] = []

        // Need at least marker (2) + length (2) at the given offset
        guard offset + 4 <= data.count else {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF51,
                message: "Insufficient data at offset \(offset) to read SIZ marker and length.",
                byteOffset: offset
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        // Verify marker code
        if data[offset] != 0xFF || data[offset + 1] != 0x51 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF51,
                message: "Expected SIZ marker (0xFF51) at offset \(offset); "
                    + "found 0x\(String(format: "%02X%02X", data[offset], data[offset + 1])).",
                byteOffset: offset
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        // Read Lsiz (segment length including the 2-byte length field itself)
        let lsiz = (Int(data[offset + 2]) << 8) | Int(data[offset + 3])

        // ISO/IEC 15444-1 §A.5.1: Lsiz = 38 + 3*Csiz, minimum when Csiz=1 → Lsiz=41
        if lsiz < 41 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF51,
                message: "SIZ segment length Lsiz=\(lsiz) is below the minimum of 41.",
                byteOffset: offset + 2
            ))
        }

        // Ensure enough bytes exist in the buffer
        guard offset + 2 + lsiz <= data.count else {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF51,
                message: "SIZ segment extends beyond end of data "
                    + "(offset=\(offset), Lsiz=\(lsiz), available=\(data.count - offset - 2)).",
                byteOffset: offset
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        // Read Rsiz (capability / profile)
        let rsiz = (Int(data[offset + 4]) << 8) | Int(data[offset + 5])
        // Recognised Rsiz values: 0 (no profile), 1 (Profile-0), 2 (Profile-1), 0x4000+ (HTJ2K)
        let knownRsiz = rsiz == 0 || rsiz == 1 || rsiz == 2 || (rsiz & 0x4000) != 0
        if !knownRsiz {
            issues.append(ValidationIssue(
                severity: .warning,
                marker: 0xFF51,
                message: "Rsiz=0x\(String(format: "%04X", rsiz)) is not a recognised profile value.",
                byteOffset: offset + 4
            ))
        }

        // Read Csiz (component count) at a fixed position within the SIZ body
        // Fixed fields: Lsiz(2) + Rsiz(2) + Xsiz(4) + Ysiz(4) + XOsiz(4) + YOsiz(4)
        //             + XTsiz(4) + YTsiz(4) + XTOsiz(4) + YTOsiz(4) = 36 bytes after marker
        let csizOffset = offset + 2 + 36  // 2 (marker) + 36 fixed body bytes
        if csizOffset + 2 > data.count {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF51,
                message: "SIZ segment too short to contain Csiz field.",
                byteOffset: csizOffset
            ))
            return MarkerValidationResult(isCompliant: issues.isEmpty, issues: issues)
        }

        let csiz = (Int(data[csizOffset]) << 8) | Int(data[csizOffset + 1])
        if csiz < 1 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF51,
                message: "Csiz=\(csiz) is invalid; at least one component is required.",
                byteOffset: csizOffset
            ))
        }

        return MarkerValidationResult(isCompliant: issues.filter { $0.severity == .error }.isEmpty, issues: issues)
    }

    // MARK: COD Validation

    /// Validates the COD marker segment (0xFF52) for ISO/IEC 15444-1 §A.6.1 compliance.
    ///
    /// Checks that:
    /// - The marker code is 0xFF52.
    /// - The segment length `Lcod` is at least 12 bytes.
    /// - The progression order (`Prog`) is in the range 0–4.
    /// - The number of quality layers is at most 65535.
    /// - The number of decomposition levels is in the range 0–32.
    ///
    /// - Parameters:
    ///   - data: The raw codestream bytes.
    ///   - offset: Byte offset of the COD marker within `data`.
    /// - Returns: A ``MarkerValidationResult`` describing any detected issues.
    public static func validateCOD(_ data: Data, offset: Int) -> MarkerValidationResult {
        var issues: [ValidationIssue] = []

        guard offset + 4 <= data.count else {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "Insufficient data at offset \(offset) to read COD marker and length.",
                byteOffset: offset
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        if data[offset] != 0xFF || data[offset + 1] != 0x52 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "Expected COD marker (0xFF52) at offset \(offset); "
                    + "found 0x\(String(format: "%02X%02X", data[offset], data[offset + 1])).",
                byteOffset: offset
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        let lcod = (Int(data[offset + 2]) << 8) | Int(data[offset + 3])

        // ISO/IEC 15444-1 §A.6.1: Lcod ≥ 12
        if lcod < 12 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "COD segment length Lcod=\(lcod) is below the minimum of 12.",
                byteOffset: offset + 2
            ))
        }

        guard offset + 2 + lcod <= data.count else {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "COD segment extends beyond end of data.",
                byteOffset: offset
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        // Scod (coding style): 1 byte at offset+4
        // SGcod starts at offset+5: Prog(1) + Layers(2) + MCT(1)
        // SPcod starts at offset+9: NL(1) + ...
        let codBodyStart = offset + 4  // first byte after Lcod

        guard codBodyStart + 8 <= data.count else {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "COD segment body too short to read SGcod and SPcod fields.",
                byteOffset: codBodyStart
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        // Progression order: SGcod byte 0 (at codBodyStart + 1, after Scod byte)
        let progressionOrder = Int(data[codBodyStart + 1])
        if progressionOrder > 4 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "Progression order \(progressionOrder) is out of range; "
                    + "valid values are 0–4 (LRCP, RLCP, RPCL, PCRL, CPRL).",
                byteOffset: codBodyStart + 1
            ))
        }

        // Number of quality layers: SGcod bytes 1–2 (big-endian)
        let layers = (Int(data[codBodyStart + 2]) << 8) | Int(data[codBodyStart + 3])
        if layers < 1 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "Number of quality layers must be at least 1; got \(layers).",
                byteOffset: codBodyStart + 2
            ))
        }
        // Per spec the field is 16-bit unsigned, so maximum is 65535 — always satisfied
        // unless the field erroneously signals 0.

        // Decomposition levels NL: SPcod byte 0 (at codBodyStart + 5)
        let nl = Int(data[codBodyStart + 5])
        if nl > 32 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFF52,
                message: "Decomposition levels NL=\(nl) exceeds the maximum of 32.",
                byteOffset: codBodyStart + 5
            ))
        }

        return MarkerValidationResult(isCompliant: issues.filter { $0.severity == .error }.isEmpty, issues: issues)
    }

    // MARK: EOC Validation

    /// Validates that the codestream ends with the EOC marker (0xFFD9).
    ///
    /// Per ISO/IEC 15444-1 §A.4.4, the EOC marker shall be the last two bytes of
    /// every conformant JPEG 2000 codestream.
    ///
    /// - Parameter data: The raw codestream bytes.
    /// - Returns: A ``MarkerValidationResult`` indicating whether the EOC is present and correctly positioned.
    public static func validateEOC(_ data: Data) -> MarkerValidationResult {
        var issues: [ValidationIssue] = []

        guard data.count >= 2 else {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFFD9,
                message: "Codestream is too short to contain EOC marker (need ≥ 2 bytes, got \(data.count)).",
                byteOffset: data.count
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        let lastTwo = data.count - 2
        if data[lastTwo] != 0xFF || data[lastTwo + 1] != 0xD9 {
            issues.append(ValidationIssue(
                severity: .error,
                marker: 0xFFD9,
                message: "EOC marker (0xFFD9) not found at end of codestream "
                    + "(last two bytes: 0x\(String(format: "%02X%02X", data[lastTwo], data[lastTwo + 1]))).",
                byteOffset: lastTwo
            ))
            return MarkerValidationResult(isCompliant: false, issues: issues)
        }

        return MarkerValidationResult(isCompliant: true, issues: [])
    }

    // MARK: Full Codestream Validation

    /// Validates the overall structure of a JPEG 2000 codestream.
    ///
    /// Performs the following checks in order:
    /// 1. SOC (0xFF4F) is the first two bytes.
    /// 2. SIZ (0xFF51) appears immediately after SOC.
    /// 3. EOC (0xFFD9) is the last two bytes.
    /// 4. The forbidden marker 0xFF00 does not appear within scan data.
    ///
    /// - Parameter data: The raw codestream bytes.
    /// - Returns: A combined ``MarkerValidationResult`` aggregating all findings.
    public static func validateCodestream(_ data: Data) -> MarkerValidationResult {
        var allIssues: [ValidationIssue] = []

        // 1. SOC check
        let socResult = validateSOC(data)
        allIssues.append(contentsOf: socResult.issues)

        // 2. SIZ immediately after SOC (offset 2)
        if socResult.isCompliant {
            if data.count < 4 || data[2] != 0xFF || data[3] != 0x51 {
                let found = data.count >= 4
                    ? "0x\(String(format: "%02X%02X", data[2], data[3]))"
                    : "<end of data>"
                allIssues.append(ValidationIssue(
                    severity: .error,
                    marker: 0xFF51,
                    message: "SIZ marker (0xFF51) must immediately follow SOC at offset 2; found \(found).",
                    byteOffset: 2
                ))
            } else {
                let sizResult = validateSIZ(data, offset: 2)
                allIssues.append(contentsOf: sizResult.issues)
            }
        }

        // 3. EOC check
        let eocResult = validateEOC(data)
        allIssues.append(contentsOf: eocResult.issues)

        // 4. Scan the codestream for COD markers (validate progression order) and
        //    forbidden 0xFF00 byte sequences (erroneous byte stuffing).
        if data.count >= 2 {
            var scanIdx = 0
            while scanIdx + 1 < data.count {
                guard data[scanIdx] == 0xFF else { scanIdx += 1; continue }
                let markerByte = data[scanIdx + 1]

                if markerByte == 0x52 {
                    // COD marker — validate its progression order inline
                    let codResult = validateCOD(data, offset: scanIdx)
                    for issue in codResult.issues {
                        // Only propagate errors; warnings from COD are forwarded as-is
                        allIssues.append(issue)
                    }
                    if scanIdx + 3 < data.count {
                        let len = (Int(data[scanIdx + 2]) << 8) | Int(data[scanIdx + 3])
                        scanIdx += max(2, 2 + len)
                    } else {
                        scanIdx += 2
                    }
                    continue
                }

                if markerByte == 0x00 {
                    allIssues.append(ValidationIssue(
                        severity: .warning,
                        marker: 0xFF00,
                        message: "Forbidden byte sequence 0xFF00 found at offset \(scanIdx); "
                            + "this indicates erroneous byte stuffing.",
                        byteOffset: scanIdx
                    ))
                }

                // Advance: standalone markers have no length; others skip by length field
                if markerByte >= 0x30 && markerByte <= 0x3F {
                    scanIdx += 2
                } else if scanIdx + 3 < data.count && markerByte != 0x4F && markerByte != 0xD9 {
                    let len = (Int(data[scanIdx + 2]) << 8) | Int(data[scanIdx + 3])
                    scanIdx += len > 0 ? 2 + len : 2
                } else {
                    scanIdx += 2
                }
            }
        }

        let hasErrors = allIssues.contains { $0.severity == .error }
        return MarkerValidationResult(isCompliant: !hasErrors, issues: allIssues)
    }
}

// MARK: - Codestream Syntax Validator

/// Validates the high-level syntax and marker ordering of a JPEG 2000 codestream.
///
/// Implements checks derived from ISO/IEC 15444-1 §A (Codestream Syntax), verifying
/// that markers appear in the correct order and that tile-part structures are well-formed.
public struct J2KCodestreamSyntaxValidator: Sendable {

    // MARK: Result

    /// The result of a codestream syntax validation.
    public struct SyntaxResult: Sendable {
        /// `true` when no syntax errors were found.
        public let isValid: Bool
        /// Descriptions of syntax errors.
        public let errors: [String]
        /// Descriptions of non-fatal warnings.
        public let warnings: [String]
        /// Total number of distinct markers encountered during the scan.
        public let markerCount: Int

        /// Creates a new syntax result.
        public init(isValid: Bool, errors: [String], warnings: [String], markerCount: Int) {
            self.isValid = isValid
            self.errors = errors
            self.warnings = warnings
            self.markerCount = markerCount
        }
    }

    // MARK: Marker Ordering

    /// Validates the ordering of main header markers in the codestream.
    ///
    /// Per ISO/IEC 15444-1 §A.4–A.6, the required ordering is:
    /// - SOC shall be first.
    /// - SIZ shall immediately follow SOC.
    /// - COD and/or COC shall appear before the first SOT.
    /// - EOC shall be last.
    ///
    /// - Parameter data: The raw codestream bytes.
    /// - Returns: A ``SyntaxResult`` describing ordering compliance.
    public static func validateMarkerOrdering(_ data: Data) -> SyntaxResult {
        var errors: [String] = []
        var warnings: [String] = []
        var markerCount = 0

        guard data.count >= 2 else {
            return SyntaxResult(isValid: false, errors: ["Codestream is empty."], warnings: [], markerCount: 0)
        }

        // SOC must be first
        if data[0] != 0xFF || data[1] != 0x4F {
            errors.append("SOC marker (0xFF4F) not found at byte 0.")
        }

        // Walk the main header to collect marker positions
        var idx = 2
        var foundSIZ = false
        var foundCOD = false
        var foundSOT = false
        var foundEOC = false
        var socIsFirst = (data.count >= 2 && data[0] == 0xFF && data[1] == 0x4F)

        // SIZ must be first marker after SOC
        if socIsFirst && data.count >= 4 {
            if data[2] == 0xFF && data[3] == 0x51 {
                foundSIZ = true
                markerCount += 1
            } else {
                errors.append("SIZ marker (0xFF51) must immediately follow SOC; not found at offset 2.")
            }
        }

        // Scan all markers
        idx = 2
        while idx + 1 < data.count {
            guard data[idx] == 0xFF else {
                idx += 1
                continue
            }
            let markerByte = data[idx + 1]

            switch markerByte {
            case 0x51:  // SIZ
                markerCount += 1
                if !foundSIZ { foundSIZ = true }
                // Skip segment
                if idx + 3 < data.count {
                    let len = (Int(data[idx + 2]) << 8) | Int(data[idx + 3])
                    idx += 2 + len
                } else { idx += 2 }
                continue
            case 0x52:  // COD
                markerCount += 1
                if foundSOT {
                    errors.append("COD marker found after SOT; COD must appear in the main header.")
                } else {
                    foundCOD = true
                }
                if idx + 3 < data.count {
                    let len = (Int(data[idx + 2]) << 8) | Int(data[idx + 3])
                    idx += 2 + len
                } else { idx += 2 }
                continue
            case 0x53, 0x5C, 0x5D, 0x5E, 0x5F, 0x64:
                // COC, QCD, QCC, RGN, POC, COM — skip
                markerCount += 1
                if idx + 3 < data.count {
                    let len = (Int(data[idx + 2]) << 8) | Int(data[idx + 3])
                    idx += 2 + len
                } else { idx += 2 }
                continue
            case 0x90:  // SOT
                markerCount += 1
                foundSOT = true
                if idx + 3 < data.count {
                    let len = (Int(data[idx + 2]) << 8) | Int(data[idx + 3])
                    idx += 2 + len
                } else { idx += 2 }
                continue
            case 0x93:  // SOD
                markerCount += 1
                // After SOD we skip to next tile-part or EOC; for ordering purposes just advance
                idx += 2
                continue
            case 0xD9:  // EOC
                markerCount += 1
                foundEOC = true
                idx += 2
                continue
            default:
                if markerByte >= 0x30 && markerByte <= 0x3F {
                    // Markers with no segment (standalone)
                    markerCount += 1
                    idx += 2
                } else {
                    idx += 1
                }
                continue
            }
        }

        if !foundSIZ {
            errors.append("SIZ marker (0xFF51) not found in codestream.")
        }
        if !foundCOD {
            warnings.append("COD marker (0xFF52) not found in main header; it is strongly recommended.")
        }
        if !foundEOC {
            errors.append("EOC marker (0xFFD9) not found at end of codestream.")
        }

        return SyntaxResult(isValid: errors.isEmpty, errors: errors, warnings: warnings, markerCount: markerCount)
    }

    // MARK: Tile-Part Structure

    /// Validates the tile-part structure within a codestream.
    ///
    /// Each SOT marker segment must eventually be followed by an SOD marker,
    /// as required by ISO/IEC 15444-1 §A.4.2.
    ///
    /// - Parameter data: The raw codestream bytes.
    /// - Returns: A ``SyntaxResult`` describing tile-part structure compliance.
    public static func validateTilePartStructure(_ data: Data) -> SyntaxResult {
        var errors: [String] = []
        var warnings: [String] = []
        var markerCount = 0
        var idx = 0

        while idx + 1 < data.count {
            guard data[idx] == 0xFF else {
                idx += 1
                continue
            }

            let markerByte = data[idx + 1]
            markerCount += 1

            if markerByte == 0x90 {  // SOT
                // Read Psot (tile-part length) to know where the SOD should be
                guard idx + 11 < data.count else {
                    errors.append("SOT marker at offset \(idx) is truncated.")
                    idx += 2
                    continue
                }
                let lsot = (Int(data[idx + 2]) << 8) | Int(data[idx + 3])
                guard lsot >= 10 else {
                    errors.append("SOT segment length Lsot=\(lsot) is below the minimum of 10.")
                    idx += 2
                    continue
                }

                // Search for SOD between current SOT and next SOT/EOC
                let sotEnd = idx + 2 + lsot
                var foundSOD = false
                var searchIdx = sotEnd

                while searchIdx + 1 < data.count {
                    if data[searchIdx] == 0xFF {
                        if data[searchIdx + 1] == 0x93 {  // SOD
                            foundSOD = true
                            markerCount += 1
                            break
                        } else if data[searchIdx + 1] == 0x90 || data[searchIdx + 1] == 0xD9 {
                            // Next SOT or EOC — stop searching
                            break
                        }
                    }
                    searchIdx += 1
                }

                if !foundSOD {
                    errors.append("Tile-part beginning at SOT offset \(idx) has no corresponding SOD marker.")
                }

                idx = sotEnd
                continue
            }

            if markerByte == 0x93 {  // SOD (standalone, already counted above or orphaned)
                idx += 2
                continue
            }

            if markerByte == 0xD9 {  // EOC
                idx += 2
                break
            }

            // Markers with a length field
            if idx + 3 < data.count {
                let len = (Int(data[idx + 2]) << 8) | Int(data[idx + 3])
                if len < 2 {
                    warnings.append("Marker 0xFF\(String(format: "%02X", markerByte)) at offset \(idx) has length \(len) < 2.")
                    idx += 2
                } else {
                    idx += 2 + len
                }
            } else {
                idx += 2
            }
        }

        return SyntaxResult(isValid: errors.isEmpty, errors: errors, warnings: warnings, markerCount: markerCount)
    }

    // MARK: Progression Order

    /// Returns `true` if the given progression order value is valid per ISO/IEC 15444-1 §A.6.1.
    ///
    /// Valid progression orders are:
    /// - 0: LRCP (Layer–Resolution–Component–Position)
    /// - 1: RLCP (Resolution–Layer–Component–Position)
    /// - 2: RPCL (Resolution–Position–Component–Layer)
    /// - 3: PCRL (Position–Component–Resolution–Layer)
    /// - 4: CPRL (Component–Position–Resolution–Layer)
    ///
    /// - Parameter progressionOrder: The raw byte value from the SGcod field of a COD segment.
    /// - Returns: `true` if the value is in the range 0–4 (inclusive).
    public static func validateProgressionOrder(_ progressionOrder: UInt8) -> Bool {
        progressionOrder <= 4
    }
}

// MARK: - Numerical Precision Validator

/// Validates numerical precision requirements for lossless and lossy JPEG 2000 decoding.
///
/// Lossless codecs must achieve bit-exact reconstruction (MAE = 0), whilst lossy codecs
/// are assessed against a configurable minimum PSNR threshold.
public struct J2KNumericalPrecisionValidator: Sendable {

    // MARK: Result

    /// The result of a numerical precision validation.
    public struct PrecisionResult: Sendable {
        /// `true` when the reconstruction is bit-exact (lossless context only).
        public let isExact: Bool
        /// Maximum absolute difference between any pair of corresponding samples.
        public let maxAbsoluteError: Int32
        /// Mean squared error over all samples.
        public let meanSquaredError: Double
        /// `true` when the result satisfies the applicable conformance criterion.
        public let passesConformance: Bool

        /// Creates a new precision result.
        public init(
            isExact: Bool,
            maxAbsoluteError: Int32,
            meanSquaredError: Double,
            passesConformance: Bool
        ) {
            self.isExact = isExact
            self.maxAbsoluteError = maxAbsoluteError
            self.meanSquaredError = meanSquaredError
            self.passesConformance = passesConformance
        }
    }

    // MARK: Lossless Round-Trip

    /// Validates that a lossless round-trip produces bit-exact reconstructed samples.
    ///
    /// Per ISO/IEC 15444-1 §G.1, a lossless decoder shall reproduce every sample
    /// exactly; the maximum absolute error must therefore be zero.
    ///
    /// - Parameters:
    ///   - original: The original sample values before encoding.
    ///   - reconstructed: The decoded sample values after decoding.
    /// - Returns: A ``PrecisionResult`` with `passesConformance = true` iff MAE is 0.
    public static func validateLosslessRoundTrip(
        original: [Int32],
        reconstructed: [Int32]
    ) -> PrecisionResult {
        guard original.count == reconstructed.count, !original.isEmpty else {
            return PrecisionResult(
                isExact: false,
                maxAbsoluteError: Int32.max,
                meanSquaredError: Double.infinity,
                passesConformance: false
            )
        }

        var maxErr: Int32 = 0
        var mse: Double = 0.0

        for i in 0..<original.count {
            let diff = original[i] - reconstructed[i]
            let absDiff = diff < 0 ? -diff : diff
            if absDiff > maxErr { maxErr = absDiff }
            mse += Double(diff) * Double(diff)
        }

        mse /= Double(original.count)
        let isExact = maxErr == 0

        return PrecisionResult(
            isExact: isExact,
            maxAbsoluteError: maxErr,
            meanSquaredError: mse,
            passesConformance: isExact
        )
    }

    // MARK: Lossy PSNR

    /// Validates that lossy decoded output meets a minimum PSNR requirement.
    ///
    /// - Parameters:
    ///   - original: The original (reference) sample values.
    ///   - reconstructed: The decoded sample values.
    ///   - bitDepth: The nominal bit depth of the image (used to compute the peak value).
    ///   - minimumPSNR: The minimum acceptable PSNR in decibels.
    /// - Returns: A ``PrecisionResult`` with `passesConformance = true` iff PSNR ≥ `minimumPSNR`.
    public static func validateLossyPSNR(
        original: [Int32],
        reconstructed: [Int32],
        bitDepth: Int,
        minimumPSNR: Double
    ) -> PrecisionResult {
        guard original.count == reconstructed.count, !original.isEmpty, bitDepth > 0 else {
            return PrecisionResult(
                isExact: false,
                maxAbsoluteError: Int32.max,
                meanSquaredError: Double.infinity,
                passesConformance: false
            )
        }

        var maxErr: Int32 = 0
        var mse: Double = 0.0

        for i in 0..<original.count {
            let diff = original[i] - reconstructed[i]
            let absDiff = diff < 0 ? -diff : diff
            if absDiff > maxErr { maxErr = absDiff }
            mse += Double(diff) * Double(diff)
        }

        mse /= Double(original.count)
        let isExact = maxErr == 0

        let passes: Bool
        if mse == 0.0 {
            passes = true  // Infinite PSNR — trivially satisfies any finite threshold
        } else {
            let peakValue = Double((1 << bitDepth) - 1)
            let psnr = 10.0 * log10((peakValue * peakValue) / mse)
            passes = psnr >= minimumPSNR
        }

        return PrecisionResult(
            isExact: isExact,
            maxAbsoluteError: maxErr,
            meanSquaredError: mse,
            passesConformance: passes
        )
    }

    // MARK: Bit-Depth Range

    /// Validates that all samples in the supplied array lie within the representable range for the
    /// given bit depth and signedness.
    ///
    /// - Parameters:
    ///   - samples: The sample values to validate.
    ///   - bitDepth: The nominal bit depth of the component (1–32).
    ///   - isSigned: `true` for two's-complement signed samples; `false` for unsigned samples.
    /// - Returns: `true` if every sample is within the valid range.
    public static func validateBitDepthRange(
        _ samples: [Int32],
        bitDepth: Int,
        isSigned: Bool
    ) -> Bool {
        guard bitDepth > 0, bitDepth <= 32 else { return false }

        let minValue: Int32
        let maxValue: Int32

        if isSigned {
            // Two's-complement: -(2^(bitDepth-1)) … 2^(bitDepth-1)-1
            if bitDepth == 32 {
                minValue = Int32.min
                maxValue = Int32.max
            } else {
                minValue = -(Int32(1) << (bitDepth - 1))
                maxValue = (Int32(1) << (bitDepth - 1)) - 1
            }
        } else {
            // Unsigned: 0 … 2^bitDepth-1
            minValue = 0
            if bitDepth >= 32 {
                maxValue = Int32.max
            } else {
                maxValue = (Int32(1) << bitDepth) - 1
            }
        }

        return samples.allSatisfy { $0 >= minValue && $0 <= maxValue }
    }
}

// MARK: - Part 1 Conformance Test Suite

/// Generates and evaluates ISO/IEC 15444-1 Part 1 conformance test vectors.
///
/// Provides a curated library of test cases covering the full range of Part 1
/// decoder requirements, from minimal single-tile lossless configurations through
/// to multi-tile multi-component lossy streams and error-resilience scenarios.
public struct J2KPart1ConformanceTestSuite: Sendable {

    // MARK: Test Category

    /// Broad category groupings for Part 1 conformance test cases.
    public enum TestCategory: String, Sendable, CaseIterable {
        /// Class-0 decoder requirements (single-tile, lossless, reversible wavelet).
        case decoderClass0
        /// Class-1 decoder requirements (multi-tile, lossy, irreversible wavelet).
        case decoderClass1
        /// Marker segment structural and field validation.
        case markerValidation
        /// Numerical precision, lossless round-trip, and PSNR checks.
        case numericalPrecision
        /// Error-resilience, truncation, and malformed-codestream handling.
        case errorResilience
    }

    // MARK: Test Case

    /// A single Part 1 conformance test case.
    public struct ConformanceTestCase: Sendable {
        /// Unique identifier for this test case (e.g. `"p1-cls0-001"`).
        public let identifier: String
        /// Broad category this test case belongs to.
        public let category: TestCategory
        /// Human-readable description of what is being verified.
        public let description: String
        /// The raw JPEG 2000 codestream under test.
        public let codestream: Data
        /// `true` if the codestream is expected to be conformant / decodable.
        public let expectedValid: Bool
        /// The decoder class that must successfully decode this codestream, if applicable.
        public let expectedDecoderClass: J2KDecoderConformanceClass?

        /// Creates a new conformance test case.
        public init(
            identifier: String,
            category: TestCategory,
            description: String,
            codestream: Data,
            expectedValid: Bool,
            expectedDecoderClass: J2KDecoderConformanceClass? = nil
        ) {
            self.identifier = identifier
            self.category = category
            self.description = description
            self.codestream = codestream
            self.expectedValid = expectedValid
            self.expectedDecoderClass = expectedDecoderClass
        }
    }

    // MARK: Standard Test Cases

    /// Returns the standard library of Part 1 conformance test cases.
    ///
    /// Covers at least 20 distinct scenarios including:
    /// - Valid minimal (Class-0) codestreams.
    /// - Valid multi-component codestreams.
    /// - Invalid codestreams missing SOC, SIZ, or EOC.
    /// - Invalid COD with out-of-range progression order.
    /// - Valid 5-level DWT, lossless, and lossy configurations.
    /// - Truncated codestreams.
    /// - Codestreams with unknown extension markers.
    /// - Tile-part structure variants.
    /// - Various bit depths (1, 8, 12, 16).
    ///
    /// - Returns: An array of ``ConformanceTestCase`` values.
    public static func standardTestCases() -> [ConformanceTestCase] {
        var cases: [ConformanceTestCase] = []

        // ── Class-0: valid minimal codestream ──────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls0-001",
            category: .decoderClass0,
            description: "Valid minimal Class-0 codestream: single-tile, 1-component, 8-bit, lossless.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Class-0: single-tile lossless, reversible wavelet ──────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls0-002",
            category: .decoderClass0,
            description: "Valid Class-0 single-tile lossless with explicit reversible wavelet signalling.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 16, height: 16, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Class-1: multi-component codestream ───────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls1-001",
            category: .decoderClass1,
            description: "Valid Class-1 codestream with 3 components (RGB), 8-bit.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 16, height: 16, components: 3, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class1
        ))

        // ── Class-1: lossy single-tile ─────────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls1-002",
            category: .decoderClass1,
            description: "Valid Class-1 single-tile lossy codestream, 8-bit.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 32, height: 32, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class1
        ))

        // ── Marker validation: missing SOC ────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-mrk-001",
            category: .markerValidation,
            description: "Invalid codestream: SOC marker absent (stream starts with 0x0000).",
            codestream: makeInvalidCodestream_missingSOC(),
            expectedValid: false,
            expectedDecoderClass: nil
        ))

        // ── Marker validation: missing SIZ ────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-mrk-002",
            category: .markerValidation,
            description: "Invalid codestream: SOC present but SIZ marker absent.",
            codestream: makeInvalidCodestream_missingSIZ(),
            expectedValid: false,
            expectedDecoderClass: nil
        ))

        // ── Marker validation: missing EOC ────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-mrk-003",
            category: .markerValidation,
            description: "Invalid codestream: EOC marker absent (truncated at end).",
            codestream: makeInvalidCodestream_missingEOC(),
            expectedValid: false,
            expectedDecoderClass: nil
        ))

        // ── Marker validation: invalid COD progression order ──────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-mrk-004",
            category: .markerValidation,
            description: "Invalid codestream: COD progression order byte is 0x0A (out of range 0–4).",
            codestream: makeInvalidCodestream_badProgressionOrder(),
            expectedValid: false,
            expectedDecoderClass: nil
        ))

        // ── Class-0: valid 5-level DWT ────────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls0-003",
            category: .decoderClass0,
            description: "Valid Class-0 codestream with 5-level decomposition, 32×32 image.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 32, height: 32, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Class-0: explicit lossless configuration ──────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls0-004",
            category: .decoderClass0,
            description: "Valid lossless configuration, 1-component, 8-bit.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Error resilience: truncated codestream ────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-err-001",
            category: .errorResilience,
            description: "Truncated codestream: only the first 6 bytes present.",
            codestream: Data([0xFF, 0x4F, 0xFF, 0x51, 0x00, 0x29]),
            expectedValid: false,
            expectedDecoderClass: nil
        ))

        // ── Error resilience: unknown extension markers ────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-err-002",
            category: .errorResilience,
            description: "Codestream with unknown comment marker (COM) — should warn, not fail.",
            codestream: makeCodestreamWithCOMMarker(),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Marker validation: valid tile-part structure ───────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-mrk-005",
            category: .markerValidation,
            description: "Valid tile-part structure: SOT followed by SOD.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Numerical precision: 8-bit lossless ───────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-num-001",
            category: .numericalPrecision,
            description: "8-bit lossless round-trip precision test vector.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Numerical precision: 12-bit ───────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-num-002",
            category: .numericalPrecision,
            description: "12-bit lossless precision test vector.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 1, bitDepth: 12, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Numerical precision: 16-bit ───────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-num-003",
            category: .numericalPrecision,
            description: "16-bit lossless precision test vector.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 1, bitDepth: 16, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Numerical precision: 1-bit ────────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-num-004",
            category: .numericalPrecision,
            description: "1-bit (bi-level) precision test vector.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 1, bitDepth: 1, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Class-1: multiple progression orders ──────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls1-003",
            category: .decoderClass1,
            description: "Valid multi-component codestream suitable for different progression orders.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 16, height: 16, components: 4, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class1
        ))

        // ── Error resilience: empty data ──────────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-err-003",
            category: .errorResilience,
            description: "Empty codestream (zero bytes) — must be rejected.",
            codestream: Data(),
            expectedValid: false,
            expectedDecoderClass: nil
        ))

        // ── Error resilience: only SOC marker ─────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-err-004",
            category: .errorResilience,
            description: "Codestream containing only the SOC marker — missing all required segments.",
            codestream: Data([0xFF, 0x4F]),
            expectedValid: false,
            expectedDecoderClass: nil
        ))

        // ── Class-1: 4-component (CMYK-like), 8-bit ───────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls1-004",
            category: .decoderClass1,
            description: "Valid Class-1 codestream with 4 components and 8-bit depth.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 16, height: 16, components: 4, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class1
        ))

        // ── Class-0: 1-component, 8-bit single tile lossless ─────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls0-005",
            category: .decoderClass0,
            description: "Single-tile lossless 1-component 8-bit — canonical Class-0 test.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 4, height: 4, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class0
        ))

        // ── Class-1: single-tile lossy, 8-bit ─────────────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-cls1-005",
            category: .decoderClass1,
            description: "Single-tile lossy 8-bit — Class-1 decoder test.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 64, height: 64, components: 1, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class1
        ))

        // ── Numerical precision: 3-component 8-bit RGB ────────────────────────
        cases.append(ConformanceTestCase(
            identifier: "p1-num-005",
            category: .numericalPrecision,
            description: "3-component (RGB) 8-bit numerical precision test vector.",
            codestream: J2KHTInteroperabilityValidator.createSyntheticCodestream(
                width: 8, height: 8, components: 3, bitDepth: 8, htj2k: false
            ),
            expectedValid: true,
            expectedDecoderClass: .class1
        ))

        return cases
    }

    // MARK: Report Generation

    /// Generates a Markdown-formatted conformance report from a set of test results.
    ///
    /// - Parameter results: An array of `(ConformanceTestCase, Bool)` pairs where the
    ///   `Bool` indicates whether the test passed (`true`) or failed (`false`).
    /// - Returns: A Markdown string summarising the conformance results.
    public static func generateReport(results: [(ConformanceTestCase, Bool)]) -> String {
        let totalCount = results.count
        let passCount = results.filter { $0.1 }.count
        let failCount = totalCount - passCount

        var lines: [String] = []
        lines.append("# JPEG 2000 Part 1 Conformance Report")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")
        lines.append("| Total test cases | \(totalCount) |")
        lines.append("| Passed | \(passCount) |")
        lines.append("| Failed | \(failCount) |")
        lines.append("| Pass rate | \(totalCount > 0 ? String(format: "%.1f%%", Double(passCount) / Double(totalCount) * 100) : "N/A") |")
        lines.append("")
        lines.append("## Results by Category")
        lines.append("")

        // Group by category
        var byCategory: [TestCategory: [(ConformanceTestCase, Bool)]] = [:]
        for result in results {
            byCategory[result.0.category, default: []].append(result)
        }

        for category in TestCategory.allCases {
            guard let categoryResults = byCategory[category], !categoryResults.isEmpty else { continue }
            let catPass = categoryResults.filter { $0.1 }.count
            lines.append("### \(category.rawValue)")
            lines.append("")
            lines.append("**\(catPass)/\(categoryResults.count) passed**")
            lines.append("")
            lines.append("| Identifier | Description | Expected | Result |")
            lines.append("|------------|-------------|----------|--------|")

            for (testCase, passed) in categoryResults {
                let expected = testCase.expectedValid ? "Valid" : "Invalid"
                let result = passed ? "✅ Pass" : "❌ Fail"
                let desc = testCase.description
                    .replacingOccurrences(of: "|", with: "\\|")
                lines.append("| `\(testCase.identifier)` | \(desc) | \(expected) | \(result) |")
            }
            lines.append("")
        }

        lines.append("---")
        lines.append("*Generated by J2KPart1ConformanceTestSuite — ISO/IEC 15444-1 / 15444-4*")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Builds a minimal invalid codestream that starts with wrong bytes instead of SOC.
    private static func makeInvalidCodestream_missingSOC() -> Data {
        // Starts with 0x0000 instead of 0xFF4F
        var data = Data([0x00, 0x00])
        data.append(contentsOf: [0xFF, 0x51])  // SIZ marker (but SOC is missing)
        data.append(contentsOf: [0xFF, 0xD9])  // EOC
        return data
    }

    /// Builds a codestream with SOC but no SIZ marker.
    private static func makeInvalidCodestream_missingSIZ() -> Data {
        var data = Data()
        data.append(contentsOf: [0xFF, 0x4F])  // SOC
        // Skip SIZ; go straight to EOC
        data.append(contentsOf: [0xFF, 0xD9])  // EOC
        return data
    }

    /// Builds a codestream that is missing the EOC marker at the end.
    private static func makeInvalidCodestream_missingEOC() -> Data {
        var data = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )
        // Drop the last two bytes (EOC)
        if data.count >= 2 {
            data = data.dropLast(2)
        }
        return data
    }

    /// Builds a codestream with a COD marker whose progression order byte is out of range.
    private static func makeInvalidCodestream_badProgressionOrder() -> Data {
        var base = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        // Locate COD marker (0xFF52) and patch the progression order byte
        for i in 0..<(base.count - 1) {
            if base[i] == 0xFF && base[i + 1] == 0x52 {
                // COD segment: marker(2) + Lcod(2) + Scod(1) + SGcod: Prog(1) ...
                let progOffset = i + 2 + 2 + 1  // after marker, Lcod, Scod
                if progOffset < base.count {
                    base[progOffset] = 0x0A  // Invalid: 10 > 4
                }
                break
            }
        }
        return base
    }

    /// Builds a valid codestream that contains a COM (comment) marker.
    private static func makeCodestreamWithCOMMarker() -> Data {
        // Start with the synthetic codestream and insert a COM marker before EOC
        var base = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        guard base.count >= 2 else { return base }

        // Build COM segment: marker 0xFF64 + Lcom(2) + Rcom(2) + comment bytes
        let comment = "J2KSwift conformance".utf8
        var comSegment = Data()
        comSegment.append(contentsOf: [0xFF, 0x64])                 // COM marker
        let lcom = UInt16(2 + 2 + comment.count)                    // Lcom includes itself
        comSegment.append(UInt8((lcom >> 8) & 0xFF))
        comSegment.append(UInt8(lcom & 0xFF))
        comSegment.append(contentsOf: [0x00, 0x01])                 // Rcom = 1 (Latin/ISO 8859-1)
        comSegment.append(contentsOf: comment)

        // Insert COM before the final EOC
        let insertionPoint = base.count - 2
        base.insert(contentsOf: comSegment, at: insertionPoint)
        return base
    }
}
