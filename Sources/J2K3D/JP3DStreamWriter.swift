/// # JP3DStreamWriter
///
/// Streaming encoder actor for JP3D volumetric encoding.
///
/// Supports slice-by-slice encoding with memory-efficient pipeline,
/// out-of-order slice addition, progress reporting, and interruptible
/// encoding with partial output.
///
/// ## Topics
///
/// ### Streaming Types
/// - ``JP3DStreamWriter``
/// - ``JP3DStreamWriterState``
/// - ``JP3DStreamProgress``

import Foundation
import J2KCore

/// Progress update for streaming encoding.
public struct JP3DStreamProgress: Sendable {
    /// Number of slices received so far.
    public let slicesReceived: Int

    /// Total number of slices expected.
    public let totalSlices: Int

    /// Number of tiles fully encoded.
    public let tilesEncoded: Int

    /// Total number of tiles.
    public let totalTiles: Int

    /// Progress percentage (0.0 to 1.0).
    public var progress: Double {
        guard totalSlices > 0 else { return 0 }
        return Double(slicesReceived) / Double(totalSlices)
    }
}

/// State of the streaming encoder.
public enum JP3DStreamWriterState: Sendable {
    /// Writer is ready to accept slices.
    case ready
    /// Writer is actively receiving slices.
    case encoding
    /// Writer has been finalized and produced output.
    case finalized
    /// Writer was cancelled.
    case cancelled
}

/// Streaming encoder actor for slice-by-slice JP3D encoding.
///
/// `JP3DStreamWriter` enables encoding a volume incrementally, one slice
/// at a time. This is memory-efficient as only tile-sized buffers need to
/// be kept in memory at any time.
///
/// Example:
/// ```swift
/// let writer = JP3DStreamWriter(configuration: config)
///
/// for z in 0..<depth {
///     try await writer.addSlice(sliceData, atIndex: z)
/// }
///
/// let codestream = try await writer.finalize()
/// ```
public actor JP3DStreamWriter {
    // MARK: - Configuration

    /// The encoder configuration.
    public struct Configuration: Sendable {
        /// Volume width.
        public let width: Int

        /// Volume height.
        public let height: Int

        /// Volume depth (total number of slices).
        public let depth: Int

        /// Number of components.
        public let componentCount: Int

        /// Bit depth per component.
        public let bitDepth: Int

        /// Compression mode.
        public let compressionMode: JP3DCompressionMode

        /// Tiling configuration.
        public let tiling: JP3DTilingConfiguration

        /// Progression order.
        public let progressionOrder: JP3DProgressionOrder

        /// Number of quality layers.
        public let qualityLayers: Int

        /// Creates a streaming encoder configuration.
        ///
        /// - Parameters:
        ///   - width: Volume width.
        ///   - height: Volume height.
        ///   - depth: Volume depth (total slices).
        ///   - componentCount: Number of components (default: 1).
        ///   - bitDepth: Bit depth (default: 8).
        ///   - compressionMode: Compression mode (default: `.lossless`).
        ///   - tiling: Tiling configuration (default: `.streaming`).
        ///   - progressionOrder: Progression order (default: `.lrcps`).
        ///   - qualityLayers: Number of quality layers (default: 1).
        public init(
            width: Int,
            height: Int,
            depth: Int,
            componentCount: Int = 1,
            bitDepth: Int = 8,
            compressionMode: JP3DCompressionMode = .lossless,
            tiling: JP3DTilingConfiguration = .streaming,
            progressionOrder: JP3DProgressionOrder = .lrcps,
            qualityLayers: Int = 1
        ) {
            self.width = max(1, width)
            self.height = max(1, height)
            self.depth = max(1, depth)
            self.componentCount = max(1, componentCount)
            self.bitDepth = max(1, min(38, bitDepth))
            self.compressionMode = compressionMode
            self.tiling = tiling
            self.progressionOrder = progressionOrder
            self.qualityLayers = max(1, qualityLayers)
        }
    }

    // MARK: - State

    private let config: Configuration
    private var state: JP3DStreamWriterState = .ready
    private var sliceBuffer: [Int: [Float]] // sliceIndex -> slice data
    private var encodedTiles: [Data]
    private var slicesReceived: Int = 0
    private var progressCallback: (@Sendable (JP3DStreamProgress) -> Void)?

    // MARK: - Init

    /// Creates a streaming encoder with the given configuration.
    ///
    /// - Parameter configuration: The streaming encoder configuration.
    public init(configuration: Configuration) {
        self.config = configuration
        self.sliceBuffer = [:]
        self.encodedTiles = []
    }

    // MARK: - Public API

    /// The current state of the writer.
    public var writerState: JP3DStreamWriterState { state }

    /// Sets the progress reporting callback.
    ///
    /// - Parameter callback: Called after each slice is processed.
    public func setProgressCallback(_ callback: @escaping @Sendable (JP3DStreamProgress) -> Void) {
        self.progressCallback = callback
    }

    /// Adds a slice of data to the encoder.
    ///
    /// Slices can be added in any order. Each slice contains data for all
    /// components at a single Z position.
    ///
    /// - Parameters:
    ///   - data: Slice data as Float values in row-major order (width × height × components).
    ///   - index: The Z-index of this slice (0-based).
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the index is out of range
    ///           or data size is incorrect.
    /// - Throws: ``J2KError/encodingError(_:)`` if the writer is not in encoding state.
    public func addSlice(_ data: [Float], atIndex index: Int) throws {
        guard state == .ready || state == .encoding else {
            throw J2KError.encodingError("Writer is in state \(state), cannot add slices")
        }

        guard index >= 0, index < config.depth else {
            throw J2KError.invalidParameter(
                "Slice index \(index) out of range [0, \(config.depth))"
            )
        }

        let expectedSize = config.width * config.height * config.componentCount
        guard data.count == expectedSize else {
            throw J2KError.invalidParameter(
                "Slice data count \(data.count) does not match expected \(expectedSize)"
            )
        }

        state = .encoding
        sliceBuffer[index] = data
        slicesReceived += 1

        // Report progress
        let tileGrid = config.tiling.tileGrid(
            volumeWidth: config.width,
            volumeHeight: config.height,
            volumeDepth: config.depth
        )
        let totalTiles = tileGrid.tilesX * tileGrid.tilesY * tileGrid.tilesZ
        let progress = JP3DStreamProgress(
            slicesReceived: slicesReceived,
            totalSlices: config.depth,
            tilesEncoded: encodedTiles.count,
            totalTiles: totalTiles
        )
        progressCallback?(progress)

        // Flush completed tile rows along Z
        try flushCompleteTiles()
    }

    /// Finalizes the encoding and returns the complete codestream.
    ///
    /// All remaining buffered slices are encoded. After finalization,
    /// no more slices can be added.
    ///
    /// - Returns: The complete JP3D codestream as `Data`.
    /// - Throws: ``J2KError/encodingError(_:)`` if finalization fails.
    public func finalize() throws -> Data {
        guard state == .encoding || state == .ready else {
            throw J2KError.encodingError("Writer is in state \(state), cannot finalize")
        }

        // Flush any remaining tiles
        try flushAllRemainingTiles()

        let builder = JP3DCodestreamBuilder()
        let maxLevel = maxDecompositionLevels()
        let codestream = builder.build(
            tileData: encodedTiles,
            width: config.width,
            height: config.height,
            depth: config.depth,
            components: config.componentCount,
            bitDepth: config.bitDepth,
            levelsX: maxLevel,
            levelsY: maxLevel,
            levelsZ: maxLevel,
            tileSizeX: config.tiling.tileSizeX,
            tileSizeY: config.tiling.tileSizeY,
            tileSizeZ: config.tiling.tileSizeZ,
            isLossless: config.compressionMode.isLossless
        )

        state = .finalized
        return codestream
    }

    /// Cancels the encoding process.
    ///
    /// Releases all buffered data. The writer cannot be reused after cancellation.
    public func cancel() {
        state = .cancelled
        sliceBuffer.removeAll()
        encodedTiles.removeAll()
    }

    /// Returns the number of slices received.
    public var receivedSliceCount: Int { slicesReceived }

    // MARK: - Private

    /// Checks if a tile's Z range is fully covered by received slices
    /// and encodes it if so.
    private func flushCompleteTiles() throws {
        let tileGrid = config.tiling.tileGrid(
            volumeWidth: config.width,
            volumeHeight: config.height,
            volumeDepth: config.depth
        )

        for tz in 0..<tileGrid.tilesZ {
            let zStart = tz * config.tiling.tileSizeZ
            let zEnd = min(zStart + config.tiling.tileSizeZ, config.depth)

            // Check if all slices in this Z range are available
            var allAvailable = true
            for z in zStart..<zEnd {
                if sliceBuffer[z] == nil {
                    allAvailable = false
                    break
                }
            }

            guard allAvailable else { continue }

            // Check if this tile-row hasn't already been encoded
            let expectedPriorTiles = tz * tileGrid.tilesX * tileGrid.tilesY
            guard encodedTiles.count == expectedPriorTiles else { continue }

            // Encode all tiles in this Z-row
            try encodeTileRow(tz: tz, tileGrid: tileGrid, zStart: zStart, zEnd: zEnd)

            // Free the slices we no longer need
            for z in zStart..<zEnd {
                sliceBuffer.removeValue(forKey: z)
            }
        }
    }

    /// Encodes all remaining tiles at finalization.
    private func flushAllRemainingTiles() throws {
        let tileGrid = config.tiling.tileGrid(
            volumeWidth: config.width,
            volumeHeight: config.height,
            volumeDepth: config.depth
        )
        let totalExpectedTiles = tileGrid.tilesX * tileGrid.tilesY * tileGrid.tilesZ

        // If we already have all tiles encoded, nothing to do
        guard encodedTiles.count < totalExpectedTiles else { return }

        // Encode remaining tile rows
        for tz in 0..<tileGrid.tilesZ {
            let expectedCount = (tz + 1) * tileGrid.tilesX * tileGrid.tilesY
            guard encodedTiles.count < expectedCount else { continue }
            // Ensure we have exactly the right number already
            guard encodedTiles.count == tz * tileGrid.tilesX * tileGrid.tilesY else { continue }

            let zStart = tz * config.tiling.tileSizeZ
            let zEnd = min(zStart + config.tiling.tileSizeZ, config.depth)
            try encodeTileRow(tz: tz, tileGrid: tileGrid, zStart: zStart, zEnd: zEnd)
        }
    }

    /// Encodes a row of tiles at a specific Z tile index.
    private func encodeTileRow(
        tz: Int,
        tileGrid: (tilesX: Int, tilesY: Int, tilesZ: Int),
        zStart: Int,
        zEnd: Int
    ) throws {
        let rateController = JP3DRateController(
            mode: config.compressionMode,
            qualityLayers: config.qualityLayers
        )

        for ty in 0..<tileGrid.tilesY {
            for tx in 0..<tileGrid.tilesX {
                let tile = config.tiling.tile(
                    atX: tx, y: ty, z: tz,
                    volumeWidth: config.width,
                    volumeHeight: config.height,
                    volumeDepth: config.depth
                )

                var tileBytes = Data()

                for comp in 0..<config.componentCount {
                    let tileData = extractTileFromSlices(
                        tile: tile, componentIndex: comp, zStart: zStart, zEnd: zEnd
                    )

                    // Quantize
                    let quantized = rateController.quantize(
                        coefficients: tileData,
                        tile: tile,
                        componentIndex: comp,
                        bitDepth: config.bitDepth,
                        decompositionLevels: maxDecompositionLevels()
                    )

                    // Simple encoding: store quantized coefficients as bytes
                    for coeff in quantized.coefficients {
                        var value = coeff.bigEndian
                        tileBytes.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
                    }
                }

                encodedTiles.append(tileBytes)
            }
        }
    }

    /// Extracts tile data from the slice buffer.
    private func extractTileFromSlices(
        tile: JP3DTile,
        componentIndex: Int,
        zStart: Int,
        zEnd: Int
    ) -> [Float] {
        let tw = tile.width
        let th = tile.height
        let td = tile.depth
        var data = [Float](repeating: 0, count: tw * th * td)

        let compStride = config.width * config.height

        for z in 0..<td {
            let sliceIndex = tile.region.z.lowerBound + z
            guard let sliceData = sliceBuffer[sliceIndex] else { continue }

            for y in 0..<th {
                let srcY = tile.region.y.lowerBound + y
                guard srcY < config.height else { continue }
                let srcYOffset = componentIndex * compStride + srcY * config.width
                for x in 0..<tw {
                    let srcX = tile.region.x.lowerBound + x
                    guard srcX < config.width else { continue }
                    let srcIdx = srcYOffset + srcX
                    let dstIdx = z * tw * th + y * tw + x
                    if srcIdx < sliceData.count {
                        data[dstIdx] = sliceData[srcIdx]
                    }
                }
            }
        }

        return data
    }

    /// Computes maximum decomposition levels based on tile dimensions.
    private func maxDecompositionLevels() -> Int {
        let minDim = min(
            config.tiling.tileSizeX,
            min(config.tiling.tileSizeY, config.tiling.tileSizeZ)
        )
        guard minDim > 1 else { return 0 }
        var levels = 0
        var d = minDim
        while d > 1 { d = (d + 1) / 2; levels += 1 }
        return min(levels, 5) // Cap at 5 levels
    }
}
