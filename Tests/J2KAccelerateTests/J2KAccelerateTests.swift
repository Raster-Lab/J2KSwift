import XCTest
@testable import J2KAccelerate
@testable import J2KCore

/// Tests for the J2KAccelerate module.
final class J2KAccelerateTests: XCTestCase {
    /// Tests that the module compiles and links correctly.
    func testModuleCompilationAndLinkage() throws {
        // This test verifies that the J2KAccelerate module can be imported and basic types are accessible.
        let dwt = J2KDWTAccelerated()
        XCTAssertNotNil(dwt)
    }
    
    /// Tests that the color transform processor can be instantiated.
    func testColorTransformInstantiation() throws {
        let transform = J2KColorTransform()
        XCTAssertNotNil(transform)
    }
    
    /// Tests that the DWT processor can be instantiated.
    func testDWTInstantiation() throws {
        let dwt = J2KDWTAccelerated()
        XCTAssertNotNil(dwt)
    }
}
