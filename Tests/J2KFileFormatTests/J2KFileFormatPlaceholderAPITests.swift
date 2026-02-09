import XCTest
@testable import J2KFileFormat
@testable import J2KCore

/// Tests that file format placeholder APIs throw `notImplemented` errors.
///
/// File writing is planned for full implementation in v1.1 Phase 2-3.
final class J2KFileFormatPlaceholderAPITests: XCTestCase {
    
    /// Tests that `J2KFileWriter.write()` throws `notImplemented`.
    func testFileWriterWriteThrowsNotImplemented() throws {
        let writer = J2KFileWriter()
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)
        let url = URL(fileURLWithPath: "/tmp/test_output.jp2")
        
        XCTAssertThrowsError(try writer.write(image, to: url)) { error in
            guard case J2KError.notImplemented = error else {
                XCTFail("Expected J2KError.notImplemented, got \(error)")
                return
            }
        }
    }
    
    /// Tests that `J2KFileWriter.write()` with custom format throws `notImplemented`.
    func testFileWriterWriteJ2KFormatThrowsNotImplemented() throws {
        let writer = J2KFileWriter(format: .j2k)
        let image = J2KImage(width: 16, height: 16, components: 3, bitDepth: 8)
        let url = URL(fileURLWithPath: "/tmp/test_output.j2k")
        
        XCTAssertThrowsError(try writer.write(image, to: url)) { error in
            guard case J2KError.notImplemented = error else {
                XCTFail("Expected J2KError.notImplemented, got \(error)")
                return
            }
        }
    }
}
