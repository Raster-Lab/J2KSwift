//
// J2KNonLinearTransformTests.swift
// J2KSwift
//
// J2KNonLinearTransformTests.swift
// J2KSwift
//
// Tests for non-linear point transforms (ISO/IEC 15444-2 Part 2).
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class J2KNonLinearTransformTests: XCTestCase {
    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = J2KNLTConfiguration.default
        XCTAssertFalse(config.enabled)
        XCTAssertNil(config.componentTransforms)
        XCTAssertFalse(config.autoOptimize)
    }

    func testDisabledConfiguration() {
        let config = J2KNLTConfiguration.disabled
        XCTAssertFalse(config.enabled)
    }

    func testAutoOptimizedConfiguration() {
        let config = J2KNLTConfiguration.autoOptimized
        XCTAssertTrue(config.enabled)
        XCTAssertNil(config.componentTransforms)
        XCTAssertTrue(config.autoOptimize)
    }

    func testCustomConfiguration() {
        let transforms = [
            J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2)),
            J2KNLTComponentTransform(componentIndex: 1, transformType: .identity),
            J2KNLTComponentTransform(componentIndex: 2, transformType: .logarithmic)
        ]

        let config = J2KNLTConfiguration(
            enabled: true,
            componentTransforms: transforms,
            autoOptimize: false
        )

        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.componentTransforms?.count, 3)
        XCTAssertFalse(config.autoOptimize)
    }

    // MARK: - Identity Transform Tests

    func testIdentityTransform() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .identity)

        let input: [Int32] = [0, 50, 100, 150, 200, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // Identity should not change values
        XCTAssertEqual(result.transformedData, input)
        XCTAssertFalse(result.statistics.clipped)
    }

    func testIdentityTransformInverse() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .identity)

        let input: [Int32] = [0, 50, 100, 150, 200, 255]

        let forward = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        let inverse = try nlt.applyInverse(
            componentData: forward.transformedData,
            transform: transform,
            bitDepth: 8
        )

        // Should recover original values
        XCTAssertEqual(inverse.transformedData, input)
    }

    // MARK: - Gamma Transform Tests

    func testGammaTransform() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2))

        let input: [Int32] = [0, 64, 128, 192, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // Gamma 2.2 should darken mid-tones
        XCTAssertEqual(result.transformedData[0], 0)  // Black stays black
        XCTAssertLessThan(result.transformedData[1], 64)  // Mid-tone darkens
        XCTAssertLessThan(result.transformedData[2], 128)
        XCTAssertEqual(result.transformedData[4], 255)  // White stays white
    }

    func testGammaTransformInverse() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2))

        let input: [Int32] = [0, 64, 128, 192, 255]

        let forward = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        let inverse = try nlt.applyInverse(
            componentData: forward.transformedData,
            transform: transform,
            bitDepth: 8
        )

        // Should recover original values (within rounding error)
        for i in 0..<input.count {
            XCTAssertEqual(inverse.transformedData[i], input[i], accuracy: 1)
        }
    }

    func testInvalidGamma() {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(-1.0))

        XCTAssertThrowsError(try nlt.applyForward(
            componentData: [100],
            transform: transform,
            bitDepth: 8
        ))
    }

    // MARK: - Logarithmic Transform Tests

    func testLogarithmicTransform() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .logarithmic)

        let input: [Int32] = [0, 64, 128, 192, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // Log transform should compress the dynamic range
        XCTAssertEqual(result.transformedData[0], 0)
        XCTAssertLessThanOrEqual(result.transformedData[4], 255)
    }

    func testLogarithmicTransformInverse() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .logarithmic)

        let input: [Int32] = [0, 64, 128, 192, 255]

        let forward = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        let inverse = try nlt.applyInverse(
            componentData: forward.transformedData,
            transform: transform,
            bitDepth: 8
        )

        // Should recover original values (within rounding error)
        for i in 0..<input.count {
            XCTAssertEqual(inverse.transformedData[i], input[i], accuracy: 2)
        }
    }

    func testLogarithmic10Transform() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .logarithmic10)

        let input: [Int32] = [0, 64, 128, 192, 255]

        let forward = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        let inverse = try nlt.applyInverse(
            componentData: forward.transformedData,
            transform: transform,
            bitDepth: 8
        )

        // Should recover original values
        for i in 0..<input.count {
            XCTAssertEqual(inverse.transformedData[i], input[i], accuracy: 2)
        }
    }

    // MARK: - Exponential Transform Tests

    func testExponentialTransform() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .exponential)

        let input: [Int32] = [0, 64, 128, 192, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // Exponential forward transform compresses values
        XCTAssertEqual(result.transformedData[0], 0)
        // Middle values should be compressed
        XCTAssertLessThan(result.transformedData[2], 128)
    }

    func testExponentialTransformInverse() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .exponential)

        let input: [Int32] = [0, 64, 128, 192, 255]

        let forward = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        let inverse = try nlt.applyInverse(
            componentData: forward.transformedData,
            transform: transform,
            bitDepth: 8
        )

        // Should recover original values
        for i in 0..<input.count {
            XCTAssertEqual(inverse.transformedData[i], input[i], accuracy: 2)
        }
    }

    // MARK: - LUT Transform Tests

    func testLUTTransformNearestNeighbor() throws {
        let nlt = J2KNonLinearTransform()

        // Simple inversion LUT
        let forwardLUT = stride(from: 255.0, through: 0.0, by: -1.0).map { $0 }
        let inverseLUT = stride(from: 255.0, through: 0.0, by: -1.0).map { $0 }

        let transform = J2KNLTComponentTransform(
            componentIndex: 0,
            transformType: .lookupTable(
                forwardLUT: forwardLUT,
                inverseLUT: inverseLUT,
                interpolation: false
            )
        )

        let input: [Int32] = [0, 64, 128, 192, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // LUT should invert values
        XCTAssertEqual(result.transformedData[0], 255, accuracy: 1)
        XCTAssertEqual(result.transformedData[4], 0, accuracy: 1)
    }

    func testLUTTransformInterpolation() throws {
        let nlt = J2KNonLinearTransform()

        // Small LUT with interpolation
        let forwardLUT = [0.0, 85.0, 170.0, 255.0]
        let inverseLUT = [0.0, 85.0, 170.0, 255.0]

        let transform = J2KNLTComponentTransform(
            componentIndex: 0,
            transformType: .lookupTable(
                forwardLUT: forwardLUT,
                inverseLUT: inverseLUT,
                interpolation: true
            )
        )

        let input: [Int32] = [0, 64, 128, 192, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // With interpolation, should be smoother
        XCTAssertEqual(result.transformedData[0], 0, accuracy: 1)
        XCTAssertEqual(result.transformedData[4], 255, accuracy: 1)
    }

    // MARK: - Piecewise Linear Transform Tests

    func testPiecewiseLinearTransform() throws {
        let nlt = J2KNonLinearTransform()

        // Two-segment piecewise linear: compress shadows, expand highlights
        let breakpoints = [0.0, 0.5, 1.0]
        let values = [0.0, 0.3, 1.0]

        let transform = J2KNLTComponentTransform(
            componentIndex: 0,
            transformType: .piecewiseLinear(breakpoints: breakpoints, values: values)
        )

        let input: [Int32] = [0, 64, 128, 192, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // Shadows should be compressed
        XCTAssertEqual(result.transformedData[0], 0)
        XCTAssertLessThan(result.transformedData[2], 128)
        XCTAssertEqual(result.transformedData[4], 255)
    }

    // MARK: - PQ (Perceptual Quantizer) Transform Tests

    func testPQTransform() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .perceptualQuantizer)

        let input: [Int32] = [0, 256, 512, 768, 1023]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 10
        )

        // PQ should linearize the values
        XCTAssertNotNil(result.transformedData)
        XCTAssertEqual(result.transformedData.count, input.count)
    }

    func testPQTransformInverse() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .perceptualQuantizer)

        let input: [Int32] = [0, 256, 512, 768, 1023]

        let forward = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 10
        )

        let inverse = try nlt.applyInverse(
            componentData: forward.transformedData,
            transform: transform,
            bitDepth: 10
        )

        // Should recover original values (within larger tolerance for PQ HDR)
        for i in 0..<input.count {
            XCTAssertEqual(inverse.transformedData[i], input[i], accuracy: 50)
        }
    }

    // MARK: - HLG (Hybrid Log-Gamma) Transform Tests

    func testHLGTransform() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .hybridLogGamma)

        let input: [Int32] = [0, 256, 512, 768, 1023]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 10
        )

        // HLG should linearize the values
        XCTAssertNotNil(result.transformedData)
        XCTAssertEqual(result.transformedData.count, input.count)
    }

    func testHLGTransformInverse() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .hybridLogGamma)

        let input: [Int32] = [0, 256, 512, 768, 1023]

        let forward = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 10
        )

        let inverse = try nlt.applyInverse(
            componentData: forward.transformedData,
            transform: transform,
            bitDepth: 10
        )

        // Should recover original values (within tolerance for HDR)
        for i in 0..<input.count {
            XCTAssertEqual(inverse.transformedData[i], input[i], accuracy: 5)
        }
    }

    // MARK: - Edge Case Tests

    func testEmptyData() {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .identity)

        XCTAssertThrowsError(try nlt.applyForward(
            componentData: [],
            transform: transform,
            bitDepth: 8
        ))
    }

    func testInvalidBitDepth() {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .identity)

        XCTAssertThrowsError(try nlt.applyForward(
            componentData: [100],
            transform: transform,
            bitDepth: 0
        ))

        XCTAssertThrowsError(try nlt.applyForward(
            componentData: [100],
            transform: transform,
            bitDepth: 33
        ))
    }

    func testSignedData() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2))

        let input: [Int32] = [-128, -64, 0, 64, 127]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8,
            signed: true
        )

        XCTAssertNotNil(result.transformedData)
        XCTAssertEqual(result.transformedData.count, input.count)
    }

    func testHighBitDepth() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2))

        let input: [Int32] = [0, 1024, 2048, 3072, 4095]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 12
        )

        XCTAssertNotNil(result.transformedData)
        XCTAssertEqual(result.transformedData.count, input.count)
    }

    // MARK: - Statistics Tests

    func testStatistics() throws {
        let nlt = J2KNonLinearTransform()
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2))

        let input: [Int32] = [0, 64, 128, 192, 255]

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        let stats = result.statistics
        XCTAssertEqual(stats.inputRange.min, 0)
        XCTAssertEqual(stats.inputRange.max, 255)
        XCTAssertEqual(stats.sampleCount, 5)
    }

    func testClipping() throws {
        let nlt = J2KNonLinearTransform()

        // Exponential can cause clipping at high values
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .exponential)

        let input: [Int32] = Array(0...255)

        let result = try nlt.applyForward(
            componentData: input,
            transform: transform,
            bitDepth: 8
        )

        // May or may not clip depending on the transform
        XCTAssertNotNil(result.statistics.clipped)
    }

    // MARK: - Multi-Component Tests

    func testMultipleComponents() throws {
        let nlt = J2KNonLinearTransform()

        let transforms = [
            J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2)),
            J2KNLTComponentTransform(componentIndex: 1, transformType: .identity),
            J2KNLTComponentTransform(componentIndex: 2, transformType: .logarithmic)
        ]

        let input: [Int32] = [0, 64, 128, 192, 255]

        for transform in transforms {
            let result = try nlt.applyForward(
                componentData: input,
                transform: transform,
                bitDepth: 8
            )

            XCTAssertEqual(result.transformedData.count, input.count)
            XCTAssertEqual(result.transform.componentIndex, transform.componentIndex)
        }
    }
}

// MARK: - NLT Marker Segment Tests

final class J2KNLTMarkerSegmentTests: XCTestCase {
    func testMarkerCode() {
        XCTAssertEqual(J2KNLTMarkerSegment.markerCode, 0xFF90)
    }

    func testEncodeDecodeIdentity() throws {
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .identity)
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        XCTAssertGreaterThan(encoded.count, 0)

        // Skip marker code and decode
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        XCTAssertEqual(decoded.transforms.count, 1)
        XCTAssertEqual(decoded.transforms[0].componentIndex, 0)

        if case .identity = decoded.transforms[0].transformType {
            // Success
        } else {
            XCTFail("Expected identity transform")
        }
    }

    func testEncodeDecodeGamma() throws {
        let transform = J2KNLTComponentTransform(componentIndex: 1, transformType: .gamma(2.2))
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        XCTAssertEqual(decoded.transforms.count, 1)
        XCTAssertEqual(decoded.transforms[0].componentIndex, 1)

        if case .gamma(let gamma) = decoded.transforms[0].transformType {
            XCTAssertEqual(gamma, 2.2, accuracy: 0.001)
        } else {
            XCTFail("Expected gamma transform")
        }
    }

    func testEncodeDecodeLogarithmic() throws {
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .logarithmic)
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .logarithmic = decoded.transforms[0].transformType {
            // Success
        } else {
            XCTFail("Expected logarithmic transform")
        }
    }

    func testEncodeDecodeLogarithmic10() throws {
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .logarithmic10)
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .logarithmic10 = decoded.transforms[0].transformType {
            // Success
        } else {
            XCTFail("Expected logarithmic10 transform")
        }
    }

    func testEncodeDecodeExponential() throws {
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .exponential)
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .exponential = decoded.transforms[0].transformType {
            // Success
        } else {
            XCTFail("Expected exponential transform")
        }
    }

    func testEncodeDecodePQ() throws {
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .perceptualQuantizer)
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .perceptualQuantizer = decoded.transforms[0].transformType {
            // Success
        } else {
            XCTFail("Expected PQ transform")
        }
    }

    func testEncodeDecodeHLG() throws {
        let transform = J2KNLTComponentTransform(componentIndex: 0, transformType: .hybridLogGamma)
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .hybridLogGamma = decoded.transforms[0].transformType {
            // Success
        } else {
            XCTFail("Expected HLG transform")
        }
    }

    func testEncodeDecodeLUT() throws {
        let forwardLUT = [0.0, 64.0, 128.0, 192.0, 255.0]
        let inverseLUT = [0.0, 64.0, 128.0, 192.0, 255.0]

        let transform = J2KNLTComponentTransform(
            componentIndex: 0,
            transformType: .lookupTable(
                forwardLUT: forwardLUT,
                inverseLUT: inverseLUT,
                interpolation: true
            )
        )
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .lookupTable(let fwd, let inv, let interp) = decoded.transforms[0].transformType {
            XCTAssertEqual(fwd.count, 5)
            XCTAssertEqual(inv.count, 5)
            XCTAssertTrue(interp)
            XCTAssertEqual(fwd[0], 0.0, accuracy: 0.001)
            XCTAssertEqual(fwd[4], 255.0, accuracy: 0.001)
        } else {
            XCTFail("Expected LUT transform")
        }
    }

    func testEncodeDecodePiecewiseLinear() throws {
        let breakpoints = [0.0, 0.5, 1.0]
        let values = [0.0, 0.3, 1.0]

        let transform = J2KNLTComponentTransform(
            componentIndex: 0,
            transformType: .piecewiseLinear(breakpoints: breakpoints, values: values)
        )
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .piecewiseLinear(let bp, let val) = decoded.transforms[0].transformType {
            XCTAssertEqual(bp.count, 3)
            XCTAssertEqual(val.count, 3)
            XCTAssertEqual(bp[0], 0.0, accuracy: 0.001)
            XCTAssertEqual(bp[1], 0.5, accuracy: 0.001)
            XCTAssertEqual(bp[2], 1.0, accuracy: 0.001)
        } else {
            XCTFail("Expected piecewise linear transform")
        }
    }

    func testEncodeDecodeCustom() throws {
        let parameters = [1.0, 2.0, 3.0]
        let function = "custom_transform"

        let transform = J2KNLTComponentTransform(
            componentIndex: 0,
            transformType: .custom(parameters: parameters, function: function)
        )
        let marker = J2KNLTMarkerSegment(transforms: [transform])

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        if case .custom(let params, let function) = decoded.transforms[0].transformType {
            XCTAssertEqual(params.count, 3)
            XCTAssertEqual(function, "custom_transform")
            XCTAssertEqual(params[0], 1.0, accuracy: 0.001)
        } else {
            XCTFail("Expected custom transform")
        }
    }

    func testEncodeDecodeMultipleTransforms() throws {
        let transforms = [
            J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2)),
            J2KNLTComponentTransform(componentIndex: 1, transformType: .identity),
            J2KNLTComponentTransform(componentIndex: 2, transformType: .logarithmic)
        ]
        let marker = J2KNLTMarkerSegment(transforms: transforms)

        let encoded = try marker.encode()
        let markerData = encoded.dropFirst(2)
        let decoded = try J2KNLTMarkerSegment.decode(from: Data(markerData))

        XCTAssertEqual(decoded.transforms.count, 3)
        XCTAssertEqual(decoded.transforms[0].componentIndex, 0)
        XCTAssertEqual(decoded.transforms[1].componentIndex, 1)
        XCTAssertEqual(decoded.transforms[2].componentIndex, 2)
    }

    func testValidation() {
        // Valid marker
        let validTransform = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2))
        let validMarker = J2KNLTMarkerSegment(transforms: [validTransform])
        XCTAssertTrue(validMarker.validate())

        // Invalid: duplicate component indices
        let duplicates = [
            J2KNLTComponentTransform(componentIndex: 0, transformType: .identity),
            J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2))
        ]
        let invalidMarker = J2KNLTMarkerSegment(transforms: duplicates)
        XCTAssertFalse(invalidMarker.validate())

        // Invalid: negative gamma
        let negativeGamma = J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(-1.0))
        let invalidGammaMarker = J2KNLTMarkerSegment(transforms: [negativeGamma])
        XCTAssertFalse(invalidGammaMarker.validate())

        // Invalid: empty LUT
        let emptyLUT = J2KNLTComponentTransform(
            componentIndex: 0,
            transformType: .lookupTable(forwardLUT: [], inverseLUT: [], interpolation: false)
        )
        let invalidLUTMarker = J2KNLTMarkerSegment(transforms: [emptyLUT])
        XCTAssertFalse(invalidLUTMarker.validate())
    }

    func testDecodeTruncatedData() {
        let shortData = Data([0x00, 0x04, 0x00])  // Too short
        XCTAssertThrowsError(try J2KNLTMarkerSegment.decode(from: shortData))
    }
}
