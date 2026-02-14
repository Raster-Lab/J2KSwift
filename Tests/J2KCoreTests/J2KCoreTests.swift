import XCTest
@testable import J2KCore

/// Tests for the J2KCore module.
final class J2KCoreTests: XCTestCase {
    /// Tests that the module compiles and links correctly.
    func testModuleCompilationAndLinkage() throws {
        let image = J2KImage(width: 100, height: 100, components: 3)
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 100)
        XCTAssertEqual(image.components.count, 3)
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
        let error1 = J2KError.notImplemented("feature")
        let error2 = J2KError.invalidParameter("test")
        let error3 = J2KError.internalError("test")
        let error4 = J2KError.invalidDimensions("test")
        let error5 = J2KError.encodingError("test")
        
        // Verify errors exist and can be created
        XCTAssertNotNil(error1)
        XCTAssertNotNil(error2)
        XCTAssertNotNil(error3)
        XCTAssertNotNil(error4)
        XCTAssertNotNil(error5)
    }
    
    /// Tests version string.
    func testGetVersion() throws {
        let version = getVersion()
        XCTAssertFalse(version.isEmpty)
        XCTAssertTrue(version.contains("1.1.0"))
    }
    
    // MARK: - J2KComponent Tests
    
    /// Tests J2KComponent initialization with defaults.
    func testComponentInitialization() throws {
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            width: 512,
            height: 512
        )
        
        XCTAssertEqual(component.index, 0)
        XCTAssertEqual(component.bitDepth, 8)
        XCTAssertFalse(component.signed)
        XCTAssertEqual(component.width, 512)
        XCTAssertEqual(component.height, 512)
        XCTAssertEqual(component.subsamplingX, 1)
        XCTAssertEqual(component.subsamplingY, 1)
        XCTAssertTrue(component.data.isEmpty)
    }
    
    /// Tests J2KComponent with custom subsampling.
    func testComponentSubsampling() throws {
        let component = J2KComponent(
            index: 1,
            bitDepth: 8,
            width: 256,
            height: 256,
            subsamplingX: 2,
            subsamplingY: 2
        )
        
        XCTAssertEqual(component.subsamplingX, 2)
        XCTAssertEqual(component.subsamplingY, 2)
    }
    
    /// Tests J2KComponent with signed values.
    func testComponentSigned() throws {
        let component = J2KComponent(
            index: 0,
            bitDepth: 12,
            signed: true,
            width: 512,
            height: 512
        )
        
        XCTAssertTrue(component.signed)
        XCTAssertEqual(component.bitDepth, 12)
    }
    
    // MARK: - J2KImage Tests
    
    /// Tests J2KImage simple initialization.
    func testImageSimpleInitialization() throws {
        let image = J2KImage(width: 512, height: 512, components: 3)
        
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        XCTAssertEqual(image.components.count, 3)
        XCTAssertEqual(image.offsetX, 0)
        XCTAssertEqual(image.offsetY, 0)
        XCTAssertEqual(image.tileWidth, 0)
        XCTAssertEqual(image.tileHeight, 0)
    }
    
    /// Tests J2KImage with custom bit depth.
    func testImageCustomBitDepth() throws {
        let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 16)
        
        XCTAssertEqual(image.components.count, 3)
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 16)
        }
    }
    
    /// Tests J2KImage with tiling.
    func testImageWithTiling() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: 1024, height: 1024)
        ]
        
        let image = J2KImage(
            width: 1024,
            height: 1024,
            components: components,
            tileWidth: 256,
            tileHeight: 256
        )
        
        XCTAssertEqual(image.tileWidth, 256)
        XCTAssertEqual(image.tileHeight, 256)
        XCTAssertEqual(image.tilesX, 4)
        XCTAssertEqual(image.tilesY, 4)
        XCTAssertEqual(image.tileCount, 16)
    }
    
    /// Tests J2KImage without tiling.
    func testImageWithoutTiling() throws {
        let image = J2KImage(width: 512, height: 512, components: 3)
        
        XCTAssertEqual(image.tilesX, 1)
        XCTAssertEqual(image.tilesY, 1)
        XCTAssertEqual(image.tileCount, 1)
    }
    
    /// Tests J2KImage with color space.
    func testImageColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: 512, height: 512)
        ]
        
        let image = J2KImage(
            width: 512,
            height: 512,
            components: components,
            colorSpace: .grayscale
        )
        
        if case .grayscale = image.colorSpace {
            // Success
        } else {
            XCTFail("Expected grayscale color space")
        }
    }
    
    // MARK: - J2KTile Tests
    
    /// Tests J2KTile initialization.
    func testTileInitialization() throws {
        let tile = J2KTile(
            index: 0,
            x: 0,
            y: 0,
            width: 256,
            height: 256,
            offsetX: 0,
            offsetY: 0
        )
        
        XCTAssertEqual(tile.index, 0)
        XCTAssertEqual(tile.x, 0)
        XCTAssertEqual(tile.y, 0)
        XCTAssertEqual(tile.width, 256)
        XCTAssertEqual(tile.height, 256)
        XCTAssertTrue(tile.components.isEmpty)
    }
    
    /// Tests J2KTile with components.
    func testTileWithComponents() throws {
        let tileComponents = [
            J2KTileComponent(componentIndex: 0, width: 256, height: 256),
            J2KTileComponent(componentIndex: 1, width: 256, height: 256),
            J2KTileComponent(componentIndex: 2, width: 256, height: 256)
        ]
        
        let tile = J2KTile(
            index: 0,
            x: 0,
            y: 0,
            width: 256,
            height: 256,
            offsetX: 0,
            offsetY: 0,
            components: tileComponents
        )
        
        XCTAssertEqual(tile.components.count, 3)
    }
    
    // MARK: - J2KTileComponent Tests
    
    /// Tests J2KTileComponent initialization.
    func testTileComponentInitialization() throws {
        let tileComponent = J2KTileComponent(
            componentIndex: 0,
            width: 256,
            height: 256
        )
        
        XCTAssertEqual(tileComponent.componentIndex, 0)
        XCTAssertEqual(tileComponent.width, 256)
        XCTAssertEqual(tileComponent.height, 256)
        XCTAssertTrue(tileComponent.precincts.isEmpty)
    }
    
    // MARK: - J2KPrecinct Tests
    
    /// Tests J2KPrecinct initialization.
    func testPrecinctInitialization() throws {
        let precinct = J2KPrecinct(
            index: 0,
            x: 0,
            y: 0,
            width: 64,
            height: 64,
            resolutionLevel: 0
        )
        
        XCTAssertEqual(precinct.index, 0)
        XCTAssertEqual(precinct.x, 0)
        XCTAssertEqual(precinct.y, 0)
        XCTAssertEqual(precinct.width, 64)
        XCTAssertEqual(precinct.height, 64)
        XCTAssertEqual(precinct.resolutionLevel, 0)
        XCTAssertTrue(precinct.codeBlocks.isEmpty)
    }
    
    // MARK: - J2KCodeBlock Tests
    
    /// Tests J2KCodeBlock initialization.
    func testCodeBlockInitialization() throws {
        let codeBlock = J2KCodeBlock(
            index: 0,
            x: 0,
            y: 0,
            width: 32,
            height: 32,
            subband: .ll
        )
        
        XCTAssertEqual(codeBlock.index, 0)
        XCTAssertEqual(codeBlock.x, 0)
        XCTAssertEqual(codeBlock.y, 0)
        XCTAssertEqual(codeBlock.width, 32)
        XCTAssertEqual(codeBlock.height, 32)
        XCTAssertEqual(codeBlock.subband, .ll)
        XCTAssertTrue(codeBlock.data.isEmpty)
        XCTAssertEqual(codeBlock.passeCount, 0)
        XCTAssertEqual(codeBlock.zeroBitPlanes, 0)
    }
    
    /// Tests J2KCodeBlock with different subbands.
    func testCodeBlockSubbands() throws {
        let llBlock = J2KCodeBlock(index: 0, x: 0, y: 0, width: 32, height: 32, subband: .ll)
        let hlBlock = J2KCodeBlock(index: 1, x: 0, y: 0, width: 32, height: 32, subband: .hl)
        let lhBlock = J2KCodeBlock(index: 2, x: 0, y: 0, width: 32, height: 32, subband: .lh)
        let hhBlock = J2KCodeBlock(index: 3, x: 0, y: 0, width: 32, height: 32, subband: .hh)
        
        XCTAssertEqual(llBlock.subband, .ll)
        XCTAssertEqual(hlBlock.subband, .hl)
        XCTAssertEqual(lhBlock.subband, .lh)
        XCTAssertEqual(hhBlock.subband, .hh)
    }
    
    // MARK: - J2KSubband Tests
    
    /// Tests J2KSubband enum values.
    func testSubbandEnum() throws {
        XCTAssertEqual(J2KSubband.ll.rawValue, "LL")
        XCTAssertEqual(J2KSubband.hl.rawValue, "HL")
        XCTAssertEqual(J2KSubband.lh.rawValue, "LH")
        XCTAssertEqual(J2KSubband.hh.rawValue, "HH")
    }
    
    // MARK: - J2KColorSpace Tests
    
    /// Tests J2KColorSpace enum values.
    func testColorSpaceEnum() throws {
        let srgb = J2KColorSpace.sRGB
        let gray = J2KColorSpace.grayscale
        let ycbcr = J2KColorSpace.yCbCr
        let unknown = J2KColorSpace.unknown
        
        if case .sRGB = srgb {} else { XCTFail() }
        if case .grayscale = gray {} else { XCTFail() }
        if case .yCbCr = ycbcr {} else { XCTFail() }
        if case .unknown = unknown {} else { XCTFail() }
    }
    
    /// Tests J2KColorSpace with ICC profile.
    func testColorSpaceICCProfile() throws {
        let profileData = Data([0x00, 0x01, 0x02, 0x03])
        let colorSpace = J2KColorSpace.iccProfile(profileData)
        
        if case .iccProfile(let data) = colorSpace {
            XCTAssertEqual(data, profileData)
        } else {
            XCTFail("Expected ICC profile color space")
        }
    }
}
