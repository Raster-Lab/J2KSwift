//
// J2KCrossPlatformValidationTests.swift
// J2KSwift
//
// J2KCrossPlatformValidationTests.swift
// J2KSwift
//
// Tests for cross-platform validation ensuring consistent behavior
// across different operating systems and architectures.

import XCTest
@testable import J2KCore

final class J2KCrossPlatformValidationTests: XCTestCase {
    // MARK: - Cross-Platform Data Consistency Tests

    func testInt32RepresentationConsistency() throws {
        // Verify Int32 has consistent behavior across platforms
        XCTAssertEqual(MemoryLayout<Int32>.size, 4,
                       "Int32 should always be 4 bytes")
        XCTAssertEqual(Int32.max, 2147483647)
        XCTAssertEqual(Int32.min, -2147483648)
    }

    func testDoubleRepresentationConsistency() throws {
        // Verify Double (IEEE 754) consistency
        XCTAssertEqual(MemoryLayout<Double>.size, 8,
                       "Double should always be 8 bytes")

        // Known IEEE 754 values
        XCTAssertTrue(Double.nan.isNaN)
        XCTAssertTrue(Double.infinity.isInfinite)
        XCTAssertEqual(Double.pi, 3.141592653589793, accuracy: 1e-15)
    }

    func testDataEndianConsistency() throws {
        // Test that Data byte representation is consistent
        let value: UInt16 = 0xFF4F  // SOC marker
        var bigEndian = value.bigEndian
        let data = Data(bytes: &bigEndian, count: 2)

        // Big-endian representation should always be 0xFF 0x4F
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x4F)
    }

    func testMarkerByteOrder() throws {
        // JPEG 2000 markers are big-endian (network byte order)
        // Verify consistent marker creation across platforms
        let socMarker: UInt16 = 0xFF4F
        let sizMarker: UInt16 = 0xFF51
        let codMarker: UInt16 = 0xFF52
        let eocMarker: UInt16 = 0xFFD9

        // Big-endian byte representation
        func markerBytes(_ marker: UInt16) -> [UInt8] {
            [UInt8(marker >> 8), UInt8(marker & 0xFF)]
        }

        XCTAssertEqual(markerBytes(socMarker), [0xFF, 0x4F])
        XCTAssertEqual(markerBytes(sizMarker), [0xFF, 0x51])
        XCTAssertEqual(markerBytes(codMarker), [0xFF, 0x52])
        XCTAssertEqual(markerBytes(eocMarker), [0xFF, 0xD9])
    }

    // MARK: - Cross-Platform Error Metrics Consistency

    func testMSEConsistentAcrossPlatforms() throws {
        // Use fixed test data that should produce identical results everywhere
        let reference: [Int32] = [0, 64, 128, 192, 255, 100, 50, 200, 150, 75]
        let test: [Int32] = [1, 63, 130, 190, 254, 102, 48, 198, 152, 73]

        let mse = J2KErrorMetrics.meanSquaredError(reference: reference, test: test)
        XCTAssertNotNil(mse)

        // Expected MSE: (1+1+4+4+1+4+4+4+4+4)/10 = 3.1
        XCTAssertEqual(mse!, 3.1, accuracy: 0.0001,
                       "MSE should be consistent across platforms")
    }

    func testPSNRConsistentAcrossPlatforms() throws {
        let reference: [Int32] = [0, 64, 128, 192, 255, 100, 50, 200, 150, 75]
        let test: [Int32] = [1, 63, 130, 190, 254, 102, 48, 198, 152, 73]

        let psnr = J2KErrorMetrics.peakSignalToNoiseRatio(
            reference: reference, test: test, bitDepth: 8
        )
        XCTAssertNotNil(psnr)

        // Expected PSNR: 10 * log10(255^2 / 3.1) = 10 * log10(20975.806) ≈ 43.22 dB
        XCTAssertEqual(psnr!, 43.22, accuracy: 0.1,
                       "PSNR should be consistent across platforms")
    }

    func testMAEConsistentAcrossPlatforms() throws {
        let reference: [Int32] = [0, 64, 128, 192, 255, 100, 50, 200, 150, 75]
        let test: [Int32] = [1, 63, 130, 190, 254, 102, 48, 198, 152, 73]

        let mae = J2KErrorMetrics.maximumAbsoluteError(reference: reference, test: test)
        XCTAssertNotNil(mae)
        XCTAssertEqual(mae!, 2, "MAE should be consistent across platforms")
    }

    // MARK: - Cross-Platform J2KImage Consistency

    func testJ2KImageCreationConsistency() throws {
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: 16,
            height: 16,
            subsamplingX: 1,
            subsamplingY: 1,
            data: Data(repeating: 128, count: 16 * 16)
        )

        let image = J2KImage(
            width: 16,
            height: 16,
            components: [component]
        )

        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 16)
        XCTAssertEqual(image.components.count, 1)
        XCTAssertEqual(image.components[0].bitDepth, 8)
        XCTAssertEqual(image.components[0].maxValue, 255)
        XCTAssertEqual(image.components[0].minValue, 0)
        XCTAssertEqual(image.pixelCount, 256)
        XCTAssertTrue(image.isGrayscale)
    }

    func testJ2KComponentMaxMinValues() throws {
        // 8-bit unsigned
        let comp8u = J2KComponent(index: 0, bitDepth: 8, signed: false, width: 1, height: 1)
        XCTAssertEqual(comp8u.maxValue, 255)
        XCTAssertEqual(comp8u.minValue, 0)

        // 8-bit signed
        let comp8s = J2KComponent(index: 0, bitDepth: 8, signed: true, width: 1, height: 1)
        XCTAssertEqual(comp8s.maxValue, 255)
        XCTAssertEqual(comp8s.minValue, -128)

        // 12-bit unsigned
        let comp12u = J2KComponent(index: 0, bitDepth: 12, signed: false, width: 1, height: 1)
        XCTAssertEqual(comp12u.maxValue, 4095)
        XCTAssertEqual(comp12u.minValue, 0)

        // 16-bit unsigned
        let comp16u = J2KComponent(index: 0, bitDepth: 16, signed: false, width: 1, height: 1)
        XCTAssertEqual(comp16u.maxValue, 65535)
        XCTAssertEqual(comp16u.minValue, 0)
    }

    // MARK: - Cross-Platform Floating Point Consistency

    func testFloatingPointArithmeticConsistency() throws {
        // These operations should produce identical results on all platforms
        // (IEEE 754 double precision)

        let a: Double = 255.0
        let b: Double = 100.0

        // MSE-like calculation
        let diff = a - b
        let squared = diff * diff
        XCTAssertEqual(squared, 24025.0, accuracy: 0.0,
                       "Integer-like floating point should be exact")

        // PSNR-like calculation
        let maxVal: Double = 255.0
        let mse: Double = 100.0
        let psnr = 10.0 * log10((maxVal * maxVal) / mse)
        XCTAssertEqual(psnr, 28.1308, accuracy: 0.001,
                       "PSNR calculation should be consistent")
    }

    func testBitShiftConsistency() throws {
        // Verify bit operations used in JPEG 2000 are consistent
        XCTAssertEqual(1 << 8, 256)
        XCTAssertEqual(1 << 12, 4096)
        XCTAssertEqual(1 << 16, 65536)
        XCTAssertEqual((1 << 8) - 1, 255)
        XCTAssertEqual((1 << 12) - 1, 4095)
        XCTAssertEqual((1 << 16) - 1, 65535)
    }

    // MARK: - Cross-Platform Test Vector Consistency

    func testTestVectorSendable() throws {
        // J2KTestVector must be Sendable for cross-platform thread safety
        let vector = J2KTestVector(
            name: "test",
            description: "Sendable test",
            codestream: Data([0xFF, 0x4F]),
            referenceImage: [100, 200],
            width: 1,
            height: 2,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 0
        )

        // Verify properties survive copy (value type semantics)
        let copy = vector
        XCTAssertEqual(copy.name, vector.name)
        XCTAssertEqual(copy.width, vector.width)
        XCTAssertEqual(copy.referenceImage, vector.referenceImage)
    }

    func testErrorMetricsSendable() throws {
        // J2KErrorMetrics operations should be stateless and thread-safe
        let ref: [Int32] = [100, 200, 150]
        let test: [Int32] = [101, 199, 152]

        // These should all be safe to call from any thread
        let mse = J2KErrorMetrics.meanSquaredError(reference: ref, test: test)
        let psnr = J2KErrorMetrics.peakSignalToNoiseRatio(reference: ref, test: test, bitDepth: 8)
        let mae = J2KErrorMetrics.maximumAbsoluteError(reference: ref, test: test)
        let tolerance = J2KErrorMetrics.withinTolerance(reference: ref, test: test, maxError: 3)

        XCTAssertNotNil(mse)
        XCTAssertNotNil(psnr)
        XCTAssertNotNil(mae)
        XCTAssertTrue(tolerance)
    }

    // MARK: - Cross-Platform Conformance Validator Consistency

    func testConformanceReportConsistency() throws {
        let reference: [Int32] = [100, 200, 150, 50]
        let decoded: [Int32] = [100, 200, 150, 50]

        let vector = J2KTestVector(
            name: "report_test",
            description: "Report consistency test",
            codestream: Data(),
            referenceImage: reference,
            width: 2,
            height: 2,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 0
        )

        let result = J2KConformanceValidator.validate(
            decoded: decoded,
            against: vector
        )

        let report = J2KConformanceValidator.generateReport(results: [result])

        // Report format should be consistent across platforms
        XCTAssertTrue(report.contains("1/1 tests passed"))
        XCTAssertTrue(report.contains("100.0%"))
    }
}
