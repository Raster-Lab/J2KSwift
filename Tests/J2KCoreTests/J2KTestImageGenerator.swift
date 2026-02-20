//
// J2KTestImageGenerator.swift
// J2KSwift
//
import XCTest
@testable import J2KCore
import Foundation

/// Utility for generating test images with various patterns.
///
/// This utility provides methods to create test images for validating
/// JPEG 2000 encoding and decoding operations.
///
/// ## Topics
///
/// ### Pattern Types
/// - ``Pattern``
///
/// ### Image Generation
/// - ``generate(width:height:components:bitDepth:pattern:)``
/// - ``generateWithData(width:height:components:bitDepth:pattern:)``
public struct J2KTestImageGenerator: Sendable {
    /// The type of pattern to generate.
    public enum Pattern: String, Sendable, CaseIterable {
        /// A solid color image (all pixels same value).
        case solid

        /// A horizontal gradient from left to right.
        case horizontalGradient

        /// A vertical gradient from top to bottom.
        case verticalGradient

        /// A diagonal gradient from top-left to bottom-right.
        case diagonalGradient

        /// A checkerboard pattern with alternating colors.
        case checkerboard

        /// Horizontal stripes.
        case horizontalStripes

        /// Vertical stripes.
        case verticalStripes

        /// Random noise pattern.
        case noise

        /// Edge test pattern with high contrast borders.
        case edges

        /// A ramp pattern testing all values.
        case ramp
    }

    /// Creates a new test image generator.
    public init() {}

    /// Generates a test image with the specified parameters.
    ///
    /// - Parameters:
    ///   - width: The width of the image in pixels.
    ///   - height: The height of the image in pixels.
    ///   - components: The number of color components (e.g., 1 for grayscale, 3 for RGB).
    ///   - bitDepth: The bit depth per component (default: 8).
    ///   - pattern: The pattern to generate (default: solid).
    ///   - seed: Random seed for noise pattern (default: 12345).
    /// - Returns: A J2KImage with the specified pattern.
    public func generate(
        width: Int,
        height: Int,
        components: Int,
        bitDepth: Int = 8,
        pattern: Pattern = .solid,
        seed: UInt64 = 12345
    ) -> J2KImage {
        J2KImage(width: width, height: height, components: components, bitDepth: bitDepth)
    }

    /// Generates a test image buffer with pixel data for a single component.
    ///
    /// This method creates a single-component (grayscale) image buffer with the
    /// specified pattern. For multi-component images, use `generateComponent`
    /// multiple times and combine them into a `J2KImage`.
    ///
    /// - Parameters:
    ///   - width: The width of the buffer in pixels.
    ///   - height: The height of the buffer in pixels.
    ///   - bitDepth: The bit depth per pixel (default: 8, clamped to 1-16).
    ///   - pattern: The pattern to generate (default: solid).
    ///   - seed: Random seed for noise pattern (default: 12345).
    /// - Returns: A J2KImageBuffer with the specified pattern.
    public func generateBuffer(
        width: Int,
        height: Int,
        bitDepth: Int = 8,
        pattern: Pattern = .solid,
        seed: UInt64 = 12345
    ) -> J2KImageBuffer {
        let clampedBitDepth = max(1, min(bitDepth, 16))
        var buffer = J2KImageBuffer(width: width, height: height, bitDepth: clampedBitDepth)
        let maxValue = (1 << clampedBitDepth) - 1

        switch pattern {
        case .solid:
            fillSolid(&buffer, value: maxValue / 2)

        case .horizontalGradient:
            fillHorizontalGradient(&buffer, maxValue: maxValue)

        case .verticalGradient:
            fillVerticalGradient(&buffer, maxValue: maxValue)

        case .diagonalGradient:
            fillDiagonalGradient(&buffer, maxValue: maxValue)

        case .checkerboard:
            fillCheckerboard(&buffer, maxValue: maxValue, blockSize: 8)

        case .horizontalStripes:
            fillHorizontalStripes(&buffer, maxValue: maxValue, stripeHeight: 4)

        case .verticalStripes:
            fillVerticalStripes(&buffer, maxValue: maxValue, stripeWidth: 4)

        case .noise:
            fillNoise(&buffer, maxValue: maxValue, seed: seed)

        case .edges:
            fillEdges(&buffer, maxValue: maxValue, borderWidth: 4)

        case .ramp:
            fillRamp(&buffer, maxValue: maxValue)
        }

        return buffer
    }

    /// Generates a component with pixel data for a given pattern.
    ///
    /// - Parameters:
    ///   - index: The component index.
    ///   - width: The width of the component in pixels.
    ///   - height: The height of the component in pixels.
    ///   - bitDepth: The bit depth (default: 8).
    ///   - pattern: The pattern to generate (default: solid).
    ///   - seed: Random seed for noise pattern (default: 12345).
    /// - Returns: A J2KComponent with pixel data.
    public func generateComponent(
        index: Int,
        width: Int,
        height: Int,
        bitDepth: Int = 8,
        pattern: Pattern = .solid,
        seed: UInt64 = 12345
    ) -> J2KComponent {
        let buffer = generateBuffer(
            width: width,
            height: height,
            bitDepth: bitDepth,
            pattern: pattern,
            seed: seed
        )

        return J2KComponent(
            index: index,
            bitDepth: bitDepth,
            width: width,
            height: height,
            data: buffer.toData()
        )
    }

    // MARK: - Pattern Fill Methods

    private func fillSolid(_ buffer: inout J2KImageBuffer, value: Int) {
        let count = buffer.width * buffer.height
        for i in 0..<count {
            buffer.setPixel(at: i, value: value)
        }
    }

    private func fillHorizontalGradient(_ buffer: inout J2KImageBuffer, maxValue: Int) {
        let width = buffer.width
        let height = buffer.height

        for y in 0..<height {
            for x in 0..<width {
                let value = width > 1 ? (x * maxValue) / (width - 1) : maxValue / 2
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillVerticalGradient(_ buffer: inout J2KImageBuffer, maxValue: Int) {
        let width = buffer.width
        let height = buffer.height

        for y in 0..<height {
            let value = height > 1 ? (y * maxValue) / (height - 1) : maxValue / 2
            for x in 0..<width {
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillDiagonalGradient(_ buffer: inout J2KImageBuffer, maxValue: Int) {
        let width = buffer.width
        let height = buffer.height
        let diagonal = width + height - 2

        for y in 0..<height {
            for x in 0..<width {
                let pos = x + y
                let value = diagonal > 0 ? (pos * maxValue) / diagonal : maxValue / 2
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillCheckerboard(_ buffer: inout J2KImageBuffer, maxValue: Int, blockSize: Int) {
        let width = buffer.width
        let height = buffer.height

        for y in 0..<height {
            for x in 0..<width {
                let blockX = x / blockSize
                let blockY = y / blockSize
                let isWhite = (blockX + blockY).isMultiple(of: 2)
                let value = isWhite ? maxValue : 0
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillHorizontalStripes(_ buffer: inout J2KImageBuffer, maxValue: Int, stripeHeight: Int) {
        let width = buffer.width
        let height = buffer.height

        for y in 0..<height {
            let stripeIndex = y / stripeHeight
            let value = stripeIndex.isMultiple(of: 2) ? maxValue : 0
            for x in 0..<width {
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillVerticalStripes(_ buffer: inout J2KImageBuffer, maxValue: Int, stripeWidth: Int) {
        let width = buffer.width
        let height = buffer.height

        for y in 0..<height {
            for x in 0..<width {
                let stripeIndex = x / stripeWidth
                let value = stripeIndex.isMultiple(of: 2) ? maxValue : 0
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillNoise(_ buffer: inout J2KImageBuffer, maxValue: Int, seed: UInt64) {
        let width = buffer.width
        let height = buffer.height

        // Simple PRNG (xorshift64)
        var state = seed

        for y in 0..<height {
            for x in 0..<width {
                // xorshift64 step
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17

                let value = Int(state % UInt64(maxValue + 1))
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillEdges(_ buffer: inout J2KImageBuffer, maxValue: Int, borderWidth: Int) {
        let width = buffer.width
        let height = buffer.height
        let midValue = maxValue / 2

        for y in 0..<height {
            for x in 0..<width {
                let isTopBorder = y < borderWidth
                let isBottomBorder = y >= height - borderWidth
                let isLeftBorder = x < borderWidth
                let isRightBorder = x >= width - borderWidth

                let value: Int
                if isTopBorder || isBottomBorder || isLeftBorder || isRightBorder {
                    value = maxValue
                } else {
                    value = midValue
                }
                buffer.setPixel(x: x, y: y, value: value)
            }
        }
    }

    private func fillRamp(_ buffer: inout J2KImageBuffer, maxValue: Int) {
        let width = buffer.width
        let height = buffer.height
        let totalPixels = width * height

        for i in 0..<totalPixels {
            let value = totalPixels > 1 ? (i * maxValue) / (totalPixels - 1) : 0
            buffer.setPixel(at: i, value: value)
        }
    }

    // MARK: - Edge Case Image Generators

    /// Generates a minimal 1x1 pixel image.
    ///
    /// - Parameters:
    ///   - components: Number of components (default: 1).
    ///   - bitDepth: Bit depth (default: 8).
    /// - Returns: A minimal 1x1 J2KImage.
    public func generateMinimalImage(components: Int = 1, bitDepth: Int = 8) -> J2KImage {
        J2KImage(width: 1, height: 1, components: components, bitDepth: bitDepth)
    }

    /// Generates a square image with power-of-two dimensions.
    ///
    /// - Parameters:
    ///   - power: The power of 2 for dimensions (e.g., 8 for 256x256).
    ///   - components: Number of components (default: 3).
    ///   - bitDepth: Bit depth (default: 8).
    /// - Returns: A square J2KImage with dimensions 2^power.
    public func generatePowerOfTwoImage(
        power: Int,
        components: Int = 3,
        bitDepth: Int = 8
    ) -> J2KImage {
        let size = 1 << power
        return J2KImage(width: size, height: size, components: components, bitDepth: bitDepth)
    }

    /// Generates an image with non-power-of-two dimensions.
    ///
    /// - Parameters:
    ///   - width: Width (default: 127, a prime number).
    ///   - height: Height (default: 131, a prime number).
    ///   - components: Number of components (default: 3).
    ///   - bitDepth: Bit depth (default: 8).
    /// - Returns: A J2KImage with non-power-of-two dimensions.
    public func generateNonPowerOfTwoImage(
        width: Int = 127,
        height: Int = 131,
        components: Int = 3,
        bitDepth: Int = 8
    ) -> J2KImage {
        J2KImage(width: width, height: height, components: components, bitDepth: bitDepth)
    }

    /// Generates an image with tiling configuration.
    ///
    /// - Parameters:
    ///   - width: Image width.
    ///   - height: Image height.
    ///   - tileWidth: Tile width.
    ///   - tileHeight: Tile height.
    ///   - components: Number of components (default: 3).
    ///   - bitDepth: Bit depth (default: 8).
    /// - Returns: A tiled J2KImage.
    public func generateTiledImage(
        width: Int,
        height: Int,
        tileWidth: Int,
        tileHeight: Int,
        components: Int = 3,
        bitDepth: Int = 8
    ) -> J2KImage {
        let imageComponents = (0..<components).map { index in
            J2KComponent(
                index: index,
                bitDepth: bitDepth,
                width: width,
                height: height
            )
        }

        return J2KImage(
            width: width,
            height: height,
            components: imageComponents,
            tileWidth: tileWidth,
            tileHeight: tileHeight
        )
    }

    /// Generates an image with specific bit depth for testing.
    ///
    /// - Parameter bitDepth: The bit depth (1-16).
    /// - Returns: A J2KImage with the specified bit depth.
    public func generateBitDepthTestImage(bitDepth: Int) -> J2KImage {
        J2KImage(width: 64, height: 64, components: 1, bitDepth: bitDepth)
    }

    /// Generates an image with subsampled components (like YCbCr 4:2:0).
    ///
    /// - Parameters:
    ///   - width: Full resolution width.
    ///   - height: Full resolution height.
    /// - Returns: A J2KImage with subsampled chroma components.
    public func generateSubsampledImage(width: Int, height: Int) -> J2KImage {
        let components = [
            // Y component - full resolution
            J2KComponent(index: 0, bitDepth: 8, width: width, height: height, subsamplingX: 1, subsamplingY: 1),
            // Cb component - half resolution
            J2KComponent(index: 1, bitDepth: 8, width: width / 2, height: height / 2, subsamplingX: 2, subsamplingY: 2),
            // Cr component - half resolution
            J2KComponent(index: 2, bitDepth: 8, width: width / 2, height: height / 2, subsamplingX: 2, subsamplingY: 2)
        ]

        return J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: .yCbCr
        )
    }
}

// MARK: - Test Image Generator Tests

/// Tests for the test image generator.
final class J2KTestImageGeneratorTests: XCTestCase {
    private let generator = J2KTestImageGenerator()

    // MARK: - Basic Pattern Tests

    func testGenerateSolidPattern() throws {
        let buffer = generator.generateBuffer(
            width: 10,
            height: 10,
            bitDepth: 8,
            pattern: .solid
        )

        XCTAssertEqual(buffer.width, 10)
        XCTAssertEqual(buffer.height, 10)

        // All pixels should have the same value (127 for 8-bit solid)
        let firstValue = buffer.getPixel(at: 0)
        for i in 1..<100 {
            XCTAssertEqual(buffer.getPixel(at: i), firstValue)
        }
    }

    func testGenerateHorizontalGradient() throws {
        let buffer = generator.generateBuffer(
            width: 256,
            height: 10,
            bitDepth: 8,
            pattern: .horizontalGradient
        )

        // First column should be 0, last column should be 255
        XCTAssertEqual(buffer.getPixel(x: 0, y: 0), 0)
        XCTAssertEqual(buffer.getPixel(x: 255, y: 0), 255)

        // Values should increase left to right
        let leftValue = buffer.getPixel(x: 50, y: 5)
        let rightValue = buffer.getPixel(x: 200, y: 5)
        XCTAssertLessThan(leftValue, rightValue)
    }

    func testGenerateVerticalGradient() throws {
        let buffer = generator.generateBuffer(
            width: 10,
            height: 256,
            bitDepth: 8,
            pattern: .verticalGradient
        )

        // First row should be 0, last row should be 255
        XCTAssertEqual(buffer.getPixel(x: 0, y: 0), 0)
        XCTAssertEqual(buffer.getPixel(x: 0, y: 255), 255)

        // Values should increase top to bottom
        let topValue = buffer.getPixel(x: 5, y: 50)
        let bottomValue = buffer.getPixel(x: 5, y: 200)
        XCTAssertLessThan(topValue, bottomValue)
    }

    func testGenerateDiagonalGradient() throws {
        let buffer = generator.generateBuffer(
            width: 100,
            height: 100,
            bitDepth: 8,
            pattern: .diagonalGradient
        )

        // Top-left should be minimum
        let topLeft = buffer.getPixel(x: 0, y: 0)
        XCTAssertEqual(topLeft, 0)

        // Bottom-right should be maximum
        let bottomRight = buffer.getPixel(x: 99, y: 99)
        XCTAssertEqual(bottomRight, 255)
    }

    func testGenerateCheckerboard() throws {
        let buffer = generator.generateBuffer(
            width: 16,
            height: 16,
            bitDepth: 8,
            pattern: .checkerboard
        )

        // Check alternating pattern with 8x8 blocks (default blockSize)
        let block00 = buffer.getPixel(x: 0, y: 0)
        let block10 = buffer.getPixel(x: 8, y: 0)
        let block01 = buffer.getPixel(x: 0, y: 8)
        let block11 = buffer.getPixel(x: 8, y: 8)

        XCTAssertNotEqual(block00, block10)
        XCTAssertNotEqual(block00, block01)
        XCTAssertEqual(block00, block11)
    }

    func testGenerateHorizontalStripes() throws {
        let buffer = generator.generateBuffer(
            width: 10,
            height: 16,
            bitDepth: 8,
            pattern: .horizontalStripes
        )

        // Rows within the same stripe should have the same value
        let row0 = buffer.getPixel(x: 0, y: 0)
        let row3 = buffer.getPixel(x: 0, y: 3)
        XCTAssertEqual(row0, row3)

        // Adjacent stripes should differ
        let row4 = buffer.getPixel(x: 0, y: 4)
        XCTAssertNotEqual(row0, row4)
    }

    func testGenerateVerticalStripes() throws {
        let buffer = generator.generateBuffer(
            width: 16,
            height: 10,
            bitDepth: 8,
            pattern: .verticalStripes
        )

        // Columns within the same stripe should have the same value
        let col0 = buffer.getPixel(x: 0, y: 0)
        let col3 = buffer.getPixel(x: 3, y: 0)
        XCTAssertEqual(col0, col3)

        // Adjacent stripes should differ
        let col4 = buffer.getPixel(x: 4, y: 0)
        XCTAssertNotEqual(col0, col4)
    }

    func testGenerateNoise() throws {
        let buffer1 = generator.generateBuffer(
            width: 10,
            height: 10,
            bitDepth: 8,
            pattern: .noise,
            seed: 12345
        )

        let buffer2 = generator.generateBuffer(
            width: 10,
            height: 10,
            bitDepth: 8,
            pattern: .noise,
            seed: 12345
        )

        // Same seed should produce same noise
        for i in 0..<100 {
            XCTAssertEqual(buffer1.getPixel(at: i), buffer2.getPixel(at: i))
        }

        // Different seed should produce different noise
        let buffer3 = generator.generateBuffer(
            width: 10,
            height: 10,
            bitDepth: 8,
            pattern: .noise,
            seed: 54321
        )

        var differences = 0
        for i in 0..<100 where buffer1.getPixel(at: i) != buffer3.getPixel(at: i) {
            differences += 1
        }
        XCTAssertGreaterThan(differences, 50) // Should have many differences
    }

    func testGenerateEdges() throws {
        let buffer = generator.generateBuffer(
            width: 20,
            height: 20,
            bitDepth: 8,
            pattern: .edges
        )

        // Border pixels should be max value
        XCTAssertEqual(buffer.getPixel(x: 0, y: 0), 255)
        XCTAssertEqual(buffer.getPixel(x: 19, y: 0), 255)
        XCTAssertEqual(buffer.getPixel(x: 0, y: 19), 255)
        XCTAssertEqual(buffer.getPixel(x: 19, y: 19), 255)

        // Interior pixels should be mid value
        XCTAssertEqual(buffer.getPixel(x: 10, y: 10), 127)
    }

    func testGenerateRamp() throws {
        let buffer = generator.generateBuffer(
            width: 16,
            height: 16,
            bitDepth: 8,
            pattern: .ramp
        )

        // First pixel should be 0
        XCTAssertEqual(buffer.getPixel(at: 0), 0)

        // Last pixel should be 255
        XCTAssertEqual(buffer.getPixel(at: 255), 255)

        // Should increase monotonically
        for i in 1..<256 {
            XCTAssertGreaterThanOrEqual(buffer.getPixel(at: i), buffer.getPixel(at: i - 1))
        }
    }

    // MARK: - Edge Case Tests

    func testGenerateMinimalImage() throws {
        let image = generator.generateMinimalImage()

        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
        XCTAssertEqual(image.components.count, 1)
    }

    func testGeneratePowerOfTwoImage() throws {
        let image = generator.generatePowerOfTwoImage(power: 8)

        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)
    }

    func testGenerateNonPowerOfTwoImage() throws {
        let image = generator.generateNonPowerOfTwoImage()

        XCTAssertEqual(image.width, 127)
        XCTAssertEqual(image.height, 131)
    }

    func testGenerateTiledImage() throws {
        let image = generator.generateTiledImage(
            width: 512,
            height: 512,
            tileWidth: 128,
            tileHeight: 128
        )

        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
        XCTAssertEqual(image.tileWidth, 128)
        XCTAssertEqual(image.tileHeight, 128)
        XCTAssertEqual(image.tilesX, 4)
        XCTAssertEqual(image.tilesY, 4)
        XCTAssertEqual(image.tileCount, 16)
    }

    func testGenerateBitDepthTestImages() throws {
        for bitDepth in [1, 8, 12, 16] {
            let image = generator.generateBitDepthTestImage(bitDepth: bitDepth)
            XCTAssertEqual(image.components[0].bitDepth, bitDepth)
        }
    }

    func testGenerateSubsampledImage() throws {
        let image = generator.generateSubsampledImage(width: 256, height: 256)

        XCTAssertEqual(image.components.count, 3)

        // Y component - full resolution
        XCTAssertEqual(image.components[0].width, 256)
        XCTAssertEqual(image.components[0].height, 256)
        XCTAssertEqual(image.components[0].subsamplingX, 1)
        XCTAssertEqual(image.components[0].subsamplingY, 1)

        // Cb component - half resolution
        XCTAssertEqual(image.components[1].width, 128)
        XCTAssertEqual(image.components[1].height, 128)
        XCTAssertEqual(image.components[1].subsamplingX, 2)
        XCTAssertEqual(image.components[1].subsamplingY, 2)

        // Cr component - half resolution
        XCTAssertEqual(image.components[2].width, 128)
        XCTAssertEqual(image.components[2].height, 128)
        XCTAssertEqual(image.components[2].subsamplingX, 2)
        XCTAssertEqual(image.components[2].subsamplingY, 2)
    }

    func testGenerateComponent() throws {
        let component = generator.generateComponent(
            index: 0,
            width: 64,
            height: 64,
            bitDepth: 8,
            pattern: .horizontalGradient
        )

        XCTAssertEqual(component.index, 0)
        XCTAssertEqual(component.width, 64)
        XCTAssertEqual(component.height, 64)
        XCTAssertEqual(component.bitDepth, 8)
        XCTAssertFalse(component.data.isEmpty)
    }

    // MARK: - Bit Depth Tests

    func testGenerate16BitBuffer() throws {
        let buffer = generator.generateBuffer(
            width: 100,
            height: 100,
            bitDepth: 16,
            pattern: .horizontalGradient
        )

        // Should use full 16-bit range
        XCTAssertEqual(buffer.getPixel(x: 0, y: 0), 0)
        XCTAssertEqual(buffer.getPixel(x: 99, y: 0), 65535)
    }

    func testAllPatternsGenerate() throws {
        for pattern in J2KTestImageGenerator.Pattern.allCases {
            let buffer = generator.generateBuffer(
                width: 32,
                height: 32,
                bitDepth: 8,
                pattern: pattern
            )

            XCTAssertEqual(buffer.width, 32, "Pattern \(pattern.rawValue) width mismatch")
            XCTAssertEqual(buffer.height, 32, "Pattern \(pattern.rawValue) height mismatch")
            XCTAssertEqual(buffer.count, 1024, "Pattern \(pattern.rawValue) pixel count mismatch")
        }
    }
}
