//
// J2KColorTransformTests.swift
// J2KSwift
//
// J2KColorTransformTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Comprehensive tests for JPEG 2000 color transforms.
final class J2KColorTransformTests: XCTestCase {
    // MARK: - Configuration Tests

    func testColorTransformModeAllCases() throws {
        let allModes = J2KColorTransformMode.allCases
        XCTAssertEqual(allModes.count, 3)
        XCTAssertTrue(allModes.contains(.reversible))
        XCTAssertTrue(allModes.contains(.irreversible))
        XCTAssertTrue(allModes.contains(.none))
    }

    func testDefaultConfiguration() throws {
        let config = J2KColorTransformConfiguration()
        XCTAssertEqual(config.mode, .reversible)
    }

    func testLosslessConfiguration() throws {
        let config = J2KColorTransformConfiguration.lossless
        XCTAssertEqual(config.mode, .reversible)
    }

    func testLossyConfiguration() throws {
        let config = J2KColorTransformConfiguration.lossy
        XCTAssertEqual(config.mode, .irreversible)
    }

    func testNoneConfiguration() throws {
        let config = J2KColorTransformConfiguration.none
        XCTAssertEqual(config.mode, .none)
    }

    func testConfigurationEquality() throws {
        let config1 = J2KColorTransformConfiguration(mode: .reversible, validateReversibility: true)
        let config2 = J2KColorTransformConfiguration(mode: .reversible, validateReversibility: true)
        let config3 = J2KColorTransformConfiguration(mode: .irreversible, validateReversibility: false)

        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }

    // MARK: - Basic RCT Tests

    func testForwardRCTBasic() throws {
        let transform = J2KColorTransform()

        // Test with simple values
        let red: [Int32] = [100, 150, 200]
        let green: [Int32] = [80, 120, 180]
        let blue: [Int32] = [60, 100, 160]

        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)

        // Verify results
        XCTAssertEqual(y.count, 3)
        XCTAssertEqual(cb.count, 3)
        XCTAssertEqual(cr.count, 3)

        // Y = ⌊(R + 2G + B) / 4⌋
        XCTAssertEqual(y[0], (100 + 2 * 80 + 60) / 4)  // 80
        XCTAssertEqual(y[1], (150 + 2 * 120 + 100) / 4)  // 122
        XCTAssertEqual(y[2], (200 + 2 * 180 + 160) / 4)  // 180

        // Cb = B - G
        XCTAssertEqual(cb[0], 60 - 80)  // -20
        XCTAssertEqual(cb[1], 100 - 120)  // -20
        XCTAssertEqual(cb[2], 160 - 180)  // -20

        // Cr = R - G
        XCTAssertEqual(cr[0], 100 - 80)  // 20
        XCTAssertEqual(cr[1], 150 - 120)  // 30
        XCTAssertEqual(cr[2], 200 - 180)  // 20
    }

    func testInverseRCTBasic() throws {
        let transform = J2KColorTransform()

        // Test with YCbCr values
        let y: [Int32] = [80, 122, 180]
        let cb: [Int32] = [-20, -20, -20]
        let cr: [Int32] = [20, 30, 20]

        let (red, green, blue) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        // Verify results
        XCTAssertEqual(red.count, 3)
        XCTAssertEqual(green.count, 3)
        XCTAssertEqual(blue.count, 3)

        // G = Y - ⌊(Cb + Cr) / 4⌋
        XCTAssertEqual(green[0], 80 - ((-20 + 20) / 4))  // 80
        XCTAssertEqual(green[1], 122 - ((-20 + 30) / 4))  // 120
        XCTAssertEqual(green[2], 180 - ((-20 + 20) / 4))  // 180

        // R = Cr + G
        XCTAssertEqual(red[0], 20 + 80)  // 100
        XCTAssertEqual(red[1], 30 + 120)  // 150
        XCTAssertEqual(red[2], 20 + 180)  // 200

        // B = Cb + G
        XCTAssertEqual(blue[0], -20 + 80)  // 60
        XCTAssertEqual(blue[1], -20 + 120)  // 100
        XCTAssertEqual(blue[2], -20 + 180)  // 160
    }

    func testRCTReversibility() throws {
        let transform = J2KColorTransform()

        // Test with various RGB values
        let testCases: [(Int32, Int32, Int32)] = [
            (0, 0, 0),
            (128, 128, 128),
            (255, 255, 255),
            (100, 150, 200),
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255),
            (50, 100, 150),
            (200, 150, 100)
        ]

        for (r, g, b) in testCases {
            let red: [Int32] = [r]
            let green: [Int32] = [g]
            let blue: [Int32] = [b]

            // Forward transform
            let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)

            // Inverse transform
            let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

            // Verify perfect reconstruction
            XCTAssertEqual(r2[0], r, "Red component not preserved for RGB(\(r), \(g), \(b))")
            XCTAssertEqual(g2[0], g, "Green component not preserved for RGB(\(r), \(g), \(b))")
            XCTAssertEqual(b2[0], b, "Blue component not preserved for RGB(\(r), \(g), \(b))")
        }
    }

    func testRCTWithSignedValues() throws {
        let transform = J2KColorTransform()

        // Test with signed values (level-shifted)
        let red: [Int32] = [-128, 0, 127, -50, 100]
        let green: [Int32] = [-100, -20, 100, 30, -60]
        let blue: [Int32] = [-80, 50, 120, -30, 80]

        // Forward and inverse transform
        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        // Verify perfect reconstruction
        for i in 0..<red.count {
            XCTAssertEqual(r2[i], red[i], "Red component not preserved at index \(i)")
            XCTAssertEqual(g2[i], green[i], "Green component not preserved at index \(i)")
            XCTAssertEqual(b2[i], blue[i], "Blue component not preserved at index \(i)")
        }
    }

    func testRCTWithLargeValues() throws {
        let transform = J2KColorTransform()

        // Test with 16-bit range values
        let red: [Int32] = [0, 32767, 65535, -32768, -1]
        let green: [Int32] = [10000, 20000, 30000, -10000, -20000]
        let blue: [Int32] = [5000, 15000, 25000, -5000, -15000]

        // Forward and inverse transform
        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        // Verify perfect reconstruction
        for i in 0..<red.count {
            XCTAssertEqual(r2[i], red[i], "Red component not preserved at index \(i)")
            XCTAssertEqual(g2[i], green[i], "Green component not preserved at index \(i)")
            XCTAssertEqual(b2[i], blue[i], "Blue component not preserved at index \(i)")
        }
    }

    // MARK: - Edge Case Tests

    func testEmptyComponentsThrowsError() throws {
        let transform = J2KColorTransform()

        let empty: [Int32] = []

        XCTAssertThrowsError(try transform.forwardRCT(red: empty, green: empty, blue: empty)) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("empty"))
        }
    }

    func testMismatchedComponentSizesThrowsError() throws {
        let transform = J2KColorTransform()

        let red: [Int32] = [100, 150, 200]
        let green: [Int32] = [80, 120]  // Different size
        let blue: [Int32] = [60, 100, 160]

        XCTAssertThrowsError(try transform.forwardRCT(red: red, green: green, blue: blue)) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("must match"))
        }
    }

    func testSinglePixelTransform() throws {
        let transform = J2KColorTransform()

        let red: [Int32] = [128]
        let green: [Int32] = [128]
        let blue: [Int32] = [128]

        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        XCTAssertEqual(r2[0], red[0])
        XCTAssertEqual(g2[0], green[0])
        XCTAssertEqual(b2[0], blue[0])
    }

    func testLargeImageTransform() throws {
        let transform = J2KColorTransform()

        // Test with a large image (512x512 = 262,144 pixels)
        let pixelCount = 512 * 512
        var red = [Int32](repeating: 0, count: pixelCount)
        var green = [Int32](repeating: 0, count: pixelCount)
        var blue = [Int32](repeating: 0, count: pixelCount)

        // Fill with pseudo-random data
        for i in 0..<pixelCount {
            red[i] = Int32((i * 17) % 256)
            green[i] = Int32((i * 31) % 256)
            blue[i] = Int32((i * 47) % 256)
        }

        // Forward and inverse transform
        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

        // Verify perfect reconstruction for all pixels
        for i in 0..<pixelCount {
            XCTAssertEqual(r2[i], red[i], "Red mismatch at pixel \(i)")
            XCTAssertEqual(g2[i], green[i], "Green mismatch at pixel \(i)")
            XCTAssertEqual(b2[i], blue[i], "Blue mismatch at pixel \(i)")
        }
    }

    // MARK: - Irreversible Color Transform (ICT) Tests

    func testForwardICTBasic() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Test with simple values (level-shifted to signed)
        let red: [Double] = [100, 150, 200]
        let green: [Double] = [80, 120, 180]
        let blue: [Double] = [60, 100, 160]

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)

        // Verify results
        XCTAssertEqual(y.count, 3)
        XCTAssertEqual(cb.count, 3)
        XCTAssertEqual(cr.count, 3)

        // Check that ICT produces reasonable values
        // Y should be weighted average of RGB
        for i in 0..<3 {
            let expectedY = 0.299 * red[i] + 0.587 * green[i] + 0.114 * blue[i]
            XCTAssertEqual(y[i], expectedY, accuracy: 0.001)
        }

        // Cb should be blue-difference component
        for i in 0..<3 {
            let expectedCb = -0.168736 * red[i] - 0.331264 * green[i] + 0.5 * blue[i]
            XCTAssertEqual(cb[i], expectedCb, accuracy: 0.001)
        }

        // Cr should be red-difference component
        for i in 0..<3 {
            let expectedCr = 0.5 * red[i] - 0.418688 * green[i] - 0.081312 * blue[i]
            XCTAssertEqual(cr[i], expectedCr, accuracy: 0.001)
        }
    }

    func testInverseICTBasic() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Test with YCbCr values
        let y: [Double] = [100.0, 150.0, 200.0]
        let cb: [Double] = [-10.0, 0.0, 10.0]
        let cr: [Double] = [5.0, -5.0, 15.0]

        let (red, green, blue) = try transform.inverseICT(y: y, cb: cb, cr: cr)

        // Verify results
        XCTAssertEqual(red.count, 3)
        XCTAssertEqual(green.count, 3)
        XCTAssertEqual(blue.count, 3)

        // Check inverse transform formulas
        for i in 0..<3 {
            let expectedR = y[i] + 1.402 * cr[i]
            XCTAssertEqual(red[i], expectedR, accuracy: 0.001)

            let expectedG = y[i] - 0.344136 * cb[i] - 0.714136 * cr[i]
            XCTAssertEqual(green[i], expectedG, accuracy: 0.001)

            let expectedB = y[i] + 1.772 * cb[i]
            XCTAssertEqual(blue[i], expectedB, accuracy: 0.001)
        }
    }

    func testICTRoundTrip() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Test round-trip transformation
        let red: [Double] = [100, 150, 200, 50, 128, 255, 0]
        let green: [Double] = [80, 120, 180, 100, 128, 0, 255]
        let blue: [Double] = [60, 100, 160, 150, 128, 100, 200]

        // Forward transform
        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)

        // Inverse transform
        let (r2, g2, b2) = try transform.inverseICT(y: y, cb: cb, cr: cr)

        // Verify approximate reconstruction (ICT is not perfectly reversible)
        for i in 0..<red.count {
            XCTAssertEqual(r2[i], red[i], accuracy: 0.5, "Red mismatch at index \(i)")
            XCTAssertEqual(g2[i], green[i], accuracy: 0.5, "Green mismatch at index \(i)")
            XCTAssertEqual(b2[i], blue[i], accuracy: 0.5, "Blue mismatch at index \(i)")
        }
    }

    func testICTWithZeroValues() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        let red: [Double] = [0, 0, 0]
        let green: [Double] = [0, 0, 0]
        let blue: [Double] = [0, 0, 0]

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)

        // All components should be zero
        XCTAssertEqual(y[0], 0, accuracy: 0.001)
        XCTAssertEqual(cb[0], 0, accuracy: 0.001)
        XCTAssertEqual(cr[0], 0, accuracy: 0.001)
    }

    func testICTWithNegativeValues() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Test with negative values (signed representation)
        let red: [Double] = [-100, -50, -128]
        let green: [Double] = [-80, -60, -100]
        let blue: [Double] = [-60, -70, -80]

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseICT(y: y, cb: cb, cr: cr)

        // Verify approximate reconstruction
        for i in 0..<red.count {
            XCTAssertEqual(r2[i], red[i], accuracy: 0.5)
            XCTAssertEqual(g2[i], green[i], accuracy: 0.5)
            XCTAssertEqual(b2[i], blue[i], accuracy: 0.5)
        }
    }

    func testICTWithLargeValues() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Test with large values (16-bit range)
        let red: [Double] = [1000, 2000, 4095]
        let green: [Double] = [800, 1500, 3000]
        let blue: [Double] = [600, 1000, 2000]

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseICT(y: y, cb: cb, cr: cr)

        // Verify approximate reconstruction
        for i in 0..<red.count {
            XCTAssertEqual(r2[i], red[i], accuracy: 1.0)
            XCTAssertEqual(g2[i], green[i], accuracy: 1.0)
            XCTAssertEqual(b2[i], blue[i], accuracy: 1.0)
        }
    }

    func testICTPrimaryColors() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Test with primary colors (assuming 8-bit range shifted to signed)
        let testCases: [(r: Double, g: Double, b: Double, name: String)] = [
            (127, -128, -128, "Red"),      // Red (255, 0, 0) shifted
            (-128, 127, -128, "Green"),    // Green (0, 255, 0) shifted
            (-128, -128, 127, "Blue"),     // Blue (0, 0, 255) shifted
            (127, 127, -128, "Yellow"),    // Yellow (255, 255, 0) shifted
            (127, -128, 127, "Magenta"),   // Magenta (255, 0, 255) shifted
            (-128, 127, 127, "Cyan"),      // Cyan (0, 255, 255) shifted
        ]

        for testCase in testCases {
            let red: [Double] = [testCase.r]
            let green: [Double] = [testCase.g]
            let blue: [Double] = [testCase.b]

            let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)
            let (r2, g2, b2) = try transform.inverseICT(y: y, cb: cb, cr: cr)

            XCTAssertEqual(r2[0], testCase.r, accuracy: 1.0, "\(testCase.name) - Red")
            XCTAssertEqual(g2[0], testCase.g, accuracy: 1.0, "\(testCase.name) - Green")
            XCTAssertEqual(b2[0], testCase.b, accuracy: 1.0, "\(testCase.name) - Blue")
        }
    }

    func testICTEmptyComponentsThrowsError() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        let red: [Double] = []
        let green: [Double] = []
        let blue: [Double] = []

        XCTAssertThrowsError(try transform.forwardICT(red: red, green: green, blue: blue)) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("empty"))
        }
    }

    func testICTMismatchedSizesThrowsError() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        let red: [Double] = [100, 150, 200]
        let green: [Double] = [80, 120]  // Different size
        let blue: [Double] = [60, 100, 160]

        XCTAssertThrowsError(try transform.forwardICT(red: red, green: green, blue: blue)) { error in
            guard case J2KError.invalidParameter(let message) = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
            XCTAssertTrue(message.contains("must match"))
        }
    }

    func testICTSinglePixel() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        let red: [Double] = [100]
        let green: [Double] = [80]
        let blue: [Double] = [60]

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseICT(y: y, cb: cb, cr: cr)

        XCTAssertEqual(r2[0], red[0], accuracy: 0.5)
        XCTAssertEqual(g2[0], green[0], accuracy: 0.5)
        XCTAssertEqual(b2[0], blue[0], accuracy: 0.5)
    }

    func testICTLargeImage() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Test with a large image (256x256 = 65,536 pixels)
        let pixelCount = 256 * 256
        var red = [Double](repeating: 0, count: pixelCount)
        var green = [Double](repeating: 0, count: pixelCount)
        var blue = [Double](repeating: 0, count: pixelCount)

        // Fill with pseudo-random data
        for i in 0..<pixelCount {
            red[i] = Double((i * 17) % 256) - 128
            green[i] = Double((i * 31) % 256) - 128
            blue[i] = Double((i * 47) % 256) - 128
        }

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)
        let (r2, g2, b2) = try transform.inverseICT(y: y, cb: cb, cr: cr)

        // Spot check a few pixels
        for i in stride(from: 0, to: pixelCount, by: 1000) {
            XCTAssertEqual(r2[i], red[i], accuracy: 1.0, "Red mismatch at pixel \(i)")
            XCTAssertEqual(g2[i], green[i], accuracy: 1.0, "Green mismatch at pixel \(i)")
            XCTAssertEqual(b2[i], blue[i], accuracy: 1.0, "Blue mismatch at pixel \(i)")
        }
    }

    func testICTComponentAPI() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Create test components
        let width = 4
        let height = 4
        let pixelCount = width * height

        var redData = Data(count: pixelCount * MemoryLayout<Int32>.size)
        var greenData = Data(count: pixelCount * MemoryLayout<Int32>.size)
        var blueData = Data(count: pixelCount * MemoryLayout<Int32>.size)

        // Fill with test data
        redData.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let int32Ptr = baseAddress.assumingMemoryBound(to: Int32.self)
            for i in 0..<pixelCount {
                int32Ptr[i] = Int32((i * 10) % 256)
            }
        }

        greenData.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let int32Ptr = baseAddress.assumingMemoryBound(to: Int32.self)
            for i in 0..<pixelCount {
                int32Ptr[i] = Int32((i * 15) % 256)
            }
        }

        blueData.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let int32Ptr = baseAddress.assumingMemoryBound(to: Int32.self)
            for i in 0..<pixelCount {
                int32Ptr[i] = Int32((i * 20) % 256)
            }
        }

        let redComponent = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: true,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: redData
        )

        let greenComponent = J2KComponent(
            index: 1,
            bitDepth: 8,
            signed: true,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: greenData
        )

        let blueComponent = J2KComponent(
            index: 2,
            bitDepth: 8,
            signed: true,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: blueData
        )

        // Forward transform
        let (yComp, cbComp, crComp) = try transform.forwardICT(
            redComponent: redComponent,
            greenComponent: greenComponent,
            blueComponent: blueComponent
        )

        XCTAssertEqual(yComp.width, width)
        XCTAssertEqual(yComp.height, height)
        XCTAssertEqual(cbComp.width, width)
        XCTAssertEqual(crComp.width, width)

        // Inverse transform
        let (r2Comp, g2Comp, b2Comp) = try transform.inverseICT(
            yComponent: yComp,
            cbComponent: cbComp,
            crComponent: crComp
        )

        // Verify dimensions
        XCTAssertEqual(r2Comp.width, width)
        XCTAssertEqual(g2Comp.width, width)
        XCTAssertEqual(b2Comp.width, width)

        // Verify approximate reconstruction (ICT introduces rounding errors)
        r2Comp.data.withUnsafeBytes { r2Buffer in
            redData.withUnsafeBytes { rBuffer in
                guard let r2Base = r2Buffer.baseAddress,
                      let rBase = rBuffer.baseAddress else { return }
                let r2Ptr = r2Base.assumingMemoryBound(to: Int32.self)
                let rPtr = rBase.assumingMemoryBound(to: Int32.self)

                for i in 0..<pixelCount {
                    let diff = abs(r2Ptr[i] - rPtr[i])
                    XCTAssertLessThanOrEqual(diff, 2, "Red difference too large at pixel \(i)")
                }
            }
        }
    }

    func testICTComponentDimensionMismatch() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        let redComp = J2KComponent(
            index: 0, bitDepth: 8, signed: true, width: 4, height: 4,
            subsamplingX: 1, subsamplingY: 1,
            data: Data(count: 16 * MemoryLayout<Int32>.size)
        )

        let greenComp = J2KComponent(
            index: 1, bitDepth: 8, signed: true, width: 8, height: 8,  // Different size
            subsamplingX: 1, subsamplingY: 1,
            data: Data(count: 64 * MemoryLayout<Int32>.size)
        )

        let blueComp = J2KComponent(
            index: 2, bitDepth: 8, signed: true, width: 4, height: 4,
            subsamplingX: 1, subsamplingY: 1,
            data: Data(count: 16 * MemoryLayout<Int32>.size)
        )

        XCTAssertThrowsError(try transform.forwardICT(
            redComponent: redComp,
            greenComponent: greenComp,
            blueComponent: blueComp
        )) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error")
                return
            }
        }
    }

    func testICTDecorrelation() throws {
        let transform = J2KColorTransform(configuration: .lossy)

        // Create correlated RGB data (natural image characteristics)
        let pixelCount = 100
        var red = [Double](repeating: 0, count: pixelCount)
        var green = [Double](repeating: 0, count: pixelCount)
        var blue = [Double](repeating: 0, count: pixelCount)

        // Simulate correlated data (similar values)
        for i in 0..<pixelCount {
            let base = Double(i % 128)
            red[i] = base + 10
            green[i] = base + 5
            blue[i] = base - 5
        }

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)

        // Y should contain most of the energy (similar to input)
        // Cb and Cr should be smaller (decorrelation)
        let avgY = y.reduce(0, +) / Double(pixelCount)
        let avgCb = cb.reduce(0, +) / Double(pixelCount)
        let avgCr = cr.reduce(0, +) / Double(pixelCount)

        // Y should be close to the average of RGB
        let avgRGB = (red.reduce(0, +) + green.reduce(0, +) + blue.reduce(0, +)) / (3 * Double(pixelCount))
        XCTAssertEqual(avgY, avgRGB, accuracy: 10.0)

        // Cb and Cr should be closer to zero (decorrelation)
        XCTAssertLessThan(abs(avgCb), abs(avgY))
        XCTAssertLessThan(abs(avgCr), abs(avgY))
    }

    // MARK: - Component-Based Tests

    func testForwardRCTWithComponents() throws {
        let transform = J2KColorTransform()

        // Create test components
        let width = 4
        let height = 4

        let redComponent = createTestComponent(
            index: 0,
            width: width,
            height: height,
            fillValue: 100
        )
        let greenComponent = createTestComponent(
            index: 1,
            width: width,
            height: height,
            fillValue: 80
        )
        let blueComponent = createTestComponent(
            index: 2,
            width: width,
            height: height,
            fillValue: 60
        )

        let (yComp, cbComp, crComp) = try transform.forwardRCT(
            redComponent: redComponent,
            greenComponent: greenComponent,
            blueComponent: blueComponent
        )

        // Verify component properties
        XCTAssertEqual(yComp.width, width)
        XCTAssertEqual(yComp.height, height)
        XCTAssertEqual(cbComp.width, width)
        XCTAssertEqual(cbComp.height, height)
        XCTAssertEqual(crComp.width, width)
        XCTAssertEqual(crComp.height, height)
    }

    func testInverseRCTWithComponents() throws {
        let transform = J2KColorTransform()

        // Create test components
        let width = 4
        let height = 4

        let redComponent = createTestComponent(index: 0, width: width, height: height, fillValue: 100)
        let greenComponent = createTestComponent(index: 1, width: width, height: height, fillValue: 80)
        let blueComponent = createTestComponent(index: 2, width: width, height: height, fillValue: 60)

        // Forward transform
        let (yComp, cbComp, crComp) = try transform.forwardRCT(
            redComponent: redComponent,
            greenComponent: greenComponent,
            blueComponent: blueComponent
        )

        // Inverse transform
        let (r2, g2, b2) = try transform.inverseRCT(
            yComponent: yComp,
            cbComponent: cbComp,
            crComponent: crComp
        )

        // Verify dimensions are preserved
        XCTAssertEqual(r2.width, width)
        XCTAssertEqual(r2.height, height)
        XCTAssertEqual(g2.width, width)
        XCTAssertEqual(g2.height, height)
        XCTAssertEqual(b2.width, width)
        XCTAssertEqual(b2.height, height)
    }

    func testComponentMismatchedDimensionsThrowsError() throws {
        let transform = J2KColorTransform()

        let redComponent = createTestComponent(index: 0, width: 4, height: 4, fillValue: 100)
        let greenComponent = createTestComponent(index: 1, width: 4, height: 4, fillValue: 80)
        let blueComponent = createTestComponent(index: 2, width: 8, height: 4, fillValue: 60)  // Wrong width

        XCTAssertThrowsError(try transform.forwardRCT(
            redComponent: redComponent,
            greenComponent: greenComponent,
            blueComponent: blueComponent
        )) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error")
                return
            }
        }
    }

    // MARK: - Subsampling Tests

    func testSubsamplingInfoEquality() throws {
        let info1 = J2KColorTransform.SubsamplingInfo(horizontalFactor: 2, verticalFactor: 1)
        let info2 = J2KColorTransform.SubsamplingInfo(horizontalFactor: 2, verticalFactor: 1)
        let info3 = J2KColorTransform.SubsamplingInfo(horizontalFactor: 1, verticalFactor: 1)

        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
    }

    func testSubsamplingPresets() throws {
        let none = J2KColorTransform.SubsamplingInfo.none
        XCTAssertEqual(none.horizontalFactor, 1)
        XCTAssertEqual(none.verticalFactor, 1)

        let yuv422 = J2KColorTransform.SubsamplingInfo.yuv422
        XCTAssertEqual(yuv422.horizontalFactor, 2)
        XCTAssertEqual(yuv422.verticalFactor, 1)

        let yuv420 = J2KColorTransform.SubsamplingInfo.yuv420
        XCTAssertEqual(yuv420.horizontalFactor, 2)
        XCTAssertEqual(yuv420.verticalFactor, 2)
    }

    func testValidateSubsamplingSuccess() throws {
        let transform = J2KColorTransform()

        let components = [
            createTestComponent(index: 0, width: 8, height: 8, fillValue: 100, subsamplingX: 1, subsamplingY: 1),
            createTestComponent(index: 1, width: 8, height: 8, fillValue: 80, subsamplingX: 1, subsamplingY: 1),
            createTestComponent(index: 2, width: 8, height: 8, fillValue: 60, subsamplingX: 1, subsamplingY: 1)
        ]

        XCTAssertNoThrow(try transform.validateSubsampling(components))
    }

    func testValidateSubsamplingMismatchThrowsError() throws {
        let transform = J2KColorTransform()

        let components = [
            createTestComponent(index: 0, width: 8, height: 8, fillValue: 100, subsamplingX: 1, subsamplingY: 1),
            createTestComponent(
                index: 1, width: 4, height: 8, fillValue: 80,
                subsamplingX: 2, subsamplingY: 1),  // Different
            createTestComponent(index: 2, width: 8, height: 8, fillValue: 60, subsamplingX: 1, subsamplingY: 1)
        ]

        XCTAssertThrowsError(try transform.validateSubsampling(components)) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error")
                return
            }
        }
    }

    func testValidateSubsamplingInsufficientComponentsThrowsError() throws {
        let transform = J2KColorTransform()

        let components = [
            createTestComponent(index: 0, width: 8, height: 8, fillValue: 100)
        ]

        XCTAssertThrowsError(try transform.validateSubsampling(components)) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error")
                return
            }
        }
    }

    // MARK: - Grayscale and Black Point Tests

    func testRCTWithGrayscaleInput() throws {
        let transform = J2KColorTransform()

        // Grayscale (R=G=B)
        let gray: Int32 = 128
        let red: [Int32] = [gray]
        let green: [Int32] = [gray]
        let blue: [Int32] = [gray]

        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)

        // For grayscale input: Y should equal the gray value, Cb and Cr should be 0
        XCTAssertEqual(y[0], gray)
        XCTAssertEqual(cb[0], 0)
        XCTAssertEqual(cr[0], 0)

        // Verify reversibility
        let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)
        XCTAssertEqual(r2[0], gray)
        XCTAssertEqual(g2[0], gray)
        XCTAssertEqual(b2[0], gray)
    }

    func testRCTWithBlackInput() throws {
        let transform = J2KColorTransform()

        let red: [Int32] = [0]
        let green: [Int32] = [0]
        let blue: [Int32] = [0]

        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)

        // All black should result in all zeros
        XCTAssertEqual(y[0], 0)
        XCTAssertEqual(cb[0], 0)
        XCTAssertEqual(cr[0], 0)

        // Verify reversibility
        let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)
        XCTAssertEqual(r2[0], 0)
        XCTAssertEqual(g2[0], 0)
        XCTAssertEqual(b2[0], 0)
    }

    func testRCTWithWhiteInput() throws {
        let transform = J2KColorTransform()

        let white: Int32 = 255
        let red: [Int32] = [white]
        let green: [Int32] = [white]
        let blue: [Int32] = [white]

        let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)

        // All white should result in Y=255, Cb=0, Cr=0
        XCTAssertEqual(y[0], white)
        XCTAssertEqual(cb[0], 0)
        XCTAssertEqual(cr[0], 0)

        // Verify reversibility
        let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)
        XCTAssertEqual(r2[0], white)
        XCTAssertEqual(g2[0], white)
        XCTAssertEqual(b2[0], white)
    }

    // MARK: - Primary Colors Tests

    func testRCTWithPrimaryColors() throws {
        let transform = J2KColorTransform()

        // Test red, green, blue primaries
        let testColors: [(name: String, r: Int32, g: Int32, b: Int32)] = [
            ("red", 255, 0, 0),
            ("green", 0, 255, 0),
            ("blue", 0, 0, 255),
            ("cyan", 0, 255, 255),
            ("magenta", 255, 0, 255),
            ("yellow", 255, 255, 0)
        ]

        for color in testColors {
            let red: [Int32] = [color.r]
            let green: [Int32] = [color.g]
            let blue: [Int32] = [color.b]

            let (y, cb, cr) = try transform.forwardRCT(red: red, green: green, blue: blue)
            let (r2, g2, b2) = try transform.inverseRCT(y: y, cb: cb, cr: cr)

            XCTAssertEqual(r2[0], color.r, "Red not preserved for \(color.name)")
            XCTAssertEqual(g2[0], color.g, "Green not preserved for \(color.name)")
            XCTAssertEqual(b2[0], color.b, "Blue not preserved for \(color.name)")
        }
    }

    // MARK: - Concurrency Tests

    func testColorTransformIsSendable() throws {
        let transform = J2KColorTransform()

        // This test verifies that J2KColorTransform conforms to Sendable
        // If it doesn't, the code won't compile
        let _: any Sendable = transform
    }

    func testConfigurationIsSendable() throws {
        let config = J2KColorTransformConfiguration.lossless

        // This test verifies that J2KColorTransformConfiguration conforms to Sendable
        let _: any Sendable = config
    }

    func testSubsamplingInfoIsSendable() throws {
        let info = J2KColorTransform.SubsamplingInfo.none

        // This test verifies that SubsamplingInfo conforms to Sendable
        let _: any Sendable = info
    }

    // MARK: - Helper Methods

    private func createTestComponent(
        index: Int,
        width: Int,
        height: Int,
        fillValue: Int32,
        subsamplingX: Int = 1,
        subsamplingY: Int = 1
    ) -> J2KComponent {
        let pixelCount = width * height
        var data = Data(count: pixelCount * MemoryLayout<Int32>.size)

        data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let int32Ptr = baseAddress.assumingMemoryBound(to: Int32.self)
            for i in 0..<pixelCount {
                int32Ptr[i] = fillValue
            }
        }

        return J2KComponent(
            index: index,
            bitDepth: 8,
            signed: true,
            width: width,
            height: height,
            subsamplingX: subsamplingX,
            subsamplingY: subsamplingY,
            data: data
        )
    }

    // MARK: - Grayscale Tests

    func testRGBToGrayscaleInt32() throws {
        let transform = J2KColorTransform()

        // Test with known values (using ITU-R BT.601 weights)
        let red: [Int32] = [255, 128, 0]
        let green: [Int32] = [0, 128, 255]
        let blue: [Int32] = [0, 128, 255]

        let gray = try transform.rgbToGrayscale(red: red, green: green, blue: blue)

        XCTAssertEqual(gray.count, 3)

        // Y = 0.299 × R + 0.587 × G + 0.114 × B
        // Using fixed-point arithmetic: (R*306 + G*601 + B*117 + 512) >> 10
        let calc0 = (255 * 306 + 0 * 601 + 0 * 117 + 512) >> 10
        let expectedGray0 = Int32(calc0)  // ~76
        let calc1 = (128 * 306 + 128 * 601 + 128 * 117 + 512) >> 10
        let expectedGray1 = Int32(calc1)  // ~128
        let calc2 = (0 * 306 + 255 * 601 + 255 * 117 + 512) >> 10
        let expectedGray2 = Int32(calc2)  // ~179

        XCTAssertEqual(gray[0], expectedGray0)
        XCTAssertEqual(gray[1], expectedGray1)
        XCTAssertEqual(gray[2], expectedGray2)
    }

    func testRGBToGrayscaleDouble() throws {
        let transform = J2KColorTransform()

        // Test with known values
        let red: [Double] = [255.0, 128.0, 0.0]
        let green: [Double] = [0.0, 128.0, 255.0]
        let blue: [Double] = [0.0, 128.0, 255.0]

        let gray = try transform.rgbToGrayscale(red: red, green: green, blue: blue)

        XCTAssertEqual(gray.count, 3)

        // Y = 0.299 × R + 0.587 × G + 0.114 × B
        let expectedGray0 = 0.299 * 255.0  // ~76.245
        let expectedGray1 = 0.299 * 128.0 + 0.587 * 128.0 + 0.114 * 128.0  // 128.0
        let expectedGray2 = 0.587 * 255.0 + 0.114 * 255.0  // ~178.755

        XCTAssertEqual(gray[0], expectedGray0, accuracy: 0.1)
        XCTAssertEqual(gray[1], expectedGray1, accuracy: 0.1)
        XCTAssertEqual(gray[2], expectedGray2, accuracy: 0.1)
    }

    func testGrayscaleToRGBInt32() throws {
        let transform = J2KColorTransform()

        let gray: [Int32] = [0, 128, 255]
        let (red, green, blue) = transform.grayscaleToRGB(gray: gray)

        // Grayscale to RGB should replicate the value
        XCTAssertEqual(red, gray)
        XCTAssertEqual(green, gray)
        XCTAssertEqual(blue, gray)
    }

    func testGrayscaleToRGBDouble() throws {
        let transform = J2KColorTransform()

        let gray: [Double] = [0.0, 128.0, 255.0]
        let (red, green, blue) = transform.grayscaleToRGB(gray: gray)

        // Grayscale to RGB should replicate the value
        XCTAssertEqual(red, gray)
        XCTAssertEqual(green, gray)
        XCTAssertEqual(blue, gray)
    }

    func testRGBToGrayscaleComponent() throws {
        let transform = J2KColorTransform()

        // Create test components with uniform fill values (simpler test)
        let redComp = createTestComponent(index: 0, width: 2, height: 2, fillValue: 255)
        let greenComp = createTestComponent(index: 1, width: 2, height: 2, fillValue: 0)
        let blueComp = createTestComponent(index: 2, width: 2, height: 2, fillValue: 0)

        let grayComp = try transform.rgbToGrayscale(
            redComponent: redComp,
            greenComponent: greenComp,
            blueComponent: blueComp
        )

        XCTAssertEqual(grayComp.width, 2)
        XCTAssertEqual(grayComp.height, 2)
        XCTAssertEqual(grayComp.index, 0)
    }

    func testRGBToGrayscaleEmptyInput() throws {
        let transform = J2KColorTransform()

        let red: [Int32] = []
        let green: [Int32] = []
        let blue: [Int32] = []

        XCTAssertThrowsError(try transform.rgbToGrayscale(red: red, green: green, blue: blue)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    func testRGBToGrayscaleMismatchedSizes() throws {
        let transform = J2KColorTransform()

        let red: [Int32] = [100, 150]
        let green: [Int32] = [80, 120]
        let blue: [Int32] = [60]  // Mismatched size

        XCTAssertThrowsError(try transform.rgbToGrayscale(red: red, green: green, blue: blue)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    // MARK: - Palette Tests

    func testPaletteCreation() throws {
        let entries: [(red: UInt8, green: UInt8, blue: UInt8)] = [
            (255, 0, 0),
            (0, 255, 0),
            (0, 0, 255)
        ]
        let palette = J2KColorTransform.Palette(entries: entries)

        XCTAssertEqual(palette.count, 3)
        XCTAssertEqual(palette.entries[0].red, 255)
        XCTAssertEqual(palette.entries[1].green, 255)
        XCTAssertEqual(palette.entries[2].blue, 255)
    }

    func testExpandPalette() throws {
        let transform = J2KColorTransform()

        let palette = J2KColorTransform.Palette(entries: [
            (255, 0, 0),    // Red
            (0, 255, 0),    // Green
            (0, 0, 255),    // Blue
            (255, 255, 255) // White
        ])

        let indices: [UInt8] = [0, 1, 2, 3, 0, 1, 2, 3]
        let (red, green, blue) = try transform.expandPalette(indices: indices, palette: palette)

        XCTAssertEqual(red.count, 8)
        XCTAssertEqual(green.count, 8)
        XCTAssertEqual(blue.count, 8)

        // Check first 4 pixels
        XCTAssertEqual(red[0], 255)
        XCTAssertEqual(green[0], 0)
        XCTAssertEqual(blue[0], 0)

        XCTAssertEqual(red[1], 0)
        XCTAssertEqual(green[1], 255)
        XCTAssertEqual(blue[1], 0)

        XCTAssertEqual(red[2], 0)
        XCTAssertEqual(green[2], 0)
        XCTAssertEqual(blue[2], 255)

        XCTAssertEqual(red[3], 255)
        XCTAssertEqual(green[3], 255)
        XCTAssertEqual(blue[3], 255)
    }

    func testExpandPaletteInvalidIndex() throws {
        let transform = J2KColorTransform()

        let palette = J2KColorTransform.Palette(entries: [
            (255, 0, 0),
            (0, 255, 0)
        ])

        let indices: [UInt8] = [0, 1, 5]  // Index 5 is out of range

        XCTAssertThrowsError(try transform.expandPalette(indices: indices, palette: palette)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    func testCreatePaletteFewColors() throws {
        let transform = J2KColorTransform()

        // Image with 3 distinct colors
        let red: [UInt8] = [255, 0, 128, 255, 0]
        let green: [UInt8] = [0, 255, 128, 0, 255]
        let blue: [UInt8] = [0, 0, 128, 0, 0]

        let (palette, indices) = try transform.createPalette(
            red: red,
            green: green,
            blue: blue,
            maxColors: 10
        )

        XCTAssertEqual(palette.count, 3)
        XCTAssertEqual(indices.count, 5)

        // Verify indices point to valid palette entries
        for index in indices {
            XCTAssertLessThan(index, UInt8(palette.count))
        }

        // Verify reconstruction
        let (reconstructedRed, reconstructedGreen, reconstructedBlue) = try transform.expandPalette(
            indices: indices,
            palette: palette
        )

        XCTAssertEqual(reconstructedRed, red)
        XCTAssertEqual(reconstructedGreen, green)
        XCTAssertEqual(reconstructedBlue, blue)
    }

    func testCreatePaletteManyColors() throws {
        let transform = J2KColorTransform()

        // Generate image with many colors (more than maxColors)
        var red: [UInt8] = []
        var green: [UInt8] = []
        var blue: [UInt8] = []

        for i in 0..<300 {
            red.append(UInt8(i % 256))
            green.append(UInt8((i * 2) % 256))
            blue.append(UInt8((i * 3) % 256))
        }

        let (palette, indices) = try transform.createPalette(
            red: red,
            green: green,
            blue: blue,
            maxColors: 16
        )

        XCTAssertEqual(palette.count, 16)
        XCTAssertEqual(indices.count, 300)

        // Verify indices point to valid palette entries
        for index in indices {
            XCTAssertLessThan(index, UInt8(palette.count))
        }
    }

    func testCreatePaletteEmptyInput() throws {
        let transform = J2KColorTransform()

        let red: [UInt8] = []
        let green: [UInt8] = []
        let blue: [UInt8] = []

        XCTAssertThrowsError(try transform.createPalette(red: red, green: green, blue: blue)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    func testCreatePaletteInvalidMaxColors() throws {
        let transform = J2KColorTransform()

        let red: [UInt8] = [255, 0, 128]
        let green: [UInt8] = [0, 255, 128]
        let blue: [UInt8] = [0, 0, 128]

        // maxColors out of range
        XCTAssertThrowsError(try transform.createPalette(red: red, green: green, blue: blue, maxColors: 0)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }

        XCTAssertThrowsError(try transform.createPalette(red: red, green: green, blue: blue, maxColors: 257)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    // MARK: - Color Space Detection Tests

    func testDetectGrayscaleColorSpace() throws {
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 256,
            height: 256
        )

        let colorSpace = J2KColorTransform.detectColorSpace(components: [component])

        XCTAssertEqual(colorSpace, .grayscale)
    }

    func testDetectRGBColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 2, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        let colorSpace = J2KColorTransform.detectColorSpace(components: components)

        XCTAssertEqual(colorSpace, .sRGB)
    }

    func testDetectRGBAColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 2, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 3, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        let colorSpace = J2KColorTransform.detectColorSpace(components: components)

        // 4-component images default to sRGB (could be RGBA)
        XCTAssertEqual(colorSpace, .sRGB)
    }

    func testDetectUnknownColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        let colorSpace = J2KColorTransform.detectColorSpace(components: components)

        XCTAssertEqual(colorSpace, .unknown)
    }

    func testDetectEmptyComponentsReturnsUnknown() throws {
        let colorSpace = J2KColorTransform.detectColorSpace(components: [])

        XCTAssertEqual(colorSpace, .unknown)
    }

    // MARK: - Color Space Validation Tests

    func testValidateGrayscaleColorSpace() throws {
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 256,
            height: 256
        )

        // Should not throw
        try J2KColorTransform.validateColorSpace(components: [component], colorSpace: .grayscale)
    }

    func testValidateGrayscaleWithMultipleComponentsFails() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        XCTAssertThrowsError(
            try J2KColorTransform.validateColorSpace(
                components: components, colorSpace: .grayscale)
        ) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error")
                return
            }
        }
    }

    func testValidateRGBColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 2, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        // Should not throw
        try J2KColorTransform.validateColorSpace(components: components, colorSpace: .sRGB)
    }

    func testValidateRGBWithTwoComponentsFails() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        XCTAssertThrowsError(
            try J2KColorTransform.validateColorSpace(
                components: components, colorSpace: .sRGB)
        ) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error")
                return
            }
        }
    }

    func testValidateYCbCrColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 2, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        // Should not throw
        try J2KColorTransform.validateColorSpace(components: components, colorSpace: .yCbCr)
    }

    func testValidateICCProfileColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        // ICC profiles can have arbitrary component counts, so should not throw
        let iccData = Data([0x00, 0x01, 0x02, 0x03])
        try J2KColorTransform.validateColorSpace(components: components, colorSpace: .iccProfile(iccData))
    }

    func testValidateUnknownColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: 256, height: 256),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: 256, height: 256)
        ]

        // Unknown color space should not throw
        try J2KColorTransform.validateColorSpace(components: components, colorSpace: .unknown)
    }
}
