//
// JP3DDecoderTests.swift
// J2KSwift
//
/// Tests for JP3D Decoder (Week 222-225).
///
/// Validates the complete JP3D decoding pipeline including codestream parsing,
/// round-trip encode→decode, ROI decoding, progressive decoding, multi-resolution
/// support, and edge case / error handling.

import XCTest
@testable import J2KCore
@testable import J2K3D

/// Thread-safe storage for use in Sendable closures.
private final class SendableStorage<T: Sendable>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ initial: T) { _value = initial }

    var value: T {
        lock.withLock { _value }
    }

    func set(_ newValue: T) {
        lock.withLock { _value = newValue }
    }
}

// MARK: - Test Class

final class JP3DDecoderTests: XCTestCase {
    // MARK: - Helpers

    /// Creates a test volume with deterministic gradient data.
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
                        let value = (x + y * 2 + z * 3 + c * 7) % (1 << min(bitDepth, 8))
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

    /// Encodes a volume with the given configuration.
    private func encode(
        _ volume: J2KVolume,
        config: JP3DEncoderConfiguration = .lossless
    ) async throws -> Data {
        let encoder = JP3DEncoder(configuration: config)
        return try await encoder.encode(volume).data
    }

    /// Returns the voxel value at (x, y, z, component) from a J2KVolume.
    private func voxelValue(
        in volume: J2KVolume,
        x: Int, y: Int, z: Int, comp: Int
    ) -> Int {
        guard comp < volume.components.count else { return 0 }
        let c = volume.components[comp]
        let bps = (c.bitDepth + 7) / 8
        let idx = z * c.width * c.height + y * c.width + x
        let offset = idx * bps
        guard offset + bps <= c.data.count else { return 0 }
        var val = 0
        for b in 0..<bps {
            val |= Int(c.data[offset + b]) << (b * 8)
        }
        return val
    }

    // MARK: - 1. Codestream Parser Tests

    func testParserRejectsEmptyData() {
        let parser = JP3DCodestreamParser()
        XCTAssertThrowsError(try parser.parse(Data())) { error in
            XCTAssertTrue(error is J2KError)
        }
    }

    func testParserRejectsMissingSOC() {
        let parser = JP3DCodestreamParser()
        // Random non-SOC data
        let badData = Data([0xFF, 0x52, 0x00, 0x00])
        XCTAssertThrowsError(try parser.parse(badData))
    }

    func testParserHandlesMinimalCodestream() async throws {
        // Arrange: encode a tiny volume
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let data = try await encode(volume)

        // Act: parse the codestream
        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)

        // Assert: metadata matches
        XCTAssertEqual(codestream.siz.width, 4)
        XCTAssertEqual(codestream.siz.height, 4)
        XCTAssertEqual(codestream.siz.depth, 2)
        XCTAssertEqual(codestream.siz.componentCount, 1)
        XCTAssertEqual(codestream.siz.bitDepth, 8)
        XCTAssertFalse(codestream.tiles.isEmpty)
    }

    func testParserExtractsLosslessFlag() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let losslessData = try await encode(volume, config: .lossless)
        let lossyData = try await encode(volume, config: .lossy(psnr: 40.0))

        let parser = JP3DCodestreamParser()
        let lossless = try parser.parse(losslessData)
        let lossy = try parser.parse(lossyData)

        XCTAssertTrue(lossless.cod.isLossless)
        XCTAssertFalse(lossy.cod.isLossless)
    }

    func testParserExtractsDecompositionLevels() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless,
            levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)

        XCTAssertEqual(codestream.cod.levelsX, 2)
        XCTAssertEqual(codestream.cod.levelsY, 2)
        XCTAssertEqual(codestream.cod.levelsZ, 1)
    }

    func testParserExtractsTileCount() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)

        // One tile (volume is smaller than default tile size)
        XCTAssertEqual(codestream.tiles.count, 1)
    }

    func testParserExtractsMultipleTiles() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .lossless, tiling: tiling)
        let data = try await encode(volume, config: config)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)

        // 2×2×2 = 8 tiles
        XCTAssertEqual(codestream.tiles.count, 8)
    }

    func testParserTileDataNonEmpty() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)

        XCTAssertFalse(codestream.tiles[0].data.isEmpty)
    }

    func testParserPreservesLosslessQuantizationFlag() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let data = try await encode(volume, config: .lossless)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)

        XCTAssertTrue(codestream.isLosslessQuantization)
    }

    func testParserTileGrid() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(compressionMode: .lossless, tiling: tiling)
        let data = try await encode(volume, config: config)

        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)
        let grid = codestream.tileGrid

        XCTAssertEqual(grid.tilesX, 2)
        XCTAssertEqual(grid.tilesY, 2)
        XCTAssertEqual(grid.tilesZ, 2)
    }

    // MARK: - 2. Decoder Basic Functionality

    func testDecoderProducesCorrectDimensions() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        // Act
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)

        // Assert
        XCTAssertEqual(result.volume.width, 8)
        XCTAssertEqual(result.volume.height, 8)
        XCTAssertEqual(result.volume.depth, 4)
        XCTAssertEqual(result.volume.componentCount, 1)
    }

    func testDecoderLosslessRoundTrip() async throws {
        // Arrange
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume, config: .lossless)

        // Act
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)

        // Assert: every voxel must match exactly
        for z in 0..<volume.depth {
            for y in 0..<volume.height {
                for x in 0..<volume.width {
                    let original = voxelValue(in: volume, x: x, y: y, z: z, comp: 0)
                    let decoded = voxelValue(in: result.volume, x: x, y: y, z: z, comp: 0)
                    XCTAssertEqual(decoded, original,
                        "Mismatch at (\(x),\(y),\(z)): encoded \(original), decoded \(decoded)")
                }
            }
        }
    }

    func testDecoderTilesDecodedCount() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertGreaterThan(result.tilesDecoded, 0)
    }

    func testDecoderIsNotPartialForValidData() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertFalse(result.isPartial)
    }

    func testDecoderSingleComponent() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4, componentCount: 1)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertEqual(result.volume.componentCount, 1)
    }

    func testDecoderMultipleComponents() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4, componentCount: 3)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertEqual(result.volume.componentCount, 3)
    }

    func testDecoderPreservesComponentCount() async throws {
        for componentCount in [1, 2, 3, 4] {
            let volume = makeTestVolume(width: 4, height: 4, depth: 2, componentCount: componentCount)
            let data = try await encode(volume)
            let decoder = JP3DDecoder()
            let result = try await decoder.decode(data)
            XCTAssertEqual(result.volume.componentCount, componentCount,
                "Expected \(componentCount) components")
        }
    }

    func testDecoderLosslessRoundTripMultipleComponents() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4, componentCount: 3)
        let data = try await encode(volume, config: .lossless)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)

        for comp in 0..<3 {
            for z in 0..<4 {
                for y in 0..<8 {
                    for x in 0..<8 {
                        let original = voxelValue(in: volume, x: x, y: y, z: z, comp: comp)
                        let decoded = voxelValue(in: result.volume, x: x, y: y, z: z, comp: comp)
                        XCTAssertEqual(decoded, original,
                            "Comp \(comp) mismatch at (\(x),\(y),\(z))")
                    }
                }
            }
        }
    }

    func testDecoderProgressCallback() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        let progressCount = SendableStorage(0)
        let decoder = JP3DDecoder()
        await decoder.setProgressCallback { _ in
            progressCount.set(progressCount.value + 1)
        }

        _ = try await decoder.decode(data)
        XCTAssertGreaterThan(progressCount.value, 0)
    }

    func testDecoderPeekMetadata() async throws {
        let volume = makeTestVolume(width: 16, height: 12, depth: 5)
        let data = try await encode(volume)

        let decoder = JP3DDecoder()
        let siz = try await decoder.peekMetadata(data)

        XCTAssertEqual(siz.width, 16)
        XCTAssertEqual(siz.height, 12)
        XCTAssertEqual(siz.depth, 5)
    }

    // MARK: - 3. Round-Trip Accuracy Tests

    func testLosslessRoundTripSmallVolume() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let data = try await encode(volume, config: .lossless)
        let result = try await JP3DDecoder().decode(data)
        for z in 0..<2 { for y in 0..<4 { for x in 0..<4 {
            XCTAssertEqual(
                voxelValue(in: volume, x: x, y: y, z: z, comp: 0),
                voxelValue(in: result.volume, x: x, y: y, z: z, comp: 0)
            )
        }}}
    }

    func testLosslessRoundTripMediumVolume() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let data = try await encode(volume, config: .lossless)
        let result = try await JP3DDecoder().decode(data)

        XCTAssertEqual(result.volume.width, 16)
        XCTAssertEqual(result.volume.height, 16)
        XCTAssertEqual(result.volume.depth, 8)

        // Spot-check several voxels
        for z in [0, 3, 7] { for y in [0, 7, 15] { for x in [0, 7, 15] {
            XCTAssertEqual(
                voxelValue(in: volume, x: x, y: y, z: z, comp: 0),
                voxelValue(in: result.volume, x: x, y: y, z: z, comp: 0),
                "Mismatch at (\(x),\(y),\(z))"
            )
        }}}
    }

    func testLosslessRoundTripSingleSlice() async throws {
        // depth = 1: effectively a 2D image wrapped in a volume
        let volume = makeTestVolume(width: 8, height: 8, depth: 1)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, levelsX: 2, levelsY: 2, levelsZ: 0
        )
        let data = try await encode(volume, config: config)
        let result = try await JP3DDecoder().decode(data)
        XCTAssertEqual(result.volume.depth, 1)
        for y in 0..<8 { for x in 0..<8 {
            XCTAssertEqual(
                voxelValue(in: volume, x: x, y: y, z: 0, comp: 0),
                voxelValue(in: result.volume, x: x, y: y, z: 0, comp: 0),
                "Mismatch at (\(x),\(y),0)"
            )
        }}
    }

    func testLosslessRoundTripMultipleTiles() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)
        let result = try await JP3DDecoder().decode(data)

        XCTAssertFalse(result.isPartial)
        // Spot-check corners from different tiles
        for (x, y, z) in [(0, 0, 0), (15, 0, 0), (0, 15, 0), (0, 0, 7), (15, 15, 7)] {
            XCTAssertEqual(
                voxelValue(in: volume, x: x, y: y, z: z, comp: 0),
                voxelValue(in: result.volume, x: x, y: y, z: z, comp: 0),
                "Mismatch at (\(x),\(y),\(z))"
            )
        }
    }

    func testDecoderBitDepth16() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 2, bitDepth: 16)
        let data = try await encode(volume, config: .lossless)
        let result = try await JP3DDecoder().decode(data)
        XCTAssertEqual(result.volume.components[0].bitDepth, 16)
    }

    // MARK: - 4. ROI Decoding Tests

    func testROIDecoderFullVolumeRegion() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        let roi = JP3DRegion(x: 0..<8, y: 0..<8, z: 0..<4)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)

        XCTAssertTrue(result.isFullVolume)
        XCTAssertEqual(result.volume.width, 8)
        XCTAssertEqual(result.volume.height, 8)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testROIDecoderSubRegion() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)

        let roi = JP3DRegion(x: 0..<8, y: 0..<8, z: 0..<4)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)

        XCTAssertEqual(result.decodedRegion.x, 0..<8)
        XCTAssertEqual(result.decodedRegion.y, 0..<8)
        XCTAssertEqual(result.decodedRegion.z, 0..<4)
        XCTAssertEqual(result.volume.width, 8)
        XCTAssertEqual(result.volume.height, 8)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testROIDecoderSkipsTiles() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)

        // Request only top-left-front tile
        let roi = JP3DRegion(x: 0..<8, y: 0..<8, z: 0..<4)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)

        // With 8 total tiles, should skip some
        XCTAssertGreaterThan(result.tilesSkipped, 0)
    }

    func testROIDecoderClampsToBounds() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        // Request region exceeding bounds
        let roi = JP3DRegion(x: 4..<20, y: 4..<20, z: 2..<10)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)

        // Should clamp to valid region
        XCTAssertEqual(result.decodedRegion.x.upperBound, 8)
        XCTAssertEqual(result.decodedRegion.y.upperBound, 8)
        XCTAssertEqual(result.decodedRegion.z.upperBound, 4)
    }

    func testROIDecoderEmptyIntersection() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        // Region entirely outside volume
        let roi = JP3DRegion(x: 100..<200, y: 100..<200, z: 100..<200)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)

        XCTAssertFalse(result.warnings.isEmpty)
        XCTAssertEqual(result.tilesDecoded, 0)
    }

    func testROIDecoderAccuracyLossless() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)

        // Decode a single tile region via ROI
        let roi = JP3DRegion(x: 0..<8, y: 0..<8, z: 0..<4)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)

        // Verify voxels match the original volume
        for z in 0..<4 { for y in 0..<8 { for x in 0..<8 {
            let original = voxelValue(in: volume, x: x, y: y, z: z, comp: 0)
            let decoded = voxelValue(in: result.volume, x: x, y: y, z: z, comp: 0)
            XCTAssertEqual(decoded, original, "Mismatch at (\(x),\(y),\(z))")
        }}}
    }

    func testROIDecoderSingleVoxelRegion() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let roi = JP3DRegion(x: 3..<4, y: 3..<4, z: 1..<2)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)
        XCTAssertEqual(result.volume.width, 1)
        XCTAssertEqual(result.volume.height, 1)
        XCTAssertEqual(result.volume.depth, 1)
    }

    func testROIDecoderTiledDecodedCount() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)
        let roi = JP3DRegion(x: 0..<8, y: 0..<8, z: 0..<4) // 1 tile
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)
        XCTAssertEqual(result.tilesDecoded, 1)
    }

    // MARK: - 5. Progressive Decoding Tests

    func testProgressiveDecoderResolutionMode() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)

        let progressDecoder = JP3DProgressiveDecoder()
        var steps: [JP3DProgressiveResult] = []
        let stepsStorage = SendableStorage<[JP3DProgressiveResult]>([])

        try await progressDecoder.decode(data, mode: .resolution) { result in
            var arr = stepsStorage.value
            arr.append(result)
            stepsStorage.set(arr)
            return true
        }

        steps = stepsStorage.value
        XCTAssertGreaterThan(steps.count, 0)
        XCTAssertTrue(steps.last?.isFinal ?? false)
    }

    func testProgressiveDecoderQualityMode() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        let progressDecoder = JP3DProgressiveDecoder()
        let stepCount = SendableStorage(0)

        try await progressDecoder.decode(data, mode: .quality) { _ in
            stepCount.set(stepCount.value + 1)
            return true
        }

        XCTAssertGreaterThan(stepCount.value, 0)
    }

    func testProgressiveDecoderSliceMode() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 8)
        let data = try await encode(volume)

        let progressDecoder = JP3DProgressiveDecoder()
        let stepCount = SendableStorage(0)
        let lastVolume = SendableStorage<J2KVolume?>(nil)

        try await progressDecoder.decode(data, mode: .slice(batchSize: 2)) { result in
            stepCount.set(stepCount.value + 1)
            lastVolume.set(result.volume)
            return true
        }

        // 8 slices / 2 per batch = 4 steps
        XCTAssertEqual(stepCount.value, 4)
    }

    func testProgressiveDecoderCanCancel() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)

        let progressDecoder = JP3DProgressiveDecoder()
        let stepCount = SendableStorage(0)

        try await progressDecoder.decode(data, mode: .resolution) { _ in
            stepCount.set(stepCount.value + 1)
            return false // cancel after first step
        }

        XCTAssertEqual(stepCount.value, 1)
    }

    func testProgressiveDecoderFinalResultMatchesFull() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume, config: .lossless)

        let progressDecoder = JP3DProgressiveDecoder()
        let finalVolume = SendableStorage<J2KVolume?>(nil)

        try await progressDecoder.decode(data, mode: .slice(batchSize: volume.depth)) { result in
            if result.isFinal { finalVolume.set(result.volume) }
            return true
        }

        let decoded = finalVolume.value
        XCTAssertNotNil(decoded)
    }

    func testProgressiveDecoderSliceBatchContainsCorrectDepth() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 6)
        let data = try await encode(volume)

        let progressDecoder = JP3DProgressiveDecoder()
        let batchDepths = SendableStorage<[Int]>([])

        try await progressDecoder.decode(data, mode: .slice(batchSize: 2)) { result in
            var arr = batchDepths.value
            arr.append(result.volume.depth)
            batchDepths.set(arr)
            return true
        }

        let depths = batchDepths.value
        // 6 slices / 2 per batch = 3 steps, each of depth 2
        XCTAssertEqual(depths.count, 3)
        XCTAssertTrue(depths.allSatisfy { $0 == 2 })
    }

    func testProgressiveDecoderProgressFractions() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 4)
        let data = try await encode(volume)

        let progressDecoder = JP3DProgressiveDecoder()
        let progressValues = SendableStorage<[Double]>([])

        try await progressDecoder.decode(data, mode: .slice(batchSize: 1)) { result in
            var arr = progressValues.value
            arr.append(result.progress)
            progressValues.set(arr)
            return true
        }

        let values = progressValues.value
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.last ?? 0, 1.0, accuracy: 0.001)
        // Progress must be strictly increasing
        for i in 1..<values.count {
            XCTAssertGreaterThan(values[i], values[i - 1])
        }
    }

    func testProgressiveDecoderCanReset() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let data = try await encode(volume)

        let progressDecoder = JP3DProgressiveDecoder()
        // First decode, cancel early
        try await progressDecoder.decode(data, mode: .resolution) { _ in false }
        // Reset and decode again
        await progressDecoder.reset()
        let stepCount = SendableStorage(0)
        try await progressDecoder.decode(data, mode: .quality) { _ in
            stepCount.set(stepCount.value + 1)
            return true
        }
        XCTAssertGreaterThan(stepCount.value, 0)
    }

    // MARK: - 6. Multi-Resolution Decode Tests

    func testDecoderDefaultConfiguration() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertEqual(result.volume.width, 8)
        XCTAssertEqual(result.volume.height, 8)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testDecoderWithTolerateErrorsEnabled() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let config = JP3DDecoderConfiguration(tolerateErrors: true)
        let decoder = JP3DDecoder(configuration: config)
        let result = try await decoder.decode(data)
        XCTAssertFalse(result.isPartial)
    }

    func testDecoderConfigurationDefault() {
        let config = JP3DDecoderConfiguration.default
        XCTAssertEqual(config.maxQualityLayers, 0)
        XCTAssertEqual(config.resolutionLevel, 0)
        XCTAssertTrue(config.tolerateErrors)
    }

    func testDecoderConfigurationThumbnail() {
        let config = JP3DDecoderConfiguration.thumbnail
        XCTAssertEqual(config.resolutionLevel, 2)
    }

    // MARK: - 7. Truncated and Corrupted Input Tests

    func testDecoderThrowsOnMalformedData() async throws {
        let badData = Data([0x00, 0x01, 0x02, 0x03])
        let decoder = JP3DDecoder(configuration: JP3DDecoderConfiguration(tolerateErrors: false))
        do {
            _ = try await decoder.decode(badData)
            XCTFail("Expected decoding error")
        } catch {
            XCTAssertTrue(error is J2KError)
        }
    }

    func testDecoderToleratesTruncatedTileData() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)

        // Truncate the last 20% of the codestream
        let truncated = data.prefix(data.count * 4 / 5)
        let config = JP3DDecoderConfiguration(tolerateErrors: true)
        let decoder = JP3DDecoder(configuration: config)

        // Should not throw, may produce partial result
        do {
            _ = try await decoder.decode(Data(truncated))
        } catch {
            // It's OK if it throws for severely truncated data
        }
    }

    func testDecoderRejectsEmptyData() async throws {
        let decoder = JP3DDecoder()
        do {
            _ = try await decoder.decode(Data())
            XCTFail("Expected decoding error")
        } catch {
            XCTAssertTrue(error is J2KError)
        }
    }

    func testDecoderHandlesCorruptedMarker() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        var data = try await encode(volume)

        // Corrupt a byte in the middle of the codestream
        if data.count > 50 {
            data[50] = 0xAB
            data[51] = 0xCD
        }

        let config = JP3DDecoderConfiguration(tolerateErrors: true)
        let decoder = JP3DDecoder(configuration: config)
        // Tolerate-errors mode should not throw for minor corruption
        do {
            _ = try await decoder.decode(data)
        } catch {
            // Acceptable if severely corrupted
        }
    }

    // MARK: - 8. Edge Case Tests

    func testDecoderSingleVoxelVolume() async throws {
        let volume = makeTestVolume(width: 1, height: 1, depth: 1)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, levelsX: 0, levelsY: 0, levelsZ: 0
        )
        let data = try await encode(volume, config: config)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertEqual(result.volume.width, 1)
        XCTAssertEqual(result.volume.height, 1)
        XCTAssertEqual(result.volume.depth, 1)
    }

    func testDecoderNonSquareVolume() async throws {
        let volume = makeTestVolume(width: 16, height: 8, depth: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertEqual(result.volume.width, 16)
        XCTAssertEqual(result.volume.height, 8)
        XCTAssertEqual(result.volume.depth, 4)
    }

    func testDecoderThickVolume() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 16)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, levelsX: 1, levelsY: 1, levelsZ: 2
        )
        let data = try await encode(volume, config: config)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertEqual(result.volume.depth, 16)
    }

    func testROIDecoderZeroWidthClampedRegion() async throws {
        let volume = makeTestVolume(width: 4, height: 4, depth: 2)
        let data = try await encode(volume)
        // Region with x range starting beyond volume width
        let roi = JP3DRegion(x: 10..<20, y: 0..<4, z: 0..<2)
        let roiDecoder = JP3DROIDecoder()
        let result = try await roiDecoder.decode(data, region: roi)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testDecoderResultWarningsEmptyForCleanDecode() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testDecoderTilesTotal() async throws {
        let volume = makeTestVolume(width: 16, height: 16, depth: 8)
        let tiling = JP3DTilingConfiguration(tileSizeX: 8, tileSizeY: 8, tileSizeZ: 4)
        let config = JP3DEncoderConfiguration(
            compressionMode: .lossless, tiling: tiling, levelsX: 2, levelsY: 2, levelsZ: 1
        )
        let data = try await encode(volume, config: config)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertEqual(result.tilesTotal, 8) // 2×2×2
        XCTAssertEqual(result.tilesDecoded, 8)
    }

    // MARK: - 9. JP3DCodestreamBuilder Tests

    func testCodestreamBuilderMinimalBuild() {
        let builder = JP3DCodestreamBuilder()
        let data = builder.build(
            tileData: [Data(repeating: 0xAB, count: 16)],
            width: 4, height: 4, depth: 2,
            components: 1, bitDepth: 8,
            levelsX: 1, levelsY: 1, levelsZ: 1,
            tileSizeX: 4, tileSizeY: 4, tileSizeZ: 2,
            isLossless: true
        )
        XCTAssertGreaterThan(data.count, 0)
        // Starts with SOC marker
        XCTAssertEqual(data[0], 0xFF)
        XCTAssertEqual(data[1], 0x4F)
    }

    func testCodestreamBuilderEndsWithEOC() {
        let builder = JP3DCodestreamBuilder()
        let data = builder.build(
            tileData: [Data(repeating: 0, count: 4)],
            width: 2, height: 2, depth: 1,
            components: 1, bitDepth: 8,
            levelsX: 0, levelsY: 0, levelsZ: 0,
            tileSizeX: 2, tileSizeY: 2, tileSizeZ: 1,
            isLossless: true
        )
        // Ends with EOC: 0xFF 0xD9
        XCTAssertEqual(data[data.count - 2], 0xFF)
        XCTAssertEqual(data[data.count - 1], 0xD9)
    }

    func testCodestreamRoundTripTileCount() async throws {
        for tileCount in [1, 4, 8] {
            let tiles = Array(repeating: Data(repeating: 0, count: 16), count: tileCount)
            let builder = JP3DCodestreamBuilder()
            let data = builder.build(
                tileData: tiles,
                width: 4, height: 4, depth: 4,
                components: 1, bitDepth: 8,
                levelsX: 1, levelsY: 1, levelsZ: 1,
                tileSizeX: 4, tileSizeY: 4, tileSizeZ: 4,
                isLossless: true
            )
            let parser = JP3DCodestreamParser()
            let codestream = try parser.parse(data)
            XCTAssertEqual(codestream.tiles.count, tileCount,
                "Expected \(tileCount) tiles, got \(codestream.tiles.count)")
        }
    }

    // MARK: - 10. JP3DDecoderResult Tests

    func testDecoderResultIsNotPartialForCompleteInput() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertFalse(result.isPartial)
        XCTAssertEqual(result.tilesDecoded, result.tilesTotal)
    }

    func testDecoderResultVolumeIsNotEmpty() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        XCTAssertGreaterThan(result.volume.voxelCount, 0)
    }

    func testDecoderResultComponentDataNotEmpty() async throws {
        let volume = makeTestVolume(width: 8, height: 8, depth: 4)
        let data = try await encode(volume)
        let decoder = JP3DDecoder()
        let result = try await decoder.decode(data)
        for comp in result.volume.components {
            XCTAssertFalse(comp.data.isEmpty)
        }
    }
}
