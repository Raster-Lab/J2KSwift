//
// J2KDecoderPipeline.swift
// J2KSwift
//
// J2KDecoderPipeline.swift
// J2KSwift
//
// Decoder pipeline implementation for JPEG 2000 decoding.
//

import Foundation
import J2KCore
import J2KMetal

#if canImport(Accelerate)
import Accelerate
#endif

// MARK: - Decoding Stage

/// Represents the stages of the JPEG 2000 decoding pipeline.
public enum DecodingStage: String, Sendable, CaseIterable {
    /// Codestream parsing and marker validation.
    case codestreamParsing = "Codestream Parsing"

    /// Tile data extraction from packets.
    case tileExtraction = "Tile Extraction"

    /// Entropy decoding (EBCOT bit-plane decoding).
    case entropyDecoding = "Entropy Decoding"

    /// Dequantization of wavelet coefficients.
    case dequantization = "Dequantization"

    /// Inverse wavelet transform.
    case inverseWaveletTransform = "Inverse Wavelet Transform"

    /// Inverse colour space transformation.
    case inverseColorTransform = "Inverse Color Transform"

    /// Image reconstruction.
    case imageReconstruction = "Image Reconstruction"
}

// MARK: - Progress Update

/// Reports progress during decoding.
public struct DecoderProgressUpdate: Sendable {
    /// The current decoding stage.
    public let stage: DecodingStage

    /// Progress within the current stage (0.0 to 1.0).
    public let progress: Double

    /// Overall decoding progress (0.0 to 1.0).
    public let overallProgress: Double
}

// MARK: - Decoder Configuration

/// Configuration for the decoder pipeline.
struct DecoderConfiguration: Sendable {
    /// Number of decomposition levels (from COD marker).
    var decompositionLevels: Int = 5

    /// Code block size (from COD marker).
    var codeBlockSize: (width: Int, height: Int) = (32, 32)

    /// Whether to use reversible colour transform.
    var useReversibleTransform: Bool = true

    /// Number of quality layers (from COD marker).
    var qualityLayers: Int = 1

    /// Progression order (from COD marker).
    var progressionOrder: J2KProgressionOrder = .lrcp

    /// Wavelet filter type (from COD marker).
    var waveletFilter: J2KDWT1D.Filter = .reversible53

    /// Whether HTJ2K block coding is used (from COD marker bit 6).
    var useHTJ2K: Bool = false

    /// HTJ2K code-block wire format. `.custom` is the v4.x layout that
    /// only round-trips with J2KSwift itself; `.conformant` is the
    /// ISO/IEC 15444-15 layout — the same byte stream emitted by
    /// OpenJPH and other Part-15 reference encoders. The default is
    /// `.conformant` so any third-party HTJ2K codestream decodes
    /// out of the box; J2KSwift `.custom` codestreams carry a
    /// J2KSwift-private COM marker that the decoder still recognises
    /// (kept for legacy archives — see `parseHTBlockFormatCOM`).
    /// Only meaningful when `useHTJ2K` is true.
    var htj2kBlockFormat: HTBlockFormat = .conformant

    /// Whether `htj2kBlockFormat` was set from an explicit codestream
    /// signal (e.g. the J2KSwift block-format COM marker) versus
    /// inherited from the default. When `false`, the entropy decoder
    /// is allowed to run a structural heuristic on the first non-empty
    /// codeblock to recover the format — this catches legacy J2KSwift
    /// `.custom` archives that pre-date marker-based signalling.
    var htBlockFormatExplicit: Bool = false

    /// Whether selective arithmetic coding bypass is enabled (from COD marker bit 0).
    var useSelectiveArithmeticBypass: Bool = false

    /// Per-component DC offset values from DCO marker segment (Part 2).
    ///
    /// When non-nil, the decoder applies these offsets after inverse wavelet
    /// transform to restore original component values.
    var dcOffsets: [J2KDCOffsetValue]?

    /// Extended precision configuration (Part 2).
    ///
    /// Controls guard bit count and rounding mode for coefficient processing.
    var extendedPrecision: J2KExtendedPrecisionConfiguration = .default

    /// Wavelet kernel configuration (Part 2).
    ///
    /// Specifies which wavelet kernels to use per tile-component.
    /// When nil, uses the waveletFilter property for all components.
    var waveletKernelConfiguration: J2KWaveletKernelConfiguration?
}

// MARK: - Codestream Metadata

/// Metadata extracted from codestream markers.
struct CodestreamMetadata: Sendable {
    /// Image width.
    var width: Int

    /// Image height.
    var height: Int

    /// Number of components.
    var componentCount: Int

    /// Component information.
    var components: [ComponentInfo]

    /// Tile size.
    var tileSize: (width: Int, height: Int)

    /// Image offset (XOsiz, YOsiz).
    var imageOffset: (x: Int, y: Int) = (0, 0)

    /// Tile offset (XTOsiz, YTOsiz).
    var tileOffset: (x: Int, y: Int) = (0, 0)

    /// Configuration from COD marker.
    var configuration: DecoderConfiguration

    /// Quantization step sizes from QCD marker.
    var quantizationSteps: [String: Double]

    /// Guard bits from QCD marker Sqcd byte.
    var quantizationGuardBits: Int

    /// Band-level Kb values (number of magnitude bit-planes) per subband.
    /// Keyed by "{subband}_{level}" matching quantizationSteps keys.
    var bandKbValues: [String: Int]

    /// DCO marker segment from codestream (Part 2).
    ///
    /// Present when the codestream contains a DCO marker segment (0xFF5C)
    /// signaling per-component DC offset values.
    var dcoMarkerSegment: J2KDCOMarkerSegment?

    /// Number of tiles in X direction.
    var numTilesX: Int { max(1, (width + tileSize.width - 1) / tileSize.width) }

    /// Number of tiles in Y direction.
    var numTilesY: Int { max(1, (height + tileSize.height - 1) / tileSize.height) }

    /// Total number of tiles.
    var totalTiles: Int { numTilesX * numTilesY }

    /// Whether this is a multi-tile codestream.
    var isMultiTile: Bool { totalTiles > 1 }

    /// Returns the actual dimensions for a given tile index, accounting for edge tiles.
    func tileDimensions(tileIndex: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let col = tileIndex % numTilesX
        let row = tileIndex / numTilesX
        let x0 = col * tileSize.width
        let y0 = row * tileSize.height
        let w = min(tileSize.width, width - x0)
        let h = min(tileSize.height, height - y0)
        return (x0, y0, w, h)
    }

    struct ComponentInfo: Sendable {
        var bitDepth: Int
        var signed: Bool
        var subsamplingX: Int
        var subsamplingY: Int
    }
}

// MARK: - Decoder Pipeline

/// Internal decoding pipeline that connects all JPEG 2000 decoding components.
///
/// The pipeline processes a codestream through these stages:
/// 1. Codestream Parsing — parse markers and extract metadata
/// 2. Tile Extraction — extract tile data from packets
/// 3. Entropy Decoding — EBCOT bit-plane decoding per code block
/// 4. Dequantization — convert integer indices to coefficients
/// 5. Inverse Wavelet Transform — multi-level 2D IDWT reconstruction
/// 6. Inverse Colour Transform — YCbCr → RGB conversion
/// 7. Image Reconstruction — assemble final image
struct DecoderPipeline: Sendable {
    /// Opt-in flag for GPU HT cleanup-pass entropy decode.
    ///
    /// When `true` AND the codestream is HTJ2K conformant cleanup-only
    /// AND Metal is available on this platform, eligible codeblocks are
    /// batched through `J2KGPUHTDispatch` instead of decoding one at a
    /// time on CPU. Ineligible codeblocks (refinement passes, custom
    /// format, empty data, passCount == 0, or parse failure) fall
    /// through to the existing CPU path. Default is `false`: production
    /// HT decode remains on CPU until callers opt in.
    var useGPUHT: Bool = false

    /// Optional shared Metal session. When set, every GPU dispatch
    /// path on this pipeline (HT cleanup + inverse DWT) reuses the
    /// session's Metal device, shader library, and buffer pool
    /// instead of constructing fresh ones per decode. Long-running
    /// callers that decode many images get the warm-process
    /// amortisation v5.6.0 introduced. Default `nil` keeps v5.5.0
    /// behaviour (per-decode Metal init).
    var metalSession: J2KMetalSession? = nil

    /// Decodes a JPEG 2000 codestream through the full pipeline.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data.
    ///   - progress: Optional progress callback.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    func decode(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)? = nil
    ) async throws -> J2KImage {
        // Stage 1: Parse codestream and extract metadata
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 0.0)
        let (metadata, tiles) = try parseCodestream(data)
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 1.0)

        if metadata.isMultiTile {
            return try await decodeMultiTile(metadata: metadata, tiles: tiles, progress: progress)
        } else {
            let tileData = tiles.first?.tileData ?? Data()
            return try await decodeSingleTile(metadata: metadata, tileData: tileData, progress: progress)
        }
    }

    // MARK: - GPU-Accelerated Decode

    /// Decodes a JPEG 2000 codestream using GPU-accelerated inverse DWT.
    ///
    /// Uses Metal GPU for the inverse wavelet transform and colour transform
    /// stages when available. Falls back to CPU implementations when Metal is
    /// unavailable (e.g. Linux, CI servers without GPU).
    ///
    /// HTJ2K block decoding (when signaled via COD marker bit 6) always runs
    /// on CPU using the FBCOT algorithm.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data.
    ///   - progress: Optional progress callback.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    func decodeGPU(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)? = nil
    ) async throws -> J2KImage {
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 0.0)
        let (metadata, tiles) = try parseCodestream(data)
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 1.0)

        if metadata.isMultiTile {
            return try await decodeMultiTileGPU(metadata: metadata, tiles: tiles, progress: progress)
        } else {
            let tileData = tiles.first?.tileData ?? Data()
            return try await decodeSingleTileGPU(metadata: metadata, tileData: tileData, progress: progress)
        }
    }

    /// GPU-accelerated single-tile decode.
    private func decodeSingleTileGPU(
        metadata: CodestreamMetadata,
        tileData: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        // v5.12.1: profile probes mirroring `decodeSingleTile`'s
        // CPU-path probes. Set `J2K_PROFILE_DECODE=1` to surface
        // per-stage timings on stderr; useful for sizing future
        // post-DWT optimisations (GPU MCT fusion, int-to-double
        // fusion, etc.) by ground-truth measurement instead of
        // estimated cost.
        let profileDecode = ProcessInfo.processInfo.environment["J2K_PROFILE_DECODE"] != nil
        var t0 = DispatchTime.now()

        // Stages 2-4: same as CPU path
        reportProgress(progress, stage: .tileExtraction, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let codeBlocks = try extractTileData(tileData, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE-GPU: extractTileData        = \(String(format: "%.1f", dt)) ms (\(codeBlocks.count) blocks)")
        }
        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        reportProgress(progress, stage: .entropyDecoding, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let (decodedBlocks, gpuBatch) = try await applyEntropyDecoding(codeBlocks, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE-GPU: entropyDecoding         = \(String(format: "%.1f", dt)) ms (\(decodedBlocks.count) subbands, gpuBatch=\(gpuBatch != nil))")
        }
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 1.0)

        reportProgress(progress, stage: .dequantization, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE-GPU: dequantization          = \(String(format: "%.1f", dt)) ms")
        }
        reportProgress(progress, stage: .dequantization, stageProgress: 1.0)

        // Stage 5: GPU inverse wavelet transform
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let spatialData = try await applyInverseWaveletTransformGPU(dequantizedSubbands, metadata: metadata, gpuBatch: gpuBatch)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE-GPU: inverseWaveletTransform = \(String(format: "%.1f", dt)) ms")
        }
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 1.0)

        // Stages 6-7: GPU inverse colour transform
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        var rgbData = try await applyInverseColorTransformGPU(spatialData, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE-GPU: inverseColorTransform   = \(String(format: "%.1f", dt)) ms")
        }
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 1.0)

        t0 = DispatchTime.now()
        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < rgbData.count else { break }
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                rgbData[compIdx].withUnsafeMutableBufferPointer { buf in
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset, buf.baseAddress!, 1, vDSP_Length(buf.count))
                }
            }
        }
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE-GPU: dcLevelUnshift          = \(String(format: "%.1f", dt)) ms")
        }

        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let image = try reconstructImage(rgbData, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE-GPU: reconstructImage        = \(String(format: "%.1f", dt)) ms")
        }
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)
        return image
    }

    /// GPU-accelerated multi-tile decode.
    private func decodeMultiTileGPU(
        metadata: CodestreamMetadata,
        tiles: [(tileIndex: Int, tileData: Data)],
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        let numComponents = metadata.componentCount
        var fullComponents: [[Double]] = (0..<numComponents).map { compIdx in
            let compInfo = metadata.components[compIdx]
            let w = metadata.width / compInfo.subsamplingX
            let h = metadata.height / compInfo.subsamplingY
            return [Double](repeating: 0.0, count: w * h)
        }

        reportProgress(progress, stage: .tileExtraction, stageProgress: 0.0)

        // See decodeMultiTile for the rationale; this variant routes the
        // inverse wavelet + colour transform stages through the GPU pipeline.
        //
        // v5.12: bounded concurrency. The previous unbounded TaskGroup
        // would spawn N tasks for N tiles up front, causing the heap-
        // backed buffer pool to allocate N peak working sets in
        // parallel. For 100-tile tiled JPEG 2000 codestreams that
        // exhausts even a 256 MB heap and forces fallthrough to
        // `device.makeBuffer`. The chunked-TaskGroup pattern below
        // caps in-flight tiles to `Self.maxInFlightTilesGPU` —
        // tile chunks are processed sequentially but tiles within
        // a chunk run concurrently. Single-tile decodes (the entire
        // DICOM corpus) take exactly one slot and observe identical
        // behaviour to v5.11.
        var decodedTiles: [DecodedTile] = []
        decodedTiles.reserveCapacity(tiles.count)
        let chunkSize = max(1, Self.maxInFlightTilesGPU)
        var tileIdx = 0
        while tileIdx < tiles.count {
            let end = min(tileIdx + chunkSize, tiles.count)
            let chunk = Array(tiles[tileIdx..<end])
            let chunkResults = try await withThrowingTaskGroup(of: DecodedTile.self) { group in
                for tile in chunk {
                    let captured = tile
                    let metadataCopy = metadata
                    group.addTask {
                        try await self.decodeTilePayloadGPU(
                            metadata: metadataCopy,
                            tileIndex: captured.tileIndex,
                            tileData: captured.tileData
                        )
                    }
                }
                var results: [DecodedTile] = []
                results.reserveCapacity(chunk.count)
                for try await decoded in group {
                    results.append(decoded)
                }
                return results
            }
            decodedTiles.append(contentsOf: chunkResults)
            tileIdx = end
        }

        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        for tile in decodedTiles {
            compositeTile(tile, into: &fullComponents, metadata: metadata)
        }

        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        let image = try reconstructImage(fullComponents, metadata: metadata)
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)
        return image
    }

    /// v5.12: maximum number of tiles that can have GPU command
    /// buffers in flight at the same time. Higher values amortize
    /// dispatch overhead but increase peak heap residency. 8 covers
    /// most codestreams without exhausting the default 256 MB heap.
    private static let maxInFlightTilesGPU = 8

    /// v5.12: maximum number of tiles that can be CPU-decoded in
    /// parallel. CPU concurrency scales with available cores; the
    /// bound primarily prevents unbounded memory growth on
    /// codestreams with many large tiles.
    private static let maxInFlightTilesCPU = 8

    /// Decodes a single-tile codestream (original path).
    private func decodeSingleTile(
        metadata: CodestreamMetadata,
        tileData: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        let profileDecode = ProcessInfo.processInfo.environment["J2K_PROFILE_DECODE"] != nil

        // Stage 2: Extract tile data
        reportProgress(progress, stage: .tileExtraction, stageProgress: 0.0)
        var t0 = DispatchTime.now()
        let codeBlocks = try extractTileData(tileData, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE: extractTileData        = \(String(format: "%.1f", dt)) ms (\(codeBlocks.count) blocks)")
        }
        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        // Stage 3: Entropy decoding
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let (decodedBlocks, _) = try await applyEntropyDecoding(codeBlocks, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE: entropyDecoding         = \(String(format: "%.1f", dt)) ms (\(decodedBlocks.count) subbands)")
        }
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 1.0)

        // Stage 4: Dequantization
        reportProgress(progress, stage: .dequantization, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE: dequantization          = \(String(format: "%.1f", dt)) ms")
        }
        reportProgress(progress, stage: .dequantization, stageProgress: 1.0)

        // Stage 5: Inverse wavelet transform
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        var spatialData = try await applyInverseWaveletTransform(dequantizedSubbands, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE: inverseWaveletTransform = \(String(format: "%.1f", dt)) ms (\(spatialData.count) components)")
        }
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 1.0)

        // Stage 6: Inverse colour transform (in-place to avoid 2 large buffer allocations)
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        try applyInverseColorTransformInPlace(&spatialData, metadata: metadata)
        var rgbData = spatialData
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE: inverseColorTransform   = \(String(format: "%.1f", dt)) ms")
        }
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 1.0)

        // DC level unshift: for unsigned components, add back 2^(bitDepth-1)
        t0 = DispatchTime.now()
        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < rgbData.count else { break }
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                rgbData[compIdx].withUnsafeMutableBufferPointer { buf in
                    #if canImport(Accelerate)
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset, buf.baseAddress!, 1, vDSP_Length(buf.count))
                    #else
                    for i in 0..<buf.count { buf[i] += dcOffset }
                    #endif
                }
            }
        }
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE: dcLevelUnshift          = \(String(format: "%.1f", dt)) ms")
        }

        // Stage 7: Image reconstruction
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let image = try reconstructImage(rgbData, metadata: metadata)
        if profileDecode {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            print("PROFILE: reconstructImage        = \(String(format: "%.1f", dt)) ms")
        }
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)

        return image
    }

    /// Decodes a multi-tile codestream by processing each tile independently
    /// and assembling the results into the full image.
    /// Result of a per-tile decode: the spatial-domain pixels plus the
    /// destination rectangle so the caller can composite into the full image.
    private struct DecodedTile: Sendable {
        let tileX: Int
        let tileY: Int
        let tileW: Int
        let tileH: Int
        let rgb: [[Double]]
    }

    /// End-to-end decode of a single tile (extract → entropy → dequant →
    /// IDWT → colour transform → DC level unshift). Pure function on
    /// `tileMeta` and `tileData`; safe to invoke concurrently across tiles
    /// since each task gets its own metadata copy and the inner stages
    /// allocate their own scratch buffers.
    private func decodeTilePayload(
        metadata: CodestreamMetadata,
        tileIndex: Int,
        tileData: Data
    ) async throws -> DecodedTile {
        let (tileX, tileY, tileW, tileH) = metadata.tileDimensions(tileIndex: tileIndex)
        var tileMeta = metadata
        tileMeta.width = tileW
        tileMeta.height = tileH
        tileMeta.tileSize = (width: tileW, height: tileH)

        let codeBlocks = try extractTileData(tileData, metadata: tileMeta)
        let (decodedBlocks, _) = try await applyEntropyDecoding(codeBlocks, metadata: tileMeta)
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: tileMeta)
        var spatialDataTile = try await applyInverseWaveletTransform(dequantizedSubbands, metadata: tileMeta)
        try applyInverseColorTransformInPlace(&spatialDataTile, metadata: tileMeta)

        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < spatialDataTile.count else { break }
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                spatialDataTile[compIdx].withUnsafeMutableBufferPointer { buf in
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset, buf.baseAddress!, 1, vDSP_Length(buf.count))
                }
            }
        }
        return DecodedTile(tileX: tileX, tileY: tileY, tileW: tileW, tileH: tileH, rgb: spatialDataTile)
    }

    /// Same as `decodeTilePayload` but routes the inverse wavelet transform
    /// through the GPU pipeline.
    private func decodeTilePayloadGPU(
        metadata: CodestreamMetadata,
        tileIndex: Int,
        tileData: Data
    ) async throws -> DecodedTile {
        let (tileX, tileY, tileW, tileH) = metadata.tileDimensions(tileIndex: tileIndex)
        var tileMeta = metadata
        tileMeta.width = tileW
        tileMeta.height = tileH
        tileMeta.tileSize = (width: tileW, height: tileH)

        let codeBlocks = try extractTileData(tileData, metadata: tileMeta)
        let (decodedBlocks, gpuBatch) = try await applyEntropyDecoding(codeBlocks, metadata: tileMeta)
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: tileMeta)
        let spatialData = try await applyInverseWaveletTransformGPU(dequantizedSubbands, metadata: tileMeta, gpuBatch: gpuBatch)
        var tileRGB = try await applyInverseColorTransformGPU(spatialData, metadata: tileMeta)

        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < tileRGB.count else { break }
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                tileRGB[compIdx].withUnsafeMutableBufferPointer { buf in
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset, buf.baseAddress!, 1, vDSP_Length(buf.count))
                }
            }
        }
        return DecodedTile(tileX: tileX, tileY: tileY, tileW: tileW, tileH: tileH, rgb: tileRGB)
    }

    /// Composites a decoded tile into the full-image component buffers.
    /// Each tile writes to a non-overlapping rectangle, so calling this
    /// sequentially after all tiles have decoded is safe and fast.
    private func compositeTile(
        _ tile: DecodedTile,
        into fullComponents: inout [[Double]],
        metadata: CodestreamMetadata
    ) {
        let numComponents = metadata.componentCount
        for compIdx in 0..<min(numComponents, tile.rgb.count) {
            let compInfo = metadata.components[compIdx]
            let fullW = metadata.width / compInfo.subsamplingX
            let compTileX = tile.tileX / compInfo.subsamplingX
            let compTileY = tile.tileY / compInfo.subsamplingY
            let compTileW = tile.tileW / compInfo.subsamplingX
            let compTileH = tile.tileH / compInfo.subsamplingY

            tile.rgb[compIdx].withUnsafeBufferPointer { srcBuf in
                fullComponents[compIdx].withUnsafeMutableBufferPointer { dstBuf in
                    let srcP = srcBuf.baseAddress!
                    let dstP = dstBuf.baseAddress!
                    for row in 0..<compTileH {
                        let srcOffset = row * compTileW
                        let dstOffset = (compTileY + row) * fullW + compTileX
                        let copyW = min(compTileW, srcBuf.count - srcOffset)
                        guard copyW > 0, dstOffset + copyW <= dstBuf.count else { continue }
                        (dstP + dstOffset).update(from: srcP + srcOffset, count: copyW)
                    }
                }
            }
        }
    }

    private func decodeMultiTile(
        metadata: CodestreamMetadata,
        tiles: [(tileIndex: Int, tileData: Data)],
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        let numComponents = metadata.componentCount

        // Prepare full-image component buffers
        var fullComponents: [[Double]] = (0..<numComponents).map { compIdx in
            let compInfo = metadata.components[compIdx]
            let w = metadata.width / compInfo.subsamplingX
            let h = metadata.height / compInfo.subsamplingY
            return [Double](repeating: 0.0, count: w * h)
        }

        reportProgress(progress, stage: .tileExtraction, stageProgress: 0.0)

        // Tiles are independent: extract → entropy decode → dequant → IDWT
        // → colour transform → DC unshift can run concurrently because each
        // task allocates its own scratch buffers and writes to its own
        // tileRGB. Composition into `fullComponents` runs sequentially after
        // all tiles complete (each tile occupies a unique rectangle, so the
        // writes don't collide, but Swift's [Double] would CoW under
        // concurrent withUnsafeMutableBufferPointer — sequential composite
        // sidesteps that without measurable cost since composite is just
        // memcpy).
        //
        // v5.12: bounded concurrency. Same chunked-TaskGroup pattern
        // as the GPU multi-tile path; see decodeMultiTileGPU for
        // rationale. CPU concurrency cap at `maxInFlightTilesCPU`
        // primarily prevents unbounded memory growth on codestreams
        // with many large tiles — Swift's structured concurrency
        // already throttles compute via cooperative scheduling.
        var decodedTiles: [DecodedTile] = []
        decodedTiles.reserveCapacity(tiles.count)
        let chunkSize = max(1, Self.maxInFlightTilesCPU)
        var tileIdx = 0
        while tileIdx < tiles.count {
            let end = min(tileIdx + chunkSize, tiles.count)
            let chunk = Array(tiles[tileIdx..<end])
            let chunkResults = try await withThrowingTaskGroup(of: DecodedTile.self) { group in
                for tile in chunk {
                    let captured = tile
                    let metadataCopy = metadata
                    group.addTask {
                        try await self.decodeTilePayload(
                            metadata: metadataCopy,
                            tileIndex: captured.tileIndex,
                            tileData: captured.tileData
                        )
                    }
                }
                var results: [DecodedTile] = []
                results.reserveCapacity(chunk.count)
                for try await decoded in group {
                    results.append(decoded)
                }
                return results
            }
            decodedTiles.append(contentsOf: chunkResults)
            tileIdx = end
        }

        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        for tile in decodedTiles {
            compositeTile(tile, into: &fullComponents, metadata: metadata)
        }

        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        let image = try reconstructImage(fullComponents, metadata: metadata)
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)

        return image
    }

    // MARK: - Stage 1: Codestream Parsing

    /// Parses the JPEG 2000 codestream and extracts metadata and tile data.
    private func parseCodestream(_ data: Data) throws -> (CodestreamMetadata, [(tileIndex: Int, tileData: Data)]) {
        var reader = J2KBitReader(data: data)

        // Verify SOC marker
        guard try reader.readMarker() == J2KMarker.soc.rawValue else {
            throw J2KError.decodingError("Invalid codestream: missing SOC marker")
        }

        var metadata: CodestreamMetadata?
        var configuration = DecoderConfiguration()
        var quantizationSteps: (steps: [String: Double], guardBits: Int, bandKb: [String: Int]) = ([:], 2, [:])
        var tiles: [(tileIndex: Int, tileData: Data)] = []

        // Parse main header markers
        while reader.position < data.count {
            let marker = try reader.readMarker()

            switch marker {
            case J2KMarker.siz.rawValue:
                // Parse SIZ marker
                metadata = try parseSIZMarker(&reader)

            case J2KMarker.cod.rawValue:
                // Parse COD marker
                configuration = try parseCODMarker(&reader)

            case J2KMarker.qcd.rawValue:
                // Parse QCD marker
                let bitDepth = metadata?.components.first?.bitDepth ?? 8
                quantizationSteps = try parseQCDMarker(&reader, config: configuration, bitDepth: bitDepth)

            case J2KMarker.com.rawValue:
                // COM carries the J2KSwift private block-format signal.
                // Promote the configuration to `.conformant` when we
                // recognize the payload; otherwise ignore the comment.
                if try parseHTBlockFormatCOM(&reader) {
                    configuration.htj2kBlockFormat = .conformant
                    configuration.htBlockFormatExplicit = true
                }

            case J2KMarker.sot.rawValue:
                // Start of tile-part — collect all tiles
                let (tileIndex, tilepartData) = try parseSOTMarker(&reader)
                tiles.append((tileIndex: tileIndex, tileData: tilepartData))

            case J2KMarker.eoc.rawValue:
                // End of codestream
                break

            default:
                // Skip unknown marker segment
                if marker >= 0xFF30 {
                    let length = Int(try reader.readUInt16())
                    if length > 2 {
                        try reader.skip(length - 2)
                    }
                }
            }

            if marker == J2KMarker.eoc.rawValue {
                break
            }
        }

        guard var meta = metadata else {
            throw J2KError.decodingError("Missing SIZ marker in codestream")
        }

        meta.configuration = configuration
        meta.quantizationSteps = quantizationSteps.steps
        meta.quantizationGuardBits = quantizationSteps.guardBits
        meta.bandKbValues = quantizationSteps.bandKb

        // If no tiles were found via SOT, but we have remaining data,
        // treat everything after the main header as a single tile
        if tiles.isEmpty {
            // Calculate remaining data after main header
            let remaining = data.subdata(in: reader.position..<data.count)
            if !remaining.isEmpty {
                tiles.append((tileIndex: 0, tileData: remaining))
            }
        }

        return (meta, tiles)
    }

    /// Parses the SIZ marker segment.
    private func parseSIZMarker(_ reader: inout J2KBitReader) throws -> CodestreamMetadata {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        // Rsiz — Capabilities
        _ = try reader.readUInt16()

        // Image dimensions
        let width = Int(try reader.readUInt32())
        let height = Int(try reader.readUInt32())

        // Image offset
        let xOsiz = Int(try reader.readUInt32())
        let yOsiz = Int(try reader.readUInt32())

        // Tile dimensions
        let tileWidth = Int(try reader.readUInt32())
        let tileHeight = Int(try reader.readUInt32())

        // Tile offset
        let xtOsiz = Int(try reader.readUInt32())
        let ytOsiz = Int(try reader.readUInt32())

        // Number of components
        let componentCount = Int(try reader.readUInt16())

        // Parse component information
        var components: [CodestreamMetadata.ComponentInfo] = []
        for _ in 0..<componentCount {
            let ssiz = try reader.readUInt8()
            let signed = (ssiz & 0x80) != 0
            let bitDepth = Int((ssiz & 0x7F)) + 1
            let subsamplingX = Int(try reader.readUInt8())
            let subsamplingY = Int(try reader.readUInt8())

            components.append(CodestreamMetadata.ComponentInfo(
                bitDepth: bitDepth,
                signed: signed,
                subsamplingX: subsamplingX,
                subsamplingY: subsamplingY
            ))
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return CodestreamMetadata(
            width: width,
            height: height,
            componentCount: componentCount,
            components: components,
            tileSize: (width: tileWidth, height: tileHeight),
            imageOffset: (x: xOsiz, y: yOsiz),
            tileOffset: (x: xtOsiz, y: ytOsiz),
            configuration: DecoderConfiguration(),
            quantizationSteps: [:],
            quantizationGuardBits: 2,
            bandKbValues: [:]
        )
    }

    /// Parses the COD marker segment.
    private func parseCODMarker(_ reader: inout J2KBitReader) throws -> DecoderConfiguration {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        var config = DecoderConfiguration()

        // Scod — Coding style flags
        let scod = try reader.readUInt8()
        // Bits 3-4: HT set extensions (legacy non-standard; current encoder
        // no longer sets these, but decode them for backward compatibility).
        let htSetBits = (scod >> 3) & 0x03
        let hasHTSets = htSetBits != 0

        // Progression order
        let progOrder = try reader.readUInt8()
        switch progOrder {
        case 0: config.progressionOrder = .lrcp
        case 1: config.progressionOrder = .rlcp
        case 2: config.progressionOrder = .rpcl
        case 3: config.progressionOrder = .pcrl
        case 4: config.progressionOrder = .cprl
        default: config.progressionOrder = .lrcp
        }

        // Number of layers
        config.qualityLayers = Int(try reader.readUInt16())

        // Multiple component transform
        let mct = try reader.readUInt8()
        config.useReversibleTransform = (mct == 1)

        // Number of decomposition levels
        config.decompositionLevels = Int(try reader.readUInt8())

        // Code-block dimensions
        let cbWidthExp = Int(try reader.readUInt8()) + 2
        let cbHeightExp = Int(try reader.readUInt8()) + 2
        config.codeBlockSize = (width: 1 << cbWidthExp, height: 1 << cbHeightExp)

        // Code-block style
        // Bit 0: Selective arithmetic coding bypass
        // Bit 6: HT block coding (1 = HTJ2K, 0 = legacy EBCOT)
        let codeBlockStyle = try reader.readUInt8()
        config.useSelectiveArithmeticBypass = (codeBlockStyle & 0x01) != 0
        config.useHTJ2K = (codeBlockStyle & 0x40) != 0

        // Wavelet transform type
        let transformType = try reader.readUInt8()
        config.waveletFilter = (transformType == 1) ? .reversible53 : .irreversible97

        // HT set parameters (ISO/IEC 15444-15) — only when bits 3-4 of Scod are non-zero
        // If HT sets are signaled, the configuration byte must be read regardless of useHTJ2K flag
        if hasHTSets {
            // Read HT set configuration byte
            _ = try reader.readUInt8()
            // We read and ignore for now - parameters are advisory
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return config
    }

    /// Parses the COC marker segment (Coding Style Component).
    ///
    /// The COC marker provides per-component coding parameters that override
    /// the default COD parameters for a specific component.
    ///
    /// - Parameters:
    ///   - reader: The bit reader to read from.
    ///   - componentCount: Total number of components in the image.
    ///   - baseConfig: The base configuration from COD marker.
    /// - Returns: A tuple of (component index, component-specific configuration).
    private func parseCOCMarker(
        _ reader: inout J2KBitReader,
        componentCount: Int,
        baseConfig: DecoderConfiguration
    ) throws -> (componentIndex: Int, config: DecoderConfiguration) {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        // Start with base configuration
        var config = baseConfig

        // Ccoc — Component index
        let componentIndex: Int
        if componentCount < 257 {
            // 1 byte for component index
            componentIndex = Int(try reader.readUInt8())
        } else {
            // 2 bytes for component index
            componentIndex = Int(try reader.readUInt16())
        }

        // Scoc — Coding style for this component

        // Number of decomposition levels
        config.decompositionLevels = Int(try reader.readUInt8())

        // Code-block dimensions
        let cbWidthExp = Int(try reader.readUInt8()) + 2
        let cbHeightExp = Int(try reader.readUInt8()) + 2
        config.codeBlockSize = (width: 1 << cbWidthExp, height: 1 << cbHeightExp)

        // Code-block style
        // Bit 0: Selective arithmetic coding bypass
        // Bit 6: HT block coding (1 = HTJ2K, 0 = legacy EBCOT)
        let codeBlockStyle = try reader.readUInt8()
        config.useSelectiveArithmeticBypass = (codeBlockStyle & 0x01) != 0
        config.useHTJ2K = (codeBlockStyle & 0x40) != 0

        // Wavelet transform type
        let transformType = try reader.readUInt8()
        config.waveletFilter = (transformType == 1) ? .reversible53 : .irreversible97

        // HT set parameters (ISO/IEC 15444-15) — only when HTJ2K is enabled
        // Note: COC doesn't have its own Scod, so we check if HTJ2K mode is set
        if config.useHTJ2K {
            // Check if there's enough data left to read HT set configuration byte
            let currentBytesRead = reader.position - startPos
            if currentBytesRead < length - 2 {
                // Read HT set configuration byte
                _ = try reader.readUInt8()
                // We read and ignore for now - parameters are advisory
            }
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return (componentIndex, config)
    }

    /// Parses the QCD marker segment.
    private func parseQCDMarker(
        _ reader: inout J2KBitReader,
        config: DecoderConfiguration,
        bitDepth: Int = 8
    ) throws -> (steps: [String: Double], guardBits: Int, bandKb: [String: Int]) {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        var stepSizes: [String: Double] = [:]
        var bandKb: [String: Int] = [:]

        // Sqcd — Quantization style
        let sqcd = try reader.readUInt8()
        let quantStyle = sqcd & 0x1F
        let guardBits = Int((sqcd >> 5) & 0x07)

        if quantStyle == 0 {
            // No quantization (reversible) — step size is 1.0
            // Read exponent values (used only for Kb computation)
            let llExp = Int(try reader.readUInt8() >> 3)
            stepSizes["LL_0"] = 1.0
            bandKb["LL_0"] = llExp + guardBits - 1  // Kb = εb + Gb - 1

            if config.decompositionLevels > 0 {
                for level in 1...config.decompositionLevels {
                    for subband in ["HL", "LH", "HH"] {
                        let exp = Int(try reader.readUInt8() >> 3)
                        stepSizes["\(subband)_\(level)"] = 1.0
                        bandKb["\(subband)_\(level)"] = exp + guardBits - 1  // Kb = εb + Gb - 1
                    }
                }
            }
        } else if quantStyle == 2 {
            // Scalar expounded quantization.
            // For the 9/7 irreversible path, the stored QCD exponents are
            // interpreted using the base image precision for every subband.
            // This matches the encoder's OpenJPEG-compatible signaling and keeps
            // the dequantization step sizes consistent across decode paths.
            let baseRangeBits = bitDepth

            func decodeStepSize(_ value: UInt16, subbandGain: Int) -> Double {
                let exp = Int((value >> 11) & 0x1F)
                let mant = Double(value & 0x7FF)
                let rangeBits = baseRangeBits + subbandGain
                return pow(2.0, Double(rangeBits - exp)) * (1.0 + mant / 2048.0)
            }

            // LL subband (gain = 0)
            let llValue = try reader.readUInt16()
            let llExp = Int((llValue >> 11) & 0x1F)
            stepSizes["LL_0"] = decodeStepSize(llValue, subbandGain: 0)
            bandKb["LL_0"] = llExp + guardBits - 1  // Kb = εb + Gb - 1

            if config.decompositionLevels > 0 {
                for level in 1...config.decompositionLevels {
                    for subband in ["HL", "LH", "HH"] {
                        let value = try reader.readUInt16()
                        let exp = Int((value >> 11) & 0x1F)
                        let gainExponent: Int
                        switch subband {
                        case "HL", "LH": gainExponent = 1
                        case "HH": gainExponent = 2
                        default: gainExponent = 0
                        }
                        stepSizes["\(subband)_\(level)"] = decodeStepSize(value, subbandGain: gainExponent)
                        bandKb["\(subband)_\(level)"] = exp + guardBits - 1  // Kb = εb + Gb - 1
                    }
                }
            }
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return (steps: stepSizes, guardBits: guardBits, bandKb: bandKb)
    }

    /// Parses a COM (comment) marker and returns `true` iff the
    /// payload matches the J2KSwift block-format signature that
    /// signals `.conformant` HTJ2K blocks.
    private func parseHTBlockFormatCOM(_ reader: inout J2KBitReader) throws -> Bool {
        let length = Int(try reader.readUInt16())
        // Lcom includes the length field itself but not the marker.
        // Payload = Rcom(2) + Ccom(length - 4).
        guard length >= 4 else {
            // Malformed but non-fatal — skip.
            if length > 2 { try reader.skip(length - 2) }
            return false
        }
        _ = try reader.readUInt16() // Rcom, ignored for signature match
        let ccomLen = length - 4
        let payload = try reader.readBytes(ccomLen)
        let signature = HTBlockFormatCOMSignature.conformant
        guard payload.count == signature.count else { return false }
        return zip(payload, signature).allSatisfy { $0 == $1 }
    }

    /// Parses the SOT marker segment and extracts tile data.
    private func parseSOTMarker(_ reader: inout J2KBitReader) throws -> (Int, Data) {
        _ = Int(try reader.readUInt16())

        // Isot — Tile index
        let tileIndex = Int(try reader.readUInt16())

        // Psot — Tile-part length
        let tilepartLength = Int(try reader.readUInt32())

        // TPsot — Tile-part index
        _ = try reader.readUInt8()

        // TNsot — Number of tile-parts
        _ = try reader.readUInt8()

        // Find SOD marker
        guard try reader.readMarker() == J2KMarker.sod.rawValue else {
            throw J2KError.decodingError("Missing SOD marker after SOT")
        }

        // Calculate data length
        // tilepartLength includes SOT marker (2) + length (2) + segment (8) + SOD marker (2)
        let dataLength = tilepartLength - 14

        // Extract tile data
        let tileData = try reader.readBytes(dataLength)

        return (tileIndex, tileData)
    }

    // MARK: - Stage 2: Tile Extraction

    /// Information about a code block extracted from tile data.
    struct CodeBlockInfo: Sendable {
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let data: Data
        let passCount: Int
        let zeroBitPlanes: Int
        let bandKb: Int
    }

    /// Extracts code blocks from tile data using ISO/IEC 15444-1 packet format.
    ///
    /// Parses packet headers using tag trees for code-block inclusion and
    /// zero bit-planes, Table B.4 for coding passes, and Lblock for data lengths.
    private func extractTileData(
        _ tileData: Data,
        metadata: CodestreamMetadata
    ) throws -> [CodeBlockInfo] {
        var blocks: [CodeBlockInfo] = []

        let cbWidth = metadata.configuration.codeBlockSize.width
        let cbHeight = metadata.configuration.codeBlockSize.height
        let levels = metadata.configuration.decompositionLevels
        let tileWidth = metadata.tileSize.width
        let tileHeight = metadata.tileSize.height
        let numComponents = metadata.components.count
        var reader = J2KBitReader(data: tileData)
        // Enable JPEG 2000 byte stuffing for packet headers (ISO 15444-1 B.10.1)
        reader.setByteStuffing(true)

        // LRCP progression: Layer → Resolution → Component → Position
        // Single layer for now
        for resLevel in 0...levels {
            for compIdx in 0..<numComponents {
                // Read non-empty packet flag
                guard reader.bytesRemaining > 0 || reader.bitOffset > 0 else { break }
                let notEmpty = try reader.readBit()
                guard notEmpty else {
                    // Empty packet: align to byte boundary per ISO 15444-1 B.10.
                    // Each packet starts on a byte boundary. The encoder writes the
                    // empty flag bit and then pads to the next byte boundary.
                    try reader.alignToByte()
                    continue
                }

                let subbands: [J2KSubband] = resLevel == 0 ? [.ll] : [.hl, .lh, .hh]

                // Track included blocks for data extraction after header
                struct PendingBlock {
                    let componentIndex: Int
                    let decomLevel: Int
                    let subband: J2KSubband
                    let x, y, width, height: Int
                    let passCount: Int
                    let zeroBitPlanes: Int
                    let bandKb: Int
                    let dataLength: Int
                }
                var pendingBlocks: [PendingBlock] = []

                for subband in subbands {
                    // Compute subband dimensions
                    let (sbWidth, sbHeight) = Self.subbandDimensions(
                        tileWidth: tileWidth, tileHeight: tileHeight,
                        levels: levels, resLevel: resLevel, subband: subband
                    )
                    guard sbWidth > 0 && sbHeight > 0 else { continue }

                    let blocksX = (sbWidth + cbWidth - 1) / cbWidth
                    let blocksY = (sbHeight + cbHeight - 1) / cbHeight
                    let blockCount = blocksX * blocksY

                    // Look up band Kb from QCD metadata
                    let bandKey: String
                    if subband == .ll {
                        bandKey = "LL_0"
                    } else {
                        bandKey = "\(subband.rawValue)_\(resLevel)"
                    }
                    let kb = metadata.bandKbValues[bandKey] ?? (metadata.components[compIdx].bitDepth + metadata.quantizationGuardBits)

                    // Convert resolution level to decomposition level
                    let decomLevel = resLevel == 0 ? 0 : (levels - resLevel + 1)

                    // Create tag trees for this band
                    var inclusionTree = J2KTagTree(width: blocksX, height: blocksY)
                    var zbpTree = J2KTagTree(width: blocksX, height: blocksY)

                    for leafIdx in 0..<blockCount {
                        // Decode inclusion via tag tree (threshold=1 for layer 0)
                        let included = try inclusionTree.decode(
                            reader: &reader, leafIndex: leafIdx, threshold: 1
                        )
                        guard included else { continue }

                        // Decode zero bit-planes via tag tree
                        var zbp: Int32 = 0
                        while !(try zbpTree.decode(reader: &reader, leafIndex: leafIdx, threshold: zbp + 1)) {
                            zbp += 1
                            if zbp > 100 { break }
                        }

                        // Decode coding passes (ISO Table B.4)
                        let passes = try Self.decodeCodingPasses(&reader)

                        // Decode data length (Lblock + floor(log2(numpasses)))
                        let length = try Self.decodeDataLength(&reader, numPasses: passes)

                        let blockX = (leafIdx % blocksX) * cbWidth
                        let blockY = (leafIdx / blocksX) * cbHeight
                        let actualW = min(cbWidth, sbWidth - blockX)
                        let actualH = min(cbHeight, sbHeight - blockY)

                        pendingBlocks.append(PendingBlock(
                            componentIndex: compIdx,
                            decomLevel: decomLevel,
                            subband: subband,
                            x: blockX, y: blockY,
                            width: actualW, height: actualH,
                            passCount: passes,
                            zeroBitPlanes: Int(zbp),
                            bandKb: kb,
                            dataLength: length
                        ))
                    }
                }

                // Byte-align after packet header
                try reader.alignToByte()
                // Disable byte stuffing for raw code-block data
                reader.setByteStuffing(false)

                // Read code-block data in band order
                for pb in pendingBlocks {
                    let blockData = try reader.readBytes(pb.dataLength)
                    blocks.append(CodeBlockInfo(
                        componentIndex: pb.componentIndex,
                        level: pb.decomLevel,
                        subband: pb.subband,
                        x: pb.x, y: pb.y,
                        width: pb.width, height: pb.height,
                        data: blockData,
                        passCount: pb.passCount,
                        zeroBitPlanes: pb.zeroBitPlanes,
                        bandKb: pb.bandKb
                    ))
                }
                // Re-enable byte stuffing for next packet header
                reader.setByteStuffing(true)
            }
        }

        return blocks
    }

    /// Computes subband dimensions for a given resolution level and subband type.
    private static func subbandDimensions(
        tileWidth: Int, tileHeight: Int,
        levels: Int, resLevel: Int, subband: J2KSubband
    ) -> (width: Int, height: Int) {
        if resLevel == 0 {
            // LL at deepest decomposition level
            var w = tileWidth, h = tileHeight
            for _ in 0..<levels {
                w = (w + 1) / 2
                h = (h + 1) / 2
            }
            return (w, h)
        } else {
            // Detail subband at decomposition level d = levels - resLevel + 1
            // Parent LL is at decomposition level (d - 1)
            let d = levels - resLevel + 1
            var w = tileWidth, h = tileHeight
            for _ in 0..<(d - 1) {
                w = (w + 1) / 2
                h = (h + 1) / 2
            }
            // Parent dimensions are (w, h). DWT splits into:
            switch subband {
            case .ll: return ((w + 1) / 2, (h + 1) / 2)
            case .hl: return (w / 2, (h + 1) / 2)
            case .lh: return ((w + 1) / 2, h / 2)
            case .hh: return (w / 2, h / 2)
            }
        }
    }

    /// Decodes the number of coding passes per ISO/IEC 15444-1 Table B.4.
    private static func decodeCodingPasses(_ reader: inout J2KBitReader) throws -> Int {
        if !(try reader.readBit()) { return 1 }   // 0 → 1 pass
        if !(try reader.readBit()) { return 2 }   // 10 → 2 passes
        // 11...
        let b3 = try reader.readBit()
        let b4 = try reader.readBit()
        if !(b3 && b4) {
            return 3 + (b3 ? 2 : 0) + (b4 ? 1 : 0) // 1100→3, 1101→4, 1110→5
        }
        // 1111 → read 5-bit value per ISO 15444-1 Table B.4
        let value5 = Int(try reader.readBits(5))
        if value5 < 31 {
            return 6 + value5                         // 1111 XXXXX → 6-36
        }
        return 37 + Int(try reader.readBits(7))      // 1111 11111 XXXXXXX → 37-164
    }

    /// Decodes data length using the Lblock mechanism per ISO 15444-1 B.10.7.
    /// Total bits = Lblock + floor(log2(numpasses)).
    private static func decodeDataLength(_ reader: inout J2KBitReader, numPasses: Int) throws -> Int {
        var lblock = 3
        while try reader.readBit() { lblock += 1 }
        let passLog = numPasses > 1 ? Int(log2(Double(numPasses))) : 0
        let totalBits = lblock + passLog
        return Int(try reader.readBits(totalBits))
    }

    // MARK: - Stage 3: Entropy Decoding

    /// Decoded subband information.
    struct SubbandInfo: Sendable {
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let coefficients: [Int32]
        /// Double-precision dequantized coefficients for the irreversible 9/7 path.
        /// When populated, the inverse DWT uses these directly to avoid
        /// precision loss from Int32 rounding of fractional dequantized values.
        let doubleCoefficients: [Double]?
        let width: Int
        let height: Int
        /// Per-coefficient mask set to `true` where the HTJ2K block decoder
        /// applied a block-level partial-refinement midpoint. When non-empty
        /// and for the irreversible HT path, dequantization must skip the
        /// quantization bin midpoint (`+0.5 * stepSize`) for those coefficients
        /// to avoid the double-midpoint bias.
        let htPartiallyRefined: [Bool]

        init(
            componentIndex: Int,
            level: Int,
            subband: J2KSubband,
            coefficients: [Int32],
            doubleCoefficients: [Double]?,
            width: Int,
            height: Int,
            htPartiallyRefined: [Bool] = []
        ) {
            self.componentIndex = componentIndex
            self.level = level
            self.subband = subband
            self.coefficients = coefficients
            self.doubleCoefficients = doubleCoefficients
            self.width = width
            self.height = height
            self.htPartiallyRefined = htPartiallyRefined
        }
    }

    /// Applies entropy decoding to code blocks.
    ///
    /// When `metadata.configuration.useHTJ2K` is true, uses HTJ2K FBCOT block
    /// decoding (ISO/IEC 15444-15). Otherwise uses legacy EBCOT bit-plane
    /// decoding (ISO/IEC 15444-1).
    private func applyEntropyDecoding(
        _ blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata
    ) async throws -> (subbands: [SubbandInfo], batch: J2KGPUHTBatch?) {
        let isIrreversible: Bool
        if case .irreversible97 = metadata.configuration.waveletFilter {
            isIrreversible = true
        } else {
            isIrreversible = false
        }
        let useHT = metadata.configuration.useHTJ2K
        // Format dispatch:
        //   1. If the codestream carried an explicit J2KSwift HT block-format
        //      COM marker, trust it.
        //   2. Otherwise default to `.conformant` (matches the ISO Part-15
        //      bytes emitted by OpenJPH / Kakadu).
        //   3. Run a structural heuristic on the first non-empty codeblock
        //      so legacy J2KSwift `.custom` archives (which pre-date the COM
        //      marker) are still picked up automatically.
        var resolvedFormat = metadata.configuration.htj2kBlockFormat
        if useHT && !metadata.configuration.htBlockFormatExplicit {
            for block in blocks where !block.data.isEmpty {
                resolvedFormat = detectHTBlockFormat(block.data)
                break
            }
        }
        let useConformant = useHT && resolvedFormat == .conformant

        // v5.9 zero-copy fast-lane.
        //
        // When the v5.8 fused-DWT path is going to be active
        // downstream (session + reversible 5/3 + conformant HT +
        // all-blocks-eligible) AND the IDWT itself will run on GPU,
        // the LH/HL/HH `[SubbandInfo]` we'd build via the CPU
        // regroup loop are dead code — the fused DWT consumes them
        // straight off the GPU codeblock buffer via the scatter
        // kernel. The fast lane skips the regroup entirely and only
        // produces the LL `[SubbandInfo]` that the outermost-level
        // DWT initialLL upload still needs.
        //
        // Memcpy budget on the fast-lane: O(LL codeblocks per
        // component) — typically 1–4 per component on 5-decomp
        // images. Down from O(all codeblocks) on the slow-lane.
        //
        // The downstream-IDWT-path precondition (`idwtWillBeGPU`)
        // mirrors `applyInverseWaveletTransformGPU`'s own gate.
        // When that gate fails, the IDWT falls back to CPU
        // `applyInverseWaveletTransform`, which expects
        // `[SubbandInfo]` for *all* subbands — and the fast lane
        // only provides LL. The mr_002 fixture (180×180 = 32400 px)
        // is the canonical case: GPU IDWT requires
        // `pixelCount >= 256*256`, so the small-image path goes to
        // CPU. Without this gate the fast lane fires anyway, the
        // CPU IDWT sees empty LH/HL/HH, and 30541/64800 output
        // bytes diverge from the sessionless reference.
        // `testCorpusSessionAndSessionlessAgreeBitExact` is the
        // regression gate.
        let pixelCount = metadata.width * metadata.height
        let dwtLevels = metadata.configuration.decompositionLevels
        let idwtWillBeGPU =
            pixelCount >= 256 * 256 &&
            dwtLevels >= 1 &&
            metadata.configuration.waveletKernelConfiguration == nil &&
            J2KMetalDWT.isAvailable
        if idwtWillBeGPU,
           !isIrreversible, useHT, useConformant, useGPUHT,
           let session = metalSession, !blocks.isEmpty,
           J2KGPUHTDispatch.isAvailable,
           blocks.allSatisfy({ !$0.data.isEmpty && $0.passCount > 0 }) {
            if let fastLane = try await runZeroCopyFastLane(
                blocks: blocks, metadata: metadata, session: session)
            {
                return fastLane
            }
            // fall through to slow-lane below
        }

        // M2-prime / v5.8 unified early GPU pass.
        //
        // - Sessionless or non-reversible-5/3: take the v5.6.0 path
        //   that calls `J2KGPUHTDispatch.decodeBatch` and returns
        //   per-block [Int32] coefficients; no batch.
        // - Session + reversible-5/3 + all-blocks-eligible: take
        //   the v5.8 fused path via `decodeBatchGPUResident` —
        //   ONE GPU decode produces both per-block [Int32] (sliced
        //   from the codeblock buffer's shared memory) AND the
        //   GPU-resident batch consumed by
        //   `inverse2DInt32FullFusedFromCodeblocks` downstream. No
        //   duplicate decode work.
        //
        // `gpuPreDecoded` feeds the existing per-block CPU regroup
        // loop below (so `[SubbandInfo]` is populated identically
        // to v5.7.0). `gpuBatch` is non-nil only on the fused path.
        let isIrreversibleFilter: Bool = {
            if case .irreversible97 = metadata.configuration.waveletFilter {
                return true
            }
            return false
        }()
        let gpuEarly: (preDecoded: [Int: [Int32]], batch: J2KGPUHTBatch?) = try await {
            guard useGPUHT, useHT, useConformant,
                  J2KGPUHTDispatch.isAvailable, !blocks.isEmpty
            else { return ([:], nil) }

            var gpuInputs: [GPUHTBlock] = []
            var inputOriginalIndices: [Int] = []
            for (i, block) in blocks.enumerated() {
                guard !block.data.isEmpty, block.passCount > 0 else { continue }
                gpuInputs.append(GPUHTBlock(
                    width: block.width,
                    height: block.height,
                    data: [UInt8](block.data),
                    missingMSBs: block.zeroBitPlanes))
                inputOriginalIndices.append(i)
            }
            if gpuInputs.isEmpty { return ([:], nil) }

            // v5.8 fused path: requires session + reversible 5/3.
            if let session = metalSession, !isIrreversibleFilter {
                if let res = try await J2KGPUHTDispatch.decodeBatchGPUResident(
                    blocks: gpuInputs, session: session)
                {
                    // res.decodedBlockCoefficients +
                    // decodedBlockOutputOffsets are keyed by
                    // dispatcher-input index (gpuInputs index, NOT
                    // pipeline block index). Remap to pipeline
                    // index via inputOriginalIndices.
                    var remappedCoeffs: [Int: [Int32]] = [:]
                    var remappedOffsets: [Int: Int] = [:]
                    for (gpuIdx, coeffs) in res.decodedBlockCoefficients {
                        remappedCoeffs[inputOriginalIndices[gpuIdx]] = coeffs
                    }
                    for (gpuIdx, offset) in res.decodedBlockOutputOffsets {
                        remappedOffsets[inputOriginalIndices[gpuIdx]] = offset
                    }
                    // If any blocks were ineligible (parse failure
                    // etc), return the buffer and fall through with
                    // coeffs only. [SubbandInfo] regroup still
                    // produces correct LH/HL/HH for the non-fused
                    // DWT path; we just skip fusion.
                    if res.cpuFallbackIndices.isEmpty {
                        let batch = buildGPUHTBatchFromResult(
                            codeblockBuffer: res.codeblockBuffer,
                            outputSampleCount: res.outputSampleCount,
                            decodedBlockOutputOffsets: remappedOffsets,
                            blocks: blocks, metadata: metadata,
                            bufferPool: session.bufferPool)
                        return (remappedCoeffs, batch)
                    }
                    await session.bufferPool.returnBuffer(res.codeblockBuffer)
                    return (remappedCoeffs, nil)
                }
            }

            // v5.6.0 path (no session, or 9/7 lossy, or fused
            // dispatcher returned nil).
            let result = try await J2KGPUHTDispatch.decodeBatch(
                blocks: gpuInputs, session: metalSession)
            var dict: [Int: [Int32]] = [:]
            for (i, gpuInputIdx) in result.decodedBlockIndices.enumerated() {
                dict[inputOriginalIndices[gpuInputIdx]] = result.results[i].coefficients
            }
            return (dict, nil)
        }()
        let gpuPreDecoded: [Int: [Int32]] = gpuEarly.preDecoded
        let gpuBatch: J2KGPUHTBatch? = gpuEarly.batch

        // Struct key avoids per-block string interpolation allocations.
        struct SubbandKey: Hashable {
            let componentIndex: Int; let level: Int; let subband: J2KSubband
        }

        // Track subband dimensions and use 2D placement for code blocks
        var subbandDims: [SubbandKey: (width: Int, height: Int)] = [:]
        // Store decoded code blocks with their positions for proper 2D placement
        struct DecodedBlock {
            let x: Int
            let y: Int
            let width: Int
            let height: Int
            let coefficients: [Int32]
            /// Per-coefficient mask set to `true` where the HT block decoder
            /// applied a block-level partial-refinement midpoint. Empty for
            /// EBCOT blocks (which never carry this flag).
            let htPartiallyRefined: [Bool]
        }
        var subbandBlocks: [SubbandKey: [DecodedBlock]] = [:]

        let blockCount = blocks.count
        // Each EBCOT code block is independently decodable: own MQ state, context models,
        // coefficient arrays. DecoderScratchBuffers are per-task (not shared). Thread-safe
        // for all bit depths and filter types.
        let shouldParallelDecodeBlocks = blockCount >= 4

        if shouldParallelDecodeBlocks {
            // === Parallel code block decoding ===
            // Each code block is independent (own MQ state + context models for EBCOT,
            // own MEL/VLC/MagSgn state for HTJ2K).
            let componentBitDepths = metadata.components.map { $0.bitDepth }
            let decodeOptions: CodingOptions = metadata.configuration.useSelectiveArithmeticBypass ? .fastEncoding : .default

            // Parallel decode using structured concurrency with chunking
            let coreCount = ProcessInfo.processInfo.processorCount
            let chunkSize = max(1, blockCount / coreCount)

            let allResults: [([Int32], [Bool])?] = try await withThrowingTaskGroup(
                of: [(Int, [Int32], [Bool])].self
            ) { group in
                for chunkStart in stride(from: 0, to: blockCount, by: chunkSize) {
                    let chunkEnd = min(chunkStart + chunkSize, blockCount)
                    group.addTask {
                        var chunkResults: [(Int, [Int32], [Bool])] = []
                        chunkResults.reserveCapacity(chunkEnd - chunkStart)
                        // One scratch buffer per task — reused across all blocks in the chunk
                        let scratch = useHT ? nil : DecoderScratchBuffers()
                        for i in chunkStart..<chunkEnd {
                            // Skip blocks already decoded on GPU. The
                            // empty `htPartiallyRefined` mask matches the
                            // `useConformant` cleanup-only branch below
                            // (cleanup-only blocks never carry partial
                            // refinement).
                            if let gpuCoeffs = gpuPreDecoded[i] {
                                chunkResults.append((i, gpuCoeffs, []))
                                continue
                            }
                            let block = blocks[i]
                            let bitDepth = block.bandKb > 0 ? block.bandKb : componentBitDepths[block.componentIndex]

                            let coeffs: [Int32]
                            let htPartiallyRefined: [Bool]
                            if useHT {
                                let htDecoder = HTBlockDecoder(
                                    width: block.width,
                                    height: block.height,
                                    subband: block.subband
                                )
                                if useConformant {
                                    // Part-15 conformant blocks are cleanup-only; no refinement
                                    // passes, so the partial-refinement mask is empty.
                                    if block.data.isEmpty || block.passCount == 0 {
                                        coeffs = [Int32](repeating: 0, count: block.width * block.height)
                                    } else {
                                        coeffs = try htDecoder.decodeCleanupConformant(
                                            rawBytes: [UInt8](block.data),
                                            missingMSBs: block.zeroBitPlanes)
                                    }
                                    htPartiallyRefined = []
                                } else {
                                    let detailed = try htDecoder
                                        .decodeFromCodestreamDetailed(
                                            data: block.data,
                                            passCount: block.passCount,
                                            bitDepth: bitDepth,
                                            zeroBitPlanes: block.zeroBitPlanes)
                                    coeffs = detailed.coefficients
                                    htPartiallyRefined = detailed.isPartiallyRefined
                                }
                            } else {
                                let blockDecoder = CodeBlockDecoder()
                                let codeBlock = J2KCodeBlock(
                                    index: 0,
                                    x: block.x,
                                    y: block.y,
                                    width: block.width,
                                    height: block.height,
                                    subband: block.subband,
                                    data: block.data,
                                    passeCount: block.passCount,
                                    zeroBitPlanes: block.zeroBitPlanes
                                )
                                coeffs = try blockDecoder.decode(
                                    codeBlock: codeBlock,
                                    bitDepth: bitDepth,
                                    options: decodeOptions,
                                    irreversible: isIrreversible,
                                    scratch: scratch
                                )
                                htPartiallyRefined = []
                            }
                            chunkResults.append((i, coeffs, htPartiallyRefined))
                        }
                        return chunkResults
                    }
                }
                // Pre-allocated array indexed by block index avoids hash-table overhead
            var resultsArray = [([Int32], [Bool])?](repeating: nil, count: blockCount)
                for try await chunk in group {
                    for (i, coeffs, mask) in chunk {
                        resultsArray[i] = (coeffs, mask)
                    }
                }
                return resultsArray
            }

            // Collect results sequentially
            for i in 0..<blockCount {
                let block = blocks[i]
                var coeffs: [Int32]
                var htMask: [Bool]
                if let entry = allResults[i] {
                    coeffs = entry.0
                    htMask = entry.1
                } else {
                    coeffs = [Int32](repeating: 0, count: block.width * block.height)
                    htMask = []
                }

                let key = SubbandKey(componentIndex: block.componentIndex, level: block.level, subband: block.subband)

                let currentWidth = subbandDims[key]?.width ?? 0
                let currentHeight = subbandDims[key]?.height ?? 0
                subbandDims[key] = (
                    width: max(currentWidth, block.x + block.width),
                    height: max(currentHeight, block.y + block.height)
                )

                if subbandBlocks[key] == nil {
                    subbandBlocks[key] = []
                }
                subbandBlocks[key]?.append(DecodedBlock(
                    x: block.x, y: block.y,
                    width: block.width, height: block.height,
                    coefficients: coeffs,
                    htPartiallyRefined: htMask
                ))
            }
        } else {
            // Sequential path for small block counts
            let decodeOptions: CodingOptions = metadata.configuration.useSelectiveArithmeticBypass ? .fastEncoding : .default
            for (blockIdx, block) in blocks.enumerated() {
                let compInfo = metadata.components[block.componentIndex]
                let bitDepth = block.bandKb > 0 ? block.bandKb : compInfo.bitDepth
                let coeffs: [Int32]
                let htMask: [Bool]

                if let gpuCoeffs = gpuPreDecoded[blockIdx] {
                    // GPU early pass already decoded this block.
                    // Empty htMask matches the useConformant cleanup-only
                    // branch (cleanup-only blocks never carry partial
                    // refinement).
                    coeffs = gpuCoeffs
                    htMask = []
                } else if useHT {
                    // HTJ2K path: use FBCOT block decoding.
                    let htDecoder = HTBlockDecoder(
                        width: block.width,
                        height: block.height,
                        subband: block.subband
                    )
                    if useConformant {
                        if block.data.isEmpty || block.passCount == 0 {
                            coeffs = [Int32](repeating: 0, count: block.width * block.height)
                        } else {
                            coeffs = try htDecoder.decodeCleanupConformant(
                                rawBytes: [UInt8](block.data),
                                missingMSBs: block.zeroBitPlanes)
                        }
                        htMask = []
                    } else {
                        let detailed = try htDecoder.decodeFromCodestreamDetailed(
                            data: block.data,
                            passCount: block.passCount,
                            bitDepth: bitDepth,
                            zeroBitPlanes: block.zeroBitPlanes
                        )
                        coeffs = detailed.coefficients
                        htMask = detailed.isPartiallyRefined
                    }
                } else {
                    // Legacy path: use EBCOT bit-plane decoding
                    let decoder = CodeBlockDecoder()
                    let codeBlock = J2KCodeBlock(
                        index: 0,
                        x: block.x,
                        y: block.y,
                        width: block.width,
                        height: block.height,
                        subband: block.subband,
                        data: block.data,
                        passeCount: block.passCount,
                        zeroBitPlanes: block.zeroBitPlanes
                    )
                    coeffs = try decoder.decode(
                        codeBlock: codeBlock,
                        bitDepth: bitDepth,
                        options: decodeOptions,
                        irreversible: isIrreversible
                    )
                    htMask = []
                }

                let key = SubbandKey(componentIndex: block.componentIndex, level: block.level, subband: block.subband)

                let currentWidth = subbandDims[key]?.width ?? 0
                let currentHeight = subbandDims[key]?.height ?? 0
                subbandDims[key] = (
                    width: max(currentWidth, block.x + block.width),
                    height: max(currentHeight, block.y + block.height)
                )

                if subbandBlocks[key] == nil {
                    subbandBlocks[key] = []
                }
                subbandBlocks[key]?.append(DecodedBlock(
                    x: block.x, y: block.y,
                    width: block.width, height: block.height,
                    coefficients: coeffs,
                    htPartiallyRefined: htMask
                ))
            }
        }

        // Scatter code block coefficients into proper 2D subband positions
        var subbands: [SubbandInfo] = []
        for (key, decodedBlocks) in subbandBlocks {
            guard let dims = subbandDims[key] else { continue }

            let compIdx = key.componentIndex
            let level = key.level
            let subbandType = key.subband

            // Create subband buffer and place each code block at its correct position
            var subbandCoeffs = [Int32](repeating: 0, count: dims.width * dims.height)
            // Parallel per-coefficient mask for HT partial refinement. Scatter only
            // if at least one contributing block supplies a non-empty mask; keeping
            // it empty is the fast path (cleanup-only blocks, EBCOT blocks).
            let subbandPixelCount = dims.width * dims.height
            let anyHTMask = decodedBlocks.contains { !$0.htPartiallyRefined.isEmpty }
            var subbandHTMask: [Bool] = anyHTMask ? [Bool](repeating: false, count: subbandPixelCount) : []
            subbandCoeffs.withUnsafeMutableBufferPointer { dstBuf in
                for db in decodedBlocks {
                    db.coefficients.withUnsafeBufferPointer { srcBuf in
                        for row in 0..<db.height {
                            let srcStart = row * db.width
                            let dstStart = (db.y + row) * dims.width + db.x
                            let copyCount = min(db.width, srcBuf.count - srcStart)
                            guard copyCount > 0, dstStart + copyCount <= dstBuf.count else { continue }
                            dstBuf.baseAddress!.advanced(by: dstStart)
                                .update(from: srcBuf.baseAddress!.advanced(by: srcStart), count: copyCount)
                        }
                    }
                    if anyHTMask && !db.htPartiallyRefined.isEmpty {
                        for row in 0..<db.height {
                            let srcStart = row * db.width
                            let dstStart = (db.y + row) * dims.width + db.x
                            for col in 0..<db.width {
                                let srcIdx = srcStart + col
                                let dstIdx = dstStart + col
                                guard srcIdx < db.htPartiallyRefined.count,
                                      dstIdx < subbandHTMask.count else { continue }
                                if db.htPartiallyRefined[srcIdx] {
                                    subbandHTMask[dstIdx] = true
                                }
                            }
                        }
                    }
                }
            }

            subbands.append(SubbandInfo(
                componentIndex: compIdx,
                level: level,
                subband: subbandType,
                coefficients: subbandCoeffs,
                doubleCoefficients: nil,
                width: dims.width,
                height: dims.height,
                htPartiallyRefined: subbandHTMask
            ))
        }

        return (subbands, gpuBatch)
    }

    /// v5.9 zero-copy fast-lane: when the v5.8 fused DWT path is
    /// going to run downstream, the only `[SubbandInfo]` consumed
    /// is the outermost LL (for `initialLL` upload). Everything
    /// else is read straight off the GPU codeblock buffer by the
    /// scatter kernel. This helper takes that fast path:
    /// decodeBatchGPUResident with no per-block coefficient slicing,
    /// build LL-only [SubbandInfo] directly from buffer + offsets,
    /// build the batch, return.
    ///
    /// Returns `nil` when the dispatcher reports any
    /// `cpuFallbackIndices` (mixed-eligibility tile) — caller
    /// falls through to the slow-lane.
    private func runZeroCopyFastLane(
        blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata,
        session: J2KMetalSession
    ) async throws -> (subbands: [SubbandInfo], batch: J2KGPUHTBatch?)? {
        // Build dispatcher input + remember pipeline-block-index
        // mapping for downstream offset remapping.
        var gpuInputs: [GPUHTBlock] = []
        var inputOriginalIndices: [Int] = []
        gpuInputs.reserveCapacity(blocks.count)
        inputOriginalIndices.reserveCapacity(blocks.count)
        for (i, block) in blocks.enumerated() {
            gpuInputs.append(GPUHTBlock(
                width: block.width, height: block.height,
                data: [UInt8](block.data),
                missingMSBs: block.zeroBitPlanes))
            inputOriginalIndices.append(i)
        }

        // v5.9: includePerBlockCoefficients=false → dispatcher
        // skips the per-block memcpy slicing loop. We read LL
        // blocks directly from the buffer below.
        guard let result = try await J2KGPUHTDispatch.decodeBatchGPUResident(
            blocks: gpuInputs, session: session,
            includePerBlockCoefficients: false)
        else { return nil }
        guard result.cpuFallbackIndices.isEmpty else {
            await session.bufferPool.returnBuffer(result.codeblockBuffer)
            return nil
        }

        // Remap dispatcher's gpuInput-indexed offsets → pipeline-
        // block-index keyed offsets.
        var remappedOffsets: [Int: Int] = [:]
        remappedOffsets.reserveCapacity(result.decodedBlockOutputOffsets.count)
        for (gpuIdx, offset) in result.decodedBlockOutputOffsets {
            remappedOffsets[inputOriginalIndices[gpuIdx]] = offset
        }

        // v5.9e: LL is scattered into its 2D buffer by the GPU at
        // the innermost level (`buildGPUHTBatchFromResult` includes
        // target=0 LL descriptors there). The fused IDWT consumes
        // it directly — no CPU-side LL allocation, no per-row
        // memcpy, no `[Int32]` array crossing the pipeline
        // boundary. `buildLLSubbandsFromBuffer` stays in the file
        // as a recoverable helper but is no longer called.
        let batch = buildGPUHTBatchFromResult(
            codeblockBuffer: result.codeblockBuffer,
            outputSampleCount: result.outputSampleCount,
            decodedBlockOutputOffsets: remappedOffsets,
            blocks: blocks, metadata: metadata,
            bufferPool: session.bufferPool)

        return ([], batch)
    }

    /// v5.9c helper: rebuild the LL `[SubbandInfo]` (one per
    /// component) directly from the GPU codeblock buffer. Reads each
    /// LL block via `bufferPtr + offset` instead of materialising
    /// the whole per-block coefficient array first. Same approach
    /// the v5.9a fast lane used before v5.9b's failed attempt to
    /// route LL through the GPU scatter (kept here as a recoverable
    /// helper in case v5.10 / v5.11 wants to take another swing).
    private func buildLLSubbandsFromBuffer(
        blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata,
        codeblockBuffer: any MTLBuffer,
        sampleCount: Int,
        offsets: [Int: Int]
    ) -> [SubbandInfo] {
        let levels = metadata.configuration.decompositionLevels
        guard sampleCount > 0 else { return [] }

        struct LLAccumulator {
            var blocks: [(blockIdx: Int, info: CodeBlockInfo)] = []
            var width: Int = 0
            var height: Int = 0
        }
        var byComponent: [Int: LLAccumulator] = [:]
        for (i, block) in blocks.enumerated() {
            guard block.subband == .ll, offsets[i] != nil else { continue }
            byComponent[block.componentIndex, default: LLAccumulator()].blocks.append((i, block))
            byComponent[block.componentIndex]!.width = max(
                byComponent[block.componentIndex]!.width, block.x + block.width)
            byComponent[block.componentIndex]!.height = max(
                byComponent[block.componentIndex]!.height, block.y + block.height)
        }

        J2KMetalUMACounters.incrementContents()
        let bufferPtr = codeblockBuffer.contents()
            .bindMemory(to: Int32.self, capacity: sampleCount)

        var result: [SubbandInfo] = []
        for (compIdx, acc) in byComponent {
            guard acc.width > 0, acc.height > 0 else { continue }
            var llCoeffs = [Int32](repeating: 0, count: acc.width * acc.height)
            llCoeffs.withUnsafeMutableBufferPointer { dst in
                for (blockIdx, info) in acc.blocks {
                    guard let srcOffset = offsets[blockIdx] else { continue }
                    let src = bufferPtr + srcOffset
                    for r in 0..<info.height {
                        let dstRow = (info.y + r) * acc.width + info.x
                        let srcRow = r * info.width
                        J2KMetalUMACounters.incrementMemcpy()
                        memcpy(dst.baseAddress! + dstRow,
                               src + srcRow,
                               info.width * MemoryLayout<Int32>.stride)
                    }
                }
            }
            result.append(SubbandInfo(
                componentIndex: compIdx,
                level: levels,
                subband: .ll,
                coefficients: llCoeffs,
                doubleCoefficients: nil,
                width: acc.width,
                height: acc.height,
                htPartiallyRefined: []))
        }
        return result
    }

    /// v5.8 dedupe helper: build a `J2KGPUHTBatch` from an already-
    /// computed `GPUHTBatchGPUResidentResult`. The unified early-
    /// pass in `applyEntropyDecoding` calls
    /// `decodeBatchGPUResident` once and threads the result here
    /// so we don't re-decode on the GPU just to build the batch.
    private func buildGPUHTBatchFromResult(
        codeblockBuffer: any MTLBuffer,
        outputSampleCount: Int,
        decodedBlockOutputOffsets: [Int: Int],
        blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata,
        bufferPool: J2KMetalBufferPool
    ) -> J2KGPUHTBatch {
        let levels = metadata.configuration.decompositionLevels
        var plansByComponent: [Int: [J2KMetalDWT.LevelScatterPlan]] = [:]
        let maxComponent = max(
            metadata.componentCount - 1,
            blocks.map { $0.componentIndex }.max() ?? 0)

        for compIdx in 0...maxComponent {
            let compW = metadata.width / max(metadata.components[compIdx].subsamplingX, 1)
            let compH = metadata.height / max(metadata.components[compIdx].subsamplingY, 1)
            var levelSizes: [(width: Int, height: Int)] = [(compW, compH)]
            for _ in 0..<levels {
                let (pw, ph) = levelSizes.last!
                levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))
            }

            var levelPlans: [J2KMetalDWT.LevelScatterPlan] = []
            for level in (1...levels).reversed() {
                let parentW = levelSizes[level - 1].width
                let parentH = levelSizes[level - 1].height
                let llW = levelSizes[level].width
                let llH = levelSizes[level].height
                let hlW = parentW - llW
                let lhH = parentH - llH

                var descs: [J2KMetalSubbandScatterDescriptor] = []
                var maxBlockW = 0
                var maxBlockH = 0
                for (i, block) in blocks.enumerated() {
                    guard block.componentIndex == compIdx,
                          let outputOffset = decodedBlockOutputOffsets[i]
                    else { continue }
                    // Codeblock-level enumeration in this codebase
                    // numbers the deepest residual LL as decomLevel 0
                    // (parser converts resLevel=0 → decomLevel=0) and
                    // LH/HL/HH at decomposition level k as decomLevel k.
                    // So LL belongs to the innermost iteration here
                    // (level == levels), and LH/HL/HH belong to
                    // whichever iteration's level matches their own.
                    let isLLForInnermost =
                        block.subband == .ll && block.level == 0 && level == levels
                    let isDetailForThisLevel =
                        block.subband != .ll && block.level == level
                    guard isLLForInnermost || isDetailForThisLevel else { continue }
                    let target: UInt32
                    let stride: Int
                    switch block.subband {
                    case .ll: target = 0; stride = llW
                    case .lh: target = 1; stride = llW
                    case .hl: target = 2; stride = hlW
                    case .hh: target = 3; stride = hlW
                    }
                    descs.append(J2KMetalSubbandScatterDescriptor(
                        codeblockOffset: UInt32(outputOffset),
                        blockWidth: UInt32(block.width),
                        blockHeight: UInt32(block.height),
                        subbandX: UInt32(block.x),
                        subbandY: UInt32(block.y),
                        subbandStride: UInt32(stride),
                        targetSubband: target))
                    maxBlockW = max(maxBlockW, block.width)
                    maxBlockH = max(maxBlockH, block.height)
                }

                levelPlans.append(J2KMetalDWT.LevelScatterPlan(
                    scatterDescriptors: descs,
                    llWidth: llW, llHeight: llH,
                    lhWidth: llW, lhHeight: lhH,
                    hlWidth: hlW, hlHeight: llH,
                    hhWidth: hlW, hhHeight: lhH,
                    originalWidth: parentW, originalHeight: parentH,
                    maxBlockWidth: max(maxBlockW, 1),
                    maxBlockHeight: max(maxBlockH, 1)))
            }
            plansByComponent[compIdx] = levelPlans
        }

        return J2KGPUHTBatch(
            codeblockBuffer: codeblockBuffer,
            outputSampleCount: outputSampleCount,
            plansByComponent: plansByComponent,
            bufferPool: bufferPool)
    }

    // MARK: - Stage 4: Dequantization

    /// Applies dequantization to decoded subbands (parallel across subbands).
    private func applyDequantization(
        _ subbands: [SubbandInfo],
        metadata: CodestreamMetadata
    ) async throws -> [SubbandInfo] {
        let levels = metadata.configuration.decompositionLevels

        let isIrreversible: Bool
        if case .irreversible97 = metadata.configuration.waveletFilter {
            isIrreversible = true
        } else {
            isIrreversible = false
        }

        // HTJ2K (FBCOT) outputs coefficients at natural scale, while standard
        // EBCOT uses bpno_plus_one (shifted left by 1) for irreversible 9/7.
        // The dequantization scale factor must account for this difference.
        let useHTJ2K = metadata.configuration.useHTJ2K
        let quantSteps = metadata.quantizationSteps  // capture value type for task isolation

        guard !subbands.isEmpty else { return [] }
        // Each subband is independent — process all in parallel.
        var result = [SubbandInfo](repeating: subbands[0], count: subbands.count)
        try await withThrowingTaskGroup(of: (Int, SubbandInfo).self) { group in
            for (idx, info) in subbands.enumerated() {
                group.addTask {
                    // QCD keys use resolution-level numbering (1=coarsest, NL=finest),
                    // but SubbandInfo.level uses decomposition-level numbering (NL=coarsest, 1=finest).
                    // Convert: resLevel = NL - decomLevel + 1
                    let key: String
                    if info.subband == .ll {
                        key = "LL_0"
                    } else {
                        let resLevel = levels - info.level + 1
                        key = "\(info.subband.rawValue)_\(resLevel)"
                    }
                    let stepSize = quantSteps[key] ?? 1.0

                    guard isIrreversible else {
                        // For reversible 5/3, step size is always 1 (no quantization).
                        return (idx, SubbandInfo(
                            componentIndex: info.componentIndex,
                            level: info.level,
                            subband: info.subband,
                            coefficients: info.coefficients,
                            doubleCoefficients: nil,
                            width: info.width,
                            height: info.height
                        ))
                    }

                    // For irreversible 9/7, dequantize to Double to preserve fractional
                    // precision through the inverse DWT. Rounding to Int32 here would
                    // destroy sub-integer information (e.g. step=0.02, q=10 → 0.2 → 0).
                    //
                    // Standard EBCOT coefficients use bpno_plus_one scale (shifted left
                    // by 1) to match OPJ's oneplushalf approach, so dequantization
                    // applies ×0.5 to compensate. The EBCOT halfBit adds 1 at bit 0,
                    // giving effective dequantization of (2q + 1) × stepSize/2 =
                    // (q + 0.5) × stepSize — the midpoint of the quantization bin.
                    //
                    // HTJ2K (FBCOT) outputs coefficients at natural scale (no shift).
                    // For **cleanup-only** or **fully-refined** coefficients the block
                    // decoder returns the exact integer magnitude, so dequantization
                    // adds the standard `+0.5 * stepSize` quantization-bin midpoint.
                    // For **partially-refined** coefficients the block decoder has
                    // already injected a block-level midpoint `1 << uncertaintyPlane`
                    // that centers the coefficient inside its residual-uncertainty
                    // range; in that case adding another `+0.5 * stepSize` on top
                    // produces the double-midpoint bias, so we skip the offset
                    // whenever `htPartiallyRefined[i]` is set.
                    let effectiveStepSize = useHTJ2K ? stepSize : (0.5 * stepSize)
                    let midpointOffset = useHTJ2K ? (0.5 * stepSize) : 0.0
                    let htMask = info.htPartiallyRefined
                    let hasHTMask = useHTJ2K && !htMask.isEmpty && htMask.count == info.coefficients.count
                    let dequantizedDouble: [Double]
                    if hasHTMask {
                        // HTJ2K per-coefficient offset — must stay scalar (mask varies per element)
                        dequantizedDouble = info.coefficients.enumerated().map { (i, coeff) -> Double in
                            if coeff == 0 { return 0.0 }
                            let sign: Double = coeff > 0 ? 1.0 : -1.0
                            let magnitude = Double(abs(coeff))
                            let offset = htMask[i] ? 0.0 : midpointOffset
                            return sign * (magnitude * effectiveStepSize + offset)
                        }
                    } else {
                        // Standard EBCOT path: vectorise with vDSP.
                        // Steps: Int32→Double, abs, scale+offset, restore sign.
                        let n = info.coefficients.count
                        // Skip zero-init — both arrays are fully overwritten by vDSP before any read.
                        var absDoubles  = [Double](unsafeUninitializedCapacity: n) { _, s in s = n }
                        var signDoubles = [Double](unsafeUninitializedCapacity: n) { _, s in s = n }
                        info.coefficients.withUnsafeBufferPointer { src in
                            // 1. Convert Int32 → Double (signed originals)
                            vDSP_vflt32D(src.baseAddress!, 1, &signDoubles, 1, vDSP_Length(n))
                            // 2. |x|
                            vDSP_vabsD(signDoubles, 1, &absDoubles, 1, vDSP_Length(n))
                            // 3. magnitude * effectiveStepSize + midpointOffset
                            var scale  = effectiveStepSize
                            var offset = midpointOffset
                            vDSP_vsmsaD(absDoubles, 1, &scale, &offset, &absDoubles, 1, vDSP_Length(n))
                            // 4. Restore sign: sign(original) * scaled_magnitude.
                            //    Compute signum(x): clip to ±1 via vDSP_vclipD then multiply.
                            var posOne = 1.0, negOne = -1.0
                            vDSP_vclipD(signDoubles, 1, &negOne, &posOne, &signDoubles, 1, vDSP_Length(n))
                            vDSP_vmulD(absDoubles, 1, signDoubles, 1, &signDoubles, 1, vDSP_Length(n))
                        }
                        // 5. For standard JPEG 2000, midpointOffset == 0.0 so zeros stay zero.
                        //    For HTJ2K without htMask, vDSP_vsmsaD applied a non-zero offset to
                        //    zero-valued coefficients — fix those back to 0.0.
                        if midpointOffset != 0.0 {
                            info.coefficients.withUnsafeBufferPointer { src in
                                for i in 0..<n where src[i] == 0 { signDoubles[i] = 0.0 }
                            }
                        }
                        dequantizedDouble = signDoubles
                    }

                    return (idx, SubbandInfo(
                        componentIndex: info.componentIndex,
                        level: info.level,
                        subband: info.subband,
                        coefficients: info.coefficients,
                        doubleCoefficients: dequantizedDouble,
                        width: info.width,
                        height: info.height,
                        htPartiallyRefined: info.htPartiallyRefined
                    ))
                }
            }
            for try await (idx, subband) in group {
                result[idx] = subband
            }
        }
        return result
    }

    // MARK: - Stage 5: Inverse Wavelet Transform

    /// Applies inverse wavelet transform to reconstruct spatial domain.
    private func applyInverseWaveletTransform(
        _ subbands: [SubbandInfo],
        metadata: CodestreamMetadata
    ) async throws -> [[Double]] {
        let filter = metadata.configuration.waveletFilter
        let levels = metadata.configuration.decompositionLevels

        // Use the component count from the SIZ marker, not from the data.
        // Some components may have all-empty packets (e.g., aggressive rate
        // control). They should still produce zero-filled output.
        let maxComponent = max(
            metadata.componentCount - 1,
            subbands.map { $0.componentIndex }.max() ?? 0
        )
        let componentCount = maxComponent + 1

        // Pre-index subbands by component — avoids O(n) .filter per component.
        var subbandsByComponentMut = [[SubbandInfo]](repeating: [], count: componentCount)
        for sb in subbands {
            if sb.componentIndex < componentCount {
                subbandsByComponentMut[sb.componentIndex].append(sb)
            }
        }
        let subbandsByComponent = subbandsByComponentMut

        // Thread-safe result storage for parallel component processing.
        // Each component's IDWT is fully independent (reads separate
        // subbands, writes to its own output array).

        let inverseTransformOneComponent: @Sendable (Int) async throws -> [Double] = { (compIdx: Int) async throws -> [Double] in
            // Select filter for this component
            let componentFilter: J2KDWT1D.Filter
            if let kernelConfig = metadata.configuration.waveletKernelConfiguration {
                // Use arbitrary wavelet kernel if configured
                if let kernel = kernelConfig.kernel(
                    forTile: 0, component: compIdx,
                    lossless: metadata.configuration.useReversibleTransform
                ) {
                    componentFilter = kernel.toDWTFilter()
                } else {
                    componentFilter = filter
                }
            } else {
                componentFilter = filter
            }

            let compSubbands = subbandsByComponent[compIdx]

            if compSubbands.isEmpty {
                // Component has no data (e.g., all code blocks were zeroed by
                // rate control). Fill with neutral values so downstream stages
                // (color transform, reconstruction) have the expected shape.
                return [Double](repeating: 0.0, count: metadata.width * metadata.height)
            }

            // Find LL subband.  When rate control truncates aggressively the
            // LL code blocks may all be empty, so synthesise a zero-filled
            // subband with the standard dimensions for the deepest level.
            let llSubband: SubbandInfo
            let width: Int
            let height: Int
            if let found = compSubbands.first(where: { $0.subband == .ll }) {
                llSubband = found
                width = found.width
                height = found.height
            } else {
                let cW = metadata.width / metadata.components[compIdx].subsamplingX
                let cH = metadata.height / metadata.components[compIdx].subsamplingY
                var w = cW; var h = cH
                for _ in 0..<levels { w = (w + 1) / 2; h = (h + 1) / 2 }
                llSubband = SubbandInfo(
                    componentIndex: compIdx,
                    level: levels,
                    subband: .ll,
                    coefficients: [Int32](repeating: 0, count: w * h),
                    doubleCoefficients: nil,
                    width: w,
                    height: h
                )
                width = w
                height = h
            }

            // For now, if no decomposition levels, just return LL subband
            if levels == 0 {
                return vDSPConvert.int32sToDoubles(llSubband.coefficients)
            }

            // Convert 1D coefficient arrays to 2D arrays for each subband
            func to2D(_ coeffs: [Int32], width: Int, height: Int) -> [[Int32]] {
                var result = [[Int32]](
                    repeating: [Int32](repeating: 0, count: width),
                    count: height
                )
                for row in 0..<height {
                    for col in 0..<width {
                        let idx = row * width + col
                        if idx < coeffs.count {
                            result[row][col] = coeffs[idx]
                        }
                    }
                }
                return result
            }

            func to2DDouble(_ coeffs: [Int32], width: Int, height: Int) -> [[Double]] {
                var result = [[Double]](
                    repeating: [Double](repeating: 0, count: width),
                    count: height
                )
                for row in 0..<height {
                    for col in 0..<width {
                        let idx = row * width + col
                        if idx < coeffs.count {
                            result[row][col] = Double(coeffs[idx])
                        }
                    }
                }
                return result
            }

            func to2DDoubleFromDoubles(_ coeffs: [Double], width: Int, height: Int) -> [[Double]] {
                var result = [[Double]](
                    repeating: [Double](repeating: 0, count: width),
                    count: height
                )
                for row in 0..<height {
                    for col in 0..<width {
                        let idx = row * width + col
                        if idx < coeffs.count {
                            result[row][col] = coeffs[idx]
                        }
                    }
                }
                return result
            }

            // Compute expected subband dimensions at each decomposition level
            let compW = metadata.width / metadata.components[compIdx].subsamplingX
            let compH = metadata.height / metadata.components[compIdx].subsamplingY
            var levelSizes: [(width: Int, height: Int)] = [(compW, compH)]
            for _ in 0..<levels {
                let (pw, ph) = levelSizes.last!
                levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))
            }

            // Helper: convert 1D Int32 array to 2D padded to standard dimensions.
            // When rate control truncates code blocks, the actual subband data may
            // be smaller than the standard dimension. Zero-pad to the expected size.
            func paddedInt(_ coeffs: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Int32]] {
                var result = [[Int32]](repeating: [Int32](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    for row in 0..<copyH {
                        let srcOffset = row * srcW
                        guard srcOffset + copyW <= srcBuf.count else { return }
                        result[row].withUnsafeMutableBufferPointer { dstBuf in
                            dstBuf.baseAddress!.update(from: srcBuf.baseAddress! + srcOffset, count: copyW)
                        }
                    }
                }
                return result
            }

            func paddedDoubleFromInt(_ coeffs: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Double]] {
                var result = [[Double]](repeating: [Double](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    for row in 0..<copyH {
                        let srcOffset = row * srcW
                        guard srcOffset + copyW <= srcBuf.count else { return }
                        result[row].withUnsafeMutableBufferPointer { dstBuf in
                            for col in 0..<copyW {
                                dstBuf[col] = Double(srcBuf[srcOffset + col])
                            }
                        }
                    }
                }
                return result
            }

            func paddedDouble(_ coeffs: [Double], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Double]] {
                var result = [[Double]](repeating: [Double](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    for row in 0..<copyH {
                        let srcOffset = row * srcW
                        guard srcOffset + copyW <= srcBuf.count else { return }
                        result[row].withUnsafeMutableBufferPointer { dstBuf in
                            dstBuf.baseAddress!.update(from: srcBuf.baseAddress! + srcOffset, count: copyW)
                        }
                    }
                }
                return result
            }

            // Flat-buffer helpers for 9/7 multi-level IDWT path
            func paddedFlat(_ coeffs: [Double], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Double] {
                if srcW == dstW && srcH == dstH && coeffs.count == dstW * dstH {
                    return coeffs
                }
                var result = [Double](repeating: 0, count: dstW * dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    result.withUnsafeMutableBufferPointer { dstBuf in
                        let dst = dstBuf.baseAddress!
                        let src = srcBuf.baseAddress!
                        for row in 0..<copyH {
                            let srcOffset = row * srcW
                            let dstOffset = row * dstW
                            guard srcOffset + copyW <= srcBuf.count else { return }
                            (dst + dstOffset).update(from: src + srcOffset, count: copyW)
                        }
                    }
                }
                return result
            }

            func paddedFlatFromInt(_ coeffs: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Double] {
                var result = [Double](repeating: 0, count: dstW * dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                if srcW == dstW && srcH == dstH && coeffs.count == dstW * dstH {
                    coeffs.withUnsafeBufferPointer { srcBuf in
                        result.withUnsafeMutableBufferPointer { dstBuf in
                            vDSP_vflt32D(srcBuf.baseAddress!, 1, dstBuf.baseAddress!, 1, vDSP_Length(srcBuf.count))
                        }
                    }
                    return result
                }
                coeffs.withUnsafeBufferPointer { srcBuf in
                    result.withUnsafeMutableBufferPointer { dstBuf in
                        let dst = dstBuf.baseAddress!
                        let src = srcBuf.baseAddress!
                        for row in 0..<copyH {
                            let srcOffset = row * srcW
                            let dstOffset = row * dstW
                            guard srcOffset + copyW <= srcBuf.count else { return }
                            vDSP_vflt32D(src + srcOffset, 1, dst + dstOffset, 1, vDSP_Length(copyW))
                        }
                    }
                }
                return result
            }

            /// Pads/crops flat `[Int32]` coefficients into a new flat `[Int32]` buffer.
            /// When dimensions match exactly, returns the original array (COW — no copy).
            func paddedIntFlat(_ coeffs: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Int32] {
                if srcW == dstW && srcH == dstH && coeffs.count == dstW * dstH {
                    return coeffs
                }
                var result = [Int32](repeating: 0, count: dstW * dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    result.withUnsafeMutableBufferPointer { dstBuf in
                        let dst = dstBuf.baseAddress!
                        let src = srcBuf.baseAddress!
                        for row in 0..<copyH {
                            let srcOffset = row * srcW
                            let dstOffset = row * dstW
                            guard srcOffset + copyW <= srcBuf.count else { return }
                            (dst + dstOffset).update(from: src + srcOffset, count: copyW)
                        }
                    }
                }
                return result
            }

            // Full multi-level IDWT reconstruction
            // For 9/7 irreversible, use Double precision throughout all levels to
            // avoid accumulated rounding error from Int32 truncation at each level.
            let useDoublePrecision: Bool
            if case .irreversible97 = componentFilter {
                useDoublePrecision = true
            } else {
                useDoublePrecision = false
            }
            // High-bit-depth medical lossy workflows now use reversible 5/3
            // rate truncation, and the optimized integer IDWT path has verified
            // deterministic behavior there. Keep the conservative fallback only
            // for the more fragile high-bit-depth irreversible 9/7 path.
            let useConservativeHighBitDepthPath = metadata.components[compIdx].bitDepth > 8 && useDoublePrecision

            if useDoublePrecision {
                // Double-precision path for 9/7 irreversible wavelet.
                // Use flat-buffer multi-level IDWT to avoid [[Double]]
                // intermediate conversions at each decomposition level.
                let expectedLLW = levelSizes[levels].width
                let expectedLLH = levelSizes[levels].height

                // Convert LL subband to flat [Double]
                let llFlat: [Double]
                if let dc = llSubband.doubleCoefficients {
                    llFlat = paddedFlat(dc, srcW: width, srcH: height, dstW: expectedLLW, dstH: expectedLLH)
                } else {
                    llFlat = paddedFlatFromInt(llSubband.coefficients, srcW: width, srcH: height, dstW: expectedLLW, dstH: expectedLLH)
                }

                // Build flat subbands for each level (deepest first)
                var levelSubbands: [(lh: [Double], lhW: Int, lhH: Int,
                                     hl: [Double], hlW: Int, hlH: Int,
                                     hh: [Double], hhW: Int, hhH: Int)] = []

                for level in (1...levels).reversed() {
                    let parentW = levelSizes[level - 1].width
                    let parentH = levelSizes[level - 1].height
                    let llW = levelSizes[level].width
                    let llH = levelSizes[level].height
                    let hlW = parentW - llW
                    let lhH = parentH - llH

                    // HL subband
                    let hlSub = compSubbands.first(where: { $0.level == level && $0.subband == .hl })
                    let hlFlat: [Double]
                    if let hs = hlSub, let dc = hs.doubleCoefficients {
                        hlFlat = paddedFlat(dc, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: llH)
                    } else if let hs = hlSub {
                        hlFlat = paddedFlatFromInt(hs.coefficients, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: llH)
                    } else {
                        hlFlat = [Double](repeating: 0, count: hlW * llH)
                    }

                    // LH subband
                    let lhSub = compSubbands.first(where: { $0.level == level && $0.subband == .lh })
                    let lhFlat: [Double]
                    if let ls = lhSub, let dc = ls.doubleCoefficients {
                        lhFlat = paddedFlat(dc, srcW: ls.width, srcH: ls.height, dstW: llW, dstH: lhH)
                    } else if let ls = lhSub {
                        lhFlat = paddedFlatFromInt(ls.coefficients, srcW: ls.width, srcH: ls.height, dstW: llW, dstH: lhH)
                    } else {
                        lhFlat = [Double](repeating: 0, count: llW * lhH)
                    }

                    // HH subband
                    let hhSub = compSubbands.first(where: { $0.level == level && $0.subband == .hh })
                    let hhFlat: [Double]
                    if let hs = hhSub, let dc = hs.doubleCoefficients {
                        hhFlat = paddedFlat(dc, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: lhH)
                    } else if let hs = hhSub {
                        hhFlat = paddedFlatFromInt(hs.coefficients, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: lhH)
                    } else {
                        hhFlat = [Double](repeating: 0, count: hlW * lhH)
                    }

                    levelSubbands.append((lh: lhFlat, lhW: llW, lhH: lhH,
                                          hl: hlFlat, hlW: hlW, hlH: llH,
                                          hh: hhFlat, hhW: hlW, hhH: lhH))
                }

                if useConservativeHighBitDepthPath {
                    var currentLL = to2DDoubleFromDoubles(llFlat, width: expectedLLW, height: expectedLLH)

                    for (index, _) in Array((1...levels).reversed()).enumerated() {
                        let levelData = levelSubbands[index]
                        let lh2D = to2DDoubleFromDoubles(levelData.lh, width: levelData.lhW, height: levelData.lhH)
                        let hl2D = to2DDoubleFromDoubles(levelData.hl, width: levelData.hlW, height: levelData.hlH)
                        let hh2D = to2DDoubleFromDoubles(levelData.hh, width: levelData.hhW, height: levelData.hhH)
                        currentLL = try J2KDWT2D.inverseTransform97(
                            ll: currentLL,
                            lh: lh2D,
                            hl: hl2D,
                            hh: hh2D,
                            boundaryExtension: .symmetric
                        )
                    }

                    let rowCount = currentLL.count
                    let colCount = rowCount > 0 ? currentLL[0].count : 0
                    var flattened = [Double](repeating: 0.0, count: rowCount * colCount)
                    flattened.withUnsafeMutableBufferPointer { dst in
                        for r in 0..<rowCount {
                            let row = currentLL[r]
                            let offset = r * colCount
                            for c in 0..<min(colCount, row.count) {
                                dst[offset + c] = row[c]
                            }
                        }
                    }
                    return flattened
                } else {
                    let optimizer97 = J2KDWT2DOptimizer97()
                    // Use Float32 path for ≤16-bit images: 2× SIMD throughput and
                    // 2× cache efficiency vs Double, with sufficient precision.
                    let bitDepth = metadata.components[compIdx].bitDepth
                    let result: (data: [Double], width: Int, height: Int)
                    if bitDepth <= 16 {
                        result = await optimizer97.inverseTransformMultiLevel97Float(
                            ll: llFlat, llW: expectedLLW, llH: expectedLLH,
                            subbands: levelSubbands
                        )
                    } else {
                        result = await optimizer97.inverseTransformMultiLevel97(
                            ll: llFlat, llW: expectedLLW, llH: expectedLLH,
                            subbands: levelSubbands
                        )
                    }

                    return result.data
                }
            } else {
                // Int32 path for 5/3 reversible wavelet (exact integer arithmetic)
                // Uses flat contiguous buffers throughout to eliminate the hundreds
                // of short-lived [[Int32]] allocations and cache-miss-heavy column
                // gather in the per-level inverseTransform2DOptimized path.
                let expectedLLW = levelSizes[levels].width
                let expectedLLH = levelSizes[levels].height
                let llFlat = paddedIntFlat(
                    llSubband.coefficients,
                    srcW: width, srcH: height,
                    dstW: expectedLLW, dstH: expectedLLH
                )

                // Build flat subbands array deepest-first (mirrors the 9/7 path)
                var levelSubbands53: [(lh: [Int32], lhW: Int, lhH: Int,
                                       hl: [Int32], hlW: Int, hlH: Int,
                                       hh: [Int32], hhW: Int, hhH: Int)] = []

                for level in (1...levels).reversed() {
                    let parentW = levelSizes[level - 1].width
                    let parentH = levelSizes[level - 1].height
                    let llW = levelSizes[level].width
                    let llH = levelSizes[level].height
                    let hlW = parentW - llW
                    let lhH = parentH - llH

                    let hlFlat: [Int32]
                    if let hs = compSubbands.first(where: { $0.level == level && $0.subband == .hl }) {
                        hlFlat = paddedIntFlat(hs.coefficients, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: llH)
                    } else {
                        hlFlat = [Int32](repeating: 0, count: hlW * llH)
                    }

                    let lhFlat: [Int32]
                    if let ls = compSubbands.first(where: { $0.level == level && $0.subband == .lh }) {
                        lhFlat = paddedIntFlat(ls.coefficients, srcW: ls.width, srcH: ls.height, dstW: llW, dstH: lhH)
                    } else {
                        lhFlat = [Int32](repeating: 0, count: llW * lhH)
                    }

                    let hhFlat: [Int32]
                    if let hhs = compSubbands.first(where: { $0.level == level && $0.subband == .hh }) {
                        hhFlat = paddedIntFlat(hhs.coefficients, srcW: hhs.width, srcH: hhs.height, dstW: hlW, dstH: lhH)
                    } else {
                        hhFlat = [Int32](repeating: 0, count: hlW * lhH)
                    }

                    levelSubbands53.append((
                        lh: lhFlat, lhW: llW, lhH: lhH,
                        hl: hlFlat, hlW: hlW, hlH: llH,
                        hh: hhFlat, hhW: hlW, hhH: lhH
                    ))
                }

                if useConservativeHighBitDepthPath {
                    // Conservative [[Int32]] path kept for edge-case correctness
                    var currentLL = paddedInt(llSubband.coefficients, srcW: width, srcH: height, dstW: expectedLLW, dstH: expectedLLH)
                    for (index, _) in Array((1...levels).reversed()).enumerated() {
                        let lvl = levelSubbands53[index]
                        func toJagged(_ flat: [Int32], w: Int, h: Int) -> [[Int32]] {
                            (0..<h).map { r in Array(flat[(r*w)..<(r*w+w)]) }
                        }
                        let lh2D = toJagged(lvl.lh, w: lvl.lhW, h: lvl.lhH)
                        let hl2D = toJagged(lvl.hl, w: lvl.hlW, h: lvl.hlH)
                        let hh2D = toJagged(lvl.hh, w: lvl.hhW, h: lvl.hhH)
                        currentLL = try J2KDWT2D.inverseTransform(
                            ll: currentLL, lh: lh2D, hl: hl2D, hh: hh2D,
                            filter: componentFilter, boundaryExtension: .symmetric
                        )
                    }
                    let rowCount = currentLL.count
                    let colCount = rowCount > 0 ? currentLL[0].count : 0
                    var flattened = [Double](repeating: 0.0, count: rowCount * colCount)
                    flattened.withUnsafeMutableBufferPointer { dst in
                        for r in 0..<rowCount {
                            let row = currentLL[r]
                            let offset = r * colCount
                            for c in 0..<min(colCount, row.count) {
                                dst[offset + c] = Double(row[c])
                            }
                        }
                    }
                    return flattened
                } else {
                    let optimizer = J2KDWT2DOptimizer()
                    let result = await optimizer.inverseTransformMultiLevel53(
                        ll: llFlat, llW: expectedLLW, llH: expectedLLH,
                        subbands: levelSubbands53
                    )
                    // Convert flat [Int32] → [Double] with vDSP (NEON-vectorised on Apple Silicon)
                    let n = result.data.count
                    var out = [Double](repeating: 0.0, count: n)
                    result.data.withUnsafeBufferPointer { src in
                        vDSP_vflt32D(src.baseAddress!, 1, &out, 1, vDSP_Length(n))
                    }
                    return out
                }
            }
        }

        // Execute component processing: parallel for multi-component images.
        let componentResults: [[Double]]
        if componentCount >= 2 {
            componentResults = try await withThrowingTaskGroup(
                of: (Int, [Double]).self
            ) { group in
                for compIdx in 0..<componentCount {
                    group.addTask {
                        let result = try await inverseTransformOneComponent(compIdx)
                        return (compIdx, result)
                    }
                }
                var results = [[Double]](repeating: [], count: componentCount)
                for try await (compIdx, data) in group {
                    results[compIdx] = data
                }
                return results
            }
        } else {
            var results = [[Double]]()
            for compIdx in 0..<componentCount {
                let data = try await inverseTransformOneComponent(compIdx)
                results.append(data)
            }
            componentResults = results
        }

        return componentResults
    }

    // MARK: - GPU Inverse Wavelet Transform

    /// GPU-accelerated inverse wavelet transform using Metal.
    ///
    /// Uses Metal GPU for CDF 9/7 irreversible and Le Gall 5/3 reversible inverse DWT.
    /// Falls back to CPU when Metal is unavailable or for custom filters.
    private func applyInverseWaveletTransformGPU(
        _ subbands: [SubbandInfo],
        metadata: CodestreamMetadata,
        gpuBatch: J2KGPUHTBatch? = nil
    ) async throws -> [[Double]] {
        // Fall back to CPU for custom wavelet kernels only
        if metadata.configuration.waveletKernelConfiguration != nil {
            return try await applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        let levels = metadata.configuration.decompositionLevels
        guard levels >= 1 else {
            return try await applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        // Fall back to CPU when Metal GPU is not available (e.g. Linux, CI servers)
        guard J2KMetalDWT.isAvailable else {
            return try await applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        // Fall back to CPU for small images where GPU dispatch overhead exceeds compute benefit.
        let pixelCount = metadata.width * metadata.height
        guard pixelCount >= 256 * 256 else {
            return try await applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        // v5.20.0 medical-grade gate: GPU 9/7 (irreversible) IDWT
        // currently diverges from the CPU reference by max ~45000 in
        // 16-bit space (avg ~19000). Far beyond Float-vs-Double
        // precision tolerance — there's an unidentified correctness
        // bug in the GPU lossy IDWT kernel chain. Until it's fixed
        // (tracked for v5.21.0+), force 9/7 lossy through the CPU
        // path. Lossless 5/3 (reversible) GPU IDWT remains active —
        // it's bit-exact and gated by v5.7+ regression tests.
        // See `Tests/J2KCodecTests/J2KGPULossy97DivergenceTests.swift`
        // for the bisection proof.
        if case .irreversible97 = metadata.configuration.waveletFilter {
            return try await applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        // Select filter and dispatch path based on configuration. Reversible
        // 5/3 takes the bit-exact Int32 GPU path: subbands stay as Int32
        // throughout multi-level reconstruction, so the result matches
        // J2KDWT1D.inverseTransform53 byte-for-byte regardless of backend.
        // Lossless verifyEncodedRoundTrip in DICOMKit relies on this.
        let metalFilter: J2KMetalDWTFilter
        let useReversible53Int: Bool
        if case .irreversible97 = metadata.configuration.waveletFilter {
            metalFilter = .irreversible97
            useReversible53Int = false
        } else {
            metalFilter = .reversible53
            useReversible53Int = true
        }

        // When a J2KMetalSession is set, share its device, library,
        // and buffer pool — every decode call after the first reuses
        // the cached MSL library + compute pipelines, eliminating the
        // ~50 ms per-decode shader compile cost. Without a session,
        // J2KMetalDWT constructs fresh instances (v5.5.0 behaviour).
        let metalDWT = J2KMetalDWT(
            configuration: J2KMetalDWTConfiguration(
                filter: metalFilter, decompositionLevels: levels),
            device: metalSession?.device,
            bufferPool: metalSession?.bufferPool,
            shaderLibrary: metalSession?.shaderLibrary)
        try await metalDWT.initialize()

        var componentData: [[Double]] = []
        let maxComponent = max(
            metadata.componentCount - 1,
            subbands.map { $0.componentIndex }.max() ?? 0
        )

        for compIdx in 0...maxComponent {
            let compSubbands = subbands.filter { $0.componentIndex == compIdx }

            // v5.9e: when the fast lane returns `([], batch)` —
            // every subband is GPU-resident in the batch — the
            // `compSubbands.isEmpty` early-out used to short-circuit
            // straight to all-zero output and never reach the fused
            // IDWT below. Skip the fast-out when the batch has plans
            // for this component; the IDWT will source LL/LH/HL/HH
            // straight off the GPU codeblock buffer via the scatter
            // descriptors. Without this, the gpuBatch path is dead
            // code on the v5.9 fast lane and session decode collapses
            // to DC-offset-only output (the v5.9b bug).
            let hasGPUBatchPlan = gpuBatch?.plansByComponent[compIdx] != nil
            if compSubbands.isEmpty && !hasGPUBatchPlan {
                componentData.append([Double](repeating: 0.0, count: metadata.width * metadata.height))
                continue
            }

            // Compute expected subband dimensions at each level
            let compW = metadata.width / metadata.components[compIdx].subsamplingX
            let compH = metadata.height / metadata.components[compIdx].subsamplingY
            var levelSizes: [(width: Int, height: Int)] = [(compW, compH)]
            for _ in 0..<levels {
                let (pw, ph) = levelSizes.last!
                levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))
            }

            let llSubband = compSubbands.first(where: { $0.subband == .ll })
            let expectedLLW = levelSizes[levels].width
            let expectedLLH = levelSizes[levels].height

            if useReversible53Int {
                // Bit-exact reversible 5/3 path on Int32 buffers.
                //
                // v5.9e: when a `gpuBatch` is present (fast-lane or
                // v5.8 path), LL rides the GPU scatter alongside
                // LH/HL/HH and `inverse2DInt32FullFusedFromCodeblocks`
                // is called with `initialLL: nil`. The CPU `initialLL`
                // build below is a no-op on that path — the scatter
                // kernel zero-fills the LL buffer and writes the
                // codeblocks straight into it. The multi-level-fused
                // and per-level paths (no batch) still consume
                // `initialLL` from the LL `[SubbandInfo]`.
                let initialLL: [Int32]
                if let ll = llSubband {
                    initialLL = padFlatInt32(ll.coefficients, srcW: ll.width, srcH: ll.height,
                                              dstW: expectedLLW, dstH: expectedLLH)
                } else {
                    initialLL = [Int32](repeating: 0, count: expectedLLW * expectedLLH)
                }

                // v5.7.0: when a Metal session is in scope, build all
                // levels' subband arrays up-front and dispatch the
                // entire multi-level inverse 5/3 in one fused command
                // buffer (output buffer of level N reused as LL input
                // of level N-1 — no readback between levels). Single
                // commit + await + final readback. Falls back to the
                // per-level path otherwise (no behavioural change for
                // sessionless callers).
                var currentLL: [Int32] = initialLL
                // v5.8 full-fused path: if the entropy stage built
                // a GPU batch and we have plans for this component,
                // route to inverse2DInt32FullFusedFromCodeblocks —
                // skips the CPU-side LH/HL/HH upload per level by
                // running the GPU scatter kernel inside the same
                // command buffer as the multi-level inverse 5/3.
                if let batch = gpuBatch,
                   let plansForComp = batch.plansByComponent[compIdx] {
                    // v5.9e: LL is now scattered into its 2D buffer
                    // by the GPU at the innermost level (the batch
                    // includes target=0 LL descriptors there). The
                    // fused IDWT zero-fills the LL buffer and lets
                    // scatter populate it — no `initialLL` upload.
                    currentLL = try await metalDWT.inverse2DInt32FullFusedFromCodeblocks(
                        codeblockBuffer: batch.codeblockBuffer,
                        levelsPlan: plansForComp,
                        initialLL: nil)
                } else if useGPUHT, metalSession != nil {
                    var subbandsPerLevel: [J2KMetalDWTSubbandsInt32] = []
                    for level in (1...levels).reversed() {
                        let parentW = levelSizes[level - 1].width
                        let parentH = levelSizes[level - 1].height
                        let llW = levelSizes[level].width
                        let llH = levelSizes[level].height
                        let hlW = parentW - llW
                        let lhH = parentH - llH

                        let hlInt = getSubbandAsInt32(compSubbands, level: level, subband: .hl,
                                                       dstW: hlW, dstH: llH)
                        let lhInt = getSubbandAsInt32(compSubbands, level: level, subband: .lh,
                                                       dstW: llW, dstH: lhH)
                        let hhInt = getSubbandAsInt32(compSubbands, level: level, subband: .hh,
                                                       dstW: hlW, dstH: lhH)

                        // Only the innermost (first iteration) level
                        // uses the CPU-side LL; subsequent levels'
                        // LL is the previous level's output buffer
                        // (GPU-resident, no CPU allocation needed).
                        // The fused method ignores `subbands.ll` for
                        // levels after the first.
                        let llForThisLevel: [Int32] =
                            subbandsPerLevel.isEmpty ? initialLL : []
                        subbandsPerLevel.append(J2KMetalDWTSubbandsInt32(
                            ll: llForThisLevel, lh: lhInt, hl: hlInt, hh: hhInt,
                            llWidth: llW, llHeight: llH,
                            originalWidth: parentW, originalHeight: parentH))
                    }
                    currentLL = try await metalDWT.inverse2DInt32MultiLevelFused(
                        subbandsPerLevel: subbandsPerLevel)
                } else {
                    for level in (1...levels).reversed() {
                        let parentW = levelSizes[level - 1].width
                        let parentH = levelSizes[level - 1].height
                        let llW = levelSizes[level].width
                        let llH = levelSizes[level].height
                        let hlW = parentW - llW
                        let lhH = parentH - llH

                        let hlInt = getSubbandAsInt32(compSubbands, level: level, subband: .hl,
                                                       dstW: hlW, dstH: llH)
                        let lhInt = getSubbandAsInt32(compSubbands, level: level, subband: .lh,
                                                       dstW: llW, dstH: lhH)
                        let hhInt = getSubbandAsInt32(compSubbands, level: level, subband: .hh,
                                                       dstW: hlW, dstH: lhH)

                        let subbandData = J2KMetalDWTSubbandsInt32(
                            ll: currentLL, lh: lhInt, hl: hlInt, hh: hhInt,
                            llWidth: llW, llHeight: llH,
                            originalWidth: parentW, originalHeight: parentH
                        )

                        currentLL = try await metalDWT.inverse2DInt32(subbands: subbandData, backend: .auto)
                    }
                }

                // v5.9c: Accelerate-backed SIMD conversion instead
                // of the per-element Swift map. Same allocation
                // shape (a fresh [Double] of size `currentLL.count`),
                // but vDSP_vfltu32 burns through Int32 → Double in
                // wide SIMD lanes — measurably faster than Swift's
                // per-element closure on every fixture in the
                // corpus. Matches what the 9/7 irreversible branch
                // already does (line ~2856 below). The "remove or
                // defer to final API boundary" rule from the v5.9
                // plan would require plumbing buffers through to
                // the colour-transform / DC-offset / pixel-byte
                // stages — bigger scope tracked for a follow-up;
                // this lift is the SIMD shape of the same operation.
                componentData.append(vDSPConvert.int32sToDoubles(currentLL))
            } else {
                // 9/7 irreversible — Float path (non-lossless, byte-equality
                // not enforced downstream, so existing FP tolerance is fine).
                var currentLL: [Float]
                if let ll = llSubband {
                    if let dc = ll.doubleCoefficients {
                        currentLL = padFlatFloat(vDSPConvert.doublesToFloats(dc), srcW: ll.width, srcH: ll.height,
                                                  dstW: expectedLLW, dstH: expectedLLH)
                    } else {
                        currentLL = padFlatFloat(vDSPConvert.int32sToFloats(ll.coefficients), srcW: ll.width, srcH: ll.height,
                                                  dstW: expectedLLW, dstH: expectedLLH)
                    }
                } else {
                    currentLL = [Float](repeating: 0, count: expectedLLW * expectedLLH)
                }

                for level in (1...levels).reversed() {
                    let parentW = levelSizes[level - 1].width
                    let parentH = levelSizes[level - 1].height
                    let llW = levelSizes[level].width
                    let llH = levelSizes[level].height
                    let hlW = parentW - llW
                    let lhH = parentH - llH

                    let hlFloat = getSubbandAsFloat(compSubbands, level: level, subband: .hl,
                                                     dstW: hlW, dstH: llH)
                    let lhFloat = getSubbandAsFloat(compSubbands, level: level, subband: .lh,
                                                     dstW: llW, dstH: lhH)
                    let hhFloat = getSubbandAsFloat(compSubbands, level: level, subband: .hh,
                                                     dstW: hlW, dstH: lhH)

                    let subbandData = J2KMetalDWTSubbands(
                        ll: currentLL, lh: lhFloat, hl: hlFloat, hh: hhFloat,
                        llWidth: llW, llHeight: llH,
                        originalWidth: parentW, originalHeight: parentH
                    )

                    currentLL = try await metalDWT.inverse2D(subbands: subbandData, backend: .auto)
                }

                componentData.append(vDSPConvert.floatsToDoubles(currentLL))
            }
        }

        // v5.8: return the codeblock buffer to the pool now that
        // all components have completed their fused dispatches.
        if let batch = gpuBatch {
            await batch.bufferPool.returnBuffer(batch.codeblockBuffer)
        }

        return componentData
    }

    /// Extracts a subband as an Int32 array with zero-padding to expected dimensions.
    private func getSubbandAsInt32(_ subbands: [SubbandInfo], level: Int, subband: J2KSubband,
                                     dstW: Int, dstH: Int) -> [Int32] {
        if let sb = subbands.first(where: { $0.level == level && $0.subband == subband }) {
            // Reversible 5/3 path stores integer coefficients in `coefficients`.
            // Some HTJ2K paths populate `doubleCoefficients` after dequant — in
            // that case round to nearest Int32 (lossless dequant produces values
            // exactly representable as Int32 since stepSize == 1 for reversible).
            if let dc = sb.doubleCoefficients {
                let srcData: [Int32] = dc.map { val in
                    let rounded = (val < 0) ? Int32((val - 0.5).rounded(.up)) : Int32((val + 0.5).rounded(.down))
                    return rounded
                }
                return padFlatInt32(srcData, srcW: sb.width, srcH: sb.height, dstW: dstW, dstH: dstH)
            }
            return padFlatInt32(sb.coefficients, srcW: sb.width, srcH: sb.height, dstW: dstW, dstH: dstH)
        }
        return [Int32](repeating: 0, count: dstW * dstH)
    }

    /// Zero-pads a flat Int32 array from source to destination dimensions.
    private func padFlatInt32(_ data: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Int32] {
        if srcW == dstW && srcH == dstH && data.count == dstW * dstH { return data }
        var result = [Int32](repeating: 0, count: dstW * dstH)
        let copyW = min(srcW, dstW)
        let copyH = min(srcH, dstH)
        data.withUnsafeBufferPointer { srcBuf in
            result.withUnsafeMutableBufferPointer { dstBuf in
                let dst = dstBuf.baseAddress!
                let src = srcBuf.baseAddress!
                for row in 0..<copyH {
                    let srcOffset = row * srcW
                    let dstOffset = row * dstW
                    guard srcOffset + copyW <= srcBuf.count else { return }
                    (dst + dstOffset).update(from: src + srcOffset, count: copyW)
                }
            }
        }
        return result
    }

    /// Extracts a subband as a Float array with zero-padding to expected dimensions.
    private func getSubbandAsFloat(_ subbands: [SubbandInfo], level: Int, subband: J2KSubband,
                                    dstW: Int, dstH: Int) -> [Float] {
        if let sb = subbands.first(where: { $0.level == level && $0.subband == subband }) {
            let srcData: [Float]
            if let dc = sb.doubleCoefficients {
                srcData = vDSPConvert.doublesToFloats(dc)
            } else {
                srcData = vDSPConvert.int32sToFloats(sb.coefficients)
            }
            return padFlatFloat(srcData, srcW: sb.width, srcH: sb.height, dstW: dstW, dstH: dstH)
        }
        return [Float](repeating: 0, count: dstW * dstH)
    }

    /// Zero-pads a flat Float array from source to destination dimensions.
    private func padFlatFloat(_ data: [Float], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Float] {
        if srcW == dstW && srcH == dstH && data.count == dstW * dstH { return data }
        var result = [Float](repeating: 0, count: dstW * dstH)
        let copyW = min(srcW, dstW)
        let copyH = min(srcH, dstH)
        for row in 0..<copyH {
            let srcOffset = row * srcW
            let dstOffset = row * dstW
            guard srcOffset + copyW <= data.count else { break }
            for col in 0..<copyW {
                result[dstOffset + col] = data[srcOffset + col]
            }
        }
        return result
    }

    // MARK: - Stage 6: Inverse Colour Transform

    /// GPU-accelerated inverse colour transform using Metal.
    ///
    /// Inverse ICT/RCT colour transform on 3+ component images.
    ///
    /// v5.14: routes through the in-place CPU vDSP path
    /// (`applyInverseColorTransformInPlace`) instead of the GPU MCT
    /// path. Profile data on a 1024×1024 RGB lossless decode showed
    /// the GPU MCT branch took ~9 ms — most of which was the
    /// `Double → Float → MCT → Float → Double` round-trip overhead
    /// rather than the MCT compute itself. The in-place CPU path
    /// stays in Double throughout (matching the IDWT output type),
    /// uses `vDSP_vsmaD` / `vDSP_vaddD` / `vDSP_vsubD` for the
    /// per-pixel arithmetic, and steals the input arrays' inner
    /// buffers (no allocation overhead beyond a single temp). The
    /// GPU MCT path remains in `J2KMetalColorTransform` for future
    /// re-introduction if a fused MCT-into-IDWT-cb landing
    /// (avoiding the round-trip) becomes practical.
    private func applyInverseColorTransformGPU(
        _ components: [[Double]],
        metadata: CodestreamMetadata
    ) async throws -> [[Double]] {
        guard components.count >= 3 else { return components }
        // useReversibleTransform indicates MCT is enabled; when false, no color transform
        guard metadata.configuration.useReversibleTransform else { return components }
        return try applyInverseColorTransform(components, metadata: metadata)
    }

    /// Applies inverse colour transform.
    private func applyInverseColorTransform(
        _ components: [[Double]],
        metadata: CodestreamMetadata
    ) throws -> [[Double]] {
        // Only apply if 3+ components
        guard components.count >= 3 else { return components }

        // Apply inverse RCT/ICT based on configuration
        // useReversibleTransform indicates MCT is enabled; waveletFilter determines RCT vs ICT
        if metadata.configuration.useReversibleTransform {
            if case .reversible53 = metadata.configuration.waveletFilter {
                // Inverse RCT (lossless) — operate directly on Doubles to avoid conversion overhead
                let transform = J2KColorTransform(configuration: J2KColorTransformConfiguration(mode: .reversible))
                let (r, g, b) = try transform.inverseRCTDouble(
                    y: components[0],
                    cb: components[1],
                    cr: components[2]
                )

                var result: [[Double]] = [r, g, b]
                if components.count > 3 {
                    result.append(contentsOf: components[3...])
                }
                return result
            } else {
                // Inverse ICT (lossy) — stays in Double precision throughout
                let transform = J2KColorTransform(configuration: J2KColorTransformConfiguration(mode: .irreversible))
                let (red, green, blue) = try transform.inverseICT(y: components[0], cb: components[1], cr: components[2])

                var result: [[Double]] = [red, green, blue]
                if components.count > 3 {
                    result.append(contentsOf: components[3...])
                }
                return result
            }
        } else {
            // No MCT
            return components
        }
    }

    /// In-place inverse colour transform: modifies `components` directly.
    /// Uses the steal pattern (drop outer reference before mutation) to guarantee
    /// refcount=1 on each inner buffer, preventing COW copies on in-place vDSP ops.
    /// ICT: allocates only 1 new [Double] (for G) — saves 2× large buffer allocations.
    /// RCT: allocates only 1 temp [Double] — saves 1× large buffer allocation.
    private func applyInverseColorTransformInPlace(
        _ components: inout [[Double]],
        metadata: CodestreamMetadata
    ) throws {
        guard components.count >= 3 else { return }
        guard metadata.configuration.useReversibleTransform else { return }

        // Steal inner arrays: zeroing components[i] drops the outer reference,
        // giving y/cb/cr exclusive ownership (refcount=1) so withUnsafeMutableBufferPointer
        // never copies the buffer.
        var y  = components[0]; components[0] = []
        var cb = components[1]; components[1] = []
        var cr = components[2]; components[2] = []

        let count = y.count
        guard count > 0, cb.count >= count, cr.count >= count else {
            components[0] = y; components[1] = cb; components[2] = cr
            return
        }
        let n = vDSP_Length(count)

        if case .reversible53 = metadata.configuration.waveletFilter {
            // Inverse RCT (ISO 15444-1 G.2):
            //   G = Y - floor((Cb + Cr) / 4)   in-place in y
            //   R = Cr + G                      in-place in cr
            //   B = Cb + G                      in-place in cb
            var temp = [Double](unsafeUninitializedCapacity: count) { _, s in s = count }
            var quarter = 0.25
            cb.withUnsafeBufferPointer { cbBuf in
                cr.withUnsafeBufferPointer { crBuf in
                    temp.withUnsafeMutableBufferPointer { tBuf in
                        vDSP_vaddD(cbBuf.baseAddress!, 1, crBuf.baseAddress!, 1, tBuf.baseAddress!, 1, n)
                    }
                }
            }
            temp.withUnsafeMutableBufferPointer { tBuf in
                vDSP_vsmulD(tBuf.baseAddress!, 1, &quarter, tBuf.baseAddress!, 1, n)
                vvfloor(tBuf.baseAddress!, tBuf.baseAddress!, [Int32(count)])
            }
            y.withUnsafeMutableBufferPointer { yBuf in
                temp.withUnsafeBufferPointer { tBuf in
                    vDSP_vsubD(tBuf.baseAddress!, 1, yBuf.baseAddress!, 1, yBuf.baseAddress!, 1, n)
                }
            }
            y.withUnsafeBufferPointer { gBuf in
                cr.withUnsafeMutableBufferPointer { crBuf in
                    vDSP_vaddD(crBuf.baseAddress!, 1, gBuf.baseAddress!, 1, crBuf.baseAddress!, 1, n)
                }
                cb.withUnsafeMutableBufferPointer { cbBuf in
                    vDSP_vaddD(cbBuf.baseAddress!, 1, gBuf.baseAddress!, 1, cbBuf.baseAddress!, 1, n)
                }
            }
            // [R=cr, G=y, B=cb]
            components[0] = cr
            components[1] = y
            components[2] = cb
        } else {
            // Inverse ICT (ISO 15444-1 G.3):
            //   G = Y - 0.344136*Cb - 0.714136*Cr   1 new buffer
            //   R = Y + 1.402*Cr                     in-place in cr
            //   B = Y + 1.772*Cb                     in-place in cb
            var g = [Double](unsafeUninitializedCapacity: count) { _, s in s = count }
            var cGCb = -0.344136, cGCr = -0.714136, cRCr = 1.402, cBCb = 1.772
            y.withUnsafeBufferPointer { yBuf in
                cb.withUnsafeBufferPointer { cbBuf in
                    cr.withUnsafeBufferPointer { crBuf in
                        g.withUnsafeMutableBufferPointer { gBuf in
                            vDSP_vsmaD(cbBuf.baseAddress!, 1, &cGCb, yBuf.baseAddress!, 1, gBuf.baseAddress!, 1, n)
                            vDSP_vsmaD(crBuf.baseAddress!, 1, &cGCr, gBuf.baseAddress!, 1, gBuf.baseAddress!, 1, n)
                        }
                    }
                }
                cr.withUnsafeMutableBufferPointer { crBuf in
                    vDSP_vsmaD(crBuf.baseAddress!, 1, &cRCr, yBuf.baseAddress!, 1, crBuf.baseAddress!, 1, n)
                }
                cb.withUnsafeMutableBufferPointer { cbBuf in
                    vDSP_vsmaD(cbBuf.baseAddress!, 1, &cBCb, yBuf.baseAddress!, 1, cbBuf.baseAddress!, 1, n)
                }
            }
            // [R=cr, G=g, B=cb]
            components[0] = cr
            components[1] = g
            components[2] = cb
        }
    }

    // MARK: - Stage 7: Image Reconstruction

    /// Reconstructs the final J2KImage from component data.
    private func reconstructImage(
        _ components: [[Double]],
        metadata: CodestreamMetadata
    ) throws -> J2KImage {
        var imageComponents: [J2KComponent] = []

        func clampRoundedToInt32(_ value: Double) -> Int32 {
            let rounded = value.rounded()
            if rounded.isNaN { return 0 }
            if rounded >= Double(Int32.max) { return Int32.max }
            if rounded <= Double(Int32.min) { return Int32.min }
            return Int32(rounded)
        }

        // Shared chunk buffer — allocated once, reused across all components.
        // chunkSize keeps working set (Float chunks) in L2 cache.
        #if canImport(Accelerate)
        let chunkSize = 65536
        var floatChunk = [Float](repeating: 0, count: chunkSize)
        #endif

        for (idx, compData) in components.enumerated() {
            guard idx < metadata.components.count else { break }

            let compInfo = metadata.components[idx]
            let width = metadata.width / compInfo.subsamplingX
            let height = metadata.height / compInfo.subsamplingY
            let componentLowerBound: Int32
            let componentUpperBound: Int32
            if compInfo.signed {
                let halfRange = Int64(1) << Int64(max(compInfo.bitDepth - 1, 0))
                componentLowerBound = Int32(max(Int64(Int32.min), -halfRange))
                componentUpperBound = Int32(min(Int64(Int32.max), halfRange - 1))
            } else {
                componentLowerBound = 0
                let maxValue = (Int64(1) << Int64(max(compInfo.bitDepth, 1))) - 1
                componentUpperBound = Int32(min(Int64(Int32.max), maxValue))
            }

            // Convert Double array to Data with final rounding and clamping
            // Pre-allocate the exact size needed
            let bytesPerPixel = compInfo.bitDepth <= 8 ? 1 : 2
            let pixelCount = compData.count
            var data = Data(count: pixelCount * bytesPerPixel)

            data.withUnsafeMutableBytes { rawBuf in
                let ptr = rawBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let hostIsLittleEndian = j2kHostIsLittleEndian()
                let lo = Double(componentLowerBound)
                let hi = Double(componentUpperBound)

#if canImport(Accelerate)
                // Chunked vDSP pipeline: Double→Float → clip (Float, in-place) → integer bytes.
                // Clipping in Float (not Double) eliminates the 512 KB dblChunk intermediate,
                // halving the L2 working-set and reducing per-component allocation overhead.
                // Float has sufficient precision for all standard bit depths (≤24-bit).
                var floatLo = Float(lo), floatHi = Float(hi)

                compData.withUnsafeBufferPointer { src in
                    let srcBase = src.baseAddress!
                    if compInfo.bitDepth <= 8 && !compInfo.signed {
                        // 8-bit unsigned: vDSP_vdpsp → vDSP_vclip → vDSP_vfixru8
                        floatChunk.withUnsafeMutableBufferPointer { fBuf in
                            for start in stride(from: 0, to: pixelCount, by: chunkSize) {
                                let n = min(chunkSize, pixelCount - start)
                                let cnt = vDSP_Length(n)
                                vDSP_vdpsp(srcBase + start, 1, fBuf.baseAddress!, 1, cnt)
                                vDSP_vclip(fBuf.baseAddress!, 1, &floatLo, &floatHi, fBuf.baseAddress!, 1, cnt)
                                vDSP_vfixru8(fBuf.baseAddress!, 1, ptr + start, 1, cnt)
                            }
                        }
                    } else if compInfo.bitDepth > 8 && !compInfo.signed {
                        // 16-bit unsigned → big-endian bytes.
                        // Fast path: vDSP fixes to UInt16 in host byte order, then bulk byte-swap on LE hosts.
                        let u16Ptr = ptr.withMemoryRebound(to: UInt16.self, capacity: pixelCount) { $0 }
                        floatChunk.withUnsafeMutableBufferPointer { fBuf in
                            for start in stride(from: 0, to: pixelCount, by: chunkSize) {
                                let n = min(chunkSize, pixelCount - start)
                                let cnt = vDSP_Length(n)
                                vDSP_vdpsp(srcBase + start, 1, fBuf.baseAddress!, 1, cnt)
                                vDSP_vclip(fBuf.baseAddress!, 1, &floatLo, &floatHi, fBuf.baseAddress!, 1, cnt)
                                vDSP_vfixru16(fBuf.baseAddress!, 1, u16Ptr + start, 1, cnt)
                            }
                        }
                        if hostIsLittleEndian {
                            for i in 0..<pixelCount { u16Ptr[i] = u16Ptr[i].byteSwapped }
                        }
                    } else if compInfo.bitDepth > 8 && compInfo.signed {
                        // 16-bit signed (e.g. CT Hounsfield units) → big-endian bytes.
                        let i16Ptr = ptr.withMemoryRebound(to: Int16.self, capacity: pixelCount) { $0 }
                        floatChunk.withUnsafeMutableBufferPointer { fBuf in
                            for start in stride(from: 0, to: pixelCount, by: chunkSize) {
                                let n = min(chunkSize, pixelCount - start)
                                let cnt = vDSP_Length(n)
                                vDSP_vdpsp(srcBase + start, 1, fBuf.baseAddress!, 1, cnt)
                                vDSP_vclip(fBuf.baseAddress!, 1, &floatLo, &floatHi, fBuf.baseAddress!, 1, cnt)
                                vDSP_vfixr16(fBuf.baseAddress!, 1, i16Ptr + start, 1, cnt)
                            }
                        }
                        if hostIsLittleEndian {
                            for i in 0..<pixelCount { i16Ptr[i] = i16Ptr[i].byteSwapped }
                        }
                    } else {
                        // 8-bit signed: scalar fallback
                        for i in 0..<pixelCount {
                            let rounded = min(componentUpperBound, max(componentLowerBound, clampRoundedToInt32(compData[i])))
                            ptr[i] = UInt8(bitPattern: Int8(clamping: rounded))
                        }
                    }
                }
#else
                if compInfo.bitDepth <= 8 {
                    if compInfo.signed {
                        for i in 0..<pixelCount {
                            let rounded = min(componentUpperBound, max(componentLowerBound, clampRoundedToInt32(compData[i])))
                            ptr[i] = UInt8(bitPattern: Int8(clamping: rounded))
                        }
                    } else {
                        for i in 0..<pixelCount {
                            let rounded = min(componentUpperBound, max(componentLowerBound, clampRoundedToInt32(compData[i])))
                            ptr[i] = UInt8(clamping: max(0, rounded))
                        }
                    }
                } else {
                    // 16-bit output: big-endian byte order (PGM / DICOM Explicit VR BE
                    // convention). Callers expecting little-endian output (e.g. DICOM
                    // Explicit VR LE transfer syntax) must byte-swap at integration.
                    if compInfo.signed {
                        for i in 0..<pixelCount {
                            let rounded = min(componentUpperBound, max(componentLowerBound, clampRoundedToInt32(compData[i])))
                            let v = UInt16(bitPattern: Int16(clamping: rounded))
                            ptr[i * 2]     = UInt8(v >> 8)
                            ptr[i * 2 + 1] = UInt8(v & 0xFF)
                        }
                    } else {
                        for i in 0..<pixelCount {
                            let rounded = min(componentUpperBound, max(componentLowerBound, clampRoundedToInt32(compData[i])))
                            let v = UInt16(clamping: max(0, rounded))
                            ptr[i * 2]     = UInt8(v >> 8)
                            ptr[i * 2 + 1] = UInt8(v & 0xFF)
                        }
                    }
                }
#endif
            }

            // v5.14.1: tag the component byte order explicitly so
            // downstream consumers (CLI PGM/PPM writers, file-format
            // serialisers) can write spec-compliant bytes without
            // re-swapping. The decoder's `reconstructImage` step
            // produces 16-bit samples in big-endian byte order
            // (the `if hostIsLittleEndian { byteSwapped }` branch a
            // few lines up); 8-bit samples are byte-order-agnostic.
            // Without this tag, callers that don't know the
            // convention silently corrupt 16-bit output.
            let component = J2KComponent(
                index: idx,
                bitDepth: compInfo.bitDepth,
                signed: compInfo.signed,
                width: width,
                height: height,
                subsamplingX: compInfo.subsamplingX,
                subsamplingY: compInfo.subsamplingY,
                data: data,
                sampleByteOrder: compInfo.bitDepth > 8 ? .bigEndian : nil
            )

            imageComponents.append(component)
        }

        return J2KImage(
            width: metadata.width,
            height: metadata.height,
            components: imageComponents
        )
    }

    // MARK: - Progress Reporting

    private func reportProgress(
        _ callback: ((DecoderProgressUpdate) -> Void)?,
        stage: DecodingStage,
        stageProgress: Double
    ) {
        guard let callback = callback else { return }
        let stages = DecodingStage.allCases
        guard let stageIndex = stages.firstIndex(of: stage) else { return }
        let stageWeight = 1.0 / Double(stages.count)
        let overall = Double(stageIndex) * stageWeight + stageProgress * stageWeight
        callback(DecoderProgressUpdate(
            stage: stage,
            progress: stageProgress,
            overallProgress: min(overall, 1.0)
        ))
    }
}
