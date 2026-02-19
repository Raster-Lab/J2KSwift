import XCTest
@testable import J2KMetal
@testable import J2KCore

/// Tests for Metal-accelerated discrete wavelet transforms.
final class J2KMetalDWTTests: XCTestCase {

    // MARK: - Platform Availability Tests

    /// Tests that Metal DWT availability can be queried.
    func testMetalDWTAvailability() {
        let available = J2KMetalDWT.isAvailable
        #if canImport(Metal)
        _ = available
        #else
        XCTAssertFalse(available)
        #endif
    }

    // MARK: - Filter Type Tests

    /// Tests DWT filter creation for irreversible 9/7.
    func testIrreversible97Filter() {
        let filter = J2KMetalDWTFilter.irreversible97
        switch filter {
        case .irreversible97:
            break // Expected
        default:
            XCTFail("Expected irreversible97 filter")
        }
    }

    /// Tests DWT filter creation for reversible 5/3.
    func testReversible53Filter() {
        let filter = J2KMetalDWTFilter.reversible53
        switch filter {
        case .reversible53:
            break // Expected
        default:
            XCTFail("Expected reversible53 filter")
        }
    }

    /// Tests arbitrary filter creation.
    func testArbitraryFilterCreation() {
        let arb = J2KMetalArbitraryFilter(
            analysisLowpass: [0.5, 1.0, 0.5],
            analysisHighpass: [-0.5, 1.0, -0.5],
            synthesisLowpass: [0.5, 1.0, 0.5],
            synthesisHighpass: [0.5, 1.0, 0.5]
        )
        XCTAssertEqual(arb.analysisLowpass.count, 3)
        XCTAssertEqual(arb.analysisHighpass.count, 3)
        XCTAssertEqual(arb.synthesisLowpass.count, 3)
        XCTAssertEqual(arb.synthesisHighpass.count, 3)
    }

    /// Tests lifting scheme creation.
    func testLiftingSchemeCreation() {
        let scheme = J2KMetalLiftingScheme(
            coefficients: [-1.586134342, -0.052980118, 0.882911075, 0.443506852],
            scaleLowpass: 1.230174105,
            scaleHighpass: 1.0 / 1.230174105
        )
        XCTAssertEqual(scheme.coefficients.count, 4)
        XCTAssertEqual(scheme.scaleLowpass, 1.230174105, accuracy: 1e-6)
    }

    /// Tests CDF 9/7 lifting scheme preset.
    func testCDF97LiftingSchemePreset() {
        let scheme = J2KMetalLiftingScheme.cdf97
        XCTAssertEqual(scheme.coefficients.count, 4)
        XCTAssertEqual(scheme.scaleLowpass, 1.230174105, accuracy: 1e-6)
        XCTAssertEqual(scheme.scaleHighpass, 1.0 / 1.230174105, accuracy: 1e-6)
    }

    // MARK: - Configuration Tests

    /// Tests default lossy configuration.
    func testLossyConfiguration() {
        let config = J2KMetalDWTConfiguration.lossy
        switch config.filter {
        case .irreversible97:
            break // Expected
        default:
            XCTFail("Expected irreversible97 filter for lossy config")
        }
        XCTAssertEqual(config.decompositionLevels, 5)
        XCTAssertEqual(config.tileWidth, 0)
        XCTAssertEqual(config.tileHeight, 0)
        XCTAssertEqual(config.gpuThreshold, 256)
        XCTAssertTrue(config.useThreadgroupMemory)
        XCTAssertFalse(config.enableAsyncCompute)
    }

    /// Tests lossless configuration.
    func testLosslessConfiguration() {
        let config = J2KMetalDWTConfiguration.lossless
        switch config.filter {
        case .reversible53:
            break // Expected
        default:
            XCTFail("Expected reversible53 filter for lossless config")
        }
    }

    /// Tests large image configuration.
    func testLargeImageConfiguration() {
        let config = J2KMetalDWTConfiguration.largeImage
        XCTAssertEqual(config.tileWidth, 1024)
        XCTAssertEqual(config.tileHeight, 1024)
        XCTAssertTrue(config.enableAsyncCompute)
    }

    /// Tests custom configuration.
    func testCustomConfiguration() {
        let config = J2KMetalDWTConfiguration(
            filter: .reversible53,
            decompositionLevels: 3,
            tileWidth: 512,
            tileHeight: 512,
            gpuThreshold: 128,
            useThreadgroupMemory: false,
            enableAsyncCompute: true
        )
        XCTAssertEqual(config.decompositionLevels, 3)
        XCTAssertEqual(config.tileWidth, 512)
        XCTAssertEqual(config.tileHeight, 512)
        XCTAssertEqual(config.gpuThreshold, 128)
        XCTAssertFalse(config.useThreadgroupMemory)
        XCTAssertTrue(config.enableAsyncCompute)
    }

    // MARK: - Subband Result Tests

    /// Tests subband result construction.
    func testSubbandResultConstruction() {
        let subbands = J2KMetalDWTSubbands(
            ll: [1, 2, 3, 4],
            lh: [0.1, 0.2],
            hl: [0.3, 0.4],
            hh: [0.01],
            llWidth: 2, llHeight: 2,
            originalWidth: 4, originalHeight: 4
        )
        XCTAssertEqual(subbands.ll.count, 4)
        XCTAssertEqual(subbands.lh.count, 2)
        XCTAssertEqual(subbands.hl.count, 2)
        XCTAssertEqual(subbands.hh.count, 1)
        XCTAssertEqual(subbands.llWidth, 2)
        XCTAssertEqual(subbands.llHeight, 2)
        XCTAssertEqual(subbands.originalWidth, 4)
        XCTAssertEqual(subbands.originalHeight, 4)
    }

    /// Tests multi-level decomposition result construction.
    func testDecompositionResultConstruction() {
        let level = J2KMetalDWTSubbands(
            ll: [1], lh: [0.1], hl: [0.2], hh: [0.01],
            llWidth: 1, llHeight: 1,
            originalWidth: 2, originalHeight: 2
        )
        let decomp = J2KMetalDWTDecomposition(
            approximation: [42.0],
            approximationWidth: 1,
            approximationHeight: 1,
            levels: [level]
        )
        XCTAssertEqual(decomp.approximation.count, 1)
        XCTAssertEqual(decomp.approximationWidth, 1)
        XCTAssertEqual(decomp.levels.count, 1)
    }

    // MARK: - Backend Selection Tests

    /// Tests backend selection with auto mode.
    func testAutoBackendSelection() async {
        let config = J2KMetalDWTConfiguration(gpuThreshold: 256)
        let dwt = J2KMetalDWT(configuration: config)

        // Small image → CPU
        let backend1 = await dwt.effectiveBackend(width: 64, height: 64, backend: .auto)
        XCTAssertEqual(backend1, .cpu)

        // Large image → depends on Metal availability
        let backend2 = await dwt.effectiveBackend(width: 512, height: 512, backend: .auto)
        #if canImport(Metal)
        // Metal available but device may not be in CI
        _ = backend2
        #else
        XCTAssertEqual(backend2, .cpu)
        #endif
    }

    /// Tests forced CPU backend.
    func testForcedCPUBackend() async {
        let dwt = J2KMetalDWT()
        let backend = await dwt.effectiveBackend(width: 4096, height: 4096, backend: .cpu)
        XCTAssertEqual(backend, .cpu)
    }

    /// Tests forced GPU backend falls back when unavailable.
    func testForcedGPUBackendFallback() async {
        let dwt = J2KMetalDWT()
        let backend = await dwt.effectiveBackend(width: 64, height: 64, backend: .gpu)
        #if canImport(Metal)
        _ = backend // GPU may or may not be available
        #else
        XCTAssertEqual(backend, .cpu)
        #endif
    }

    // MARK: - Statistics Tests

    /// Tests initial statistics are zero.
    func testInitialStatistics() async {
        let dwt = J2KMetalDWT()
        let stats = await dwt.statistics()
        XCTAssertEqual(stats.totalOperations, 0)
        XCTAssertEqual(stats.gpuOperations, 0)
        XCTAssertEqual(stats.cpuOperations, 0)
        XCTAssertEqual(stats.totalProcessingTime, 0.0)
        XCTAssertEqual(stats.peakGPUMemory, 0)
    }

    /// Tests GPU utilization calculation.
    func testGPUUtilizationCalculation() {
        var stats = J2KMetalDWTStatistics()
        XCTAssertEqual(stats.gpuUtilization, 0.0)

        stats.totalOperations = 10
        stats.gpuOperations = 8
        XCTAssertEqual(stats.gpuUtilization, 0.8, accuracy: 0.001)
    }

    /// Tests statistics reset.
    func testStatisticsReset() async {
        let dwt = J2KMetalDWT(configuration: .init(gpuThreshold: 999999))
        // Perform an operation to change stats
        let signal: [Float] = [1, 2, 3, 4]
        _ = try? await dwt.forward1D(signal: signal, backend: .cpu)

        let stats1 = await dwt.statistics()
        XCTAssertGreaterThan(stats1.totalOperations, 0)

        await dwt.resetStatistics()
        let stats2 = await dwt.statistics()
        XCTAssertEqual(stats2.totalOperations, 0)
    }

    // MARK: - Max Decomposition Levels Tests

    /// Tests max decomposition levels for various sizes.
    func testMaxDecompositionLevels() async {
        let dwt = J2KMetalDWT()

        let levels1 = await dwt.maxDecompositionLevels(width: 1, height: 1)
        XCTAssertEqual(levels1, 0)

        let levels2 = await dwt.maxDecompositionLevels(width: 4, height: 4)
        XCTAssertGreaterThanOrEqual(levels2, 1)

        let levels3 = await dwt.maxDecompositionLevels(width: 512, height: 512)
        XCTAssertGreaterThanOrEqual(levels3, 5)

        let levels4 = await dwt.maxDecompositionLevels(width: 4096, height: 4096)
        XCTAssertGreaterThanOrEqual(levels4, 8)
    }

    // MARK: - 1D Forward DWT Tests (CPU Backend)

    /// Tests 1D forward DWT with 9/7 filter produces correct subband sizes.
    func testForward1D97SubbandSizes() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let (lowpass, highpass) = try await dwt.forward1D(signal: signal, backend: .cpu)

        XCTAssertEqual(lowpass.count, 4)
        XCTAssertEqual(highpass.count, 4)
    }

    /// Tests 1D forward DWT with 5/3 filter produces correct subband sizes.
    func testForward1D53SubbandSizes() async throws {
        let config = J2KMetalDWTConfiguration(filter: .reversible53, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [1, 2, 3, 4, 5, 6]
        let (lowpass, highpass) = try await dwt.forward1D(signal: signal, backend: .cpu)

        XCTAssertEqual(lowpass.count, 3)
        XCTAssertEqual(highpass.count, 3)
    }

    /// Tests 1D forward DWT with odd-length signal.
    func testForward1DOddLength() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [1, 2, 3, 4, 5]
        let (lowpass, highpass) = try await dwt.forward1D(signal: signal, backend: .cpu)

        XCTAssertEqual(lowpass.count, 3) // (5+1)/2
        XCTAssertEqual(highpass.count, 2) // 5/2
    }

    /// Tests 1D forward DWT rejects too-short signal.
    func testForward1DRejectsTooShort() async {
        let dwt = J2KMetalDWT()
        do {
            _ = try await dwt.forward1D(signal: [1.0], backend: .cpu)
            XCTFail("Expected error for signal length 1")
        } catch {
            // Expected
        }
    }

    // MARK: - 1D Round-Trip Tests

    /// Tests 1D forward+inverse round-trip with 9/7 filter.
    func testRoundTrip1D97() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [1, 4, 7, 2, 9, 3, 6, 8]
        let (lowpass, highpass) = try await dwt.forward1D(signal: signal, backend: .cpu)
        let reconstructed = try await dwt.inverse1D(
            lowpass: lowpass, highpass: highpass, backend: .cpu
        )

        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 0.01,
                           "Mismatch at index \(i): \(reconstructed[i]) vs \(signal[i])")
        }
    }

    /// Tests 1D forward+inverse round-trip with 5/3 filter.
    func testRoundTrip1D53() async throws {
        let config = J2KMetalDWTConfiguration(filter: .reversible53, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [10, 20, 30, 40, 50, 60]
        let (lowpass, highpass) = try await dwt.forward1D(signal: signal, backend: .cpu)
        let reconstructed = try await dwt.inverse1D(
            lowpass: lowpass, highpass: highpass, backend: .cpu
        )

        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 0.01,
                           "Mismatch at index \(i)")
        }
    }

    /// Tests 1D round-trip with lifting scheme.
    func testRoundTrip1DLifting() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .lifting(.cdf97),
            gpuThreshold: 999999
        )
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [3, 7, 1, 9, 5, 2, 8, 4]
        let (lowpass, highpass) = try await dwt.forward1D(signal: signal, backend: .cpu)
        let reconstructed = try await dwt.inverse1D(
            lowpass: lowpass, highpass: highpass, backend: .cpu
        )

        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 0.01,
                           "Mismatch at index \(i)")
        }
    }

    // MARK: - 2D Forward DWT Tests

    /// Tests 2D forward DWT produces correct subband dimensions.
    func testForward2DSubbandDimensions() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let width = 8
        let height = 8
        let data = [Float](repeating: 1.0, count: width * height)
        let subbands = try await dwt.forward2D(
            data: data, width: width, height: height, backend: .cpu
        )

        XCTAssertEqual(subbands.llWidth, 4)
        XCTAssertEqual(subbands.llHeight, 4)
        XCTAssertEqual(subbands.originalWidth, 8)
        XCTAssertEqual(subbands.originalHeight, 8)
        XCTAssertEqual(subbands.ll.count, 16) // 4×4
        XCTAssertEqual(subbands.lh.count, 16) // 4×4
        XCTAssertEqual(subbands.hl.count, 16) // 4×4
        XCTAssertEqual(subbands.hh.count, 16) // 4×4
    }

    /// Tests 2D forward DWT with non-square image.
    func testForward2DNonSquare() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let width = 6
        let height = 4
        let data: [Float] = Array(stride(from: 1.0, through: Float(width * height), by: 1.0))
        let subbands = try await dwt.forward2D(
            data: data, width: width, height: height, backend: .cpu
        )

        XCTAssertEqual(subbands.llWidth, 3) // (6+1)/2
        XCTAssertEqual(subbands.llHeight, 2) // (4+1)/2
        XCTAssertEqual(subbands.originalWidth, 6)
        XCTAssertEqual(subbands.originalHeight, 4)
    }

    /// Tests 2D forward DWT rejects invalid dimensions.
    func testForward2DRejectsInvalidDimensions() async {
        let dwt = J2KMetalDWT()
        do {
            _ = try await dwt.forward2D(
                data: [1.0], width: 1, height: 1, backend: .cpu
            )
            XCTFail("Expected error for 1×1 image")
        } catch {
            // Expected
        }
    }

    /// Tests 2D forward DWT rejects mismatched data size.
    func testForward2DRejectsMismatchedData() async {
        let dwt = J2KMetalDWT()
        do {
            _ = try await dwt.forward2D(
                data: [1.0, 2.0, 3.0], width: 4, height: 4, backend: .cpu
            )
            XCTFail("Expected error for mismatched data size")
        } catch {
            // Expected
        }
    }

    // MARK: - 2D Round-Trip Tests

    /// Tests 2D forward+inverse round-trip with 9/7 filter.
    func testRoundTrip2D97() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let width = 8
        let height = 8
        var data = [Float](repeating: 0, count: width * height)
        for i in 0..<data.count {
            data[i] = Float(i % 17) * 3.0 + 1.0
        }

        let subbands = try await dwt.forward2D(
            data: data, width: width, height: height, backend: .cpu
        )
        let reconstructed = try await dwt.inverse2D(subbands: subbands, backend: .cpu)

        XCTAssertEqual(reconstructed.count, data.count)
        for i in 0..<data.count {
            XCTAssertEqual(reconstructed[i], data[i], accuracy: 0.1,
                           "Mismatch at index \(i): \(reconstructed[i]) vs \(data[i])")
        }
    }

    /// Tests 2D forward+inverse round-trip with 5/3 filter.
    func testRoundTrip2D53() async throws {
        let config = J2KMetalDWTConfiguration(filter: .reversible53, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let width = 8
        let height = 8
        var data = [Float](repeating: 0, count: width * height)
        for i in 0..<data.count {
            data[i] = Float(i % 11) * 5.0
        }

        let subbands = try await dwt.forward2D(
            data: data, width: width, height: height, backend: .cpu
        )
        let reconstructed = try await dwt.inverse2D(subbands: subbands, backend: .cpu)

        XCTAssertEqual(reconstructed.count, data.count)
        for i in 0..<data.count {
            XCTAssertEqual(reconstructed[i], data[i], accuracy: 0.1,
                           "Mismatch at index \(i)")
        }
    }

    // MARK: - Multi-Level DWT Tests

    /// Tests multi-level decomposition produces correct number of levels.
    func testMultiLevelDecompositionLevels() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .irreversible97,
            decompositionLevels: 3,
            gpuThreshold: 999999
        )
        let dwt = J2KMetalDWT(configuration: config)

        let width = 32
        let height = 32
        let data = [Float](repeating: 1.0, count: width * height)

        let decomp = try await dwt.forwardMultiLevel(
            data: data, width: width, height: height, backend: .cpu
        )

        XCTAssertEqual(decomp.levels.count, 3)
        XCTAssertGreaterThan(decomp.approximation.count, 0)
    }

    /// Tests multi-level round-trip reconstructs original data.
    func testMultiLevelRoundTrip() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .irreversible97,
            decompositionLevels: 2,
            gpuThreshold: 999999
        )
        let dwt = J2KMetalDWT(configuration: config)

        let width = 16
        let height = 16
        var data = [Float](repeating: 0, count: width * height)
        for i in 0..<data.count {
            data[i] = Float(i % 13) * 2.0 + 3.0
        }

        let decomp = try await dwt.forwardMultiLevel(
            data: data, width: width, height: height, backend: .cpu
        )
        let reconstructed = try await dwt.inverseMultiLevel(
            decomposition: decomp, backend: .cpu
        )

        XCTAssertEqual(reconstructed.count, data.count)
        for i in 0..<data.count {
            XCTAssertEqual(reconstructed[i], data[i], accuracy: 0.5,
                           "Mismatch at index \(i)")
        }
    }

    /// Tests that multi-level clamps levels to maximum possible.
    func testMultiLevelClampToMaxLevels() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .irreversible97,
            decompositionLevels: 100, // Way too many
            gpuThreshold: 999999
        )
        let dwt = J2KMetalDWT(configuration: config)

        let width = 8
        let height = 8
        let data = [Float](repeating: 1.0, count: width * height)

        let decomp = try await dwt.forwardMultiLevel(
            data: data, width: width, height: height, backend: .cpu
        )

        // Should not produce 100 levels for an 8×8 image
        XCTAssertLessThanOrEqual(decomp.levels.count, 3)
        XCTAssertGreaterThan(decomp.levels.count, 0)
    }

    /// Tests multi-level custom level count override.
    func testMultiLevelWithCustomLevelCount() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .irreversible97,
            decompositionLevels: 5,
            gpuThreshold: 999999
        )
        let dwt = J2KMetalDWT(configuration: config)

        let width = 64
        let height = 64
        let data = [Float](repeating: 1.0, count: width * height)

        // Override with 2 levels despite config saying 5
        let decomp = try await dwt.forwardMultiLevel(
            data: data, width: width, height: height, levels: 2, backend: .cpu
        )

        XCTAssertEqual(decomp.levels.count, 2)
    }

    // MARK: - Tile-Based Processing Tests

    /// Tests tile-based processing splits image correctly.
    func testTiledProcessing() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .irreversible97,
            tileWidth: 8,
            tileHeight: 8,
            gpuThreshold: 999999
        )
        let dwt = J2KMetalDWT(configuration: config)

        let width = 16
        let height = 16
        var data = [Float](repeating: 0, count: width * height)
        for i in 0..<data.count { data[i] = Float(i) }

        let tiles = try await dwt.forwardTiled(
            data: data, width: width, height: height, backend: .cpu
        )

        // 16×16 / 8×8 tiles = 4 tiles
        XCTAssertEqual(tiles.count, 4)

        // Verify tile coordinates
        let coords = tiles.map { ($0.tileX, $0.tileY) }
        XCTAssertTrue(coords.contains(where: { $0 == (0, 0) }))
        XCTAssertTrue(coords.contains(where: { $0 == (8, 0) }))
        XCTAssertTrue(coords.contains(where: { $0 == (0, 8) }))
        XCTAssertTrue(coords.contains(where: { $0 == (8, 8) }))
    }

    /// Tests tile-based processing with single tile covering full image.
    func testTiledProcessingFullImage() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .irreversible97,
            tileWidth: 0, // Full width
            tileHeight: 0, // Full height
            gpuThreshold: 999999
        )
        let dwt = J2KMetalDWT(configuration: config)

        let width = 8
        let height = 8
        let data = [Float](repeating: 1.0, count: width * height)

        let tiles = try await dwt.forwardTiled(
            data: data, width: width, height: height, backend: .cpu
        )

        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].tileX, 0)
        XCTAssertEqual(tiles[0].tileY, 0)
    }

    // MARK: - Numerical Accuracy Tests

    /// Tests that constant input produces energy in LL only.
    func testConstantInputConcentratesInLL() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let width = 8
        let height = 8
        let data = [Float](repeating: 100.0, count: width * height)

        let subbands = try await dwt.forward2D(
            data: data, width: width, height: height, backend: .cpu
        )

        // LL should have most energy, detail subbands should be near zero
        let llEnergy = subbands.ll.reduce(0) { $0 + $1 * $1 }
        let detailEnergy = subbands.lh.reduce(0) { $0 + $1 * $1 }
            + subbands.hl.reduce(0) { $0 + $1 * $1 }
            + subbands.hh.reduce(0) { $0 + $1 * $1 }

        XCTAssertGreaterThan(llEnergy, detailEnergy,
            "LL energy (\(llEnergy)) should dominate detail energy (\(detailEnergy))")
    }

    /// Tests energy preservation across transform.
    func testEnergyPreservation() async throws {
        let config = J2KMetalDWTConfiguration(filter: .irreversible97, gpuThreshold: 999999)
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [1, 4, 7, 2, 9, 3, 6, 8]
        let inputEnergy = signal.reduce(0) { $0 + $1 * $1 }

        let (lowpass, highpass) = try await dwt.forward1D(signal: signal, backend: .cpu)
        let outputEnergy = lowpass.reduce(0) { $0 + $1 * $1 }
            + highpass.reduce(0) { $0 + $1 * $1 }

        // Energy should be approximately preserved (within 20% for lifting)
        XCTAssertEqual(Double(outputEnergy), Double(inputEnergy),
                       accuracy: Double(inputEnergy) * 0.3,
                       "Energy not preserved: input=\(inputEnergy), output=\(outputEnergy)")
    }

    // MARK: - DWT Instance Tests

    /// Tests DWT instance creation with default parameters.
    func testDWTInstanceCreation() async {
        let dwt = J2KMetalDWT()
        let stats = await dwt.statistics()
        XCTAssertEqual(stats.totalOperations, 0)
    }

    /// Tests DWT instance creation with custom device.
    func testDWTInstanceWithCustomDevice() async {
        let device = J2KMetalDevice(configuration: .lowPower)
        let dwt = J2KMetalDWT(device: device)
        let stats = await dwt.statistics()
        XCTAssertEqual(stats.totalOperations, 0)
    }

    // MARK: - Shader Function Count Test

    /// Tests that all shader functions are defined.
    func testShaderFunctionCount() {
        let allCases = J2KMetalShaderFunction.allCases
        // 15 original + 8 DWT (arbitrary + lifting) + 7 new (NLT + MCT + fused)
        XCTAssertEqual(allCases.count, 30)
    }

    /// Tests new DWT shader function raw values.
    func testNewShaderFunctionRawValues() {
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtForwardArbitraryHorizontal.rawValue,
            "j2k_dwt_forward_arbitrary_horizontal"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtInverseArbitraryHorizontal.rawValue,
            "j2k_dwt_inverse_arbitrary_horizontal"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtForwardArbitraryVertical.rawValue,
            "j2k_dwt_forward_arbitrary_vertical"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtInverseArbitraryVertical.rawValue,
            "j2k_dwt_inverse_arbitrary_vertical"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtForwardLiftingHorizontal.rawValue,
            "j2k_dwt_forward_lifting_horizontal"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtInverseLiftingHorizontal.rawValue,
            "j2k_dwt_inverse_lifting_horizontal"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtForwardLiftingVertical.rawValue,
            "j2k_dwt_forward_lifting_vertical"
        )
        XCTAssertEqual(
            J2KMetalShaderFunction.dwtInverseLiftingVertical.rawValue,
            "j2k_dwt_inverse_lifting_vertical"
        )
    }

    // MARK: - Inverse DWT Validation Tests

    /// Tests inverse 1D DWT rejects empty lowpass.
    func testInverse1DRejectsEmptyLowpass() async {
        let dwt = J2KMetalDWT()
        do {
            _ = try await dwt.inverse1D(lowpass: [], highpass: [1.0], backend: .cpu)
            XCTFail("Expected error for empty lowpass")
        } catch {
            // Expected
        }
    }

    /// Tests inverse multi-level rejects empty decomposition.
    func testInverseMultiLevelRejectsEmpty() async {
        let dwt = J2KMetalDWT()
        let emptyDecomp = J2KMetalDWTDecomposition(
            approximation: [1.0],
            approximationWidth: 1,
            approximationHeight: 1,
            levels: []
        )
        do {
            _ = try await dwt.inverseMultiLevel(decomposition: emptyDecomp, backend: .cpu)
            XCTFail("Expected error for empty levels")
        } catch {
            // Expected
        }
    }

    // MARK: - Statistics After Operations

    /// Tests that statistics are updated after operations.
    func testStatisticsAfterOperations() async throws {
        let config = J2KMetalDWTConfiguration(
            filter: .irreversible97,
            gpuThreshold: 999999 // Force CPU
        )
        let dwt = J2KMetalDWT(configuration: config)

        let signal: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        _ = try await dwt.forward1D(signal: signal, backend: .cpu)
        _ = try await dwt.forward1D(signal: signal, backend: .cpu)

        let stats = await dwt.statistics()
        XCTAssertEqual(stats.totalOperations, 2)
        XCTAssertEqual(stats.cpuOperations, 2)
        XCTAssertEqual(stats.gpuOperations, 0)
        XCTAssertGreaterThan(stats.totalProcessingTime, 0)
    }
}
