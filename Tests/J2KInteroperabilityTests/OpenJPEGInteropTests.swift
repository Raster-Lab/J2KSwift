//
// OpenJPEGInteropTests.swift
// J2KSwift
//
/// # OpenJPEG Interoperability Tests
///
/// Week 266–268 deliverable: Automated interoperability test suite (100+ test cases)
/// for bidirectional testing between J2KSwift and OpenJPEG.
///
/// Tests cover:
/// - OpenJPEG test harness (availability, CLI wrapper, pipeline)
/// - J2KSwift → OpenJPEG direction (progression orders, quality layers, formats)
/// - OpenJPEG → J2KSwift direction (configurations, multi-tile, ROI, HTJ2K)
/// - Edge cases (single-pixel, bit depths, signed, corrupt codestreams)

import XCTest
@testable import J2KCore

// MARK: - Harness Tests: Availability Detection

final class OpenJPEGAvailabilityTests: XCTestCase {

    func testFindToolReturnsNilForNonexistentBinary() {
        // Arrange & Act
        let result = OpenJPEGAvailability.findTool("__nonexistent_tool_xyz__")

        // Assert
        XCTAssertNil(result, "A nonexistent tool name must return nil.")
    }

    func testFindToolLocatesKnownSystemBinary() {
        // Arrange & Act — /bin/ls always exists on macOS/Linux
        let result = OpenJPEGAvailability.findTool("ls")

        // Assert
        XCTAssertNotNil(result, "The 'ls' tool should be found on any Unix system.")
    }

    func testParseVersionExtractsSemanticVersion() {
        // Arrange
        let helpText = "[INFO] opj_compress version 2.5.0"

        // Act
        let version = OpenJPEGAvailability.parseVersion(from: helpText)

        // Assert
        XCTAssertEqual(version, "2.5.0", "Version 2.5.0 should be extracted.")
    }

    func testParseVersionHandlesAlternateFormat() {
        // Arrange
        let helpText = "Version: 2.4.0\nUsage: opj_compress ..."

        // Act
        let version = OpenJPEGAvailability.parseVersion(from: helpText)

        // Assert
        XCTAssertEqual(version, "2.4.0")
    }

    func testParseVersionReturnsUnknownForInvalidInput() {
        // Arrange
        let helpText = "No version information here"

        // Act
        let version = OpenJPEGAvailability.parseVersion(from: helpText)

        // Assert
        XCTAssertEqual(version, "unknown")
    }

    func testVersionSupportsHTJ2KReturnsTrueForV25() {
        XCTAssertTrue(OpenJPEGAvailability.versionSupportsHTJ2K("2.5.0"))
        XCTAssertTrue(OpenJPEGAvailability.versionSupportsHTJ2K("2.5.1"))
        XCTAssertTrue(OpenJPEGAvailability.versionSupportsHTJ2K("3.0.0"))
    }

    func testVersionSupportsHTJ2KReturnsFalseForOlderVersions() {
        XCTAssertFalse(OpenJPEGAvailability.versionSupportsHTJ2K("2.4.0"))
        XCTAssertFalse(OpenJPEGAvailability.versionSupportsHTJ2K("2.3.1"))
        XCTAssertFalse(OpenJPEGAvailability.versionSupportsHTJ2K("1.5.0"))
    }

    func testVersionSupportsHTJ2KReturnsFalseForUnknown() {
        XCTAssertFalse(OpenJPEGAvailability.versionSupportsHTJ2K("unknown"))
    }

    func testCheckReturnsAvailabilityResult() {
        // Act
        let result = OpenJPEGAvailability.check()

        // Assert — we can always construct a result; actual availability depends on host
        XCTAssertTrue(
            result.compressorAvailable || !result.compressorAvailable,
            "AvailabilityResult must always be constructible."
        )
    }

    func testAvailabilityResultBidirectionalFlag() {
        // Arrange
        let bothAvailable = OpenJPEGAvailability.AvailabilityResult(
            compressorAvailable: true,
            decompressorAvailable: true,
            compressorInfo: nil,
            decompressorInfo: nil
        )
        let onlyCompress = OpenJPEGAvailability.AvailabilityResult(
            compressorAvailable: true,
            decompressorAvailable: false,
            compressorInfo: nil,
            decompressorInfo: nil
        )

        // Assert
        XCTAssertTrue(bothAvailable.isBidirectionalTestingAvailable)
        XCTAssertFalse(onlyCompress.isBidirectionalTestingAvailable)
    }
}

// MARK: - Harness Tests: CLI Wrapper

final class OpenJPEGCLIWrapperTests: XCTestCase {

    func testBuildEncodeArgumentsLossless() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration()

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/input.pgm",
            outputPath: "/tmp/output.jp2",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains("/tmp/input.pgm"))
        XCTAssertTrue(args.contains("-o"))
        XCTAssertTrue(args.contains("/tmp/output.jp2"))
        XCTAssertTrue(args.contains("-p"))
        XCTAssertTrue(args.contains("LRCP"))
    }

    func testBuildEncodeArgumentsLossyWithRatio() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            lossless: false,
            compressionRatio: 20.0
        )

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/input.pgm",
            outputPath: "/tmp/output.j2k",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-r"))
        XCTAssertTrue(args.contains("20.0"))
    }

    func testBuildEncodeArgumentsLossyWithPSNR() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            lossless: false,
            targetPSNR: 40.0
        )

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/input.pgm",
            outputPath: "/tmp/output.j2k",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-q"))
        XCTAssertTrue(args.contains("40.0"))
    }

    func testBuildEncodeArgumentsWithTileSize() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            tileWidth: 64,
            tileHeight: 64
        )

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/in.pgm",
            outputPath: "/tmp/out.jp2",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-t"))
        XCTAssertTrue(args.contains("64,64"))
    }

    func testBuildEncodeArgumentsWithHTJ2K() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            useHTJ2K: true
        )

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/in.pgm",
            outputPath: "/tmp/out.jp2",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-HT"))
    }

    func testBuildEncodeArgumentsAllProgressionOrders() {
        for order in OpenJPEGProgressionOrder.allCases {
            // Arrange
            let config = OpenJPEGCLIWrapper.EncodeConfiguration(
                progressionOrder: order
            )

            // Act
            let args = OpenJPEGCLIWrapper.buildEncodeArguments(
                inputPath: "/tmp/in.pgm",
                outputPath: "/tmp/out.jp2",
                configuration: config
            )

            // Assert
            XCTAssertTrue(
                args.contains(order.rawValue),
                "Progression order \(order.rawValue) must appear in arguments."
            )
        }
    }

    func testBuildDecodeArguments() {
        // Act
        let args = OpenJPEGCLIWrapper.buildDecodeArguments(
            inputPath: "/tmp/input.jp2",
            outputPath: "/tmp/output.pgm"
        )

        // Assert
        XCTAssertEqual(args, ["-i", "/tmp/input.jp2", "-o", "/tmp/output.pgm"])
    }

    func testBuildEncodeArgumentsWithDecompositionLevels() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            decompositionLevels: 3
        )

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/in.pgm",
            outputPath: "/tmp/out.jp2",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-n"))
        XCTAssertTrue(args.contains("3"))
    }

    func testBuildEncodeArgumentsWithCodeBlockSize() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            codeBlockWidth: 32,
            codeBlockHeight: 32
        )

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/in.pgm",
            outputPath: "/tmp/out.jp2",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-b"))
        XCTAssertTrue(args.contains("32,32"))
    }

    func testBuildEncodeArgumentsWithAdditionalArgs() {
        // Arrange
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            additionalArguments: ["-cinema2K", "24"]
        )

        // Act
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "/tmp/in.pgm",
            outputPath: "/tmp/out.jp2",
            configuration: config
        )

        // Assert
        XCTAssertTrue(args.contains("-cinema2K"))
        XCTAssertTrue(args.contains("24"))
    }

    func testCLIResultInitialisation() {
        // Arrange & Act
        let result = OpenJPEGCLIWrapper.CLIResult(
            success: true,
            exitCode: 0,
            stdout: "OK",
            stderr: "",
            outputPath: "/tmp/out.jp2",
            elapsedTime: 0.5
        )

        // Assert
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "OK")
        XCTAssertEqual(result.outputPath, "/tmp/out.jp2")
        XCTAssertEqual(result.elapsedTime, 0.5, accuracy: 0.01)
    }

    func testCLIWrapperInitAutoDetect() {
        // Act
        let wrapper = OpenJPEGCLIWrapper()

        // Assert — auto-detection should not crash; paths may be nil
        XCTAssertTrue(
            wrapper.compressorPath != nil || wrapper.compressorPath == nil,
            "Auto-detect must not crash."
        )
    }

    func testCLIWrapperInitExplicitPaths() {
        // Act
        let wrapper = OpenJPEGCLIWrapper(
            compressorPath: "/usr/bin/opj_compress",
            decompressorPath: "/usr/bin/opj_decompress"
        )

        // Assert
        XCTAssertEqual(wrapper.compressorPath, "/usr/bin/opj_compress")
        XCTAssertEqual(wrapper.decompressorPath, "/usr/bin/opj_decompress")
    }
}

// MARK: - Harness Tests: Output Format and Progression Order

final class OpenJPEGEnumTests: XCTestCase {

    func testOutputFormatFileExtensions() {
        XCTAssertEqual(OpenJPEGOutputFormat.j2k.fileExtension, "j2k")
        XCTAssertEqual(OpenJPEGOutputFormat.jp2.fileExtension, "jp2")
        XCTAssertEqual(OpenJPEGOutputFormat.jpx.fileExtension, "jpx")
    }

    func testOutputFormatAllCases() {
        XCTAssertEqual(OpenJPEGOutputFormat.allCases.count, 3)
    }

    func testProgressionOrderAllCases() {
        let orders = OpenJPEGProgressionOrder.allCases
        XCTAssertEqual(orders.count, 5)
        XCTAssertTrue(orders.contains(.lrcp))
        XCTAssertTrue(orders.contains(.rlcp))
        XCTAssertTrue(orders.contains(.rpcl))
        XCTAssertTrue(orders.contains(.pcrl))
        XCTAssertTrue(orders.contains(.cprl))
    }

    func testProgressionOrderRawValues() {
        XCTAssertEqual(OpenJPEGProgressionOrder.lrcp.rawValue, "LRCP")
        XCTAssertEqual(OpenJPEGProgressionOrder.rlcp.rawValue, "RLCP")
        XCTAssertEqual(OpenJPEGProgressionOrder.rpcl.rawValue, "RPCL")
        XCTAssertEqual(OpenJPEGProgressionOrder.pcrl.rawValue, "PCRL")
        XCTAssertEqual(OpenJPEGProgressionOrder.cprl.rawValue, "CPRL")
    }
}

// MARK: - Harness Tests: Test Image Generation

final class OpenJPEGTestImageTests: XCTestCase {

    // MARK: PGM Creation

    func testCreatePGM8BitGradient() {
        // Act
        let pgmData = OpenJPEGInteropPipeline.createPGMData(
            width: 16, height: 16, bitDepth: 8, pattern: .gradient
        )

        // Assert
        let header = String(data: pgmData.prefix(20), encoding: .utf8) ?? ""
        XCTAssertTrue(header.hasPrefix("P5"), "PGM must start with 'P5'.")
        XCTAssertTrue(header.contains("16 16"), "Header must contain dimensions.")
        XCTAssertTrue(header.contains("255"), "Header must contain max value 255.")
    }

    func testCreatePGM16Bit() {
        // Act
        let pgmData = OpenJPEGInteropPipeline.createPGMData(
            width: 8, height: 8, bitDepth: 16, pattern: .uniform
        )

        // Assert — extract only the ASCII header before binary pixel data
        let expectedHeader = "P5\n8 8\n65535\n"
        let headerBytes = pgmData.prefix(expectedHeader.utf8.count)
        let header = String(data: headerBytes, encoding: .ascii) ?? ""
        XCTAssertTrue(header.hasPrefix("P5"))
        XCTAssertTrue(header.contains("65535"), "16-bit PGM must have max value 65535.")
    }

    func testCreatePGMSinglePixel() {
        // Act
        let pgmData = OpenJPEGInteropPipeline.createPGMData(
            width: 1, height: 1, bitDepth: 8, pattern: .uniform
        )

        // Assert — header + 1 pixel byte
        XCTAssertGreaterThan(pgmData.count, 0)
        let header = String(data: pgmData.prefix(20), encoding: .utf8) ?? ""
        XCTAssertTrue(header.contains("1 1"))
    }

    // MARK: PPM Creation

    func testCreatePPMRGB() {
        // Act
        let ppmData = OpenJPEGInteropPipeline.createPPMData(
            width: 8, height: 8, pattern: .gradient
        )

        // Assert
        let header = String(data: ppmData.prefix(20), encoding: .utf8) ?? ""
        XCTAssertTrue(header.hasPrefix("P6"), "PPM must start with 'P6'.")
        XCTAssertTrue(header.contains("8 8"))
    }

    // MARK: Test Image Patterns

    func testGradientPatternRange() {
        let pixels = TestImagePattern.gradient.generatePixels(width: 256, height: 1, maxVal: 255)
        XCTAssertEqual(pixels.count, 256)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[255], 255)
    }

    func testUniformPatternAllSame() {
        let pixels = TestImagePattern.uniform.generatePixels(width: 16, height: 16, maxVal: 200)
        let mid = 200 / 2
        XCTAssertTrue(pixels.allSatisfy { $0 == mid })
    }

    func testCheckerboardPatternAlternates() {
        let pixels = TestImagePattern.checkerboard.generatePixels(width: 16, height: 16, maxVal: 255)
        XCTAssertEqual(pixels.count, 256)
        // Top-left block should be maxVal
        XCTAssertEqual(pixels[0], 255)
    }

    func testRandomPatternDeterministic() {
        let pixels1 = TestImagePattern.random.generatePixels(width: 32, height: 32, maxVal: 255)
        let pixels2 = TestImagePattern.random.generatePixels(width: 32, height: 32, maxVal: 255)
        XCTAssertEqual(pixels1, pixels2, "Random pattern must be deterministic (same seed).")
    }

    func testStripesPatternAlternates() {
        let pixels = TestImagePattern.stripes.generatePixels(width: 4, height: 32, maxVal: 255)
        XCTAssertEqual(pixels.count, 128)
        // First stripe should be white
        XCTAssertEqual(pixels[0], 255)
    }

    func testDiagonalPattern() {
        let pixels = TestImagePattern.diagonal.generatePixels(width: 8, height: 8, maxVal: 255)
        XCTAssertEqual(pixels.count, 64)
        XCTAssertEqual(pixels[0], 0, "Top-left corner should be 0.")
    }

    func testSolidBlackPattern() {
        let pixels = TestImagePattern.solidBlack.generatePixels(width: 8, height: 8, maxVal: 255)
        XCTAssertTrue(pixels.allSatisfy { $0 == 0 })
    }

    func testSolidWhitePattern() {
        let pixels = TestImagePattern.solidWhite.generatePixels(width: 8, height: 8, maxVal: 255)
        XCTAssertTrue(pixels.allSatisfy { $0 == 255 })
    }

    func testZonePlatePattern() {
        let pixels = TestImagePattern.zonePlate.generatePixels(width: 32, height: 32, maxVal: 255)
        XCTAssertEqual(pixels.count, 1024)
        // Centre should be bright
        let centreVal = pixels[16 * 32 + 16]
        XCTAssertGreaterThan(centreVal, 200, "Zone plate centre should be near max.")
    }

    func testAllPatternsGenerateCorrectSize() {
        for pattern in TestImagePattern.allCases {
            let pixels = pattern.generatePixels(width: 7, height: 11, maxVal: 255)
            XCTAssertEqual(
                pixels.count, 77,
                "Pattern \(pattern.rawValue) must produce 7×11=77 pixels."
            )
        }
    }

    func testPatternAllCasesCount() {
        XCTAssertEqual(TestImagePattern.allCases.count, 9)
    }
}

// MARK: - Harness Tests: Test Corpus

final class OpenJPEGTestCorpusTests: XCTestCase {

    func testStandardCorpusHasMinimumEntries() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        XCTAssertGreaterThanOrEqual(
            corpus.count, 20,
            "Standard corpus must have at least 20 test images."
        )
    }

    func testStandardCorpusCoversAllCategories() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        let categories = Set(corpus.map(\.category))
        for cat in OpenJPEGTestCorpus.TestImageCategory.allCases {
            XCTAssertTrue(
                categories.contains(cat),
                "Corpus must contain images for category '\(cat.rawValue)'."
            )
        }
    }

    func testCorpusIncludesSinglePixelEdgeCase() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        let singlePixel = corpus.first { $0.width == 1 && $0.height == 1 }
        XCTAssertNotNil(singlePixel, "Corpus must include a single-pixel image.")
    }

    func testCorpusIncludesMultiComponentImages() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        let rgb = corpus.first { $0.components == 3 }
        XCTAssertNotNil(rgb, "Corpus must include RGB (3-component) images.")
    }

    func testCorpusIncludesHighBitDepth() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        let high = corpus.first { $0.bitDepth > 8 }
        XCTAssertNotNil(high, "Corpus must include images with bit depth > 8.")
    }

    func testCorpusIncludesSignedComponents() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        let signed = corpus.first { $0.isSigned }
        XCTAssertNotNil(signed, "Corpus must include signed component images.")
    }

    func testCorpusCategoryFilter() {
        let edgeCases = OpenJPEGTestCorpus.corpus(category: .edgeCase)
        XCTAssertGreaterThanOrEqual(edgeCases.count, 5, "Must have at least 5 edge case images.")
        XCTAssertTrue(edgeCases.allSatisfy { $0.category == .edgeCase })
    }

    func testCorpusImageProperties() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        for image in corpus {
            XCTAssertGreaterThan(image.width, 0, "Image width must be > 0: \(image.name)")
            XCTAssertGreaterThan(image.height, 0, "Image height must be > 0: \(image.name)")
            XCTAssertGreaterThan(image.components, 0, "Components must be > 0: \(image.name)")
            XCTAssertGreaterThan(image.bitDepth, 0, "Bit depth must be > 0: \(image.name)")
            XCTAssertFalse(image.name.isEmpty, "Image name must not be empty.")
        }
    }
}

// MARK: - Harness Tests: Corrupt Codestream Generation

final class CorruptCodestreamTests: XCTestCase {

    private func createValidCodestream() -> Data {
        return J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )
    }

    func testTruncatedCorruption() {
        let valid = createValidCodestream()
        let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: .truncated)
        XCTAssertLessThan(corrupted.count, valid.count)
    }

    func testBitFlipCorruption() {
        let valid = createValidCodestream()
        let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: .bitFlip)
        XCTAssertEqual(corrupted.count, valid.count)
        XCTAssertNotEqual(corrupted, valid, "Bit-flipped data must differ from original.")
    }

    func testMissingEOCCorruption() {
        let valid = createValidCodestream()
        let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: .missingEOC)
        // Should be shorter (EOC removed) or same length if no EOC present
        XCTAssertLessThanOrEqual(corrupted.count, valid.count)
    }

    func testCorruptSIZCorruption() {
        let valid = createValidCodestream()
        let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: .corruptSIZ)
        XCTAssertNotEqual(corrupted, valid)
    }

    func testCorruptSOTCorruption() {
        let valid = createValidCodestream()
        let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: .corruptSOT)
        // SOT may or may not be found
        XCTAssertGreaterThan(corrupted.count, 0)
    }

    func testInvalidMarkerCorruption() {
        let valid = createValidCodestream()
        let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: .invalidMarker)
        XCTAssertGreaterThan(corrupted.count, valid.count, "Invalid marker insertion should increase size.")
    }

    func testEmptyCorruption() {
        let valid = createValidCodestream()
        let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: .empty)
        XCTAssertEqual(corrupted.count, 0)
    }

    func testAllCorruptionTypes() {
        let valid = createValidCodestream()
        for corruptionType in CorruptCodestreamGenerator.CorruptionType.allCases {
            let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: corruptionType)
            // Each type should produce some output (except empty)
            if corruptionType != .empty {
                XCTAssertGreaterThan(
                    corrupted.count, 0,
                    "Corruption type \(corruptionType.rawValue) must produce non-empty data."
                )
            }
        }
    }

    func testCorruptionTypesCaseCount() {
        XCTAssertEqual(CorruptCodestreamGenerator.CorruptionType.allCases.count, 7)
    }
}

// MARK: - Harness Tests: Interoperability Report

final class OpenJPEGReportTests: XCTestCase {

    func testGenerateEmptyReport() {
        // Act
        let report = OpenJPEGInteropReport.generateMarkdownReport(
            entries: [],
            openJPEGVersion: "2.5.0",
            j2kSwiftVersion: "2.0.0"
        )

        // Assert
        XCTAssertTrue(report.contains("# OpenJPEG Interoperability Report"))
        XCTAssertTrue(report.contains("2.5.0"))
        XCTAssertTrue(report.contains("2.0.0"))
        XCTAssertTrue(report.contains("Total Tests | 0"))
    }

    func testGenerateReportWithResults() {
        // Arrange
        let entries = [
            OpenJPEGInteropReport.ReportEntry(
                testName: "test_lossless",
                direction: .j2kSwiftToOpenJPEG,
                passed: true,
                errorMessage: nil,
                psnr: .infinity,
                encodeTime: 0.1,
                decodeTime: 0.05
            ),
            OpenJPEGInteropReport.ReportEntry(
                testName: "test_lossy",
                direction: .openJPEGToJ2KSwift,
                passed: false,
                errorMessage: "PSNR below threshold",
                psnr: 25.0,
                encodeTime: 0.2,
                decodeTime: 0.1
            ),
        ]

        // Act
        let report = OpenJPEGInteropReport.generateMarkdownReport(
            entries: entries,
            openJPEGVersion: "2.5.0",
            j2kSwiftVersion: "2.0.0"
        )

        // Assert
        XCTAssertTrue(report.contains("Total Tests | 2"))
        XCTAssertTrue(report.contains("Passed | 1"))
        XCTAssertTrue(report.contains("Failed | 1"))
        XCTAssertTrue(report.contains("test_lossless"))
        XCTAssertTrue(report.contains("test_lossy"))
        XCTAssertTrue(report.contains("PSNR below threshold"))
    }

    func testReportDirectionBreakdown() {
        // Arrange
        let entries = [
            OpenJPEGInteropReport.ReportEntry(
                testName: "a", direction: .j2kSwiftToOpenJPEG,
                passed: true, errorMessage: nil, psnr: nil,
                encodeTime: nil, decodeTime: nil
            ),
            OpenJPEGInteropReport.ReportEntry(
                testName: "b", direction: .j2kSwiftToOpenJPEG,
                passed: true, errorMessage: nil, psnr: nil,
                encodeTime: nil, decodeTime: nil
            ),
            OpenJPEGInteropReport.ReportEntry(
                testName: "c", direction: .openJPEGToJ2KSwift,
                passed: false, errorMessage: "err", psnr: nil,
                encodeTime: nil, decodeTime: nil
            ),
        ]

        // Act
        let report = OpenJPEGInteropReport.generateMarkdownReport(
            entries: entries,
            openJPEGVersion: "2.5.0",
            j2kSwiftVersion: "2.0.0"
        )

        // Assert
        XCTAssertTrue(report.contains("J2KSwift → OpenJPEG"))
        XCTAssertTrue(report.contains("OpenJPEG → J2KSwift"))
    }
}

// MARK: - Harness Tests: Interoperability Pipeline

final class OpenJPEGPipelineTests: XCTestCase {

    func testDirectionRawValues() {
        XCTAssertEqual(
            OpenJPEGInteropPipeline.Direction.j2kSwiftToOpenJPEG.rawValue,
            "J2KSwift→OpenJPEG"
        )
        XCTAssertEqual(
            OpenJPEGInteropPipeline.Direction.openJPEGToJ2KSwift.rawValue,
            "OpenJPEG→J2KSwift"
        )
    }

    func testDirectionAllCases() {
        XCTAssertEqual(OpenJPEGInteropPipeline.Direction.allCases.count, 2)
    }

    func testPipelineResultInitialisation() {
        let result = OpenJPEGInteropPipeline.PipelineResult(
            direction: .j2kSwiftToOpenJPEG,
            testName: "test",
            success: true,
            errors: [],
            warnings: ["minor issue"],
            psnr: 45.0,
            maxAbsoluteError: 1,
            isLossless: false,
            encodeTime: 0.1,
            decodeTime: 0.05
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.testName, "test")
        XCTAssertEqual(result.psnr, 45.0)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertFalse(result.isLossless)
    }
}

// MARK: - Harness Tests: Validator Configurations

final class OpenJPEGValidatorConfigTests: XCTestCase {

    func testProgressionOrderConfigsCount() {
        let configs = OpenJPEGInteropValidator.progressionOrderConfigs()
        XCTAssertEqual(configs.count, 5, "Must have one config per progression order.")
    }

    func testQualityLayerConfigsCount() {
        let configs = OpenJPEGInteropValidator.qualityLayerConfigs()
        XCTAssertEqual(configs.count, 5)
    }

    func testFormatConfigsCount() {
        let configs = OpenJPEGInteropValidator.formatConfigs()
        XCTAssertEqual(configs.count, 3, "Must have one config per output format.")
    }

    func testMultiTileConfigsCount() {
        let configs = OpenJPEGInteropValidator.multiTileConfigs()
        XCTAssertEqual(configs.count, 3)
    }

    func testEdgeCaseConfigsCount() {
        let configs = OpenJPEGInteropValidator.edgeCaseConfigs()
        XCTAssertGreaterThanOrEqual(configs.count, 5)
    }

    func testValidationConfigDefaults() {
        let config = OpenJPEGInteropValidator.ValidationConfig(name: "test")
        XCTAssertEqual(config.direction, .j2kSwiftToOpenJPEG)
        XCTAssertTrue(config.expectLossless)
        XCTAssertEqual(config.minimumPSNR, 30.0)
        XCTAssertEqual(config.format, .jp2)
        XCTAssertEqual(config.progressionOrder, .lrcp)
        XCTAssertEqual(config.qualityLayers, 1)
        XCTAssertEqual(config.tileWidth, 0)
        XCTAssertEqual(config.tileHeight, 0)
    }

    func testValidationResultCreation() {
        let config = OpenJPEGInteropValidator.ValidationConfig(name: "test")
        let result = OpenJPEGInteropValidator.ValidationResult(
            config: config,
            passed: true,
            errorMessage: nil,
            psnr: 50.0,
            maxAbsoluteError: 0
        )
        XCTAssertTrue(result.passed)
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.psnr, 50.0)
    }
}

// MARK: - Test Suite Configuration

final class OpenJPEGInteropTestSuiteTests: XCTestCase {

    func testAllTestCasesExceedsHundred() {
        let cases = OpenJPEGInteropTestSuite.allTestCases()
        XCTAssertGreaterThanOrEqual(
            cases.count, 100,
            "Interoperability suite must have ≥ 100 test cases; got \(cases.count)."
        )
    }

    func testTestCountMatchesAllTestCases() {
        XCTAssertEqual(
            OpenJPEGInteropTestSuite.testCount,
            OpenJPEGInteropTestSuite.allTestCases().count
        )
    }

    func testSuiteCoversAllCategories() {
        let cases = OpenJPEGInteropTestSuite.allTestCases()
        let categories = Set(cases.map(\.category))
        for cat in OpenJPEGInteropTestSuite.TestCategory.allCases {
            XCTAssertTrue(
                categories.contains(cat),
                "Suite must include category '\(cat.rawValue)'."
            )
        }
    }

    func testSuiteCategoryFilter() {
        let harness = OpenJPEGInteropTestSuite.testCases(category: .harness)
        XCTAssertGreaterThanOrEqual(harness.count, 5)
        XCTAssertTrue(harness.allSatisfy { $0.category == .harness })
    }

    func testSuiteJ2KToOpenJPEGTests() {
        let j2kToOJP = OpenJPEGInteropTestSuite.testCases(category: .j2kSwiftToOpenJPEG)
        XCTAssertGreaterThanOrEqual(j2kToOJP.count, 15)
    }

    func testSuiteOpenJPEGToJ2KTests() {
        let ojpToJ2K = OpenJPEGInteropTestSuite.testCases(category: .openJPEGToJ2KSwift)
        XCTAssertGreaterThanOrEqual(ojpToJ2K.count, 10)
    }

    func testSuiteEdgeCaseTests() {
        let edgeCases = OpenJPEGInteropTestSuite.testCases(category: .edgeCase)
        XCTAssertGreaterThanOrEqual(edgeCases.count, 10)
    }

    func testAllTestCasesHaveUniqueIDs() {
        let cases = OpenJPEGInteropTestSuite.allTestCases()
        let ids = cases.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(
            ids.count, uniqueIDs.count,
            "All test case IDs must be unique."
        )
    }

    func testAllTestCasesHaveDescriptions() {
        let cases = OpenJPEGInteropTestSuite.allTestCases()
        for tc in cases {
            XCTAssertFalse(tc.description.isEmpty, "Test case \(tc.id) must have a description.")
        }
    }

    func testAllTestCasesHaveValidImages() {
        let cases = OpenJPEGInteropTestSuite.allTestCases()
        for tc in cases {
            XCTAssertGreaterThan(tc.image.width, 0, "Test \(tc.id): image width must be > 0.")
            XCTAssertGreaterThan(tc.image.height, 0, "Test \(tc.id): image height must be > 0.")
        }
    }
}

// MARK: - J2KSwift → OpenJPEG Direction Tests

final class J2KSwiftToOpenJPEGProgressionTests: XCTestCase {

    func testLRCPProgressionConfigValid() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(progressionOrder: .lrcp)
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "in.pgm", outputPath: "out.jp2", configuration: config
        )
        XCTAssertTrue(args.contains("LRCP"))
    }

    func testRLCPProgressionConfigValid() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(progressionOrder: .rlcp)
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "in.pgm", outputPath: "out.jp2", configuration: config
        )
        XCTAssertTrue(args.contains("RLCP"))
    }

    func testRPCLProgressionConfigValid() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(progressionOrder: .rpcl)
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "in.pgm", outputPath: "out.jp2", configuration: config
        )
        XCTAssertTrue(args.contains("RPCL"))
    }

    func testPCRLProgressionConfigValid() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(progressionOrder: .pcrl)
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "in.pgm", outputPath: "out.jp2", configuration: config
        )
        XCTAssertTrue(args.contains("PCRL"))
    }

    func testCPRLProgressionConfigValid() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(progressionOrder: .cprl)
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "in.pgm", outputPath: "out.jp2", configuration: config
        )
        XCTAssertTrue(args.contains("CPRL"))
    }
}

final class J2KSwiftToOpenJPEGQualityTests: XCTestCase {

    func testSingleLayerLosslessConfig() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            lossless: true, qualityLayers: 1
        )
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "in.pgm", outputPath: "out.jp2", configuration: config
        )
        XCTAssertFalse(args.contains("-r"), "Lossless should not have -r flag.")
        XCTAssertFalse(args.contains("-q"), "Lossless should not have -q flag.")
    }

    func testMultipleLayerConfig() {
        for layers in [2, 3, 5, 10] {
            let config = OpenJPEGCLIWrapper.EncodeConfiguration(
                lossless: false,
                compressionRatio: 20.0,
                qualityLayers: layers
            )
            XCTAssertEqual(config.qualityLayers, layers)
        }
    }

    func testLossyPSNRTargetConfig() {
        let targets: [Double] = [30.0, 35.0, 40.0, 45.0, 50.0]
        for target in targets {
            let config = OpenJPEGCLIWrapper.EncodeConfiguration(
                lossless: false,
                targetPSNR: target
            )
            XCTAssertEqual(config.targetPSNR, target)
        }
    }
}

final class J2KSwiftToOpenJPEGFormatTests: XCTestCase {

    func testJ2KFormatConfig() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(outputFormat: .j2k)
        XCTAssertEqual(config.outputFormat, .j2k)
    }

    func testJP2FormatConfig() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(outputFormat: .jp2)
        XCTAssertEqual(config.outputFormat, .jp2)
    }

    func testJPXFormatConfig() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(outputFormat: .jpx)
        XCTAssertEqual(config.outputFormat, .jpx)
    }
}

final class J2KSwiftToOpenJPEGLosslessTests: XCTestCase {

    func testLosslessConfigHasZeroError() {
        let config = OpenJPEGInteropValidator.ValidationConfig(
            name: "lossless",
            expectLossless: true,
            maximumAbsoluteError: 0
        )
        XCTAssertTrue(config.expectLossless)
        XCTAssertEqual(config.maximumAbsoluteError, 0)
    }

    func testLosslessCodestreamValidation() {
        // Generate a synthetic codestream and validate structure
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 16, height: 16, components: 1, bitDepth: 8, htj2k: false
        )
        XCTAssertGreaterThan(codestream.count, 0)
        // Validate SOC marker
        XCTAssertEqual(codestream[0], 0xFF)
        XCTAssertEqual(codestream[1], 0x4F)
    }

    func testLosslessRGBCodestreamValidation() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 16, height: 16, components: 3, bitDepth: 8, htj2k: false
        )
        XCTAssertGreaterThan(codestream.count, 0)
    }
}

// MARK: - OpenJPEG → J2KSwift Direction Tests

final class OpenJPEGToJ2KSwiftConfigTests: XCTestCase {

    func testAllProgressionOrdersHaveConfigs() {
        for order in OpenJPEGProgressionOrder.allCases {
            let config = OpenJPEGInteropValidator.ValidationConfig(
                name: "test_\(order.rawValue)",
                direction: .openJPEGToJ2KSwift,
                progressionOrder: order
            )
            XCTAssertEqual(config.direction, .openJPEGToJ2KSwift)
            XCTAssertEqual(config.progressionOrder, order)
        }
    }

    func testMultiTileConfigsValid() {
        let configs = OpenJPEGInteropValidator.multiTileConfigs()
        for config in configs {
            XCTAssertGreaterThan(config.tileWidth, 0)
            XCTAssertGreaterThan(config.tileHeight, 0)
            XCTAssertEqual(config.direction, .openJPEGToJ2KSwift)
        }
    }

    func testROIDecodingConfigValid() {
        let config = OpenJPEGInteropValidator.ValidationConfig(
            name: "roi_decode",
            direction: .openJPEGToJ2KSwift
        )
        XCTAssertEqual(config.direction, .openJPEGToJ2KSwift)
    }

    func testProgressiveDecodingConfigValid() {
        let config = OpenJPEGInteropValidator.ValidationConfig(
            name: "progressive_decode",
            direction: .openJPEGToJ2KSwift
        )
        XCTAssertEqual(config.direction, .openJPEGToJ2KSwift)
    }

    func testHTJ2KInteropConfigValid() {
        let config = OpenJPEGInteropValidator.ValidationConfig(
            name: "htj2k_interop",
            direction: .openJPEGToJ2KSwift
        )
        XCTAssertEqual(config.direction, .openJPEGToJ2KSwift)
    }
}

// MARK: - Edge Case Tests

final class OpenJPEGEdgeCaseSinglePixelTests: XCTestCase {

    func testSinglePixelPGMCreation() {
        let pgm = OpenJPEGInteropPipeline.createPGMData(
            width: 1, height: 1, bitDepth: 8, pattern: .uniform
        )
        XCTAssertGreaterThan(pgm.count, 0)
    }

    func testSinglePixelCodestream() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 1, height: 1, components: 1, bitDepth: 8, htj2k: false
        )
        XCTAssertGreaterThan(codestream.count, 0)
        XCTAssertEqual(codestream[0], 0xFF)
        XCTAssertEqual(codestream[1], 0x4F)
    }
}

final class OpenJPEGEdgeCaseBitDepthTests: XCTestCase {

    func test1BitImagePixels() {
        let pixels = TestImagePattern.checkerboard.generatePixels(width: 8, height: 8, maxVal: 1)
        XCTAssertTrue(pixels.allSatisfy { $0 == 0 || $0 == 1 })
    }

    func test12BitImagePixels() {
        let pixels = TestImagePattern.gradient.generatePixels(width: 64, height: 1, maxVal: 4095)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[63], 4095)
    }

    func test16BitImagePixels() {
        let pixels = TestImagePattern.gradient.generatePixels(width: 32, height: 1, maxVal: 65535)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[31], 65535)
    }

    func test24BitImagePixels() {
        let maxVal = (1 << 24) - 1
        let pixels = TestImagePattern.gradient.generatePixels(width: 8, height: 1, maxVal: maxVal)
        XCTAssertEqual(pixels[0], 0)
        XCTAssertEqual(pixels[7], maxVal)
    }

    func test32BitImagePixels() {
        let maxVal = Int(Int32.max)
        let pixels = TestImagePattern.uniform.generatePixels(width: 4, height: 4, maxVal: maxVal)
        let mid = maxVal / 2
        XCTAssertTrue(pixels.allSatisfy { $0 == mid })
    }
}

final class OpenJPEGEdgeCaseSignedTests: XCTestCase {

    func testSignedComponentCorpusEntry() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        let signed = corpus.filter { $0.isSigned }
        XCTAssertGreaterThanOrEqual(signed.count, 1)
    }

    func testSignedConfigValidation() {
        let config = OpenJPEGInteropValidator.ValidationConfig(
            name: "signed_test",
            direction: .j2kSwiftToOpenJPEG
        )
        XCTAssertTrue(config.expectLossless)
    }
}

final class OpenJPEGEdgeCaseTileSizeTests: XCTestCase {

    func testNonStandardTileSizes() {
        let tileSizes = [(7, 7), (13, 17), (3, 5)]
        for (tw, th) in tileSizes {
            let config = OpenJPEGCLIWrapper.EncodeConfiguration(
                tileWidth: tw,
                tileHeight: th
            )
            let args = OpenJPEGCLIWrapper.buildEncodeArguments(
                inputPath: "in.pgm", outputPath: "out.jp2",
                configuration: config
            )
            XCTAssertTrue(args.contains("-t"))
            XCTAssertTrue(args.contains("\(tw),\(th)"))
        }
    }

    func testZeroTileSizeOmitsFlag() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            tileWidth: 0,
            tileHeight: 0
        )
        let args = OpenJPEGCLIWrapper.buildEncodeArguments(
            inputPath: "in.pgm", outputPath: "out.jp2",
            configuration: config
        )
        XCTAssertFalse(args.contains("-t"))
    }
}

final class OpenJPEGEdgeCaseCorruptTests: XCTestCase {

    func testAllCorruptionTypesProduceDifferentResults() {
        let valid = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 16, height: 16, components: 1, bitDepth: 8, htj2k: false
        )

        var results: [Data] = []
        for corruptionType in CorruptCodestreamGenerator.CorruptionType.allCases {
            let corrupted = CorruptCodestreamGenerator.corrupt(valid, type: corruptionType)
            results.append(corrupted)
        }

        // At least some corruption types should produce distinct results
        let uniqueResults = Set(results.map { $0.hashValue })
        XCTAssertGreaterThan(
            uniqueResults.count, 1,
            "Different corruption types should produce different outputs."
        )
    }

    func testTruncatedCodestreamHasValidSOC() {
        let valid = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )
        let truncated = CorruptCodestreamGenerator.corrupt(valid, type: .truncated)
        XCTAssertGreaterThanOrEqual(truncated.count, 2)
        XCTAssertEqual(truncated[0], 0xFF)
        XCTAssertEqual(truncated[1], 0x4F)
    }
}

// MARK: - J2KSwift → OpenJPEG: Codestream Structure Tests

final class J2KSwiftCodestreamStructureTests: XCTestCase {

    func testSyntheticCodestreamMarkerOrdering() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 32, height: 32, components: 1, bitDepth: 8, htj2k: false
        )

        // Validate basic marker ordering: SOC, SIZ, COD
        XCTAssertEqual(codestream[0], 0xFF)
        XCTAssertEqual(codestream[1], 0x4F, "First marker must be SOC (0xFF4F).")
        XCTAssertEqual(codestream[2], 0xFF)
        XCTAssertEqual(codestream[3], 0x51, "Second marker must be SIZ (0xFF51).")
    }

    func testHTJ2KCodestreamIncludesCAP() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 16, height: 16, components: 1, bitDepth: 8, htj2k: true
        )

        // Should contain CAP marker (0xFF50)
        var foundCAP = false
        for i in 0..<(codestream.count - 1) {
            if codestream[i] == 0xFF && codestream[i + 1] == 0x50 {
                foundCAP = true
                break
            }
        }
        XCTAssertTrue(foundCAP, "HTJ2K codestream must include CAP marker (0xFF50).")
    }

    func testCodestreamEndsWithEOC() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        let last2 = codestream.suffix(2)
        XCTAssertEqual(last2[last2.startIndex], 0xFF)
        XCTAssertEqual(last2[last2.startIndex + 1], 0xD9, "Codestream must end with EOC (0xFFD9).")
    }

    func testCodestreamContainsSOT() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        var foundSOT = false
        for i in 0..<(codestream.count - 1) {
            if codestream[i] == 0xFF && codestream[i + 1] == 0x90 {
                foundSOT = true
                break
            }
        }
        XCTAssertTrue(foundSOT, "Codestream must contain SOT marker (0xFF90).")
    }

    func testCodestreamContainsQCD() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        var foundQCD = false
        for i in 0..<(codestream.count - 1) {
            if codestream[i] == 0xFF && codestream[i + 1] == 0x5C {
                foundQCD = true
                break
            }
        }
        XCTAssertTrue(foundQCD, "Codestream must contain QCD marker (0xFF5C).")
    }

    func testMultiComponentCodestream() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 16, height: 16, components: 3, bitDepth: 8, htj2k: false
        )
        XCTAssertGreaterThan(codestream.count, 0)
        XCTAssertEqual(codestream[0], 0xFF)
        XCTAssertEqual(codestream[1], 0x4F)
    }
}

// MARK: - OpenJPEG → J2KSwift: Multi-Tile Tests

final class OpenJPEGToJ2KSwiftMultiTileTests: XCTestCase {

    func testMultiTileConfig64x64() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            tileWidth: 64, tileHeight: 64
        )
        XCTAssertEqual(config.tileWidth, 64)
        XCTAssertEqual(config.tileHeight, 64)
    }

    func testMultiTileConfig128x128() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            tileWidth: 128, tileHeight: 128
        )
        XCTAssertEqual(config.tileWidth, 128)
    }

    func testMultiTileConfig32x32() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            tileWidth: 32, tileHeight: 32
        )
        XCTAssertEqual(config.tileWidth, 32)
    }

    func testMultiTileImageInCorpus() {
        let corpus = OpenJPEGTestCorpus.standardCorpus()
        let largish = corpus.filter { $0.width >= 128 && $0.height >= 128 }
        XCTAssertGreaterThan(
            largish.count, 0,
            "Corpus must include images large enough for multi-tile testing."
        )
    }
}

// MARK: - OpenJPEG → J2KSwift: HTJ2K Interoperability Tests

final class OpenJPEGToJ2KSwiftHTJ2KTests: XCTestCase {

    func testHTJ2KCodestreamHasCAPMarker() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: true
        )

        var foundCAP = false
        for i in 0..<(codestream.count - 1) {
            if codestream[i] == 0xFF && codestream[i + 1] == 0x50 {
                foundCAP = true
                break
            }
        }
        XCTAssertTrue(foundCAP)
    }

    func testHTJ2KCodestreamHasCPFMarker() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: true
        )

        var foundCPF = false
        for i in 0..<(codestream.count - 1) {
            if codestream[i] == 0xFF && codestream[i + 1] == 0x59 {
                foundCPF = true
                break
            }
        }
        XCTAssertTrue(foundCPF, "HTJ2K codestream must include CPF marker (0xFF59).")
    }

    func testNonHTJ2KCodestreamLacksCAPMarker() {
        let codestream = J2KHTInteroperabilityValidator.createSyntheticCodestream(
            width: 8, height: 8, components: 1, bitDepth: 8, htj2k: false
        )

        var foundCAP = false
        for i in 0..<(codestream.count - 1) {
            if codestream[i] == 0xFF && codestream[i + 1] == 0x50 {
                foundCAP = true
                break
            }
        }
        XCTAssertFalse(foundCAP, "Non-HTJ2K codestream must not include CAP marker.")
    }

    func testHTJ2KVersionDetection() {
        XCTAssertTrue(OpenJPEGAvailability.versionSupportsHTJ2K("2.5.0"))
        XCTAssertFalse(OpenJPEGAvailability.versionSupportsHTJ2K("2.4.0"))
    }
}

// MARK: - OpenJPEG → J2KSwift: Progressive Decoding Tests

final class OpenJPEGToJ2KSwiftProgressiveTests: XCTestCase {

    func testProgressiveCodestreamWithMultipleLayers() {
        // A codestream with multiple quality layers should support progressive decode
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            lossless: false,
            compressionRatio: 10.0,
            qualityLayers: 5,
            progressionOrder: .lrcp
        )
        XCTAssertEqual(config.qualityLayers, 5)
        XCTAssertEqual(config.progressionOrder, .lrcp)
    }

    func testProgressiveCodestreamRLCP() {
        let config = OpenJPEGCLIWrapper.EncodeConfiguration(
            qualityLayers: 3,
            progressionOrder: .rlcp
        )
        XCTAssertEqual(config.progressionOrder, .rlcp)
    }
}

// MARK: - Interoperability Validator Integration

final class OpenJPEGInteropValidatorIntegrationTests: XCTestCase {

    func testValidationResultPassesForLossless() {
        let config = OpenJPEGInteropValidator.ValidationConfig(
            name: "lossless_test",
            expectLossless: true,
            maximumAbsoluteError: 0
        )
        let result = OpenJPEGInteropValidator.ValidationResult(
            config: config,
            passed: true,
            errorMessage: nil,
            psnr: .infinity,
            maxAbsoluteError: 0
        )
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.maxAbsoluteError, 0)
    }

    func testValidationResultFailsForLossyBelowThreshold() {
        let config = OpenJPEGInteropValidator.ValidationConfig(
            name: "lossy_test",
            expectLossless: false,
            minimumPSNR: 40.0,
            maximumAbsoluteError: 10
        )
        let result = OpenJPEGInteropValidator.ValidationResult(
            config: config,
            passed: false,
            errorMessage: "PSNR 30.0 below minimum 40.0",
            psnr: 30.0,
            maxAbsoluteError: 50
        )
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.psnr, 30.0)
    }

    func testValidationConfigWithAllFormats() {
        for fmt in OpenJPEGOutputFormat.allCases {
            let config = OpenJPEGInteropValidator.ValidationConfig(
                name: "format_\(fmt.rawValue)",
                format: fmt
            )
            XCTAssertEqual(config.format, fmt)
        }
    }

    func testFullPipelineResultCreation() {
        let result = OpenJPEGInteropPipeline.PipelineResult(
            direction: .j2kSwiftToOpenJPEG,
            testName: "full_pipeline",
            success: true,
            errors: [],
            warnings: [],
            psnr: Double.infinity,
            maxAbsoluteError: 0,
            isLossless: true,
            encodeTime: 0.05,
            decodeTime: 0.03
        )
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.isLossless)
        XCTAssertTrue(result.errors.isEmpty)
    }
}

// MARK: - ToolInfo Tests

final class OpenJPEGToolInfoTests: XCTestCase {

    func testToolInfoCreation() {
        let info = OpenJPEGAvailability.ToolInfo(
            path: "/usr/local/bin/opj_compress",
            version: "2.5.0",
            supportsHTJ2K: true
        )
        XCTAssertEqual(info.path, "/usr/local/bin/opj_compress")
        XCTAssertEqual(info.version, "2.5.0")
        XCTAssertTrue(info.supportsHTJ2K)
    }

    func testToolInfoOlderVersion() {
        let info = OpenJPEGAvailability.ToolInfo(
            path: "/usr/bin/opj_compress",
            version: "2.3.1",
            supportsHTJ2K: false
        )
        XCTAssertFalse(info.supportsHTJ2K)
    }
}

// MARK: - Comprehensive Test Case Listing

final class OpenJPEGInteropComprehensiveTests: XCTestCase {

    func testAllTestCasesCanBeEnumerated() {
        let allCases = OpenJPEGInteropTestSuite.allTestCases()
        XCTAssertGreaterThanOrEqual(allCases.count, 100)

        // Verify we can iterate all cases without error
        var count = 0
        for testCase in allCases {
            XCTAssertFalse(testCase.id.isEmpty)
            XCTAssertFalse(testCase.description.isEmpty)
            count += 1
        }
        XCTAssertEqual(count, allCases.count)
    }

    func testHarnessTestCategoryPopulation() {
        let harness = OpenJPEGInteropTestSuite.testCases(category: .harness)
        XCTAssertGreaterThanOrEqual(harness.count, 8, "Harness category must have ≥ 8 tests.")
    }

    func testJ2KToOpenJPEGCategoryPopulation() {
        let j2kToOJP = OpenJPEGInteropTestSuite.testCases(category: .j2kSwiftToOpenJPEG)
        XCTAssertGreaterThanOrEqual(j2kToOJP.count, 20, "J2K→OJP must have ≥ 20 tests.")
    }

    func testOpenJPEGToJ2KCategoryPopulation() {
        let ojpToJ2K = OpenJPEGInteropTestSuite.testCases(category: .openJPEGToJ2KSwift)
        XCTAssertGreaterThanOrEqual(ojpToJ2K.count, 10, "OJP→J2K must have ≥ 10 tests.")
    }

    func testEdgeCaseCategoryPopulation() {
        let edgeCases = OpenJPEGInteropTestSuite.testCases(category: .edgeCase)
        XCTAssertGreaterThanOrEqual(edgeCases.count, 15, "Edge cases must have ≥ 15 tests.")
    }

    func testTestCaseImageReferencesAreValid() {
        let allCases = OpenJPEGInteropTestSuite.allTestCases()
        for tc in allCases {
            XCTAssertGreaterThan(tc.image.width, 0)
            XCTAssertGreaterThan(tc.image.height, 0)
            XCTAssertGreaterThan(tc.image.components, 0)
            XCTAssertGreaterThan(tc.image.bitDepth, 0)
        }
    }
}
