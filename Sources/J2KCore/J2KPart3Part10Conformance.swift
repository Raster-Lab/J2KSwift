//
// J2KPart3Part10Conformance.swift
// J2KSwift
//
/// # JPEG 2000 Part 3 and Part 10 Conformance
///
/// Week 261–262 deliverable: ISO/IEC 15444-3 (Motion JPEG 2000) and
/// ISO/IEC 15444-10 (JP3D Volumetric) conformance validation.
///
/// Provides MJ2 file-structure validators, JP3D volumetric validators, a
/// cross-part interaction checker, and a complete conformance test suite
/// covering both parts.
///
/// ## Topics
///
/// ### Validators
/// - ``J2KMJ2ConformanceValidator``
/// - ``J2KJP3DConformanceValidator``
/// - ``J2KCrossPartConformanceValidator``
///
/// ### Test Suite
/// - ``J2KPart3Part10ConformanceTestSuite``

import Foundation

// MARK: - MJ2 Conformance Validator

/// Validates Motion JPEG 2000 (MJ2) file-structure compliance per ISO/IEC 15444-3.
///
/// All methods are pure functions and are safe to call from any concurrency domain.
public struct J2KMJ2ConformanceValidator: Sendable {

    // MARK: Result

    /// The result of an MJ2 file-structure validation check.
    public struct MJ2ValidationResult: Sendable {
        /// `true` when no errors were detected.
        public let isValid: Bool
        /// Conformance errors found during validation.
        public let errors: [String]
        /// Non-fatal warnings found during validation.
        public let warnings: [String]
        /// Number of frames reported by or inferred from the structure.
        public let frameCount: Int

        /// Creates a new MJ2 validation result.
        public init(isValid: Bool, errors: [String], warnings: [String], frameCount: Int) {
            self.isValid = isValid
            self.errors = errors
            self.warnings = warnings
            self.frameCount = frameCount
        }
    }

    // MARK: MJ2 Signature

    /// Validates the MJ2/JP2 Signature box at the start of the supplied data.
    ///
    /// MJ2 files re-use the standard JP2 Signature box:
    /// `00 00 00 0C 6A 50 20 20 0D 0A 87 0A` (ISO/IEC 15444-3 §7.1).
    ///
    /// - Parameter data: The raw file bytes.
    /// - Returns: An ``MJ2ValidationResult`` indicating whether the signature is correct.
    public static func validateMJ2Signature(_ data: Data) -> MJ2ValidationResult {
        let required: [UInt8] = [
            0x00, 0x00, 0x00, 0x0C,
            0x6A, 0x50, 0x20, 0x20,
            0x0D, 0x0A, 0x87, 0x0A
        ]

        guard data.count >= required.count else {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["Data too short for MJ2 Signature box: need ≥ \(required.count) bytes, got \(data.count)."],
                warnings: [],
                frameCount: 0
            )
        }

        for (index, byte) in required.enumerated() where data[index] != byte {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["MJ2 Signature box mismatch at byte \(index): expected 0x\(String(byte, radix: 16, uppercase: true)), got 0x\(String(data[index], radix: 16, uppercase: true))."],
                warnings: [],
                frameCount: 0
            )
        }

        return MJ2ValidationResult(isValid: true, errors: [], warnings: [], frameCount: 0)
    }

    // MARK: File Type Box

    /// Validates that the File Type box declares `mjp2` as the file brand.
    ///
    /// The brand field occupies bytes 16–19 of a valid MJ2 file and must equal
    /// `6D 6A 70 32` ("mjp2") per ISO/IEC 15444-3 §7.2.
    ///
    /// - Parameter data: The raw file bytes.
    /// - Returns: An ``MJ2ValidationResult`` indicating whether the mjp2 brand is present.
    public static func validateMJ2FileType(_ data: Data) -> MJ2ValidationResult {
        // ftyp box begins at byte 12; brand begins 8 bytes into that box (4-byte LBox + 4-byte TBox)
        let brandOffset = 20
        let mjp2Brand: [UInt8] = [0x6D, 0x6A, 0x70, 0x32]

        guard data.count >= brandOffset + 4 else {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["Data too short to contain mjp2 brand (need ≥ \(brandOffset + 4) bytes)."],
                warnings: [],
                frameCount: 0
            )
        }

        for (i, byte) in mjp2Brand.enumerated() where data[brandOffset + i] != byte {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["MJ2 File Type box does not declare 'mjp2' brand at offset \(brandOffset)."],
                warnings: [],
                frameCount: 0
            )
        }

        return MJ2ValidationResult(isValid: true, errors: [], warnings: [], frameCount: 0)
    }

    // MARK: Frame Rate

    /// Validates an MJ2 frame rate expressed as a rational number.
    ///
    /// The resulting frame rate must lie in the range `[1/128, 999]` fps.
    ///
    /// - Parameters:
    ///   - numerator: Frame-rate numerator; must be > 0.
    ///   - denominator: Frame-rate denominator; must be > 0.
    /// - Returns: An ``MJ2ValidationResult`` indicating whether the frame rate is valid.
    public static func validateFrameRate(numerator: Int, denominator: Int) -> MJ2ValidationResult {
        guard numerator > 0 else {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["Frame rate numerator must be > 0; got \(numerator)."],
                warnings: [],
                frameCount: 0
            )
        }

        guard denominator > 0 else {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["Frame rate denominator must be > 0; got \(denominator)."],
                warnings: [],
                frameCount: 0
            )
        }

        let fps = Double(numerator) / Double(denominator)
        let minFPS = 1.0 / 128.0
        let maxFPS = 999.0

        guard fps >= minFPS && fps <= maxFPS else {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["Frame rate \(fps) fps is outside the valid range [\(minFPS), \(maxFPS)] fps."],
                warnings: [],
                frameCount: 0
            )
        }

        return MJ2ValidationResult(isValid: true, errors: [], warnings: [], frameCount: 0)
    }

    // MARK: Temporal Metadata

    /// Validates the consistency of MJ2 temporal metadata.
    ///
    /// Checks that `frameCount > 0`, `duration > 0`, and that the ratio
    /// `frameCount / duration` is within 1 % of `frameRate`.
    ///
    /// - Parameters:
    ///   - frameCount: Total number of frames.
    ///   - duration: Total clip duration in seconds.
    ///   - frameRate: Declared frame rate in fps.
    /// - Returns: An ``MJ2ValidationResult`` describing any temporal inconsistencies.
    public static func validateTemporalMetadata(
        frameCount: Int,
        duration: Double,
        frameRate: Double
    ) -> MJ2ValidationResult {
        guard frameCount > 0 else {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["Frame count must be > 0; got \(frameCount)."],
                warnings: [],
                frameCount: frameCount
            )
        }

        guard duration > 0 else {
            return MJ2ValidationResult(
                isValid: false,
                errors: ["Duration must be > 0; got \(duration)."],
                warnings: [],
                frameCount: frameCount
            )
        }

        let impliedRate = Double(frameCount) / duration
        let tolerance = 0.01 * frameRate

        guard abs(impliedRate - frameRate) <= tolerance else {
            return MJ2ValidationResult(
                isValid: false,
                errors: [
                    "Temporal metadata inconsistency: implied frame rate \(impliedRate) fps "
                    + "deviates from declared rate \(frameRate) fps by more than 1 %."
                ],
                warnings: [],
                frameCount: frameCount
            )
        }

        return MJ2ValidationResult(isValid: true, errors: [], warnings: [], frameCount: frameCount)
    }

    // MARK: MJ2 Structure

    /// Validates MJ2 structural parameters.
    ///
    /// - Parameters:
    ///   - frameCount: Number of frames; must be ≥ 1.
    ///   - width: Frame width in pixels; must be ≥ 1.
    ///   - height: Frame height in pixels; must be ≥ 1.
    ///   - bitDepth: Sample bit depth; must be in the range 1–38.
    /// - Returns: An ``MJ2ValidationResult`` indicating structural conformance.
    public static func validateMJ2Structure(
        frameCount: Int,
        width: Int,
        height: Int,
        bitDepth: Int
    ) -> MJ2ValidationResult {
        var errors: [String] = []

        if frameCount < 1 { errors.append("Frame count must be ≥ 1; got \(frameCount).") }
        if width < 1     { errors.append("Frame width must be ≥ 1; got \(width).") }
        if height < 1    { errors.append("Frame height must be ≥ 1; got \(height).") }
        if bitDepth < 1 || bitDepth > 38 { errors.append("Bit depth must be in 1–38; got \(bitDepth).") }

        return MJ2ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: [],
            frameCount: errors.isEmpty ? frameCount : 0
        )
    }
}

// MARK: - JP3D Conformance Validator

/// Validates JP3D volumetric codestream compliance per ISO/IEC 15444-10.
///
/// All methods are pure functions and are safe to call from any concurrency domain.
public struct J2KJP3DConformanceValidator: Sendable {

    // MARK: Result

    /// The result of a JP3D volumetric validation check.
    public struct JP3DValidationResult: Sendable {
        /// `true` when no errors were detected.
        public let isValid: Bool
        /// Conformance errors found during validation.
        public let errors: [String]
        /// Non-fatal warnings found during validation.
        public let warnings: [String]
        /// Total number of voxels implied by the validated parameters.
        public let voxelCount: Int

        /// Creates a new JP3D validation result.
        public init(isValid: Bool, errors: [String], warnings: [String], voxelCount: Int) {
            self.isValid = isValid
            self.errors = errors
            self.warnings = warnings
            self.voxelCount = voxelCount
        }
    }

    // MARK: Volume Extents

    /// Validates volumetric extent parameters.
    ///
    /// All dimensions must be ≥ 1.  A warning is issued for any dimension exceeding 4096.
    ///
    /// - Parameters:
    ///   - width: Volume width in voxels.
    ///   - height: Volume height in voxels.
    ///   - depth: Volume depth in voxels.
    /// - Returns: A ``JP3DValidationResult`` describing any extent violations.
    public static func validateVolumeExtents(width: Int, height: Int, depth: Int) -> JP3DValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        if width < 1  { errors.append("Volume width must be ≥ 1; got \(width).") }
        if height < 1 { errors.append("Volume height must be ≥ 1; got \(height).") }
        if depth < 1  { errors.append("Volume depth must be ≥ 1; got \(depth).") }

        if width > 4096  { warnings.append("Volume width \(width) exceeds recommended maximum of 4096 voxels.") }
        if height > 4096 { warnings.append("Volume height \(height) exceeds recommended maximum of 4096 voxels.") }
        if depth > 4096  { warnings.append("Volume depth \(depth) exceeds recommended maximum of 4096 voxels.") }

        let voxels = errors.isEmpty ? width * height * depth : 0
        return JP3DValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings, voxelCount: voxels)
    }

    // MARK: 3D Wavelet Levels

    /// Validates the 3D discrete wavelet transform decomposition levels.
    ///
    /// Both `xyLevels` and `zLevels` must be in `0…32`.  In addition,
    /// `zLevels ≤ floor(log2(depth)) + 1` to prevent over-decomposition along Z.
    ///
    /// - Parameters:
    ///   - xyLevels: Number of DWT decomposition levels in the XY plane.
    ///   - zLevels: Number of DWT decomposition levels along the Z axis.
    ///   - depth: Volume depth used to cap `zLevels`.
    /// - Returns: A ``JP3DValidationResult`` describing any wavelet-level violations.
    public static func validate3DWaveletLevels(xyLevels: Int, zLevels: Int, depth: Int) -> JP3DValidationResult {
        var errors: [String] = []

        guard (0...32).contains(xyLevels) else {
            errors.append("XY wavelet levels must be in 0–32; got \(xyLevels).")
            return JP3DValidationResult(isValid: false, errors: errors, warnings: [], voxelCount: 0)
        }

        guard (0...32).contains(zLevels) else {
            errors.append("Z wavelet levels must be in 0–32; got \(zLevels).")
            return JP3DValidationResult(isValid: false, errors: errors, warnings: [], voxelCount: 0)
        }

        guard depth >= 1 else {
            errors.append("Volume depth must be ≥ 1 to validate Z wavelet levels.")
            return JP3DValidationResult(isValid: false, errors: errors, warnings: [], voxelCount: 0)
        }

        let maxZLevels = Int(log2(Double(depth))) + 1
        if zLevels > maxZLevels {
            errors.append("Z wavelet levels \(zLevels) exceeds maximum \(maxZLevels) for depth \(depth).")
        }

        return JP3DValidationResult(isValid: errors.isEmpty, errors: errors, warnings: [], voxelCount: 0)
    }

    // MARK: 3D Tiling

    /// Validates a 3D tiling configuration.
    ///
    /// All tile dimensions must be ≥ 1 and must not exceed the corresponding volume dimensions.
    ///
    /// - Parameters:
    ///   - tileWidth: Tile width in voxels.
    ///   - tileHeight: Tile height in voxels.
    ///   - tileDepth: Tile depth in voxels.
    ///   - volumeWidth: Volume width in voxels.
    ///   - volumeHeight: Volume height in voxels.
    ///   - volumeDepth: Volume depth in voxels.
    /// - Returns: A ``JP3DValidationResult`` describing any tiling violations.
    public static func validate3DTilingConfiguration(
        tileWidth: Int, tileHeight: Int, tileDepth: Int,
        volumeWidth: Int, volumeHeight: Int, volumeDepth: Int
    ) -> JP3DValidationResult {
        var errors: [String] = []

        if tileWidth < 1  { errors.append("Tile width must be ≥ 1; got \(tileWidth).") }
        if tileHeight < 1 { errors.append("Tile height must be ≥ 1; got \(tileHeight).") }
        if tileDepth < 1  { errors.append("Tile depth must be ≥ 1; got \(tileDepth).") }

        if tileWidth > volumeWidth   { errors.append("Tile width \(tileWidth) exceeds volume width \(volumeWidth).") }
        if tileHeight > volumeHeight { errors.append("Tile height \(tileHeight) exceeds volume height \(volumeHeight).") }
        if tileDepth > volumeDepth   { errors.append("Tile depth \(tileDepth) exceeds volume depth \(volumeDepth).") }

        return JP3DValidationResult(isValid: errors.isEmpty, errors: errors, warnings: [], voxelCount: 0)
    }

    // MARK: Volumetric Codestream Structure

    /// Performs a lightweight structural validation of a JP3D codestream.
    ///
    /// Checks that:
    /// - The data is at least 6 bytes long.
    /// - The SOC marker (0xFF4F) is present at the start.
    /// - The EOC marker (0xFFD9) is present at the end.
    ///
    /// - Parameter data: The raw JP3D codestream bytes.
    /// - Returns: A ``JP3DValidationResult`` describing any structural violations.
    public static func validateVolumetricCodestreamStructure(_ data: Data) -> JP3DValidationResult {
        var errors: [String] = []

        guard data.count >= 6 else {
            errors.append("Codestream is too short: need ≥ 6 bytes, got \(data.count).")
            return JP3DValidationResult(isValid: false, errors: errors, warnings: [], voxelCount: 0)
        }

        if data[0] != 0xFF || data[1] != 0x4F {
            errors.append("SOC marker (0xFF4F) not found at start of codestream.")
        }

        let lastTwo = data.count - 2
        if data[lastTwo] != 0xFF || data[lastTwo + 1] != 0xD9 {
            errors.append("EOC marker (0xFFD9) not found at end of codestream.")
        }

        return JP3DValidationResult(isValid: errors.isEmpty, errors: errors, warnings: [], voxelCount: 0)
    }
}

// MARK: - Cross-Part Conformance Validator

/// Validates conformance requirements that span multiple JPEG 2000 parts.
///
/// All methods are pure functions and are safe to call from any concurrency domain.
public struct J2KCrossPartConformanceValidator: Sendable {

    // MARK: Result

    /// The result of a cross-part conformance check.
    public struct CrossPartResult: Sendable {
        /// `true` when all cross-part requirements are satisfied.
        public let isValid: Bool
        /// The JPEG 2000 parts involved in this interaction.
        public let parts: [String]
        /// Conformance errors found during validation.
        public let errors: [String]

        /// Creates a new cross-part result.
        public init(isValid: Bool, parts: [String], errors: [String]) {
            self.isValid = isValid
            self.parts = parts
            self.errors = errors
        }
    }

    // MARK: Part 3 ↔ Part 1

    /// Validates the interaction between an MJ2 container (Part 3) and a Part 1 codestream.
    ///
    /// Requires `part1Valid = true` (each frame is a conformant Part 1 codestream)
    /// and `mj2FrameCount ≥ 1`.
    ///
    /// - Parameters:
    ///   - mj2FrameCount: Number of frames in the MJ2 container.
    ///   - part1Valid: Whether the embedded Part 1 codestreams are conformant.
    /// - Returns: A ``CrossPartResult`` describing the interaction conformance.
    public static func validatePart3Part1Interaction(
        mj2FrameCount: Int,
        part1Valid: Bool
    ) -> CrossPartResult {
        var errors: [String] = []

        if !part1Valid {
            errors.append("Embedded Part 1 codestream is not conformant; MJ2 container requires valid Part 1 frames.")
        }

        if mj2FrameCount < 1 {
            errors.append("MJ2 container must contain at least one frame; got \(mj2FrameCount).")
        }

        return CrossPartResult(
            isValid: errors.isEmpty,
            parts: ["Part 1 (Core)", "Part 3 (MJ2)"],
            errors: errors
        )
    }

    // MARK: Part 10 ↔ Part 1

    /// Validates the interaction between a JP3D volume (Part 10) and a Part 1 codestream.
    ///
    /// Both `jp3dVolumeValid` and `part1Valid` must be `true`.
    ///
    /// - Parameters:
    ///   - jp3dVolumeValid: Whether the JP3D volumetric structure is conformant.
    ///   - part1Valid: Whether the underlying Part 1 codestream is conformant.
    /// - Returns: A ``CrossPartResult`` describing the interaction conformance.
    public static func validatePart10Part1Interaction(
        jp3dVolumeValid: Bool,
        part1Valid: Bool
    ) -> CrossPartResult {
        var errors: [String] = []

        if !part1Valid {
            errors.append("Underlying Part 1 codestream is not conformant.")
        }

        if !jp3dVolumeValid {
            errors.append("JP3D volumetric structure is not conformant.")
        }

        return CrossPartResult(
            isValid: errors.isEmpty,
            parts: ["Part 1 (Core)", "Part 10 (JP3D)"],
            errors: errors
        )
    }
}

// MARK: - Part 3 / Part 10 Conformance Test Suite

/// A self-contained conformance test suite for ISO/IEC 15444-3 and ISO/IEC 15444-10.
///
/// Use ``standardTestCases()`` to obtain a canonical set of test inputs, then
/// evaluate each case with the appropriate validator and pass the results to
/// ``generateReport(results:)`` to produce a Markdown conformance report.
public struct J2KPart3Part10ConformanceTestSuite: Sendable {

    // MARK: Test Category

    /// Categories of Part 3 / Part 10 conformance tests.
    public enum TestCategory: String, Sendable, CaseIterable {
        /// MJ2 file-structure tests.
        case mj2Structure = "MJ2 Structure"
        /// MJ2 frame-rate tests.
        case mj2FrameRate = "MJ2 Frame Rate"
        /// MJ2 temporal-metadata tests.
        case mj2Temporal = "MJ2 Temporal"
        /// JP3D volume-extent tests.
        case jp3dVolume = "JP3D Volume"
        /// JP3D wavelet-decomposition tests.
        case jp3dWavelet = "JP3D Wavelet"
        /// JP3D tiling tests.
        case jp3dTiling = "JP3D Tiling"
        /// Cross-part interaction tests.
        case crossPart = "Cross-Part"
    }

    // MARK: Test Case

    /// A single conformance test case for Part 3 or Part 10.
    public struct TestCase: Sendable {
        /// Unique identifier for this test case (e.g. `"P3-STR-001"`).
        public let identifier: String
        /// The test category.
        public let category: TestCategory
        /// Human-readable description of what is being tested.
        public let description: String
        /// Whether this configuration is expected to be valid.
        public let expectedValid: Bool

        /// Creates a new test case.
        public init(identifier: String, category: TestCategory, description: String, expectedValid: Bool) {
            self.identifier = identifier
            self.category = category
            self.description = description
            self.expectedValid = expectedValid
        }
    }

    // MARK: Standard Test Cases

    /// Returns the standard set of Part 3 / Part 10 conformance test cases.
    ///
    /// The returned collection contains ≥ 20 cases spanning valid and invalid
    /// configurations across all ``TestCategory`` values.
    ///
    /// - Returns: An array of ``TestCase`` values.
    public static func standardTestCases() -> [TestCase] {
        [
            // MJ2 Structure
            TestCase(identifier: "P3-STR-001", category: .mj2Structure, description: "Valid MJ2 signature accepted.", expectedValid: true),
            TestCase(identifier: "P3-STR-002", category: .mj2Structure, description: "Truncated data rejects MJ2 signature.", expectedValid: false),
            TestCase(identifier: "P3-STR-003", category: .mj2Structure, description: "mjp2 brand validated in ftyp box.", expectedValid: true),
            TestCase(identifier: "P3-STR-004", category: .mj2Structure, description: "Valid structural parameters accepted.", expectedValid: true),
            TestCase(identifier: "P3-STR-005", category: .mj2Structure, description: "Zero frame count rejected.", expectedValid: false),

            // MJ2 Frame Rate
            TestCase(identifier: "P3-FPS-001", category: .mj2FrameRate, description: "30 fps (30/1) is valid.", expectedValid: true),
            TestCase(identifier: "P3-FPS-002", category: .mj2FrameRate, description: "Zero denominator rejected.", expectedValid: false),
            TestCase(identifier: "P3-FPS-003", category: .mj2FrameRate, description: "Zero numerator rejected.", expectedValid: false),
            TestCase(identifier: "P3-FPS-004", category: .mj2FrameRate, description: "1/128 fps (minimum) accepted.", expectedValid: true),
            TestCase(identifier: "P3-FPS-005", category: .mj2FrameRate, description: "999 fps (maximum) accepted.", expectedValid: true),

            // MJ2 Temporal
            TestCase(identifier: "P3-TMP-001", category: .mj2Temporal, description: "Consistent temporal metadata accepted.", expectedValid: true),
            TestCase(identifier: "P3-TMP-002", category: .mj2Temporal, description: "Zero frame count rejected.", expectedValid: false),
            TestCase(identifier: "P3-TMP-003", category: .mj2Temporal, description: "Zero duration rejected.", expectedValid: false),
            TestCase(identifier: "P3-TMP-004", category: .mj2Temporal, description: "Inconsistent frame rate rejected.", expectedValid: false),

            // JP3D Volume
            TestCase(identifier: "P10-VOL-001", category: .jp3dVolume, description: "Minimum 1×1×1 volume accepted.", expectedValid: true),
            TestCase(identifier: "P10-VOL-002", category: .jp3dVolume, description: "Zero width rejected.", expectedValid: false),
            TestCase(identifier: "P10-VOL-003", category: .jp3dVolume, description: "Large dimension warns but remains valid.", expectedValid: true),

            // JP3D Wavelet
            TestCase(identifier: "P10-WAV-001", category: .jp3dWavelet, description: "Valid XY and Z wavelet levels accepted.", expectedValid: true),
            TestCase(identifier: "P10-WAV-002", category: .jp3dWavelet, description: "Excessive Z levels for depth rejected.", expectedValid: false),

            // JP3D Tiling
            TestCase(identifier: "P10-TIL-001", category: .jp3dTiling, description: "Valid tiling configuration accepted.", expectedValid: true),
            TestCase(identifier: "P10-TIL-002", category: .jp3dTiling, description: "Tile exceeding volume dimension rejected.", expectedValid: false),

            // Cross-Part
            TestCase(identifier: "CP-001", category: .crossPart, description: "Part 3 + Part 1 valid interaction.", expectedValid: true),
            TestCase(identifier: "CP-002", category: .crossPart, description: "Part 3 + Part 1 fails when Part 1 invalid.", expectedValid: false),
            TestCase(identifier: "CP-003", category: .crossPart, description: "Part 10 + Part 1 valid interaction.", expectedValid: true),
            TestCase(identifier: "CP-004", category: .crossPart, description: "Part 10 + Part 1 fails when JP3D invalid.", expectedValid: false),
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
            "# JPEG 2000 Part 3 / Part 10 Conformance Report",
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
            let expected = testCase.expectedValid ? "✅" : "❌"
            let actualStr = actual ? "✅" : "❌"
            lines.append("| \(testCase.identifier) | \(testCase.category.rawValue) | \(testCase.description) | \(expected) | \(actualStr) |")
        }

        return lines.joined(separator: "\n")
    }
}
