import XCTest
@testable import J2KFileFormat
@testable import J2KCore

/// Tests for the J2KFileFormat module.
final class J2KFileFormatTests: XCTestCase {
    /// Tests that the module compiles and links correctly.
    func testModuleCompilationAndLinkage() throws {
        // This test verifies that the J2KFileFormat module can be imported and basic types are accessible.
        let reader = J2KFileReader()
        XCTAssertNotNil(reader)
    }

    /// Tests that the file writer can be instantiated with default format.
    func testFileWriterDefaultFormat() throws {
        let writer = J2KFileWriter()
        XCTAssertEqual(writer.format, .jp2)
    }

    /// Tests that the file writer can be instantiated with custom format.
    func testFileWriterCustomFormat() throws {
        let writer = J2KFileWriter(format: .j2k)
        XCTAssertEqual(writer.format, .j2k)
    }

    /// Tests that all format types are accessible.
    func testFormatTypes() throws {
        XCTAssertEqual(J2KFormat.jp2.rawValue, "jp2")
        XCTAssertEqual(J2KFormat.j2k.rawValue, "j2k")
        XCTAssertEqual(J2KFormat.jpx.rawValue, "jpx")
        XCTAssertEqual(J2KFormat.jpm.rawValue, "jpm")
    }
}
