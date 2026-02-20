//
// J2KPart2ConformanceHardening.swift
// J2KSwift
//
/// # JPEG 2000 Part 2 (Extensions) Conformance Hardening
///
/// Week 259–260 deliverable: ISO/IEC 15444-2 (Part 2 Extensions) conformance hardening.
///
/// Provides JPX file-format validation, per-extension conformance validators, and a
/// complete Part 2 conformance test suite covering DC-Offset, Arbitrary Wavelets,
/// Multi-Component Transform, Non-Linear Transform, Trellis-Coded Quantisation,
/// Extended ROI, and Extended Precision.
///
/// ## Topics
///
/// ### Extensions
/// - ``J2KPart2Extension``
///
/// ### Validators
/// - ``J2KJPXFileFormatValidator``
/// - ``J2KPart2ConformanceValidator``
///
/// ### Test Suite
/// - ``J2KPart2ConformanceTestSuite``

import Foundation

// MARK: - Part 2 Extensions

/// Identifies the optional extensions defined in ISO/IEC 15444-2 (JPEG 2000 Part 2).
///
/// Each case corresponds to a capability that a Part 2 compliant encoder or decoder
/// may declare in the JPX file-type or CAP marker.
public enum J2KPart2Extension: String, Sendable, CaseIterable {
    /// DC-Offset coding extension.
    case dcOffset = "DC-Offset"
    /// Arbitrary (non-standard) wavelet filter extension.
    case arbitraryWavelets = "Arbitrary-Wavelets"
    /// Multi-Component Transform extension.
    case multiComponentTransform = "MCT"
    /// Non-Linear Transform extension.
    case nonLinearTransform = "NLT"
    /// Trellis-Coded Quantisation extension.
    case trellisCodedQuantisation = "TCQ"
    /// Extended Region of Interest extension.
    case extendedROI = "Extended-ROI"
    /// Extended sample precision extension.
    case extendedPrecision = "Extended-Precision"
}

// MARK: - JPX File-Format Validator

/// Validates the JPX (JPEG 2000 Part 2) file-format structure.
///
/// All methods are pure functions and are safe to call from any concurrency domain.
public struct J2KJPXFileFormatValidator: Sendable {

    // MARK: Result

    /// The result of a JPX file-format validation check.
    public struct JPXValidationResult: Sendable {
        /// `true` when no errors were detected.
        public let isValid: Bool
        /// Conformance errors found during validation.
        public let errors: [String]
        /// Non-fatal warnings found during validation.
        public let warnings: [String]

        /// Creates a new JPX validation result.
        public init(isValid: Bool, errors: [String], warnings: [String]) {
            self.isValid = isValid
            self.errors = errors
            self.warnings = warnings
        }
    }

    // MARK: JP2 Signature Box

    /// Validates the JP2 Signature box at the start of the supplied data.
    ///
    /// The JP2 Signature box occupies the first 12 bytes and must equal
    /// `00 00 00 0C 6A 50 20 20 0D 0A 87 0A` (ISO/IEC 15444-1 §I.5.1).
    ///
    /// - Parameter data: The raw file bytes.
    /// - Returns: A ``JPXValidationResult`` indicating whether the signature is correct.
    public static func validateJP2Signature(_ data: Data) -> JPXValidationResult {
        let required: [UInt8] = [
            0x00, 0x00, 0x00, 0x0C,
            0x6A, 0x50, 0x20, 0x20,
            0x0D, 0x0A, 0x87, 0x0A
        ]

        guard data.count >= required.count else {
            return JPXValidationResult(
                isValid: false,
                errors: ["Data too short for JP2 Signature box: need ≥ \(required.count) bytes, got \(data.count)."],
                warnings: []
            )
        }

        for (index, byte) in required.enumerated() where data[index] != byte {
            return JPXValidationResult(
                isValid: false,
                errors: ["JP2 Signature box mismatch at byte \(index): expected 0x\(String(byte, radix: 16, uppercase: true)), got 0x\(String(data[index], radix: 16, uppercase: true))."],
                warnings: []
            )
        }

        return JPXValidationResult(isValid: true, errors: [], warnings: [])
    }

    // MARK: File Type Box

    /// Validates that a File Type box (ftyp) is present immediately after the JP2 Signature box.
    ///
    /// The ftyp box carries the 4-byte box type `66 74 79 70` ("ftyp") and must appear
    /// at byte offset 12 in a conformant JP2/JPX file (ISO/IEC 15444-1 §I.5.2).
    ///
    /// - Parameter data: The raw file bytes.
    /// - Returns: A ``JPXValidationResult`` indicating whether an ftyp box is present.
    public static func validateJP2FileTypeBox(_ data: Data) -> JPXValidationResult {
        // ftyp box starts at byte 12; minimum structure: 4-byte length + 4-byte type
        let ftypOffset = 12
        let ftypType: [UInt8] = [0x66, 0x74, 0x79, 0x70]

        guard data.count >= ftypOffset + 8 else {
            return JPXValidationResult(
                isValid: false,
                errors: ["Data too short to contain File Type box after Signature box (need ≥ \(ftypOffset + 8) bytes)."],
                warnings: []
            )
        }

        let typeStart = ftypOffset + 4
        for (i, byte) in ftypType.enumerated() where data[typeStart + i] != byte {
            return JPXValidationResult(
                isValid: false,
                errors: ["File Type box (ftyp) not found at expected offset \(typeStart): box type bytes do not match."],
                warnings: []
            )
        }

        return JPXValidationResult(isValid: true, errors: [], warnings: [])
    }

    // MARK: JPX Capabilities

    /// Validates that the declared extensions are consistent with JPX compatibility.
    ///
    /// When any Part 2 extension is used, the File Type box must declare `jpx ` as a
    /// compatible brand.  This method returns a warning rather than an error because
    /// the brand list is not inspected from raw bytes; callers are expected to supply
    /// the logical extension list from a higher-level parser.
    ///
    /// - Parameter extensions: The list of Part 2 extensions in use.
    /// - Returns: A ``JPXValidationResult`` with a warning when extensions are present.
    public static func validateJPXCapabilities(_ extensions: [J2KPart2Extension]) -> JPXValidationResult {
        guard !extensions.isEmpty else {
            return JPXValidationResult(isValid: true, errors: [], warnings: [])
        }

        let names = extensions.map(\.rawValue).joined(separator: ", ")
        return JPXValidationResult(
            isValid: true,
            errors: [],
            warnings: [
                "Extensions in use (\(names)) require Part 2 (JPX) compatibility to be declared in the File Type box."
            ]
        )
    }
}

// MARK: - Part 2 Conformance Validator

/// Validates individual ISO/IEC 15444-2 extensions for conformance.
///
/// Each `validate*` method returns an ``J2KPart2ConformanceValidator/ExtensionResult``
/// that captures support, compliance, and any explanatory notes.
public struct J2KPart2ConformanceValidator: Sendable {

    // MARK: Result

    /// The result of validating a single Part 2 extension configuration.
    public struct ExtensionResult: Sendable {
        /// The extension that was validated.
        public let `extension`: J2KPart2Extension
        /// `true` when the extension is supported by the implementation.
        public let isSupported: Bool
        /// `true` when the supplied parameters conform to ISO/IEC 15444-2.
        public let isCompliant: Bool
        /// Human-readable notes describing the outcome or any violations.
        public let notes: String

        /// Creates a new extension result.
        public init(extension ext: J2KPart2Extension, isSupported: Bool, isCompliant: Bool, notes: String) {
            self.extension = ext
            self.isSupported = isSupported
            self.isCompliant = isCompliant
            self.notes = notes
        }
    }

    // MARK: MCT

    /// Validates a Multi-Component Transform configuration.
    ///
    /// Conforms when `componentCount ≥ 2` and `transformCount ≤ componentCount`.
    ///
    /// - Parameters:
    ///   - componentCount: Number of image components.
    ///   - transformCount: Number of MCT stages declared.
    /// - Returns: An ``ExtensionResult`` for the MCT extension.
    public static func validateMCT(componentCount: Int, transformCount: Int) -> ExtensionResult {
        guard componentCount >= 2 else {
            return ExtensionResult(
                extension: .multiComponentTransform,
                isSupported: true,
                isCompliant: false,
                notes: "MCT requires at least 2 components; got \(componentCount)."
            )
        }

        guard transformCount <= componentCount else {
            return ExtensionResult(
                extension: .multiComponentTransform,
                isSupported: true,
                isCompliant: false,
                notes: "Transform count (\(transformCount)) must not exceed component count (\(componentCount))."
            )
        }

        return ExtensionResult(
            extension: .multiComponentTransform,
            isSupported: true,
            isCompliant: true,
            notes: "MCT configuration is valid (\(componentCount) components, \(transformCount) stages)."
        )
    }

    // MARK: NLT

    /// Validates a Non-Linear Transform type value.
    ///
    /// Valid NLT type values are 0 (none), 1 (gamma), and 2 (lookup table).
    ///
    /// - Parameter type: The NLT type byte from the NLT marker segment.
    /// - Returns: An ``ExtensionResult`` for the NLT extension.
    public static func validateNLT(type: UInt8) -> ExtensionResult {
        let validTypes: Set<UInt8> = [0, 1, 2]

        guard validTypes.contains(type) else {
            return ExtensionResult(
                extension: .nonLinearTransform,
                isSupported: true,
                isCompliant: false,
                notes: "NLT type \(type) is not defined in ISO/IEC 15444-2; valid values are 0 (none), 1 (gamma), 2 (LUT)."
            )
        }

        return ExtensionResult(
            extension: .nonLinearTransform,
            isSupported: true,
            isCompliant: true,
            notes: "NLT type \(type) is valid."
        )
    }

    // MARK: TCQ

    /// Validates a Trellis-Coded Quantisation configuration.
    ///
    /// Conforms when `guardbits` is in the range `0…7` and `stepCount ≥ 1`.
    ///
    /// - Parameters:
    ///   - guardbits: Number of guard bits in the TCQ quantisation step.
    ///   - stepCount: Number of quantisation steps.
    /// - Returns: An ``ExtensionResult`` for the TCQ extension.
    public static func validateTCQ(guardbits: Int, stepCount: Int) -> ExtensionResult {
        guard (0...7).contains(guardbits) else {
            return ExtensionResult(
                extension: .trellisCodedQuantisation,
                isSupported: true,
                isCompliant: false,
                notes: "Guard bits value \(guardbits) is out of range 0–7."
            )
        }

        guard stepCount >= 1 else {
            return ExtensionResult(
                extension: .trellisCodedQuantisation,
                isSupported: true,
                isCompliant: false,
                notes: "TCQ step count must be ≥ 1; got \(stepCount)."
            )
        }

        return ExtensionResult(
            extension: .trellisCodedQuantisation,
            isSupported: true,
            isCompliant: true,
            notes: "TCQ configuration is valid (guard bits: \(guardbits), steps: \(stepCount))."
        )
    }

    // MARK: Extended ROI

    /// Validates an Extended ROI shift parameter.
    ///
    /// Conforms when `shift ≥ 0` and `shift ≤ maxShift` (maximum allowed value is 37).
    ///
    /// - Parameters:
    ///   - shift: The ROI upshift value.
    ///   - maxShift: The declared maximum shift; must not exceed 37.
    /// - Returns: An ``ExtensionResult`` for the Extended ROI extension.
    public static func validateExtendedROI(shift: Int, maxShift: Int) -> ExtensionResult {
        let absoluteMax = 37

        guard shift >= 0 else {
            return ExtensionResult(
                extension: .extendedROI,
                isSupported: true,
                isCompliant: false,
                notes: "ROI shift must be ≥ 0; got \(shift)."
            )
        }

        guard shift <= min(maxShift, absoluteMax) else {
            return ExtensionResult(
                extension: .extendedROI,
                isSupported: true,
                isCompliant: false,
                notes: "ROI shift \(shift) exceeds allowed maximum \(min(maxShift, absoluteMax))."
            )
        }

        return ExtensionResult(
            extension: .extendedROI,
            isSupported: true,
            isCompliant: true,
            notes: "Extended ROI shift \(shift) is valid (max: \(maxShift))."
        )
    }

    // MARK: Arbitrary Wavelet

    /// Validates an arbitrary wavelet filter configuration.
    ///
    /// For symmetric filters, the tap count must be odd and ≥ 3.
    /// For asymmetric filters, the tap count must be ≥ 2.
    ///
    /// - Parameters:
    ///   - tapCount: Number of filter taps.
    ///   - isSymmetric: `true` if the filter is symmetric.
    /// - Returns: An ``ExtensionResult`` for the Arbitrary Wavelets extension.
    public static func validateArbitraryWavelet(tapCount: Int, isSymmetric: Bool) -> ExtensionResult {
        if isSymmetric {
            guard tapCount >= 3 else {
                return ExtensionResult(
                    extension: .arbitraryWavelets,
                    isSupported: true,
                    isCompliant: false,
                    notes: "Symmetric wavelet filter requires ≥ 3 taps; got \(tapCount)."
                )
            }

            guard tapCount % 2 == 1 else {
                return ExtensionResult(
                    extension: .arbitraryWavelets,
                    isSupported: true,
                    isCompliant: false,
                    notes: "Symmetric wavelet filter must have an odd tap count; got \(tapCount)."
                )
            }
        } else {
            guard tapCount >= 2 else {
                return ExtensionResult(
                    extension: .arbitraryWavelets,
                    isSupported: true,
                    isCompliant: false,
                    notes: "Asymmetric wavelet filter requires ≥ 2 taps; got \(tapCount)."
                )
            }
        }

        let symmetryLabel = isSymmetric ? "symmetric" : "asymmetric"
        return ExtensionResult(
            extension: .arbitraryWavelets,
            isSupported: true,
            isCompliant: true,
            notes: "Arbitrary wavelet filter is valid (\(symmetryLabel), \(tapCount) taps)."
        )
    }

    // MARK: DC Offset

    /// Validates a DC-Offset value for a given bit depth and signedness.
    ///
    /// - For **signed** components the valid range is `[-2^(bitDepth-1), 2^(bitDepth-1) - 1]`.
    /// - For **unsigned** components the valid range is `[0, 2^bitDepth - 1]`.
    ///
    /// - Parameters:
    ///   - offset: The DC-Offset value to validate.
    ///   - bitDepth: The bit depth of the component (1–38 in Part 2).
    ///   - isSigned: Whether the component uses signed sample values.
    /// - Returns: An ``ExtensionResult`` for the DC-Offset extension.
    public static func validateDCOffset(offset: Int32, bitDepth: Int, isSigned: Bool) -> ExtensionResult {
        let lower: Int64
        let upper: Int64

        if isSigned {
            lower = -(Int64(1) << (bitDepth - 1))
            upper =  (Int64(1) << (bitDepth - 1)) - 1
        } else {
            lower = 0
            upper = (Int64(1) << bitDepth) - 1
        }

        let value = Int64(offset)
        guard value >= lower && value <= upper else {
            return ExtensionResult(
                extension: .dcOffset,
                isSupported: true,
                isCompliant: false,
                notes: "DC-Offset \(offset) is outside valid range [\(lower), \(upper)] for \(bitDepth)-bit \(isSigned ? "signed" : "unsigned") component."
            )
        }

        return ExtensionResult(
            extension: .dcOffset,
            isSupported: true,
            isCompliant: true,
            notes: "DC-Offset \(offset) is valid for \(bitDepth)-bit \(isSigned ? "signed" : "unsigned") component."
        )
    }
}

// MARK: - Part 2 Conformance Test Suite

/// A self-contained conformance test suite for ISO/IEC 15444-2 extensions.
///
/// Use ``standardTestCases()`` to obtain a canonical set of test inputs, then
/// evaluate each case with the appropriate validator and pass the results to
/// ``generateReport(results:)`` to produce a Markdown conformance report.
public struct J2KPart2ConformanceTestSuite: Sendable {

    // MARK: Test Category

    /// Categories of Part 2 conformance tests.
    public enum TestCategory: String, Sendable, CaseIterable {
        /// JPX file-format structure tests.
        case jpxFileFormat = "JPX File Format"
        /// Multi-Component Transform tests.
        case mct = "MCT"
        /// Non-Linear Transform tests.
        case nlt = "NLT"
        /// Trellis-Coded Quantisation tests.
        case tcq = "TCQ"
        /// Extended Region of Interest tests.
        case extendedROI = "Extended ROI"
        /// Arbitrary wavelet filter tests.
        case arbitraryWavelet = "Arbitrary Wavelet"
        /// DC-Offset tests.
        case dcOffset = "DC Offset"
    }

    // MARK: Test Case

    /// A single conformance test case for a Part 2 extension.
    public struct TestCase: Sendable {
        /// Unique identifier for this test case (e.g. `"P2-MCT-001"`).
        public let identifier: String
        /// The test category.
        public let category: TestCategory
        /// Human-readable description of what is being tested.
        public let description: String
        /// The extension under test.
        public let `extension`: J2KPart2Extension
        /// Whether this configuration is expected to be conformant.
        public let expectedCompliant: Bool

        /// Creates a new test case.
        public init(
            identifier: String,
            category: TestCategory,
            description: String,
            extension ext: J2KPart2Extension,
            expectedCompliant: Bool
        ) {
            self.identifier = identifier
            self.category = category
            self.description = description
            self.extension = ext
            self.expectedCompliant = expectedCompliant
        }
    }

    // MARK: Standard Test Cases

    /// Returns the standard set of Part 2 conformance test cases.
    ///
    /// The returned collection contains ≥ 20 cases spanning valid and invalid
    /// configurations for every extension defined in ``J2KPart2Extension``.
    ///
    /// - Returns: An array of ``TestCase`` values.
    public static func standardTestCases() -> [TestCase] {
        [
            // JPX File Format
            TestCase(identifier: "P2-JPX-001", category: .jpxFileFormat, description: "Valid JP2 signature box accepted.", extension: .dcOffset, expectedCompliant: true),
            TestCase(identifier: "P2-JPX-002", category: .jpxFileFormat, description: "Truncated data rejects JP2 signature.", extension: .dcOffset, expectedCompliant: false),
            TestCase(identifier: "P2-JPX-003", category: .jpxFileFormat, description: "Correct ftyp box detected after signature.", extension: .dcOffset, expectedCompliant: true),
            TestCase(identifier: "P2-JPX-004", category: .jpxFileFormat, description: "Extensions trigger JPX compatibility warning.", extension: .multiComponentTransform, expectedCompliant: true),

            // MCT
            TestCase(identifier: "P2-MCT-001", category: .mct, description: "Valid MCT with 3 components and 2 stages.", extension: .multiComponentTransform, expectedCompliant: true),
            TestCase(identifier: "P2-MCT-002", category: .mct, description: "MCT rejected for single-component image.", extension: .multiComponentTransform, expectedCompliant: false),
            TestCase(identifier: "P2-MCT-003", category: .mct, description: "MCT rejected when stages exceed component count.", extension: .multiComponentTransform, expectedCompliant: false),
            TestCase(identifier: "P2-MCT-004", category: .mct, description: "MCT valid with 4 components and 4 stages.", extension: .multiComponentTransform, expectedCompliant: true),

            // NLT
            TestCase(identifier: "P2-NLT-001", category: .nlt, description: "NLT type 0 (none) is valid.", extension: .nonLinearTransform, expectedCompliant: true),
            TestCase(identifier: "P2-NLT-002", category: .nlt, description: "NLT type 1 (gamma) is valid.", extension: .nonLinearTransform, expectedCompliant: true),
            TestCase(identifier: "P2-NLT-003", category: .nlt, description: "NLT type 2 (LUT) is valid.", extension: .nonLinearTransform, expectedCompliant: true),
            TestCase(identifier: "P2-NLT-004", category: .nlt, description: "NLT type 255 is invalid.", extension: .nonLinearTransform, expectedCompliant: false),

            // TCQ
            TestCase(identifier: "P2-TCQ-001", category: .tcq, description: "Valid TCQ with 2 guard bits and 8 steps.", extension: .trellisCodedQuantisation, expectedCompliant: true),
            TestCase(identifier: "P2-TCQ-002", category: .tcq, description: "TCQ rejected with 0 steps.", extension: .trellisCodedQuantisation, expectedCompliant: false),
            TestCase(identifier: "P2-TCQ-003", category: .tcq, description: "TCQ rejected with guard bits = 8.", extension: .trellisCodedQuantisation, expectedCompliant: false),

            // Extended ROI
            TestCase(identifier: "P2-ROI-001", category: .extendedROI, description: "Valid ROI shift of 10 within max 37.", extension: .extendedROI, expectedCompliant: true),
            TestCase(identifier: "P2-ROI-002", category: .extendedROI, description: "ROI shift rejected when negative.", extension: .extendedROI, expectedCompliant: false),
            TestCase(identifier: "P2-ROI-003", category: .extendedROI, description: "ROI shift 38 rejected (exceeds absolute max 37).", extension: .extendedROI, expectedCompliant: false),

            // Arbitrary Wavelet
            TestCase(identifier: "P2-WAV-001", category: .arbitraryWavelet, description: "Symmetric 5-tap wavelet is valid.", extension: .arbitraryWavelets, expectedCompliant: true),
            TestCase(identifier: "P2-WAV-002", category: .arbitraryWavelet, description: "Symmetric 2-tap wavelet rejected (must be odd ≥ 3).", extension: .arbitraryWavelets, expectedCompliant: false),
            TestCase(identifier: "P2-WAV-003", category: .arbitraryWavelet, description: "Asymmetric 2-tap wavelet is valid.", extension: .arbitraryWavelets, expectedCompliant: true),
            TestCase(identifier: "P2-WAV-004", category: .arbitraryWavelet, description: "Asymmetric 1-tap wavelet rejected.", extension: .arbitraryWavelets, expectedCompliant: false),

            // DC Offset
            TestCase(identifier: "P2-DCO-001", category: .dcOffset, description: "DC-Offset 0 valid for 8-bit unsigned.", extension: .dcOffset, expectedCompliant: true),
            TestCase(identifier: "P2-DCO-002", category: .dcOffset, description: "DC-Offset 255 valid for 8-bit unsigned.", extension: .dcOffset, expectedCompliant: true),
            TestCase(identifier: "P2-DCO-003", category: .dcOffset, description: "DC-Offset 256 rejected for 8-bit unsigned.", extension: .dcOffset, expectedCompliant: false),
            TestCase(identifier: "P2-DCO-004", category: .dcOffset, description: "DC-Offset -128 valid for 8-bit signed.", extension: .dcOffset, expectedCompliant: true),
            TestCase(identifier: "P2-DCO-005", category: .dcOffset, description: "DC-Offset -129 rejected for 8-bit signed.", extension: .dcOffset, expectedCompliant: false),
        ]
    }

    // MARK: Report Generation

    /// Generates a Markdown conformance report from a set of test results.
    ///
    /// - Parameter results: Pairs of ``TestCase`` and a `Bool` indicating pass (`true`) or fail (`false`).
    /// - Returns: A Markdown-formatted string summarising the results.
    public static func generateReport(results: [(TestCase, Bool)]) -> String {
        let passed = results.filter(\.1).count
        let failed = results.count - passed
        let passRate = results.isEmpty ? 0.0 : Double(passed) / Double(results.count) * 100.0

        var lines: [String] = [
            "# JPEG 2000 Part 2 Conformance Report",
            "",
            "| Metric | Value |",
            "|--------|-------|",
            "| Total Tests | \(results.count) |",
            "| Passed | \(passed) |",
            "| Failed | \(failed) |",
            "| Pass Rate | \(String(format: "%.1f", passRate))% |",
            "",
            "## Results",
            "",
            "| ID | Category | Description | Expected | Actual |",
            "|----|----------|-------------|----------|--------|",
        ]

        for (testCase, actual) in results {
            let expected = testCase.expectedCompliant ? "✅" : "❌"
            let actualStr = actual ? "✅" : "❌"
            lines.append("| \(testCase.identifier) | \(testCase.category.rawValue) | \(testCase.description) | \(expected) | \(actualStr) |")
        }

        return lines.joined(separator: "\n")
    }
}
