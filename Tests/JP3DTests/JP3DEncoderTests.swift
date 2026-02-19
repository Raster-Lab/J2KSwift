/// Tests for JP3D Encoder (Week 218-221).
///
/// Validates the complete JP3D encoding pipeline including tiling,
/// wavelet transform, quantization, rate control, packet formation,
/// streaming encoder, and edge cases.

import XCTest
@testable import J2KCore
@testable import J2K3D

/// Thread-safe counter for use in Sendable closures.
private final class ManagedAtomic: @unchecked Sendable {
    private var _value: Int
    private let lock = NSLock()

    init(_ initial: Int) { _value = initial }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}

final class JP3DEncoderTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a test volume with gradient data.
    private func makeTestVolume(
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
                        let idx = z * width * height + y * width + x
                        let value = (x + y * 2 + z * 3 + c * 7) % 256
                        for b in 0..<bytesPerSample {
                            data[idx * bytesPerSample + b] = UInt8(truncatingIfNeeded: value >> (b * 8))
                        }
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

    /// Creates raw float test data.
    private func makeTestData(width: Int, height: Int, depth: Int) -> [Float] {
        var data = [Float](repeating: 0, count: width * height * depth)
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width {
                    let idx = z * width * height + y * width + x
                    data[idx] = Float(x + y * 2 + z * 3) * 0.5 + 1.0
                }
            }
        }
        return data
    }

    // MARK: - 1. Tiling Tests

    func testTileDecomposerDefaultConfig() throws {
        // Arrange
        let volume = makeTestVolume(width: 16, height: 16, depth: 4)
        let decomposer = JP3DTileDecomposer(configuration: .default)

        // Act
        let tiles = decomposer.decompose(volume: volume)

        // Assert - volume is smaller than default tile (256x256x16), so 1 tile
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].width, 16)
        XCTAssertEqual(tiles[0].height, 16)
        XCTAssertEqual(tiles[0].depth, 4)
    }

    func testTileDecomposerMultipleTiles() throws {
        // Arrange
        let volume = makeTestVolume(width: 32, height: 32, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 16, tileSizeY: 16, tileSizeZ: 4)
        let decomposer = JP3DTileDecomposer(configuration: tiling)

        // Act
        let tiles = decomposer.decompose(volume: volume)

        // Assert - 2x2x2 = 8 tiles
        XCTAssertEqual(tiles.count, 8)
        for tile in tiles {
            XCTAssertEqual(tile.width, 16)
            XCTAssertEqual(tile.height, 16)
            XCTAssertEqual(tile.depth, 4)
        }
    }

    func testTileDecomposerPartialTiles() throws {
        // Arrange - 17 is not evenly divisible by 8
        let volume = makeTestVolume(width: 17, height: 17, depth: 5)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let decomposer = JP3DTileDecomposer(configuration: tiling)

        // Act
        let tiles = decomposer.decompose(volume: volume)
        let grid = decomposer.tileGrid(for: volume)

        // Assert - 3x3x2 = 18 tiles
        XCTAssertEqual(grid.tilesX, 3)
        XCTAssertEqual(grid.tilesY, 3)
        XCTAssertEqual(grid.tilesZ, 2)
        XCTAssertEqual(tiles.count, 18)

        // Check boundary tile has partial size
        let lastTile = tiles.last!
        XCTAssertEqual(lastTile.width, 1)  // 17 - 16 = 1
        XCTAssertEqual(lastTile.height, 1) // 17 - 16 = 1
        XCTAssertEqual(lastTile.depth, 1)  // 5 - 4 = 1
    }

    func testTileDataExtraction() throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let tiling = JP3DTilingConfiguration(tileSizeX: 4, tileSizeY: 4, tileSizeZ: 2)
        let decomposer = JP3DTileDecomposer(configuration: tiling)
        let tiles = decomposer.decompose(volume: volume)

        // Act
        let tileData = try decomposer.extractTileData(
            from: volume, tile: tiles[0], componentIndex: 0
        )

        // Assert
        XCTAssertEqual(tileData.width, 4)
        XCTAssertEqual(tileData.height, 4)
        XCTAssertEqual(tileData.depth, 2)
        XCTAssertEqual(tileData.data.count, 4 * 4 * 2)
    }

    func testTileDataExtractionInvalidComponent() throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let decomposer = JP3DTileDecomposer(configuration: .default)
        let tiles = decomposer.decompose(volume: volume)

        // Act & Assert
        XCTAssertThrowsError(
            try decomposer.extractTileData(
                from: volume, tile: tiles[0], componentIndex: 5
            )
        )
    }

    func testTileDecomposerSingleTile() throws {
        // Arrange - tile size >= volume size
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let tiling = JP3DTilingConfiguration(tileSizeX: 1000, tileSizeY: 1000, tileSizeZ: 1000)
        let decomposer = JP3DTileDecomposer(configuration: tiling)

        // Act
        let tiles = decomposer.decompose(volume: volume)

        // Assert - clamped to volume, single tile
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].width, 4)
        XCTAssertEqual(tiles[0].height, 4)
        XCTAssertEqual(tiles[0].depth, 2)
    }

    func testClampedConfiguration() throws {
        // Arrange
        let volume = makeTestVolume(width: 10, height: 10, depth: 3)
        let decomposer = JP3DTileDecomposer(configuration: .batch) // 512x512x32

        // Act
        let clamped = decomposer.clampedConfiguration(for: volume)

        // Assert
        XCTAssertEqual(clamped.tileSizeX, 10)
        XCTAssertEqual(clamped.tileSizeY, 10)
        XCTAssertEqual(clamped.tileSizeZ, 3)
    }

    func testTileLinearIndex() {
        // Arrange
        let region = JP3DRegion(x: 0..<8, y: 0..<8, z: 0..<4)
        let tile = JP3DTile(indexX: 1, indexY: 2, indexZ: 1, region: region)

        // Act
        let idx = tile.linearIndex(tilesX: 3, tilesY: 3)

        // Assert - z * (3*3) + y * 3 + x = 1*9 + 2*3 + 1 = 16
        XCTAssertEqual(idx, 16)
    }

    // MARK: - 2. Rate Control Tests

    func testRateControlLosslessStepSize() {
        // Arrange
        let controller = JP3DRateController(mode: .lossless)

        // Act
        let step = controller.stepSize(bitDepth: 8, decompositionLevels: 3)

        // Assert - lossless always has step size 1.0
        XCTAssertEqual(step, 1.0)
    }

    func testRateControlLossyStepSize() {
        // Arrange
        let controller = JP3DRateController(mode: .lossy(psnr: 40.0))

        // Act
        let step = controller.stepSize(bitDepth: 8, decompositionLevels: 3)

        // Assert - lossy step should be >= 1.0
        XCTAssertGreaterThanOrEqual(step, 1.0)
    }

    func testRateControlTargetBitrateStepSize() {
        // Arrange
        let controller = JP3DRateController(mode: .targetBitrate(bitsPerVoxel: 1.0))

        // Act
        let step = controller.stepSize(bitDepth: 8, decompositionLevels: 3)

        // Assert
        XCTAssertGreaterThanOrEqual(step, 1.0)
    }

    func testRateControlVisuallyLossless() {
        // Arrange
        let controller = JP3DRateController(mode: .visuallyLossless)

        // Act
        let step = controller.stepSize(bitDepth: 8, decompositionLevels: 3)

        // Assert - visually lossless uses high PSNR, step should be moderate
        XCTAssertGreaterThanOrEqual(step, 1.0)
    }

    func testQuantizeLossless() {
        // Arrange
        let controller = JP3DRateController(mode: .lossless)
        let coefficients: [Float] = [1.0, -2.0, 3.5, -4.7, 0.0, 5.9]
        let tile = JP3DTile(
            indexX: 0, indexY: 0, indexZ: 0,
            region: JP3DRegion(x: 0..<3, y: 0..<2, z: 0..<1)
        )

        // Act
        let quantized = controller.quantize(
            coefficients: coefficients, tile: tile,
            componentIndex: 0, bitDepth: 8, decompositionLevels: 3
        )

        // Assert - lossless rounds to nearest integer
        XCTAssertEqual(quantized.coefficients.count, 6)
        XCTAssertEqual(quantized.coefficients[0], 1)
        XCTAssertEqual(quantized.coefficients[1], -2)
        XCTAssertEqual(quantized.coefficients[2], 4) // rounds 3.5 -> 4
        XCTAssertEqual(quantized.stepSize, 1.0)
    }

    func testQuantizeLossy() {
        // Arrange
        let controller = JP3DRateController(mode: .lossy(psnr: 30.0))
        let coefficients: [Float] = [100.0, -200.0, 50.0, 0.0]
        let tile = JP3DTile(
            indexX: 0, indexY: 0, indexZ: 0,
            region: JP3DRegion(x: 0..<2, y: 0..<2, z: 0..<1)
        )

        // Act
        let quantized = controller.quantize(
            coefficients: coefficients, tile: tile,
            componentIndex: 0, bitDepth: 8, decompositionLevels: 3
        )

        // Assert - lossy quantization reduces values
        XCTAssertEqual(quantized.coefficients.count, 4)
        XCTAssertGreaterThan(quantized.stepSize, 1.0)
    }

    func testDequantizeRoundTrip() {
        // Arrange
        let controller = JP3DRateController(mode: .lossless)
        let coefficients: [Float] = [1.0, -2.0, 3.0, 0.0]
        let tile = JP3DTile(
            indexX: 0, indexY: 0, indexZ: 0,
            region: JP3DRegion(x: 0..<2, y: 0..<2, z: 0..<1)
        )

        // Act
        let quantized = controller.quantize(
            coefficients: coefficients, tile: tile,
            componentIndex: 0, bitDepth: 8, decompositionLevels: 3
        )
        let dequantized = controller.dequantize(quantized)

        // Assert - lossless round-trip
        XCTAssertEqual(dequantized.count, coefficients.count)
        for i in 0..<coefficients.count {
            XCTAssertEqual(dequantized[i], coefficients[i], accuracy: 0.01)
        }
    }

    func testQualityLayerFormation() {
        // Arrange
        let controller = JP3DRateController(mode: .lossy(psnr: 40.0), qualityLayers: 3)

        // Act
        let layers = controller.formQualityLayers(totalVoxels: 1000, totalBits: 8000)

        // Assert
        XCTAssertEqual(layers.count, 3)
        XCTAssertEqual(layers[0].index, 0)
        XCTAssertEqual(layers[2].index, 2)
        // Each successive layer should have higher target rate
        XCTAssertLessThan(layers[0].targetBitsPerVoxel, layers[1].targetBitsPerVoxel)
        XCTAssertLessThan(layers[1].targetBitsPerVoxel, layers[2].targetBitsPerVoxel)
    }

    func testZeroQualityLayersRejected() {
        // Arrange & Act
        let controller = JP3DRateController(mode: .lossless, qualityLayers: 0)

        // Assert - clamped to minimum of 1
        XCTAssertEqual(controller.qualityLayers, 1)
    }

    // MARK: - 3. Packet Formation Tests

    func testPacketSequencerLRCPS() {
        // Arrange
        let sequencer = JP3DPacketSequencer(progressionOrder: .lrcps)

        // Act
        let indices = sequencer.packetOrder(
            layers: 2, resolutions: 2, components: 1,
            precinctsPerResolution: [1, 1], slices: 2
        )

        // Assert - LRCPS: layers outermost
        XCTAssertEqual(indices.count, 8) // 2*2*1*1*2
        XCTAssertEqual(indices[0].layer, 0) // First layer first
        XCTAssertEqual(indices[4].layer, 1) // Second layer later
    }

    func testPacketSequencerRLCPS() {
        // Arrange
        let sequencer = JP3DPacketSequencer(progressionOrder: .rlcps)

        // Act
        let indices = sequencer.packetOrder(
            layers: 2, resolutions: 2, components: 1,
            precinctsPerResolution: [1, 1], slices: 2
        )

        // Assert - RLCPS: resolution outermost
        XCTAssertEqual(indices.count, 8)
        XCTAssertEqual(indices[0].resolution, 0) // First resolution first
    }

    func testPacketSequencerSLRCP() {
        // Arrange
        let sequencer = JP3DPacketSequencer(progressionOrder: .slrcp)

        // Act
        let indices = sequencer.packetOrder(
            layers: 2, resolutions: 2, components: 1,
            precinctsPerResolution: [1, 1], slices: 3
        )

        // Assert - SLRCP: slice outermost
        XCTAssertEqual(indices[0].slice, 0)
        XCTAssertEqual(indices.last!.slice, 2)
    }

    func testPacketSequencerPCRLS() {
        // Arrange
        let sequencer = JP3DPacketSequencer(progressionOrder: .pcrls)

        // Act
        let indices = sequencer.packetOrder(
            layers: 1, resolutions: 2, components: 1,
            precinctsPerResolution: [2, 1], slices: 1
        )

        // Assert - PCRLS: position outermost
        XCTAssertFalse(indices.isEmpty)
        XCTAssertEqual(indices[0].precinct, 0)
    }

    func testPacketSequencerCPRLS() {
        // Arrange
        let sequencer = JP3DPacketSequencer(progressionOrder: .cprls)

        // Act
        let indices = sequencer.packetOrder(
            layers: 1, resolutions: 1, components: 3,
            precinctsPerResolution: [1], slices: 1
        )

        // Assert - CPRLS: component outermost
        XCTAssertEqual(indices.count, 3)
        XCTAssertEqual(indices[0].component, 0)
        XCTAssertEqual(indices[1].component, 1)
        XCTAssertEqual(indices[2].component, 2)
    }

    func testAllProgressionOrders() {
        // All progression orders should produce the same number of packets
        let layers = 2
        let resolutions = 2
        let components = 2
        let precincts = [2, 1]
        let slices = 2

        for order in JP3DProgressionOrder.allCases {
            let sequencer = JP3DPacketSequencer(progressionOrder: order)
            let indices = sequencer.packetOrder(
                layers: layers, resolutions: resolutions, components: components,
                precinctsPerResolution: precincts, slices: slices
            )
            // All orders should produce valid non-empty sequences
            XCTAssertFalse(indices.isEmpty, "Order \(order.rawValue) produced empty sequence")
        }
    }

    // MARK: - 4. Codestream Builder Tests

    func testCodestreamBuilderBasic() {
        // Arrange
        let builder = JP3DCodestreamBuilder()
        let tileData = [Data([0x01, 0x02, 0x03, 0x04])]

        // Act
        let codestream = builder.build(
            tileData: tileData,
            width: 4, height: 4, depth: 1,
            components: 1, bitDepth: 8,
            decompositionLevels: 3, isLossless: true
        )

        // Assert
        XCTAssertFalse(codestream.isEmpty)
        // Check SOC marker (0xFF4F)
        XCTAssertEqual(codestream[0], 0xFF)
        XCTAssertEqual(codestream[1], 0x4F)
        // Check EOC marker at end (0xFFD9)
        XCTAssertEqual(codestream[codestream.count - 2], 0xFF)
        XCTAssertEqual(codestream[codestream.count - 1], 0xD9)
    }

    func testCodestreamBuilderMultipleTiles() {
        // Arrange
        let builder = JP3DCodestreamBuilder()
        let tileData = [
            Data([0x01, 0x02]),
            Data([0x03, 0x04]),
            Data([0x05, 0x06]),
            Data([0x07, 0x08])
        ]

        // Act
        let codestream = builder.build(
            tileData: tileData,
            width: 8, height: 8, depth: 4,
            components: 1, bitDepth: 8,
            decompositionLevels: 2, isLossless: false
        )

        // Assert
        XCTAssertFalse(codestream.isEmpty)
        XCTAssertGreaterThan(codestream.count, 20)
    }

    // MARK: - 5. Core Encoder Tests

    func testEncoderLosslessSmallVolume() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertEqual(result.width, 8)
        XCTAssertEqual(result.height, 8)
        XCTAssertEqual(result.depth, 4)
        XCTAssertEqual(result.componentCount, 1)
        XCTAssertTrue(result.isLossless)
        XCTAssertGreaterThan(result.tileCount, 0)
    }

    func testEncoderLossySmallVolume() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossy())

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertFalse(result.isLossless)
    }

    func testEncoderVisuallyLossless() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 2)
        let encoder = JP3DEncoder(configuration: .visuallyLossless)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertFalse(result.isLossless)
    }

    func testEncoderMultiComponent() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 2, componentCount: 3)
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertEqual(result.componentCount, 3)
        XCTAssertFalse(result.data.isEmpty)
    }

    func testEncoderWithCustomTiling() async throws {
        // Arrange
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            tiling: JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4),
            qualityLayers: 1,
            levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert - 2x2x2 = 8 tiles
        XCTAssertEqual(result.tileCount, 8)
        XCTAssertFalse(result.data.isEmpty)
    }

    func testEncoderWithProgressCallback() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)
        let progressCount = ManagedAtomic(0)

        await encoder.setProgressCallback { _ in
            progressCount.increment()
        }

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertGreaterThan(progressCount.value, 0)
    }

    func testEncoderCompressionRatio() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertGreaterThan(result.compressionRatio, 0)
    }

    func testEncoderRawData() async throws {
        // Arrange
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act
        let result = try await encoder.encode(
            data: data, width: 8, height: 8, depth: 4
        )

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertEqual(result.width, 8)
        XCTAssertEqual(result.height, 8)
        XCTAssertEqual(result.depth, 4)
    }

    // MARK: - 6. Configuration Preset Tests

    func testLosslessPreset() {
        let config = JP3DEncoderConfiguration.lossless
        XCTAssertTrue(config.compressionMode.isLossless)
        XCTAssertEqual(config.qualityLayers, 1)
        XCTAssertEqual(config.levelsX, 3)
    }

    func testLossyPreset() {
        let config = JP3DEncoderConfiguration.lossy(psnr: 35.0)
        XCTAssertFalse(config.compressionMode.isLossless)
        XCTAssertEqual(config.qualityLayers, 3)
    }

    func testVisuallyLosslessPreset() {
        let config = JP3DEncoderConfiguration.visuallyLossless
        XCTAssertFalse(config.compressionMode.isLossless)
    }

    func testStreamingPreset() {
        let config = JP3DEncoderConfiguration.streaming
        XCTAssertEqual(config.progressionOrder, .slrcp)
        XCTAssertEqual(config.levelsX, 2)
        XCTAssertEqual(config.levelsY, 2)
    }

    func testConfigurationEquality() {
        let a = JP3DEncoderConfiguration.lossless
        let b = JP3DEncoderConfiguration.lossless
        XCTAssertEqual(a, b)
    }

    // MARK: - 7. Edge Case Tests

    func testEncoderSingleSliceVolume() async throws {
        // Arrange - depth == 1 should be encoded as 2D with JP3D wrapper
        let volume = makeTestVolume(width: 8, height: 8, depth: 1)
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertEqual(result.depth, 1)
    }

    func testEncoderSingleTile() async throws {
        // Arrange - tile size >= volume: no tiling overhead
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let config = JP3DEncoderConfiguration(
            tiling: JP3DTilingConfiguration(tileSizeX: 100, tileSizeY: 100, tileSizeZ: 100)
        )
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertEqual(result.tileCount, 1)
    }

    func testEncoderInvalidDimensions() async throws {
        // Arrange
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act & Assert - zero dimensions should fail
        do {
            _ = try await encoder.encode(data: [], width: 0, height: 8, depth: 4)
            XCTFail("Expected error for zero width")
        } catch {
            // Expected
        }
    }

    func testEncoderInvalidDataSize() async throws {
        // Arrange
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act & Assert - wrong data size should fail
        do {
            let wrongSizeData = [Float](repeating: 0, count: 10)
            _ = try await encoder.encode(data: wrongSizeData, width: 8, height: 8, depth: 4)
            XCTFail("Expected error for wrong data size")
        } catch {
            // Expected
        }
    }

    func testEncoderEmptyComponents() async throws {
        // Arrange - volume with no components
        let volume = J2KVolume(width: 4, height: 4, depth: 2, components: [])
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act & Assert
        do {
            _ = try await encoder.encode(volume)
            XCTFail("Expected error for empty components")
        } catch {
            // Expected
        }
    }

    func testEncoderNonPowerOf2Dimensions() async throws {
        // Arrange
        let volume = makeTestVolume(width: 7, height: 11, depth: 3)
        let config = JP3DEncoderConfiguration(
            tiling: JP3DTilingConfiguration(tileSizeX: 4, tileSizeY: 4, tileSizeZ: 2),
            levelsX: 1, levelsY: 1, levelsZ: 1
        )
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertEqual(result.width, 7)
        XCTAssertEqual(result.height, 11)
        XCTAssertEqual(result.depth, 3)
    }

    func testEncoderLargerVolume() async throws {
        // Arrange
        let volume = makeTestVolume(width: 32, height: 32, depth: 8)
        let config = JP3DEncoderConfiguration(
            tiling: JP3DTilingConfiguration(tileSizeX: 16, tileSizeY: 16, tileSizeZ: 4),
            levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert - 2x2x2 = 8 tiles
        XCTAssertEqual(result.tileCount, 8)
        XCTAssertFalse(result.data.isEmpty)
    }

    func testEncoderMixedBitDepth16() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 2, bitDepth: 16)
        let encoder = JP3DEncoder(configuration: .lossless)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
    }

    func testEncoderHTJ2KMode() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 2)
        let config = JP3DEncoderConfiguration(
            compressionMode: .losslessHTJ2K
        )
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertTrue(result.isLossless)
    }

    func testEncoderTargetBitrate() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .targetBitrate(bitsPerVoxel: 2.0)
        )
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertFalse(result.data.isEmpty)
        XCTAssertFalse(result.isLossless)
    }

    // MARK: - 8. Streaming Encoder Tests

    func testStreamWriterBasic() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 8, height: 8, depth: 4,
            componentCount: 1, bitDepth: 8
        )
        let writer = JP3DStreamWriter(configuration: config)
        let sliceSize = 8 * 8 * 1

        // Act
        for z in 0..<4 {
            let sliceData = [Float](repeating: Float(z), count: sliceSize)
            try await writer.addSlice(sliceData, atIndex: z)
        }
        let codestream = try await writer.finalize()

        // Assert
        XCTAssertFalse(codestream.isEmpty)
        let state = await writer.writerState
        XCTAssertEqual(state, .finalized)
    }

    func testStreamWriterOutOfOrder() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 4, height: 4, depth: 4,
            tiling: JP3DTilingConfiguration(tileSizeX: 4, tileSizeY: 4, tileSizeZ: 2)
        )
        let writer = JP3DStreamWriter(configuration: config)
        let sliceSize = 4 * 4 * 1

        // Act - add slices out of order
        try await writer.addSlice(
            [Float](repeating: 3, count: sliceSize), atIndex: 3
        )
        try await writer.addSlice(
            [Float](repeating: 1, count: sliceSize), atIndex: 1
        )
        try await writer.addSlice(
            [Float](repeating: 0, count: sliceSize), atIndex: 0
        )
        try await writer.addSlice(
            [Float](repeating: 2, count: sliceSize), atIndex: 2
        )
        let codestream = try await writer.finalize()

        // Assert
        XCTAssertFalse(codestream.isEmpty)
    }

    func testStreamWriterProgressCallback() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 4, height: 4, depth: 2
        )
        let writer = JP3DStreamWriter(configuration: config)
        let progressCount = ManagedAtomic(0)

        await writer.setProgressCallback { _ in
            progressCount.increment()
        }

        // Act
        let sliceSize = 4 * 4 * 1
        for z in 0..<2 {
            try await writer.addSlice(
                [Float](repeating: Float(z), count: sliceSize), atIndex: z
            )
        }
        _ = try await writer.finalize()

        // Assert
        XCTAssertEqual(progressCount.value, 2) // One per slice
    }

    func testStreamWriterCancel() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 4, height: 4, depth: 4
        )
        let writer = JP3DStreamWriter(configuration: config)

        // Act
        let sliceSize = 4 * 4 * 1
        try await writer.addSlice(
            [Float](repeating: 0, count: sliceSize), atIndex: 0
        )
        await writer.cancel()

        // Assert
        let state = await writer.writerState
        XCTAssertEqual(state, .cancelled)
    }

    func testStreamWriterInvalidSliceIndex() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 4, height: 4, depth: 2
        )
        let writer = JP3DStreamWriter(configuration: config)

        // Act & Assert
        do {
            let sliceSize = 4 * 4 * 1
            try await writer.addSlice(
                [Float](repeating: 0, count: sliceSize), atIndex: 5
            )
            XCTFail("Expected error for out-of-range slice index")
        } catch {
            // Expected
        }
    }

    func testStreamWriterInvalidSliceSize() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 4, height: 4, depth: 2
        )
        let writer = JP3DStreamWriter(configuration: config)

        // Act & Assert
        do {
            try await writer.addSlice([Float](repeating: 0, count: 5), atIndex: 0)
            XCTFail("Expected error for wrong slice data size")
        } catch {
            // Expected
        }
    }

    func testStreamWriterCannotAddAfterFinalize() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 4, height: 4, depth: 1
        )
        let writer = JP3DStreamWriter(configuration: config)
        let sliceSize = 4 * 4 * 1

        // Act
        try await writer.addSlice(
            [Float](repeating: 0, count: sliceSize), atIndex: 0
        )
        _ = try await writer.finalize()

        // Assert
        do {
            try await writer.addSlice(
                [Float](repeating: 0, count: sliceSize), atIndex: 0
            )
            XCTFail("Expected error for adding slice after finalize")
        } catch {
            // Expected
        }
    }

    func testStreamWriterReceivedSliceCount() async throws {
        // Arrange
        let config = JP3DStreamWriter.Configuration(
            width: 4, height: 4, depth: 4
        )
        let writer = JP3DStreamWriter(configuration: config)
        let sliceSize = 4 * 4 * 1

        // Act
        try await writer.addSlice(
            [Float](repeating: 0, count: sliceSize), atIndex: 0
        )
        try await writer.addSlice(
            [Float](repeating: 1, count: sliceSize), atIndex: 2
        )

        // Assert
        let count = await writer.receivedSliceCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - 9. Compression Mode Tests

    func testCompressionModeLossless() {
        XCTAssertTrue(JP3DCompressionMode.lossless.isLossless)
        XCTAssertFalse(JP3DCompressionMode.lossless.isHTJ2K)
    }

    func testCompressionModeLossy() {
        let mode = JP3DCompressionMode.lossy(psnr: 40.0)
        XCTAssertFalse(mode.isLossless)
        XCTAssertFalse(mode.isHTJ2K)
    }

    func testCompressionModeHTJ2K() {
        XCTAssertTrue(JP3DCompressionMode.losslessHTJ2K.isHTJ2K)
        XCTAssertTrue(JP3DCompressionMode.losslessHTJ2K.isLossless)
        XCTAssertTrue(JP3DCompressionMode.lossyHTJ2K(psnr: 40.0).isHTJ2K)
        XCTAssertFalse(JP3DCompressionMode.lossyHTJ2K(psnr: 40.0).isLossless)
    }

    func testCompressionModeTargetBitrate() {
        let mode = JP3DCompressionMode.targetBitrate(bitsPerVoxel: 1.5)
        XCTAssertFalse(mode.isLossless)
        XCTAssertFalse(mode.isHTJ2K)
    }

    func testCompressionModeVisuallyLossless() {
        XCTAssertFalse(JP3DCompressionMode.visuallyLossless.isLossless)
    }

    // MARK: - 10. Progression Order Tests

    func testAllProgressionOrdersExist() {
        let allOrders = JP3DProgressionOrder.allCases
        XCTAssertEqual(allOrders.count, 5)
    }

    func testProgressionOrderRawValues() {
        XCTAssertEqual(JP3DProgressionOrder.lrcps.rawValue, "LRCPS")
        XCTAssertEqual(JP3DProgressionOrder.rlcps.rawValue, "RLCPS")
        XCTAssertEqual(JP3DProgressionOrder.pcrls.rawValue, "PCRLS")
        XCTAssertEqual(JP3DProgressionOrder.slrcp.rawValue, "SLRCP")
        XCTAssertEqual(JP3DProgressionOrder.cprls.rawValue, "CPRLS")
    }

    // MARK: - 11. Encoding Stage Tests

    func testEncodingStageNames() {
        XCTAssertEqual(JP3DEncodingStage.preparation.rawValue, "Preparation")
        XCTAssertEqual(JP3DEncodingStage.waveletTransform.rawValue, "Wavelet Transform")
        XCTAssertEqual(JP3DEncodingStage.quantization.rawValue, "Quantization")
        XCTAssertEqual(JP3DEncodingStage.codestreamGeneration.rawValue, "Codestream Generation")
    }

    // MARK: - 12. Parallel Encoding Tests

    func testEncoderParallelConfiguration() {
        let config = JP3DEncoderConfiguration(parallelEncoding: true)
        XCTAssertTrue(config.parallelEncoding)

        let config2 = JP3DEncoderConfiguration(parallelEncoding: false)
        XCTAssertFalse(config2.parallelEncoding)
    }

    func testEncoderMultipleTilesParallel() async throws {
        // Arrange
        let volume = makeTestVolume(width: 32, height: 32, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            tiling: JP3DTilingConfiguration(tileSizeX: 16, tileSizeY: 16, tileSizeZ: 4),
            levelsX: 2, levelsY: 2, levelsZ: 1,
            parallelEncoding: true
        )
        let encoder = JP3DEncoder(configuration: config)

        // Act
        let result = try await encoder.encode(volume)

        // Assert
        XCTAssertEqual(result.tileCount, 4) // 2x2x1
        XCTAssertFalse(result.data.isEmpty)
    }
}
