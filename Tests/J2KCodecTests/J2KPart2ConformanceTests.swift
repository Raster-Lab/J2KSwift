// J2KPart2ConformanceTests.swift
// J2KSwift
//
// Conformance tests for Part 2 codestream marker extensions and
// file format integration per ISO/IEC 15444-2.

import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for Part 2 codestream marker extensions.
final class J2KPart2ConformanceTests: XCTestCase {

    // MARK: - Part 2 Rsiz Capability Tests

    func testDefaultConfigProducesPart1Rsiz() throws {
        let config = J2KEncodingConfiguration()
        let caps = J2KPart2Capabilities(configuration: config)

        XCTAssertEqual(caps.rsizValue, 0x0000)
        XCTAssertFalse(caps.requiresPart2)
        XCTAssertFalse(caps.requiresHTJ2K)
    }

    func testHTJ2KConfigSetsHTJ2KFlag() throws {
        let config = J2KEncodingConfiguration(useHTJ2K: true)
        let caps = J2KPart2Capabilities(configuration: config)

        XCTAssertTrue(caps.requiresHTJ2K)
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.htj2kFlag) != 0)
        XCTAssertFalse(caps.requiresPart2)
    }

    func testDCOffsetConfigSetsPart2Flag() throws {
        let config = J2KEncodingConfiguration(
            dcOffsetConfiguration: .naturalImage
        )
        let caps = J2KPart2Capabilities(configuration: config)

        XCTAssertTrue(caps.requiresPart2)
        XCTAssertTrue(caps.usesDCOffset)
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.part2Flag) != 0)
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.dcOffsetBit) != 0)
    }

    func testExtendedPrecisionConfigSetsPart2Flag() throws {
        let config = J2KEncodingConfiguration(
            extendedPrecisionConfiguration: .highPrecision
        )
        let caps = J2KPart2Capabilities(configuration: config)

        XCTAssertTrue(caps.requiresPart2)
        XCTAssertTrue(caps.usesExtendedPrecision)
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.extendedPrecisionBit) != 0)
    }

    func testArbitraryWaveletsSetsPart2Flag() throws {
        let kernel = J2KWaveletKernelLibrary.haar
        let config = J2KEncodingConfiguration(
            waveletKernelConfiguration: .arbitrary(kernel: kernel)
        )
        let caps = J2KPart2Capabilities(configuration: config)

        XCTAssertTrue(caps.requiresPart2)
        XCTAssertTrue(caps.usesArbitraryWavelets)
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.arbitraryWaveletsBit) != 0)
    }

    func testCombinedPart2FeaturesSetMultipleBits() throws {
        let config = J2KEncodingConfiguration(
            dcOffsetConfiguration: .naturalImage,
            extendedPrecisionConfiguration: .highPrecision,
            waveletKernelConfiguration: .arbitrary(kernel: J2KWaveletKernelLibrary.haar)
        )
        let caps = J2KPart2Capabilities(configuration: config)

        XCTAssertTrue(caps.requiresPart2)
        XCTAssertTrue(caps.usesDCOffset)
        XCTAssertTrue(caps.usesExtendedPrecision)
        XCTAssertTrue(caps.usesArbitraryWavelets)

        // All three bits should be set
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.dcOffsetBit) != 0)
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.extendedPrecisionBit) != 0)
        XCTAssertTrue((caps.rsizValue & J2KPart2Capabilities.arbitraryWaveletsBit) != 0)
    }

    func testPart2WithHTJ2KSetsBothFlags() throws {
        let config = J2KEncodingConfiguration(
            useHTJ2K: true,
            dcOffsetConfiguration: .naturalImage
        )
        let caps = J2KPart2Capabilities(configuration: config)

        XCTAssertTrue(caps.requiresPart2)
        XCTAssertTrue(caps.requiresHTJ2K)
    }

    func testRsizValueFromRawValue() throws {
        let caps = J2KPart2Capabilities(rsizValue: 0x8011)

        XCTAssertTrue(caps.requiresPart2)
        XCTAssertTrue(caps.usesMCT)
        XCTAssertTrue(caps.usesDCOffset)
        XCTAssertFalse(caps.requiresHTJ2K)
        XCTAssertFalse(caps.usesArbitraryWavelets)
    }

    func testFeatureDescriptionsForPart2Config() throws {
        let config = J2KEncodingConfiguration(
            dcOffsetConfiguration: .naturalImage
        )
        let caps = J2KPart2Capabilities(configuration: config)

        let descriptions = caps.featureDescriptions
        XCTAssertTrue(descriptions.contains("Part 2 Extensions"))
        XCTAssertTrue(descriptions.contains("DC Offset"))
    }

    func testFeatureDescriptionsForBaseline() throws {
        let config = J2KEncodingConfiguration()
        let caps = J2KPart2Capabilities(configuration: config)

        let descriptions = caps.featureDescriptions
        XCTAssertTrue(descriptions.isEmpty)
    }

    // MARK: - Part 2 Coding Extensions Tests

    func testDefaultCodingExtensionsHasNoExtensions() throws {
        let config = J2KEncodingConfiguration()
        let ext = J2KPart2CodingExtensions(configuration: config)

        XCTAssertFalse(ext.hasPart2Extensions)
        XCTAssertFalse(ext.usesArbitraryDecomposition)
        XCTAssertFalse(ext.usesMultiComponentCoding)
        XCTAssertTrue(ext.extendedPrecinctSizes.isEmpty)
    }

    func testArbitraryWaveletCodingExtension() throws {
        let config = J2KEncodingConfiguration(
            waveletKernelConfiguration: .arbitrary(kernel: J2KWaveletKernelLibrary.haar)
        )
        let ext = J2KPart2CodingExtensions(configuration: config)

        XCTAssertTrue(ext.usesArbitraryDecomposition)
        XCTAssertTrue(ext.hasPart2Extensions)
    }

    func testManualCodingExtensionConstruction() throws {
        let ext = J2KPart2CodingExtensions(
            usesArbitraryDecomposition: true,
            usesMultiComponentCoding: true,
            extendedPrecinctSizes: [
                .init(level: 0, widthExponent: 7, heightExponent: 7),
                .init(level: 1, widthExponent: 6, heightExponent: 6)
            ]
        )

        XCTAssertTrue(ext.hasPart2Extensions)
        XCTAssertTrue(ext.usesArbitraryDecomposition)
        XCTAssertTrue(ext.usesMultiComponentCoding)
        XCTAssertEqual(ext.extendedPrecinctSizes.count, 2)
    }

    func testExtendedScodBitsForPrecinctSizes() throws {
        let ext = J2KPart2CodingExtensions(
            extendedPrecinctSizes: [
                .init(level: 0, widthExponent: 7, heightExponent: 7)
            ]
        )

        XCTAssertEqual(ext.extendedScodBits & 0x01, 0x01)
    }

    func testExtendedScodBitsForNoExtensions() throws {
        let ext = J2KPart2CodingExtensions()

        XCTAssertEqual(ext.extendedScodBits, 0x00)
    }

    // MARK: - Part 2 Quantization Extensions Tests

    func testDefaultQuantizationExtensions() throws {
        let config = J2KEncodingConfiguration()
        let ext = J2KPart2QuantizationExtensions(configuration: config)

        XCTAssertEqual(ext.extendedGuardBits, 2)
        XCTAssertFalse(ext.usesTrellisQuantization)
        XCTAssertFalse(ext.usesDeadzoneAdjustment)
        XCTAssertFalse(ext.hasPart2Extensions)
    }

    func testExtendedPrecisionGuardBits() throws {
        let config = J2KEncodingConfiguration(
            extendedPrecisionConfiguration: .highPrecision
        )
        let ext = J2KPart2QuantizationExtensions(configuration: config)

        XCTAssertTrue(ext.extendedGuardBits >= 2)
    }

    func testSqcdEncodingForLossless() throws {
        let ext = J2KPart2QuantizationExtensions(extendedGuardBits: 2)
        let sqcd = ext.encodeSqcd(quantizationStyle: 0x00)

        // Guard bits 2 in bits 5-7: 010 << 5 = 0x40, style 0 => 0x40
        XCTAssertEqual(sqcd, 0x40)
    }

    func testSqcdEncodingForLossy() throws {
        let ext = J2KPart2QuantizationExtensions(extendedGuardBits: 2)
        let sqcd = ext.encodeSqcd(quantizationStyle: 0x02)

        // Guard bits 2 in bits 5-7: 010 << 5 = 0x40, style 2 => 0x42
        XCTAssertEqual(sqcd, 0x42)
    }

    func testSqcdEncodingWithExtendedGuardBits() throws {
        // Extended guard bits > 7 are clamped to 7 in Sqcd byte
        let ext = J2KPart2QuantizationExtensions(extendedGuardBits: 10)
        let sqcd = ext.encodeSqcd(quantizationStyle: 0x00)

        // Guard bits clamped to 7: 111 << 5 = 0xE0
        XCTAssertEqual(sqcd, 0xE0)
        XCTAssertTrue(ext.hasPart2Extensions)
    }

    func testManualQuantizationExtensionConstruction() throws {
        let ext = J2KPart2QuantizationExtensions(
            extendedGuardBits: 5,
            usesTrellisQuantization: true,
            usesDeadzoneAdjustment: false
        )

        XCTAssertEqual(ext.extendedGuardBits, 5)
        XCTAssertTrue(ext.usesTrellisQuantization)
        XCTAssertFalse(ext.usesDeadzoneAdjustment)
    }

    func testGuardBitsClamping() throws {
        let ext = J2KPart2QuantizationExtensions(extendedGuardBits: 20)

        // Clamped to maximum 15
        XCTAssertEqual(ext.extendedGuardBits, 15)
    }

    // MARK: - Encoder Pipeline Integration Tests

    func testEncoderProducesPart1SIZForDefault() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)

        // Verify SOC marker
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x4F)

        // Verify SIZ marker follows
        XCTAssertEqual(data[2], 0xFF)
        XCTAssertEqual(data[3], 0x51)

        // Read SIZ segment length (2 bytes after marker)
        let sizLen = Int(data[4]) << 8 | Int(data[5])
        XCTAssertTrue(sizLen > 0)

        // Rsiz is first 2 bytes of SIZ segment content (after length field)
        let rsiz = UInt16(data[6]) << 8 | UInt16(data[7])

        // Default config should produce Part 1 Rsiz (0x0000)
        XCTAssertEqual(rsiz, 0x0000)
    }

    func testEncoderProducesPart2SIZForDCOffset() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2,
            dcOffsetConfiguration: .naturalImage
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)

        // Rsiz is first 2 bytes of SIZ segment content (after SOC + SIZ marker + length)
        let rsiz = UInt16(data[6]) << 8 | UInt16(data[7])

        // Should have Part 2 flag (bit 15) and DC offset bit (bit 4) set
        XCTAssertTrue((rsiz & J2KPart2Capabilities.part2Flag) != 0)
        XCTAssertTrue((rsiz & J2KPart2Capabilities.dcOffsetBit) != 0)
    }

    func testEncoderProducesHTJ2KRsiz() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2,
            useHTJ2K: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)

        // Rsiz is first 2 bytes of SIZ segment content
        let rsiz = UInt16(data[6]) << 8 | UInt16(data[7])

        // Should have HTJ2K flag (bit 14) set
        XCTAssertTrue((rsiz & J2KPart2Capabilities.htj2kFlag) != 0)
    }

    // MARK: - Capabilities Equality Tests

    func testCapabilitiesEquality() throws {
        let caps1 = J2KPart2Capabilities(rsizValue: 0x8001)
        let caps2 = J2KPart2Capabilities(rsizValue: 0x8001)
        let caps3 = J2KPart2Capabilities(rsizValue: 0x0000)

        XCTAssertEqual(caps1, caps2)
        XCTAssertNotEqual(caps1, caps3)
    }

    func testCodingExtensionsEquality() throws {
        let ext1 = J2KPart2CodingExtensions(usesArbitraryDecomposition: true)
        let ext2 = J2KPart2CodingExtensions(usesArbitraryDecomposition: true)
        let ext3 = J2KPart2CodingExtensions(usesArbitraryDecomposition: false)

        XCTAssertEqual(ext1, ext2)
        XCTAssertNotEqual(ext1, ext3)
    }

    func testQuantizationExtensionsEquality() throws {
        let ext1 = J2KPart2QuantizationExtensions(extendedGuardBits: 5)
        let ext2 = J2KPart2QuantizationExtensions(extendedGuardBits: 5)
        let ext3 = J2KPart2QuantizationExtensions(extendedGuardBits: 2)

        XCTAssertEqual(ext1, ext2)
        XCTAssertNotEqual(ext1, ext3)
    }
}
