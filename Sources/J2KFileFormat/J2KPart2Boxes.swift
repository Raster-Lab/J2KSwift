//
// J2KPart2Boxes.swift
// J2KSwift
//
// J2KPart2Boxes.swift
// Part 2 metadata box implementations for ISO/IEC 15444-2 (JPX extended file format)
//
// Copyright (c) 2024 J2KSwift contributors
// Licensed under the MIT License

import Foundation
import J2KCore
import J2KCodec

// MARK: - Part 2 Extended Box Types (ISO/IEC 15444-2)

extension J2KBoxType {
    /// Intellectual property rights box ('jp2i').
    public static let jp2i = J2KBoxType(string: "jp2i")

    /// Label box ('lbl ') — human-readable label.
    public static let lbl = J2KBoxType(string: "lbl ")

    /// Association box ('asoc') — groups related boxes.
    public static let asoc = J2KBoxType(string: "asoc")

    /// Cross-reference box ('cref') — references to external data.
    public static let cref = J2KBoxType(string: "cref")

    /// Number list box ('nlst') — list of numbered associations.
    public static let nlst = J2KBoxType(string: "nlst")

    /// Data entry URL box ('url ') — external reference URL.
    public static let url = J2KBoxType(string: "url ")

    /// Digital signature box ('dsig') — digital signatures.
    public static let dsig = J2KBoxType(string: "dsig")

    /// ROI description box ('roid') — region of interest description.
    public static let roid = J2KBoxType(string: "roid")
}

// MARK: - J2KIPRBox

/// Intellectual property rights box.
///
/// Contains arbitrary binary data representing intellectual property rights
/// information associated with the file. The content is opaque and its
/// interpretation depends on the rights management system in use.
///
/// ## Box Structure
///
/// - Type: 'jp2i' (0x6A703269)
/// - Length: Variable (8 + N bytes)
/// - Content:
///   - IPR data (N bytes): Arbitrary binary rights data
///
/// Example:
/// ```swift
/// let ipr = J2KIPRBox(data: myIPRData)
/// let encoded = try ipr.write()
/// ```
public struct J2KIPRBox: J2KBox, Sendable {
    /// The raw intellectual property rights data.
    public var data: Data

    public var boxType: J2KBoxType { .jp2i }

    /// Creates a new intellectual property rights box.
    ///
    /// - Parameter data: The raw IPR data.
    public init(data: Data = Data()) {
        self.data = data
    }

    public func write() throws -> Data {
        data
    }

    public mutating func read(from data: Data) throws {
        self.data = data
    }
}

// MARK: - J2KLabelBox

/// Label box — human-readable text label.
///
/// Contains a UTF-8 encoded string used to provide a human-readable label
/// for associated content. Label boxes are typically placed inside an
/// association box to name a group of related boxes.
///
/// ## Box Structure
///
/// - Type: 'lbl ' (0x6C626C20)
/// - Length: Variable (8 + N bytes)
/// - Content:
///   - Label string (N bytes): UTF-8 encoded text
///
/// Example:
/// ```swift
/// let label = try J2KLabelBox(label: "Layer 0 – Background")
/// let data = try label.write()
/// ```
public struct J2KLabelBox: J2KBox, Sendable {
    /// The UTF-8 text label.
    public var label: String

    public var boxType: J2KBoxType { .lbl }

    /// Creates a new label box.
    ///
    /// - Parameter label: The human-readable label string.
    /// - Throws: ``J2KError/fileFormatError(_:)`` if the string cannot be
    ///   encoded as UTF-8.
    public init(label: String) throws {
        guard label.data(using: .utf8) != nil else {
            throw J2KError.fileFormatError("Label string cannot be encoded as UTF-8")
        }
        self.label = label
    }

    public func write() throws -> Data {
        guard let data = label.data(using: .utf8) else {
            throw J2KError.fileFormatError("Failed to encode label as UTF-8")
        }
        return data
    }

    public mutating func read(from data: Data) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw J2KError.fileFormatError("Label box data is not valid UTF-8")
        }
        self.label = string
    }
}

// MARK: - J2KNumberListBox

/// Number list box — associates numbered entities with a parent.
///
/// Contains a list of associations between entity types (codestreams,
/// compositing layers, or rendered results) and their indices. This box
/// is used inside an association box to identify which entities the
/// associated metadata applies to.
///
/// ## Box Structure
///
/// - Type: 'nlst' (0x6E6C7374)
/// - Length: Variable (8 + N × 6 bytes)
/// - Content:
///   - For each association (6 bytes):
///     - Entity type (2 bytes): 0 = codestream, 1 = compositing layer,
///       2 = rendered result
///     - Entity index (4 bytes): Zero-based index of the entity
///
/// Example:
/// ```swift
/// let associations = [
///     J2KNumberListBox.Association(entityType: .codestream, entityIndex: 0),
///     J2KNumberListBox.Association(entityType: .compositingLayer, entityIndex: 1)
/// ]
/// let box = J2KNumberListBox(associations: associations)
/// let data = try box.write()
/// ```
public struct J2KNumberListBox: J2KBox, Sendable {
    /// Type of entity referenced by an association.
    public enum EntityType: UInt16, Sendable {
        /// A codestream within the file.
        case codestream = 0
        /// A compositing layer.
        case compositingLayer = 1
        /// A rendered result.
        case rendered = 2
    }

    /// A single numbered association.
    public struct Association: Sendable, Equatable {
        /// The type of entity referenced.
        public var entityType: EntityType
        /// The zero-based index of the entity.
        public var entityIndex: UInt32

        /// Creates a new association.
        ///
        /// - Parameters:
        ///   - entityType: The entity type.
        ///   - entityIndex: The zero-based entity index.
        public init(entityType: EntityType, entityIndex: UInt32) {
            self.entityType = entityType
            self.entityIndex = entityIndex
        }
    }

    /// The list of numbered associations.
    public var associations: [Association]

    public var boxType: J2KBoxType { .nlst }

    /// Creates a new number list box.
    ///
    /// - Parameter associations: The list of entity associations.
    public init(associations: [Association] = []) {
        self.associations = associations
    }

    public func write() throws -> Data {
        var data = Data(capacity: associations.count * 6)

        for assoc in associations {
            // Entity type (2 bytes, big-endian)
            let t = assoc.entityType.rawValue
            data.append(UInt8((t >> 8) & 0xFF))
            data.append(UInt8(t & 0xFF))

            // Entity index (4 bytes, big-endian)
            let idx = assoc.entityIndex
            data.append(UInt8((idx >> 24) & 0xFF))
            data.append(UInt8((idx >> 16) & 0xFF))
            data.append(UInt8((idx >> 8) & 0xFF))
            data.append(UInt8(idx & 0xFF))
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count.isMultiple(of: 6) else {
            throw J2KError.fileFormatError(
                "Number list box size \(data.count) is not a multiple of 6")
        }

        let count = data.count / 6
        var result: [Association] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            let offset = i * 6

            let rawType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            guard let entityType = EntityType(rawValue: rawType) else {
                throw J2KError.fileFormatError(
                    "Invalid entity type \(rawType) at association index \(i)")
            }

            let entityIndex = UInt32(data[offset + 2]) << 24 |
                              UInt32(data[offset + 3]) << 16 |
                              UInt32(data[offset + 4]) << 8 |
                              UInt32(data[offset + 5])

            result.append(Association(entityType: entityType, entityIndex: entityIndex))
        }

        self.associations = result
    }
}

// MARK: - J2KAssociationBox

/// Association box — groups related boxes together.
///
/// A super-box that associates metadata boxes with the entities they describe.
/// An association box typically contains an optional label box followed by one
/// or more content boxes such as XML metadata, number lists, or nested
/// associations.
///
/// ## Box Structure
///
/// - Type: 'asoc' (0x61736F63)
/// - Length: Variable
/// - Content: One or more child boxes
///   - Optional 'lbl ' box: Human-readable label for this association
///   - Child boxes: Any combination of 'xml ', 'lbl ', 'nlst', or other boxes
///
/// Example:
/// ```swift
/// let label = try J2KLabelBox(label: "GeoTIFF Metadata")
/// let xml = try J2KXMLBox(xmlString: "<gml>...</gml>")
/// let box = J2KAssociationBox(
///     label: label,
///     children: [.xmlContent(xml)]
/// )
/// let data = try box.write()
/// ```
public struct J2KAssociationBox: J2KBox, Sendable {
    /// The type of content held by an association child.
    public enum AssociatedContent: Sendable {
        /// XML metadata content.
        case xmlContent(J2KXMLBox)
        /// A nested label.
        case labelContent(J2KLabelBox)
        /// A number list associating entities.
        case numberList(J2KNumberListBox)
        /// Raw box content whose type is not specifically handled.
        case rawContent(J2KBoxType, Data)
    }

    /// An optional label for this association group.
    public var label: J2KLabelBox?

    /// The child content boxes.
    public var children: [AssociatedContent]

    public var boxType: J2KBoxType { .asoc }

    /// Creates a new association box.
    ///
    /// - Parameters:
    ///   - label: An optional label for the association.
    ///   - children: The child content boxes.
    public init(label: J2KLabelBox? = nil, children: [AssociatedContent] = []) {
        self.label = label
        self.children = children
    }

    public func write() throws -> Data {
        var writer = J2KBoxWriter()

        // Write label first if present
        if let label = label {
            try writer.writeBox(label)
        }

        // Write each child box
        for child in children {
            switch child {
            case .xmlContent(let box):
                try writer.writeBox(box)
            case .labelContent(let box):
                try writer.writeBox(box)
            case .numberList(let box):
                try writer.writeBox(box)
            case .rawContent(let type, let content):
                try writer.writeRawBox(type: type, content: content)
            }
        }

        return writer.data
    }

    public mutating func read(from data: Data) throws {
        var reader = J2KBoxReader(data: data)
        var parsedChildren: [AssociatedContent] = []
        var parsedLabel: J2KLabelBox?

        while let boxInfo = try reader.readNextBox() {
            let content = reader.extractContent(from: boxInfo)

            switch boxInfo.type {
            case .lbl:
                var box = try J2KLabelBox(label: "")
                try box.read(from: content)
                // First label becomes the association label
                if parsedLabel == nil {
                    parsedLabel = box
                } else {
                    parsedChildren.append(.labelContent(box))
                }
            case .xml:
                var box = try J2KXMLBox(xmlString: "")
                try box.read(from: content)
                parsedChildren.append(.xmlContent(box))
            case .nlst:
                var box = J2KNumberListBox()
                try box.read(from: content)
                parsedChildren.append(.numberList(box))
            default:
                parsedChildren.append(.rawContent(boxInfo.type, content))
            }
        }

        self.label = parsedLabel
        self.children = parsedChildren
    }
}

// MARK: - J2KCrossReferenceBox

/// Cross-reference box — references external resources.
///
/// Contains a reference to an external resource identified by a URL,
/// fragment, or UUID. This allows metadata or content to be stored
/// outside the JPEG 2000 file itself.
///
/// ## Box Structure
///
/// - Type: 'cref' (0x63726566)
/// - Length: Variable (8 + 1 + N bytes)
/// - Content:
///   - Reference type (1 byte): 0 = URL, 1 = fragment, 2 = UUID
///   - Reference string (N bytes): UTF-8 encoded reference
///
/// Example:
/// ```swift
/// let box = try J2KCrossReferenceBox(
///     referenceType: .url,
///     reference: "https://example.com/metadata.xml"
/// )
/// let data = try box.write()
/// ```
public struct J2KCrossReferenceBox: J2KBox, Sendable {
    /// The type of external reference.
    public enum ReferenceType: UInt8, Sendable {
        /// A URL reference.
        case url = 0
        /// A fragment identifier.
        case fragment = 1
        /// A UUID-based reference.
        case uuid = 2
    }

    /// The reference type.
    public var referenceType: ReferenceType

    /// The UTF-8 encoded reference string (URL, fragment, or UUID string).
    public var reference: String

    public var boxType: J2KBoxType { .cref }

    /// Creates a new cross-reference box.
    ///
    /// - Parameters:
    ///   - referenceType: The type of reference.
    ///   - reference: The reference string.
    /// - Throws: ``J2KError/fileFormatError(_:)`` if the reference cannot be
    ///   encoded as UTF-8.
    public init(referenceType: ReferenceType, reference: String) throws {
        guard reference.data(using: .utf8) != nil else {
            throw J2KError.fileFormatError(
                "Cross-reference string cannot be encoded as UTF-8")
        }
        self.referenceType = referenceType
        self.reference = reference
    }

    public func write() throws -> Data {
        guard let refData = reference.data(using: .utf8) else {
            throw J2KError.fileFormatError(
                "Failed to encode cross-reference as UTF-8")
        }
        var data = Data(capacity: 1 + refData.count)
        data.append(referenceType.rawValue)
        data.append(refData)
        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 1 else {
            throw J2KError.fileFormatError(
                "Cross-reference box too small: \(data.count)")
        }

        guard let type = ReferenceType(rawValue: data[0]) else {
            throw J2KError.fileFormatError(
                "Invalid cross-reference type: \(data[0])")
        }

        guard let string = String(data: data.suffix(from: 1), encoding: .utf8) else {
            throw J2KError.fileFormatError(
                "Cross-reference data is not valid UTF-8")
        }

        self.referenceType = type
        self.reference = string
    }
}

// MARK: - J2KDigitalSignatureBox

/// Digital signature box — content integrity verification.
///
/// Contains a digital signature over one or more boxes in the file,
/// allowing recipients to verify that the signed content has not been
/// modified. The box stores the hash algorithm, the list of signed box
/// types, and the raw signature bytes.
///
/// ## Box Structure
///
/// - Type: 'dsig' (0x64736967)
/// - Length: Variable (8 + 1 + 2 + M × 4 + N bytes)
/// - Content:
///   - Signature type (1 byte): 0 = MD5, 1 = SHA-1, 2 = SHA-256, 3 = SHA-512
///   - Signed box type count (2 bytes): Number of box types covered
///   - Signed box types (M × 4 bytes): Four-byte type codes
///   - Signature data (N bytes): Raw signature bytes
///
/// Example:
/// ```swift
/// let box = J2KDigitalSignatureBox(
///     signatureType: .sha256,
///     signatureData: sha256Bytes,
///     signedBoxTypes: [.jp2h, .jp2c]
/// )
/// let data = try box.write()
/// ```
public struct J2KDigitalSignatureBox: J2KBox, Sendable {
    /// Hash algorithm used for the signature.
    public enum SignatureType: UInt8, Sendable {
        /// MD5 (128-bit digest).
        case md5 = 0
        /// SHA-1 (160-bit digest).
        case sha1 = 1
        /// SHA-256 (256-bit digest).
        case sha256 = 2
        /// SHA-512 (512-bit digest).
        case sha512 = 3
    }

    /// The hash algorithm used.
    public var signatureType: SignatureType

    /// The raw signature bytes.
    public var signatureData: Data

    /// The box types whose content is covered by this signature.
    public var signedBoxTypes: [J2KBoxType]

    public var boxType: J2KBoxType { .dsig }

    /// Creates a new digital signature box.
    ///
    /// - Parameters:
    ///   - signatureType: The hash algorithm used.
    ///   - signatureData: The raw signature bytes.
    ///   - signedBoxTypes: The box types covered by this signature.
    public init(
        signatureType: SignatureType = .sha256,
        signatureData: Data = Data(),
        signedBoxTypes: [J2KBoxType] = []
    ) {
        self.signatureType = signatureType
        self.signatureData = signatureData
        self.signedBoxTypes = signedBoxTypes
    }

    public func write() throws -> Data {
        let typeCount = UInt16(signedBoxTypes.count)
        var data = Data(capacity: 1 + 2 + signedBoxTypes.count * 4 + signatureData.count)

        // Signature type (1 byte)
        data.append(signatureType.rawValue)

        // Signed box type count (2 bytes, big-endian)
        data.append(UInt8((typeCount >> 8) & 0xFF))
        data.append(UInt8(typeCount & 0xFF))

        // Signed box types (4 bytes each, big-endian)
        for boxType in signedBoxTypes {
            let v = boxType.rawValue
            data.append(UInt8((v >> 24) & 0xFF))
            data.append(UInt8((v >> 16) & 0xFF))
            data.append(UInt8((v >> 8) & 0xFF))
            data.append(UInt8(v & 0xFF))
        }

        // Signature data
        data.append(signatureData)

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 3 else {
            throw J2KError.fileFormatError(
                "Digital signature box too small: \(data.count)")
        }

        guard let sigType = SignatureType(rawValue: data[0]) else {
            throw J2KError.fileFormatError(
                "Invalid signature type: \(data[0])")
        }

        let typeCount = Int(UInt16(data[1]) << 8 | UInt16(data[2]))
        let headerSize = 3 + typeCount * 4
        guard data.count >= headerSize else {
            throw J2KError.fileFormatError(
                "Digital signature box too small for \(typeCount) box types: \(data.count)")
        }

        var types: [J2KBoxType] = []
        types.reserveCapacity(typeCount)

        for i in 0..<typeCount {
            let offset = 3 + i * 4
            let v = UInt32(data[offset]) << 24 |
                    UInt32(data[offset + 1]) << 16 |
                    UInt32(data[offset + 2]) << 8 |
                    UInt32(data[offset + 3])
            types.append(J2KBoxType(rawValue: v))
        }

        self.signatureType = sigType
        self.signedBoxTypes = types
        self.signatureData = data.suffix(from: headerSize)
    }
}

// MARK: - J2KROIDescriptionBox

/// ROI description box — describes regions of interest in the image.
///
/// Contains one or more regions that identify areas within the image
/// for which higher quality or special processing is desired. Each
/// region specifies a bounding rectangle and a priority level.
///
/// ## Box Structure
///
/// - Type: 'roid' (0x726F6964)
/// - Length: Variable (8 + 1 + 2 + N × 17 bytes)
/// - Content:
///   - ROI type (1 byte): 0 = rectangular, 1 = elliptical, 2 = polygonal
///   - Region count (2 bytes): Number of regions
///   - For each region (17 bytes):
///     - X origin (4 bytes): Horizontal offset
///     - Y origin (4 bytes): Vertical offset
///     - Width (4 bytes): Region width
///     - Height (4 bytes): Region height
///     - Priority (1 byte): Region priority (0 = highest)
///
/// Example:
/// ```swift
/// let region = J2KROIDescriptionBox.ROIRegion(
///     x: 100, y: 200, width: 300, height: 400, priority: 0
/// )
/// let box = J2KROIDescriptionBox(roiType: .rectangular, regions: [region])
/// let data = try box.write()
/// ```
public struct J2KROIDescriptionBox: J2KBox, Sendable {
    /// The geometric shape used to describe regions.
    public enum ROIType: UInt8, Sendable {
        /// Axis-aligned rectangle.
        case rectangular = 0
        /// Ellipse inscribed in the bounding rectangle.
        case elliptical = 1
        /// Polygon (vertices derived from bounding rectangle).
        case polygonal = 2
    }

    /// A single region of interest.
    public struct ROIRegion: Sendable, Equatable {
        /// Horizontal offset of the region origin.
        public var x: UInt32
        /// Vertical offset of the region origin.
        public var y: UInt32
        /// Width of the region.
        public var width: UInt32
        /// Height of the region.
        public var height: UInt32
        /// Priority level (0 = highest priority).
        public var priority: UInt8

        /// Creates a new ROI region.
        ///
        /// - Parameters:
        ///   - x: Horizontal offset.
        ///   - y: Vertical offset.
        ///   - width: Region width.
        ///   - height: Region height.
        ///   - priority: Priority level (0 = highest).
        public init(x: UInt32, y: UInt32, width: UInt32, height: UInt32, priority: UInt8) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.priority = priority
        }
    }

    /// The geometric type of the regions.
    public var roiType: ROIType

    /// The list of regions.
    public var regions: [ROIRegion]

    public var boxType: J2KBoxType { .roid }

    /// Creates a new ROI description box.
    ///
    /// - Parameters:
    ///   - roiType: The geometric shape of the regions.
    ///   - regions: The list of regions.
    public init(roiType: ROIType = .rectangular, regions: [ROIRegion] = []) {
        self.roiType = roiType
        self.regions = regions
    }

    public func write() throws -> Data {
        let regionCount = UInt16(regions.count)
        var data = Data(capacity: 1 + 2 + regions.count * 17)

        // ROI type (1 byte)
        data.append(roiType.rawValue)

        // Region count (2 bytes, big-endian)
        data.append(UInt8((regionCount >> 8) & 0xFF))
        data.append(UInt8(regionCount & 0xFF))

        // Regions (17 bytes each)
        for region in regions {
            // X (4 bytes)
            data.append(UInt8((region.x >> 24) & 0xFF))
            data.append(UInt8((region.x >> 16) & 0xFF))
            data.append(UInt8((region.x >> 8) & 0xFF))
            data.append(UInt8(region.x & 0xFF))

            // Y (4 bytes)
            data.append(UInt8((region.y >> 24) & 0xFF))
            data.append(UInt8((region.y >> 16) & 0xFF))
            data.append(UInt8((region.y >> 8) & 0xFF))
            data.append(UInt8(region.y & 0xFF))

            // Width (4 bytes)
            data.append(UInt8((region.width >> 24) & 0xFF))
            data.append(UInt8((region.width >> 16) & 0xFF))
            data.append(UInt8((region.width >> 8) & 0xFF))
            data.append(UInt8(region.width & 0xFF))

            // Height (4 bytes)
            data.append(UInt8((region.height >> 24) & 0xFF))
            data.append(UInt8((region.height >> 16) & 0xFF))
            data.append(UInt8((region.height >> 8) & 0xFF))
            data.append(UInt8(region.height & 0xFF))

            // Priority (1 byte)
            data.append(region.priority)
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 3 else {
            throw J2KError.fileFormatError(
                "ROI description box too small: \(data.count)")
        }

        guard let type = ROIType(rawValue: data[0]) else {
            throw J2KError.fileFormatError(
                "Invalid ROI type: \(data[0])")
        }

        let regionCount = Int(UInt16(data[1]) << 8 | UInt16(data[2]))
        let expectedSize = 3 + regionCount * 17
        guard data.count >= expectedSize else {
            throw J2KError.fileFormatError(
                "ROI description box too small for \(regionCount) regions: "
                + "\(data.count), expected \(expectedSize)")
        }

        var result: [ROIRegion] = []
        result.reserveCapacity(regionCount)

        for i in 0..<regionCount {
            let offset = 3 + i * 17

            let x = UInt32(data[offset]) << 24 |
                    UInt32(data[offset + 1]) << 16 |
                    UInt32(data[offset + 2]) << 8 |
                    UInt32(data[offset + 3])

            let y = UInt32(data[offset + 4]) << 24 |
                    UInt32(data[offset + 5]) << 16 |
                    UInt32(data[offset + 6]) << 8 |
                    UInt32(data[offset + 7])

            let w = UInt32(data[offset + 8]) << 24 |
                    UInt32(data[offset + 9]) << 16 |
                    UInt32(data[offset + 10]) << 8 |
                    UInt32(data[offset + 11])

            let h = UInt32(data[offset + 12]) << 24 |
                    UInt32(data[offset + 13]) << 16 |
                    UInt32(data[offset + 14]) << 8 |
                    UInt32(data[offset + 15])

            let priority = data[offset + 16]

            result.append(ROIRegion(x: x, y: y, width: w, height: h, priority: priority))
        }

        self.roiType = type
        self.regions = result
    }
}

// MARK: - J2KDataEntryURLBox

/// Data entry URL box — external resource reference.
///
/// Contains a URL pointing to an external resource. The version and flags
/// fields follow the ISO base media file format full-box convention where
/// the flags field is 24 bits wide.
///
/// ## Box Structure
///
/// - Type: 'url ' (0x75726C20)
/// - Length: Variable (8 + 1 + 3 + N bytes)
/// - Content:
///   - Version (1 byte): Box version (typically 0)
///   - Flags (3 bytes): 24-bit flags stored in a UInt32
///   - URL string (N bytes): UTF-8 encoded URL
///
/// Example:
/// ```swift
/// let box = try J2KDataEntryURLBox(
///     version: 0,
///     flags: 0,
///     url: "https://example.com/resource"
/// )
/// let data = try box.write()
/// ```
public struct J2KDataEntryURLBox: J2KBox, Sendable {
    /// Box version (typically 0).
    public var version: UInt8

    /// 24-bit flags stored in the lower 3 bytes of a UInt32.
    public var flags: UInt32

    /// The UTF-8 encoded URL string.
    public var url: String

    public var boxType: J2KBoxType { .url }

    /// Creates a new data entry URL box.
    ///
    /// - Parameters:
    ///   - version: The box version.
    ///   - flags: 24-bit flags value.
    ///   - url: The URL string.
    /// - Throws: ``J2KError/fileFormatError(_:)`` if the URL cannot be
    ///   encoded as UTF-8.
    public init(version: UInt8 = 0, flags: UInt32 = 0, url: String) throws {
        guard url.data(using: .utf8) != nil else {
            throw J2KError.fileFormatError(
                "URL string cannot be encoded as UTF-8")
        }
        self.version = version
        self.flags = flags & 0x00FFFFFF
        self.url = url
    }

    public func write() throws -> Data {
        guard let urlData = url.data(using: .utf8) else {
            throw J2KError.fileFormatError("Failed to encode URL as UTF-8")
        }

        var data = Data(capacity: 4 + urlData.count)

        // Version (1 byte)
        data.append(version)

        // Flags (3 bytes, big-endian, only lower 24 bits)
        data.append(UInt8((flags >> 16) & 0xFF))
        data.append(UInt8((flags >> 8) & 0xFF))
        data.append(UInt8(flags & 0xFF))

        // URL string
        data.append(urlData)

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 4 else {
            throw J2KError.fileFormatError(
                "Data entry URL box too small: \(data.count)")
        }

        self.version = data[0]
        self.flags = UInt32(data[1]) << 16 |
                     UInt32(data[2]) << 8 |
                     UInt32(data[3])

        guard let string = String(data: data.suffix(from: 4), encoding: .utf8) else {
            throw J2KError.fileFormatError(
                "Data entry URL box data is not valid UTF-8")
        }
        self.url = string
    }
}

// MARK: - J2KPart2XMLMetadata

/// Helper for Part 2 extended XML metadata.
///
/// Wraps a ``J2KXMLBox`` with Part 2 specific schema detection and
/// convenience methods. This is **not** a box type itself — use
/// ``toXMLBox()`` to produce a standard XML box for serialisation.
///
/// ## Schema Types
///
/// Part 2 defines several well-known XML schema families:
/// - **GML**: Geography Markup Language metadata (GMLJP2)
/// - **JPX**: JPX file format metadata extensions
/// - **Custom**: Application-specific schemas
/// - **Generic**: Unrecognised or general-purpose XML
///
/// Example:
/// ```swift
/// let meta = J2KPart2XMLMetadata(
///     schema: .gml,
///     content: "<gml:FeatureCollection>...</gml:FeatureCollection>"
/// )
/// let box = meta.toXMLBox()
/// let data = try box.write()
/// ```
public struct J2KPart2XMLMetadata: Sendable {
    /// Well-known XML schema families used in Part 2 files.
    public enum SchemaType: UInt8, Sendable {
        /// General-purpose or unrecognised XML.
        case generic = 0
        /// Geography Markup Language (GMLJP2).
        case gml = 1
        /// JPX file format metadata.
        case jpx = 2
        /// Application-specific schema.
        case custom = 3
    }

    /// The schema family.
    public var schemaType: SchemaType

    /// The XML content string.
    public var xmlContent: String

    /// Creates Part 2 XML metadata.
    ///
    /// - Parameters:
    ///   - schema: The schema family.
    ///   - content: The XML content string.
    public init(schema: SchemaType, content: String) {
        self.schemaType = schema
        self.xmlContent = content
    }

    /// Converts this metadata into a standard ``J2KXMLBox``.
    ///
    /// - Returns: A ``J2KXMLBox`` containing the XML content.
    /// - Throws: ``J2KError/fileFormatError(_:)`` if the content is not
    ///   valid UTF-8.
    public func toXMLBox() throws -> J2KXMLBox {
        try J2KXMLBox(xmlString: xmlContent)
    }

    /// Attempts to create Part 2 metadata from an existing ``J2KXMLBox``.
    ///
    /// The schema type is inferred from the XML content by inspecting
    /// well-known namespace URIs and root element names.
    ///
    /// - Parameter box: The XML box to inspect.
    /// - Returns: A ``J2KPart2XMLMetadata`` instance, or `nil` if the
    ///   content is empty.
    public static func fromXMLBox(_ box: J2KXMLBox) -> J2KPart2XMLMetadata? {
        let content = box.xmlString
        guard !content.isEmpty else { return nil }

        let schema = detectSchema(content)
        return J2KPart2XMLMetadata(schema: schema, content: content)
    }

    /// Detects the schema type from XML content.
    ///
    /// - Parameter xml: The XML string to inspect.
    /// - Returns: The detected ``SchemaType``.
    public static func detectSchema(_ xml: String) -> SchemaType {
        if xml.contains("http://www.opengis.net/gml") ||
           xml.contains("gml:") ||
           xml.contains("<gml") {
            return .gml
        }
        if xml.contains("http://www.jpeg.org/jpx") ||
           xml.contains("jpx:") ||
           xml.contains("<jpx") {
            return .jpx
        }
        return .generic
    }

    /// Generates a minimal Part 2 feature description XML document.
    ///
    /// - Parameters:
    ///   - featureName: The name of the feature.
    ///   - description: A human-readable description.
    /// - Returns: A well-formed XML string.
    public static func featureXML(featureName: String, description: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <jpx:Feature xmlns:jpx="http://www.jpeg.org/jpx">
          <jpx:Name>\(featureName)</jpx:Name>
          <jpx:Description>\(description)</jpx:Description>
        </jpx:Feature>
        """
    }
}
