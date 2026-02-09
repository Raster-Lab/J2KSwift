import XCTest
@testable import J2KAccelerate
@testable import J2KCore

/// Tests that accelerated color transform placeholder APIs throw `notImplemented` errors.
///
/// These APIs are planned for full implementation in v1.1 Phase 4. Until then, they should
/// throw catchable errors with guidance to use J2KCodec color transforms instead.
final class J2KAcceleratePlaceholderAPITests: XCTestCase {
    
    // MARK: - Color Transform Placeholder Tests
    
    /// Tests that `J2KColorTransform.rgbToYCbCr()` throws `notImplemented`.
    func testRgbToYCbCrThrowsNotImplemented() throws {
        let transform = J2KColorTransform()
        let rgb: [Double] = [0.5, 0.5, 0.5]
        
        XCTAssertThrowsError(try transform.rgbToYCbCr(rgb)) { error in
            guard case J2KError.notImplemented(let message) = error else {
                XCTFail("Expected J2KError.notImplemented, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("v1.1"), "Error message should mention v1.1 target version")
        }
    }
    
    /// Tests that `J2KColorTransform.rgbToYCbCr()` error suggests J2KCodec alternatives.
    func testRgbToYCbCrErrorSuggestsAlternatives() throws {
        let transform = J2KColorTransform()
        let rgb: [Double] = [0.5, 0.5, 0.5]
        
        do {
            _ = try transform.rgbToYCbCr(rgb)
            XCTFail("Expected notImplemented error")
        } catch let error as J2KError {
            guard case .notImplemented(let message) = error else {
                XCTFail("Expected notImplemented case")
                return
            }
            XCTAssertTrue(message.contains("J2KCodec"), "Error should suggest J2KCodec module")
        }
    }
    
    /// Tests that `J2KColorTransform.ycbcrToRGB()` throws `notImplemented`.
    func testYcbcrToRgbThrowsNotImplemented() throws {
        let transform = J2KColorTransform()
        let ycbcr: [Double] = [0.5, 0.0, 0.0]
        
        XCTAssertThrowsError(try transform.ycbcrToRGB(ycbcr)) { error in
            guard case J2KError.notImplemented(let message) = error else {
                XCTFail("Expected J2KError.notImplemented, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("v1.1"), "Error message should mention v1.1 target version")
        }
    }
    
    /// Tests that `J2KColorTransform.ycbcrToRGB()` error suggests J2KCodec alternatives.
    func testYcbcrToRgbErrorSuggestsAlternatives() throws {
        let transform = J2KColorTransform()
        let ycbcr: [Double] = [0.5, 0.0, 0.0]
        
        do {
            _ = try transform.ycbcrToRGB(ycbcr)
            XCTFail("Expected notImplemented error")
        } catch let error as J2KError {
            guard case .notImplemented(let message) = error else {
                XCTFail("Expected notImplemented case")
                return
            }
            XCTAssertTrue(message.contains("J2KCodec"), "Error should suggest J2KCodec module")
        }
    }
}
