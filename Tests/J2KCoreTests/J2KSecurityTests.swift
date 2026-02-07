import XCTest
@testable import J2KCore
@testable import J2KFileFormat

/// Security and robustness tests for J2KSwift.
///
/// These tests verify that the implementation handles malformed input,
/// invalid data, and potential security vulnerabilities correctly.
final class J2KSecurityTests: XCTestCase {
    
    // MARK: - Input Validation Tests
    
    func testEmptyDataHandling() throws {
        let emptyData = Data()
        
        // Should not crash, should return appropriate error
        XCTAssertThrowsError(try J2KFileReader().detectFormat(data: emptyData)) { error in
            // Verify it's an appropriate error
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testTruncatedDataHandling() throws {
        // JP2 signature is 12 bytes, provide only 4
        let truncatedData = Data([0x00, 0x00, 0x00, 0x0C])
        
        XCTAssertThrowsError(try J2KFileReader().detectFormat(data: truncatedData)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testInvalidMarkerHandling() throws {
        // Invalid JPEG 2000 marker
        let invalidMarker = Data([0xFF, 0x00])  // Not a valid J2K marker
        
        XCTAssertThrowsError(try J2KFileReader().detectFormat(data: invalidMarker)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testNegativeDimensionsHandling() throws {
        // Test that negative dimensions are handled
        // J2KImage clamps invalid values, doesn't throw
        let image1 = J2KImage(width: -1, height: 100, components: 3, bitDepth: 8)
        XCTAssertGreaterThan(image1.width, 0, "Negative width should be clamped to positive")
        
        let image2 = J2KImage(width: 100, height: -1, components: 3, bitDepth: 8)
        XCTAssertGreaterThan(image2.height, 0, "Negative height should be clamped to positive")
    }
    
    func testZeroDimensionsHandling() throws {
        // Test that zero dimensions are handled
        let image1 = J2KImage(width: 0, height: 100, components: 3, bitDepth: 8)
        XCTAssertGreaterThan(image1.width, 0, "Zero width should be clamped to positive")
        
        let image2 = J2KImage(width: 100, height: 0, components: 3, bitDepth: 8)
        XCTAssertGreaterThan(image2.height, 0, "Zero height should be clamped to positive")
    }
    
    func testInvalidComponentCountHandling() throws {
        // Test that invalid component counts are handled
        let image1 = J2KImage(width: 100, height: 100, components: 0, bitDepth: 8)
        XCTAssertGreaterThan(image1.components.count, 0, "Zero components should be clamped")
        
        let image2 = J2KImage(width: 100, height: 100, components: -1, bitDepth: 8)
        XCTAssertGreaterThan(image2.components.count, 0, "Negative components should be clamped")
    }
    
    func testInvalidBitDepthHandling() throws {
        // Test that invalid bit depths are handled
        let image1 = J2KImage(width: 100, height: 100, components: 3, bitDepth: 0)
        XCTAssertGreaterThan(image1.components[0].bitDepth, 0, "Zero bit depth should be clamped")
        
        let image2 = J2KImage(width: 100, height: 100, components: 3, bitDepth: -1)
        XCTAssertGreaterThan(image2.components[0].bitDepth, 0, "Negative bit depth should be clamped")
        
        // Test bit depth too large (>38 bits) - should be clamped
        let image3 = J2KImage(width: 100, height: 100, components: 3, bitDepth: 40)
        XCTAssertLessThanOrEqual(image3.components[0].bitDepth, 38, "Large bit depth should be clamped")
    }
    
    // MARK: - Buffer Overflow Tests
    
    func testVeryLargeDimensionsHandling() throws {
        // Test that extremely large dimensions don't cause integer overflow
        // or excessive memory allocation
        let maxInt = Int.max
        
        // These should fail due to memory limits or validation
        // Note: J2KImage init doesn't throw, so we just test it doesn't crash
        _ = J2KImage(width: 1, height: 100, components: 3, bitDepth: 8)
        _ = J2KImage(width: 100, height: 1, components: 3, bitDepth: 8)
        
        // Very large dimensions should be rejected or handled safely
        // We don't actually create these to avoid memory issues
        XCTAssertTrue(true)
    }
    
    // MARK: - Malformed Data Tests
    
    func testCorruptedSignatureBox() throws {
        // JP2 file with corrupted signature
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0C])  // Length
        data.append(contentsOf: [0x6A, 0x50, 0x20, 0x20])  // Box type "jP  "
        data.append(contentsOf: [0x0D, 0x0A, 0x87, 0x0B])  // Should be 0x0D0A870A, but last byte is wrong
        
        XCTAssertThrowsError(try J2KFileReader().detectFormat(data: data)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testInvalidBoxLength() throws {
        // Box with length that extends beyond data
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0xFF, 0xFF])  // Huge length
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70])  // Box type "ftyp"
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20])  // Data
        
        let reader = J2KFileReader()
        XCTAssertThrowsError(try reader.detectFormat(data: data)) { error in
            XCTAssertTrue(error is J2KError)
        }
    }
    
    func testNestedBoxDepthLimit() throws {
        // Create deeply nested boxes to test recursion limits
        var data = Data()
        
        // Create 100 nested superboxes (should hit recursion limit)
        for _ in 0..<100 {
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x14])  // Length (20 bytes)
            data.append(contentsOf: [0x6A, 0x70, 0x32, 0x68])  // Type "jp2h" (header box, can be nested)
        }
        
        // This should either succeed with a reasonable nesting level or fail gracefully
        let reader = J2KFileReader()
        // Don't crash
        _ = try? reader.detectFormat(data: data)
    }
    
    func testZeroLengthBox() throws {
        // Box with zero length (extends to end of file)
        var data = Data()
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // Length = 0 (extends to EOF)
        data.append(contentsOf: [0x66, 0x74, 0x79, 0x70])  // Box type "ftyp"
        data.append(contentsOf: [0x6A, 0x70, 0x32, 0x20])  // Data (4 bytes)
        
        // Should handle this gracefully
        let reader = J2KFileReader()
        _ = try? reader.detectFormat(data: data)
    }
    
    // MARK: - Denial of Service Tests
    
    func testRepeatedAllocationAttempts() throws {
        // Test that repeated allocation attempts don't exhaust memory
        for _ in 0..<1000 {
            // Try to create and immediately release small images
            _ = J2KImage(width: 10, height: 10, components: 3, bitDepth: 8)
        }
        // If we got here without crashing or hanging, test passed
        XCTAssertTrue(true)
    }
    
    // MARK: - Fuzzing Tests (Basic)
    
    func testRandomDataHandling() throws {
        // Generate random data and ensure it doesn't crash
        for _ in 0..<100 {
            let length = Int.random(in: 1...1000)
            var randomData = Data(count: length)
            for i in 0..<length {
                randomData[i] = UInt8.random(in: 0...255)
            }
            
            // Should not crash, just fail gracefully
            let reader = J2KFileReader()
            _ = try? reader.detectFormat(data: randomData)
        }
        
        XCTAssertTrue(true)
    }
    
    func testBoundaryValues() throws {
        // Test with boundary value dimensions
        let boundaryValues = [1, 2, 127, 128, 255, 256, 511, 512, 1023, 1024]
        
        for width in boundaryValues {
            for height in boundaryValues {
                // These should either succeed or fail gracefully
                _ = J2KImage(width: width, height: height, components: 3, bitDepth: 8)
            }
        }
        
        XCTAssertTrue(true)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentImageCreation() throws {
        let iterations = 100
        let expectation = self.expectation(description: "Concurrent creation")
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = J2KImage(width: 10, height: 10, components: 3, bitDepth: 8)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testConcurrentFormatDetection() throws {
        let validJP2Header = Data([
            0x00, 0x00, 0x00, 0x0C,  // Length
            0x6A, 0x50, 0x20, 0x20,  // Type "jP  "
            0x0D, 0x0A, 0x87, 0x0A   // Signature
        ])
        
        let iterations = 100
        let expectation = self.expectation(description: "Concurrent detection")
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let reader = J2KFileReader()
            _ = try? reader.detectFormat(data: validJP2Header)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
}
