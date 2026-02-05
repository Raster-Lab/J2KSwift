import XCTest
@testable import J2KCore
import Foundation

/// Integration tests for the J2KSwift framework.
///
/// These tests validate cross-component workflows and end-to-end scenarios.
final class J2KIntegrationTests: XCTestCase {
    
    private var generator: J2KTestImageGenerator!
    
    override func setUp() {
        super.setUp()
        generator = J2KTestImageGenerator()
    }
    
    override func tearDown() {
        generator = nil
        super.tearDown()
    }
    
    // MARK: - Image Buffer Integration Tests
    
    /// Tests that image buffers can be created and manipulated correctly.
    func testImageBufferIntegration() throws {
        // Create a buffer with a pattern
        let buffer = generator.generateBuffer(
            width: 128,
            height: 128,
            bitDepth: 8,
            pattern: .horizontalGradient
        )
        
        // Verify data can be extracted
        let data = buffer.toData()
        XCTAssertEqual(data.count, 128 * 128)
        
        // Verify data can be used to create a new buffer
        let reconstructed = J2KImageBuffer(width: 128, height: 128, bitDepth: 8, data: data)
        
        // Compare pixel values
        for y in 0..<128 {
            for x in 0..<128 {
                XCTAssertEqual(
                    buffer.getPixel(x: x, y: y),
                    reconstructed.getPixel(x: x, y: y),
                    "Pixel mismatch at (\(x), \(y))"
                )
            }
        }
    }
    
    /// Tests image buffer with component creation.
    func testImageBufferComponentIntegration() throws {
        let component = generator.generateComponent(
            index: 0,
            width: 64,
            height: 64,
            bitDepth: 8,
            pattern: .checkerboard
        )
        
        // Verify component data
        XCTAssertEqual(component.data.count, 64 * 64)
        
        // Create J2KImage with components
        let image = J2KImage(
            width: 64,
            height: 64,
            components: [component]
        )
        
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
        XCTAssertEqual(image.components.count, 1)
        XCTAssertEqual(image.components[0].data.count, 64 * 64)
    }
    
    // MARK: - Tiling Integration Tests
    
    /// Tests that tiled images are set up correctly.
    func testTiledImageIntegration() throws {
        let image = generator.generateTiledImage(
            width: 512,
            height: 512,
            tileWidth: 128,
            tileHeight: 128,
            components: 3
        )
        
        // Verify tiling math
        XCTAssertEqual(image.tilesX, 4)
        XCTAssertEqual(image.tilesY, 4)
        XCTAssertEqual(image.tileCount, 16)
        
        // Create tiles for the image
        var tiles: [J2KTile] = []
        for tileY in 0..<image.tilesY {
            for tileX in 0..<image.tilesX {
                let index = tileY * image.tilesX + tileX
                
                // Calculate tile bounds
                let tileStartX = tileX * image.tileWidth
                let tileStartY = tileY * image.tileHeight
                let tileEndX = min(tileStartX + image.tileWidth, image.width)
                let tileEndY = min(tileStartY + image.tileHeight, image.height)
                let actualWidth = tileEndX - tileStartX
                let actualHeight = tileEndY - tileStartY
                
                let tile = J2KTile(
                    index: index,
                    x: tileX,
                    y: tileY,
                    width: actualWidth,
                    height: actualHeight,
                    offsetX: tileStartX,
                    offsetY: tileStartY
                )
                tiles.append(tile)
            }
        }
        
        XCTAssertEqual(tiles.count, 16)
        
        // Verify tile coverage
        var coveredPixels = Set<Int>()
        for tile in tiles {
            for y in tile.offsetY..<(tile.offsetY + tile.height) {
                for x in tile.offsetX..<(tile.offsetX + tile.width) {
                    let pixelIndex = y * image.width + x
                    XCTAssertFalse(coveredPixels.contains(pixelIndex), "Tile overlap detected")
                    coveredPixels.insert(pixelIndex)
                }
            }
        }
        
        XCTAssertEqual(coveredPixels.count, image.width * image.height)
    }
    
    /// Tests tiling with non-aligned dimensions.
    func testNonAlignedTilingIntegration() throws {
        // Image size not evenly divisible by tile size
        let image = generator.generateTiledImage(
            width: 500,
            height: 300,
            tileWidth: 128,
            tileHeight: 128
        )
        
        // Should have 4x3 = 12 tiles
        XCTAssertEqual(image.tilesX, 4) // ceil(500/128)
        XCTAssertEqual(image.tilesY, 3) // ceil(300/128)
        
        // Right-most and bottom tiles should be smaller
        // Last tile X: starts at 384, width = 500 - 384 = 116
        // Last tile Y: starts at 256, height = 300 - 256 = 44
    }
    
    // MARK: - Bitstream Integration Tests
    
    /// Tests bitstream read/write round-trip.
    func testBitstreamRoundTrip() throws {
        // Write some data
        var writer = J2KBitWriter()
        
        // Write markers and data like a real codestream
        writer.writeMarker(J2KMarker.soc.rawValue)
        
        // Write a mock SIZ segment
        var sizData = Data()
        sizData.append(contentsOf: [0x00, 0x00]) // Rsiz
        sizData.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Xsiz = 256
        sizData.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Ysiz = 256
        writer.writeMarkerSegment(J2KMarker.siz.rawValue, segmentData: sizData)
        
        writer.writeMarker(J2KMarker.eoc.rawValue)
        
        // Read it back
        let codestreamData = writer.data
        var reader = J2KBitReader(data: codestreamData)
        
        // Verify SOC
        XCTAssertTrue(reader.isNextMarker())
        let socMarker = try reader.readMarker()
        XCTAssertEqual(socMarker, J2KMarker.soc.rawValue)
        
        // Verify SIZ
        XCTAssertTrue(reader.isNextMarker())
        let sizMarker = try reader.readMarker()
        XCTAssertEqual(sizMarker, J2KMarker.siz.rawValue)
        
        let length = try reader.readUInt16()
        let segmentContent = try reader.readBytes(Int(length) - 2)
        XCTAssertEqual(segmentContent.count, sizData.count)
        
        // Verify EOC
        let eocMarker = try reader.readMarker()
        XCTAssertEqual(eocMarker, J2KMarker.eoc.rawValue)
        
        XCTAssertTrue(reader.isAtEnd)
    }
    
    /// Tests marker parsing with generated data.
    func testMarkerParsingIntegration() throws {
        // Create a minimal valid codestream header
        var writer = J2KBitWriter()
        
        // SOC
        writer.writeMarker(J2KMarker.soc.rawValue)
        
        // SIZ (minimal for 1 component 256x256 image)
        var sizData = Data()
        sizData.append(contentsOf: [0x00, 0x00]) // Rsiz
        sizData.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Xsiz = 256
        sizData.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // Ysiz = 256
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XOsiz
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YOsiz
        sizData.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // XTsiz = 256
        sizData.append(contentsOf: [0x00, 0x00, 0x01, 0x00]) // YTsiz = 256
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // XTOsiz
        sizData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // YTOsiz
        sizData.append(contentsOf: [0x00, 0x01]) // Csiz = 1 component
        sizData.append(contentsOf: [0x07]) // Ssiz = 8 bits
        sizData.append(contentsOf: [0x01]) // XRsiz
        sizData.append(contentsOf: [0x01]) // YRsiz
        writer.writeMarkerSegment(J2KMarker.siz.rawValue, segmentData: sizData)
        
        // SOT (start of tile)
        var sotData = Data()
        sotData.append(contentsOf: [0x00, 0x00]) // Isot = tile 0
        sotData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Psot = 0
        sotData.append(contentsOf: [0x00]) // TPsot
        sotData.append(contentsOf: [0x01]) // TNsot
        writer.writeMarkerSegment(J2KMarker.sot.rawValue, segmentData: sotData)
        
        // Use marker parser
        let parser = J2KMarkerParser(data: writer.data)
        
        XCTAssertTrue(parser.validateBasicStructure())
        
        let segments = try parser.parseMainHeader()
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].marker, .soc)
        XCTAssertEqual(segments[1].marker, .siz)
        XCTAssertEqual(segments[2].marker, .sot)
    }
    
    // MARK: - Memory Management Integration Tests
    
    /// Tests memory pool and tracker working together.
    func testMemoryManagementIntegration() async throws {
        let pool = J2KMemoryPool()
        let tracker = J2KMemoryTracker(limit: 1024 * 1024) // 1MB limit
        
        var buffers: [J2KBuffer] = []
        
        // Acquire multiple buffers
        for _ in 0..<10 {
            let buffer = await pool.acquire(capacity: 4096)
            try await tracker.allocate(buffer.capacity)
            buffers.append(buffer)
        }
        
        // Verify tracking
        let stats = await tracker.getStatistics()
        XCTAssertGreaterThan(stats.currentUsage, 0)
        XCTAssertLessThanOrEqual(stats.currentUsage, 1024 * 1024)
        
        // Release all buffers
        for buffer in buffers {
            await tracker.deallocate(buffer.capacity)
            await pool.release(buffer)
        }
        
        // Verify cleanup
        let finalStats = await tracker.getStatistics()
        XCTAssertEqual(finalStats.currentUsage, 0)
    }
    
    /// Tests that memory limits are enforced.
    func testMemoryLimitEnforcement() async throws {
        let tracker = J2KMemoryTracker(limit: 1000)
        
        // Should succeed
        try await tracker.allocate(500)
        
        // Should succeed (total = 900)
        try await tracker.allocate(400)
        
        // Should fail (would exceed limit)
        do {
            try await tracker.allocate(200)
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
        
        let stats = await tracker.getStatistics()
        XCTAssertEqual(stats.currentUsage, 900)
        XCTAssertEqual(stats.failedAllocations, 1)
    }
    
    // MARK: - Multi-Component Integration Tests
    
    /// Tests creating and working with multi-component images.
    func testMultiComponentImageIntegration() throws {
        // Create RGB image with different patterns per component
        let redComponent = generator.generateComponent(
            index: 0,
            width: 128,
            height: 128,
            bitDepth: 8,
            pattern: .horizontalGradient
        )
        
        let greenComponent = generator.generateComponent(
            index: 1,
            width: 128,
            height: 128,
            bitDepth: 8,
            pattern: .verticalGradient
        )
        
        let blueComponent = generator.generateComponent(
            index: 2,
            width: 128,
            height: 128,
            bitDepth: 8,
            pattern: .diagonalGradient
        )
        
        let image = J2KImage(
            width: 128,
            height: 128,
            components: [redComponent, greenComponent, blueComponent],
            colorSpace: .sRGB
        )
        
        XCTAssertEqual(image.components.count, 3)
        
        // Verify each component has data
        for (idx, component) in image.components.enumerated() {
            XCTAssertEqual(component.index, idx)
            XCTAssertEqual(component.data.count, 128 * 128)
            XCTAssertEqual(component.bitDepth, 8)
        }
    }
    
    /// Tests subsampled YCbCr image creation.
    func testYCbCrSubsamplingIntegration() throws {
        let image = generator.generateSubsampledImage(width: 256, height: 256)
        
        XCTAssertEqual(image.components.count, 3)
        
        // Y component
        XCTAssertEqual(image.components[0].width, 256)
        XCTAssertEqual(image.components[0].height, 256)
        
        // Cb component (4:2:0 subsampled)
        XCTAssertEqual(image.components[1].width, 128)
        XCTAssertEqual(image.components[1].height, 128)
        
        // Cr component (4:2:0 subsampled)
        XCTAssertEqual(image.components[2].width, 128)
        XCTAssertEqual(image.components[2].height, 128)
    }
    
    // MARK: - Code Block Integration Tests
    
    /// Tests code block organization within a precinct.
    func testCodeBlockOrganization() throws {
        // Create a precinct with code blocks
        let codeBlocks: [J2KSubband: [J2KCodeBlock]] = [
            .ll: [J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32, subband: .ll)],
            .hl: [J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32, subband: .hl)],
            .lh: [J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32, subband: .lh)],
            .hh: [J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32, subband: .hh)]
        ]
        
        let precinct = J2KPrecinct(
            index: 0,
            x: 0,
            y: 0,
            width: 64,
            height: 64,
            resolutionLevel: 0,
            codeBlocks: codeBlocks
        )
        
        XCTAssertEqual(precinct.codeBlocks.count, 4)
        XCTAssertNotNil(precinct.codeBlocks[.ll])
        XCTAssertNotNil(precinct.codeBlocks[.hl])
        XCTAssertNotNil(precinct.codeBlocks[.lh])
        XCTAssertNotNil(precinct.codeBlocks[.hh])
    }
    
    /// Tests tile component with precincts.
    func testTileComponentWithPrecincts() throws {
        let precinct = J2KPrecinct(
            index: 0,
            x: 0,
            y: 0,
            width: 64,
            height: 64,
            resolutionLevel: 0
        )
        
        let tileComponent = J2KTileComponent(
            componentIndex: 0,
            width: 256,
            height: 256,
            precincts: [[precinct]] // One resolution level with one precinct
        )
        
        XCTAssertEqual(tileComponent.precincts.count, 1)
        XCTAssertEqual(tileComponent.precincts[0].count, 1)
        XCTAssertEqual(tileComponent.precincts[0][0].resolutionLevel, 0)
    }
    
    // MARK: - Test Pattern Verification Tests
    
    /// Tests that generated patterns have expected properties.
    func testPatternVerification() throws {
        // Test checkerboard pattern properties
        let checkerboard = generator.generateBuffer(
            width: 64,
            height: 64,
            bitDepth: 8,
            pattern: .checkerboard
        )
        
        // Count black and white pixels
        var blackCount = 0
        var whiteCount = 0
        for i in 0..<(64 * 64) {
            let value = checkerboard.getPixel(at: i)
            if value == 0 {
                blackCount += 1
            } else if value == 255 {
                whiteCount += 1
            }
        }
        
        // Should be roughly equal (not exactly due to block size)
        let ratio = Double(blackCount) / Double(whiteCount)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.1)
    }
    
    /// Tests gradient continuity.
    func testGradientContinuity() throws {
        let gradient = generator.generateBuffer(
            width: 256,
            height: 1,
            bitDepth: 8,
            pattern: .horizontalGradient
        )
        
        // Values should never decrease more than 1 (due to rounding)
        for x in 1..<256 {
            let prev = gradient.getPixel(at: x - 1)
            let curr = gradient.getPixel(at: x)
            XCTAssertGreaterThanOrEqual(curr, prev, "Gradient should be monotonically increasing")
        }
        
        // First and last values
        XCTAssertEqual(gradient.getPixel(at: 0), 0)
        XCTAssertEqual(gradient.getPixel(at: 255), 255)
    }
    
    // MARK: - Configuration Integration Tests
    
    /// Tests J2KConfiguration usage.
    func testConfigurationIntegration() throws {
        let lossyConfig = J2KConfiguration(quality: 0.8, lossless: false)
        let losslessConfig = J2KConfiguration(quality: 1.0, lossless: true)
        
        XCTAssertFalse(lossyConfig.lossless)
        XCTAssertEqual(lossyConfig.quality, 0.8, accuracy: 0.001)
        
        XCTAssertTrue(losslessConfig.lossless)
        XCTAssertEqual(losslessConfig.quality, 1.0, accuracy: 0.001)
    }
    
    // MARK: - Color Space Integration Tests
    
    /// Tests different color space configurations.
    func testColorSpaceIntegration() throws {
        let rgbImage = J2KImage(width: 64, height: 64, components: 3)
        // Default should be sRGB
        if case .sRGB = rgbImage.colorSpace {
            // Expected
        } else {
            XCTFail("Expected sRGB color space")
        }
        
        let grayComponent = J2KComponent(index: 0, bitDepth: 8, width: 64, height: 64)
        let grayscaleImage = J2KImage(
            width: 64,
            height: 64,
            components: [grayComponent],
            colorSpace: .grayscale
        )
        if case .grayscale = grayscaleImage.colorSpace {
            // Expected
        } else {
            XCTFail("Expected grayscale color space")
        }
        
        // ICC profile
        let iccData = Data([0x00, 0x01, 0x02, 0x03])
        let iccImage = J2KImage(
            width: 64,
            height: 64,
            components: [grayComponent],
            colorSpace: .iccProfile(iccData)
        )
        if case .iccProfile(let data) = iccImage.colorSpace {
            XCTAssertEqual(data, iccData)
        } else {
            XCTFail("Expected ICC profile color space")
        }
    }
}
