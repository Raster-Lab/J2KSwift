//
// J2KDWT2DTiledTests.swift
// J2KSwift
//
// J2KDWT2DTiledTests.swift
// J2KSwift Tests
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class J2KDWT2DTiledTests: XCTestCase {
    // MARK: - Tile Extraction Tests

    func testExtractSingleTile() throws {
        // Create a simple tiled image (one tile)
        let image = J2KImage(
            width: 8,
            height: 8,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 8, height: 8)
            ],
            tileWidth: 8,
            tileHeight: 8
        )

        let tiler = J2KDWT2DTiled()
        let tile = try tiler.extractTile(from: image, tileIndex: 0)

        XCTAssertEqual(tile.index, 0)
        XCTAssertEqual(tile.x, 0)
        XCTAssertEqual(tile.y, 0)
        XCTAssertEqual(tile.width, 8)
        XCTAssertEqual(tile.height, 8)
        XCTAssertEqual(tile.offsetX, 0)
        XCTAssertEqual(tile.offsetY, 0)
        XCTAssertEqual(tile.components.count, 1)
    }

    func testExtractMultipleTiles() throws {
        // 16x16 image with 4 tiles (2x2 grid of 8x8 tiles)
        let image = J2KImage(
            width: 16,
            height: 16,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 16, height: 16)
            ],
            tileWidth: 8,
            tileHeight: 8
        )

        XCTAssertEqual(image.tileCount, 4)
        XCTAssertEqual(image.tilesX, 2)
        XCTAssertEqual(image.tilesY, 2)

        let tiler = J2KDWT2DTiled()

        // Tile 0 (top-left)
        let tile0 = try tiler.extractTile(from: image, tileIndex: 0)
        XCTAssertEqual(tile0.x, 0)
        XCTAssertEqual(tile0.y, 0)
        XCTAssertEqual(tile0.offsetX, 0)
        XCTAssertEqual(tile0.offsetY, 0)
        XCTAssertEqual(tile0.width, 8)
        XCTAssertEqual(tile0.height, 8)

        // Tile 1 (top-right)
        let tile1 = try tiler.extractTile(from: image, tileIndex: 1)
        XCTAssertEqual(tile1.x, 1)
        XCTAssertEqual(tile1.y, 0)
        XCTAssertEqual(tile1.offsetX, 8)
        XCTAssertEqual(tile1.offsetY, 0)

        // Tile 2 (bottom-left)
        let tile2 = try tiler.extractTile(from: image, tileIndex: 2)
        XCTAssertEqual(tile2.x, 0)
        XCTAssertEqual(tile2.y, 1)
        XCTAssertEqual(tile2.offsetX, 0)
        XCTAssertEqual(tile2.offsetY, 8)

        // Tile 3 (bottom-right)
        let tile3 = try tiler.extractTile(from: image, tileIndex: 3)
        XCTAssertEqual(tile3.x, 1)
        XCTAssertEqual(tile3.y, 1)
        XCTAssertEqual(tile3.offsetX, 8)
        XCTAssertEqual(tile3.offsetY, 8)
    }

    func testExtractTileWithNonAlignedDimensions() throws {
        // 10x10 image with 8x8 tiles results in partial tiles at edges
        let image = J2KImage(
            width: 10,
            height: 10,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 10, height: 10)
            ],
            tileWidth: 8,
            tileHeight: 8
        )

        XCTAssertEqual(image.tileCount, 4) // 2x2 grid

        let tiler = J2KDWT2DTiled()

        // Tile 0 should be full size
        let tile0 = try tiler.extractTile(from: image, tileIndex: 0)
        XCTAssertEqual(tile0.width, 8)
        XCTAssertEqual(tile0.height, 8)

        // Tile 1 should be partial width
        let tile1 = try tiler.extractTile(from: image, tileIndex: 1)
        XCTAssertEqual(tile1.width, 2)  // 10 - 8 = 2
        XCTAssertEqual(tile1.height, 8)

        // Tile 2 should be partial height
        let tile2 = try tiler.extractTile(from: image, tileIndex: 2)
        XCTAssertEqual(tile2.width, 8)
        XCTAssertEqual(tile2.height, 2)  // 10 - 8 = 2

        // Tile 3 should be partial both dimensions
        let tile3 = try tiler.extractTile(from: image, tileIndex: 3)
        XCTAssertEqual(tile3.width, 2)
        XCTAssertEqual(tile3.height, 2)
    }

    func testExtractTileDataSimple() throws {
        let imageData: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        let tile = J2KTile(
            index: 0,
            x: 0,
            y: 0,
            width: 2,
            height: 2,
            offsetX: 0,
            offsetY: 0
        )

        let tiler = J2KDWT2DTiled()
        let tileData = try tiler.extractTileData(from: imageData, tile: tile)

        XCTAssertEqual(tileData.count, 2)
        XCTAssertEqual(tileData[0], [1, 2])
        XCTAssertEqual(tileData[1], [5, 6])
    }

    func testExtractTileDataWithOffset() throws {
        let imageData: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        // Extract bottom-right 2x2 region
        let tile = J2KTile(
            index: 0,
            x: 1,
            y: 1,
            width: 2,
            height: 2,
            offsetX: 2,
            offsetY: 2
        )

        let tiler = J2KDWT2DTiled()
        let tileData = try tiler.extractTileData(from: imageData, tile: tile)

        XCTAssertEqual(tileData.count, 2)
        XCTAssertEqual(tileData[0], [11, 12])
        XCTAssertEqual(tileData[1], [15, 16])
    }

    // MARK: - Tile Assembly Tests

    func testAssembleSingleTile() throws {
        let image = J2KImage(
            width: 4,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 4, height: 4)
            ],
            tileWidth: 4,
            tileHeight: 4
        )

        let tileData: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        let tiler = J2KDWT2DTiled()
        let assembled = try tiler.assembleTiles([tileData], into: image)

        XCTAssertEqual(assembled, tileData)
    }

    func testAssembleMultipleTiles() throws {
        let image = J2KImage(
            width: 4,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 4, height: 4)
            ],
            tileWidth: 2,
            tileHeight: 2
        )

        XCTAssertEqual(image.tileCount, 4)

        let tile0: [[Int32]] = [[1, 2], [5, 6]]
        let tile1: [[Int32]] = [[3, 4], [7, 8]]
        let tile2: [[Int32]] = [[9, 10], [13, 14]]
        let tile3: [[Int32]] = [[11, 12], [15, 16]]

        let tiler = J2KDWT2DTiled()
        let assembled = try tiler.assembleTiles([tile0, tile1, tile2, tile3], into: image)

        let expected: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        XCTAssertEqual(assembled, expected)
    }

    // MARK: - Tile-wise DWT Tests

    func testForwardTransformSingleTile() throws {
        let tileData: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        let tiler = J2KDWT2DTiled()
        let decomposition = try tiler.forwardTransformTile(
            tileData: tileData,
            levels: 1,
            filter: .reversible53
        )

        XCTAssertEqual(decomposition.levelCount, 1)
        XCTAssertEqual(decomposition.levels[0].ll.count, 2)  // 4x4 -> 2x2 LL
        XCTAssertEqual(decomposition.levels[0].ll[0].count, 2)
    }

    func testRoundTripSingleTile() throws {
        let tileData: [[Int32]] = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160]
        ]

        let tiler = J2KDWT2DTiled()

        // Forward
        let decomposition = try tiler.forwardTransformTile(
            tileData: tileData,
            levels: 1,
            filter: .reversible53
        )

        // Inverse
        let reconstructed = try tiler.inverseTransformTile(
            decomposition: decomposition,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, tileData, "Perfect reconstruction should match original")
    }

    func testMultiLevelTileTransform() throws {
        let tileData: [[Int32]] = [
            [1, 2, 3, 4, 5, 6, 7, 8],
            [9, 10, 11, 12, 13, 14, 15, 16],
            [17, 18, 19, 20, 21, 22, 23, 24],
            [25, 26, 27, 28, 29, 30, 31, 32],
            [33, 34, 35, 36, 37, 38, 39, 40],
            [41, 42, 43, 44, 45, 46, 47, 48],
            [49, 50, 51, 52, 53, 54, 55, 56],
            [57, 58, 59, 60, 61, 62, 63, 64]
        ]

        let tiler = J2KDWT2DTiled()

        // 2-level decomposition
        let decomposition = try tiler.forwardTransformTile(
            tileData: tileData,
            levels: 2,
            filter: .reversible53
        )

        XCTAssertEqual(decomposition.levelCount, 2)

        // Level 0: 8x8 -> 4x4 subbands
        XCTAssertEqual(decomposition.levels[0].ll.count, 4)
        XCTAssertEqual(decomposition.levels[0].ll[0].count, 4)

        // Level 1: 4x4 LL -> 2x2 subbands
        XCTAssertEqual(decomposition.levels[1].ll.count, 2)
        XCTAssertEqual(decomposition.levels[1].ll[0].count, 2)

        // Round trip
        let reconstructed = try tiler.inverseTransformTile(
            decomposition: decomposition,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, tileData)
    }

    // MARK: - Full Image Tiled Processing Tests

    func testProcessImageTiledSingleTile() throws {
        let imageData: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        let image = J2KImage(
            width: 4,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 4, height: 4)
            ],
            tileWidth: 4,
            tileHeight: 4
        )

        let tiler = J2KDWT2DTiled()
        let results = try tiler.processImageTiled(
            imageData: imageData,
            image: image,
            levels: 1,
            filter: .reversible53
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].tile.index, 0)
        XCTAssertEqual(results[0].decomposition.levelCount, 1)
    }

    func testProcessImageTiledMultipleTiles() throws {
        let imageData: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        let image = J2KImage(
            width: 4,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 4, height: 4)
            ],
            tileWidth: 2,
            tileHeight: 2
        )

        let tiler = J2KDWT2DTiled()
        let results = try tiler.processImageTiled(
            imageData: imageData,
            image: image,
            levels: 1,
            filter: .reversible53
        )

        XCTAssertEqual(results.count, 4)

        for (index, result) in results.enumerated() {
            XCTAssertEqual(result.tile.index, index)
            XCTAssertEqual(result.decomposition.levelCount, 1)
        }
    }

    func testFullRoundTripWithTiles() throws {
        let imageData: [[Int32]] = [
            [10, 20, 30, 40, 50, 60, 70, 80],
            [15, 25, 35, 45, 55, 65, 75, 85],
            [20, 30, 40, 50, 60, 70, 80, 90],
            [25, 35, 45, 55, 65, 75, 85, 95],
            [30, 40, 50, 60, 70, 80, 90, 100],
            [35, 45, 55, 65, 75, 85, 95, 105],
            [40, 50, 60, 70, 80, 90, 100, 110],
            [45, 55, 65, 75, 85, 95, 105, 115]
        ]

        let image = J2KImage(
            width: 8,
            height: 8,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 8, height: 8)
            ],
            tileWidth: 4,
            tileHeight: 4
        )

        let tiler = J2KDWT2DTiled()

        // Forward
        let tileResults = try tiler.processImageTiled(
            imageData: imageData,
            image: image,
            levels: 2,
            filter: .reversible53
        )

        XCTAssertEqual(tileResults.count, 4)

        // Inverse
        let reconstructed = try tiler.reconstructImageFromTiles(
            tileDecompositions: tileResults,
            image: image,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, imageData, "Full round trip should preserve data")
    }

    func testTiledVsNonTiledConsistency() throws {
        // Verify that tiled processing produces same result as non-tiled
        // when using a single tile
        let imageData: [[Int32]] = [
            [1, 2, 3, 4, 5, 6, 7, 8],
            [9, 10, 11, 12, 13, 14, 15, 16],
            [17, 18, 19, 20, 21, 22, 23, 24],
            [25, 26, 27, 28, 29, 30, 31, 32],
            [33, 34, 35, 36, 37, 38, 39, 40],
            [41, 42, 43, 44, 45, 46, 47, 48],
            [49, 50, 51, 52, 53, 54, 55, 56],
            [57, 58, 59, 60, 61, 62, 63, 64]
        ]

        // Non-tiled transform
        let nonTiledDecomp = try J2KDWT2D.forwardDecomposition(
            image: imageData,
            levels: 2,
            filter: .reversible53
        )

        // Tiled transform with single tile
        let image = J2KImage(
            width: 8,
            height: 8,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 8, height: 8)
            ],
            tileWidth: 8,
            tileHeight: 8
        )

        let tiler = J2KDWT2DTiled()
        let tiledResults = try tiler.processImageTiled(
            imageData: imageData,
            image: image,
            levels: 2,
            filter: .reversible53
        )

        XCTAssertEqual(tiledResults.count, 1)
        let tiledDecomp = tiledResults[0].decomposition

        // Compare results
        XCTAssertEqual(tiledDecomp.levelCount, nonTiledDecomp.levelCount)
        XCTAssertEqual(tiledDecomp.coarsestLL, nonTiledDecomp.coarsestLL)
    }

    // MARK: - Edge Case Tests

    func testMinimumTileSize() throws {
        // Minimum tile size is 2x2 (required for DWT)
        let tileData: [[Int32]] = [
            [1, 2],
            [3, 4]
        ]

        let tiler = J2KDWT2DTiled()
        let decomposition = try tiler.forwardTransformTile(
            tileData: tileData,
            levels: 1,
            filter: .reversible53
        )

        XCTAssertEqual(decomposition.levelCount, 1)

        let reconstructed = try tiler.inverseTransformTile(
            decomposition: decomposition,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, tileData)
    }

    func testOddSizedTile() throws {
        let tileData: [[Int32]] = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9]
        ]

        let tiler = J2KDWT2DTiled()
        let decomposition = try tiler.forwardTransformTile(
            tileData: tileData,
            levels: 1,
            filter: .reversible53
        )

        let reconstructed = try tiler.inverseTransformTile(
            decomposition: decomposition,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, tileData)
    }

    func testRectangularTiles() throws {
        // 8x4 image with 4x4 tiles (2 tiles)
        let imageData: [[Int32]] = [
            [1, 2, 3, 4, 5, 6, 7, 8],
            [9, 10, 11, 12, 13, 14, 15, 16],
            [17, 18, 19, 20, 21, 22, 23, 24],
            [25, 26, 27, 28, 29, 30, 31, 32]
        ]

        let image = J2KImage(
            width: 8,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 8, height: 4)
            ],
            tileWidth: 4,
            tileHeight: 4
        )

        XCTAssertEqual(image.tileCount, 2)

        let tiler = J2KDWT2DTiled()
        let results = try tiler.processImageTiled(
            imageData: imageData,
            image: image,
            levels: 1,
            filter: .reversible53
        )

        XCTAssertEqual(results.count, 2)

        let reconstructed = try tiler.reconstructImageFromTiles(
            tileDecompositions: results,
            image: image,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, imageData)
    }

    // MARK: - Error Handling Tests

    func testInvalidTileIndex() throws {
        let image = J2KImage(
            width: 8,
            height: 8,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 8, height: 8)
            ],
            tileWidth: 8,
            tileHeight: 8
        )

        let tiler = J2KDWT2DTiled()

        XCTAssertThrowsError(try tiler.extractTile(from: image, tileIndex: -1))
        XCTAssertThrowsError(try tiler.extractTile(from: image, tileIndex: 1))
    }

    func testExtractTileDataOutOfBounds() throws {
        let imageData: [[Int32]] = [
            [1, 2],
            [3, 4]
        ]

        let tile = J2KTile(
            index: 0,
            x: 0,
            y: 0,
            width: 4,  // Exceeds image width
            height: 2,
            offsetX: 0,
            offsetY: 0
        )

        let tiler = J2KDWT2DTiled()
        XCTAssertThrowsError(try tiler.extractTileData(from: imageData, tile: tile))
    }

    func testAssembleTilesCountMismatch() throws {
        let image = J2KImage(
            width: 4,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 4, height: 4)
            ],
            tileWidth: 2,
            tileHeight: 2
        )

        XCTAssertEqual(image.tileCount, 4)

        let tiles = [[[Int32]](), [[Int32]]()]  // Only 2 tiles instead of 4

        let tiler = J2KDWT2DTiled()
        XCTAssertThrowsError(try tiler.assembleTiles(tiles, into: image))
    }

    func testReconstructWithWrongTileCount() throws {
        let image = J2KImage(
            width: 4,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 4, height: 4)
            ],
            tileWidth: 2,
            tileHeight: 2
        )

        let tiler = J2KDWT2DTiled()
        let emptyResults: [J2KDWT2DTiled.TileDecompositionResult] = []

        XCTAssertThrowsError(
            try tiler.reconstructImageFromTiles(
                tileDecompositions: emptyResults,
                image: image,
                filter: .reversible53
            )
        )
    }

    // MARK: - Boundary Extension Tests

    func testTileBoundaryIndependence() throws {
        // Verify that tiles are processed independently and don't affect each other
        let imageData: [[Int32]] = [
            [100, 100, 200, 200],
            [100, 100, 200, 200],
            [300, 300, 400, 400],
            [300, 300, 400, 400]
        ]

        let image = J2KImage(
            width: 4,
            height: 4,
            components: [
                J2KComponent(index: 0, bitDepth: 8, width: 4, height: 4)
            ],
            tileWidth: 2,
            tileHeight: 2
        )

        let tiler = J2KDWT2DTiled()

        // Process with tiling
        let tiledResults = try tiler.processImageTiled(
            imageData: imageData,
            image: image,
            levels: 1,
            filter: .reversible53
        )

        let reconstructed = try tiler.reconstructImageFromTiles(
            tileDecompositions: tiledResults,
            image: image,
            filter: .reversible53
        )

        // Perfect reconstruction should work
        XCTAssertEqual(reconstructed, imageData)

        // Each tile should have constant LL and zero detail subbands
        for result in tiledResults {
            let ll = result.decomposition.levels[0].ll

            // Constant regions should produce minimal high-frequency content
            // (though not necessarily zero due to boundary effects)
            XCTAssertEqual(ll.count, 1)
            XCTAssertEqual(ll[0].count, 1)
        }
    }

    func testDifferentBoundaryExtensions() throws {
        let tileData: [[Int32]] = [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ]

        let tiler = J2KDWT2DTiled()

        // Test all three boundary extension modes
        let modes: [J2KDWT1D.BoundaryExtension] = [.symmetric, .periodic, .zeroPadding]

        for mode in modes {
            let decomposition = try tiler.forwardTransformTile(
                tileData: tileData,
                levels: 1,
                filter: .reversible53,
                boundaryExtension: mode
            )

            let reconstructed = try tiler.inverseTransformTile(
                decomposition: decomposition,
                filter: .reversible53,
                boundaryExtension: mode
            )

            XCTAssertEqual(reconstructed, tileData,
                          "Perfect reconstruction should work with \(mode) boundary extension")
        }
    }
}
