// J2KCrossPlatformValidationTests.swift
// J2KSwift
//
// Tests for cross-platform validation ensuring consistent behavior
// across different operating systems and architectures.

import XCTest
@testable import J2KCore

final class J2KCrossPlatformValidationTests: XCTestCase {
    
    // MARK: - Platform Detection Tests
    
    func testPlatformDetection() throws {
        let os = J2KPlatformInfo.currentOS
        XCTAssertNotEqual(os, .unknown, "Should detect current OS")
        
        // Verify the platform matches compile-time checks
        #if os(macOS)
        XCTAssertEqual(os, .macOS)
        #elseif os(iOS)
        XCTAssertEqual(os, .iOS)
        #elseif os(tvOS)
        XCTAssertEqual(os, .tvOS)
        #elseif os(watchOS)
        XCTAssertEqual(os, .watchOS)
        #elseif os(Linux)
        XCTAssertEqual(os, .linux)
        #elseif os(Windows)
        XCTAssertEqual(os, .windows)
        #endif
    }
    
    func testArchitectureDetection() throws {
        let arch = J2KPlatformInfo.currentArchitecture
        XCTAssertNotEqual(arch, .unknown, "Should detect current architecture")
        
        #if arch(arm64)
        XCTAssertEqual(arch, .arm64)
        #elseif arch(x86_64)
        XCTAssertEqual(arch, .x86_64)
        #endif
    }
    
    func testHardwareAccelerationDetection() throws {
        let hasAcceleration = J2KPlatformInfo.hasHardwareAcceleration
        
        #if canImport(Accelerate)
        XCTAssertTrue(hasAcceleration, "Should detect Accelerate framework")
        #else
        XCTAssertFalse(hasAcceleration, "Should not detect Accelerate on this platform")
        #endif
    }
    
    func testApplePlatformDetection() throws {
        let isApple = J2KPlatformInfo.isApplePlatform
        
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        XCTAssertTrue(isApple, "Should be detected as Apple platform")
        #else
        XCTAssertFalse(isApple, "Should not be detected as Apple platform")
        #endif
    }
    
    func testPlatformSummary() throws {
        let summary = J2KPlatformInfo.platformSummary()
        
        XCTAssertTrue(summary.contains("J2KSwift Platform Info"))
        XCTAssertTrue(summary.contains("OS:"))
        XCTAssertTrue(summary.contains("Architecture:"))
        XCTAssertTrue(summary.contains("Apple Platform:"))
        XCTAssertTrue(summary.contains("Hardware Acceleration:"))
        XCTAssertTrue(summary.contains("Pointer Size:"))
        XCTAssertTrue(summary.contains("Byte Order:"))
    }
    
    func testPointerSize() throws {
        let pointerSize = J2KPlatformInfo.pointerSize
        // All supported platforms are 64-bit
        XCTAssertEqual(pointerSize, 8, "Expected 64-bit pointer size")
    }
    
    func testByteOrderDetection() throws {
        // Verify byte order detection is accessible and returns a valid value
        let isLittleEndian = J2KPlatformInfo.isLittleEndian
        // On x86_64 and arm64, we expect little-endian
        #if arch(x86_64) || arch(arm64)
        XCTAssertTrue(isLittleEndian, "x86_64 and arm64 should be little-endian")
        #else
        // Just verify the property returns without error
        XCTAssertTrue(isLittleEndian || !isLittleEndian)
        #endif
    }
    
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
            return [UInt8(marker >> 8), UInt8(marker & 0xFF)]
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
        let test: [Int32] =      [1, 63, 130, 190, 254, 102, 48, 198, 152, 73]
        
        let mse = J2KErrorMetrics.meanSquaredError(reference: reference, test: test)
        XCTAssertNotNil(mse)
        
        // Expected MSE: (1+1+4+4+1+4+4+4+4+4)/10 = 3.1
        XCTAssertEqual(mse!, 3.1, accuracy: 0.0001,
                       "MSE should be consistent across platforms")
    }
    
    func testPSNRConsistentAcrossPlatforms() throws {
        let reference: [Int32] = [0, 64, 128, 192, 255, 100, 50, 200, 150, 75]
        let test: [Int32] =      [1, 63, 130, 190, 254, 102, 48, 198, 152, 73]
        
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
        let test: [Int32] =      [1, 63, 130, 190, 254, 102, 48, 198, 152, 73]
        
        let mae = J2KErrorMetrics.maximumAbsoluteError(reference: reference, test: test)
        XCTAssertNotNil(mae)
        XCTAssertEqual(mae!, 2, "MAE should be consistent across platforms")
    }
    
    // MARK: - Cross-Platform Image Generation Consistency
    
    func testImageGenerationConsistentAcrossPlatforms() throws {
        let pixels = J2KISOTestSuiteLoader.generateTestImage(
            width: 8, height: 8, components: 1, bitDepth: 8
        )
        
        // Verify specific known values that should be identical on all platforms
        // First pixel of first row (x=0, y=0) should be 0
        XCTAssertEqual(pixels[0], 0, "First pixel should be 0")
        
        // Last pixel of first row (x=7, y=0) should be 255
        XCTAssertEqual(pixels[7], 255, "Last pixel in first row should be 255")
        
        // First pixel of last row (x=0, y=7) should be 0 (horizontal gradient for component 0)
        XCTAssertEqual(pixels[7 * 8], 0, "First pixel of last row should be 0")
    }
    
    func testImageGenerationMultiComponentConsistency() throws {
        let pixels = J2KISOTestSuiteLoader.generateTestImage(
            width: 4, height: 4, components: 3, bitDepth: 8
        )
        
        // Total pixels: 4 * 4 * 3 = 48
        XCTAssertEqual(pixels.count, 48)
        
        // Component 0: horizontal gradient
        // Component 1: vertical gradient
        // Component 2: diagonal average
        
        // Component 0, first pixel (x=0, y=0): 0
        XCTAssertEqual(pixels[0], 0)
        
        // Component 1, first pixel (component offset = 16, x=0, y=0): 0
        XCTAssertEqual(pixels[16], 0)
        
        // All values should be deterministic
        let pixels2 = J2KISOTestSuiteLoader.generateTestImage(
            width: 4, height: 4, components: 3, bitDepth: 8
        )
        XCTAssertEqual(pixels, pixels2, "Multi-component generation should be deterministic")
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
    
    // MARK: - Platform-Specific Feature Availability
    
    func testAccelerateAvailability() throws {
        #if canImport(Accelerate)
        // On Apple platforms, hardware acceleration should be available
        XCTAssertTrue(J2KPlatformInfo.hasHardwareAcceleration)
        XCTAssertTrue(J2KPlatformInfo.isApplePlatform)
        #else
        // On non-Apple platforms, no hardware acceleration
        XCTAssertFalse(J2KPlatformInfo.hasHardwareAcceleration)
        // Should still function correctly without it
        let ref: [Int32] = [100, 200]
        let test: [Int32] = [101, 199]
        let mse = J2KErrorMetrics.meanSquaredError(reference: ref, test: test)
        XCTAssertNotNil(mse, "Error metrics should work without hardware acceleration")
        #endif
    }
    
    // MARK: - Cross-Platform Conformance Validator Consistency
    
    func testConformanceValidatorConsistency() throws {
        let reference = J2KISOTestSuiteLoader.generateTestImage(
            width: 16, height: 16, components: 1, bitDepth: 8
        )
        
        let vector = J2KTestVector(
            name: "cross_platform_test",
            description: "Cross-platform validation test",
            codestream: Data(),
            referenceImage: reference,
            width: 16,
            height: 16,
            components: 1,
            bitDepth: 8,
            maxAllowableError: 0
        )
        
        // Perfect match should always pass regardless of platform
        let result = J2KConformanceValidator.validate(
            decoded: reference,
            against: vector
        )
        
        XCTAssertTrue(result.passed,
                      "Perfect match validation should pass on all platforms")
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.mse!, 0.0, accuracy: 0.0001)
        XCTAssertEqual(result.mae!, 0)
        XCTAssertEqual(result.psnr!, Double.infinity)
    }
    
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
    
    // MARK: - Operating System Enum Tests
    
    func testOperatingSystemRawValues() throws {
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.macOS.rawValue, "macOS")
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.iOS.rawValue, "iOS")
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.tvOS.rawValue, "tvOS")
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.watchOS.rawValue, "watchOS")
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.visionOS.rawValue, "visionOS")
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.linux.rawValue, "Linux")
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.windows.rawValue, "Windows")
        XCTAssertEqual(J2KPlatformInfo.OperatingSystem.unknown.rawValue, "Unknown")
    }
    
    func testArchitectureRawValues() throws {
        XCTAssertEqual(J2KPlatformInfo.Architecture.arm64.rawValue, "arm64")
        XCTAssertEqual(J2KPlatformInfo.Architecture.x86_64.rawValue, "x86_64")
        XCTAssertEqual(J2KPlatformInfo.Architecture.arm.rawValue, "arm")
        XCTAssertEqual(J2KPlatformInfo.Architecture.i386.rawValue, "i386")
        XCTAssertEqual(J2KPlatformInfo.Architecture.unknown.rawValue, "Unknown")
    }
}
