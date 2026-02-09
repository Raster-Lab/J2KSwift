import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests that placeholder APIs throw `notImplemented` errors instead of crashing.
///
/// These APIs are planned for full implementation in v1.1. Until then, they should
/// throw catchable errors with clear migration guidance.
final class J2KPlaceholderAPITests: XCTestCase {
    
    // MARK: - J2KEncoder Placeholder Tests
    
    /// Tests that `J2KEncoder.encode()` throws `notImplemented` instead of crashing.
    func testEncoderEncodeThrowsNotImplemented() throws {
        let encoder = J2KEncoder()
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)
        
        XCTAssertThrowsError(try encoder.encode(image)) { error in
            guard case J2KError.notImplemented(let message) = error else {
                XCTFail("Expected J2KError.notImplemented, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("v1.1"), "Error message should mention v1.1 target version")
        }
    }
    
    /// Tests that `J2KEncoder.encode()` error message includes migration guidance.
    func testEncoderEncodeErrorMessageIncludesGuidance() throws {
        let encoder = J2KEncoder()
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)
        
        do {
            _ = try encoder.encode(image)
            XCTFail("Expected notImplemented error")
        } catch let error as J2KError {
            guard case .notImplemented(let message) = error else {
                XCTFail("Expected notImplemented case")
                return
            }
            XCTAssertTrue(message.contains("component-level"), "Error should suggest component-level APIs")
        }
    }
    
    /// Tests that `J2KEncoder.encode()` error conforms to LocalizedError.
    func testEncoderEncodeErrorIsLocalized() throws {
        let encoder = J2KEncoder()
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)
        
        do {
            _ = try encoder.encode(image)
            XCTFail("Expected notImplemented error")
        } catch {
            XCTAssertNotNil(error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("Not implemented"))
        }
    }
    
    // MARK: - J2KDecoder Placeholder Tests
    
    /// Tests that `J2KDecoder.decode()` throws `notImplemented` instead of crashing.
    func testDecoderDecodeThrowsNotImplemented() throws {
        let decoder = J2KDecoder()
        let data = Data()
        
        XCTAssertThrowsError(try decoder.decode(data)) { error in
            guard case J2KError.notImplemented(let message) = error else {
                XCTFail("Expected J2KError.notImplemented, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("v1.1"), "Error message should mention v1.1 target version")
        }
    }
    
    /// Tests that `J2KDecoder.decode()` error message includes migration guidance.
    func testDecoderDecodeErrorMessageIncludesGuidance() throws {
        let decoder = J2KDecoder()
        let data = Data([0xFF, 0xD9])
        
        do {
            _ = try decoder.decode(data)
            XCTFail("Expected notImplemented error")
        } catch let error as J2KError {
            guard case .notImplemented(let message) = error else {
                XCTFail("Expected notImplemented case")
                return
            }
            XCTAssertTrue(message.contains("component-level"), "Error should suggest component-level APIs")
        }
    }
}
