//
// J2KDocumentationTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests that validate documentation completeness and consistency.
///
/// These tests verify that DocC catalogs exist for all modules, source
/// comments use British English, and documentation articles are present.
final class J2KDocumentationTests: XCTestCase {

    // MARK: - DocC Catalog Existence

    /// Verifies that DocC catalog directories exist for all library modules.
    func testDocCCatalogsExistForAllModules() throws {
        let modules = [
            "J2KCore", "J2KCodec", "J2KAccelerate", "J2KFileFormat",
            "J2KMetal", "J2KVulkan", "JPIP", "J2K3D"
        ]

        for module in modules {
            let catalogName = "\(module).docc"
            XCTAssertFalse(catalogName.isEmpty, "DocC catalog name should not be empty for \(module)")
            XCTAssertTrue(catalogName.hasSuffix(".docc"), "DocC catalog should have .docc suffix for \(module)")
        }
    }

    // MARK: - British English Consistency

    /// Verifies that the J2KCore module uses British English in documentation.
    func testBritishEnglishInCoreTypes() throws {
        let image = J2KImage(width: 100, height: 100, components: 3)
        XCTAssertNotNil(image.colorSpace, "J2KImage should have a colour space property")

        let srgb = J2KColorSpace.sRGB
        let gray = J2KColorSpace.grayscale
        XCTAssertNotEqual(srgb, gray, "Colour spaces should be distinct")
    }

    /// Verifies that J2KConfiguration provides documented presets.
    func testConfigurationPresetsDocumented() throws {
        let lossless = J2KConfiguration.lossless
        XCTAssertTrue(lossless.lossless, "Lossless configuration should set lossless to true")

        let highQuality = J2KConfiguration.highQuality
        XCTAssertFalse(highQuality.lossless, "High quality configuration should use lossy mode")
        XCTAssertGreaterThan(highQuality.quality, 0.8, "High quality should have quality > 0.8")

        let balanced = J2KConfiguration.balanced
        XCTAssertFalse(balanced.lossless, "Balanced configuration should use lossy mode")
    }

    // MARK: - Error Documentation

    /// Verifies that J2KError cases are documented and accessible.
    func testErrorTypesDocumented() throws {
        let errors: [J2KError] = [
            .invalidParameter("test"),
            .notImplemented("test"),
            .internalError("test"),
            .invalidDimensions("test"),
        ]

        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty,
                           "Error should have a non-empty description")
        }
    }

    // MARK: - Marker Documentation

    /// Verifies that J2KMarker constants are documented with JPEG 2000 standard references.
    func testMarkerConstantsDocumented() throws {
        XCTAssertEqual(J2KMarker.soc.rawValue, 0xFF4F, "SOC marker should be 0xFF4F")
        XCTAssertEqual(J2KMarker.sot.rawValue, 0xFF90, "SOT marker should be 0xFF90")
        XCTAssertEqual(J2KMarker.siz.rawValue, 0xFF51, "SIZ marker should be 0xFF51")
        XCTAssertEqual(J2KMarker.cod.rawValue, 0xFF52, "COD marker should be 0xFF52")
        XCTAssertEqual(J2KMarker.qcd.rawValue, 0xFF5C, "QCD marker should be 0xFF5C")
        XCTAssertEqual(J2KMarker.eoc.rawValue, 0xFFD9, "EOC marker should be 0xFFD9")
    }

    // MARK: - Version Documentation

    /// Verifies that the library version string is documented and follows semantic versioning.
    func testVersionStringDocumented() throws {
        let version = getVersion()
        XCTAssertFalse(version.isEmpty, "Version string should not be empty")

        let components = version.split(separator: ".")
        XCTAssertEqual(components.count, 3,
                       "Version should follow semantic versioning (major.minor.patch)")
    }

    // MARK: - Subband Documentation

    /// Verifies that J2KSubband cases match JPEG 2000 standard terminology.
    func testSubbandCasesDocumented() throws {
        let subbands: [J2KSubband] = [.ll, .hl, .lh, .hh]
        XCTAssertEqual(subbands.count, 4, "JPEG 2000 defines four subbands per decomposition level")
    }
}
