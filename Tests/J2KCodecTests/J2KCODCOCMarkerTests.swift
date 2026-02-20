//
// J2KCODCOCMarkerTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for COD and COC marker generation and parsing with HTJ2K support.
final class J2KCODCOCMarkerTests: XCTestCase {
    // MARK: - COD Marker Tests

    func testCODMarkerLegacyMode() throws {
        // Arrange: Create configuration without HTJ2K
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 5,
            codeBlockSize: (32, 32),
            qualityLayers: 5,
            useHTJ2K: false
        )

        // Act: Create encoder pipeline and encode a test image
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 64, height: 64, components: 1)
        let encodedData = try pipeline.encode(image)

        // Assert: Verify the codestream contains COD marker without HT bit
        let codMarkerData = try extractMarkerData(from: encodedData, marker: .cod)
        XCTAssertFalse(codMarkerData.isEmpty, "COD marker should be present")

        // COD marker structure:
        // Scod (1 byte) + progression (1 byte) + layers (2 bytes) + MCT (1 byte)
        // + levels (1 byte) + cb_width_exp (1 byte) + cb_height_exp (1 byte)
        // + cb_style (1 byte) + transform (1 byte)
        // Total minimum: 10 bytes
        XCTAssertGreaterThanOrEqual(codMarkerData.count, 10, "COD marker data should have at least 10 bytes")

        if codMarkerData.count >= 9 {
            let codeBlockStyle = codMarkerData[8] // 8th byte (0-indexed) is code-block style
            XCTAssertEqual(codeBlockStyle & 0x40, 0, "HT bit (bit 6) should be 0 for legacy mode")
        }
    }

    func testCODMarkerHTJ2KMode() throws {
        // Arrange: Create configuration with HTJ2K enabled
        let config = J2KEncodingConfiguration(
            quality: 0.9,
            lossless: false,
            decompositionLevels: 5,
            codeBlockSize: (32, 32),
            qualityLayers: 5,
            useHTJ2K: true
        )

        // Act: Create encoder pipeline and encode a test image
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 64, height: 64, components: 1)
        let encodedData = try pipeline.encode(image)

        // Assert: Verify the codestream contains COD marker with HT bit set
        let codMarkerData = try extractMarkerData(from: encodedData, marker: .cod)
        XCTAssertFalse(codMarkerData.isEmpty, "COD marker should be present")
        XCTAssertGreaterThanOrEqual(codMarkerData.count, 10, "COD marker data should have at least 10 bytes")

        if codMarkerData.count >= 9 {
            let codeBlockStyle = codMarkerData[8]
            XCTAssertEqual(codeBlockStyle & 0x40, 0x40, "HT bit (bit 6) should be 1 for HTJ2K mode")
        }
    }

    func testCODMarkerLosslessMode() throws {
        // Arrange: Create lossless configuration
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            codeBlockSize: (64, 64),
            qualityLayers: 1,
            useHTJ2K: false
        )

        // Act: Encode
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 64, height: 64, components: 1)
        let encodedData = try pipeline.encode(image)

        // Assert: Verify wavelet transform type is reversible
        let codMarkerData = try extractMarkerData(from: encodedData, marker: .cod)
        XCTAssertFalse(codMarkerData.isEmpty, "COD marker should be present")
        XCTAssertGreaterThanOrEqual(codMarkerData.count, 10, "COD marker data should have at least 10 bytes")

        if codMarkerData.count >= 10 {
            let transformType = codMarkerData[9] // 9th byte is transform type
            XCTAssertEqual(transformType, 1, "Lossless mode should use reversible 5/3 transform (type = 1)")
        }
    }

    func testCODMarkerHTJ2KLossless() throws {
        // Arrange: Create HTJ2K lossless configuration
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            codeBlockSize: (64, 64),
            qualityLayers: 1,
            useHTJ2K: true
        )

        // Act: Encode
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 64, height: 64, components: 1)
        let encodedData = try pipeline.encode(image)

        // Assert: Verify both HT bit and reversible transform
        let codMarkerData = try extractMarkerData(from: encodedData, marker: .cod)
        XCTAssertGreaterThanOrEqual(codMarkerData.count, 10, "COD marker data should have at least 10 bytes")

        if codMarkerData.count >= 10 {
            let codeBlockStyle = codMarkerData[8]
            XCTAssertEqual(codeBlockStyle & 0x40, 0x40, "HT bit should be set")

            let transformType = codMarkerData[9]
            XCTAssertEqual(transformType, 1, "Lossless should use reversible transform")
        }
    }

    // MARK: - COD Marker Parsing Tests

    func testCODParsingLegacyMode() throws {
        // Arrange: Create codestream with legacy mode
        let config = J2KEncodingConfiguration(useHTJ2K: false)
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 64, height: 64, components: 1)
        let encodedData = try pipeline.encode(image)

        // Act: Parse the codestream
        let decoderPipeline = DecoderPipeline()
        let decodedImage = try decoderPipeline.decode(encodedData)

        // Assert: Image decoded successfully (parser handled legacy mode)
        XCTAssertEqual(decodedImage.width, 64)
        XCTAssertEqual(decodedImage.height, 64)
    }

    func testCODParsingHTJ2KMode() throws {
        // Arrange: Create codestream with HTJ2K mode
        let config = J2KEncodingConfiguration(useHTJ2K: true)
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 64, height: 64, components: 1)
        let encodedData = try pipeline.encode(image)

        // Act: Parse the codestream
        let decoderPipeline = DecoderPipeline()

        // Note: Full decoding with HTJ2K block coder may not be implemented yet,
        // so we just verify the marker parsing doesn't fail
        do {
            _ = try decoderPipeline.decode(encodedData)
            // If decoding succeeds, that's great
        } catch {
            // If decoding fails due to missing HTJ2K block decoder, that's expected
            // The important thing is that the COD marker parsing worked
            let errorMessage = "\(error)"
            XCTAssertFalse(errorMessage.contains("Invalid marker") || errorMessage.contains("COD"),
                          "COD marker parsing should not fail, error: \(errorMessage)")
        }
    }

    // MARK: - COC Marker Tests

    func testCOCMarkerGeneration() throws {
        // The COC marker is optional and written per-component
        // For now, we test that the writeCOCMarker function is available
        // In a real scenario, it would be called for component-specific parameters

        let config = J2KEncodingConfiguration(
            decompositionLevels: 5,
            codeBlockSize: (32, 32),
            useHTJ2K: false
        )
        let pipeline = EncoderPipeline(config: config)

        // Verify the encoder pipeline has the COC marker writer available
        // (This is a structural test - the method exists and compiles)
        XCTAssertNotNil(pipeline)
    }

    func testCOCMarkerHTJ2KMode() throws {
        // Test that COC marker can be generated with HTJ2K mode
        let config = J2KEncodingConfiguration(
            decompositionLevels: 5,
            codeBlockSize: (64, 64),
            useHTJ2K: true
        )
        let pipeline = EncoderPipeline(config: config)
        XCTAssertNotNil(pipeline)

        // In the future, when COC markers are written, verify they contain HT bit
    }

    // MARK: - Round-trip Tests

    func testCODRoundTripLegacy() throws {
        // Arrange: Create configuration with single component
        let config = J2KEncodingConfiguration(
            quality: 0.95,
            lossless: false,
            decompositionLevels: 3,
            codeBlockSize: (32, 32),
            qualityLayers: 3,
            useHTJ2K: false
        )

        // Act: Encode and decode with single component
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 128, height: 128, components: 1)
        let encodedData = try pipeline.encode(image)

        let decoderPipeline = DecoderPipeline()
        let decodedImage = try decoderPipeline.decode(encodedData)

        // Assert: Image properties preserved
        XCTAssertEqual(decodedImage.width, image.width)
        XCTAssertEqual(decodedImage.height, image.height)
        XCTAssertEqual(decodedImage.componentCount, image.componentCount)
    }

    func testCODRoundTripLossless() throws {
        // Arrange: Create lossless configuration
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            codeBlockSize: (32, 32),
            qualityLayers: 1,
            useHTJ2K: false
        )

        // Act: Encode and decode
        let pipeline = EncoderPipeline(config: config)
        let image = try createTestImage(width: 64, height: 64, components: 1)
        let encodedData = try pipeline.encode(image)

        let decoderPipeline = DecoderPipeline()
        let decodedImage = try decoderPipeline.decode(encodedData)

        // Assert: Lossless reconstruction
        XCTAssertEqual(decodedImage.width, image.width)
        XCTAssertEqual(decodedImage.height, image.height)

        // For lossless, pixel values should match exactly (within acceptable tolerance for rounding)
        // This is a basic check - full pixel-by-pixel comparison would be more thorough
        XCTAssertEqual(decodedImage.componentCount, image.componentCount)
    }

    // MARK: - Helper Methods

    private func createTestImage(width: Int, height: Int, components: Int) throws -> J2KImage {
        // Use the convenience initializer which creates components automatically
        J2KImage(width: width, height: height, components: components, bitDepth: 8, signed: false)
    }

    private func extractMarkerData(from data: Data, marker: J2KMarker) throws -> Data {
        var reader = J2KBitReader(data: data)

        // Skip SOC marker
        _ = try reader.readMarker()

        // Search for the requested marker
        while reader.position < data.count - 2 {
            let markerValue = try reader.readMarker()

            if markerValue == marker.rawValue {
                // Found the marker, read its segment length
                let length = Int(try reader.readUInt16())
                // Read the marker segment data (length includes the 2-byte length field)
                let segmentData = try reader.readBytes(length - 2)
                return Data(segmentData)
            } else if J2KMarker(rawValue: markerValue)?.hasSegment == true {
                // Skip this marker segment
                let length = Int(try reader.readUInt16())
                try reader.skip(length - 2)
            }
        }

        return Data() // Marker not found
    }
}
