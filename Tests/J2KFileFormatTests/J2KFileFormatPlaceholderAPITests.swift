import XCTest
@testable import J2KFileFormat
@testable import J2KCore
import Foundation

/// Tests that file format APIs are now implemented.
///
/// File writing was implemented as part of v1.1 Phase 2-3 completion.
final class J2KFileFormatPlaceholderAPITests: XCTestCase {
    
    /// Tests that `J2KFileWriter.write()` successfully writes a JP2 file.
    func testFileWriterWriteThrowsNotImplemented() throws {
        let writer = J2KFileWriter()
        let image = J2KImage(width: 8, height: 8, components: 1, bitDepth: 8)
        
        // Create a temporary URL for testing
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jp2")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Should succeed without throwing
        XCTAssertNoThrow(try writer.write(image, to: tempURL))
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }
    
    /// Tests that `J2KFileWriter.write()` with J2K format successfully writes a codestream.
    func testFileWriterWriteJ2KFormatThrowsNotImplemented() throws {
        let writer = J2KFileWriter(format: .j2k)
        let image = J2KImage(width: 16, height: 16, components: 3, bitDepth: 8)
        
        // Create a temporary URL for testing
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".j2k")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // Should succeed without throwing
        XCTAssertNoThrow(try writer.write(image, to: tempURL))
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        // Verify it's a valid J2K codestream (starts with FF 4F)
        let data = try Data(contentsOf: tempURL)
        XCTAssertGreaterThan(data.count, 2)
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x4F)
    }
}
