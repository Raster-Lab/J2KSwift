import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for the high-level encoding and decoding APIs.
///
/// Encoder tests validate that `J2KEncoder.encode()` produces valid JPEG 2000 codestreams.
/// Decoder tests validate that `J2KDecoder.decode()` still throws `notImplemented` (planned for v1.1).
final class J2KPlaceholderAPITests: XCTestCase {

    // MARK: - J2KEncoder Tests

    /// Tests that `J2KEncoder.encode()` produces non-empty output for a grayscale image.
    func testEncoderEncodeGrayscaleImage() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty, "Encoded data should not be empty")
    }

    /// Tests that the encoded data starts with SOC marker (0xFF4F).
    func testEncoderEncodeStartsWithSOC() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertGreaterThanOrEqual(data.count, 2)
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x4F)
    }

    /// Tests that the encoded data ends with EOC marker (0xFFD9).
    func testEncoderEncodeEndsWithEOC() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.9, lossless: false, decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertGreaterThanOrEqual(data.count, 4)
        XCTAssertEqual(data[data.count - 2], 0xFF)
        XCTAssertEqual(data[data.count - 1], 0xD9)
    }

    /// Tests encoding with a custom encoding configuration.
    func testEncoderEncodeWithCustomConfig() throws {
        let config = J2KEncodingConfiguration(
            quality: 0.8,
            lossless: false,
            decompositionLevels: 3,
            codeBlockSize: (width: 32, height: 32),
            qualityLayers: 3
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 8)

        let data = try encoder.encode(image)
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - J2KDecoder Placeholder Tests

    /// Tests that `J2KDecoder.decode()` throws appropriate error for invalid data.
    func testDecoderDecodeThrowsOnInvalidData() throws {
        let decoder = J2KDecoder()
        let data = Data()

        XCTAssertThrowsError(try decoder.decode(data)) { error in
            guard case J2KError.invalidData(_) = error else {
                XCTFail("Expected J2KError.invalidData, got \(error)")
                return
            }
        }
    }

    /// Tests that `J2KDecoder.decode()` throws error for malformed codestream.
    func testDecoderDecodeThrowsOnMalformedCodestream() throws {
        let decoder = J2KDecoder()
        // Invalid marker (not SOC)
        let data = Data([0xFF, 0xD9])

        XCTAssertThrowsError(try decoder.decode(data)) { error in
            guard case J2KError.decodingError(_) = error else {
                XCTFail("Expected J2KError.decodingError, got \(error)")
                return
            }
        }
    }
}
