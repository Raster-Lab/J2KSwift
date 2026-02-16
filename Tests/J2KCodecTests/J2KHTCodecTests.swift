import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for the HTJ2K (High-Throughput JPEG 2000) block coder and codec.
final class J2KHTCodecTests: XCTestCase {

    // MARK: - HTCodingMode Tests

    func testHTCodingModeEquality() throws {
        XCTAssertEqual(HTCodingMode.ht, HTCodingMode.ht)
        XCTAssertEqual(HTCodingMode.legacy, HTCodingMode.legacy)
        XCTAssertNotEqual(HTCodingMode.ht, HTCodingMode.legacy)
    }

    // MARK: - HTCodingPassType Tests

    func testHTCodingPassTypes() throws {
        let cleanup = HTCodingPassType.htCleanup
        let sigProp = HTCodingPassType.htSigProp
        let magRef = HTCodingPassType.htMagRef

        XCTAssertEqual(cleanup, .htCleanup)
        XCTAssertEqual(sigProp, .htSigProp)
        XCTAssertEqual(magRef, .htMagRef)
        XCTAssertNotEqual(cleanup, sigProp)
    }

    // MARK: - MEL Coder Tests

    func testMELCoderInitialization() throws {
        let mel = HTMELCoder()
        XCTAssertNotNil(mel)
    }

    func testMELCoderEncodeFlush() throws {
        var mel = HTMELCoder()
        mel.encode(bit: 0)
        mel.encode(bit: 0)
        mel.encode(bit: 1)
        let data = mel.flush()
        XCTAssertFalse(data.isEmpty, "MEL coder should produce output data")
    }

    func testMELCoderAllZeros() throws {
        var mel = HTMELCoder()
        for _ in 0..<8 {
            mel.encode(bit: 0)
        }
        let data = mel.flush()
        XCTAssertFalse(data.isEmpty, "MEL coder should produce data for all-zero input")
    }

    func testMELCoderAllOnes() throws {
        var mel = HTMELCoder()
        for _ in 0..<8 {
            mel.encode(bit: 1)
        }
        let data = mel.flush()
        XCTAssertFalse(data.isEmpty, "MEL coder should produce data for all-one input")
    }

    // MARK: - VLC Coder Tests

    func testVLCCoderInitialization() throws {
        let vlc = HTVLCCoder()
        XCTAssertNotNil(vlc)
    }

    func testVLCCoderEncodeSignificancePatterns() throws {
        var vlc = HTVLCCoder()

        // Encode all four significance patterns
        vlc.encodeSignificance(pattern: 0) // Neither significant
        vlc.encodeSignificance(pattern: 1) // Second significant
        vlc.encodeSignificance(pattern: 2) // First significant
        vlc.encodeSignificance(pattern: 3) // Both significant

        let data = vlc.flush()
        XCTAssertFalse(data.isEmpty, "VLC coder should produce output for significance patterns")
    }

    func testVLCCoderEncodeSign() throws {
        var vlc = HTVLCCoder()
        vlc.encodeSign(0) // Positive
        vlc.encodeSign(1) // Negative
        let data = vlc.flush()
        XCTAssertFalse(data.isEmpty, "VLC coder should produce output for sign bits")
    }

    // MARK: - MagSgn Coder Tests

    func testMagSgnCoderInitialization() throws {
        let magsgn = HTMagSgnCoder()
        XCTAssertNotNil(magsgn)
    }

    func testMagSgnCoderEncode() throws {
        var magsgn = HTMagSgnCoder()
        magsgn.encode(magnitude: 5, sign: 0, bitPlane: 3)
        magsgn.encode(magnitude: 3, sign: 1, bitPlane: 3)
        let data = magsgn.flush()
        XCTAssertFalse(data.isEmpty, "MagSgn coder should produce output")
    }

    func testMagSgnCoderZeroMagnitude() throws {
        var magsgn = HTMagSgnCoder()
        magsgn.encode(magnitude: 0, sign: 0, bitPlane: 3) // Should be a no-op
        let data = magsgn.flush()
        // Zero magnitude should produce no data (guarded by the magnitude > 0 check)
        XCTAssertTrue(data.isEmpty, "Zero magnitude should not produce output")
    }

    // MARK: - HT Block Encoder Tests

    func testHTBlockEncoderInitialization() throws {
        let encoder = HTBlockEncoder(width: 32, height: 32, subband: .hh)
        XCTAssertEqual(encoder.width, 32)
        XCTAssertEqual(encoder.height, 32)
        XCTAssertEqual(encoder.subband, .hh)
    }

    func testHTBlockEncoderCleanupPassZeroCoefficients() throws {
        let encoder = HTBlockEncoder(width: 4, height: 4, subband: .ll)
        let coefficients = [Int](repeating: 0, count: 16)
        let result = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 0)

        XCTAssertEqual(result.passType, .htCleanup)
        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 4)
    }

    func testHTBlockEncoderCleanupPassNonZeroCoefficients() throws {
        let encoder = HTBlockEncoder(width: 4, height: 4, subband: .hh)
        var coefficients = [Int](repeating: 0, count: 16)
        coefficients[0] = 128
        coefficients[5] = -64
        coefficients[10] = 32

        let result = try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 7)

        XCTAssertEqual(result.passType, .htCleanup)
        XCTAssertFalse(result.codedData.isEmpty, "Non-zero coefficients should produce coded data")
    }

    func testHTBlockEncoderCoefficientCountMismatch() throws {
        let encoder = HTBlockEncoder(width: 4, height: 4, subband: .ll)
        let coefficients = [Int](repeating: 0, count: 8) // Wrong count

        XCTAssertThrowsError(try encoder.encodeCleanup(coefficients: coefficients, bitPlane: 0)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }

    func testHTBlockEncoderSigPropPass() throws {
        let encoder = HTBlockEncoder(width: 4, height: 4, subband: .hh)
        var coefficients = [Int](repeating: 0, count: 16)
        coefficients[0] = 10
        coefficients[1] = -5
        coefficients[4] = 3

        var sigState = [Bool](repeating: false, count: 16)
        sigState[0] = true // One sample already significant

        let data = try encoder.encodeSigProp(
            coefficients: coefficients,
            significanceState: sigState,
            bitPlane: 1
        )
        // Should produce some data since there are neighbors of significant samples
        XCTAssertNotNil(data)
    }

    func testHTBlockEncoderMagRefPass() throws {
        let encoder = HTBlockEncoder(width: 4, height: 4, subband: .hh)
        var coefficients = [Int](repeating: 0, count: 16)
        coefficients[0] = 10
        coefficients[5] = -7

        var sigState = [Bool](repeating: false, count: 16)
        sigState[0] = true
        sigState[5] = true

        let data = try encoder.encodeMagRef(
            coefficients: coefficients,
            significanceState: sigState,
            bitPlane: 1
        )
        XCTAssertNotNil(data)
    }

    // MARK: - HT Block Decoder Tests

    func testHTBlockDecoderInitialization() throws {
        let decoder = HTBlockDecoder(width: 32, height: 32, subband: .hh)
        XCTAssertEqual(decoder.width, 32)
        XCTAssertEqual(decoder.height, 32)
        XCTAssertEqual(decoder.subband, .hh)
    }

    func testHTBlockDecoderWrongPassType() throws {
        let decoder = HTBlockDecoder(width: 4, height: 4, subband: .ll)
        let block = HTEncodedBlock(
            codedData: Data(),
            passType: .htSigProp, // Wrong pass type
            melLength: 0,
            vlcLength: 0,
            magsgnLength: 0,
            bitPlane: 0,
            width: 4,
            height: 4
        )

        XCTAssertThrowsError(try decoder.decodeCleanup(from: block))
    }

    // MARK: - HTEncodedBlock Tests

    func testHTEncodedBlockCreation() throws {
        let block = HTEncodedBlock(
            codedData: Data([0x01, 0x02, 0x03]),
            passType: .htCleanup,
            melLength: 1,
            vlcLength: 1,
            magsgnLength: 1,
            bitPlane: 7,
            width: 32,
            height: 32
        )

        XCTAssertEqual(block.codedData.count, 3)
        XCTAssertEqual(block.passType, .htCleanup)
        XCTAssertEqual(block.melLength, 1)
        XCTAssertEqual(block.vlcLength, 1)
        XCTAssertEqual(block.magsgnLength, 1)
        XCTAssertEqual(block.bitPlane, 7)
        XCTAssertEqual(block.width, 32)
        XCTAssertEqual(block.height, 32)
    }

    // MARK: - HTJ2K Configuration Tests

    func testHTJ2KConfigurationDefault() throws {
        let config = HTJ2KConfiguration.default
        XCTAssertEqual(config.codingMode, .ht)
        XCTAssertFalse(config.allowMixedMode)
        XCTAssertEqual(config.quality, 0.9, accuracy: 0.001)
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.qualityLayers, 1)
        XCTAssertEqual(config.decompositionLevels, 5)
        XCTAssertEqual(config.codeBlockWidth, 64)
        XCTAssertEqual(config.codeBlockHeight, 64)
    }

    func testHTJ2KConfigurationLossless() throws {
        let config = HTJ2KConfiguration.lossless
        XCTAssertTrue(config.lossless)
        XCTAssertEqual(config.codingMode, .ht)
    }

    func testHTJ2KConfigurationMaxThroughput() throws {
        let config = HTJ2KConfiguration.maxThroughput
        XCTAssertEqual(config.qualityLayers, 1)
        XCTAssertEqual(config.codeBlockWidth, 64)
        XCTAssertEqual(config.codeBlockHeight, 64)
    }

    func testHTJ2KConfigurationLegacyCompatible() throws {
        let config = HTJ2KConfiguration.legacyCompatible
        XCTAssertEqual(config.codingMode, .legacy)
    }

    func testHTJ2KConfigurationQualityClamping() throws {
        let configLow = HTJ2KConfiguration(quality: -0.5)
        XCTAssertEqual(configLow.quality, 0.0, accuracy: 0.001)

        let configHigh = HTJ2KConfiguration(quality: 1.5)
        XCTAssertEqual(configHigh.quality, 1.0, accuracy: 0.001)
    }

    func testHTJ2KConfigurationBlockSizeClamping() throws {
        let config = HTJ2KConfiguration(codeBlockWidth: 3, codeBlockHeight: 5)
        XCTAssertEqual(config.codeBlockWidth, 4) // Rounded up to power of 2
        XCTAssertTrue(config.codeBlockHeight >= 4) // At least 4
    }

    func testHTJ2KConfigurationCustom() throws {
        let config = HTJ2KConfiguration(
            codingMode: .ht,
            allowMixedMode: true,
            quality: 0.75,
            lossless: false,
            qualityLayers: 3,
            decompositionLevels: 4,
            codeBlockWidth: 32,
            codeBlockHeight: 32
        )
        XCTAssertEqual(config.codingMode, .ht)
        XCTAssertTrue(config.allowMixedMode)
        XCTAssertEqual(config.quality, 0.75, accuracy: 0.001)
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.qualityLayers, 3)
        XCTAssertEqual(config.decompositionLevels, 4)
        XCTAssertEqual(config.codeBlockWidth, 32)
        XCTAssertEqual(config.codeBlockHeight, 32)
    }

    // MARK: - HTJ2K Encoder Tests

    func testHTJ2KEncoderInitialization() throws {
        let encoder = HTJ2KEncoder()
        XCTAssertEqual(encoder.configuration.codingMode, .ht)
    }

    func testHTJ2KEncoderWithCustomConfig() throws {
        let config = HTJ2KConfiguration(codingMode: .legacy, quality: 0.5)
        let encoder = HTJ2KEncoder(configuration: config)
        XCTAssertEqual(encoder.configuration.codingMode, .legacy)
        XCTAssertEqual(encoder.configuration.quality, 0.5, accuracy: 0.001)
    }

    func testHTJ2KEncoderEmptyCoefficients() throws {
        let encoder = HTJ2KEncoder()
        XCTAssertThrowsError(
            try encoder.encodeCodeBlocks(coefficients: [], width: 4, height: 4, subband: .hh)
        )
    }

    func testHTJ2KEncoderInvalidDimensions() throws {
        let encoder = HTJ2KEncoder()
        XCTAssertThrowsError(
            try encoder.encodeCodeBlocks(coefficients: [1, 2, 3], width: 0, height: 4, subband: .hh)
        )
    }

    func testHTJ2KEncoderHTMode() throws {
        let encoder = HTJ2KEncoder(configuration: .default)
        let coefficients = [Int](repeating: 0, count: 16)

        let result = try encoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: 4, height: 4, subband: .hh
        )

        XCTAssertEqual(result.codingMode, .ht)
        XCTAssertEqual(result.cleanupPass.passType, .htCleanup)
        XCTAssertGreaterThanOrEqual(result.totalPasses, 1)
    }

    func testHTJ2KEncoderHTModeNonZero() throws {
        let encoder = HTJ2KEncoder(configuration: .default)
        var coefficients = [Int](repeating: 0, count: 16)
        coefficients[0] = 100
        coefficients[3] = -50
        coefficients[8] = 25
        coefficients[15] = -12

        let result = try encoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: 4, height: 4, subband: .hh
        )

        XCTAssertEqual(result.codingMode, .ht)
        XCTAssertFalse(result.cleanupPass.codedData.isEmpty)
    }

    func testHTJ2KEncoderLegacyMode() throws {
        let encoder = HTJ2KEncoder(configuration: .legacyCompatible)
        let coefficients = [Int](repeating: 0, count: 16)

        let result = try encoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: 4, height: 4, subband: .ll
        )

        XCTAssertEqual(result.codingMode, .legacy)
    }

    // MARK: - HTJ2K Decoder Tests

    func testHTJ2KDecoderInitialization() throws {
        let decoder = HTJ2KDecoder()
        XCTAssertNotNil(decoder)
    }

    func testHTJ2KDecoderHTModeZeroCoefficients() throws {
        let encoder = HTJ2KEncoder(configuration: .default)
        let decoder = HTJ2KDecoder()
        let coefficients = [Int](repeating: 0, count: 16)

        let encoded = try encoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: 4, height: 4, subband: .hh
        )

        let decoded = try decoder.decodeCodeBlocks(
            from: encoded,
            width: 4, height: 4, subband: .hh
        )

        XCTAssertEqual(decoded.count, 16)
        // All zero coefficients should decode to all zeros
        for value in decoded {
            XCTAssertEqual(value, 0)
        }
    }

    // MARK: - CAP Marker Tests

    func testCAPMarkerGeneration() throws {
        let encoder = HTJ2KEncoder(configuration: .default)
        let capData = encoder.generateCAPMarkerData()

        XCTAssertFalse(capData.isEmpty, "CAP marker data should not be empty")
        XCTAssertGreaterThanOrEqual(capData.count, 4, "CAP must have at least 4 bytes for Pcap")
    }

    func testCAPMarkerLegacyMode() throws {
        let encoder = HTJ2KEncoder(configuration: .legacyCompatible)
        let capData = encoder.generateCAPMarkerData()

        // Legacy mode should not set the HT capability bit
        XCTAssertEqual(capData.count, 4, "Legacy mode should only have Pcap without Ccap")
    }

    func testCAPMarkerMixedMode() throws {
        let config = HTJ2KConfiguration(allowMixedMode: true)
        let encoder = HTJ2KEncoder(configuration: config)
        let capData = encoder.generateCAPMarkerData()

        XCTAssertGreaterThan(capData.count, 4, "Mixed mode should include Ccap extension")
    }

    func testCAPMarkerParsing() throws {
        let encoder = HTJ2KEncoder(configuration: .default)
        let capData = encoder.generateCAPMarkerData()

        let decoder = HTJ2KDecoder()
        let (htSupported, mixedMode) = try decoder.parseCAPMarker(data: capData)

        XCTAssertTrue(htSupported, "HT mode should be detected")
        XCTAssertFalse(mixedMode, "Mixed mode should not be set by default")
    }

    func testCAPMarkerParsingMixedMode() throws {
        let config = HTJ2KConfiguration(allowMixedMode: true)
        let encoder = HTJ2KEncoder(configuration: config)
        let capData = encoder.generateCAPMarkerData()

        let decoder = HTJ2KDecoder()
        let (htSupported, mixedMode) = try decoder.parseCAPMarker(data: capData)

        XCTAssertTrue(htSupported)
        XCTAssertTrue(mixedMode, "Mixed mode should be detected")
    }

    func testCAPMarkerParsingTooShort() throws {
        let decoder = HTJ2KDecoder()
        XCTAssertThrowsError(try decoder.parseCAPMarker(data: Data([0x00, 0x01])))
    }

    // MARK: - Marker Segment Tests

    func testCAPMarkerExists() throws {
        XCTAssertEqual(J2KMarker.cap.rawValue, 0xFF50)
        XCTAssertEqual(J2KMarker.cap.name, "CAP (Extended capabilities)")
        XCTAssertTrue(J2KMarker.cap.hasSegment)
        XCTAssertTrue(J2KMarker.cap.canAppearInMainHeader)
    }

    func testCPFMarkerExists() throws {
        XCTAssertEqual(J2KMarker.cpf.rawValue, 0xFF59)
        XCTAssertEqual(J2KMarker.cpf.name, "CPF (Corresponding profile)")
        XCTAssertTrue(J2KMarker.cpf.hasSegment)
        XCTAssertTrue(J2KMarker.cpf.canAppearInMainHeader)
    }

    // MARK: - CPF Marker Tests

    func testCPFMarkerGenerationHTJ2KLossless() throws {
        let encoder = HTJ2KEncoder(configuration: .lossless)
        let cpfData = encoder.generateCPFMarkerData()

        XCTAssertEqual(cpfData.count, 2, "CPF marker should have exactly 2 bytes (Pcpf)")
        
        // Extract Pcpf
        let pcpf = UInt16(cpfData[0]) << 8 | UInt16(cpfData[1])
        
        // Bit 15 should be 1 for HTJ2K
        XCTAssertTrue((pcpf & 0x8000) != 0, "Bit 15 should be set for HTJ2K profile")
        
        // Profile number should be 0 for lossless
        let profile = Int(pcpf & 0x7FFF)
        XCTAssertEqual(profile, 0, "Lossless HTJ2K should use profile 0")
    }

    func testCPFMarkerGenerationHTJ2KLossy() throws {
        let config = HTJ2KConfiguration(codingMode: .ht, quality: 0.8, lossless: false)
        let encoder = HTJ2KEncoder(configuration: config)
        let cpfData = encoder.generateCPFMarkerData()

        XCTAssertEqual(cpfData.count, 2, "CPF marker should have exactly 2 bytes")
        
        let pcpf = UInt16(cpfData[0]) << 8 | UInt16(cpfData[1])
        
        // Bit 15 should be 1 for HTJ2K
        XCTAssertTrue((pcpf & 0x8000) != 0, "Bit 15 should be set for HTJ2K profile")
        
        // Profile number should be 1 for lossy
        let profile = Int(pcpf & 0x7FFF)
        XCTAssertEqual(profile, 1, "Lossy HTJ2K should use profile 1")
    }

    func testCPFMarkerGenerationLegacyLossless() throws {
        let config = HTJ2KConfiguration(codingMode: .legacy, lossless: true)
        let encoder = HTJ2KEncoder(configuration: config)
        let cpfData = encoder.generateCPFMarkerData()

        XCTAssertEqual(cpfData.count, 2, "CPF marker should have exactly 2 bytes")
        
        let pcpf = UInt16(cpfData[0]) << 8 | UInt16(cpfData[1])
        
        // Bit 15 should be 0 for legacy
        XCTAssertTrue((pcpf & 0x8000) == 0, "Bit 15 should NOT be set for legacy profile")
        
        // Profile number should be 0 for lossless
        let profile = Int(pcpf & 0x7FFF)
        XCTAssertEqual(profile, 0, "Lossless legacy should use profile 0")
    }

    func testCPFMarkerGenerationLegacyLossy() throws {
        let config = HTJ2KConfiguration(codingMode: .legacy, lossless: false)
        let encoder = HTJ2KEncoder(configuration: config)
        let cpfData = encoder.generateCPFMarkerData()

        XCTAssertEqual(cpfData.count, 2, "CPF marker should have exactly 2 bytes")
        
        let pcpf = UInt16(cpfData[0]) << 8 | UInt16(cpfData[1])
        
        // Bit 15 should be 0 for legacy
        XCTAssertTrue((pcpf & 0x8000) == 0, "Bit 15 should NOT be set for legacy profile")
        
        // Profile number should be 1 for lossy
        let profile = Int(pcpf & 0x7FFF)
        XCTAssertEqual(profile, 1, "Lossy legacy should use profile 1")
    }

    func testCPFMarkerParsingHTJ2KLossless() throws {
        let decoder = HTJ2KDecoder()
        
        // Construct CPF data for HTJ2K lossless (profile 0)
        // Bit 15 = 1 (HTJ2K), Profile = 0
        let pcpf: UInt16 = 0x8000 | 0x0000
        var cpfData = Data()
        cpfData.append(UInt8((pcpf >> 8) & 0xFF))
        cpfData.append(UInt8(pcpf & 0xFF))
        
        let result = try decoder.parseCPFMarker(data: cpfData)
        
        XCTAssertTrue(result.isHTJ2K, "Should detect HTJ2K profile")
        XCTAssertEqual(result.profileNumber, 0, "Should extract profile 0")
        XCTAssertTrue(result.lossless, "Profile 0 should indicate lossless")
    }

    func testCPFMarkerParsingHTJ2KLossy() throws {
        let decoder = HTJ2KDecoder()
        
        // Construct CPF data for HTJ2K lossy (profile 1)
        let pcpf: UInt16 = 0x8000 | 0x0001
        var cpfData = Data()
        cpfData.append(UInt8((pcpf >> 8) & 0xFF))
        cpfData.append(UInt8(pcpf & 0xFF))
        
        let result = try decoder.parseCPFMarker(data: cpfData)
        
        XCTAssertTrue(result.isHTJ2K, "Should detect HTJ2K profile")
        XCTAssertEqual(result.profileNumber, 1, "Should extract profile 1")
        XCTAssertFalse(result.lossless, "Profile 1 should indicate lossy")
    }

    func testCPFMarkerParsingLegacy() throws {
        let decoder = HTJ2KDecoder()
        
        // Construct CPF data for legacy Part 1 profile
        let pcpf: UInt16 = 0x0001 // Bit 15 = 0, Profile = 1
        var cpfData = Data()
        cpfData.append(UInt8((pcpf >> 8) & 0xFF))
        cpfData.append(UInt8(pcpf & 0xFF))
        
        let result = try decoder.parseCPFMarker(data: cpfData)
        
        XCTAssertFalse(result.isHTJ2K, "Should detect legacy profile")
        XCTAssertEqual(result.profileNumber, 1, "Should extract profile 1")
        XCTAssertFalse(result.lossless, "Profile 1 should indicate lossy")
    }

    func testCPFMarkerParsingTooShort() throws {
        let decoder = HTJ2KDecoder()
        let cpfData = Data([0xFF]) // Only 1 byte, need 2
        
        XCTAssertThrowsError(try decoder.parseCPFMarker(data: cpfData)) { error in
            XCTAssertTrue(error is J2KError)
            if case J2KError.decodingError(let message) = error {
                XCTAssertTrue(message.contains("too short"))
            }
        }
    }

    func testCPFMarkerRoundTrip() throws {
        // Test that encoding and then parsing produces the same values
        let configs: [HTJ2KConfiguration] = [
            .lossless,
            .default,
            .legacyCompatible,
            HTJ2KConfiguration(codingMode: .ht, lossless: false)
        ]
        
        let decoder = HTJ2KDecoder()
        
        for config in configs {
            let encoder = HTJ2KEncoder(configuration: config)
            let cpfData = encoder.generateCPFMarkerData()
            let result = try decoder.parseCPFMarker(data: cpfData)
            
            // Verify HTJ2K detection
            let expectedHTJ2K = (config.codingMode == .ht || config.allowMixedMode)
            XCTAssertEqual(result.isHTJ2K, expectedHTJ2K,
                          "HTJ2K detection mismatch for config: \(config.codingMode)")
            
            // Verify lossless detection
            XCTAssertEqual(result.lossless, config.lossless,
                          "Lossless detection mismatch for config")
        }
    }

    // MARK: - Conformance Validator Tests

    func testConformanceValidatorCreation() throws {
        let validator = HTJ2KConformanceValidator()
        XCTAssertNotNil(validator)
    }

    func testConformanceValidatorTooShort() throws {
        let validator = HTJ2KConformanceValidator()
        let result = validator.validate(codestream: Data([0xFF]))
        XCTAssertFalse(result.isValid)
        XCTAssertFalse(result.issues.isEmpty)
    }

    func testConformanceValidatorMissingSOC() throws {
        let validator = HTJ2KConformanceValidator()
        let result = validator.validate(codestream: Data([0x00, 0x00, 0x00, 0x00]))
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains("Missing SOC marker"))
    }

    func testConformanceValidatorEncodedResult() throws {
        let encoder = HTJ2KEncoder()
        let coefficients = [Int](repeating: 0, count: 16)
        let encoded = try encoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: 4, height: 4, subband: .hh
        )

        let validator = HTJ2KConformanceValidator()
        let result = validator.validate(encodedResult: encoded)

        XCTAssertTrue(result.isValid, "Valid encoded result should pass validation. Issues: \(result.issues)")
    }

    func testConformanceValidatorInvalidResult() throws {
        let block = HTEncodedBlock(
            codedData: Data(),
            passType: .htSigProp, // Wrong type for cleanup
            melLength: 0, vlcLength: 0, magsgnLength: 0,
            bitPlane: 0, width: 4, height: 4
        )
        let result = HTEncodedResult(
            codingMode: .ht,
            cleanupPass: block,
            sigPropPasses: [],
            magRefPasses: [],
            zeroBitPlanes: 0,
            totalPasses: 0
        )

        let validator = HTJ2KConformanceValidator()
        let validation = validator.validate(encodedResult: result)
        XCTAssertFalse(validation.isValid)
    }

    // MARK: - ConformanceResult Tests

    func testConformanceResultValid() throws {
        let result = ConformanceResult(isValid: true, issues: [])
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testConformanceResultInvalid() throws {
        let result = ConformanceResult(isValid: false, issues: ["Issue 1", "Issue 2"])
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.issues.count, 2)
    }

    // MARK: - HTEncodedResult Tests

    func testHTEncodedResultCreation() throws {
        let block = HTEncodedBlock(
            codedData: Data([0x01]),
            passType: .htCleanup,
            melLength: 1, vlcLength: 0, magsgnLength: 0,
            bitPlane: 3, width: 4, height: 4
        )
        let result = HTEncodedResult(
            codingMode: .ht,
            cleanupPass: block,
            sigPropPasses: [Data([0x02])],
            magRefPasses: [Data([0x03])],
            zeroBitPlanes: 28,
            totalPasses: 3
        )

        XCTAssertEqual(result.codingMode, .ht)
        XCTAssertEqual(result.sigPropPasses.count, 1)
        XCTAssertEqual(result.magRefPasses.count, 1)
        XCTAssertEqual(result.zeroBitPlanes, 28)
        XCTAssertEqual(result.totalPasses, 3)
    }

    // MARK: - BenchmarkResult Tests

    func testBenchmarkResultSpeedup() throws {
        let result = BenchmarkResult(
            htEncodingTime: 0.001,
            legacyEncodingTime: 0.005,
            iterations: 10,
            blockSize: 1024
        )

        XCTAssertEqual(result.speedup, 5.0, accuracy: 0.01)
        XCTAssertEqual(result.iterations, 10)
        XCTAssertEqual(result.blockSize, 1024)
    }

    func testBenchmarkResultZeroHT() throws {
        let result = BenchmarkResult(
            htEncodingTime: 0.0,
            legacyEncodingTime: 0.005,
            iterations: 1,
            blockSize: 64
        )

        XCTAssertEqual(result.speedup, 0.0)
    }

    // MARK: - Larger Block Encoding Tests

    func testHTEncode8x8Block() throws {
        let encoder = HTJ2KEncoder()
        let size = 64
        var coefficients = [Int](repeating: 0, count: size)
        for i in 0..<size {
            coefficients[i] = (i % 7 == 0) ? (i * 3 - 100) : 0
        }

        let result = try encoder.encodeCodeBlocks(
            coefficients: coefficients,
            width: 8, height: 8, subband: .hl
        )

        XCTAssertEqual(result.codingMode, .ht)
        XCTAssertFalse(result.cleanupPass.codedData.isEmpty)
    }

    func testHTEncodeAllSubbands() throws {
        let encoder = HTJ2KEncoder()
        let coefficients = [Int](repeating: 5, count: 16)

        for subband in [J2KSubband.ll, .hl, .lh, .hh] {
            let result = try encoder.encodeCodeBlocks(
                coefficients: coefficients,
                width: 4, height: 4, subband: subband
            )
            XCTAssertEqual(result.codingMode, .ht)
        }
    }

    // MARK: - Mixed Mode Tests

    func testMixedModeConfiguration() throws {
        let config = HTJ2KConfiguration(codingMode: .ht, allowMixedMode: true)
        XCTAssertTrue(config.allowMixedMode)
        XCTAssertEqual(config.codingMode, .ht)
    }
}
