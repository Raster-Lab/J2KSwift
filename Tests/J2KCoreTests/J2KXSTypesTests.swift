// J2KXSTypesTests.swift
// J2KSwift
//
// Tests for Phase 19 JPEG XS exploration types.

import XCTest
@testable import J2KCore

final class J2KXSTypesTests: XCTestCase {

    // MARK: - J2KXSProfile

    func testProfileMaxComponentsLight() {
        XCTAssertEqual(J2KXSProfile.light.maxComponents, 1)
    }

    func testProfileMaxComponentsMain() {
        XCTAssertEqual(J2KXSProfile.main.maxComponents, 4)
    }

    func testProfileMaxComponentsHigh() {
        XCTAssertEqual(J2KXSProfile.high.maxComponents, 16)
    }

    func testProfileAllCasesPresent() {
        let all = J2KXSProfile.allCases
        XCTAssertTrue(all.contains(.light))
        XCTAssertTrue(all.contains(.main))
        XCTAssertTrue(all.contains(.high))
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - J2KXSLevel

    func testLevelPixelRateSublevel0() {
        XCTAssertEqual(J2KXSLevel.sublevel0.pixelRateGigaPixelsPerSecond, 1.0)
    }

    func testLevelPixelRateSublevel1() {
        XCTAssertEqual(J2KXSLevel.sublevel1.pixelRateGigaPixelsPerSecond, 2.0)
    }

    func testLevelPixelRateSublevel2() {
        XCTAssertEqual(J2KXSLevel.sublevel2.pixelRateGigaPixelsPerSecond, 4.0)
    }

    func testLevelPixelRateSublevel3() {
        XCTAssertEqual(J2KXSLevel.sublevel3.pixelRateGigaPixelsPerSecond, 8.0)
    }

    func testLevelAllCasesPresent() {
        let all = J2KXSLevel.allCases
        XCTAssertEqual(all.count, 4)
    }

    // MARK: - J2KXSSliceHeight

    func testSliceHeight16Pixels() {
        XCTAssertEqual(J2KXSSliceHeight.height16.pixels, 16)
    }

    func testSliceHeight32Pixels() {
        XCTAssertEqual(J2KXSSliceHeight.height32.pixels, 32)
    }

    func testSliceHeight64Pixels() {
        XCTAssertEqual(J2KXSSliceHeight.height64.pixels, 64)
    }

    func testSliceHeightAllCasesPresent() {
        let all = J2KXSSliceHeight.allCases
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - J2KXSConfiguration

    func testPreviewPreset() {
        let config = J2KXSConfiguration.preview
        XCTAssertEqual(config.profile, .main)
        XCTAssertEqual(config.level, .sublevel1)
        XCTAssertEqual(config.sliceHeight, .height32)
        XCTAssertEqual(config.targetBitsPerPixel, 3.0, accuracy: 1e-9)
    }

    func testProductionPreset() {
        let config = J2KXSConfiguration.production
        XCTAssertEqual(config.profile, .high)
        XCTAssertEqual(config.level, .sublevel2)
        XCTAssertEqual(config.sliceHeight, .height32)
        XCTAssertEqual(config.targetBitsPerPixel, 6.0, accuracy: 1e-9)
    }

    func testConfigurationBitRateClamped() {
        let config = J2KXSConfiguration(
            profile: .main,
            level: .sublevel0,
            sliceHeight: .height16,
            targetBitsPerPixel: -1.0
        )
        XCTAssertGreaterThan(config.targetBitsPerPixel, 0.0)
    }

    func testConfigurationEquality() {
        let a = J2KXSConfiguration.preview
        let b = J2KXSConfiguration(
            profile: .main, level: .sublevel1, sliceHeight: .height32, targetBitsPerPixel: 3.0
        )
        XCTAssertEqual(a, b)
    }

    // MARK: - J2KXSCapabilities

    func testCurrentCapabilitiesNotAvailable() {
        let caps = J2KXSCapabilities.current
        XCTAssertFalse(caps.isAvailable)
    }

    func testCurrentCapabilitiesVersion() {
        let caps = J2KXSCapabilities.current
        XCTAssertTrue(caps.version.contains("exploration"))
        XCTAssertTrue(caps.version.contains("2.2.0"))
    }

    func testCurrentCapabilitiesSupportedProfiles() {
        let caps = J2KXSCapabilities.current
        XCTAssertFalse(caps.supportedProfiles.isEmpty)
        XCTAssertTrue(caps.supportedProfiles.contains(.light))
        XCTAssertTrue(caps.supportedProfiles.contains(.main))
    }

    func testCapabilitiesCustomInit() {
        let caps = J2KXSCapabilities(
            isAvailable: true,
            supportedProfiles: [.light, .main, .high],
            version: "1.0.0"
        )
        XCTAssertTrue(caps.isAvailable)
        XCTAssertEqual(caps.supportedProfiles.count, 3)
        XCTAssertEqual(caps.version, "1.0.0")
    }
}
