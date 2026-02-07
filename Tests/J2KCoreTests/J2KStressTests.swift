import XCTest
@testable import J2KCore
@testable import J2KCodec

/// Stress tests for J2KSwift to validate behavior under extreme conditions.
///
/// These tests verify that the implementation handles large datasets, high loads,
/// and edge cases correctly without crashes or excessive resource usage.
final class J2KStressTests: XCTestCase {
    
    // MARK: - Large Image Tests
    
    func testLargeImageCreation() throws {
        // Test creating a large image (4K resolution)
        let width = 3840
        let height = 2160
        let components = 3
        
        let image = J2KImage(width: width, height: height, components: components, bitDepth: 8)
        
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
        XCTAssertEqual(image.components.count, components)
    }
    
    func testVeryLargeImageCreation() throws {
        // Test creating a very large image (8K resolution)
        let width = 7680
        let height = 4320
        let components = 3
        
        let image = J2KImage(width: width, height: height, components: components, bitDepth: 8)
        
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
        XCTAssertEqual(image.components.count, components)
    }
    
    func testMultiComponentImage() throws {
        // Test creating an image with many components
        let width = 512
        let height = 512
        let components = 16  // Many components (e.g., multispectral)
        
        let image = J2KImage(width: width, height: height, components: components, bitDepth: 8)
        
        XCTAssertEqual(image.components.count, components)
    }
    
    func testHighBitDepthImage() throws {
        // Test creating a high bit depth image
        let width = 1024
        let height = 1024
        let components = 3
        let bitDepth = 16
        
        let image = J2KImage(width: width, height: height, components: components, bitDepth: bitDepth)
        
        for component in image.components {
            XCTAssertEqual(component.bitDepth, bitDepth)
        }
    }
    
    // MARK: - Memory Stress Tests
    
    func testMultipleImageAllocation() throws {
        // Test allocating multiple images
        var images: [J2KImage] = []
        
        for _ in 0..<100 {
            let image = J2KImage(width: 256, height: 256, components: 3, bitDepth: 8)
            images.append(image)
        }
        
        XCTAssertEqual(images.count, 100)
    }
    
    func testSequentialAllocationDeallocation() throws {
        // Test rapid allocation and deallocation
        for _ in 0..<1000 {
            _ = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
        }
    }
    
    func testLargeBufferOperations() throws {
        // Test operations on large buffers
        let size = 1024 * 1024  // 1M samples
        var buffer = [Int32](repeating: 0, count: size)
        
        // Fill buffer
        for i in 0..<size {
            buffer[i] = Int32(i % 256)
        }
        
        // Calculate sum to ensure data is valid
        let sum = buffer.reduce(0, +)
        XCTAssertGreaterThan(sum, 0)
    }
    
    // MARK: - Edge Case Tests
    
    func testMinimumDimensions() throws {
        // Test minimum valid dimensions
        let image = J2KImage(width: 1, height: 1, components: 1, bitDepth: 1)
        
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
    }
    
    func testMaximumBitDepth() throws {
        // Test maximum bit depth (38 bits per JPEG 2000 spec)
        let image = J2KImage(width: 100, height: 100, components: 1, bitDepth: 38)
        
        XCTAssertLessThanOrEqual(image.components[0].bitDepth, 38)
    }
    
    func testPowerOfTwoDimensions() throws {
        // Test various power-of-two dimensions
        let dimensions = [2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
        
        for dim in dimensions {
            let image = J2KImage(width: dim, height: dim, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, dim)
            XCTAssertEqual(image.height, dim)
        }
    }
    
    func testNonPowerOfTwoDimensions() throws {
        // Test non-power-of-two dimensions
        let dimensions = [(100, 200), (333, 777), (1920, 1080), (1366, 768)]
        
        for (width, height) in dimensions {
            let image = J2KImage(width: width, height: height, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, width)
            XCTAssertEqual(image.height, height)
        }
    }
    
    func testOddDimensions() throws {
        // Test odd dimensions
        let image = J2KImage(width: 123, height: 457, components: 3, bitDepth: 8)
        
        XCTAssertEqual(image.width, 123)
        XCTAssertEqual(image.height, 457)
    }
    
    func testPrimeDimensions() throws {
        // Test prime number dimensions
        let primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53]
        
        for prime in primes {
            let image = J2KImage(width: prime, height: prime * 2, components: 1, bitDepth: 8)
            XCTAssertEqual(image.width, prime)
        }
    }
    
    // MARK: - Coefficient Range Tests
    
    func testExtremeCoefficientValues() throws {
        // Test with extreme coefficient values
        let size = 100
        var coefficients = [Int32](repeating: 0, count: size)
        
        // Set extreme values
        coefficients[0] = Int32.max
        coefficients[1] = Int32.min
        coefficients[2] = 0
        
        // Verify values are preserved
        XCTAssertEqual(coefficients[0], Int32.max)
        XCTAssertEqual(coefficients[1], Int32.min)
        XCTAssertEqual(coefficients[2], 0)
    }
    
    func testMixedSignCoefficients() throws {
        // Test with mixed positive and negative coefficients
        let size = 1000
        var coefficients = [Int32](repeating: 0, count: size)
        
        for i in 0..<size {
            coefficients[i] = i % 2 == 0 ? Int32(i) : -Int32(i)
        }
        
        // Verify pattern
        XCTAssertGreaterThan(coefficients[0], 0)
        XCTAssertLessThan(coefficients[1], 0)
    }
    
    // MARK: - Performance Baseline Tests
    
    func testSmallImageCreationPerformance() {
        measure {
            for _ in 0..<100 {
                _ = J2KImage(width: 64, height: 64, components: 3, bitDepth: 8)
            }
        }
    }
    
    func testMediumImageCreationPerformance() {
        measure {
            for _ in 0..<10 {
                _ = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
            }
        }
    }
    
    func testLargeBufferAllocationPerformance() {
        measure {
            _ = [Int32](repeating: 0, count: 1024 * 1024)
        }
    }
    
    // MARK: - Concurrent Operation Tests
    
    func testConcurrentImageCreation() throws {
        let iterations = 100
        let expectation = self.expectation(description: "Concurrent creation")
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let size = 64 + (i % 128)
            _ = J2KImage(width: size, height: size, components: 3, bitDepth: 8)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    func testConcurrentBufferOperations() throws {
        let iterations = 50
        let expectation = self.expectation(description: "Concurrent buffers")
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let size = 1000 + (i * 100)
            var buffer = [Int32](repeating: 0, count: size)
            for j in 0..<size {
                buffer[j] = Int32(j)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
    }
    
    // MARK: - Tile Processing Tests
    
    func testManySmallTiles() throws {
        // Simulate processing many small tiles
        let tileSize = 64
        let tilesX = 32
        let tilesY = 32
        
        for ty in 0..<tilesY {
            for tx in 0..<tilesX {
                _ = J2KImage(width: tileSize, height: tileSize, components: 3, bitDepth: 8)
            }
        }
    }
    
    func testVariableTileSizes() throws {
        // Test with variable tile sizes
        let tileSizes = [32, 64, 128, 256, 512]
        
        for size in tileSizes {
            let image = J2KImage(width: size, height: size, components: 3, bitDepth: 8)
            XCTAssertEqual(image.width, size)
        }
    }
    
    // MARK: - Long-Running Operation Tests
    
    func testLongSequenceOfOperations() throws {
        // Test a long sequence of operations
        for i in 0..<1000 {
            let size = 50 + (i % 100)
            let image = J2KImage(width: size, height: size, components: 3, bitDepth: 8)
            
            // Verify occasionally
            if i % 100 == 0 {
                XCTAssertEqual(image.width, size)
            }
        }
    }
    
    func testRepeatedLargeAllocations() throws {
        // Test repeated large allocations (tests memory management)
        for _ in 0..<10 {
            _ = J2KImage(width: 2048, height: 2048, components: 3, bitDepth: 8)
        }
    }
}
