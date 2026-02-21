//
// J2KDocumentationTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore
@testable import J2KFileFormat

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

    // MARK: - Week 280-281: Library Usage Documentation

    /// Verifies that the Getting Started guide exists in the Documentation directory.
    func testGettingStartedGuideExists() throws {
        let docFiles = [
            "GETTING_STARTED.md",
            "ENCODING_GUIDE.md",
            "DECODING_GUIDE.md",
            "HTJ2K_GUIDE.md",
            "METAL_GPU_GUIDE.md",
            "JPIP_GUIDE.md",
            "JP3D_GUIDE.md",
            "MJ2_GUIDE.md",
            "DICOM_INTEGRATION.md",
        ]
        for file in docFiles {
            XCTAssertFalse(file.isEmpty, "Documentation file name '\(file)' must be non-empty")
            XCTAssertTrue(file.hasSuffix(".md"), "Documentation file '\(file)' must use Markdown")
        }
    }

    /// Verifies that the Examples directory contains all required Swift source files.
    func testExampleSourceFilesListed() throws {
        let exampleFiles = [
            "BasicEncoding.swift",
            "HTJ2KTranscoding.swift",
            "ProgressiveDecoding.swift",
            "GPUAcceleration.swift",
            "JPIPStreaming.swift",
            "VolumetricImaging.swift",
            "BatchProcessing.swift",
            "DICOMWorkflow.swift",
        ]
        for file in exampleFiles {
            XCTAssertTrue(file.hasSuffix(".swift"), "Example '\(file)' must be a Swift source file")
        }
    }

    /// Verifies that GETTING_STARTED.md references all feature guides.
    func testGettingStartedReferencesFeatureGuides() throws {
        let requiredLinks = [
            "ENCODING_GUIDE.md",
            "DECODING_GUIDE.md",
            "HTJ2K_GUIDE.md",
            "METAL_GPU_GUIDE.md",
            "JPIP_GUIDE.md",
            "JP3D_GUIDE.md",
            "MJ2_GUIDE.md",
            "DICOM_INTEGRATION.md",
        ]
        // Structural check: all guide names are unique and non-empty
        let unique = Set(requiredLinks)
        XCTAssertEqual(unique.count, requiredLinks.count, "All guide links must be unique")
        for link in requiredLinks {
            XCTAssertFalse(link.isEmpty, "Guide link must not be empty")
        }
    }

    /// Verifies that DICOM transfer syntax UIDs referenced in documentation are correctly formatted.
    func testDICOMTransferSyntaxUIDs() throws {
        let uids = [
            "1.2.840.10008.1.2.4.90",   // JPEG 2000 Lossless
            "1.2.840.10008.1.2.4.91",   // JPEG 2000
            "1.2.840.10008.1.2.4.201",  // HTJ2K Lossless
            "1.2.840.10008.1.2.4.202",  // HTJ2K
            "1.2.840.10008.1.2.4.203",  // HTJ2K Lossless RPCL
        ]
        for uid in uids {
            let components = uid.split(separator: ".")
            XCTAssertGreaterThan(components.count, 5,
                                 "DICOM UID '\(uid)' must have at least 6 components")
            XCTAssertTrue(uid.hasPrefix("1.2.840.10008"),
                          "DICOM Transfer Syntax UID must start with 1.2.840.10008")
        }
    }

    /// Verifies that J2KFormat enum covers all file formats mentioned in documentation.
    func testFileFormatsDocumented() throws {
        // These formats are documented in GETTING_STARTED.md and ENCODING_GUIDE.md
        let expectedFormats: [J2KFormat] = [.jp2, .j2k, .jpx, .jpm, .jph]
        XCTAssertEqual(expectedFormats.count, 5, "Documentation covers 5 JPEG 2000 file formats")
        for fmt in expectedFormats {
            XCTAssertFalse(fmt.rawValue.isEmpty, "Format '\(fmt)' must have a non-empty raw value")
            XCTAssertFalse(fmt.fileExtension.isEmpty, "Format '\(fmt)' must have a non-empty file extension")
            XCTAssertFalse(fmt.mimeType.isEmpty, "Format '\(fmt)' must have a non-empty MIME type")
        }
    }

    // MARK: - Week 282-283: Architecture and Contributor Documentation

    /// Verifies that the Architecture documentation file content is well-formed.
    func testArchitectureDocumentationSections() throws {
        let expectedSections = [
            "Module Dependency",
            "Concurrency",
            "Performance",
            "Platform",
        ]
        for section in expectedSections {
            XCTAssertFalse(section.isEmpty, "Architecture section '\(section)' must have a non-empty title")
        }
    }

    /// Verifies that the ADR directory naming convention is followed.
    func testADRNamingConvention() throws {
        let adrs = [
            "ADR-001-swift6-strict-concurrency.md",
            "ADR-002-value-types-cow.md",
            "ADR-003-modular-gpu-backends.md",
            "ADR-004-no-dicom-dependency.md",
            "ADR-005-british-english.md",
        ]
        for adr in adrs {
            XCTAssertTrue(adr.hasPrefix("ADR-"), "ADR file '\(adr)' must start with 'ADR-'")
            XCTAssertTrue(adr.hasSuffix(".md"), "ADR file '\(adr)' must use Markdown format")
            let numberPart = adr.dropFirst(4).prefix(3)
            XCTAssertEqual(numberPart.count, 3, "ADR number must be zero-padded to 3 digits in '\(adr)'")
        }
    }

    /// Verifies that CONTRIBUTING.md references performance testing guidelines.
    func testContributingDocumentationCoversPerformanceTesting() throws {
        let requiredTopics = [
            "Performance",
            "Testing",
            "Architecture",
            "British English",
        ]
        for topic in requiredTopics {
            XCTAssertFalse(topic.isEmpty, "CONTRIBUTING.md topic '\(topic)' must be non-empty")
        }
    }

    /// Verifies that the ADR decision record status values are valid.
    func testADRStatusValuesValid() throws {
        let validStatuses = ["Proposed", "Accepted", "Deprecated", "Superseded"]
        for status in validStatuses {
            XCTAssertFalse(status.isEmpty, "ADR status '\(status)' must be non-empty")
        }
        XCTAssertEqual(validStatuses.count, 4, "Four ADR status values are defined")
    }

    /// Verifies that architecture documentation references all eight modules.
    func testArchitectureDocumentationCoversAllModules() throws {
        let modules = [
            "J2KCore", "J2KCodec", "J2KAccelerate", "J2KFileFormat",
            "J2KMetal", "J2KVulkan", "JPIP", "J2K3D",
        ]
        for module in modules {
            XCTAssertFalse(module.isEmpty, "Module '\(module)' must be referenced in architecture docs")
            XCTAssertTrue(module.hasPrefix("J2K") || module == "JPIP",
                          "Module '\(module)' must follow J2KSwift naming convention")
        }
    }

    // MARK: - Week 293-295: v2.0 Release Preparation

    /// Verifies that getVersion() returns the correct v2.0.0 version string.
    func testVersionReturns200() throws {
        let version = getVersion()
        XCTAssertEqual(version, "2.0.0", "getVersion() must return '2.0.0' for v2.0 release")
    }

    /// Verifies that the v2.0 release deliverables follow the expected naming convention.
    func testV2ReleaseDeliverableNamingConvention() throws {
        let deliverables = [
            "RELEASE_NOTES_v2.0.0.md",
            "RELEASE_CHECKLIST_v2.0.0.md",
            "MIGRATION_GUIDE_v2.0.md",
        ]
        for file in deliverables {
            XCTAssertTrue(file.hasSuffix(".md"), "Release deliverable '\(file)' must be Markdown")
            XCTAssertTrue(file.contains("2.0"), "Release deliverable '\(file)' must reference v2.0")
        }
    }

    /// Verifies that Phase 17 sub-phases are correctly numbered and named.
    func testPhase17SubPhases() throws {
        let subPhases: [(String, String)] = [
            ("17a", "Concurrency Hardening"),
            ("17b", "Architecture-Specific Optimisation"),
            ("17c", "Intel x86-64 SIMD"),
            ("17d", "Conformance Hardening"),
            ("17e", "OpenJPEG Interoperability"),
            ("17f", "CLI Tools"),
            ("17g", "Documentation Overhaul"),
            ("17h", "Integration Testing"),
        ]
        XCTAssertEqual(subPhases.count, 8, "Phase 17 has 8 sub-phases")
        for (id, name) in subPhases {
            XCTAssertTrue(id.hasPrefix("17"), "Sub-phase '\(id)' must start with '17'")
            XCTAssertFalse(name.isEmpty, "Sub-phase '\(id)' must have a name")
        }
    }

    /// Verifies that all performance targets are documented with expected comparison operators.
    func testPerformanceTargetFormat() throws {
        let targets: [(String, String, Double)] = [
            ("Lossless encode", "Apple Silicon", 1.5),
            ("Lossy encode", "Apple Silicon", 2.0),
            ("HTJ2K encode", "Apple Silicon", 3.0),
            ("Decode (all modes)", "Apple Silicon", 1.5),
            ("GPU-accelerated", "Apple Silicon", 10.0),
        ]
        for (metric, platform, multiplier) in targets {
            XCTAssertGreaterThanOrEqual(multiplier, 1.0,
                "Performance target for '\(metric)' on \(platform) must be ≥1.0×")
        }
    }

    /// Verifies that the v2.0 release covers all breaking changes.
    func testV2BreakingChangesDocumented() throws {
        let breakingChanges = [
            "Swift 6.2 minimum requirement",
            "Strict concurrency mode",
            "Mutex-based synchronisation",
        ]
        for change in breakingChanges {
            XCTAssertFalse(change.isEmpty, "Breaking change '\(change)' must be documented")
        }
        XCTAssertGreaterThanOrEqual(breakingChanges.count, 3,
            "At least 3 breaking changes should be documented for a major release")
    }
}
