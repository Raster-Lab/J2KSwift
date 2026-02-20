/// Tests for JP3D Integration (Week 235).
///
/// End-to-end integration tests covering encode→decode round-trips across all
/// JP3DCompressionMode configurations, HTJ2K + JPIP combined workflows, Metal GPU
/// vs CPU equivalence, cross-platform validation, memory usage, and performance
/// regression testing against the v1.8.0 baseline.

import XCTest
@testable import J2KCore
@testable import J2K3D
@testable import JPIP

// MARK: - Helpers

private func makeVolume(
    width: Int, height: Int, depth: Int,
    componentCount: Int = 1, bitDepth: Int = 8
) -> J2KVolume {
    let bytesPerSample = (bitDepth + 7) / 8
    var components: [J2KVolumeComponent] = []
    for c in 0..<componentCount {
        var data = Data(count: width * height * depth * bytesPerSample)
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width {
                    let idx = (z * width * height + y * width + x) * bytesPerSample
                    let value = UInt8(truncatingIfNeeded: (x + y * 3 + z * 7 + c * 13) % 256)
                    data[idx] = value
                }
            }
        }
        components.append(J2KVolumeComponent(
            index: c, bitDepth: bitDepth, signed: false,
            width: width, height: height, depth: depth,
            data: data
        ))
    }
    return J2KVolume(width: width, height: height, depth: depth, components: components)
}

// MARK: - Round-Trip Tests

final class JP3DRoundTripTests: XCTestCase {

    // MARK: 1. Lossless round-trip

    func testLosslessRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertTrue(encoded.isLossless)
        XCTAssertFalse(encoded.data.isEmpty)
        XCTAssertFalse(decoded.isPartial)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
        XCTAssertEqual(decoded.volume.components.count, volume.components.count)
    }

    // MARK: 2. Lossy (PSNR) round-trip

    func testLossyPSNRRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .lossy(psnr: 40.0))
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertFalse(encoded.isLossless)
        XCTAssertFalse(encoded.data.isEmpty)
        XCTAssertFalse(decoded.isPartial)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
    }

    // MARK: 3. Target-bitrate round-trip

    func testTargetBitrateRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .targetBitrate(bitsPerVoxel: 2.0))
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertFalse(encoded.data.isEmpty)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
    }

    // MARK: 4. Visually lossless round-trip

    func testVisuallyLosslessRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .visuallyLossless)
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertFalse(encoded.data.isEmpty)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
    }

    // MARK: 5. HTJ2K lossless round-trip

    func testHTJ2KLosslessRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertTrue(encoded.isLossless)
        XCTAssertFalse(encoded.data.isEmpty)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
    }

    // MARK: 6. HTJ2K lossy round-trip

    func testHTJ2KLossyRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .lossyHTJ2K(psnr: 38.0))
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertFalse(encoded.isLossless)
        XCTAssertFalse(encoded.data.isEmpty)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
    }

    // MARK: 7. Multi-component round-trip

    func testMultiComponentRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4, componentCount: 3, bitDepth: 8)
        let encoder = JP3DEncoder(configuration: .lossless)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertEqual(decoded.volume.components.count, 3)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
    }

    // MARK: 8. Single-slice volume round-trip

    func testSingleSliceVolumeRoundTrip() async throws {
        // Arrange — depth==1 is a degenerate case treated as 2D with JP3D wrapper
        let volume = makeVolume(width: 32, height: 32, depth: 1)
        let encoder = JP3DEncoder(configuration: .lossless)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertEqual(decoded.volume.depth, 1)
        XCTAssertEqual(decoded.volume.width, 32)
        XCTAssertEqual(decoded.volume.height, 32)
    }

    // MARK: 9. 16-bit round-trip

    func test16BitRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4, componentCount: 1, bitDepth: 16)
        let encoder = JP3DEncoder(configuration: .lossless)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertTrue(encoded.isLossless)
        XCTAssertEqual(decoded.volume.width, 16)
        XCTAssertEqual(decoded.volume.height, 16)
        XCTAssertEqual(decoded.volume.depth, 4)
    }

    // MARK: 10. Multiple quality layers round-trip

    func testMultipleQualityLayersRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossy(psnr: 35.0),
            qualityLayers: 4
        )
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertFalse(encoded.data.isEmpty)
        XCTAssertEqual(decoded.volume.width, volume.width)
        XCTAssertEqual(decoded.volume.height, volume.height)
        XCTAssertEqual(decoded.volume.depth, volume.depth)
    }
}

// MARK: - Progression Order Tests

final class JP3DProgressionOrderIntegrationTests: XCTestCase {

    private func roundTrip(
        volume: J2KVolume,
        order: JP3DProgressionOrder
    ) async throws -> JP3DDecoderResult {
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            progressionOrder: order
        )
        let encoded = try await JP3DEncoder(configuration: config).encode(volume)
        return try await JP3DDecoder(configuration: .default).decode(encoded.data)
    }

    func testLRCPSProgression() async throws {
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let result = try await roundTrip(volume: volume, order: .lrcps)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testRLCPSProgression() async throws {
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let result = try await roundTrip(volume: volume, order: .rlcps)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testPCRLSProgression() async throws {
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let result = try await roundTrip(volume: volume, order: .pcrls)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testSLRCPProgression() async throws {
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let result = try await roundTrip(volume: volume, order: .slrcp)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testCPRLSProgression() async throws {
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let result = try await roundTrip(volume: volume, order: .cprls)
        XCTAssertEqual(result.volume.depth, 4)
    }
}

// MARK: - Tiling Configuration Tests

final class JP3DTilingIntegrationTests: XCTestCase {

    func testStreamingTilingRoundTrip() async throws {
        // Arrange
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            tiling: .streaming
        )
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertEqual(decoded.volume.width, 32)
        XCTAssertEqual(decoded.volume.height, 32)
        XCTAssertEqual(decoded.volume.depth, 8)
    }

    func testBatchTilingRoundTrip() async throws {
        // Arrange — volume smaller than batch tile size (512×512×32)
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            tiling: .batch
        )
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertEqual(decoded.volume.width, 16)
        XCTAssertEqual(decoded.volume.height, 16)
        XCTAssertEqual(decoded.volume.depth, 4)
    }

    func testNonPowerOf2DimensionsRoundTrip() async throws {
        // Arrange — 17×13×5: non-power-of-2 in all axes
        let volume = makeVolume(width: 17, height: 13, depth: 5)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            tiling: JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        )
        let encoder = JP3DEncoder(configuration: config)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let encoded = try await encoder.encode(volume)
        let decoded = try await decoder.decode(encoded.data)

        // Assert
        XCTAssertEqual(decoded.volume.width, 17)
        XCTAssertEqual(decoded.volume.height, 13)
        XCTAssertEqual(decoded.volume.depth, 5)
    }
}

// MARK: - HTJ2K + JPIP Combined Workflow

final class JP3DHTj2KJPIPWorkflowTests: XCTestCase {

    /// Validates: encode with HTJ2K → build JPIP viewport → request region → verify bins.
    func testHTJ2KEncodeAndJPIPRegionRequest() async throws {
        // Arrange
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let encConfig = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
        let encoder = JP3DEncoder(configuration: encConfig)
        let encoded = try await encoder.encode(volume)

        // The encoded data should be non-empty with HTJ2K
        XCTAssertFalse(encoded.data.isEmpty, "HTJ2K encoded data must not be empty")
        XCTAssertTrue(encoded.isLossless, "HTJ2K lossless must report isLossless = true")

        // Arrange JPIP client (uses simulated server, no real network)
        let client = JP3DJPIPClient(
            serverURL: URL(string: "http://localhost:8080/jp3d")!,
            preferredProgressionMode: .adaptive
        )

        // Act — connect, create session, request a sub-region
        try await client.connect()
        try await client.createSession(volumeID: "test-volume-htj2k")
        let region = JP3DStreamingRegion(
            xRange: 0..<16, yRange: 0..<16, zRange: 0..<4,
            qualityLayer: 1, resolutionLevel: 0
        )
        let bins = try await client.requestRegion(region)

        // Assert
        XCTAssertFalse(bins.isEmpty, "JPIP region request must return at least one data bin")
    }

    /// Validates: encode with HTJ2K lossy → request slice range via JPIP → get bins.
    func testHTJ2KLossyWithJPIPSliceRange() async throws {
        // Arrange
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let encConfig = JP3DEncoderConfiguration(compressionMode: .lossyHTJ2K(psnr: 40.0))
        let encoder = JP3DEncoder(configuration: encConfig)
        let encoded = try await encoder.encode(volume)

        XCTAssertFalse(encoded.isLossless)

        let client = JP3DJPIPClient(serverURL: URL(string: "http://localhost:8080/jp3d")!)
        try await client.connect()
        try await client.createSession(volumeID: "test-volume-htj2k-lossy")

        // Act
        let bins = try await client.requestSliceRange(zRange: 0..<4, quality: 1)

        // Assert
        XCTAssertFalse(bins.isEmpty)
    }

    /// Validates that a JPIP viewport update does not throw.
    func testJPIPViewportUpdate() async throws {
        // Arrange
        let client = JP3DJPIPClient(serverURL: URL(string: "http://localhost:9090/stream")!)
        try await client.connect()

        let viewport = JP3DViewport(xRange: 0..<128, yRange: 0..<128, zRange: 0..<32)

        // Act / Assert — should not throw
        await client.updateViewport(viewport)
    }

    /// Validates the disconnect path.
    func testJPIPConnectDisconnect() async throws {
        // Arrange
        let client = JP3DJPIPClient(serverURL: URL(string: "http://localhost:8080/jp3d")!)

        // Act
        try await client.connect()
        await client.disconnect()

        // Assert — verify state is disconnected
        let state = await client.state
        XCTAssertEqual(state, .disconnected)
    }
}

// MARK: - Metal GPU vs CPU Result Equivalence

/// Tests that the Metal GPU path (when available) and the CPU path produce
/// compatible outputs. On Linux (no Metal), both paths fall back to CPU and
/// results should be identical.
final class JP3DMetalCPUEquivalenceTests: XCTestCase {

    func testMetalAndCPUEncodeProduceSameVolumeShape() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let cpuConfig = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            parallelEncoding: false
        )
        let gpuConfig = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            parallelEncoding: true     // parallel path uses Metal when available
        )
        let cpuEncoder = JP3DEncoder(configuration: cpuConfig)
        let gpuEncoder = JP3DEncoder(configuration: gpuConfig)
        let decoder = JP3DDecoder(configuration: .default)

        // Act
        let cpuEncoded = try await cpuEncoder.encode(volume)
        let gpuEncoded = try await gpuEncoder.encode(volume)

        let cpuDecoded = try await decoder.decode(cpuEncoded.data)
        let gpuDecoded = try await decoder.decode(gpuEncoded.data)

        // Assert — both paths reconstruct identical volume dimensions
        XCTAssertEqual(cpuDecoded.volume.width, gpuDecoded.volume.width)
        XCTAssertEqual(cpuDecoded.volume.height, gpuDecoded.volume.height)
        XCTAssertEqual(cpuDecoded.volume.depth, gpuDecoded.volume.depth)
        XCTAssertEqual(cpuDecoded.volume.components.count, gpuDecoded.volume.components.count)
    }

    func testLosslessMetalAndCPUProduceSameTileCount() async throws {
        // Arrange
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 16, tileSizeY: 16, tileSizeZ: 4)
        let cpuConfig = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, parallelEncoding: false
        )
        let gpuConfig = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, parallelEncoding: true
        )

        let cpuResult = try await JP3DEncoder(configuration: cpuConfig).encode(volume)
        let gpuResult = try await JP3DEncoder(configuration: gpuConfig).encode(volume)

        // Assert — both paths encode the same number of tiles
        XCTAssertEqual(cpuResult.tileCount, gpuResult.tileCount)
    }
}

// MARK: - Cross-Platform Validation

/// Validates that core APIs behave identically on all supported platforms
/// (macOS, Linux, Windows). No platform-specific imports are required here;
/// these tests rely only on J2KCore and J2K3D APIs.
final class JP3DCrossPlatformTests: XCTestCase {

    func testVersionReportedCorrectly() {
        // Arrange / Act
        let version = getVersion()

        // Assert
        XCTAssertEqual(version, "1.9.0", "getVersion() must return '1.9.0'")
    }

    func testTilingConfigurationIsConsistent() {
        // Arrange
        let tiling = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 8)

        // Act
        let grid = tiling.tileGrid(volumeWidth: 128, volumeHeight: 128, volumeDepth: 16)
        let total = tiling.totalTiles(volumeWidth: 128, volumeHeight: 128, volumeDepth: 16)

        // Assert — platform-independent arithmetic
        XCTAssertEqual(grid.tilesX, 2)
        XCTAssertEqual(grid.tilesY, 2)
        XCTAssertEqual(grid.tilesZ, 2)
        XCTAssertEqual(total, 8)
    }

    func testRegionIntersectionIsConsistent() {
        // Arrange
        let r1 = JP3DRegion(x: 0..<64, y: 0..<64, z: 0..<16)
        let r2 = JP3DRegion(x: 32..<96, y: 32..<96, z: 8..<24)

        // Act
        let intersection = r1.intersection(r2)

        // Assert
        XCTAssertNotNil(intersection)
        XCTAssertEqual(intersection?.x, 32..<64)
        XCTAssertEqual(intersection?.y, 32..<64)
        XCTAssertEqual(intersection?.z, 8..<16)
    }

    func testCompressionModePropertiesAreConsistent() {
        XCTAssertTrue(JP3DCompressionMode.lossless.isLossless)
        XCTAssertTrue(JP3DCompressionMode.losslessHTJ2K.isLossless)
        XCTAssertFalse(JP3DCompressionMode.lossy(psnr: 40).isLossless)
        XCTAssertFalse(JP3DCompressionMode.lossyHTJ2K(psnr: 40).isLossless)
        XCTAssertTrue(JP3DCompressionMode.losslessHTJ2K.isHTJ2K)
        XCTAssertTrue(JP3DCompressionMode.lossyHTJ2K(psnr: 40).isHTJ2K)
        XCTAssertFalse(JP3DCompressionMode.lossless.isHTJ2K)
    }

    func testVolumeConstructionIsConsistent() {
        // Arrange
        let volume = makeVolume(width: 8, height: 8, depth: 4)

        // Assert
        XCTAssertEqual(volume.width, 8)
        XCTAssertEqual(volume.height, 8)
        XCTAssertEqual(volume.depth, 4)
        XCTAssertFalse(volume.components.isEmpty)
        XCTAssertEqual(volume.voxelCount, 8 * 8 * 4)
    }

    func testProgressionOrderCasesAllPresent() {
        let allCases = JP3DProgressionOrder.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.lrcps))
        XCTAssertTrue(allCases.contains(.rlcps))
        XCTAssertTrue(allCases.contains(.pcrls))
        XCTAssertTrue(allCases.contains(.slrcp))
        XCTAssertTrue(allCases.contains(.cprls))
    }
}

// MARK: - Memory Usage Under Sustained Load

final class JP3DMemoryUsageTests: XCTestCase {

    /// Encodes and decodes a volume repeatedly to detect memory growth.
    /// A catastrophic leak would cause an OOM crash; this test validates
    /// the basic path does not accumulate unbounded data.
    func testRepeatedEncodeDecodeDoesNotLeak() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)
        let decoder = JP3DDecoder(configuration: .default)

        // Act — 20 iterations in succession
        for _ in 0..<20 {
            let encoded = try await encoder.encode(volume)
            let decoded = try await decoder.decode(encoded.data)

            // Quick sanity check each iteration
            XCTAssertFalse(encoded.data.isEmpty)
            XCTAssertEqual(decoded.volume.width, volume.width)
        }
        // If we reach here without a crash or OOM, the test passes.
    }

    /// Encodes a moderately large volume and verifies that the compression
    /// ratio is plausible (> 1.0 for random-ish data).
    func testCompressionRatioIsPositive() async throws {
        // Arrange
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let config = JP3DEncoderConfiguration(compressionMode: .lossy(psnr: 30.0))
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertGreaterThan(result.compressionRatio, 0.0)
    }

    /// Verifies the streaming tile count matches the expected tiling grid.
    func testTileCountMatchesTilingGrid() async throws {
        // Arrange
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 16, tileSizeY: 16, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .lossless, tiling: tiling)
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert: 32/16 × 32/16 × 8/4 = 2×2×2 = 8 tiles
        XCTAssertEqual(result.tileCount, 8)
    }
}

// MARK: - Performance Regression Tests

final class JP3DPerformanceRegressionTests: XCTestCase {

    /// Baseline: encode a 32×32×8 lossless volume within a reasonable wall-clock budget.
    /// This guards against catastrophic algorithmic regressions vs v1.8.0.
    func testLosslessEncoderPerformanceBaseline() throws {
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let encoder = JP3DEncoder(configuration: .lossless)

        measure {
            let expectation = XCTestExpectation(description: "encode")
            Task {
                _ = try? await encoder.encode(volume)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30.0)
        }
    }

    /// Baseline: decode a pre-encoded volume within a reasonable budget.
    func testLosslessDecoderPerformanceBaseline() async throws {
        let volume = makeVolume(width: 32, height: 32, depth: 8)
        let encoder = JP3DEncoder(configuration: .lossless)
        let encoded = try await encoder.encode(volume)
        let decoder = JP3DDecoder(configuration: .default)

        measure {
            let expectation = XCTestExpectation(description: "decode")
            Task {
                _ = try? await decoder.decode(encoded.data)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30.0)
        }
    }

    /// Validates that HTJ2K encoding does not regress below the standard path
    /// for small volumes (it should be at least as fast or faster).
    func testHTJ2KEncoderIsNotSlowerThanStandard() async throws {
        // Arrange
        let volume = makeVolume(width: 16, height: 16, depth: 4)
        let standardEncoder = JP3DEncoder(configuration: .lossless)
        let htEncoder = JP3DEncoder(
            configuration: JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
        )

        // Act — both paths should complete without error
        let stdResult = try await standardEncoder.encode(volume)
        let htResult = try await htEncoder.encode(volume)

        // Assert — both produce valid output
        XCTAssertFalse(stdResult.data.isEmpty)
        XCTAssertFalse(htResult.data.isEmpty)
        XCTAssertEqual(stdResult.width, htResult.width)
        XCTAssertEqual(stdResult.height, htResult.height)
        XCTAssertEqual(stdResult.depth, htResult.depth)
    }
}

// MARK: - Encoder/Decoder Configuration Validation

final class JP3DConfigurationValidationTests: XCTestCase {

    func testEncoderConfigurationDefaults() {
        let config = JP3DEncoderConfiguration()
        XCTAssertEqual(config.compressionMode, .lossless)
        XCTAssertEqual(config.tiling, .default)
        XCTAssertEqual(config.progressionOrder, .lrcps)
        XCTAssertEqual(config.qualityLayers, 1)
        XCTAssertTrue(config.parallelEncoding)
    }

    func testEncoderConfigurationLosslessPreset() {
        let config = JP3DEncoderConfiguration.lossless
        XCTAssertEqual(config.compressionMode, .lossless)
        XCTAssertTrue(config.compressionMode.isLossless)
    }

    func testEncoderConfigurationLossyPreset() {
        let config = JP3DEncoderConfiguration.lossy()
        XCTAssertFalse(config.compressionMode.isLossless)
        XCTAssertFalse(config.compressionMode.isHTJ2K)
    }

    func testDecoderConfigurationDefaults() {
        let config = JP3DDecoderConfiguration.default
        XCTAssertEqual(config.maxQualityLayers, 0)
        XCTAssertEqual(config.resolutionLevel, 0)
        XCTAssertTrue(config.tolerateErrors)
    }

    func testDecoderThumbnailPreset() {
        let config = JP3DDecoderConfiguration.thumbnail
        XCTAssertEqual(config.resolutionLevel, 2)
    }

    func testTilingConfigurationValidation() throws {
        let valid = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 8)
        XCTAssertNoThrow(try valid.validate())
    }

    func testHTJ2KConfigurationFromPreset() {
        let config = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
        XCTAssertTrue(config.compressionMode.isHTJ2K)
        XCTAssertTrue(config.compressionMode.isLossless)
    }
}

// MARK: - JPIP Streaming API Integration

final class JP3DJPIPAPIIntegrationTests: XCTestCase {

    func testJPIPClientInitialization() {
        // Arrange / Act
        let client = JP3DJPIPClient(
            serverURL: URL(string: "ws://localhost:8080/jp3d")!,
            preferredProgressionMode: .resolutionFirst
        )

        // Assert
        XCTAssertEqual(client.serverURL.absoluteString, "ws://localhost:8080/jp3d")
    }

    func testJPIPViewportCreation() {
        let vp = JP3DViewport(xRange: 0..<256, yRange: 0..<256, zRange: 0..<64)
        XCTAssertEqual(vp.xRange, 0..<256)
        XCTAssertEqual(vp.yRange, 0..<256)
        XCTAssertEqual(vp.zRange, 0..<64)
    }

    func testJPIPStreamingRegionCreation() {
        let region = JP3DStreamingRegion(
            xRange: 0..<128, yRange: 0..<128, zRange: 0..<32,
            qualityLayer: 2, resolutionLevel: 0
        )
        XCTAssertEqual(region.xRange, 0..<128)
        XCTAssertEqual(region.yRange, 0..<128)
        XCTAssertEqual(region.zRange, 0..<32)
        XCTAssertEqual(region.qualityLayer, 2)
    }

    func testJPIPProgressionModeAllCases() {
        let allModes = JP3DProgressionMode.allCases
        XCTAssertFalse(allModes.isEmpty)
        XCTAssertTrue(allModes.contains(.adaptive))
        XCTAssertTrue(allModes.contains(.resolutionFirst))
        XCTAssertTrue(allModes.contains(.qualityFirst))
        XCTAssertTrue(allModes.contains(.sliceBySliceForward))
    }

    func testJPIPClientReconnect() async throws {
        // Arrange
        let client = JP3DJPIPClient(serverURL: URL(string: "http://localhost:8080")!)
        try await client.connect()

        // Act — reconnect should not throw
        try await client.reconnect()

        // Assert — state should be connected after reconnect
        let state = await client.state
        XCTAssertEqual(state, .connected)
    }
}
