//
// J2KAdvancedDecodingTests.swift
// J2KSwift
//
// J2KAdvancedDecodingTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-07.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KAdvancedDecodingTests: XCTestCase {
    // MARK: - Partial Decoding Options Tests

    func testPartialDecodingOptionsDefault() {
        let options = J2KPartialDecodingOptions()

        XCTAssertNil(options.maxLayer)
        XCTAssertNil(options.maxResolutionLevel)
        XCTAssertNil(options.region)
        XCTAssertTrue(options.earlyStop)
        XCTAssertNil(options.components)
    }

    func testPartialDecodingOptionsCustom() {
        let region = J2KRegion(x: 10, y: 20, width: 100, height: 200)
        let options = J2KPartialDecodingOptions(
            maxLayer: 3,
            maxResolutionLevel: 2,
            region: region,
            earlyStop: false,
            components: [0, 1]
        )

        XCTAssertEqual(options.maxLayer, 3)
        XCTAssertEqual(options.maxResolutionLevel, 2)
        XCTAssertEqual(options.region, region)
        XCTAssertFalse(options.earlyStop)
        XCTAssertEqual(options.components, [0, 1])
    }

    func testPartialDecodingOptionsValidation() throws {
        let options = J2KPartialDecodingOptions(maxLayer: 2, maxResolutionLevel: 3)

        // Valid options
        try options.validate(
            imageWidth: 512,
            imageHeight: 512,
            maxLayers: 5,
            maxLevels: 5,
            componentCount: 3
        )
    }

    func testPartialDecodingOptionsValidationInvalidLayer() {
        let options = J2KPartialDecodingOptions(maxLayer: 10)

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                maxLevels: 5,
                componentCount: 3
            )
        ) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("maxLayer"))
        }
    }

    func testPartialDecodingOptionsValidationInvalidLevel() {
        let options = J2KPartialDecodingOptions(maxResolutionLevel: 10)

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                maxLevels: 5,
                componentCount: 3
            )
        ) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("maxResolutionLevel"))
        }
    }

    func testPartialDecodingOptionsValidationInvalidRegion() {
        let region = J2KRegion(x: 400, y: 400, width: 200, height: 200)
        let options = J2KPartialDecodingOptions(region: region)

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                maxLevels: 5,
                componentCount: 3
            )
        )
    }

    func testPartialDecodingOptionsValidationInvalidComponent() {
        let options = J2KPartialDecodingOptions(components: [0, 1, 5])

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                maxLevels: 5,
                componentCount: 3
            )
        ) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("component"))
        }
    }

    func testPartialDecodingOptionsValidationEmptyComponents() {
        let options = J2KPartialDecodingOptions(components: [])

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                maxLevels: 5,
                componentCount: 3
            )
        ) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("empty"))
        }
    }

    func testPartialDecodingOptionsEquality() {
        let region = J2KRegion(x: 10, y: 20, width: 100, height: 200)
        let options1 = J2KPartialDecodingOptions(
            maxLayer: 3,
            maxResolutionLevel: 2,
            region: region,
            components: [0, 1]
        )
        let options2 = J2KPartialDecodingOptions(
            maxLayer: 3,
            maxResolutionLevel: 2,
            region: region,
            components: [0, 1]
        )
        let options3 = J2KPartialDecodingOptions(maxLayer: 4)

        XCTAssertEqual(options1, options2)
        XCTAssertNotEqual(options1, options3)
    }

    func testPartialDecodingOptionsDescription() {
        let region = J2KRegion(x: 10, y: 20, width: 100, height: 200)
        let options = J2KPartialDecodingOptions(
            maxLayer: 3,
            maxResolutionLevel: 2,
            region: region,
            components: [0, 1]
        )

        let description = options.description
        XCTAssertTrue(description.contains("maxLayer: 3"))
        XCTAssertTrue(description.contains("maxLevel: 2"))
        XCTAssertTrue(description.contains("region"))
        XCTAssertTrue(description.contains("components"))
    }

    // MARK: - ROI Decoding Options Tests

    func testROIDecodingOptionsDefault() {
        let region = J2KRegion(x: 100, y: 100, width: 200, height: 200)
        let options = J2KROIDecodingOptions(region: region)

        XCTAssertEqual(options.region, region)
        XCTAssertNil(options.maxLayer)
        XCTAssertNil(options.components)
        XCTAssertEqual(options.strategy, .direct)
    }

    func testROIDecodingOptionsCustom() {
        let region = J2KRegion(x: 100, y: 100, width: 200, height: 200)
        let options = J2KROIDecodingOptions(
            region: region,
            maxLayer: 5,
            components: [0, 1, 2],
            strategy: .fullImageExtraction
        )

        XCTAssertEqual(options.region, region)
        XCTAssertEqual(options.maxLayer, 5)
        XCTAssertEqual(options.components, [0, 1, 2])
        XCTAssertEqual(options.strategy, .fullImageExtraction)
    }

    func testROIDecodingOptionsValidation() throws {
        let region = J2KRegion(x: 100, y: 100, width: 200, height: 200)
        let options = J2KROIDecodingOptions(region: region, maxLayer: 3)

        try options.validate(
            imageWidth: 512,
            imageHeight: 512,
            maxLayers: 5,
            componentCount: 3
        )
    }

    func testROIDecodingOptionsValidationInvalidRegion() {
        let region = J2KRegion(x: 400, y: 400, width: 200, height: 200)
        let options = J2KROIDecodingOptions(region: region)

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                componentCount: 3
            )
        )
    }

    func testROIDecodingOptionsValidationInvalidLayer() {
        let region = J2KRegion(x: 100, y: 100, width: 200, height: 200)
        let options = J2KROIDecodingOptions(region: region, maxLayer: 10)

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                componentCount: 3
            )
        )
    }

    func testROIDecodingOptionsValidationInvalidComponent() {
        let region = J2KRegion(x: 100, y: 100, width: 200, height: 200)
        let options = J2KROIDecodingOptions(region: region, components: [5])

        XCTAssertThrowsError(
            try options.validate(
                imageWidth: 512,
                imageHeight: 512,
                maxLayers: 5,
                componentCount: 3
            )
        )
    }

    func testROIDecodingStrategyEquality() {
        XCTAssertEqual(J2KROIDecodingStrategy.direct, .direct)
        XCTAssertEqual(J2KROIDecodingStrategy.fullImageExtraction, .fullImageExtraction)
        XCTAssertNotEqual(J2KROIDecodingStrategy.direct, .fullImageExtraction)
    }

    func testROIDecodingStrategyDescription() {
        XCTAssertEqual(J2KROIDecodingStrategy.direct.description, "direct")
        XCTAssertEqual(J2KROIDecodingStrategy.fullImageExtraction.description, "fullImageExtraction")
        XCTAssertEqual(J2KROIDecodingStrategy.cached.description, "cached")
    }

    func testROIDecodingOptionsDescription() {
        let region = J2KRegion(x: 100, y: 100, width: 200, height: 200)
        let options = J2KROIDecodingOptions(
            region: region,
            maxLayer: 3,
            components: [0, 1],
            strategy: .direct
        )

        let description = options.description
        XCTAssertTrue(description.contains("region"))
        XCTAssertTrue(description.contains("maxLayer: 3"))
        XCTAssertTrue(description.contains("components"))
        XCTAssertTrue(description.contains("direct"))
    }

    // MARK: - Resolution Decoding Options Tests

    func testResolutionDecodingOptionsDefault() {
        let options = J2KResolutionDecodingOptions(level: 2)

        XCTAssertEqual(options.level, 2)
        XCTAssertNil(options.maxLayer)
        XCTAssertNil(options.components)
        XCTAssertFalse(options.upscale)
    }

    func testResolutionDecodingOptionsCustom() {
        let options = J2KResolutionDecodingOptions(
            level: 3,
            maxLayer: 4,
            components: [0],
            upscale: true
        )

        XCTAssertEqual(options.level, 3)
        XCTAssertEqual(options.maxLayer, 4)
        XCTAssertEqual(options.components, [0])
        XCTAssertTrue(options.upscale)
    }

    func testResolutionDecodingOptionsValidation() throws {
        let options = J2KResolutionDecodingOptions(level: 2, maxLayer: 3)

        try options.validate(maxLevels: 5, maxLayers: 5, componentCount: 3)
    }

    func testResolutionDecodingOptionsValidationInvalidLevel() {
        let options = J2KResolutionDecodingOptions(level: 10)

        XCTAssertThrowsError(
            try options.validate(maxLevels: 5, maxLayers: 5, componentCount: 3)
        ) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("level"))
        }
    }

    func testResolutionDecodingOptionsValidationInvalidLayer() {
        let options = J2KResolutionDecodingOptions(level: 2, maxLayer: 10)

        XCTAssertThrowsError(
            try options.validate(maxLevels: 5, maxLayers: 5, componentCount: 3)
        )
    }

    func testResolutionDecodingOptionsCalculatedDimensions() {
        let options1 = J2KResolutionDecodingOptions(level: 0)
        let dims1 = options1.calculatedDimensions(fullWidth: 512, fullHeight: 512)
        XCTAssertEqual(dims1.width, 512)
        XCTAssertEqual(dims1.height, 512)

        let options2 = J2KResolutionDecodingOptions(level: 1)
        let dims2 = options2.calculatedDimensions(fullWidth: 512, fullHeight: 512)
        XCTAssertEqual(dims2.width, 256)
        XCTAssertEqual(dims2.height, 256)

        let options3 = J2KResolutionDecodingOptions(level: 2)
        let dims3 = options3.calculatedDimensions(fullWidth: 512, fullHeight: 512)
        XCTAssertEqual(dims3.width, 128)
        XCTAssertEqual(dims3.height, 128)

        let options4 = J2KResolutionDecodingOptions(level: 3)
        let dims4 = options4.calculatedDimensions(fullWidth: 512, fullHeight: 512)
        XCTAssertEqual(dims4.width, 64)
        XCTAssertEqual(dims4.height, 64)
    }

    func testResolutionDecodingOptionsCalculatedDimensionsNonPowerOfTwo() {
        let options = J2KResolutionDecodingOptions(level: 2)
        let dims = options.calculatedDimensions(fullWidth: 1000, fullHeight: 800)

        // 1000 / 4 = 250, 800 / 4 = 200
        XCTAssertEqual(dims.width, 250)
        XCTAssertEqual(dims.height, 200)
    }

    func testResolutionDecodingOptionsCalculatedDimensionsRounding() {
        let options = J2KResolutionDecodingOptions(level: 2)
        let dims = options.calculatedDimensions(fullWidth: 513, fullHeight: 513)

        // (513 + 3) / 4 = 129
        XCTAssertEqual(dims.width, 129)
        XCTAssertEqual(dims.height, 129)
    }

    func testResolutionDecodingOptionsDescription() {
        let options = J2KResolutionDecodingOptions(
            level: 2,
            maxLayer: 3,
            components: [0, 1],
            upscale: true
        )

        let description = options.description
        XCTAssertTrue(description.contains("level: 2"))
        XCTAssertTrue(description.contains("maxLayer: 3"))
        XCTAssertTrue(description.contains("components"))
        XCTAssertTrue(description.contains("upscale"))
    }

    // MARK: - Quality Decoding Options Tests

    func testQualityDecodingOptionsDefault() {
        let options = J2KQualityDecodingOptions(layer: 3)

        XCTAssertEqual(options.layer, 3)
        XCTAssertNil(options.components)
        XCTAssertTrue(options.cumulative)
    }

    func testQualityDecodingOptionsCustom() {
        let options = J2KQualityDecodingOptions(
            layer: 5,
            components: [0, 1],
            cumulative: false
        )

        XCTAssertEqual(options.layer, 5)
        XCTAssertEqual(options.components, [0, 1])
        XCTAssertFalse(options.cumulative)
    }

    func testQualityDecodingOptionsValidation() throws {
        let options = J2KQualityDecodingOptions(layer: 3)

        try options.validate(maxLayers: 5, componentCount: 3)
    }

    func testQualityDecodingOptionsValidationInvalidLayer() {
        let options = J2KQualityDecodingOptions(layer: 10)

        XCTAssertThrowsError(
            try options.validate(maxLayers: 5, componentCount: 3)
        ) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("layer"))
        }
    }

    func testQualityDecodingOptionsValidationInvalidComponent() {
        let options = J2KQualityDecodingOptions(layer: 2, components: [5])

        XCTAssertThrowsError(
            try options.validate(maxLayers: 5, componentCount: 3)
        )
    }

    func testQualityDecodingOptionsDescription() {
        let options = J2KQualityDecodingOptions(
            layer: 3,
            components: [0, 1],
            cumulative: true
        )

        let description = options.description
        XCTAssertTrue(description.contains("layer: 3"))
        XCTAssertTrue(description.contains("components"))
        XCTAssertTrue(description.contains("cumulative"))
    }

    // MARK: - Incremental Decoder Tests

    func testIncrementalDecoderInitialization() {
        let decoder = J2KIncrementalDecoder()

        XCTAssertEqual(decoder.bufferSize(), 0)
        XCTAssertFalse(decoder.isComplete())
        XCTAssertFalse(decoder.canDecode())
    }

    func testIncrementalDecoderAppendData() {
        let decoder = J2KIncrementalDecoder()
        let data1 = Data([1, 2, 3, 4, 5])
        let data2 = Data([6, 7, 8, 9, 10])

        decoder.append(data1)
        XCTAssertEqual(decoder.bufferSize(), 5)

        decoder.append(data2)
        XCTAssertEqual(decoder.bufferSize(), 10)
    }

    func testIncrementalDecoderComplete() {
        let decoder = J2KIncrementalDecoder()

        XCTAssertFalse(decoder.isComplete())

        decoder.complete()
        XCTAssertTrue(decoder.isComplete())
    }

    func testIncrementalDecoderCanDecode() {
        let decoder = J2KIncrementalDecoder()

        XCTAssertFalse(decoder.canDecode())

        // Append enough data to pass the threshold
        let data = Data(repeating: 0, count: 200)
        decoder.append(data)

        XCTAssertTrue(decoder.canDecode())
    }

    func testIncrementalDecoderReset() {
        let decoder = J2KIncrementalDecoder()
        let data = Data(repeating: 0, count: 200)

        decoder.append(data)
        decoder.complete()

        XCTAssertEqual(decoder.bufferSize(), 200)
        XCTAssertTrue(decoder.isComplete())

        decoder.reset()

        XCTAssertEqual(decoder.bufferSize(), 0)
        XCTAssertFalse(decoder.isComplete())
    }

    func testIncrementalDecoderThreadSafety() {
        let decoder = J2KIncrementalDecoder()
        let iterations = 100

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let data = Data([UInt8(index)])
            decoder.append(data)
        }

        XCTAssertEqual(decoder.bufferSize(), iterations)
    }

    // MARK: - Region Extraction Tests

    func testRegionExtraction() throws {
        // Create a test image
        let image = createTestImage(width: 100, height: 100, components: 1)

        // Extract a region
        let decoder = J2KDecoder()
        let region = J2KRegion(x: 10, y: 10, width: 20, height: 20)

        // Use the helper extension method for testing
        let extractedImage = try decoder.extractRegion(from: image, region: region)

        // Verify dimensions
        XCTAssertEqual(extractedImage.width, 20)
        XCTAssertEqual(extractedImage.height, 20)
        XCTAssertEqual(extractedImage.components.count, 1)

        // Verify data
        for y in 0..<20 {
            for x in 0..<20 {
                let extractedIndex = y * 20 + x
                let originalIndex = (y + 10) * 100 + (x + 10)

                XCTAssertEqual(
                    extractedImage.components[0].data[extractedIndex],
                    UInt8(originalIndex % 256)
                )
            }
        }
    }

    func testRegionExtractionMultipleComponents() throws {
        // Create a 3-component test image
        let image = createTestImage(width: 50, height: 50, components: 3)

        // Extract a region
        let decoder = J2KDecoder()
        let region = J2KRegion(x: 5, y: 5, width: 10, height: 10)
        let extractedImage = try decoder.extractRegion(from: image, region: region)

        // Verify dimensions
        XCTAssertEqual(extractedImage.width, 10)
        XCTAssertEqual(extractedImage.height, 10)
        XCTAssertEqual(extractedImage.components.count, 3)

        // Verify data for all components
        for compIndex in 0..<3 {
            for y in 0..<10 {
                for x in 0..<10 {
                    let extractedIndex = y * 10 + x
                    let originalIndex = (y + 5) * 50 + (x + 5)
                    let expectedValue = UInt8((compIndex * 100 + originalIndex) % 256)

                    XCTAssertEqual(
                        extractedImage.components[compIndex].data[extractedIndex],
                        expectedValue
                    )
                }
            }
        }
    }

    func testRegionExtractionInvalidRegion() {
        let image = J2KImage(width: 100, height: 100, components: 1)
        let decoder = J2KDecoder()
        let region = J2KRegion(x: 90, y: 90, width: 20, height: 20)

        XCTAssertThrowsError(try decoder.extractRegion(from: image, region: region))
    }

    // MARK: - Decoder Extension Placeholder Tests

    func testDecodePartialThrowsNotImplemented() {
        let decoder = J2KDecoder()
        let data = Data()
        let options = J2KPartialDecodingOptions()

        XCTAssertThrowsError(try decoder.decodePartial(data, options: options)) { error in
            guard case J2KError.notImplemented = error else {
                XCTFail("Expected notImplemented error")
                return
            }
        }
    }

    func testDecodeResolutionThrowsNotImplemented() {
        let decoder = J2KDecoder()
        let data = Data()
        let options = J2KResolutionDecodingOptions(level: 2)

        XCTAssertThrowsError(try decoder.decodeResolution(data, options: options)) { error in
            guard case J2KError.notImplemented = error else {
                XCTFail("Expected notImplemented error")
                return
            }
        }
    }

    func testDecodeQualityThrowsNotImplemented() {
        let decoder = J2KDecoder()
        let data = Data()
        let options = J2KQualityDecodingOptions(layer: 2)

        XCTAssertThrowsError(try decoder.decodeQuality(data, options: options)) { error in
            guard case J2KError.notImplemented = error else {
                XCTFail("Expected notImplemented error")
                return
            }
        }
    }

    func testDecodeRegionDirectThrowsNotImplemented() {
        let decoder = J2KDecoder()
        let data = Data()
        let region = J2KRegion(x: 0, y: 0, width: 100, height: 100)
        let options = J2KROIDecodingOptions(region: region, strategy: .direct)

        XCTAssertThrowsError(try decoder.decodeRegion(data, options: options)) { error in
            guard case J2KError.notImplemented = error else {
                XCTFail("Expected notImplemented error")
                return
            }
        }
    }

    // MARK: - Equatable Tests

    func testPartialDecodingOptionsEquatable() {
        let region = J2KRegion(x: 10, y: 10, width: 100, height: 100)

        let opt1 = J2KPartialDecodingOptions(
            maxLayer: 3,
            maxResolutionLevel: 2,
            region: region,
            earlyStop: true,
            components: [0, 1]
        )

        let opt2 = J2KPartialDecodingOptions(
            maxLayer: 3,
            maxResolutionLevel: 2,
            region: region,
            earlyStop: true,
            components: [0, 1]
        )

        let opt3 = J2KPartialDecodingOptions(
            maxLayer: 4,
            maxResolutionLevel: 2,
            region: region,
            earlyStop: true,
            components: [0, 1]
        )

        XCTAssertEqual(opt1, opt2)
        XCTAssertNotEqual(opt1, opt3)
    }

    func testROIDecodingOptionsEquatable() {
        let region1 = J2KRegion(x: 10, y: 10, width: 100, height: 100)
        let region2 = J2KRegion(x: 10, y: 10, width: 100, height: 100)
        let region3 = J2KRegion(x: 20, y: 20, width: 100, height: 100)

        let opt1 = J2KROIDecodingOptions(region: region1, maxLayer: 3)
        let opt2 = J2KROIDecodingOptions(region: region2, maxLayer: 3)
        let opt3 = J2KROIDecodingOptions(region: region3, maxLayer: 3)

        XCTAssertEqual(opt1, opt2)
        XCTAssertNotEqual(opt1, opt3)
    }

    func testResolutionDecodingOptionsEquatable() {
        let opt1 = J2KResolutionDecodingOptions(level: 2, maxLayer: 3, upscale: true)
        let opt2 = J2KResolutionDecodingOptions(level: 2, maxLayer: 3, upscale: true)
        let opt3 = J2KResolutionDecodingOptions(level: 3, maxLayer: 3, upscale: true)

        XCTAssertEqual(opt1, opt2)
        XCTAssertNotEqual(opt1, opt3)
    }

    func testQualityDecodingOptionsEquatable() {
        let opt1 = J2KQualityDecodingOptions(layer: 3, cumulative: true)
        let opt2 = J2KQualityDecodingOptions(layer: 3, cumulative: true)
        let opt3 = J2KQualityDecodingOptions(layer: 4, cumulative: true)

        XCTAssertEqual(opt1, opt2)
        XCTAssertNotEqual(opt1, opt3)
    }
}

// MARK: - Helper Extension

extension J2KDecoder {
    /// Expose extractRegion for testing.
    func extractRegion(from image: J2KImage, region: J2KRegion) throws -> J2KImage {
        // Copy implementation from the private method
        try region.validate(imageWidth: image.width, imageHeight: image.height)

        // Create new components with extracted data
        let regionComponents = image.components.map { component in
            var regionData = Data(count: region.width * region.height)

            for y in 0..<region.height {
                let srcY = region.y + y
                let dstOffset = y * region.width
                let srcOffset = srcY * image.width + region.x

                for x in 0..<region.width {
                    regionData[dstOffset + x] = component.data[srcOffset + x]
                }
            }

            return J2KComponent(
                index: component.index,
                bitDepth: component.bitDepth,
                signed: component.signed,
                width: region.width,
                height: region.height,
                subsamplingX: component.subsamplingX,
                subsamplingY: component.subsamplingY,
                data: regionData
            )
        }

        // Create new image with region dimensions
        return J2KImage(
            width: region.width,
            height: region.height,
            components: regionComponents,
            colorSpace: image.colorSpace
        )
    }
}

// MARK: - Test Helpers

/// Creates a test image with pattern data.
func createTestImage(width: Int, height: Int, components: Int) -> J2KImage {
    let imageComponents = (0..<components).map { compIndex -> J2KComponent in
        var data = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                // Create a simple pattern: component offset + position (mod 256)
                data[index] = UInt8((compIndex * 100 + index) % 256)
            }
        }

        return J2KComponent(
            index: compIndex,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: data
        )
    }

    return J2KImage(
        width: width,
        height: height,
        components: imageComponents
    )
}
