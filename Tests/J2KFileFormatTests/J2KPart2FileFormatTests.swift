// J2KPart2FileFormatTests.swift
// J2KSwift
//
// Tests for Part 2 box types, reader requirements, and JPX animation.

import XCTest
@testable import J2KFileFormat
@testable import J2KCore

/// Tests for Part 2 box types defined in ISO/IEC 15444-2.
final class J2KPart2FileFormatTests: XCTestCase {

    // MARK: - IPR Box Tests

    func testIPRBoxWrite() throws {
        let iprData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let box = J2KIPRBox(data: iprData)
        let written = try box.write()

        XCTAssertEqual(written.count, 5)
        XCTAssertEqual(written, iprData)
        XCTAssertEqual(box.boxType, .jp2i)
    }

    func testIPRBoxRoundTrip() throws {
        let original = J2KIPRBox(data: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let data = try original.write()

        var decoded = J2KIPRBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.data, original.data)
        XCTAssertEqual(decoded.boxType, .jp2i)
    }

    func testIPRBoxReadTooShort() throws {
        // IPR box accepts any data including empty, so test that empty works
        var box = J2KIPRBox()
        try box.read(from: Data())
        XCTAssertEqual(box.data.count, 0)
    }

    // MARK: - Label Box Tests

    func testLabelBoxWrite() throws {
        let box = try J2KLabelBox(label: "Test Label")
        let data = try box.write()

        XCTAssertEqual(String(data: data, encoding: .utf8), "Test Label")
        XCTAssertEqual(box.boxType, .lbl)
    }

    func testLabelBoxRoundTrip() throws {
        let original = try J2KLabelBox(label: "Layer 0 - Background")
        let data = try original.write()

        var decoded = try J2KLabelBox(label: "")
        try decoded.read(from: data)

        XCTAssertEqual(decoded.label, original.label)
    }

    func testLabelBoxUnicode() throws {
        let original = try J2KLabelBox(label: "日本語テスト — résumé 🌍")
        let data = try original.write()

        var decoded = try J2KLabelBox(label: "")
        try decoded.read(from: data)

        XCTAssertEqual(decoded.label, "日本語テスト — résumé 🌍")
    }

    // MARK: - Number List Box Tests

    func testNumberListBoxWrite() throws {
        let box = J2KNumberListBox(associations: [
            .init(entityType: .codestream, entityIndex: 0)
        ])
        let data = try box.write()

        XCTAssertEqual(data.count, 6)
        // Entity type 0 (codestream) big-endian
        XCTAssertEqual(data[0], 0x00)
        XCTAssertEqual(data[1], 0x00)
        // Entity index 0 big-endian
        XCTAssertEqual(data[2], 0x00)
        XCTAssertEqual(data[3], 0x00)
        XCTAssertEqual(data[4], 0x00)
        XCTAssertEqual(data[5], 0x00)
    }

    func testNumberListBoxRoundTrip() throws {
        let original = J2KNumberListBox(associations: [
            .init(entityType: .codestream, entityIndex: 0),
            .init(entityType: .compositingLayer, entityIndex: 5),
            .init(entityType: .rendered, entityIndex: 42)
        ])
        let data = try original.write()

        var decoded = J2KNumberListBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.associations.count, 3)
        XCTAssertEqual(decoded.associations[0], original.associations[0])
        XCTAssertEqual(decoded.associations[1], original.associations[1])
        XCTAssertEqual(decoded.associations[2], original.associations[2])
    }

    func testNumberListBoxEmpty() throws {
        let box = J2KNumberListBox(associations: [])
        let data = try box.write()

        XCTAssertEqual(data.count, 0)

        var decoded = J2KNumberListBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.associations.count, 0)
    }

    // MARK: - Cross-Reference Box Tests

    func testCrossReferenceBoxWrite() throws {
        let box = try J2KCrossReferenceBox(
            referenceType: .url,
            reference: "https://example.com/metadata.xml"
        )
        let data = try box.write()

        XCTAssertEqual(data[0], 0x00) // URL type
        let refString = String(data: data.suffix(from: 1), encoding: .utf8)
        XCTAssertEqual(refString, "https://example.com/metadata.xml")
    }

    func testCrossReferenceBoxRoundTrip() throws {
        let original = try J2KCrossReferenceBox(
            referenceType: .fragment,
            reference: "#section-42"
        )
        let data = try original.write()

        var decoded = try J2KCrossReferenceBox(referenceType: .url, reference: "")
        try decoded.read(from: data)

        XCTAssertEqual(decoded.referenceType, .fragment)
        XCTAssertEqual(decoded.reference, "#section-42")
    }

    // MARK: - Digital Signature Box Tests

    func testDigitalSignatureBoxWrite() throws {
        let sigData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let box = J2KDigitalSignatureBox(
            signatureType: .sha256,
            signatureData: sigData,
            signedBoxTypes: [.jp2h, .jp2c]
        )
        let data = try box.write()

        XCTAssertEqual(data[0], 0x02) // SHA-256
        // Signed box type count = 2
        XCTAssertEqual(data[1], 0x00)
        XCTAssertEqual(data[2], 0x02)
        XCTAssertEqual(box.boxType, .dsig)
    }

    func testDigitalSignatureBoxRoundTrip() throws {
        let sigData = Data(repeating: 0x42, count: 32)
        let original = J2KDigitalSignatureBox(
            signatureType: .sha512,
            signatureData: sigData,
            signedBoxTypes: [.jp2h, .jp2c, .colr]
        )
        let data = try original.write()

        var decoded = J2KDigitalSignatureBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.signatureType, .sha512)
        XCTAssertEqual(decoded.signatureData, sigData)
        XCTAssertEqual(decoded.signedBoxTypes.count, 3)
        XCTAssertEqual(decoded.signedBoxTypes[0], .jp2h)
        XCTAssertEqual(decoded.signedBoxTypes[1], .jp2c)
        XCTAssertEqual(decoded.signedBoxTypes[2], .colr)
    }

    // MARK: - ROI Description Box Tests

    func testROIDescriptionBoxWrite() throws {
        let region = J2KROIDescriptionBox.ROIRegion(
            x: 100, y: 200, width: 300, height: 400, priority: 0
        )
        let box = J2KROIDescriptionBox(roiType: .rectangular, regions: [region])
        let data = try box.write()

        XCTAssertEqual(data[0], 0x00) // rectangular
        // Region count = 1
        XCTAssertEqual(data[1], 0x00)
        XCTAssertEqual(data[2], 0x01)
        // 3 + 17 = 20 bytes total
        XCTAssertEqual(data.count, 20)
        XCTAssertEqual(box.boxType, .roid)
    }

    func testROIDescriptionBoxRoundTrip() throws {
        let original = J2KROIDescriptionBox(
            roiType: .elliptical,
            regions: [
                .init(x: 10, y: 20, width: 100, height: 200, priority: 1),
                .init(x: 500, y: 600, width: 50, height: 75, priority: 3)
            ]
        )
        let data = try original.write()

        var decoded = J2KROIDescriptionBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.roiType, .elliptical)
        XCTAssertEqual(decoded.regions.count, 2)
        XCTAssertEqual(decoded.regions[0], original.regions[0])
        XCTAssertEqual(decoded.regions[1], original.regions[1])
    }

    // MARK: - Association Box Tests

    func testAssociationBoxWrite() throws {
        let label = try J2KLabelBox(label: "GeoTIFF Metadata")
        let nlst = J2KNumberListBox(associations: [
            .init(entityType: .codestream, entityIndex: 0)
        ])
        let box = J2KAssociationBox(
            label: label,
            children: [.numberList(nlst)]
        )
        let data = try box.write()

        // Super-box containing a label box + number list box
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(box.boxType, .asoc)
    }

    func testAssociationBoxRoundTrip() throws {
        let label = try J2KLabelBox(label: "Test Association")
        let nlst = J2KNumberListBox(associations: [
            .init(entityType: .compositingLayer, entityIndex: 2)
        ])
        let original = J2KAssociationBox(
            label: label,
            children: [.numberList(nlst)]
        )
        let data = try original.write()

        var decoded = J2KAssociationBox()
        try decoded.read(from: data)

        XCTAssertNotNil(decoded.label)
        XCTAssertEqual(decoded.label?.label, "Test Association")
        XCTAssertEqual(decoded.children.count, 1)
    }

    // MARK: - Data Entry URL Box Tests

    func testDataEntryURLBoxRoundTrip() throws {
        let original = try J2KDataEntryURLBox(
            version: 0,
            flags: 0x000001,
            url: "https://example.com/resource"
        )
        let data = try original.write()

        var decoded = try J2KDataEntryURLBox(url: "")
        try decoded.read(from: data)

        XCTAssertEqual(decoded.version, 0)
        XCTAssertEqual(decoded.flags, 0x000001)
        XCTAssertEqual(decoded.url, "https://example.com/resource")
    }

    // MARK: - Part 2 XML Metadata Tests

    func testPart2XMLMetadata() throws {
        let gmlContent = "<gml:FeatureCollection xmlns:gml=\"http://www.opengis.net/gml\"></gml:FeatureCollection>"
        let meta = J2KPart2XMLMetadata(schema: .gml, content: gmlContent)

        XCTAssertEqual(meta.schemaType, .gml)
        XCTAssertEqual(meta.xmlContent, gmlContent)

        let xmlBox = try meta.toXMLBox()
        XCTAssertEqual(xmlBox.xmlString, gmlContent)
    }

    func testPart2XMLMetadataSchemaDetection() {
        XCTAssertEqual(
            J2KPart2XMLMetadata.detectSchema("<gml:Point/>"),
            .gml
        )
        XCTAssertEqual(
            J2KPart2XMLMetadata.detectSchema("<jpx:Feature/>"),
            .jpx
        )
        XCTAssertEqual(
            J2KPart2XMLMetadata.detectSchema("<custom/>"),
            .generic
        )
    }

    func testPart2XMLMetadataFeatureXML() {
        let xml = J2KPart2XMLMetadata.featureXML(
            featureName: "MCT",
            description: "Multi-component transform"
        )
        XCTAssertTrue(xml.contains("MCT"))
        XCTAssertTrue(xml.contains("Multi-component transform"))
        XCTAssertTrue(xml.contains("xmlns:jpx"))
    }

    // MARK: - Standard Feature Tests

    func testStandardFeatureNames() {
        XCTAssertEqual(
            J2KStandardFeature.noExtensions.featureName,
            "No Extensions (Part 1 only)"
        )
        XCTAssertEqual(
            J2KStandardFeature.multiComponentTransform.featureName,
            "Multi-Component Transform (Part 2)"
        )
        XCTAssertEqual(
            J2KStandardFeature.animation.featureName,
            "Animation"
        )
    }

    func testStandardFeatureIsPart2() {
        XCTAssertFalse(J2KStandardFeature.noExtensions.isPart2Feature)
        XCTAssertFalse(J2KStandardFeature.multipleCompositionLayers.isPart2Feature)
        XCTAssertFalse(J2KStandardFeature.animation.isPart2Feature)

        XCTAssertTrue(J2KStandardFeature.multiComponentTransform.isPart2Feature)
        XCTAssertTrue(J2KStandardFeature.arbitraryWavelets.isPart2Feature)
        XCTAssertTrue(J2KStandardFeature.dcOffset.isPart2Feature)
        XCTAssertTrue(J2KStandardFeature.extendedPrecision.isPart2Feature)
    }

    // MARK: - Reader Requirements Box Tests

    func testReaderRequirementsBoxWrite() throws {
        let box = J2KReaderRequirementsBox(
            maskLength: 1,
            fullyUnderstandMask: 0x80,
            displayMask: 0x00,
            standardFeatures: [
                .init(feature: .noExtensions, mask: 0x80)
            ],
            vendorFeatures: []
        )
        let data = try box.write()

        // ML(1) + FUAM(1) + DCM(1) + NSF(2) + SF(2)+SM(1) + NVF(2) = 10
        XCTAssertEqual(data.count, 10)
        XCTAssertEqual(data[0], 1)    // ML = 1
        XCTAssertEqual(data[1], 0x80) // FUAM
        XCTAssertEqual(data[2], 0x00) // DCM
        XCTAssertEqual(box.boxType, .rreq)
    }

    func testReaderRequirementsBoxRoundTrip() throws {
        let original = J2KReaderRequirementsBox(
            maskLength: 1,
            fullyUnderstandMask: 0xC0,
            displayMask: 0x40,
            standardFeatures: [
                .init(feature: .noExtensions, mask: 0x80),
                .init(feature: .multiComponentTransform, mask: 0x40)
            ],
            vendorFeatures: []
        )
        let data = try original.write()

        var decoded = J2KReaderRequirementsBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.maskLength, 1)
        XCTAssertEqual(decoded.fullyUnderstandMask, 0xC0)
        XCTAssertEqual(decoded.displayMask, 0x40)
        XCTAssertEqual(decoded.standardFeatures.count, 2)
        XCTAssertEqual(decoded.standardFeatures[0].feature, .noExtensions)
        XCTAssertEqual(decoded.standardFeatures[0].mask, 0x80)
        XCTAssertEqual(decoded.standardFeatures[1].feature, .multiComponentTransform)
        XCTAssertEqual(decoded.standardFeatures[1].mask, 0x40)
        XCTAssertEqual(decoded.vendorFeatures.count, 0)
    }

    func testReaderRequirementsBoxMultipleMaskLengths() throws {
        for ml: UInt8 in [1, 2, 4, 8] {
            let mask: UInt64 = ml == 1 ? 0x80 : (ml == 2 ? 0x8000 : (ml == 4 ? 0x80000000 : 0x8000000000000000))
            let original = J2KReaderRequirementsBox(
                maskLength: ml,
                fullyUnderstandMask: mask,
                displayMask: 0,
                standardFeatures: [
                    .init(feature: .noExtensions, mask: mask)
                ],
                vendorFeatures: []
            )
            let data = try original.write()

            var decoded = J2KReaderRequirementsBox()
            try decoded.read(from: data)

            XCTAssertEqual(decoded.maskLength, ml, "Failed for mask length \(ml)")
            XCTAssertEqual(decoded.fullyUnderstandMask, mask, "Failed for mask length \(ml)")
            XCTAssertEqual(decoded.standardFeatures.count, 1, "Failed for mask length \(ml)")
            XCTAssertEqual(decoded.standardFeatures[0].mask, mask, "Failed for mask length \(ml)")
        }
    }

    // MARK: - Decoder Capability Tests

    func testDecoderCapabilityPart1() {
        let decoder = J2KDecoderCapability.part1Decoder()
        XCTAssertTrue(decoder.supportedFeatures.contains(.noExtensions))
        XCTAssertFalse(decoder.supportedFeatures.contains(.multiComponentTransform))
    }

    func testDecoderCapabilityPart2() {
        let decoder = J2KDecoderCapability.part2Decoder()
        XCTAssertTrue(decoder.supportedFeatures.contains(.noExtensions))
        XCTAssertTrue(decoder.supportedFeatures.contains(.multiComponentTransform))
        XCTAssertTrue(decoder.supportedFeatures.contains(.arbitraryWavelets))
        XCTAssertTrue(decoder.supportedFeatures.contains(.dcOffset))
    }

    func testDecoderCapabilityMissingFeatures() {
        let decoder = J2KDecoderCapability.part1Decoder()
        let requirements = J2KReaderRequirementsBox(
            maskLength: 1,
            fullyUnderstandMask: 0xC0,
            displayMask: 0x40,
            standardFeatures: [
                .init(feature: .noExtensions, mask: 0x80),
                .init(feature: .multiComponentTransform, mask: 0x40)
            ],
            vendorFeatures: []
        )

        let missing = decoder.missingFeatures(requirements)
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing[0], .multiComponentTransform)
    }

    func testDecoderCapabilityValidation() {
        let decoder = J2KDecoderCapability.part1Decoder()
        let requirements = J2KReaderRequirementsBox(
            maskLength: 1,
            fullyUnderstandMask: 0xC0,
            displayMask: 0x40,
            standardFeatures: [
                .init(feature: .noExtensions, mask: 0x80),
                .init(feature: .multiComponentTransform, mask: 0x40)
            ],
            vendorFeatures: []
        )

        let result = decoder.validate(requirements)
        switch result {
        case .incompatible(let missing):
            XCTAssertTrue(missing.contains(.multiComponentTransform))
        default:
            XCTFail("Expected incompatible result")
        }
    }

    // MARK: - Feature Compatibility Tests

    func testFeatureCompatibilityValidation() {
        // noExtensions with other features is an error
        let issues = J2KFeatureCompatibility.validateFeatureCombination(
            [.noExtensions, .multiComponentTransform]
        )
        let errors = issues.filter { $0.severity == .error }
        XCTAssertFalse(errors.isEmpty)
    }

    func testFeatureCompatibilityPart2Warning() {
        // Part 2 feature without needsJPXReader should warn
        let issues = J2KFeatureCompatibility.validateFeatureCombination(
            [.multiComponentTransform]
        )
        let warnings = issues.filter { $0.severity == .warning }
        XCTAssertTrue(warnings.contains { $0.feature == .needsJPXReader })
    }

    func testSuggestedReaderRequirements() {
        let features: Set<J2KStandardFeature> = [.noExtensions]
        let box = J2KFeatureCompatibility.suggestedReaderRequirements(for: features)

        XCTAssertEqual(box.maskLength, 1)
        XCTAssertEqual(box.standardFeatures.count, 1)
        XCTAssertEqual(box.standardFeatures[0].feature, .noExtensions)
        // noExtensions is not Part 2, so displayMask should be 0
        XCTAssertEqual(box.displayMask, 0)
        // fullyUnderstandMask should have bits set
        XCTAssertTrue(box.fullyUnderstandMask != 0)
    }

    // MARK: - Animation Timing Tests

    func testAnimationTimingMilliseconds() {
        let timing = J2KAnimationTiming.milliseconds(duration: 5000, loops: 3)

        XCTAssertEqual(timing.timescale, 1000)
        XCTAssertEqual(timing.duration, 5000)
        XCTAssertEqual(timing.loopCount, 3)
        XCTAssertEqual(timing.durationSeconds, 5.0, accuracy: 0.001)
        XCTAssertFalse(timing.isInfinite)
    }

    func testAnimationTimingSeconds() {
        let timing = J2KAnimationTiming.seconds(duration: 2.5, loops: 1)

        XCTAssertEqual(timing.timescale, 1000)
        XCTAssertEqual(timing.duration, 2500)
        XCTAssertEqual(timing.loopCount, 1)
        XCTAssertEqual(timing.durationSeconds, 2.5, accuracy: 0.001)
        XCTAssertFalse(timing.isInfinite)
    }

    func testAnimationTimingInfinite() {
        let timing = J2KAnimationTiming.infinite()

        XCTAssertEqual(timing.timescale, 1000)
        XCTAssertEqual(timing.duration, 0)
        XCTAssertEqual(timing.loopCount, 0)
        XCTAssertTrue(timing.isInfinite)
    }

    // MARK: - Instruction Set Box Tests

    func testInstructionSetBoxWrite() throws {
        let entry = J2KInstructionSetBox.InstructionEntry(
            layerIndex: 0,
            horizontalOffset: 100,
            verticalOffset: -50,
            persistenceFlag: true
        )
        let box = J2KInstructionSetBox(
            instructionType: .animate,
            repeatCount: 3,
            tickDuration: 100,
            instructions: [entry]
        )
        let data = try box.write()

        // Header: 1 + 2 + 4 + 2 = 9, Entry: 11, Total: 20
        XCTAssertEqual(data.count, 20)
        XCTAssertEqual(data[0], 1) // animate
        XCTAssertEqual(box.boxType, .inst)
    }

    func testInstructionSetBoxRoundTrip() throws {
        let original = J2KInstructionSetBox(
            instructionType: .compose,
            repeatCount: 5,
            tickDuration: 200,
            instructions: [
                .init(layerIndex: 0, horizontalOffset: 0, verticalOffset: 0, persistenceFlag: false),
                .init(layerIndex: 1, horizontalOffset: -100, verticalOffset: 50, persistenceFlag: true)
            ]
        )
        let data = try original.write()

        var decoded = J2KInstructionSetBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.instructionType, .compose)
        XCTAssertEqual(decoded.repeatCount, 5)
        XCTAssertEqual(decoded.tickDuration, 200)
        XCTAssertEqual(decoded.instructions.count, 2)
        XCTAssertEqual(decoded.instructions[0].layerIndex, 0)
        XCTAssertEqual(decoded.instructions[0].horizontalOffset, 0)
        XCTAssertEqual(decoded.instructions[0].persistenceFlag, false)
        XCTAssertEqual(decoded.instructions[1].layerIndex, 1)
        XCTAssertEqual(decoded.instructions[1].horizontalOffset, -100)
        XCTAssertEqual(decoded.instructions[1].verticalOffset, 50)
        XCTAssertEqual(decoded.instructions[1].persistenceFlag, true)
    }

    // MARK: - Opacity Box Tests

    func testOpacityBoxWrite() throws {
        let box = J2KOpacityBox(opacityType: .globalValue, opacity: 128)
        let data = try box.write()

        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0], 2) // globalValue
        XCTAssertEqual(data[1], 128)
        XCTAssertEqual(box.boxType, .opct)
    }

    func testOpacityBoxRoundTrip() throws {
        let original = J2KOpacityBox(opacityType: .lastChannel, opacity: 0)
        let data = try original.write()

        var decoded = J2KOpacityBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.opacityType, .lastChannel)
        XCTAssertEqual(decoded.opacity, 0)
    }

    func testOpacityBoxReadTooShort() {
        var box = J2KOpacityBox()
        XCTAssertThrowsError(try box.read(from: Data([0x00])))
    }

    // MARK: - Codestream Registration Box Tests

    func testCodestreamRegistrationBoxRoundTrip() throws {
        let original = J2KCodestreamRegistrationBox(
            horizontalGridSize: 1920,
            verticalGridSize: 1080,
            registrations: [
                .init(codestreamIndex: 0, horizontalOffset: 0, verticalOffset: 0),
                .init(codestreamIndex: 1, horizontalOffset: 960, verticalOffset: 0)
            ]
        )
        let data = try original.write()

        var decoded = J2KCodestreamRegistrationBox(
            horizontalGridSize: 0,
            verticalGridSize: 0
        )
        try decoded.read(from: data)

        XCTAssertEqual(decoded.horizontalGridSize, 1920)
        XCTAssertEqual(decoded.verticalGridSize, 1080)
        XCTAssertEqual(decoded.registrations.count, 2)
        XCTAssertEqual(decoded.registrations[0].codestreamIndex, 0)
        XCTAssertEqual(decoded.registrations[0].horizontalOffset, 0)
        XCTAssertEqual(decoded.registrations[1].codestreamIndex, 1)
        XCTAssertEqual(decoded.registrations[1].horizontalOffset, 960)
    }

    func testCodestreamRegistrationBoxReadTooShort() {
        var box = J2KCodestreamRegistrationBox(
            horizontalGridSize: 0,
            verticalGridSize: 0
        )
        XCTAssertThrowsError(try box.read(from: Data([0x00, 0x01])))
    }

    // MARK: - Composition Layer Header Box Tests

    func testCompositionLayerHeaderBoxRoundTrip() throws {
        let colorSpec = J2KColorSpecificationBox(
            method: .enumerated(.sRGB),
            precedence: 0,
            approximation: 0
        )
        let opacityBox = J2KOpacityBox(opacityType: .globalValue, opacity: 200)
        let label = try J2KLabelBox(label: "Background Layer")

        let original = J2KCompositionLayerHeaderBox(
            colorSpecs: [colorSpec],
            opacity: opacityBox,
            labels: [label]
        )
        let data = try original.write()

        var decoded = J2KCompositionLayerHeaderBox()
        try decoded.read(from: data)

        XCTAssertEqual(decoded.colorSpecs.count, 1)
        XCTAssertNotNil(decoded.opacity)
        XCTAssertEqual(decoded.opacity?.opacityType, .globalValue)
        XCTAssertEqual(decoded.opacity?.opacity, 200)
        XCTAssertEqual(decoded.labels.count, 1)
        XCTAssertEqual(decoded.labels[0].label, "Background Layer")
    }

    // MARK: - JPX Animation Sequence Tests

    func testJPXAnimationSequence() {
        var animation = J2KJPXAnimationSequence(
            width: 800,
            height: 600,
            timing: .milliseconds(duration: 3000, loops: 0)
        )
        animation.addFrame(codestreamIndex: 0, duration: 100)
        animation.addFrame(codestreamIndex: 1, duration: 100)
        animation.addFrame(codestreamIndex: 2, duration: 100)

        XCTAssertEqual(animation.frameCount, 3)
        XCTAssertEqual(animation.totalDuration, 300)
        XCTAssertEqual(animation.width, 800)
        XCTAssertEqual(animation.height, 600)

        let compositionBox = animation.toCompositionBox()
        XCTAssertEqual(compositionBox.width, 800)
        XCTAssertEqual(compositionBox.height, 600)

        let instructionBox = animation.toInstructionSetBox()
        XCTAssertEqual(instructionBox.instructionType, .animate)
        XCTAssertEqual(instructionBox.instructions.count, 3)
    }

    func testJPXAnimationSequenceValidation() {
        // Empty frames should fail
        let emptyAnimation = J2KJPXAnimationSequence(
            width: 800,
            height: 600,
            timing: .milliseconds(duration: 1000)
        )
        XCTAssertThrowsError(try emptyAnimation.validate())

        // Zero dimensions should fail
        var zeroDimAnimation = J2KJPXAnimationSequence(
            width: 0,
            height: 600,
            timing: .milliseconds(duration: 1000)
        )
        zeroDimAnimation.addFrame(codestreamIndex: 0, duration: 100)
        XCTAssertThrowsError(try zeroDimAnimation.validate())

        // Zero timescale should fail
        var zeroTimescaleAnim = J2KJPXAnimationSequence(
            width: 800,
            height: 600,
            timing: J2KAnimationTiming(timescale: 0, duration: 1000)
        )
        zeroTimescaleAnim.addFrame(codestreamIndex: 0, duration: 100)
        XCTAssertThrowsError(try zeroTimescaleAnim.validate())

        // Valid animation should succeed
        var validAnimation = J2KJPXAnimationSequence(
            width: 800,
            height: 600,
            timing: .milliseconds(duration: 1000)
        )
        validAnimation.addFrame(codestreamIndex: 0, duration: 100)
        XCTAssertNoThrow(try validAnimation.validate())
    }

    // MARK: - Multi-Layer Compositor Tests

    func testMultiLayerCompositor() throws {
        var compositor = J2KMultiLayerCompositor(
            canvasWidth: 1920,
            canvasHeight: 1080
        )
        compositor.addLayer(
            codestreamIndex: 0,
            x: 0, y: 0,
            width: 960, height: 1080,
            opacity: 255,
            compositingMode: .replace
        )
        compositor.addLayer(
            codestreamIndex: 1,
            x: 960, y: 0,
            width: 960, height: 1080,
            opacity: 200,
            compositingMode: .alphaBlend
        )

        XCTAssertEqual(compositor.layers.count, 2)

        let compositionBox = compositor.toCompositionBox()
        XCTAssertEqual(compositionBox.width, 1920)
        XCTAssertEqual(compositionBox.height, 1080)
        XCTAssertEqual(compositionBox.instructions.count, 2)

        let headers = compositor.toLayerHeaders()
        XCTAssertEqual(headers.count, 2)
        // First layer is fully opaque, no opacity box
        XCTAssertNil(headers[0].opacity)
        // Second layer has opacity < 255
        XCTAssertNotNil(headers[1].opacity)
        XCTAssertEqual(headers[1].opacity?.opacity, 200)
    }

    func testMultiLayerCompositorValidation() {
        // Empty layers
        let emptyCompositor = J2KMultiLayerCompositor(
            canvasWidth: 1920,
            canvasHeight: 1080
        )
        XCTAssertThrowsError(try emptyCompositor.validate())

        // Zero canvas dimensions
        var zeroDimCompositor = J2KMultiLayerCompositor(
            canvasWidth: 0,
            canvasHeight: 1080
        )
        zeroDimCompositor.addLayer(
            codestreamIndex: 0,
            x: 0, y: 0,
            width: 960, height: 1080,
            opacity: 255,
            compositingMode: .replace
        )
        XCTAssertThrowsError(try zeroDimCompositor.validate())

        // Valid compositor
        var validCompositor = J2KMultiLayerCompositor(
            canvasWidth: 1920,
            canvasHeight: 1080
        )
        validCompositor.addLayer(
            codestreamIndex: 0,
            x: 0, y: 0,
            width: 1920, height: 1080,
            opacity: 255,
            compositingMode: .replace
        )
        XCTAssertNoThrow(try validCompositor.validate())
    }

    // MARK: - Box Writer/Reader Round-Trip Tests

    func testIPRBoxWithBoxWriter() throws {
        let box = J2KIPRBox(data: Data([0x01, 0x02, 0x03]))

        var writer = J2KBoxWriter()
        try writer.writeBox(box)
        let fullData = writer.data

        XCTAssertGreaterThan(fullData.count, 8)

        var reader = J2KBoxReader(data: fullData)
        let boxInfo = try reader.readNextBox()

        XCTAssertNotNil(boxInfo)
        XCTAssertEqual(boxInfo?.type, .jp2i)

        let content = reader.extractContent(from: boxInfo!)
        var readBox = J2KIPRBox()
        try readBox.read(from: content)

        XCTAssertEqual(readBox.data, Data([0x01, 0x02, 0x03]))
    }

    func testDigitalSignatureBoxReadTooShort() {
        var box = J2KDigitalSignatureBox()
        XCTAssertThrowsError(try box.read(from: Data([0x02])))
    }

    func testROIDescriptionBoxReadTooShort() {
        var box = J2KROIDescriptionBox()
        XCTAssertThrowsError(try box.read(from: Data([0x00])))
    }

    func testCrossReferenceBoxReadTooShort() {
        var box = try! J2KCrossReferenceBox(referenceType: .url, reference: "x")
        XCTAssertThrowsError(try box.read(from: Data()))
    }

    func testNumberListBoxReadInvalidSize() {
        // 5 bytes is not a multiple of 6
        var box = J2KNumberListBox()
        XCTAssertThrowsError(try box.read(from: Data([0x00, 0x00, 0x00, 0x00, 0x00])))
    }

    func testReaderRequirementsBoxReadEmpty() {
        var box = J2KReaderRequirementsBox()
        XCTAssertThrowsError(try box.read(from: Data()))
    }

    func testInstructionSetBoxReadTooShort() {
        var box = J2KInstructionSetBox()
        XCTAssertThrowsError(try box.read(from: Data([0x00, 0x00])))
    }
}
