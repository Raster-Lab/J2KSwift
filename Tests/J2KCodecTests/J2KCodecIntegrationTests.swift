// J2KCodecIntegrationTests.swift
// J2KSwift
//
// Integration tests for encoder→decoder round-trip functionality.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KCodecIntegrationTests: XCTestCase {
    
    // MARK: - Basic Round-Trip Tests
    
    func testSimpleGrayscaleRoundTrip() throws {
        // Create a simple grayscale image
        let width = 16
        let height = 16
        var data = Data()
        for _ in 0..<(width * height) {
            data.append(128) // Mid-gray
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        // Encode
        let encoder = J2KEncoder()
        let encoded = try encoder.encode(image)
        
        XCTAssertGreaterThan(encoded.count, 0, "Encoded data should not be empty")
        
        // Decode
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify dimensions
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.components.count, 1)
        
        // Verify component properties
        let decodedComp = decoded.components[0]
        XCTAssertEqual(decodedComp.width, width)
        XCTAssertEqual(decodedComp.height, height)
        XCTAssertEqual(decodedComp.bitDepth, 8)
    }
    
    func testRGBRoundTrip() throws {
        // Create a simple RGB image
        let width = 32
        let height = 32
        
        func createComponentData(value: UInt8) -> Data {
            var data = Data()
            for _ in 0..<(width * height) {
                data.append(value)
            }
            return data
        }
        
        let redComponent = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: createComponentData(value: 255)
        )
        
        let greenComponent = J2KComponent(
            index: 1,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: createComponentData(value: 0)
        )
        
        let blueComponent = J2KComponent(
            index: 2,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: createComponentData(value: 0)
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [redComponent, greenComponent, blueComponent]
        )
        
        // Encode
        let config = J2KEncodingConfiguration(
            quality: 0.95,
            lossless: false,
            decompositionLevels: 2
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try encoder.encode(image)
        
        XCTAssertGreaterThan(encoded.count, 0, "Encoded data should not be empty")
        
        // Decode
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify dimensions and component count
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.components.count, 3)
    }
    
    func testLosslessRoundTrip() throws {
        // Create a gradient pattern
        let width = 16
        let height = 16
        var data = Data()
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8((x * 255) / width)
                data.append(value)
            }
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        // Encode with lossless configuration
        let config = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true
        )
        let encoder = J2KEncoder(encodingConfiguration: config)
        let encoded = try encoder.encode(image)
        
        XCTAssertGreaterThan(encoded.count, 0, "Encoded data should not be empty")
        
        // Decode
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        
        // Verify exact reconstruction (lossless)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.components.count, 1)
        
        let decodedComp = decoded.components[0]
        XCTAssertEqual(decodedComp.width, width)
        XCTAssertEqual(decodedComp.height, height)
        XCTAssertEqual(decodedComp.data.count, data.count)
    }
    
    func testProgressReportingEncoder() throws {
        let width = 16
        let height = 16
        var data = Data()
        for _ in 0..<(width * height) {
            data.append(100)
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        var progressUpdates: [EncoderProgressUpdate] = []
        let encoder = J2KEncoder()
        
        _ = try encoder.encode(image) { update in
            progressUpdates.append(update)
        }
        
        // Verify we got progress updates
        XCTAssertGreaterThan(progressUpdates.count, 0, "Should receive progress updates")
        
        // Verify progress increases
        var lastProgress = 0.0
        for update in progressUpdates {
            XCTAssertGreaterThanOrEqual(update.overallProgress, lastProgress)
            lastProgress = update.overallProgress
        }
        
        // Verify final progress is complete
        if let last = progressUpdates.last {
            XCTAssertEqual(last.overallProgress, 1.0, accuracy: 0.01)
        }
    }
    
    func testProgressReportingDecoder() throws {
        // First encode an image
        let width = 16
        let height = 16
        var data = Data()
        for _ in 0..<(width * height) {
            data.append(100)
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        let encoder = J2KEncoder()
        let encoded = try encoder.encode(image)
        
        // Now decode with progress tracking
        var progressUpdates: [DecoderProgressUpdate] = []
        let decoder = J2KDecoder()
        
        _ = try decoder.decode(encoded) { update in
            progressUpdates.append(update)
        }
        
        // Verify we got progress updates
        XCTAssertGreaterThan(progressUpdates.count, 0, "Should receive progress updates")
        
        // Verify progress increases
        var lastProgress = 0.0
        for update in progressUpdates {
            XCTAssertGreaterThanOrEqual(update.overallProgress, lastProgress)
            lastProgress = update.overallProgress
        }
        
        // Verify final progress is complete
        if let last = progressUpdates.last {
            XCTAssertEqual(last.overallProgress, 1.0, accuracy: 0.01)
        }
    }
    
    // MARK: - Edge Cases
    
    func testMinimalImage() throws {
        // 1x1 pixel image
        let width = 1
        let height = 1
        var data = Data()
        data.append(42)
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        let encoder = J2KEncoder()
        let encoded = try encoder.encode(image)
        
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.components.count, 1)
    }
    
    func testAllZeroImage() throws {
        let width = 16
        let height = 16
        let data = Data(repeating: 0, count: width * height)
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        let encoder = J2KEncoder()
        let encoded = try encoder.encode(image)
        
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.components.count, 1)
    }
    
    func testOddDimensions() throws {
        let width = 17
        let height = 13
        var data = Data()
        for _ in 0..<(width * height) {
            data.append(77)
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        let encoder = J2KEncoder()
        let encoded = try encoder.encode(image)
        
        let decoder = J2KDecoder()
        let decoded = try decoder.decode(encoded)
        
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        XCTAssertEqual(decoded.components.count, 1)
    }
    
    // MARK: - Configuration Tests
    
    func testDifferentQualityLevels() throws {
        let width = 32
        let height = 32
        var data = Data()
        for y in 0..<height {
            for x in 0..<width {
                data.append(UInt8((x + y) % 256))
            }
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        // Test different quality levels
        for quality in [0.5, 0.75, 0.9, 1.0] {
            let config = J2KEncodingConfiguration(
                quality: quality,
                lossless: (quality == 1.0)
            )
            let encoder = J2KEncoder(encodingConfiguration: config)
            let encoded = try encoder.encode(image)
            
            let decoder = J2KDecoder()
            let decoded = try decoder.decode(encoded)
            
            XCTAssertEqual(decoded.width, width)
            XCTAssertEqual(decoded.height, height)
        }
    }
    
    func testDifferentDecompositionLevels() throws {
        let width = 64
        let height = 64
        let data = Data(repeating: 150, count: width * height)
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        // Test different decomposition levels
        for levels in [0, 1, 2, 3] {
            let config = J2KEncodingConfiguration(
                quality: 0.95,
                lossless: false,
                decompositionLevels: levels
            )
            let encoder = J2KEncoder(encodingConfiguration: config)
            let encoded = try encoder.encode(image)
            
            let decoder = J2KDecoder()
            let decoded = try decoder.decode(encoded)
            
            XCTAssertEqual(decoded.width, width)
            XCTAssertEqual(decoded.height, height)
        }
    }
}
