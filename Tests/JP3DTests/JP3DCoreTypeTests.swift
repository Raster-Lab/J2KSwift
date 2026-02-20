//
// JP3DCoreTypeTests.swift
// J2KSwift
//
/// Tests for JP3D core types (Week 211-213).
///
/// Validates volume construction, component configuration, 3D spatial types,
/// tiling configuration, compression modes, and edge case handling.

import XCTest
@testable import J2KCore
@testable import J2K3D

final class JP3DCoreTypeTests: XCTestCase {
    // MARK: - J2KVolume Construction

    func testVolumeBasicConstruction() throws {
        let volume = J2KVolume(width: 256, height: 256, depth: 128, componentCount: 1, bitDepth: 16)

        XCTAssertEqual(volume.width, 256)
        XCTAssertEqual(volume.height, 256)
        XCTAssertEqual(volume.depth, 128)
        XCTAssertEqual(volume.componentCount, 1)
        XCTAssertEqual(volume.components[0].bitDepth, 16)
        XCTAssertFalse(volume.components[0].signed)
        XCTAssertEqual(volume.voxelCount, 256 * 256 * 128)
    }

    func testVolumeRGBConstruction() throws {
        let volume = J2KVolume(width: 64, height: 64, depth: 32, componentCount: 3, bitDepth: 8)

        XCTAssertEqual(volume.componentCount, 3)
        for i in 0..<3 {
            XCTAssertEqual(volume.components[i].index, i)
            XCTAssertEqual(volume.components[i].bitDepth, 8)
            XCTAssertEqual(volume.components[i].width, 64)
            XCTAssertEqual(volume.components[i].height, 64)
            XCTAssertEqual(volume.components[i].depth, 32)
        }
    }

    func testVolumeSignedConstruction() throws {
        let volume = J2KVolume(width: 10, height: 10, depth: 10, componentCount: 1, bitDepth: 12, signed: true)

        XCTAssertTrue(volume.components[0].signed)
        XCTAssertEqual(volume.components[0].maxValue, 2047)
        XCTAssertEqual(volume.components[0].minValue, -2048)
    }

    func testVolumeFullInitializer() throws {
        let component = J2KVolumeComponent(
            index: 0, bitDepth: 16, signed: true, width: 100, height: 100, depth: 50,
            subsamplingX: 2, subsamplingY: 2, subsamplingZ: 1
        )
        let volume = J2KVolume(
            width: 100, height: 100, depth: 50,
            components: [component],
            spacingX: 0.5, spacingY: 0.5, spacingZ: 1.25,
            originX: 10.0, originY: 20.0, originZ: -5.0
        )

        XCTAssertEqual(volume.spacingX, 0.5)
        XCTAssertEqual(volume.spacingY, 0.5)
        XCTAssertEqual(volume.spacingZ, 1.25)
        XCTAssertEqual(volume.originX, 10.0)
        XCTAssertEqual(volume.originY, 20.0)
        XCTAssertEqual(volume.originZ, -5.0)
        XCTAssertTrue(volume.hasSpacing)
    }

    func testVolumeConvenienceProperties() throws {
        let volume = J2KVolume(width: 100, height: 100, depth: 1, componentCount: 1, bitDepth: 8)

        XCTAssertTrue(volume.isSingleSlice)
        XCTAssertEqual(volume.voxelCount, 10000)
        XCTAssertFalse(volume.hasSpacing)
    }

    func testVolumeEstimatedMemorySize() throws {
        let volume = J2KVolume(width: 256, height: 256, depth: 128, componentCount: 1, bitDepth: 16)
        // 256 * 256 * 128 * 2 bytes = 16,777,216
        XCTAssertEqual(volume.estimatedMemorySize, 256 * 256 * 128 * 2)
    }

    func testVolumeEstimatedMemorySizeMultipleComponents() throws {
        let volume = J2KVolume(width: 64, height: 64, depth: 32, componentCount: 3, bitDepth: 8)
        // 3 components × 64 * 64 * 32 * 1 byte = 393,216
        XCTAssertEqual(volume.estimatedMemorySize, 3 * 64 * 64 * 32)
    }

    func testVolumeValidation() throws {
        let volume = J2KVolume(width: 256, height: 256, depth: 128, componentCount: 1, bitDepth: 16)
        XCTAssertNoThrow(try volume.validate())
    }

    // MARK: - J2KVolume Edge Cases

    func testVolumeEmptyDimensionsRejected() throws {
        let volume = J2KVolume(width: 0, height: 0, depth: 0, components: [
            J2KVolumeComponent(index: 0, bitDepth: 8, signed: false, width: 0, height: 0, depth: 0)
        ])

        XCTAssertThrowsError(try volume.validate()) { error in
            guard case J2KError.invalidDimensions = error else {
                XCTFail("Expected invalidDimensions error, got \(error)")
                return
            }
        }
    }

    func testVolumeSingleVoxel() throws {
        let volume = J2KVolume(width: 1, height: 1, depth: 1, componentCount: 1, bitDepth: 8)

        XCTAssertEqual(volume.voxelCount, 1)
        XCTAssertTrue(volume.isSingleSlice)
        XCTAssertNoThrow(try volume.validate())
    }

    func testVolumeThinZAxis() throws {
        // 1024×1024×1: effectively 2D, should work as degenerate case
        let volume = J2KVolume(width: 1024, height: 1024, depth: 1, componentCount: 1, bitDepth: 8)

        XCTAssertTrue(volume.isSingleSlice)
        XCTAssertEqual(volume.voxelCount, 1024 * 1024)
        XCTAssertNoThrow(try volume.validate())
    }

    func testVolumeNonUniformDimensions() throws {
        // 2×2×10000: extreme anisotropy
        let volume = J2KVolume(width: 2, height: 2, depth: 10000, componentCount: 1, bitDepth: 16)

        XCTAssertEqual(volume.voxelCount, 40000)
        XCTAssertNoThrow(try volume.validate())
    }

    func testVolumeZeroComponents() throws {
        let volume = J2KVolume(width: 10, height: 10, depth: 10, components: [])

        XCTAssertThrowsError(try volume.validate()) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error, got \(error)")
                return
            }
        }
    }

    func testVolumeNegativeSpacing() throws {
        let volume = J2KVolume(
            width: 10, height: 10, depth: 10,
            components: [J2KVolumeComponent(index: 0, bitDepth: 8, signed: false, width: 10, height: 10, depth: 10)],
            spacingX: -1.0, spacingY: 1.0, spacingZ: 1.0
        )

        XCTAssertThrowsError(try volume.validate()) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error, got \(error)")
                return
            }
        }
    }

    func testVolumeConvenienceInitClampsValues() throws {
        // Negative/zero values should be clamped
        let volume = J2KVolume(width: -5, height: 0, depth: -1, componentCount: 0, bitDepth: 0)

        XCTAssertEqual(volume.width, 1)
        XCTAssertEqual(volume.height, 1)
        XCTAssertEqual(volume.depth, 1)
        XCTAssertEqual(volume.componentCount, 1)
        XCTAssertEqual(volume.components[0].bitDepth, 1)
    }

    func testVolumeBitDepthClamping() throws {
        let volume = J2KVolume(width: 10, height: 10, depth: 10, componentCount: 1, bitDepth: 50)
        XCTAssertEqual(volume.components[0].bitDepth, 38)

        let volume2 = J2KVolume(width: 10, height: 10, depth: 10, componentCount: 1, bitDepth: -5)
        XCTAssertEqual(volume2.components[0].bitDepth, 1)
    }

    func testVolumeInvalidComponentBitDepthRejected() throws {
        let badComponent = J2KVolumeComponent(
            index: 0, bitDepth: 0, signed: false, width: 10, height: 10, depth: 10
        )
        let volume = J2KVolume(width: 10, height: 10, depth: 10, components: [badComponent])

        XCTAssertThrowsError(try volume.validate()) { error in
            guard case J2KError.invalidBitDepth = error else {
                XCTFail("Expected invalidBitDepth error, got \(error)")
                return
            }
        }
    }

    func testVolumeOverflowProtection() throws {
        let volume = J2KVolume(
            width: Int.max, height: Int.max, depth: Int.max,
            components: [J2KVolumeComponent(
                index: 0, bitDepth: 8, signed: false,
                width: Int.max, height: Int.max, depth: Int.max
            )]
        )

        XCTAssertThrowsError(try volume.validate()) { error in
            guard case J2KError.invalidDimensions = error else {
                XCTFail("Expected invalidDimensions error for overflow, got \(error)")
                return
            }
        }
    }

    // MARK: - J2KVolumeComponent

    func testVolumeComponentProperties() throws {
        let component = J2KVolumeComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 100, height: 100, depth: 50
        )

        XCTAssertEqual(component.voxelCount, 500_000)
        XCTAssertFalse(component.isSubsampled)
        XCTAssertEqual(component.maxValue, 255)
        XCTAssertEqual(component.minValue, 0)
        XCTAssertEqual(component.bytesPerSample, 1)
    }

    func testVolumeComponentSubsampled() throws {
        let component = J2KVolumeComponent(
            index: 0, bitDepth: 8, signed: false,
            width: 50, height: 50, depth: 50,
            subsamplingX: 2, subsamplingY: 2, subsamplingZ: 1
        )

        XCTAssertTrue(component.isSubsampled)
    }

    func testVolumeComponentBytesPerSample() throws {
        XCTAssertEqual(
            J2KVolumeComponent(index: 0, bitDepth: 1, signed: false, width: 1, height: 1, depth: 1).bytesPerSample, 1
        )
        XCTAssertEqual(
            J2KVolumeComponent(index: 0, bitDepth: 8, signed: false, width: 1, height: 1, depth: 1).bytesPerSample, 1
        )
        XCTAssertEqual(
            J2KVolumeComponent(index: 0, bitDepth: 9, signed: false, width: 1, height: 1, depth: 1).bytesPerSample, 2
        )
        XCTAssertEqual(
            J2KVolumeComponent(index: 0, bitDepth: 16, signed: false, width: 1, height: 1, depth: 1).bytesPerSample, 2
        )
        XCTAssertEqual(
            J2KVolumeComponent(index: 0, bitDepth: 32, signed: false, width: 1, height: 1, depth: 1).bytesPerSample, 4
        )
        XCTAssertEqual(
            J2KVolumeComponent(index: 0, bitDepth: 38, signed: false, width: 1, height: 1, depth: 1).bytesPerSample, 5
        )
    }

    // MARK: - J2KVolumeMetadata

    func testVolumeMetadataConstruction() throws {
        let metadata = J2KVolumeMetadata(
            modality: .ct,
            patientID: "ANON-001",
            studyDescription: "Chest CT",
            sliceThickness: 1.25,
            windowCenter: 40.0,
            windowWidth: 400.0
        )

        XCTAssertEqual(metadata.modality, .ct)
        XCTAssertEqual(metadata.patientID, "ANON-001")
        XCTAssertEqual(metadata.studyDescription, "Chest CT")
        XCTAssertEqual(metadata.sliceThickness, 1.25)
        XCTAssertEqual(metadata.windowCenter, 40.0)
        XCTAssertEqual(metadata.windowWidth, 400.0)
    }

    func testVolumeMetadataEmpty() throws {
        let metadata = J2KVolumeMetadata.empty

        XCTAssertEqual(metadata.modality, .unknown)
        XCTAssertNil(metadata.patientID)
        XCTAssertNil(metadata.studyDescription)
        XCTAssertNil(metadata.sliceThickness)
        XCTAssertTrue(metadata.customMetadata.isEmpty)
    }

    func testVolumeMetadataCustomFields() throws {
        let metadata = J2KVolumeMetadata(
            customMetadata: ["dicomTag": "0008,0060", "resolution": "high"]
        )

        XCTAssertEqual(metadata.customMetadata["dicomTag"], "0008,0060")
        XCTAssertEqual(metadata.customMetadata["resolution"], "high")
    }

    func testVolumeModalityAllCases() throws {
        XCTAssertEqual(J2KVolumeModality.allCases.count, 11)
        XCTAssertEqual(J2KVolumeModality.ct.rawValue, "CT")
        XCTAssertEqual(J2KVolumeModality.mri.rawValue, "MR")
        XCTAssertEqual(J2KVolumeModality.pet.rawValue, "PT")
        XCTAssertEqual(J2KVolumeModality.unknown.rawValue, "OT")
    }

    // MARK: - JP3DRegion

    func testRegionBasicConstruction() throws {
        let region = JP3DRegion(x: 0..<128, y: 0..<128, z: 10..<20)

        XCTAssertEqual(region.width, 128)
        XCTAssertEqual(region.height, 128)
        XCTAssertEqual(region.depth, 10)
        XCTAssertEqual(region.volume, 128 * 128 * 10)
        XCTAssertFalse(region.isEmpty)
    }

    func testRegionOriginConstruction() throws {
        let region = JP3DRegion(originX: 10, originY: 20, originZ: 5, width: 50, height: 40, depth: 30)

        XCTAssertEqual(region.x, 10..<60)
        XCTAssertEqual(region.y, 20..<60)
        XCTAssertEqual(region.z, 5..<35)
        XCTAssertEqual(region.width, 50)
        XCTAssertEqual(region.height, 40)
        XCTAssertEqual(region.depth, 30)
    }

    func testRegionIntersection() throws {
        let a = JP3DRegion(x: 0..<100, y: 0..<100, z: 0..<50)
        let b = JP3DRegion(x: 50..<150, y: 50..<150, z: 25..<75)

        let intersection = a.intersection(b)
        XCTAssertNotNil(intersection)
        XCTAssertEqual(intersection?.x, 50..<100)
        XCTAssertEqual(intersection?.y, 50..<100)
        XCTAssertEqual(intersection?.z, 25..<50)
    }

    func testRegionNoIntersection() throws {
        let a = JP3DRegion(x: 0..<10, y: 0..<10, z: 0..<10)
        let b = JP3DRegion(x: 20..<30, y: 20..<30, z: 20..<30)

        XCTAssertNil(a.intersection(b))
    }

    func testRegionContainsPoint() throws {
        let region = JP3DRegion(x: 10..<20, y: 10..<20, z: 5..<15)

        XCTAssertTrue(region.contains(x: 15, y: 15, z: 10))
        XCTAssertTrue(region.contains(x: 10, y: 10, z: 5))   // inclusive lower bound
        XCTAssertFalse(region.contains(x: 20, y: 15, z: 10)) // exclusive upper bound
        XCTAssertFalse(region.contains(x: 5, y: 15, z: 10))  // outside
    }

    func testRegionClamped() throws {
        let region = JP3DRegion(x: -10..<300, y: -5..<200, z: -1..<150)
        let clamped = region.clamped(toWidth: 256, height: 128, depth: 64)

        XCTAssertEqual(clamped.x, 0..<256)
        XCTAssertEqual(clamped.y, 0..<128)
        XCTAssertEqual(clamped.z, 0..<64)
    }

    func testRegionEmpty() throws {
        let region = JP3DRegion(x: 10..<10, y: 0..<5, z: 0..<5)
        XCTAssertTrue(region.isEmpty)
        XCTAssertEqual(region.volume, 0)
    }

    // MARK: - JP3DTile

    func testTileConstruction() throws {
        let region = JP3DRegion(x: 0..<256, y: 0..<256, z: 0..<16)
        let tile = JP3DTile(indexX: 0, indexY: 0, indexZ: 0, region: region)

        XCTAssertEqual(tile.indexX, 0)
        XCTAssertEqual(tile.width, 256)
        XCTAssertEqual(tile.height, 256)
        XCTAssertEqual(tile.depth, 16)
    }

    func testTileLinearIndex() throws {
        let region = JP3DRegion(x: 0..<10, y: 0..<10, z: 0..<10)
        let tile = JP3DTile(indexX: 2, indexY: 3, indexZ: 1, region: region)

        // Linear index = z * tilesX * tilesY + y * tilesX + x
        // = 1 * 4 * 4 + 3 * 4 + 2 = 16 + 12 + 2 = 30
        XCTAssertEqual(tile.linearIndex(tilesX: 4, tilesY: 4), 30)
    }

    // MARK: - JP3DPrecinct

    func testPrecinctConstruction() throws {
        let region = JP3DRegion(x: 0..<64, y: 0..<64, z: 0..<8)
        let precinct = JP3DPrecinct(
            indexX: 0, indexY: 0, indexZ: 0,
            resolutionLevel: 2, componentIndex: 0,
            region: region
        )

        XCTAssertEqual(precinct.resolutionLevel, 2)
        XCTAssertEqual(precinct.componentIndex, 0)
        XCTAssertEqual(precinct.region.width, 64)
    }

    func testPrecinctLinearIndex() throws {
        let region = JP3DRegion(x: 0..<10, y: 0..<10, z: 0..<10)
        let precinct = JP3DPrecinct(
            indexX: 1, indexY: 2, indexZ: 3,
            resolutionLevel: 0, componentIndex: 0,
            region: region
        )

        // 3 * 4 * 4 + 2 * 4 + 1 = 48 + 8 + 1 = 57
        XCTAssertEqual(precinct.linearIndex(precinctsX: 4, precinctsY: 4), 57)
    }

    // MARK: - JP3DTilingConfiguration

    func testTilingConfigurationPresets() throws {
        let defaultConfig = JP3DTilingConfiguration.default
        XCTAssertEqual(defaultConfig.tileSizeX, 256)
        XCTAssertEqual(defaultConfig.tileSizeY, 256)
        XCTAssertEqual(defaultConfig.tileSizeZ, 16)

        let streaming = JP3DTilingConfiguration.streaming
        XCTAssertEqual(streaming.tileSizeX, 128)
        XCTAssertEqual(streaming.tileSizeY, 128)
        XCTAssertEqual(streaming.tileSizeZ, 8)

        let batch = JP3DTilingConfiguration.batch
        XCTAssertEqual(batch.tileSizeX, 512)
        XCTAssertEqual(batch.tileSizeY, 512)
        XCTAssertEqual(batch.tileSizeZ, 32)
    }

    func testTilingConfigurationTileGrid() throws {
        let config = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 16)
        let grid = config.tileGrid(volumeWidth: 256, volumeHeight: 256, volumeDepth: 128)

        XCTAssertEqual(grid.tilesX, 4)
        XCTAssertEqual(grid.tilesY, 4)
        XCTAssertEqual(grid.tilesZ, 8)
    }

    func testTilingConfigurationTotalTiles() throws {
        let config = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 16)
        let total = config.totalTiles(volumeWidth: 256, volumeHeight: 256, volumeDepth: 128)

        XCTAssertEqual(total, 128) // 4 * 4 * 8
    }

    func testTilingConfigurationOddDimensions() throws {
        // 100×100×17 with 64×64×16 tiles → 2×2×2 = 8 tiles
        let config = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 16)
        let grid = config.tileGrid(volumeWidth: 100, volumeHeight: 100, volumeDepth: 17)

        XCTAssertEqual(grid.tilesX, 2)
        XCTAssertEqual(grid.tilesY, 2)
        XCTAssertEqual(grid.tilesZ, 2) // ceil(17/16) = 2
    }

    func testTilingConfigurationBoundaryTile() throws {
        let config = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 16)
        // Last tile in a 100-wide volume: x = 64..<100 (36 voxels, not 64)
        let tile = config.tile(atX: 1, y: 0, z: 0, volumeWidth: 100, volumeHeight: 100, volumeDepth: 17)

        XCTAssertEqual(tile.region.x, 64..<100)
        XCTAssertEqual(tile.width, 36)
    }

    func testTilingConfigurationAllTiles() throws {
        let config = JP3DTilingConfiguration(tileSizeX: 128, tileSizeY: 128, tileSizeZ: 64)
        let tiles = config.allTiles(volumeWidth: 256, volumeHeight: 256, volumeDepth: 128)

        XCTAssertEqual(tiles.count, 8) // 2 * 2 * 2
        // Verify all tiles cover the volume
        for tile in tiles {
            XCTAssertGreaterThan(tile.width, 0)
            XCTAssertGreaterThan(tile.height, 0)
            XCTAssertGreaterThan(tile.depth, 0)
        }
    }

    func testTilingConfigurationTilesIntersectingRegion() throws {
        let config = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 16)
        let roi = JP3DRegion(x: 50..<120, y: 50..<120, z: 10..<20)

        let tiles = config.tilesIntersecting(
            region: roi, volumeWidth: 256, volumeHeight: 256, volumeDepth: 128
        )

        // ROI spans tiles [0,1] in X, [0,1] in Y, [0,1] in Z → 2×2×2 = 8 tiles
        XCTAssertEqual(tiles.count, 8)
    }

    func testTilingConfigurationVolumeSmallerThanTile() throws {
        // Volume smaller than one tile
        let config = JP3DTilingConfiguration(tileSizeX: 256, tileSizeY: 256, tileSizeZ: 16)
        let grid = config.tileGrid(volumeWidth: 10, volumeHeight: 10, volumeDepth: 5)

        XCTAssertEqual(grid.tilesX, 1)
        XCTAssertEqual(grid.tilesY, 1)
        XCTAssertEqual(grid.tilesZ, 1)
    }

    func testTilingConfigurationValidation() throws {
        XCTAssertNoThrow(try JP3DTilingConfiguration.default.validate())

        // Zero tile size is clamped to 1 in init, so validate should pass
        let config = JP3DTilingConfiguration(tileSizeX: 0, tileSizeY: 0, tileSizeZ: 0)
        XCTAssertNoThrow(try config.validate())
        XCTAssertEqual(config.tileSizeX, 1)
    }

    func testTilingConfigurationPrimeDimensions() throws {
        // 127×131×17 with 64×64×16 tiles
        let config = JP3DTilingConfiguration(tileSizeX: 64, tileSizeY: 64, tileSizeZ: 16)
        let tiles = config.allTiles(volumeWidth: 127, volumeHeight: 131, volumeDepth: 17)

        // 2×3×2 = 12 tiles
        let grid = config.tileGrid(volumeWidth: 127, volumeHeight: 131, volumeDepth: 17)
        XCTAssertEqual(grid.tilesX, 2)  // ceil(127/64)
        XCTAssertEqual(grid.tilesY, 3)  // ceil(131/64)
        XCTAssertEqual(grid.tilesZ, 2)  // ceil(17/16)
        XCTAssertEqual(tiles.count, 12)

        // Verify last tile along X is partial
        let lastX = tiles.first(where: { $0.indexX == 1 && $0.indexY == 0 && $0.indexZ == 0 })
        XCTAssertNotNil(lastX)
        XCTAssertEqual(lastX?.width, 63) // 127 - 64 = 63
    }

    // MARK: - JP3DProgressionOrder

    func testProgressionOrderAllCases() throws {
        XCTAssertEqual(JP3DProgressionOrder.allCases.count, 5)
        XCTAssertEqual(JP3DProgressionOrder.lrcps.rawValue, "LRCPS")
        XCTAssertEqual(JP3DProgressionOrder.rlcps.rawValue, "RLCPS")
        XCTAssertEqual(JP3DProgressionOrder.pcrls.rawValue, "PCRLS")
        XCTAssertEqual(JP3DProgressionOrder.slrcp.rawValue, "SLRCP")
        XCTAssertEqual(JP3DProgressionOrder.cprls.rawValue, "CPRLS")
    }

    // MARK: - JP3DCompressionMode

    func testCompressionModeLossless() throws {
        let mode = JP3DCompressionMode.lossless
        XCTAssertTrue(mode.isLossless)
        XCTAssertFalse(mode.isHTJ2K)
    }

    func testCompressionModeLossy() throws {
        let mode = JP3DCompressionMode.lossy(psnr: 45.0)
        XCTAssertFalse(mode.isLossless)
        XCTAssertFalse(mode.isHTJ2K)
    }

    func testCompressionModeTargetBitrate() throws {
        let mode = JP3DCompressionMode.targetBitrate(bitsPerVoxel: 2.5)
        XCTAssertFalse(mode.isLossless)
        XCTAssertFalse(mode.isHTJ2K)
    }

    func testCompressionModeVisuallyLossless() throws {
        let mode = JP3DCompressionMode.visuallyLossless
        XCTAssertFalse(mode.isLossless)
        XCTAssertFalse(mode.isHTJ2K)
    }

    func testCompressionModeLosslessHTJ2K() throws {
        let mode = JP3DCompressionMode.losslessHTJ2K
        XCTAssertTrue(mode.isLossless)
        XCTAssertTrue(mode.isHTJ2K)
    }

    func testCompressionModeLossyHTJ2K() throws {
        let mode = JP3DCompressionMode.lossyHTJ2K(psnr: 50.0)
        XCTAssertFalse(mode.isLossless)
        XCTAssertTrue(mode.isHTJ2K)
    }

    // MARK: - J2K3DCoefficients

    func testCoefficientsConstruction() throws {
        let coefficients = J2K3DCoefficients(width: 64, height: 64, depth: 32, decompositionLevels: 3)

        XCTAssertEqual(coefficients.width, 64)
        XCTAssertEqual(coefficients.height, 64)
        XCTAssertEqual(coefficients.depth, 32)
        XCTAssertEqual(coefficients.decompositionLevels, 3)
        XCTAssertEqual(coefficients.count, 64 * 64 * 32)
        XCTAssertEqual(coefficients.data.count, 64 * 64 * 32)
    }

    func testCoefficientsSubscript() throws {
        var coefficients = J2K3DCoefficients(width: 4, height: 4, depth: 4, decompositionLevels: 1)

        coefficients[1, 2, 3] = 42.5
        XCTAssertEqual(coefficients[1, 2, 3], 42.5)
        XCTAssertEqual(coefficients[0, 0, 0], 0.0)
    }

    func testCoefficientsClampsDimensions() throws {
        let coefficients = J2K3DCoefficients(width: -1, height: 0, depth: -5, decompositionLevels: -2)

        XCTAssertEqual(coefficients.width, 1)
        XCTAssertEqual(coefficients.height, 1)
        XCTAssertEqual(coefficients.depth, 1)
        XCTAssertEqual(coefficients.decompositionLevels, 0)
    }

    // MARK: - JP3DSubband

    func testSubbandAllCases() throws {
        XCTAssertEqual(JP3DSubband.allCases.count, 8)
        XCTAssertEqual(JP3DSubband.lll.rawValue, "LLL")
        XCTAssertEqual(JP3DSubband.hhh.rawValue, "HHH")
    }

    // MARK: - Sendable Conformance

    func testSendableConformance() throws {
        // Verify all types can be used across concurrency boundaries.
        // This test compiles only if the types conform to Sendable.
        let volume = J2KVolume(width: 10, height: 10, depth: 10, componentCount: 1)
        let metadata = J2KVolumeMetadata.empty
        let region = JP3DRegion(x: 0..<10, y: 0..<10, z: 0..<10)
        let tile = JP3DTile(indexX: 0, indexY: 0, indexZ: 0, region: region)
        let precinct = JP3DPrecinct(
            indexX: 0, indexY: 0, indexZ: 0,
            resolutionLevel: 0, componentIndex: 0, region: region
        )
        let config = JP3DTilingConfiguration.default
        let mode = JP3DCompressionMode.lossless
        let order = JP3DProgressionOrder.lrcps
        let coefficients = J2K3DCoefficients(width: 1, height: 1, depth: 1, decompositionLevels: 0)
        let subband = JP3DSubband.lll

        // Sendable check: assign to nonisolated(unsafe) let to verify
        let _: any Sendable = volume
        let _: any Sendable = metadata
        let _: any Sendable = region
        let _: any Sendable = tile
        let _: any Sendable = precinct
        let _: any Sendable = config
        let _: any Sendable = mode
        let _: any Sendable = order
        let _: any Sendable = coefficients
        let _: any Sendable = subband
    }

    // MARK: - Equatable Conformance

    func testVolumeEquatable() throws {
        let v1 = J2KVolume(width: 10, height: 10, depth: 10, componentCount: 1, bitDepth: 8)
        let v2 = J2KVolume(width: 10, height: 10, depth: 10, componentCount: 1, bitDepth: 8)
        let v3 = J2KVolume(width: 20, height: 10, depth: 10, componentCount: 1, bitDepth: 8)

        XCTAssertEqual(v1, v2)
        XCTAssertNotEqual(v1, v3)
    }

    func testRegionEquatable() throws {
        let r1 = JP3DRegion(x: 0..<10, y: 0..<10, z: 0..<10)
        let r2 = JP3DRegion(x: 0..<10, y: 0..<10, z: 0..<10)
        let r3 = JP3DRegion(x: 0..<20, y: 0..<10, z: 0..<10)

        XCTAssertEqual(r1, r2)
        XCTAssertNotEqual(r1, r3)
    }
}
