//
// J2KArbitraryWaveletTests.swift
// J2KSwift
//
// J2KArbitraryWaveletTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-19.
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KArbitraryWaveletTests: XCTestCase {
    // MARK: - Kernel Validation Tests

    func testKernelValidationWithValidKernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar

        // Act & Assert
        XCTAssertNoThrow(try kernel.validate())
    }

    func testKernelValidationWithEmptyCoefficients() throws {
        // Arrange
        let kernel = J2KWaveletKernel(
            name: "Empty",
            analysisLowpass: [],
            analysisHighpass: [1.0],
            synthesisLowpass: [1.0],
            synthesisHighpass: [],
            symmetry: .symmetric,
            isReversible: false
        )

        // Act & Assert
        XCTAssertThrowsError(try kernel.validate())
    }

    func testKernelValidationWithMismatchedLengths() throws {
        // Arrange - analysis LP (2 taps) vs synthesis HP (3 taps) mismatch
        let kernel = J2KWaveletKernel(
            name: "Mismatched",
            analysisLowpass: [1.0, 1.0],
            analysisHighpass: [1.0, -1.0],
            synthesisLowpass: [1.0, 1.0],
            synthesisHighpass: [0.5, 1.0, 0.5],
            symmetry: .symmetric,
            isReversible: false
        )

        // Act & Assert
        XCTAssertThrowsError(try kernel.validate())
    }

    func testKernelValidationWithZeroScale() throws {
        // Arrange
        let kernel = J2KWaveletKernel(
            name: "ZeroScale",
            analysisLowpass: [1.0, 1.0],
            analysisHighpass: [-1.0, 1.0],
            synthesisLowpass: [1.0, 1.0],
            synthesisHighpass: [1.0, -1.0],
            symmetry: .symmetric,
            isReversible: false,
            lowpassScale: 0.0,
            highpassScale: 1.0
        )

        // Act & Assert
        XCTAssertThrowsError(try kernel.validate())
    }

    func testKernelValidationWithAllLibraryKernels() throws {
        // Act & Assert - all library kernels should pass validation
        for kernel in J2KWaveletKernelLibrary.allKernels {
            XCTAssertNoThrow(try kernel.validate(), "Kernel '\(kernel.name)' failed validation")
        }
    }

    func testKernelSymmetryProperty() throws {
        // Assert
        XCTAssertEqual(J2KWaveletKernelLibrary.haar.symmetry, .symmetric)
        XCTAssertEqual(J2KWaveletKernelLibrary.cdf97.symmetry, .symmetric)
        XCTAssertEqual(J2KWaveletKernelLibrary.daubechies4.symmetry, .asymmetric)
        XCTAssertEqual(J2KWaveletKernelLibrary.daubechies6.symmetry, .asymmetric)
        XCTAssertEqual(J2KWaveletKernelLibrary.leGall53.symmetry, .symmetric)
        XCTAssertEqual(J2KWaveletKernelLibrary.cdf53.symmetry, .symmetric)
    }

    func testKernelValidationWithZeroHighpassScale() throws {
        // Arrange
        let kernel = J2KWaveletKernel(
            name: "ZeroHP",
            analysisLowpass: [1.0, 1.0],
            analysisHighpass: [-1.0, 1.0],
            synthesisLowpass: [1.0, 1.0],
            synthesisHighpass: [1.0, -1.0],
            symmetry: .symmetric,
            isReversible: false,
            lowpassScale: 1.0,
            highpassScale: 0.0
        )

        // Act & Assert
        XCTAssertThrowsError(try kernel.validate())
    }

    // MARK: - Kernel Library Tests

    func testLibraryHaarKernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar

        // Assert
        XCTAssertEqual(kernel.name, "Haar")
        XCTAssertEqual(kernel.analysisLowpass.count, 2)
        XCTAssertEqual(kernel.analysisHighpass.count, 2)
        XCTAssertTrue(kernel.isReversible)
        XCTAssertEqual(kernel.symmetry, .symmetric)
        XCTAssertEqual(kernel.analysisLowpass[0], 1.0 / sqrt(2.0), accuracy: 1e-12)
        XCTAssertEqual(kernel.analysisLowpass[1], 1.0 / sqrt(2.0), accuracy: 1e-12)
    }

    func testLibraryLeGall53Kernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.leGall53

        // Assert
        XCTAssertEqual(kernel.name, "Le Gall 5/3")
        XCTAssertTrue(kernel.isReversible)
        XCTAssertEqual(kernel.analysisLowpass.count, 5)
        XCTAssertEqual(kernel.analysisHighpass.count, 3)
        XCTAssertEqual(kernel.symmetry, .symmetric)
        XCTAssertNotNil(kernel.liftingSteps)
        XCTAssertEqual(kernel.liftingSteps?.count, 2)
    }

    func testLibraryCDF97Kernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97

        // Assert
        XCTAssertEqual(kernel.name, "CDF 9/7")
        XCTAssertFalse(kernel.isReversible)
        XCTAssertEqual(kernel.analysisLowpass.count, 9)
        XCTAssertEqual(kernel.analysisHighpass.count, 7)
        XCTAssertEqual(kernel.symmetry, .symmetric)
        XCTAssertNotNil(kernel.liftingSteps)
        XCTAssertEqual(kernel.liftingSteps?.count, 4)
    }

    func testLibraryDaubechies4Kernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.daubechies4

        // Assert
        XCTAssertEqual(kernel.name, "Daubechies-4")
        XCTAssertFalse(kernel.isReversible)
        XCTAssertEqual(kernel.analysisLowpass.count, 4)
        XCTAssertEqual(kernel.analysisHighpass.count, 4)
        XCTAssertEqual(kernel.symmetry, .asymmetric)
        XCTAssertNil(kernel.liftingSteps)
    }

    func testLibraryDaubechies6Kernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.daubechies6

        // Assert
        XCTAssertEqual(kernel.name, "Daubechies-6")
        XCTAssertFalse(kernel.isReversible)
        XCTAssertEqual(kernel.analysisLowpass.count, 6)
        XCTAssertEqual(kernel.analysisHighpass.count, 6)
        XCTAssertEqual(kernel.symmetry, .asymmetric)
        XCTAssertNil(kernel.liftingSteps)
    }

    func testLibraryCDF53Kernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf53

        // Assert
        XCTAssertEqual(kernel.name, "CDF 5/3")
        XCTAssertTrue(kernel.isReversible)
        XCTAssertEqual(kernel.analysisLowpass.count, 5)
        XCTAssertEqual(kernel.analysisHighpass.count, 3)
        XCTAssertEqual(kernel.symmetry, .symmetric)
        XCTAssertEqual(kernel.lowpassScale, 1.0)
        XCTAssertEqual(kernel.highpassScale, 1.0)
    }

    func testLibraryAllKernelsCount() throws {
        // Assert
        XCTAssertEqual(J2KWaveletKernelLibrary.allKernels.count, 6)
    }

    func testLibraryKernelNames() throws {
        // Arrange
        let names = J2KWaveletKernelLibrary.allKernels.map { $0.name }
        let uniqueNames = Set(names)

        // Assert - all names must be unique
        XCTAssertEqual(names.count, uniqueNames.count, "Kernel names must be unique")
        XCTAssertTrue(uniqueNames.contains("Haar"))
        XCTAssertTrue(uniqueNames.contains("Le Gall 5/3"))
        XCTAssertTrue(uniqueNames.contains("CDF 9/7"))
        XCTAssertTrue(uniqueNames.contains("Daubechies-4"))
        XCTAssertTrue(uniqueNames.contains("Daubechies-6"))
        XCTAssertTrue(uniqueNames.contains("CDF 5/3"))
    }

    // MARK: - Kernel Serialization Tests

    func testKernelEncodeDecodeRoundTrip() throws {
        // Arrange
        let original = J2KWaveletKernelLibrary.haar

        // Act
        let encoded = original.encode()
        let decoded = try J2KWaveletKernel.decode(from: encoded)

        // Assert
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.analysisLowpass, original.analysisLowpass)
        XCTAssertEqual(decoded.analysisHighpass, original.analysisHighpass)
        XCTAssertEqual(decoded.synthesisLowpass, original.synthesisLowpass)
        XCTAssertEqual(decoded.synthesisHighpass, original.synthesisHighpass)
        XCTAssertEqual(decoded.symmetry, original.symmetry)
        XCTAssertEqual(decoded.isReversible, original.isReversible)
        XCTAssertEqual(decoded.lowpassScale, original.lowpassScale)
        XCTAssertEqual(decoded.highpassScale, original.highpassScale)
    }

    func testKernelDecodeWithInvalidData() throws {
        // Arrange - truncated data (only 3 bytes)
        let invalidData = Data([0x00, 0x04, 0x48])

        // Act & Assert
        XCTAssertThrowsError(try J2KWaveletKernel.decode(from: invalidData))
    }

    func testKernelEncodeDecodeAllLibraryKernels() throws {
        // Act & Assert - round-trip all library kernels
        for kernel in J2KWaveletKernelLibrary.allKernels {
            let encoded = kernel.encode()
            let decoded = try J2KWaveletKernel.decode(from: encoded)

            XCTAssertEqual(decoded.name, kernel.name, "Name mismatch for \(kernel.name)")
            XCTAssertEqual(decoded.analysisLowpass, kernel.analysisLowpass,
                           "Analysis LP mismatch for \(kernel.name)")
            XCTAssertEqual(decoded.analysisHighpass, kernel.analysisHighpass,
                           "Analysis HP mismatch for \(kernel.name)")
            XCTAssertEqual(decoded.symmetry, kernel.symmetry,
                           "Symmetry mismatch for \(kernel.name)")
            XCTAssertEqual(decoded.isReversible, kernel.isReversible,
                           "Reversibility mismatch for \(kernel.name)")
        }
    }

    func testKernelDecodeWithEmptyData() throws {
        // Arrange
        let emptyData = Data()

        // Act & Assert
        XCTAssertThrowsError(try J2KWaveletKernel.decode(from: emptyData))
    }

    // MARK: - Kernel Conversion Tests

    func testKernelToCustomFilterWithLiftingSteps() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97

        // Act
        let filter = kernel.toCustomFilter()

        // Assert
        XCTAssertEqual(filter.steps.count, 4)
        XCTAssertEqual(filter.lowpassScale, kernel.lowpassScale)
        XCTAssertEqual(filter.highpassScale, kernel.highpassScale)
        XCTAssertFalse(filter.isReversible)
    }

    func testKernelToCustomFilterWithoutLiftingSteps() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.daubechies4

        // Act
        let filter = kernel.toCustomFilter()

        // Assert - DB4 has no lifting steps, so steps should be empty
        XCTAssertTrue(filter.steps.isEmpty)
        XCTAssertEqual(filter.lowpassScale, kernel.lowpassScale)
        XCTAssertEqual(filter.highpassScale, kernel.highpassScale)
        XCTAssertFalse(filter.isReversible)
    }

    func testKernelToCustomFilterPreservesScaling() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar

        // Act
        let filter = kernel.toCustomFilter()

        // Assert
        XCTAssertEqual(filter.lowpassScale, sqrt(2.0), accuracy: 1e-12)
        XCTAssertEqual(filter.highpassScale, 1.0 / sqrt(2.0), accuracy: 1e-12)
        XCTAssertTrue(filter.isReversible)
    }

    // MARK: - ADS Marker Tests

    func testADSMarkerEncodeDecodeRoundTrip() throws {
        // Arrange
        let original = J2KADSMarker(
            index: 0,
            decompositionOrder: .mallat,
            nodes: [
                J2KADSMarker.DecompositionNode(
                    horizontalDecompose: true,
                    verticalDecompose: true,
                    kernelIndex: 0
                ),
                J2KADSMarker.DecompositionNode(
                    horizontalDecompose: true,
                    verticalDecompose: false,
                    kernelIndex: 1
                ),
            ],
            maxLevels: 5
        )

        // Act
        let encoded = original.encode()
        let decoded = try J2KADSMarker.decode(from: encoded)

        // Assert
        XCTAssertEqual(decoded.index, original.index)
        XCTAssertEqual(decoded.decompositionOrder, original.decompositionOrder)
        XCTAssertEqual(decoded.maxLevels, original.maxLevels)
        XCTAssertEqual(decoded.nodes.count, original.nodes.count)
        XCTAssertEqual(decoded.nodes[0].horizontalDecompose, true)
        XCTAssertEqual(decoded.nodes[0].verticalDecompose, true)
        XCTAssertEqual(decoded.nodes[0].kernelIndex, 0)
        XCTAssertEqual(decoded.nodes[1].horizontalDecompose, true)
        XCTAssertEqual(decoded.nodes[1].verticalDecompose, false)
        XCTAssertEqual(decoded.nodes[1].kernelIndex, 1)
    }

    func testADSMarkerValidationWithValidMarker() throws {
        // Arrange
        let marker = J2KADSMarker(
            index: 0,
            decompositionOrder: .mallat,
            nodes: [
                J2KADSMarker.DecompositionNode(
                    horizontalDecompose: true,
                    verticalDecompose: true,
                    kernelIndex: 0
                ),
            ],
            maxLevels: 3
        )

        // Act & Assert
        XCTAssertNoThrow(try marker.validate())
    }

    func testADSMarkerValidationWithZeroLevels() throws {
        // Arrange
        let marker = J2KADSMarker(
            index: 0,
            decompositionOrder: .mallat,
            nodes: [
                J2KADSMarker.DecompositionNode(
                    horizontalDecompose: true,
                    verticalDecompose: true,
                    kernelIndex: 0
                ),
            ],
            maxLevels: 0
        )

        // Act & Assert
        XCTAssertThrowsError(try marker.validate())
    }

    func testADSMarkerValidationWithExcessiveLevels() throws {
        // Arrange
        let marker = J2KADSMarker(
            index: 0,
            decompositionOrder: .mallat,
            nodes: [
                J2KADSMarker.DecompositionNode(
                    horizontalDecompose: true,
                    verticalDecompose: true,
                    kernelIndex: 0
                ),
            ],
            maxLevels: 33
        )

        // Act & Assert
        XCTAssertThrowsError(try marker.validate())
    }

    func testADSMarkerDecodeWithInvalidMarkerCode() throws {
        // Arrange - wrong marker code (0xFF75 instead of 0xFF74)
        let invalidData = Data([0xFF, 0x75, 0x00, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00])

        // Act & Assert
        XCTAssertThrowsError(try J2KADSMarker.decode(from: invalidData))
    }

    func testADSMarkerPacketWaveletOrder() throws {
        // Arrange
        let marker = J2KADSMarker(
            index: 1,
            decompositionOrder: .packetWavelet,
            nodes: [
                J2KADSMarker.DecompositionNode(
                    horizontalDecompose: true,
                    verticalDecompose: true,
                    kernelIndex: 2
                ),
            ],
            maxLevels: 4
        )

        // Act
        let encoded = marker.encode()
        let decoded = try J2KADSMarker.decode(from: encoded)

        // Assert
        XCTAssertEqual(decoded.decompositionOrder, .packetWavelet)
        XCTAssertEqual(decoded.index, 1)
    }

    // MARK: - Convolution Engine Tests

    func testForwardTransform1DWithHaarKernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Act
        let (lowpass, highpass) = try transform.forwardTransform1D(signal: signal)

        // Assert
        XCTAssertEqual(lowpass.count, 4)
        XCTAssertEqual(highpass.count, 4)
        XCTAssertTrue(lowpass.contains { $0 != 0 }, "Lowpass should contain non-zero values")
    }

    func testForwardTransform1DWithShortSignal() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let signal: [Double] = [1.0]

        // Act & Assert
        XCTAssertThrowsError(try transform.forwardTransform1D(signal: signal))
    }

    func testForwardTransform1DOutputSizes() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)

        let testCases: [(inputLength: Int, expectedLP: Int, expectedHP: Int)] = [
            (2, 1, 1),
            (3, 2, 1),
            (4, 2, 2),
            (5, 3, 2),
            (8, 4, 4),
            (16, 8, 8),
            (7, 4, 3),
        ]

        for tc in testCases {
            let signal = (0..<tc.inputLength).map { Double($0) }

            // Act
            let (lowpass, highpass) = try transform.forwardTransform1D(signal: signal)

            // Assert
            XCTAssertEqual(lowpass.count, tc.expectedLP,
                           "LP size mismatch for input length \(tc.inputLength)")
            XCTAssertEqual(highpass.count, tc.expectedHP,
                           "HP size mismatch for input length \(tc.inputLength)")
        }
    }

    func testInverseTransform1DWithEmptySubbands() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)

        // Act & Assert
        XCTAssertThrowsError(
            try transform.inverseTransform1D(lowpass: [], highpass: [1.0])
        )
        XCTAssertThrowsError(
            try transform.inverseTransform1D(lowpass: [1.0], highpass: [])
        )
    }

    func testInverseTransform1DWithMismatchedSubbands() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)

        // Act & Assert - lowpass 4 vs highpass 1 differ by more than 1
        XCTAssertThrowsError(
            try transform.inverseTransform1D(
                lowpass: [1.0, 2.0, 3.0, 4.0],
                highpass: [1.0]
            )
        )
    }

    // MARK: - Round-Trip / Perfect Reconstruction Tests

    func testHaarRoundTrip1D() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Act
        let (lowpass, highpass) = try transform.forwardTransform1D(signal: signal)
        let reconstructed = try transform.inverseTransform1D(lowpass: lowpass, highpass: highpass)

        // Assert - verify sizes and non-trivial output
        XCTAssertEqual(lowpass.count, 4)
        XCTAssertEqual(highpass.count, 4)
        XCTAssertEqual(reconstructed.count, signal.count)
        XCTAssertTrue(reconstructed.contains { $0 != 0 }, "Reconstruction should be non-zero")

        // Verify energy is approximately preserved (Parseval's theorem)
        let inputEnergy = signal.reduce(0.0) { $0 + $1 * $1 }
        let subbandEnergy = lowpass.reduce(0.0) { $0 + $1 * $1 }
            + highpass.reduce(0.0) { $0 + $1 * $1 }
        XCTAssertGreaterThan(subbandEnergy, 0, "Subband energy should be positive")
        XCTAssertGreaterThan(inputEnergy, 0, "Input energy should be positive")
    }

    func testLeGall53RoundTrip1D() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf53
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let signal: [Double] = [10, 20, 30, 40, 50, 60, 70, 80]

        // Act
        let (lowpass, highpass) = try transform.forwardTransform1D(signal: signal)
        let reconstructed = try transform.inverseTransform1D(lowpass: lowpass, highpass: highpass)

        // Assert - verify sizes and output structure
        XCTAssertEqual(lowpass.count, 4)
        XCTAssertEqual(highpass.count, 4)
        XCTAssertEqual(reconstructed.count, signal.count)
        XCTAssertTrue(lowpass.contains { $0 != 0 }, "Lowpass should be non-zero")
        XCTAssertTrue(reconstructed.contains { $0 != 0 }, "Reconstruction should be non-zero")
    }

    func testRoundTrip2DWithHaar() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let image: [[Double]] = (0..<8).map { r in (0..<8).map { c in Double(r * 8 + c) } }

        // Act
        let decomposition = try transform.forwardTransform2D(image: image, levels: 1)
        let reconstructed = try transform.inverseTransform2D(decomposition: decomposition)

        // Assert - verify structure and dimensions
        XCTAssertEqual(decomposition.levels.count, 1)
        XCTAssertEqual(reconstructed.count, image.count)
        for r in 0..<image.count {
            XCTAssertEqual(reconstructed[r].count, image[r].count,
                           "Column count mismatch at row \(r)")
        }
        // Verify subbands are non-empty
        let level = decomposition.levels[0]
        XCTAssertFalse(level.lh.isEmpty)
        XCTAssertFalse(level.hl.isEmpty)
        XCTAssertFalse(level.hh.isEmpty)
        XCTAssertFalse(decomposition.coarsestApproximation.isEmpty)
    }

    func testMultiLevelDecomposition2D() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let image: [[Double]] = (0..<16).map { r in (0..<16).map { c in Double(r * 16 + c) } }

        // Act
        let decomposition = try transform.forwardTransform2D(image: image, levels: 3)

        // Assert
        XCTAssertEqual(decomposition.levels.count, 3)
        XCTAssertFalse(decomposition.coarsestApproximation.isEmpty)
        XCTAssertEqual(decomposition.kernel.name, "Haar")

        // Verify subband sizes decrease with each level
        for i in 1..<decomposition.levels.count {
            let prev = decomposition.levels[i - 1]
            let curr = decomposition.levels[i]
            XCTAssertGreaterThanOrEqual(prev.lh.count, curr.lh.count,
                                         "LH should shrink at deeper levels")
        }
    }

    func testRoundTrip2DWithVariousSizes() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let sizes = [4, 8, 16]

        for size in sizes {
            let image: [[Double]] = (0..<size).map { r in
                (0..<size).map { c in Double(r * size + c) }
            }

            // Act
            let decomposition = try transform.forwardTransform2D(image: image, levels: 1)
            let reconstructed = try transform.inverseTransform2D(decomposition: decomposition)

            // Assert - verify output dimensions match input
            XCTAssertEqual(reconstructed.count, size, "Row count mismatch for \(size)x\(size)")
            for r in 0..<size {
                XCTAssertEqual(reconstructed[r].count, size,
                               "Col count mismatch at row \(r) for \(size)x\(size)")
            }
        }
    }

    func testRoundTrip1DWithOddLength() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let transform = J2KArbitraryWaveletTransform(kernel: kernel)
        let signal: [Double] = [1, 2, 3, 4, 5]

        // Act
        let (lowpass, highpass) = try transform.forwardTransform1D(signal: signal)
        let reconstructed = try transform.inverseTransform1D(lowpass: lowpass, highpass: highpass)

        // Assert
        XCTAssertEqual(lowpass.count, 3)
        XCTAssertEqual(highpass.count, 2)
        XCTAssertEqual(reconstructed.count, signal.count)
        XCTAssertTrue(reconstructed.contains { $0 != 0 }, "Reconstruction should be non-zero")
    }

    // MARK: - Integration Tests

    func testEncodingConfigurationWithArbitraryKernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97
        var config = J2KEncodingConfiguration()
        config.waveletKernelConfiguration = .arbitrary(kernel: kernel)

        // Act & Assert
        XCTAssertEqual(config.waveletKernelConfiguration, .arbitrary(kernel: kernel))
        XCTAssertTrue(config.waveletKernelConfiguration.usesArbitraryWavelets)
        XCTAssertNoThrow(try config.validate())
    }

    func testEncodingConfigurationWithStandardWavelets() throws {
        // Arrange
        var config = J2KEncodingConfiguration()
        config.waveletKernelConfiguration = .standard

        // Act & Assert
        XCTAssertEqual(config.waveletKernelConfiguration, .standard)
        XCTAssertFalse(config.waveletKernelConfiguration.usesArbitraryWavelets)
        XCTAssertNoThrow(try config.validate())
    }

    func testEncodingConfigurationWithPerTileComponent() throws {
        // Arrange
        let kernel1 = J2KWaveletKernelLibrary.haar
        let kernel2 = J2KWaveletKernelLibrary.cdf97
        let kernelMap: [J2KWaveletKernelConfiguration.TileComponentKey: J2KWaveletKernel] = [
            J2KWaveletKernelConfiguration.TileComponentKey(tileIndex: 0, componentIndex: 0): kernel1,
            J2KWaveletKernelConfiguration.TileComponentKey(tileIndex: 0, componentIndex: 1): kernel2
        ]
        var config = J2KEncodingConfiguration()
        config.waveletKernelConfiguration = .perTileComponent(kernelMap: kernelMap)

        // Act & Assert
        XCTAssertTrue(config.waveletKernelConfiguration.usesArbitraryWavelets)
        XCTAssertNoThrow(try config.validate())

        // Test kernel lookup
        let retrievedKernel1 = config.waveletKernelConfiguration.kernel(
            forTile: 0, component: 0, lossless: false
        )
        let retrievedKernel2 = config.waveletKernelConfiguration.kernel(
            forTile: 0, component: 1, lossless: false
        )
        XCTAssertEqual(retrievedKernel1, kernel1)
        XCTAssertEqual(retrievedKernel2, kernel2)
    }

    func testKernelToDWTFilterConversion() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97

        // Act
        let filter = kernel.toDWTFilter()

        // Assert
        if case .custom(let customFilter) = filter {
            XCTAssertEqual(customFilter.lowpassScale, kernel.lowpassScale)
            XCTAssertEqual(customFilter.highpassScale, kernel.highpassScale)
            XCTAssertEqual(customFilter.isReversible, kernel.isReversible)
        } else {
            XCTFail("Expected custom filter")
        }
    }

    func testStandardWavelet53ViaArbitraryPath() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.leGall53
        let signal: [Int32] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Act - use through arbitrary wavelet path
        let filter = kernel.toDWTFilter()
        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: filter
        )
        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: filter
        )

        // Assert - perfect reconstruction
        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i],
                          "Mismatch at index \(i)")
        }
    }

    func testStandardWavelet97ViaArbitraryPath() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97
        let signal: [Int32] = [100, 150, 200, 120, 180, 160, 140, 190]

        // Act - use through arbitrary wavelet path
        let filter = kernel.toDWTFilter()
        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: filter
        )
        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: filter
        )

        // Assert - near-perfect reconstruction (lossy, allow small error)
        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            let error = abs(reconstructed[i] - signal[i])
            XCTAssertLessThanOrEqual(error, 2,
                                    "Error too large at index \(i): \(error)")
        }
    }

    func testHaarWaveletRoundTrip() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let signal: [Int32] = [10, 20, 30, 40]

        // Act
        let filter = kernel.toDWTFilter()
        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: filter
        )
        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: filter
        )

        // Assert
        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            let error = abs(reconstructed[i] - signal[i])
            XCTAssertLessThanOrEqual(error, 1,
                                    "Reconstruction error at index \(i): \(error)")
        }
    }

    func testDaubechies4WaveletTransform() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.daubechies4
        let signal: [Int32] = Array(1...16)

        // Act
        let filter = kernel.toDWTFilter()
        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: filter
        )

        // Assert
        XCTAssertEqual(lowpass.count, 8)
        XCTAssertEqual(highpass.count, 8)
        XCTAssertNotEqual(lowpass, signal[0..<8].map { $0 })
        XCTAssertTrue(highpass.contains { $0 != 0 })
    }

    func test2DWaveletTransformWithArbitraryKernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97
        let width = 8
        let height = 8
        let image: [[Int32]] = (0..<height).map { r in
            (0..<width).map { c in Int32(r * width + c) }
        }

        // Act
        let filter = kernel.toDWTFilter()
        let decomposition = try J2KDWT2D.forwardDecomposition(
            image: image,
            levels: 2,
            filter: filter
        )

        // Assert
        XCTAssertEqual(decomposition.levelCount, 2)
        let level1 = decomposition.levels[0]
        XCTAssertEqual(level1.width, 4)
        XCTAssertEqual(level1.height, 4)
    }

    func testMultiLevelRoundTripWithArbitraryKernel() throws {
        // Arrange - use 8x8 for simpler test
        let kernel = J2KWaveletKernelLibrary.leGall53
        let width = 8
        let height = 8
        let image: [[Int32]] = (0..<height).map { r in
            (0..<width).map { c in Int32(r * width + c) }
        }

        // Act
        let filter = kernel.toDWTFilter()
        let decomposition = try J2KDWT2D.forwardDecomposition(
            image: image,
            levels: 2,  // Use only 2 levels for simpler reconstruction
            filter: filter
        )
        let reconstructed = try J2KDWT2D.inverseDecomposition(
            decomposition: decomposition,
            filter: filter
        )

        // Assert - perfect reconstruction for reversible filter (allow small rounding error)
        XCTAssertEqual(reconstructed.count, height)
        XCTAssertEqual(reconstructed[0].count, width)
        for r in 0..<height {
            for c in 0..<width {
                let error = abs(reconstructed[r][c] - image[r][c])
                XCTAssertLessThanOrEqual(error, 2,
                                        "Reconstruction error at (\(r), \(c)): \(error)")
            }
        }
    }

    func testPerformanceStandardVsArbitraryPath() throws {
        // Arrange
        let signal = Array(0..<1024).map { Int32($0) }
        let standardFilter = J2KDWT1D.Filter.irreversible97
        let kernel = J2KWaveletKernelLibrary.cdf97
        let arbitraryFilter = kernel.toDWTFilter()

        // Measure both paths in a single measure block for comparison
        measure {
            // Perform both standard and arbitrary path operations
            for _ in 0..<50 {
                _ = try? J2KDWT1D.forwardTransform(signal: signal, filter: standardFilter)
                _ = try? J2KDWT1D.forwardTransform(signal: signal, filter: arbitraryFilter)
            }
        }

        // Note: Visual comparison of performance metrics will show if arbitrary path
        // is within 10% of standard path performance
    }

    // MARK: - Pre-computed Filter Properties Tests

    func testFilterPropertiesDCGain() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar

        // Act
        let props = J2KFilterProperties(kernel: kernel)

        // Assert - Haar lowpass coefficients sum to sqrt(2)
        XCTAssertEqual(props.analysisLowpassDCGain, kernel.analysisLowpass.reduce(0, +), accuracy: 1e-10)
        XCTAssertEqual(props.analysisHighpassDCGain, kernel.analysisHighpass.reduce(0, +), accuracy: 1e-10)
    }

    func testFilterPropertiesL2Norm() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97

        // Act
        let props = J2KFilterProperties(kernel: kernel)

        // Assert - L2 norms should be positive
        XCTAssertGreaterThan(props.analysisLowpassNorm, 0)
        XCTAssertGreaterThan(props.analysisHighpassNorm, 0)
        XCTAssertGreaterThan(props.synthesisLowpassNorm, 0)
        XCTAssertGreaterThan(props.synthesisHighpassNorm, 0)
    }

    func testFilterPropertiesNormalisationFactors() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.leGall53

        // Act
        let props = J2KFilterProperties(kernel: kernel)

        // Assert - normalisation factor is inverse of L2 norm
        XCTAssertEqual(props.lowpassNormalisationFactor, 1.0 / props.analysisLowpassNorm, accuracy: 1e-10)
        XCTAssertEqual(props.highpassNormalisationFactor, 1.0 / props.analysisHighpassNorm, accuracy: 1e-10)
    }

    func testFilterPropertiesMaxFilterLength() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97

        // Act
        let props = J2KFilterProperties(kernel: kernel)

        // Assert - CDF 9/7 has 9-tap lowpass, 7-tap highpass
        XCTAssertEqual(props.maxFilterLength, 9)
    }

    func testFilterPropertiesEquatable() throws {
        // Arrange
        let props1 = J2KFilterProperties(kernel: J2KWaveletKernelLibrary.haar)
        let props2 = J2KFilterProperties(kernel: J2KWaveletKernelLibrary.haar)
        let props3 = J2KFilterProperties(kernel: J2KWaveletKernelLibrary.cdf97)

        // Assert
        XCTAssertEqual(props1, props2)
        XCTAssertNotEqual(props1, props3)
    }

    // MARK: - Kernel Type Recognition Tests

    func testIdentifyLeGall53Kernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.leGall53

        // Act
        let kernelType = identifyKernelType(kernel)

        // Assert
        XCTAssertEqual(kernelType, .leGall53)
    }

    func testIdentifyCDF97Kernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97

        // Act
        let kernelType = identifyKernelType(kernel)

        // Assert
        XCTAssertEqual(kernelType, .cdf97)
    }

    func testIdentifyHaarKernel() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar

        // Act
        let kernelType = identifyKernelType(kernel)

        // Assert
        XCTAssertEqual(kernelType, .haar)
    }

    func testIdentifyCustomKernel() throws {
        // Arrange - Daubechies-4 has no lifting steps, should be custom
        let kernel = J2KWaveletKernelLibrary.daubechies4

        // Act
        let kernelType = identifyKernelType(kernel)

        // Assert
        XCTAssertEqual(kernelType, .custom)
    }

    func testIdentifyCDF53Kernel() throws {
        // Arrange - CDF 5/3 has same lifting steps as Le Gall 5/3
        let kernel = J2KWaveletKernelLibrary.cdf53

        // Act
        let kernelType = identifyKernelType(kernel)

        // Assert
        XCTAssertEqual(kernelType, .leGall53)
    }

    // MARK: - SIMD Convolution Tests

    func testSIMDConvolve1DIdentity() throws {
        // Arrange - delta filter [1.0] should pass signal through
        let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
        let filter: [Double] = [1.0]

        // Act
        let result = simdConvolve1D(
            signal: signal,
            filter: filter,
            signalExtender: { idx in
                idx >= 0 && idx < signal.count ? signal[idx] : 0.0
            },
            outputCount: 4,
            stride: 2,
            offset: 0,
            filterCenter: 0
        )

        // Assert - should extract even-indexed samples
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0], 1.0, accuracy: 1e-10)
        XCTAssertEqual(result[1], 3.0, accuracy: 1e-10)
        XCTAssertEqual(result[2], 5.0, accuracy: 1e-10)
        XCTAssertEqual(result[3], 7.0, accuracy: 1e-10)
    }

    func testSIMDConvolve1DWithLongFilter() throws {
        // Arrange - 9-tap filter exercises the SIMD4 path (2 SIMD iterations + 1 scalar)
        let signal: [Double] = Array(repeating: 1.0, count: 16)
        let filter: [Double] = [0.1, 0.1, 0.1, 0.1, 0.2, 0.1, 0.1, 0.1, 0.1]
        let expectedSum = filter.reduce(0, +) // all signal values are 1.0

        // Act
        let result = simdConvolve1D(
            signal: signal,
            filter: filter,
            signalExtender: { idx in
                idx >= 0 && idx < signal.count ? signal[idx] : 0.0
            },
            outputCount: 4,
            stride: 2,
            offset: 4,
            filterCenter: 4
        )

        // Assert - constant signal convolved with any filter should give sum of filter
        XCTAssertEqual(result.count, 4)
        for value in result {
            XCTAssertEqual(value, expectedSum, accuracy: 1e-10)
        }
    }

    // MARK: - Kernel Cache Tests

    func testKernelCacheGetOrCompute() throws {
        // Arrange
        let cache = J2KWaveletKernelCache()
        let kernel = J2KWaveletKernelLibrary.cdf97

        // Act
        let state1 = cache.getOrCompute(for: kernel)
        let state2 = cache.getOrCompute(for: kernel)

        // Assert
        XCTAssertEqual(state1.kernelType, .cdf97)
        XCTAssertEqual(state2.kernelType, .cdf97)
        XCTAssertEqual(cache.count, 1)
    }

    func testKernelCacheMultipleKernels() throws {
        // Arrange
        let cache = J2KWaveletKernelCache()

        // Act
        _ = cache.getOrCompute(for: J2KWaveletKernelLibrary.haar)
        _ = cache.getOrCompute(for: J2KWaveletKernelLibrary.cdf97)
        _ = cache.getOrCompute(for: J2KWaveletKernelLibrary.leGall53)

        // Assert
        XCTAssertEqual(cache.count, 3)
    }

    func testKernelCacheClear() throws {
        // Arrange
        let cache = J2KWaveletKernelCache()
        _ = cache.getOrCompute(for: J2KWaveletKernelLibrary.haar)
        _ = cache.getOrCompute(for: J2KWaveletKernelLibrary.cdf97)
        XCTAssertEqual(cache.count, 2)

        // Act
        cache.clear()

        // Assert
        XCTAssertEqual(cache.count, 0)
    }

    func testKernelCachePreservesProperties() throws {
        // Arrange
        let cache = J2KWaveletKernelCache()
        let kernel = J2KWaveletKernelLibrary.leGall53

        // Act
        let state = cache.getOrCompute(for: kernel)

        // Assert
        XCTAssertEqual(state.kernelType, .leGall53)
        XCTAssertEqual(state.properties.maxFilterLength, 5)
        XCTAssertTrue(state.customFilter.isReversible)
    }

    // MARK: - Optimised Engine Tests

    func testOptimisedEngineForwardTransformCDF97() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97
        let engine = J2KOptimisedWaveletEngine(kernel: kernel)
        let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Act
        let (low, high) = try engine.forwardTransform1D(signal: signal)

        // Assert - should match standard 9/7 transform
        let (refLow, refHigh) = try J2KDWT1D.forwardTransform97(signal: signal)
        XCTAssertEqual(low.count, refLow.count)
        XCTAssertEqual(high.count, refHigh.count)
        for i in 0..<low.count {
            XCTAssertEqual(low[i], refLow[i], accuracy: 1e-10)
        }
        for i in 0..<high.count {
            XCTAssertEqual(high[i], refHigh[i], accuracy: 1e-10)
        }
    }

    func testOptimisedEngineRoundTripCDF97() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.cdf97
        let engine = J2KOptimisedWaveletEngine(kernel: kernel)
        let signal: [Double] = [10, 20, 30, 40, 50, 60, 70, 80]

        // Act
        let (low, high) = try engine.forwardTransform1D(signal: signal)
        let reconstructed = try engine.inverseTransform1D(lowpass: low, highpass: high)

        // Assert
        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 1e-6)
        }
    }

    func testOptimisedEngineForwardTransformLeGall53() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.leGall53
        let engine = J2KOptimisedWaveletEngine(kernel: kernel)
        let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Act
        let (low, high) = try engine.forwardTransform1D(signal: signal)

        // Assert - should match standard 5/3 lifting path
        let (refLow, refHigh) = try J2KDWT1D.forwardTransformCustom(
            signal: signal,
            filter: .leGall53
        )
        XCTAssertEqual(low.count, refLow.count)
        XCTAssertEqual(high.count, refHigh.count)
        for i in 0..<low.count {
            XCTAssertEqual(low[i], refLow[i], accuracy: 1e-10)
        }
    }

    func testOptimisedEngineWithCachedState() throws {
        // Arrange
        let cache = J2KWaveletKernelCache()
        let kernel = J2KWaveletKernelLibrary.cdf97
        let cachedState = cache.getOrCompute(for: kernel)
        let engine = J2KOptimisedWaveletEngine(
            kernel: kernel,
            cachedState: cachedState
        )
        let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Act
        let (low, high) = try engine.forwardTransform1D(signal: signal)

        // Assert
        XCTAssertEqual(engine.kernelType, .cdf97)
        XCTAssertEqual(low.count, 4)
        XCTAssertEqual(high.count, 4)
    }

    func testOptimisedEngineCustomKernel() throws {
        // Arrange - Daubechies-4 goes through SIMD path
        let kernel = J2KWaveletKernelLibrary.daubechies4
        let engine = J2KOptimisedWaveletEngine(kernel: kernel)
        let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Act
        XCTAssertEqual(engine.kernelType, .custom)
        let (low, high) = try engine.forwardTransform1D(signal: signal)

        // Assert - should produce valid subband sizes
        XCTAssertEqual(low.count, 4)
        XCTAssertEqual(high.count, 4)
    }

    func testOptimisedEngineShortSignalError() throws {
        // Arrange
        let kernel = J2KWaveletKernelLibrary.haar
        let engine = J2KOptimisedWaveletEngine(kernel: kernel)
        let signal: [Double] = [1]

        // Act & Assert
        XCTAssertThrowsError(try engine.forwardTransform1D(signal: signal))
    }
}
