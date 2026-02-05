import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for the J2KCodec module.
final class J2KCodecTests: XCTestCase {
    /// Tests that the module compiles and links correctly.
    func testModuleCompilationAndLinkage() throws {
        // This test verifies that the J2KCodec module can be imported and basic types are accessible.
        let encoder = J2KEncoder()
        XCTAssertNotNil(encoder)
        XCTAssertEqual(encoder.configuration.quality, 0.9, accuracy: 0.001)
    }
    
    /// Tests that the encoder can be created with a custom configuration.
    func testEncoderWithCustomConfiguration() throws {
        let config = J2KConfiguration(quality: 0.7, lossless: false)
        let encoder = J2KEncoder(configuration: config)
        XCTAssertEqual(encoder.configuration.quality, 0.7, accuracy: 0.001)
        XCTAssertFalse(encoder.configuration.lossless)
    }
    
    /// Tests that the decoder can be instantiated.
    func testDecoderInstantiation() throws {
        let decoder = J2KDecoder()
        XCTAssertNotNil(decoder)
    }
}
