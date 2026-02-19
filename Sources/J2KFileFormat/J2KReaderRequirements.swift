/// # J2KReaderRequirements
///
/// Reader Requirements box (rreq) and Part 2 feature signaling
/// per ISO/IEC 15444-2 Annex I.
///
/// This module provides:
/// - ``J2KStandardFeature``: Enumeration of standard JPEG 2000 features
/// - ``J2KReaderRequirementsBox``: The rreq box for signaling reader requirements
/// - ``J2KDecoderCapability``: Decoder capability negotiation
/// - ``J2KFeatureCompatibility``: Feature compatibility validation

import Foundation
import J2KCore
import J2KCodec

// MARK: - Standard Feature Enumeration

/// Standard JPEG 2000 features defined in ISO/IEC 15444-2.
///
/// Each feature has a numeric identifier assigned by the standard. Features
/// with values >= 18 are Part 2 extensions that require a JPX-aware reader.
///
/// ## Box Structure
///
/// Standard features are referenced by their 2-byte numeric value (SF field)
/// in the reader requirements box. Each feature is associated with a bit mask
/// that indicates its position in the fully-understand and display masks.
///
/// Example:
/// ```swift
/// let feature = J2KStandardFeature.multiComponentTransform
/// print(feature.featureName)    // "Multi-Component Transform (Part 2)"
/// print(feature.isPart2Feature) // true
/// ```
public enum J2KStandardFeature: UInt16, Sendable, Equatable, Hashable, CaseIterable {
    /// No extensions required (Part 1 only).
    case noExtensions = 1

    /// Multiple composition layers.
    case multipleCompositionLayers = 2

    /// Needs a JPX-aware reader.
    case needsJPXReader = 5

    /// Fragmented codestream in multiple fragment table boxes.
    case fragmentedCodestream = 8

    /// Compositing needed to render the image.
    case compositing = 12

    /// Animation support for time-based rendering.
    case animation = 16

    /// Multi-component transform (Part 2).
    case multiComponentTransform = 18

    /// Non-linear point transform (Part 2).
    case nonLinearTransform = 20

    /// Arbitrary wavelet decomposition (Part 2).
    case arbitraryWavelets = 21

    /// Trellis coded quantization (Part 2).
    case trellisQuantization = 22

    /// Extended region of interest (Part 2).
    case extendedROI = 24

    /// Extended precision for coefficients (Part 2).
    case extendedPrecision = 25

    /// DC offset signaling (Part 2).
    case dcOffset = 26

    /// Visual masking model (Part 2).
    case visualMasking = 28

    /// Perceptual encoding optimizations (Part 2).
    case perceptualEncoding = 29

    /// A human-readable name describing the feature.
    public var featureName: String {
        switch self {
        case .noExtensions:
            return "No Extensions (Part 1 only)"
        case .multipleCompositionLayers:
            return "Multiple Composition Layers"
        case .needsJPXReader:
            return "Needs JPX-Aware Reader"
        case .fragmentedCodestream:
            return "Fragmented Codestream"
        case .compositing:
            return "Compositing"
        case .animation:
            return "Animation"
        case .multiComponentTransform:
            return "Multi-Component Transform (Part 2)"
        case .nonLinearTransform:
            return "Non-Linear Point Transform (Part 2)"
        case .arbitraryWavelets:
            return "Arbitrary Wavelets (Part 2)"
        case .trellisQuantization:
            return "Trellis Coded Quantization (Part 2)"
        case .extendedROI:
            return "Extended ROI (Part 2)"
        case .extendedPrecision:
            return "Extended Precision (Part 2)"
        case .dcOffset:
            return "DC Offset (Part 2)"
        case .visualMasking:
            return "Visual Masking (Part 2)"
        case .perceptualEncoding:
            return "Perceptual Encoding (Part 2)"
        }
    }

    /// Whether this feature is a Part 2 extension (value >= 18).
    public var isPart2Feature: Bool {
        rawValue >= 18
    }
}

// MARK: - Reader Requirements Box

/// The reader requirements box (rreq).
///
/// This box signals which features a reader must support to fully understand
/// or properly display a JPX file. It is defined in ISO/IEC 15444-2 Annex I.7.2.
///
/// ## Box Structure
///
/// - Type: 'rreq' (0x72726571)
/// - Length: Variable
/// - Content:
///   - ML (1 byte): Mask length in bytes (1, 2, 4, or 8)
///   - FUAM (ML bytes): Fully-understand-aspects mask
///   - DCM (ML bytes): Display-correctly mask
///   - NSF (2 bytes): Number of standard features
///   - For each standard feature:
///     - SF (2 bytes): Standard feature value
///     - SM (ML bytes): Standard feature mask
///   - NVF (2 bytes): Number of vendor features
///   - For each vendor feature:
///     - VF (16 bytes): Vendor feature UUID
///     - VM (ML bytes): Vendor feature mask
///
/// Example:
/// ```swift
/// var box = J2KReaderRequirementsBox(
///     maskLength: 1,
///     fullyUnderstandMask: 0xFF,
///     displayMask: 0x00,
///     standardFeatures: [
///         .init(feature: .noExtensions, mask: 0x80)
///     ],
///     vendorFeatures: []
/// )
/// let data = try box.write()
/// ```
public struct J2KReaderRequirementsBox: J2KBox {
    /// An entry describing a standard feature and its associated bit mask.
    public struct StandardFeatureEntry: Sendable, Equatable {
        /// The standard feature identifier.
        public var feature: J2KStandardFeature

        /// The bit mask for this feature in the fully-understand and display masks.
        public var mask: UInt64

        /// Creates a new standard feature entry.
        ///
        /// - Parameters:
        ///   - feature: The standard feature identifier.
        ///   - mask: The bit mask for this feature.
        public init(feature: J2KStandardFeature, mask: UInt64) {
            self.feature = feature
            self.mask = mask
        }
    }

    /// An entry describing a vendor-specific feature and its associated bit mask.
    public struct VendorFeatureEntry: Sendable, Equatable {
        /// The 16-byte vendor UUID stored as two UInt64 values for Sendable compliance.
        public var uuid: (UInt64, UInt64)

        /// The bit mask for this vendor feature.
        public var mask: UInt64

        /// Creates a new vendor feature entry.
        ///
        /// - Parameters:
        ///   - uuid: The vendor UUID as two big-endian UInt64 values.
        ///   - mask: The bit mask for this vendor feature.
        public init(uuid: (UInt64, UInt64), mask: UInt64) {
            self.uuid = uuid
            self.mask = mask
        }

        public static func == (lhs: VendorFeatureEntry, rhs: VendorFeatureEntry) -> Bool {
            lhs.uuid.0 == rhs.uuid.0 && lhs.uuid.1 == rhs.uuid.1 && lhs.mask == rhs.mask
        }
    }

    public var boxType: J2KBoxType {
        .rreq
    }

    /// Length of each mask field in bytes (1, 2, 4, or 8).
    public var maskLength: UInt8

    /// Mask of features that must be understood for full file comprehension.
    public var fullyUnderstandMask: UInt64

    /// Mask of features required for correct display.
    public var displayMask: UInt64

    /// List of standard features referenced in this box.
    public var standardFeatures: [StandardFeatureEntry]

    /// List of vendor-specific features referenced in this box.
    public var vendorFeatures: [VendorFeatureEntry]

    /// Creates a new reader requirements box.
    ///
    /// - Parameters:
    ///   - maskLength: Length of each mask in bytes (1, 2, 4, or 8).
    ///   - fullyUnderstandMask: Mask for features needed to fully understand the file.
    ///   - displayMask: Mask for features needed for correct display.
    ///   - standardFeatures: Standard feature entries.
    ///   - vendorFeatures: Vendor feature entries.
    public init(
        maskLength: UInt8 = 1,
        fullyUnderstandMask: UInt64 = 0,
        displayMask: UInt64 = 0,
        standardFeatures: [StandardFeatureEntry] = [],
        vendorFeatures: [VendorFeatureEntry] = []
    ) {
        self.maskLength = maskLength
        self.fullyUnderstandMask = fullyUnderstandMask
        self.displayMask = displayMask
        self.standardFeatures = standardFeatures
        self.vendorFeatures = vendorFeatures
    }

    public func write() throws -> Data {
        guard maskLength == 1 || maskLength == 2 || maskLength == 4 || maskLength == 8 else {
            throw J2KError.fileFormatError(
                "Invalid mask length: \(maskLength), must be 1, 2, 4, or 8"
            )
        }

        let ml = Int(maskLength)
        let capacity = 1 + ml * 2 + 2 + standardFeatures.count * (2 + ml) +
                        2 + vendorFeatures.count * (16 + ml)
        var data = Data(capacity: capacity)

        // ML (1 byte)
        data.append(maskLength)

        // FUAM (ML bytes)
        writeMask(fullyUnderstandMask, length: ml, to: &data)

        // DCM (ML bytes)
        writeMask(displayMask, length: ml, to: &data)

        // NSF (2 bytes)
        let nsf = UInt16(standardFeatures.count)
        data.append(UInt8((nsf >> 8) & 0xFF))
        data.append(UInt8(nsf & 0xFF))

        // Standard feature entries
        for entry in standardFeatures {
            // SF (2 bytes)
            let sf = entry.feature.rawValue
            data.append(UInt8((sf >> 8) & 0xFF))
            data.append(UInt8(sf & 0xFF))

            // SM (ML bytes)
            writeMask(entry.mask, length: ml, to: &data)
        }

        // NVF (2 bytes)
        let nvf = UInt16(vendorFeatures.count)
        data.append(UInt8((nvf >> 8) & 0xFF))
        data.append(UInt8(nvf & 0xFF))

        // Vendor feature entries
        for entry in vendorFeatures {
            // VF (16 bytes) - UUID as two big-endian UInt64s
            writeUInt64(entry.uuid.0, to: &data)
            writeUInt64(entry.uuid.1, to: &data)

            // VM (ML bytes)
            writeMask(entry.mask, length: ml, to: &data)
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 1 else {
            throw J2KError.fileFormatError("Reader requirements box is empty")
        }

        var offset = 0

        // ML (1 byte)
        maskLength = data[offset]
        offset += 1
        guard maskLength == 1 || maskLength == 2 || maskLength == 4 || maskLength == 8 else {
            throw J2KError.fileFormatError(
                "Invalid mask length: \(maskLength), must be 1, 2, 4, or 8"
            )
        }
        let ml = Int(maskLength)

        // FUAM (ML bytes)
        guard offset + ml <= data.count else {
            throw J2KError.fileFormatError("Insufficient data for fully-understand mask")
        }
        fullyUnderstandMask = readMask(from: data, at: offset, length: ml)
        offset += ml

        // DCM (ML bytes)
        guard offset + ml <= data.count else {
            throw J2KError.fileFormatError("Insufficient data for display mask")
        }
        displayMask = readMask(from: data, at: offset, length: ml)
        offset += ml

        // NSF (2 bytes)
        guard offset + 2 <= data.count else {
            throw J2KError.fileFormatError("Insufficient data for standard feature count")
        }
        let nsf = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2

        // Standard feature entries
        standardFeatures = []
        standardFeatures.reserveCapacity(Int(nsf))
        for i in 0..<Int(nsf) {
            guard offset + 2 + ml <= data.count else {
                throw J2KError.fileFormatError(
                    "Insufficient data for standard feature entry \(i)"
                )
            }

            let sfValue = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2

            guard let feature = J2KStandardFeature(rawValue: sfValue) else {
                throw J2KError.fileFormatError(
                    "Unknown standard feature value: \(sfValue)"
                )
            }

            let mask = readMask(from: data, at: offset, length: ml)
            offset += ml

            standardFeatures.append(StandardFeatureEntry(feature: feature, mask: mask))
        }

        // NVF (2 bytes)
        guard offset + 2 <= data.count else {
            throw J2KError.fileFormatError("Insufficient data for vendor feature count")
        }
        let nvf = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2

        // Vendor feature entries
        vendorFeatures = []
        vendorFeatures.reserveCapacity(Int(nvf))
        for i in 0..<Int(nvf) {
            guard offset + 16 + ml <= data.count else {
                throw J2KError.fileFormatError(
                    "Insufficient data for vendor feature entry \(i)"
                )
            }

            let uuidHigh = readUInt64(from: data, at: offset)
            offset += 8
            let uuidLow = readUInt64(from: data, at: offset)
            offset += 8

            let mask = readMask(from: data, at: offset, length: ml)
            offset += ml

            vendorFeatures.append(VendorFeatureEntry(uuid: (uuidHigh, uuidLow), mask: mask))
        }
    }

    // MARK: - Mask Read/Write Helpers

    /// Writes a mask value in big-endian byte order with the given byte length.
    private func writeMask(_ value: UInt64, length: Int, to data: inout Data) {
        let shift = (length - 1) * 8
        for i in 0..<length {
            data.append(UInt8((value >> (shift - i * 8)) & 0xFF))
        }
    }

    /// Reads a mask value in big-endian byte order with the given byte length.
    private func readMask(from data: Data, at offset: Int, length: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<length {
            value = (value << 8) | UInt64(data[offset + i])
        }
        return value
    }

    /// Writes a UInt64 in big-endian byte order.
    private func writeUInt64(_ value: UInt64, to data: inout Data) {
        for i in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((value >> i) & 0xFF))
        }
    }

    /// Reads a UInt64 in big-endian byte order.
    private func readUInt64(from data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(data[offset + i])
        }
        return value
    }
}

// MARK: - Decoder Capability Negotiation

/// Decoder capability negotiation for checking compatibility with reader requirements.
///
/// Use this type to determine whether a decoder implementation supports
/// the features required by a particular JPX file before attempting to
/// decode it.
///
/// ## Box Structure
///
/// This type does not represent a box itself but works in conjunction with
/// ``J2KReaderRequirementsBox`` to evaluate decoder compatibility.
///
/// Example:
/// ```swift
/// let decoder = J2KDecoderCapability.part1Decoder()
/// let result = decoder.validate(requirements)
/// switch result {
/// case .compatible:
///     print("File is fully supported")
/// case .partiallyCompatible(let missing):
///     print("Missing features: \(missing.map(\.featureName))")
/// case .incompatible(let missing):
///     print("Cannot decode: \(missing.map(\.featureName))")
/// }
/// ```
public struct J2KDecoderCapability: Sendable {
    /// Result of validating decoder capabilities against file requirements.
    public enum ValidationResult: Sendable, Equatable {
        /// The decoder supports all required features.
        case compatible

        /// The decoder supports some but not all features.
        case partiallyCompatible(missing: [J2KStandardFeature])

        /// The decoder cannot handle this file.
        case incompatible(missing: [J2KStandardFeature])
    }

    /// The set of standard features this decoder supports.
    public var supportedFeatures: Set<J2KStandardFeature>

    /// The set of vendor feature UUIDs this decoder supports (as hex strings).
    public var supportedVendorFeatureUUIDs: Set<String>

    /// Creates a decoder capability description.
    ///
    /// - Parameters:
    ///   - supportedFeatures: Standard features the decoder supports.
    ///   - supportedVendorFeatureUUIDs: Vendor feature UUIDs supported (as hex strings).
    public init(
        supportedFeatures: Set<J2KStandardFeature>,
        supportedVendorFeatureUUIDs: Set<String> = []
    ) {
        self.supportedFeatures = supportedFeatures
        self.supportedVendorFeatureUUIDs = supportedVendorFeatureUUIDs
    }

    /// Returns `true` if the decoder supports all features in the fully-understand mask.
    ///
    /// - Parameter requirements: The reader requirements box to check against.
    /// - Returns: Whether this decoder can fully understand the file.
    public func canFullyUnderstand(_ requirements: J2KReaderRequirementsBox) -> Bool {
        let needed = featuresInMask(requirements.fullyUnderstandMask, from: requirements)
        return needed.allSatisfy { supportedFeatures.contains($0) }
    }

    /// Returns `true` if the decoder supports all features in the display mask.
    ///
    /// - Parameter requirements: The reader requirements box to check against.
    /// - Returns: Whether this decoder can correctly display the file.
    public func canDisplay(_ requirements: J2KReaderRequirementsBox) -> Bool {
        let needed = featuresInMask(requirements.displayMask, from: requirements)
        return needed.allSatisfy { supportedFeatures.contains($0) }
    }

    /// Returns the standard features required by the box that this decoder does not support.
    ///
    /// - Parameter requirements: The reader requirements box to check against.
    /// - Returns: An array of unsupported features.
    public func missingFeatures(_ requirements: J2KReaderRequirementsBox) -> [J2KStandardFeature] {
        let needed = featuresInMask(requirements.fullyUnderstandMask, from: requirements)
        return needed.filter { !supportedFeatures.contains($0) }
    }

    /// Validates decoder capabilities against the given requirements.
    ///
    /// - Parameter requirements: The reader requirements box to validate against.
    /// - Returns: A ``ValidationResult`` describing the compatibility level.
    public func validate(_ requirements: J2KReaderRequirementsBox) -> ValidationResult {
        let missing = missingFeatures(requirements)
        if missing.isEmpty {
            return .compatible
        }
        let displayMissing = featuresInMask(requirements.displayMask, from: requirements)
            .filter { !supportedFeatures.contains($0) }
        if displayMissing.isEmpty {
            return .partiallyCompatible(missing: missing)
        }
        return .incompatible(missing: missing)
    }

    /// Creates a Part 1–only decoder capability.
    ///
    /// - Returns: A decoder supporting only baseline JPEG 2000 features.
    public static func part1Decoder() -> J2KDecoderCapability {
        J2KDecoderCapability(supportedFeatures: [.noExtensions])
    }

    /// Creates a decoder capability supporting all Part 2 features.
    ///
    /// - Returns: A decoder supporting every standard feature.
    public static func part2Decoder() -> J2KDecoderCapability {
        J2KDecoderCapability(supportedFeatures: Set(J2KStandardFeature.allCases))
    }

    // MARK: - Private Helpers

    /// Returns the features whose masks have bits set in the given combined mask.
    private func featuresInMask(
        _ mask: UInt64,
        from requirements: J2KReaderRequirementsBox
    ) -> [J2KStandardFeature] {
        requirements.standardFeatures
            .filter { ($0.mask & mask) != 0 }
            .map(\.feature)
    }
}

// MARK: - Feature Compatibility Validation

/// Validates compatibility between JPEG 2000 Part 2 features.
///
/// Use this type to check whether a set of features can be combined
/// and to discover dependencies between features.
///
/// ## Box Structure
///
/// This type does not represent a box. It provides static utilities for
/// building and validating ``J2KReaderRequirementsBox`` instances.
///
/// Example:
/// ```swift
/// let features: Set<J2KStandardFeature> = [.multiComponentTransform, .arbitraryWavelets]
/// let issues = J2KFeatureCompatibility.validateFeatureCombination(features)
/// for issue in issues {
///     print("\(issue.severity): \(issue.issue)")
/// }
/// ```
public struct J2KFeatureCompatibility: Sendable {
    /// Severity level for a compatibility issue.
    public enum Severity: Sendable, Equatable {
        /// A potential problem that may degrade results.
        case warning

        /// A definite problem that will cause errors.
        case error
    }

    /// A compatibility issue discovered during validation.
    public struct CompatibilityIssue: Sendable {
        /// The feature that triggered this issue.
        public var feature: J2KStandardFeature

        /// A human-readable description of the issue.
        public var issue: String

        /// The severity of this issue.
        public var severity: Severity

        /// Creates a compatibility issue.
        ///
        /// - Parameters:
        ///   - feature: The feature that triggered this issue.
        ///   - issue: A description of the issue.
        ///   - severity: The severity level.
        public init(feature: J2KStandardFeature, issue: String, severity: Severity) {
            self.feature = feature
            self.issue = issue
            self.severity = severity
        }
    }

    /// Validates a set of features for known incompatible combinations.
    ///
    /// - Parameter features: The features to validate.
    /// - Returns: An array of compatibility issues, empty if no problems are found.
    public static func validateFeatureCombination(
        _ features: Set<J2KStandardFeature>
    ) -> [CompatibilityIssue] {
        var issues: [CompatibilityIssue] = []

        // Part 2 features require a JPX reader
        let hasPart2 = features.contains(where: { $0.isPart2Feature })
        if hasPart2 && !features.contains(.needsJPXReader) {
            issues.append(CompatibilityIssue(
                feature: .needsJPXReader,
                issue: "Part 2 features present but needsJPXReader is not set",
                severity: .warning
            ))
        }

        // noExtensions is contradictory with any extension feature
        if features.contains(.noExtensions) && features.count > 1 {
            issues.append(CompatibilityIssue(
                feature: .noExtensions,
                issue: "noExtensions is set alongside other features",
                severity: .error
            ))
        }

        // Visual masking and perceptual encoding are typically used together
        if features.contains(.visualMasking) && !features.contains(.perceptualEncoding) {
            issues.append(CompatibilityIssue(
                feature: .visualMasking,
                issue: "Visual masking is usually paired with perceptual encoding",
                severity: .warning
            ))
        }

        // Check dependency requirements
        for feature in features {
            let deps = requiredDependencies(for: feature)
            for dep in deps where !features.contains(dep) {
                issues.append(CompatibilityIssue(
                    feature: feature,
                    issue: "\(feature.featureName) requires \(dep.featureName)",
                    severity: .error
                ))
            }
        }

        return issues
    }

    /// Returns the set of features that the given feature depends on.
    ///
    /// - Parameter feature: The feature to query.
    /// - Returns: A set of features that must also be present.
    public static func requiredDependencies(
        for feature: J2KStandardFeature
    ) -> Set<J2KStandardFeature> {
        switch feature {
        case .multiComponentTransform, .nonLinearTransform, .arbitraryWavelets,
             .trellisQuantization, .extendedROI, .extendedPrecision,
             .dcOffset, .visualMasking, .perceptualEncoding:
            return [.needsJPXReader]
        case .compositing:
            return [.multipleCompositionLayers]
        case .animation:
            return [.multipleCompositionLayers]
        case .noExtensions, .multipleCompositionLayers, .needsJPXReader,
             .fragmentedCodestream:
            return []
        }
    }

    /// Builds a reader requirements box for the given set of features.
    ///
    /// Each feature is assigned a unique bit in the masks. All features are
    /// placed in the fully-understand mask; Part 2 features are also placed
    /// in the display mask.
    ///
    /// - Parameter features: The features to include.
    /// - Returns: A configured ``J2KReaderRequirementsBox``.
    public static func suggestedReaderRequirements(
        for features: Set<J2KStandardFeature>
    ) -> J2KReaderRequirementsBox {
        let sorted = features.sorted { $0.rawValue < $1.rawValue }

        // Choose mask length based on number of features
        let ml: UInt8
        if sorted.count <= 8 {
            ml = 1
        } else if sorted.count <= 16 {
            ml = 2
        } else if sorted.count <= 32 {
            ml = 4
        } else {
            ml = 8
        }

        let maxBits = Int(ml) * 8
        var fuam: UInt64 = 0
        var dcm: UInt64 = 0
        var entries: [J2KReaderRequirementsBox.StandardFeatureEntry] = []

        for (index, feature) in sorted.enumerated() {
            let bitPosition = maxBits - 1 - index
            let mask: UInt64 = bitPosition >= 0 ? (1 << bitPosition) : 0

            fuam |= mask

            if feature.isPart2Feature {
                dcm |= mask
            }

            entries.append(J2KReaderRequirementsBox.StandardFeatureEntry(
                feature: feature,
                mask: mask
            ))
        }

        return J2KReaderRequirementsBox(
            maskLength: ml,
            fullyUnderstandMask: fuam,
            displayMask: dcm,
            standardFeatures: entries,
            vendorFeatures: []
        )
    }
}
