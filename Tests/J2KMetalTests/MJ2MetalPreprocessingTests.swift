/// # MJ2MetalPreprocessingTests
///
/// Tests for Metal-accelerated preprocessing of Motion JPEG 2000 frames.

#if canImport(Metal)
import XCTest
import Metal
import CoreVideo
@testable import J2KMetal
@testable import J2KCore

final class MJ2MetalPreprocessingTests: XCTestCase {
    
    private var device: MTLDevice?
    
    override func setUp() {
        super.setUp()
        device = MTLCreateSystemDefaultDevice()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let config = MJ2MetalPreprocessingConfiguration.default()
        let preprocessing = try MJ2MetalPreprocessing(device: device, configuration: config)
        
        XCTAssertNotNil(preprocessing)
    }
    
    func testInitializationWithCustomConfiguration() throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let config = MJ2MetalPreprocessingConfiguration(
            pixelFormat: .yuv420BiplanarFullRange,
            scalingMode: .lanczos,
            enableZeroCopy: true,
            maxTextureSize: 4096
        )
        
        let preprocessing = try MJ2MetalPreprocessing(device: device, configuration: config)
        XCTAssertNotNil(preprocessing)
    }
    
    // MARK: - Configuration Tests
    
    func testDefaultConfiguration() throws {
        let config = MJ2MetalPreprocessingConfiguration.default()
        
        XCTAssertEqual(config.pixelFormat, .bgra32)
        XCTAssertEqual(config.scalingMode, .bilinear)
        XCTAssertTrue(config.enableZeroCopy)
        XCTAssertEqual(config.maxTextureSize, 8192)
    }
    
    func testPixelFormatConversions() throws {
        // Test Metal pixel format mappings
        XCTAssertEqual(MJ2MetalPixelFormat.argb32.metalPixelFormat, .bgra8Unorm)
        XCTAssertEqual(MJ2MetalPixelFormat.bgra32.metalPixelFormat, .bgra8Unorm)
        
        // Test Core Video pixel format mappings
        XCTAssertEqual(MJ2MetalPixelFormat.argb32.cvPixelFormat, kCVPixelFormatType_32ARGB)
        XCTAssertEqual(MJ2MetalPixelFormat.bgra32.cvPixelFormat, kCVPixelFormatType_32BGRA)
        XCTAssertEqual(MJ2MetalPixelFormat.yuv420BiplanarVideoRange.cvPixelFormat, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }
    
    // MARK: - J2KImage to CVPixelBuffer Tests
    
    func testConvertJ2KImageToPixelBuffer() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createTestImage(width: 640, height: 480)
        
        let pixelBuffer = try await preprocessing.convertToPixelBuffer(
            image: image,
            outputFormat: .bgra32
        )
        
        XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 640)
        XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), 480)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_32BGRA)
    }
    
    func testConvertJ2KImageToPixelBufferDifferentSizes() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        
        let sizes = [
            (width: 320, height: 240),
            (width: 640, height: 480),
            (width: 1280, height: 720),
            (width: 1920, height: 1080)
        ]
        
        for size in sizes {
            let image = createTestImage(width: size.width, height: size.height)
            let pixelBuffer = try await preprocessing.convertToPixelBuffer(
                image: image,
                outputFormat: .bgra32
            )
            
            XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), size.width)
            XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), size.height)
        }
    }
    
    func testConvertJ2KImageInvalidDimensions() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let config = MJ2MetalPreprocessingConfiguration(
            pixelFormat: .bgra32,
            scalingMode: .bilinear,
            enableZeroCopy: true,
            maxTextureSize: 1024  // Small limit
        )
        
        let preprocessing = try MJ2MetalPreprocessing(device: device, configuration: config)
        let image = createTestImage(width: 2048, height: 2048)  // Exceeds max
        
        do {
            _ = try await preprocessing.convertToPixelBuffer(image: image)
            XCTFail("Should throw error for dimensions exceeding max texture size")
        } catch MJ2MetalPreprocessingError.invalidDimensions {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - CVPixelBuffer to J2KImage Tests
    
    func testConvertPixelBufferToJ2KImage() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let pixelBuffer = try createTestPixelBuffer(width: 640, height: 480)
        
        let image = try await preprocessing.convertToJ2KImage(
            pixelBuffer: pixelBuffer,
            targetColorSpace: .sRGB
        )
        
        XCTAssertEqual(image.width, 640)
        XCTAssertEqual(image.height, 480)
        XCTAssertEqual(image.components.count, 3)
        XCTAssertEqual(image.colorSpace, .sRGB)
    }
    
    func testConvertPixelBufferDifferentColorSpaces() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let pixelBuffer = try createTestPixelBuffer(width: 640, height: 480)
        
        let colorSpaces: [J2KColorSpace] = [.sRGB, .yCbCr, .grayscale]
        
        for colorSpace in colorSpaces {
            let image = try await preprocessing.convertToJ2KImage(
                pixelBuffer: pixelBuffer,
                targetColorSpace: colorSpace
            )
            
            XCTAssertEqual(image.colorSpace, colorSpace)
        }
    }
    
    // MARK: - Scaling Tests
    
    func testScaleImage() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createTestImage(width: 1920, height: 1080)
        
        let scaledImage = try await preprocessing.scale(
            image: image,
            targetWidth: 1280,
            targetHeight: 720,
            scalingMode: .bilinear
        )
        
        XCTAssertEqual(scaledImage.width, 1280)
        XCTAssertEqual(scaledImage.height, 720)
        XCTAssertEqual(scaledImage.components.count, image.components.count)
    }
    
    func testScaleImageNoChange() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createTestImage(width: 640, height: 480)
        
        // Scale to same dimensions
        let scaledImage = try await preprocessing.scale(
            image: image,
            targetWidth: 640,
            targetHeight: 480
        )
        
        XCTAssertEqual(scaledImage.width, 640)
        XCTAssertEqual(scaledImage.height, 480)
    }
    
    func testScaleImageDifferentModes() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createTestImage(width: 1920, height: 1080)
        
        let modes: [MJ2MetalScalingMode] = [.nearest, .bilinear, .lanczos]
        
        for mode in modes {
            let scaledImage = try await preprocessing.scale(
                image: image,
                targetWidth: 1280,
                targetHeight: 720,
                scalingMode: mode
            )
            
            XCTAssertEqual(scaledImage.width, 1280)
            XCTAssertEqual(scaledImage.height, 720)
        }
    }
    
    func testScaleImageUpscaling() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createTestImage(width: 640, height: 480)
        
        let scaledImage = try await preprocessing.scale(
            image: image,
            targetWidth: 1920,
            targetHeight: 1080
        )
        
        XCTAssertEqual(scaledImage.width, 1920)
        XCTAssertEqual(scaledImage.height, 1080)
    }
    
    func testScaleImageDownscaling() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createTestImage(width: 3840, height: 2160)
        
        let scaledImage = try await preprocessing.scale(
            image: image,
            targetWidth: 1920,
            targetHeight: 1080
        )
        
        XCTAssertEqual(scaledImage.width, 1920)
        XCTAssertEqual(scaledImage.height, 1080)
    }
    
    func testScaleImageInvalidDimensions() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createTestImage(width: 640, height: 480)
        
        do {
            _ = try await preprocessing.scale(
                image: image,
                targetWidth: 0,
                targetHeight: 480
            )
            XCTFail("Should throw error for invalid dimensions")
        } catch MJ2MetalPreprocessingError.invalidDimensions {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Component Handling Tests
    
    func testImageWithSubsampledComponents() async throws {
        guard let device = device else {
            throw XCTSkip("Metal device not available")
        }
        
        let preprocessing = try MJ2MetalPreprocessing(device: device)
        let image = createSubsampledImage(width: 1920, height: 1080)
        
        let scaledImage = try await preprocessing.scale(
            image: image,
            targetWidth: 1280,
            targetHeight: 720
        )
        
        XCTAssertEqual(scaledImage.width, 1280)
        XCTAssertEqual(scaledImage.height, 720)
        
        // Check that subsampling is preserved
        for (idx, component) in scaledImage.components.enumerated() {
            XCTAssertEqual(
                component.subsamplingX,
                image.components[idx].subsamplingX
            )
            XCTAssertEqual(
                component.subsamplingY,
                image.components[idx].subsamplingY
            )
        }
    }
    
    func testImageWithGrayscaleComponent() throws {
        let image = createGrayscaleImage(width: 640, height: 480)
        
        XCTAssertEqual(image.components.count, 1)
        XCTAssertEqual(image.colorSpace, .grayscale)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorTypes() throws {
        let errors: [MJ2MetalPreprocessingError] = [
            .metalNotAvailable,
            .pipelineCreationFailed("test"),
            .invalidDimensions,
            .unsupportedPixelFormat,
            .textureCreationFailed,
            .bufferCreationFailed,
            .executionFailed
        ]
        
        for error in errors {
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage(width: Int, height: Int) -> J2KImage {
        let componentSize = width * height
        
        // Create RGB components with test pattern
        var rData = Data(count: componentSize)
        var gData = Data(count: componentSize)
        var bData = Data(count: componentSize)
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                rData[index] = UInt8((x * 255) / width)
                gData[index] = UInt8((y * 255) / height)
                bData[index] = 128
            }
        }
        
        let components = [
            J2KComponent(
                index: 0,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: rData
            ),
            J2KComponent(
                index: 1,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: gData
            ),
            J2KComponent(
                index: 2,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: bData
            )
        ]
        
        return J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: .sRGB,
            offsetX: 0,
            offsetY: 0,
            tileWidth: 0,
            tileHeight: 0,
            tileOffsetX: 0,
            tileOffsetY: 0
        )
    }
    
    private func createSubsampledImage(width: Int, height: Int) -> J2KImage {
        // Create 4:2:0 subsampled image (Y full resolution, Cb/Cr half resolution)
        let ySize = width * height
        let cSize = (width / 2) * (height / 2)
        
        let yData = Data(repeating: 128, count: ySize)
        let cbData = Data(repeating: 64, count: cSize)
        let crData = Data(repeating: 192, count: cSize)
        
        let components = [
            J2KComponent(
                index: 0,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: yData
            ),
            J2KComponent(
                index: 1,
                bitDepth: 8,
                signed: false,
                width: width / 2,
                height: height / 2,
                subsamplingX: 2,
                subsamplingY: 2,
                data: cbData
            ),
            J2KComponent(
                index: 2,
                bitDepth: 8,
                signed: false,
                width: width / 2,
                height: height / 2,
                subsamplingX: 2,
                subsamplingY: 2,
                data: crData
            )
        ]
        
        return J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: .yCbCr,
            offsetX: 0,
            offsetY: 0,
            tileWidth: 0,
            tileHeight: 0,
            tileOffsetX: 0,
            tileOffsetY: 0
        )
    }
    
    private func createGrayscaleImage(width: Int, height: Int) -> J2KImage {
        let componentSize = width * height
        let data = Data(repeating: 128, count: componentSize)
        
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
        
        return J2KImage(
            width: width,
            height: height,
            components: [component],
            colorSpace: .grayscale,
            offsetX: 0,
            offsetY: 0,
            tileWidth: 0,
            tileHeight: 0,
            tileOffsetX: 0,
            tileOffsetY: 0
        )
    }
    
    private func createTestPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw MJ2MetalPreprocessingError.textureCreationFailed
        }
        
        // Fill with test pattern
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let data = baseAddress.assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    data[offset + 0] = UInt8((x * 255) / width)      // B
                    data[offset + 1] = UInt8((y * 255) / height)     // G
                    data[offset + 2] = 128                            // R
                    data[offset + 3] = 255                            // A
                }
            }
        }
        
        return buffer
    }
}

#else
// Provide empty test class for non-Metal platforms
import XCTest

final class MJ2MetalPreprocessingTests: XCTestCase {
    func testMetalNotAvailable() throws {
        throw XCTSkip("Metal is not available on this platform")
    }
}
#endif
