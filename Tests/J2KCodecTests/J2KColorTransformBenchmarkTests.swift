//
// J2KColorTransformBenchmarkTests.swift
// J2KSwift
//
// J2KColorTransformBenchmarkTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Performance benchmarks for JPEG 2000 color transforms.
final class J2KColorTransformBenchmarkTests: XCTestCase {
    override class var defaultTestSuite: XCTestSuite { XCTestSuite(name: "J2KColorTransformBenchmarkTests (Disabled)") }

    // MARK: - Image Size Benchmarks

    func testRCTSmallImage() throws {
        // 256×256 pixels
        let size = 256 * 256
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }
    }

    func testRCTMediumImage() throws {
        // 512×512 pixels
        let size = 512 * 512
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }
    }

    func testRCTLargeImage() throws {
        // 1024×1024 pixels
        let size = 1024 * 1024
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }
    }

    func testRCTVeryLargeImage() throws {
        // 2048×2048 pixels
        let size = 2048 * 2048
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }
    }

    // MARK: - Inverse Transform Benchmarks

    func testInverseRCTSmallImage() throws {
        // 256×256 pixels
        let size = 256 * 256
        let transform = J2KColorTransform()

        let y = createTestData(count: size, baseValue: 80)
        let cb = createTestData(count: size, baseValue: -20)
        let cr = createTestData(count: size, baseValue: 20)

        measure {
            _ = try? transform.inverseRCT(y: y, cb: cb, cr: cr)
        }
    }

    func testInverseRCTMediumImage() throws {
        // 512×512 pixels
        let size = 512 * 512
        let transform = J2KColorTransform()

        let y = createTestData(count: size, baseValue: 80)
        let cb = createTestData(count: size, baseValue: -20)
        let cr = createTestData(count: size, baseValue: 20)

        measure {
            _ = try? transform.inverseRCT(y: y, cb: cb, cr: cr)
        }
    }

    func testInverseRCTLargeImage() throws {
        // 1024×1024 pixels
        let size = 1024 * 1024
        let transform = J2KColorTransform()

        let y = createTestData(count: size, baseValue: 80)
        let cb = createTestData(count: size, baseValue: -20)
        let cr = createTestData(count: size, baseValue: 20)

        measure {
            _ = try? transform.inverseRCT(y: y, cb: cb, cr: cr)
        }
    }

    // MARK: - Round-Trip Benchmarks

    func testRCTRoundTripSmallImage() throws {
        // 256×256 pixels
        let size = 256 * 256
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measure {
            if let (y, cb, cr) = try? transform.forwardRCT(red: red, green: green, blue: blue) {
                _ = try? transform.inverseRCT(y: y, cb: cb, cr: cr)
            }
        }
    }

    func testRCTRoundTripMediumImage() throws {
        // 512×512 pixels
        let size = 512 * 512
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measure {
            if let (y, cb, cr) = try? transform.forwardRCT(red: red, green: green, blue: blue) {
                _ = try? transform.inverseRCT(y: y, cb: cb, cr: cr)
            }
        }
    }

    func testRCTRoundTripLargeImage() throws {
        // 1024×1024 pixels
        let size = 1024 * 1024
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measure {
            if let (y, cb, cr) = try? transform.forwardRCT(red: red, green: green, blue: blue) {
                _ = try? transform.inverseRCT(y: y, cb: cb, cr: cr)
            }
        }
    }

    // MARK: - Component-Based Transform Benchmarks

    func testRCTWithComponentsSmall() throws {
        let width = 256
        let height = 256
        let transform = J2KColorTransform()

        let redComp = createTestComponent(index: 0, width: width, height: height, fillValue: 100)
        let greenComp = createTestComponent(index: 1, width: width, height: height, fillValue: 80)
        let blueComp = createTestComponent(index: 2, width: width, height: height, fillValue: 60)

        measure {
            _ = try? transform.forwardRCT(
                redComponent: redComp,
                greenComponent: greenComp,
                blueComponent: blueComp
            )
        }
    }

    func testRCTWithComponentsMedium() throws {
        let width = 512
        let height = 512
        let transform = J2KColorTransform()

        let redComp = createTestComponent(index: 0, width: width, height: height, fillValue: 100)
        let greenComp = createTestComponent(index: 1, width: width, height: height, fillValue: 80)
        let blueComp = createTestComponent(index: 2, width: width, height: height, fillValue: 60)

        measure {
            _ = try? transform.forwardRCT(
                redComponent: redComp,
                greenComponent: greenComp,
                blueComponent: blueComp
            )
        }
    }

    func testRCTWithComponentsLarge() throws {
        let width = 1024
        let height = 1024
        let transform = J2KColorTransform()

        let redComp = createTestComponent(index: 0, width: width, height: height, fillValue: 100)
        let greenComp = createTestComponent(index: 1, width: width, height: height, fillValue: 80)
        let blueComp = createTestComponent(index: 2, width: width, height: height, fillValue: 60)

        measure {
            _ = try? transform.forwardRCT(
                redComponent: redComp,
                greenComponent: greenComp,
                blueComponent: blueComp
            )
        }
    }

    // MARK: - Data Pattern Benchmarks

    func testRCTUniformData() throws {
        // Test with uniform values
        let size = 512 * 512
        let transform = J2KColorTransform()

        let red = [Int32](repeating: 128, count: size)
        let green = [Int32](repeating: 128, count: size)
        let blue = [Int32](repeating: 128, count: size)

        measure {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }
    }

    func testRCTRandomData() throws {
        // Test with pseudo-random values
        let size = 512 * 512
        let transform = J2KColorTransform()

        var red = [Int32](repeating: 0, count: size)
        var green = [Int32](repeating: 0, count: size)
        var blue = [Int32](repeating: 0, count: size)

        for i in 0..<size {
            red[i] = Int32((i * 17) % 256)
            green[i] = Int32((i * 31) % 256)
            blue[i] = Int32((i * 47) % 256)
        }

        measure {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }
    }

    func testRCTGrayscaleData() throws {
        // Test with grayscale (R=G=B)
        let size = 512 * 512
        let transform = J2KColorTransform()

        var red = [Int32](repeating: 0, count: size)
        var green = [Int32](repeating: 0, count: size)
        var blue = [Int32](repeating: 0, count: size)

        for i in 0..<size {
            let gray = Int32(i % 256)
            red[i] = gray
            green[i] = gray
            blue[i] = gray
        }

        measure {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }
    }

    // MARK: - Throughput Benchmarks

    func testRCTThroughputSmallBatches() throws {
        let transform = J2KColorTransform()
        let batchSize = 64 * 64  // Small 64×64 images
        let batchCount = 100

        var batches: [([Int32], [Int32], [Int32])] = []
        for _ in 0..<batchCount {
            batches.append((
                createTestData(count: batchSize, baseValue: 100),
                createTestData(count: batchSize, baseValue: 80),
                createTestData(count: batchSize, baseValue: 60)
            ))
        }

        measure {
            for (red, green, blue) in batches {
                _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
            }
        }
    }

    func testRCTThroughputMediumBatches() throws {
        let transform = J2KColorTransform()
        let batchSize = 256 * 256  // Medium 256×256 images
        let batchCount = 10

        var batches: [([Int32], [Int32], [Int32])] = []
        for _ in 0..<batchCount {
            batches.append((
                createTestData(count: batchSize, baseValue: 100),
                createTestData(count: batchSize, baseValue: 80),
                createTestData(count: batchSize, baseValue: 60)
            ))
        }

        measure {
            for (red, green, blue) in batches {
                _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
            }
        }
    }

    // MARK: - Memory Allocation Benchmarks

    func testRCTMemoryAllocation() throws {
        let size = 1024 * 1024
        let transform = J2KColorTransform()

        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            startMeasuring()
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
            stopMeasuring()
        }
    }

    // MARK: - Comparison Benchmarks

    func testRCTVsInverseRCTPerformance() throws {
        let size = 512 * 512
        let transform = J2KColorTransform()

        // Prepare data for forward transform
        let red = createTestData(count: size, baseValue: 100)
        let green = createTestData(count: size, baseValue: 80)
        let blue = createTestData(count: size, baseValue: 60)

        // Prepare data for inverse transform
        let y = createTestData(count: size, baseValue: 80)
        let cb = createTestData(count: size, baseValue: -20)
        let cr = createTestData(count: size, baseValue: 20)

        // Measure forward transform
        let forwardTime = measureTime {
            _ = try? transform.forwardRCT(red: red, green: green, blue: blue)
        }

        // Measure inverse transform
        let inverseTime = measureTime {
            _ = try? transform.inverseRCT(y: y, cb: cb, cr: cr)
        }

        print("Forward RCT: \(String(format: "%.2f", forwardTime * 1000)) ms")
        print("Inverse RCT: \(String(format: "%.2f", inverseTime * 1000)) ms")
        print("Ratio (Inverse/Forward): \(String(format: "%.2f", inverseTime / forwardTime))")

        // Both should be roughly the same performance
        XCTAssertLessThan(abs(inverseTime - forwardTime) / forwardTime, 0.5,
                         "Forward and inverse transforms should have similar performance")
    }

    // MARK: - Helper Methods

    private func createTestData(count: Int, baseValue: Int32, vary: Bool = false) -> [Int32] {
        if vary {
            return (0..<count).map { Int32((baseValue + Int32($0 % 50)) - 25) }
        } else {
            return [Int32](repeating: baseValue, count: count)
        }
    }

    private func createTestComponent(
        index: Int,
        width: Int,
        height: Int,
        fillValue: Int32
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
            data: data
        )
    }

    private func measureTime(_ block: () -> Void) -> TimeInterval {
        let start = Date()
        block()
        return Date().timeIntervalSince(start)
    }

    // MARK: - ICT Benchmarks

    func testICTSmallImageForward() throws {
        // 256×256 pixels
        let size = 256 * 256
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    func testICTMediumImageForward() throws {
        // 512×512 pixels
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    func testICTLargeImageForward() throws {
        // 1024×1024 pixels
        let size = 1024 * 1024
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    func testICTVeryLargeImageForward() throws {
        // 2048×2048 pixels
        let size = 2048 * 2048
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        measure {
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    func testICTSmallImageInverse() throws {
        // 256×256 pixels
        let size = 256 * 256
        let transform = J2KColorTransform(configuration: .lossy)

        let y = createDoubleTestData(count: size, baseValue: 80)
        let cb = createDoubleTestData(count: size, baseValue: -20)
        let cr = createDoubleTestData(count: size, baseValue: 20)

        measure {
            _ = try? transform.inverseICT(y: y, cb: cb, cr: cr)
        }
    }

    func testICTMediumImageInverse() throws {
        // 512×512 pixels
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        let y = createDoubleTestData(count: size, baseValue: 80)
        let cb = createDoubleTestData(count: size, baseValue: -20)
        let cr = createDoubleTestData(count: size, baseValue: 20)

        measure {
            _ = try? transform.inverseICT(y: y, cb: cb, cr: cr)
        }
    }

    func testICTLargeImageInverse() throws {
        // 1024×1024 pixels
        let size = 1024 * 1024
        let transform = J2KColorTransform(configuration: .lossy)

        let y = createDoubleTestData(count: size, baseValue: 80)
        let cb = createDoubleTestData(count: size, baseValue: -20)
        let cr = createDoubleTestData(count: size, baseValue: 20)

        measure {
            _ = try? transform.inverseICT(y: y, cb: cb, cr: cr)
        }
    }

    func testICTRoundTripSmall() throws {
        // 256×256 pixels
        let size = 256 * 256
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        measure {
            if let (y, cb, cr) = try? transform.forwardICT(red: red, green: green, blue: blue) {
                _ = try? transform.inverseICT(y: y, cb: cb, cr: cr)
            }
        }
    }

    func testICTRoundTripMedium() throws {
        // 512×512 pixels
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        measure {
            if let (y, cb, cr) = try? transform.forwardICT(red: red, green: green, blue: blue) {
                _ = try? transform.inverseICT(y: y, cb: cb, cr: cr)
            }
        }
    }

    func testICTRoundTripLarge() throws {
        // 1024×1024 pixels
        let size = 1024 * 1024
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        measure {
            if let (y, cb, cr) = try? transform.forwardICT(red: red, green: green, blue: blue) {
                _ = try? transform.inverseICT(y: y, cb: cb, cr: cr)
            }
        }
    }

    func testICTWithRandomData() throws {
        // 512×512 pixels with random data
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, randomize: true)
        let green = createDoubleTestData(count: size, randomize: true)
        let blue = createDoubleTestData(count: size, randomize: true)

        measure {
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    func testICTComponentAPISmall() throws {
        // 256×256 pixels
        let size = 256
        let transform = J2KColorTransform(configuration: .lossy)

        let redComp = createTestComponent(index: 0, width: size, height: size, fillValue: 100)
        let greenComp = createTestComponent(index: 1, width: size, height: size, fillValue: 80)
        let blueComp = createTestComponent(index: 2, width: size, height: size, fillValue: 60)

        measure {
            _ = try? transform.forwardICT(
                redComponent: redComp,
                greenComponent: greenComp,
                blueComponent: blueComp
            )
        }
    }

    func testICTComponentAPIMedium() throws {
        // 512×512 pixels
        let size = 512
        let transform = J2KColorTransform(configuration: .lossy)

        let redComp = createTestComponent(index: 0, width: size, height: size, fillValue: 100)
        let greenComp = createTestComponent(index: 1, width: size, height: size, fillValue: 80)
        let blueComp = createTestComponent(index: 2, width: size, height: size, fillValue: 60)

        measure {
            _ = try? transform.forwardICT(
                redComponent: redComp,
                greenComponent: greenComp,
                blueComponent: blueComp
            )
        }
    }

    func testICTComponentAPILarge() throws {
        // 1024×1024 pixels
        let size = 1024
        let transform = J2KColorTransform(configuration: .lossy)

        let redComp = createTestComponent(index: 0, width: size, height: size, fillValue: 100)
        let greenComp = createTestComponent(index: 1, width: size, height: size, fillValue: 80)
        let blueComp = createTestComponent(index: 2, width: size, height: size, fillValue: 60)

        measure {
            _ = try? transform.forwardICT(
                redComponent: redComp,
                greenComponent: greenComp,
                blueComponent: blueComp
            )
        }
    }

    func testICTBatchProcessingSmall() throws {
        // Process 100 small images (64×64)
        let size = 64 * 64
        let batchSize = 100
        let transform = J2KColorTransform(configuration: .lossy)

        var batches: [([Double], [Double], [Double])] = []
        for _ in 0..<batchSize {
            let red = createDoubleTestData(count: size, randomize: true)
            let green = createDoubleTestData(count: size, randomize: true)
            let blue = createDoubleTestData(count: size, randomize: true)
            batches.append((red, green, blue))
        }

        measure {
            for (red, green, blue) in batches {
                _ = try? transform.forwardICT(red: red, green: green, blue: blue)
            }
        }
    }

    func testICTBatchProcessingMedium() throws {
        // Process 10 medium images (256×256)
        let size = 256 * 256
        let batchSize = 10
        let transform = J2KColorTransform(configuration: .lossy)

        var batches: [([Double], [Double], [Double])] = []
        for _ in 0..<batchSize {
            let red = createDoubleTestData(count: size, randomize: true)
            let green = createDoubleTestData(count: size, randomize: true)
            let blue = createDoubleTestData(count: size, randomize: true)
            batches.append((red, green, blue))
        }

        measure {
            for (red, green, blue) in batches {
                _ = try? transform.forwardICT(red: red, green: green, blue: blue)
            }
        }
    }

    func testICTMemoryAllocation() throws {
        // Test memory allocation overhead
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        measure {
            let red = createDoubleTestData(count: size, baseValue: 100)
            let green = createDoubleTestData(count: size, baseValue: 80)
            let blue = createDoubleTestData(count: size, baseValue: 60)
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    func testICTForwardVsInverse() throws {
        // Compare forward vs inverse performance
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        let red = createDoubleTestData(count: size, baseValue: 100)
        let green = createDoubleTestData(count: size, baseValue: 80)
        let blue = createDoubleTestData(count: size, baseValue: 60)

        let (y, cb, cr) = try transform.forwardICT(red: red, green: green, blue: blue)

        // Measure only the inverse
        measure {
            _ = try? transform.inverseICT(y: y, cb: cb, cr: cr)
        }
    }

    func testICTDecorrelationPerformance() throws {
        // Test with highly correlated data (common in natural images)
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        var red = [Double](repeating: 0, count: size)
        var green = [Double](repeating: 0, count: size)
        var blue = [Double](repeating: 0, count: size)

        for i in 0..<size {
            let base = Double(i % 256)
            red[i] = base + 10
            green[i] = base + 5
            blue[i] = base - 5
        }

        measure {
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    func testICTWithExtremeValues() throws {
        // Test with extreme values (stress test)
        let size = 512 * 512
        let transform = J2KColorTransform(configuration: .lossy)

        var red = [Double](repeating: 0, count: size)
        var green = [Double](repeating: 0, count: size)
        var blue = [Double](repeating: 0, count: size)

        for i in 0..<size {
            red[i] = Double((i.isMultiple(of: 2)) ? 4095 : -4095)
            green[i] = Double((i.isMultiple(of: 3)) ? 4095 : -4095)
            blue[i] = Double((i.isMultiple(of: 5)) ? 4095 : -4095)
        }

        measure {
            _ = try? transform.forwardICT(red: red, green: green, blue: blue)
        }
    }

    // MARK: - Helper Methods for ICT Benchmarks

    private func createDoubleTestData(count: Int, baseValue: Double = 0, randomize: Bool = false) -> [Double] {
        if randomize {
            var result = [Double](repeating: 0, count: count)
            for i in 0..<count {
                result[i] = Double((i * 17) % 256) - 128
            }
            return result
        } else {
            return [Double](repeating: baseValue, count: count)
        }
    }
}
