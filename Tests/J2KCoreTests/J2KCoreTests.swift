import XCTest
@testable import J2KCore

/// Tests for the J2KCore module.
final class J2KCoreTests: XCTestCase {
    /// Tests that the module compiles and links correctly.
    func testModuleCompilationAndLinkage() throws {
        // This test verifies that the J2KCore module can be imported and basic types are accessible.
        let image = J2KImage(width: 100, height: 100, components: 3)
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 100)
        XCTAssertEqual(image.components, 3)
    }
    
    /// Tests that the J2KConfiguration can be created with default values.
    func testConfigurationDefaults() throws {
        let config = J2KConfiguration()
        XCTAssertEqual(config.quality, 0.9, accuracy: 0.001)
        XCTAssertFalse(config.lossless)
    }
    
    /// Tests that the J2KConfiguration can be created with custom values.
    func testConfigurationCustomValues() throws {
        let config = J2KConfiguration(quality: 0.5, lossless: true)
        XCTAssertEqual(config.quality, 0.5, accuracy: 0.001)
        XCTAssertTrue(config.lossless)
    }
    
    /// Tests that J2KError types are accessible.
    func testErrorTypes() throws {
        let error1 = J2KError.notImplemented
        let error2 = J2KError.invalidParameter("test")
        let error3 = J2KError.internalError("test")
        
        // Verify errors exist and can be created
        XCTAssertNotNil(error1)
        XCTAssertNotNil(error2)
        XCTAssertNotNil(error3)
    }
}
