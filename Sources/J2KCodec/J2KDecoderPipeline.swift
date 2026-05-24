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

    /// Per-resolution precinct size exponents (from COD when Scod bit 0
    /// is set; nil for default precinct sizes — one precinct per band).
    /// Each entry is `(widthExp, heightExp)`. ISO 15444-1 A.6.1: at
    /// resolution 0 (LL) the precinct covers a 2^widthExp × 2^heightExp
    /// region of LL; at r > 0 each sub-band precinct is 2^(widthExp-1)
    /// × 2^(heightExp-1). v5.35.0d-decode addition.
    var precinctExponents: [(widthExp: Int, heightExp: Int)]? = nil

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

    /// v10.5.0 Stage B.1 — partial-resolution decode target level.
    /// When non-nil, `extractTileData` filters code-blocks to only
    /// those needed for resolution level `r ∈ [0, N]` where
    /// `N = metadata.configuration.decompositionLevels`:
    ///   - `r = 0` → only the LL (deepest); thumbnail output
    ///   - `r = N` → all blocks; full decode
    ///   - `r ∈ (0, N)` → LL + deepest r detail levels
    ///
    /// Set by `J2KDecoder.decodeResolution(_:options:)` via the
    /// public API. Stage B.1 saves the dominant entropy decode stage
    /// for skipped blocks; Stage B.2 also truncates the inverse DWT
    /// and outputs reduced-dimension data directly (no separate
    /// downsample step).
    var partialResolutionLevel: Int? = nil

    /// v10.5.0 Stage B.2 — reduced output dimensions for partial
    /// resolution decode. Set in tandem with `partialResolutionLevel`
    /// before the decode runs:
    ///   width  = ⌈metadata.width  / 2^(N-r)⌉
    ///   height = ⌈metadata.height / 2^(N-r)⌉
    /// The downstream stages (color transform, DC unshift,
    /// reconstructImage) substitute this for
    /// `metadata.width × metadata.height` to allocate / iterate
    /// reduced buffers.
    ///
    /// When nil, downstream stages use the full metadata dimensions
    /// (preserves v10.4.0 and earlier behaviour).
    var outputDimensions: (width: Int, height: Int)? = nil

    /// v10.6.0 ROI decode — region of interest in full-image pixel
    /// coordinates. When set, `extractTileData` keeps only code-blocks
    /// whose inverse-DWT spatial footprint (plus a conservative
    /// synthesis-filter halo) overlaps the region; entropy decode is
    /// skipped for the rest. The inverse DWT still runs full-tile —
    /// off-region blocks reconstruct as zeros, which is harmless
    /// because the caller crops to the region afterwards. Every block
    /// influencing an in-region pixel is retained, so the cropped
    /// output is bit-identical to a full decode + crop.
    ///
    /// Set by `J2KDecoder.decodeRegion(_:options:)` for the `.direct`
    /// strategy. nil = no spatial filtering (full decode).
    var regionOfInterest: J2KRegion? = nil

    /// v10.9.0 quality-layer decode — when set, the multi-layer packet
    /// decode (`extractTileDataMultiLayer`) processes only quality
    /// layers `0...maxQualityLayer`, discarding the refinement carried
    /// by higher layers. nil = decode every layer (full quality). Has
    /// no effect on single-layer codestreams. Set by
    /// `J2KDecoder.decodeQuality(_:options:)`.
    var maxQualityLayer: Int? = nil

    // MARK: - v6.2.0 — GPU inverse 5/3 INT DWT routing gate
    //
    // Originally proposed as a default-on flip mirroring v6.1.0's
    // encode-side `_gpuForward53Enabled` (#310). PR #313 had measured
    // that default `decode(_:)` runs entirely on CPU at DX 6.4 MP
    // (gpuHT = 0 across the corpus) and iDWT was 36.3 % of DX wall,
    // so default-on looked like a free 30 %+ win.
    //
    // **Empirical reality (this PR's wall-time A/B): a regression on
    // every corpus fixture including DX (−8.3 %).** Routing through
    // `decodeGPU` for lossless 5/3 INT pays dispatch + per-decode
    // pipeline init cost without enough savings — the CPU 5/3 INT
    // iDWT (Accelerate-vectorised) is already very fast on M2, and
    // the GPU iDWT path was tuned for lossy 9/7 Float where it has
    // bigger relative gains. Per memory `project_gpu97_warm_session_ceiling.md`
    // the real win is at ≥3 MP via `decodeWithGPUHT` (which ALSO
    // sets `useGPUHT = true` for HT entropy on GPU); just routing to
    // `decodeGPU` (iDWT only) doesn't move the needle.
    //
    // **Default left OFF** in this PR. Gate infrastructure ships
    // for future work that pursues the right routing target (likely
    // `useGPUHT = true` together with the iDWT routing — Phase D2).
    //
    // Decoded J2KImage pixel data IS byte-identical between gate-on
    // and forced-off paths (lossless contract preserved when this
    // flag is flipped manually) — the regression is wall-time only,
    // not correctness.

    /// v6.2.0 — gate flag for routing decode through the GPU inverse
    /// 5/3 INT DWT path. **Default OFF after this PR's measurement
    /// showed a wall-time regression on every M2 corpus fixture.**
    /// Set to true via the env var or programmatically to opt in for
    /// diagnostic A/B or for hosts where the GPU dispatch curve may
    /// have shifted (M3 / M4 / M4 Pro / M4 Max — re-run
    /// `GPUInverse53DefaultOnTests.testDefaultOn_WallTimeAB_AcrossCorpus`
    /// to see if the curve flips on your hardware).
    nonisolated(unsafe) static var _gpuInverse53Enabled: Bool = _readGPUInverse53Env()

    private static func _readGPUInverse53Env() -> Bool {
        if let v = ProcessInfo.processInfo.environment["J2K_GPU_INVERSE_53"] {
            switch v.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: break
            }
        }
        // v6.2.0 D4: default ON. The OR-with-static-flag bug from
        // D2/D3 is fixed (added `isGPUPath` parameter to
        // applyEntropyDecoding constraining the static-flag check
        // to GPU pipeline paths only). Warm session from D3
        // (processShared) amortises Metal init across decodes.
        // DX 2800×2288 wall-time win measured at +37 % vs CPU on M2.
        return true
    }

    /// v6.2.0 — pixel-count threshold for the GPU inverse 5/3 INT
    /// path. Defaults to 4 000 000 (4 MP), mirroring the encode-side
    /// `_gpuForward53PixelThreshold`. Even with the flag flipped on,
    /// sub-threshold fixtures stay on CPU. Tests can lower it
    /// temporarily to exercise the GPU code path on smaller fixtures.
    nonisolated(unsafe) static var _gpuInverse53PixelThreshold: Int = 4_000_000

    /// v7.1.1 hotfix — per-tile pixel threshold for the GPU inverse
    /// 5/3 path **on the multi-tile per-tile decode** route opened
    /// by H3 (#349). Defaults to 1 048 576 (1024×1024 = 1 MP). Below
    /// this, the multi-tile per-tile decode falls back to CPU IDWT
    /// for that tile — small per-tile sizes pay too much GPU
    /// dispatch overhead × N tiles to amortise (DX 4x4 with 16 ×
    /// 400 K-pixel tiles regressed 2.14× vs CPU IDWT in v7.1.0;
    /// recovers to ~CPU wall once falling back below 1 MP/tile).
    /// Tests can lower this to exercise the GPU code path on
    /// smaller per-tile sizes.
    nonisolated(unsafe) static var _gpuInverse53MultiTilePerTilePixelThreshold: Int = 1_048_576

    /// v7.1.1 hotfix — per-tile pixel threshold for the GPU **HT
    /// entropy** path on the multi-tile per-tile decode route opened
    /// by H1.1 (#335). Defaults to 1 048 576 (1024×1024 = 1 MP).
    /// Below this, the multi-tile per-tile decode falls back to CPU
    /// entropy (the v7.0.0 behaviour) for that tile — small per-tile
    /// sizes pay too much GPU dispatch overhead × N tiles to amortise.
    /// DX 4x4 with 16 × 400 K-pixel tiles regressed 60 ms → 128 ms
    /// (2.14×) in v7.1.0 vs v7.0.0; the hotfix restores the v7.0.0
    /// behaviour on those tiles. Tests can lower this var to exercise
    /// the GPU entropy code path on smaller per-tile sizes.
    nonisolated(unsafe) static var _gpuHTEntropyMultiTilePerTilePixelThreshold: Int = 1_048_576

    /// v7.2.0 Phase E — gate flag for the cross-tile batched-entropy
    /// decode path (`decodeMultiTileGPUBatched`). When true AND the
    /// codestream is multi-tile + HT-conformant + lossless 5/3 with
    /// a Metal session, the multi-tile decode path aggregates all
    /// tiles' eligible HT codeblocks into a single GPU dispatch
    /// before per-tile post-processing. Amortises the per-tile
    /// MTLCommandBuffer overhead × N tiles which dominates wall-time
    /// on small per-tile sizes (per V720PhaseEThresholdSweepTests).
    /// Default ON — gate exists so tests / probes can opt out for
    /// A/B comparison against the v7.1.1 per-tile-CB shape.
    /// **v8.2 fix**: re-enabled by default. The v7.5.1 hotfix
    /// disabled this path because of silent decode corruption on
    /// 16+ MP mammography fixtures (smallest reproducer 1760×2392
    /// split 2x2). Root cause located 2026-05-10 in
    /// `decodeTilePayloadGPU`: when `preBatchedGPUCoefficients`
    /// short-circuits the entropy stage's GPU dispatch, the
    /// entropy returns `(coeffs, batch=nil)` — `gpuBatch` is `nil`
    /// downstream, so `applyInverseWaveletTransformGPU`'s
    /// `hasFusedFromCodeblocksPlan` CPU-fallback branch does not
    /// fire and the GPU multi-tile-per-tile IDWT runs. That GPU
    /// IDWT path silently corrupts output on certain dimensions.
    /// The fix forces CPU IDWT explicitly when `preBatched` is set
    /// (matching the per-tile path's behaviour with a non-nil
    /// `gpuBatch`). Verified bit-exact across the v8.2 diagnostic
    /// sweep (10 dimensions including the original mg fixture)
    /// and `MgRegressionTriageTest`. The cross-tile entropy
    /// amortisation that v7.2.0 measured (3 % DX 2x2) is restored.
    nonisolated(unsafe) static var _multiTileBatchedEntropyEnabled: Bool = true

    /// **v10.3 (refinement) — default `false`, but the predicate at the
    /// call site (`decodeTilePayloadGPU` line ~1270) now gates on
    /// per-tile pixel size.** Original behaviour: forced CPU IDWT
    /// whenever `preBatchedGPUCoefficients` was set, to sidestep the
    /// GPU multi-tile-per-tile IDWT corruption documented in
    /// V8_2_0_MG_CORRUPTION_ROOT_CAUSE.md (v8.3 root-caused and fixed
    /// the underlying GPU defect, PR #400).
    ///
    /// d117dcc shipped a global `false → true` flip that unlocked the
    /// MG GPU IDWT win but regressed DX/PX in the substitute corpus.
    /// This commit reverts the default to `false` and adds a per-tile
    /// size predicate at the call site:
    ///   - tile < 3 MP: CPU IDWT (keeps DX/PX 4x4 multi-tile wins)
    ///   - tile ≥ 3 MP: GPU IDWT (captures MG 2x2 multi-tile win)
    ///
    /// Setting this flag to `true` overrides the size gate and forces
    /// GPU IDWT for every tile regardless of size — kept for
    /// diagnostic A/B (replicates d117dcc's behaviour for comparison).
    ///
    /// v8.3 conformance suite + V8_3_GPUIDWTRootCauseDiagnostic +
    /// V8_2_MgBatchedDiagnostic + MgRegressionTriageTest +
    /// V10_3_V82BypassCrossCodecCheck (9 medical-real fixtures
    /// bit-exact) all PASS under both flag states.
    nonisolated(unsafe) static var _v82_disableIDWTRoutingFix: Bool = false

    /// v6.2.0 work item D2 — gate flag for routing decode through
    /// the **GPU HT entropy** decode path (the `useGPUHT = true`
    /// behaviour from `decodeWithGPUHT`). When this flag is true
    /// AND `_gpuInverse53Enabled` is true AND the iDWT threshold
    /// is met, `decode(_:)` will set `useGPUHT = true` and route
    /// to the GPU paths — the same code path
    /// `J2KDecoder.decodeWithGPUHT` already exposes.
    ///
    /// **Default OFF.** D1 (#314) found iDWT-only routing regresses
    /// on every M2 corpus fixture; per memory `project_gpu97_warm_session_ceiling.md`
    /// the win at decode lives at ≥3 MP via `decodeWithGPUHT`
    /// (which the iDWT-only routing missed). D2 tests whether
    /// pairing iDWT routing with GPU HT entropy flips the
    /// regression to a win at corpus scale on M2.
    ///
    /// Bytes byte-identical to the legacy CPU path (HT entropy
    /// GPU decode has been bit-exact via the `J2KGPUHTDispatch`
    /// path since v5.5.0). Set true via env var
    /// `J2K_GPU_HT_ENTROPY_DECODE` or programmatically for
    /// diagnostic A/B; production default unchanged from D1
    /// (CPU on the default `decode(_:)` entry point).
    nonisolated(unsafe) static var _gpuHTEntropyEnabled: Bool = _readGPUHTEntropyEnv()

    private static func _readGPUHTEntropyEnv() -> Bool {
        if let v = ProcessInfo.processInfo.environment["J2K_GPU_HT_ENTROPY_DECODE"] {
            switch v.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: break
            }
        }
        // v10.3.0 (2026-05-20): default flipped from ON to OFF after the
        // v10.7-research engagement check + 10-trial variance bench
        // (V10_7_GPUHTEntropyEngagementCheck + V10_7_GPUHTEntropyFlagFlipVarianceTests)
        // showed `_gpuHTEntropyEnabled = true` regresses MG decode by
        // 19-27 ms median (100% of trials positive) with zero impact
        // on non-MG fixtures.
        //
        // The v6.2.0 D4 default-on was correct at the time (+37 % DX
        // win measured) but the CPU HT path got significantly faster
        // post-v10.0 D1.5-D (NEON HT decoder default-on) — the GPU HT
        // entropy path is now slower than CPU+NEON on multi-tile
        // mammography workloads.
        //
        // Opt-in via `J2K_GPU_HT_ENTROPY_DECODE=1` is preserved for
        // cross-silicon re-evaluation (M3/M4/A-series may flip the
        // crossover) and diagnostic A/B.
        return false
    }

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

        // v10.5.0 Stage B.2 — `outputDimensions` is computed by the
        // caller (`J2KDecoder.decodePartialResolution`) and set on the
        // pipeline before this call when partial-resolution decode is
        // active; `decode` reads it but does not mutate `self`.

        // v6.2.0 — gated routing to the GPU decode paths.
        //
        // D1 (#314) added `_gpuInverse53Enabled` for routing to the
        // GPU iDWT path. Default OFF after empirical regression on
        // every M2 corpus fixture (CPU 5/3 INT iDWT is already very
        // fast; the iDWT-only GPU win lives at ≥17 MP per memory).
        //
        // D2 (this PR) adds `_gpuHTEntropyEnabled` for ALSO setting
        // `useGPUHT = true` on the GPU path — mirror of
        // `decodeWithGPUHT(_:)`. When BOTH flags fire (and Metal
        // is available + threshold met), the GPU path additionally
        // batches eligible HT codeblocks through the Metal HT
        // cleanup kernel, targeting the 45 % of DX wall that the
        // iDWT-only routing missed.
        //
        // Bytes byte-identical with the legacy CPU path on the
        // lossless reversible code path (cross-codec gate + 6/6
        // corpus pixel-identical from D1's GPUInverse53DefaultOnTests).
        // v8 Phase 1 — reorder: cheap pixel-threshold check FIRST so
        // `J2KMetalDWT.isAvailable` (which costs ~50 ms cold the first
        // time Metal is touched per process) is avoided entirely when
        // the image is too small to benefit from GPU. Saves ~50 ms on
        // every CLI invocation that decodes an image below the threshold.
        // v10.5.0 Stage B.2 — when partial-resolution decode is active,
        // force the CPU iDWT path. The GPU iDWT
        // (`applyInverseWaveletTransformGPU`) doesn't yet honour the
        // truncation; routing partial-decode through GPU would
        // produce full-dimension data with a reduced-dimension image
        // header (consumers misinterpret rows/cols). CPU truncation
        // gets reduced data + reduced dims consistently. A future
        // optimisation would add the truncation to the GPU iDWT.
        let allowGPUPath = partialResolutionLevel == nil

        if allowGPUPath
            && Self._gpuInverse53Enabled
            && metadata.width * metadata.height >= Self._gpuInverse53PixelThreshold
            && J2KMetalDWT.isAvailable
        {
            // v6.3.0 E1.2 — routing widened to multi-tile.
            //
            // The v6.2.0 narrow `&& !metadata.isMultiTile` guard
            // blocked multi-tile fixtures from the GPU path because
            // the per-tile entropy decode path threw `malformedBlock`
            // on non-32-aligned tiles. v6.3.0 E1.1 (#321) fixed the
            // root cause — `decodeTilePayloadGPU` was missing the
            // `tileOriginX/Y` arguments to `extractTileData`, so the
            // canvas-anchored code-block partition (ISO 15444-1 B.7)
            // mis-aligned with the encoder's grid. With that one-
            // line fix in place, multi-tile decode is bit-exact via
            // the GPU path (HTTileParityMatrixTests 12/12, self-RT
            // diff 0, cross-decode diff 0 vs OpenJPH/Grok/Kakadu).
            //
            // D2: when `_gpuHTEntropyEnabled` is true, the consume
            // sites read `(useGPUHT || (isGPUPath && Self._gpuHTEntropyEnabled))`
            // so HT entropy goes to GPU per-tile. The `isGPUPath: true`
            // parameter at the per-tile call site (line 818)
            // tightens the check so CPU pipeline calls don't
            // accidentally trigger the GPU HT entropy decode
            // (the D4 #317 bug fix).
            if metadata.isMultiTile {
                return try await decodeMultiTileGPU(metadata: metadata, tiles: tiles, progress: progress)
            } else {
                let tileData = tiles.first?.tileData ?? Data()
                return try await decodeSingleTileGPU(metadata: metadata, tileData: tileData, progress: progress)
            }
        }

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
        let codeBlocks = try extractTileData(
            tileData, metadata: metadata,
            maxResolutionLevel: partialResolutionLevel, regionOfInterest: regionOfInterest,
            maxQualityLayer: maxQualityLayer)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordExtractTileData(dt / 1000)
            if profileDecode {
                print("PROFILE-GPU: extractTileData        = \(String(format: "%.1f", dt)) ms (\(codeBlocks.count) blocks)")
            }
        }
        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        reportProgress(progress, stage: .entropyDecoding, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let (decodedBlocks, gpuBatch) = try await applyEntropyDecoding(codeBlocks, metadata: metadata, isGPUPath: true)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordEntropyDecoding(dt / 1000)
            if profileDecode {
                print("PROFILE-GPU: entropyDecoding         = \(String(format: "%.1f", dt)) ms (\(decodedBlocks.count) subbands, gpuBatch=\(gpuBatch != nil))")
            }
        }
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 1.0)

        reportProgress(progress, stage: .dequantization, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: metadata)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordDequantization(dt / 1000)
            if profileDecode {
                print("PROFILE-GPU: dequantization          = \(String(format: "%.1f", dt)) ms")
            }
        }
        reportProgress(progress, stage: .dequantization, stageProgress: 1.0)

        // Stage 5: GPU inverse wavelet transform
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let spatialData = try await applyInverseWaveletTransformGPU(dequantizedSubbands, metadata: metadata, gpuBatch: gpuBatch)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordInverseWaveletTransform(dt / 1000)
            if profileDecode {
                print("PROFILE-GPU: inverseWaveletTransform = \(String(format: "%.1f", dt)) ms")
            }
        }
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 1.0)

        // Stages 6-7: GPU inverse colour transform
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        var rgbData = try await applyInverseColorTransformGPU(spatialData, metadata: metadata)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordInverseColorTransform(dt / 1000)
            if profileDecode {
                print("PROFILE-GPU: inverseColorTransform   = \(String(format: "%.1f", dt)) ms")
            }
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
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordDcLevelUnshift(dt / 1000)
            if profileDecode {
                print("PROFILE-GPU: dcLevelUnshift          = \(String(format: "%.1f", dt)) ms")
            }
        }

        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let image = try reconstructImage(rgbData, metadata: metadata)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordReconstructImage(dt / 1000)
            if profileDecode {
                print("PROFILE-GPU: reconstructImage        = \(String(format: "%.1f", dt)) ms")
            }
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
        // v7.2.0 Phase E — when the new cross-tile batched-entropy
        // path is enabled and applicable, route to it. Falls back to
        // the per-tile shape below for non-applicable codestreams
        // (irreversible, sessionless, non-conformant HT, etc.).
        //
        // Per-tile pixel threshold gate matches the v7.1.1 hotfix:
        // when per-tile pixels < `_gpuHTEntropyMultiTilePerTilePixelThreshold`
        // the GPU compute itself is slower than CPU on Apple M2 (the
        // V720PhaseEABTest measured +14% to +65% regressions across
        // small-per-tile fixtures when the master batch was forced
        // on regardless of threshold). Amortization eliminates the
        // per-tile CB overhead but doesn't make the GPU compute
        // faster than CPU on tiny tiles.
        let useHT = metadata.configuration.useHTJ2K
        let isReversible: Bool
        if case .irreversible97 = metadata.configuration.waveletFilter {
            isReversible = false
        } else {
            isReversible = true
        }
        let useConformant = useHT
            && metadata.configuration.htj2kBlockFormat == .conformant
        // Per-tile pixel count: tile dimensions live in `metadata.tileSize`
        // when the codestream is multi-tile.
        let perTilePx: Int = {
            if metadata.tileSize.width > 0 && metadata.tileSize.height > 0 {
                return metadata.tileSize.width * metadata.tileSize.height
            }
            return metadata.width * metadata.height
        }()
        let canBatch = Self._multiTileBatchedEntropyEnabled
            && useHT && useConformant && isReversible
            && metalSession != nil
            && J2KGPUHTDispatch.isAvailable
            && Self._gpuHTEntropyEnabled
            && tiles.count >= 2
            && perTilePx >= Self._gpuHTEntropyMultiTilePerTilePixelThreshold
        if canBatch {
            return try await decodeMultiTileGPUBatched(
                metadata: metadata, tiles: tiles, progress: progress)
        }

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

    /// **v7.2.0 Phase E — cross-tile batched HT entropy decode.**
    ///
    /// Same observable behaviour as `decodeMultiTileGPU` (bit-exact
    /// J2KImage output) but the per-tile GPU HT entropy dispatches
    /// are amortised into a SINGLE shared MTLCommandBuffer across
    /// all tiles. Eliminates the per-tile CB-overhead × N tiles cost
    /// that V720PhaseEThresholdSweepTests measured as the dominant
    /// factor in the 1.8× regression at 256K threshold (vs CPU
    /// entropy at 1 MP threshold).
    ///
    /// Pipeline shape:
    ///   1. Per-tile, sequentially: `extractTileData` → CodeBlockInfo[]
    ///      (CPU-bound; cheap per tile).
    ///   2. Aggregate every tile's eligible HT codeblocks into one
    ///      flat `[GPUHTBlock]` array. Track per-tile index ranges.
    ///   3. ONE `J2KGPUHTDispatch.decodeBatch` call decodes all the
    ///      blocks across all tiles in a single GPU command buffer.
    ///   4. Per tile, in parallel via `withThrowingTaskGroup`:
    ///      slice the master result by tile range, hand the slice
    ///      to `decodeTilePayloadGPU(... preBatchedGPUCoefficients:)`
    ///      which skips its own dispatch and runs the slow-lane
    ///      regroup → dequant → IDWT → dcShift on those coefficients.
    ///
    /// IDWT amortisation: not yet — multi-tile per-tile IDWT still
    /// runs on CPU per the v6.3.0 E1.2 / v7.1.1 routing. Batching
    /// IDWT is harder (per-tile geometry + scatter plans) and is
    /// deferred to a follow-up PR if entropy amortisation alone
    /// closes enough of the Kakadu gap.
    private func decodeMultiTileGPUBatched(
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

        // Stage 1 + 2: per-tile codeBlock extract + cross-tile aggregation.
        // We do this serially because extractTileData is fast (codestream
        // unpack only — no entropy work yet) and the aggregation maintains
        // one flat block array. Doing the codestream unpack in parallel
        // would just contend on the global parser locks for marginal gain.
        struct TileExtractedState {
            let tileIndex: Int
            let tileX: Int
            let tileY: Int
            let tileW: Int
            let tileH: Int
            let codeBlocks: [CodeBlockInfo]
            // Range into the master `[GPUHTBlock]` array for blocks
            // contributed by this tile. The map below translates from
            // master-index → this-tile-codeBlock-index.
            let masterRangeStart: Int
            let perTileEligibleIndices: [Int]
        }
        var extracted: [TileExtractedState] = []
        extracted.reserveCapacity(tiles.count)
        var allMasterBlocks: [GPUHTBlock] = []
        var masterToTileLocal: [(tileSlot: Int, tileLocalIdx: Int)] = []

        for (tileSlot, t) in tiles.enumerated() {
            let (tx, ty, tw, th) = metadata.tileDimensions(tileIndex: t.tileIndex)
            var tileMeta = metadata
            tileMeta.width = tw
            tileMeta.height = th
            tileMeta.tileSize = (width: tw, height: th)
            let extT0 = DispatchTime.now()
            let blocks = try extractTileData(
                t.tileData, metadata: tileMeta,
                tileOriginX: tx, tileOriginY: ty,
                maxResolutionLevel: partialResolutionLevel, regionOfInterest: regionOfInterest,
            maxQualityLayer: maxQualityLayer)
            J2KDecodeTimings.recordExtractTileData(
                Double(DispatchTime.now().uptimeNanoseconds - extT0.uptimeNanoseconds) / 1_000_000_000)

            let masterStart = allMasterBlocks.count
            var perTileEligible: [Int] = []
            perTileEligible.reserveCapacity(blocks.count)
            for (localIdx, block) in blocks.enumerated() {
                guard !block.data.isEmpty, block.passCount > 0 else { continue }
                allMasterBlocks.append(GPUHTBlock(
                    width: block.width,
                    height: block.height,
                    data: [UInt8](block.data),
                    missingMSBs: block.zeroBitPlanes))
                masterToTileLocal.append((tileSlot, localIdx))
                perTileEligible.append(localIdx)
            }
            extracted.append(TileExtractedState(
                tileIndex: t.tileIndex,
                tileX: tx, tileY: ty, tileW: tw, tileH: th,
                codeBlocks: blocks,
                masterRangeStart: masterStart,
                perTileEligibleIndices: perTileEligible))
        }

        // Stage 3: chunked GPU dispatches across all tiles' HT
        // entropy. The original v7.2.0 shape used a SINGLE
        // `decodeBatch` call across the entire master block
        // array, which silently corrupted output once the
        // aggregated batch exceeded a kernel-dispatch-internal
        // threshold (smallest reproducer: 1760×2392 split 2x2,
        // ~1000 blocks total — the per-tile path with the same
        // ~250 blocks per dispatch never failed). Chunking the
        // master batch caps any single dispatch's block count
        // and preserves correctness while still amortising the
        // per-CB overhead across multiple tiles per dispatch.
        //
        // Chunk size 256 was chosen empirically: per-tile
        // `decodeBatchGPUResident` calls in the v7.1.x shape
        // never exceeded ~250 blocks in any production fixture
        // and never failed; capping at 256 keeps each chunk in
        // that proven-correct regime.
        // Stage 3: ONE GPU dispatch for all tiles' HT entropy.
        // J2KGPUHTDispatch.decodeBatch handles fallbacks and returns
        // a flat result keyed by master block index.
        var preBatchedPerTile: [[Int: [Int32]]] = Array(
            repeating: [:], count: tiles.count)
        if !allMasterBlocks.isEmpty, let session = metalSession {
            let dispT0 = DispatchTime.now()
            let masterResult = try await J2KGPUHTDispatch.decodeBatch(
                blocks: allMasterBlocks, session: session)
            let dispDt = Double(DispatchTime.now().uptimeNanoseconds - dispT0.uptimeNanoseconds) / 1_000_000_000
            J2KDecodeTimings.recordGPUHTDispatch(dispDt)

            // Distribute master results back per tile.
            // `masterResult.decodedBlockIndices[i]` is a master-array
            // index; map it to (tileSlot, tileLocalIdx) and record
            // the coefficients in that tile's per-block dict.
            for (resultIdx, masterIdx) in masterResult.decodedBlockIndices.enumerated() {
                let mapping = masterToTileLocal[masterIdx]
                preBatchedPerTile[mapping.tileSlot][mapping.tileLocalIdx] =
                    masterResult.results[resultIdx].coefficients
            }
            // Ineligible master blocks fall through — their tiles
            // run the slow-lane CPU decode for those blocks.
        }

        // Stage 4: per-tile post-processing (parallel). Each tile
        // gets its slice of the master batch results via the
        // `preBatchedGPUCoefficients` parameter — `decodeTilePayloadGPU`
        // skips its own dispatch, runs the slow-lane regroup that
        // builds [SubbandInfo] from these coefficients, then continues
        // dequant + IDWT + dcShift.
        let chunkSize = max(1, Self.maxInFlightTilesGPU)
        var decodedTiles: [DecodedTile] = []
        decodedTiles.reserveCapacity(tiles.count)
        var tileSlot = 0
        while tileSlot < tiles.count {
            let end = min(tileSlot + chunkSize, tiles.count)
            let chunkSlots = Array(tileSlot..<end)
            let chunkResults = try await withThrowingTaskGroup(of: DecodedTile.self) { group in
                for slot in chunkSlots {
                    let info = extracted[slot]
                    let preBatched = preBatchedPerTile[slot]
                    let metadataCopy = metadata
                    let tileData = tiles[slot].tileData
                    let tileIndex = info.tileIndex
                    group.addTask {
                        try await self.decodeTilePayloadGPU(
                            metadata: metadataCopy,
                            tileIndex: tileIndex,
                            tileData: tileData,
                            preBatchedGPUCoefficients: preBatched.isEmpty ? nil : preBatched
                        )
                    }
                }
                var results: [DecodedTile] = []
                results.reserveCapacity(chunkSlots.count)
                for try await decoded in group {
                    results.append(decoded)
                }
                return results
            }
            decodedTiles.append(contentsOf: chunkResults)
            tileSlot = end
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
        let codeBlocks = try extractTileData(
            tileData, metadata: metadata,
            maxResolutionLevel: partialResolutionLevel, regionOfInterest: regionOfInterest,
            maxQualityLayer: maxQualityLayer)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordExtractTileData(dt / 1000)
            if profileDecode {
                print("PROFILE: extractTileData        = \(String(format: "%.1f", dt)) ms (\(codeBlocks.count) blocks)")
            }
        }
        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        // Stage 3: Entropy decoding
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let (decodedBlocks, _) = try await applyEntropyDecoding(codeBlocks, metadata: metadata)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordEntropyDecoding(dt / 1000)
            if profileDecode {
                print("PROFILE: entropyDecoding         = \(String(format: "%.1f", dt)) ms (\(decodedBlocks.count) subbands)")
            }
        }
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 1.0)

        // Stage 4: Dequantization
        reportProgress(progress, stage: .dequantization, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: metadata)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordDequantization(dt / 1000)
            if profileDecode {
                print("PROFILE: dequantization          = \(String(format: "%.1f", dt)) ms")
            }
        }
        reportProgress(progress, stage: .dequantization, stageProgress: 1.0)

        // Stage 5: Inverse wavelet transform
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        var spatialData = try await applyInverseWaveletTransform(dequantizedSubbands, metadata: metadata)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordInverseWaveletTransform(dt / 1000)
            if profileDecode {
                print("PROFILE: inverseWaveletTransform = \(String(format: "%.1f", dt)) ms (\(spatialData.count) components)")
            }
        }
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 1.0)

        // Stage 6: Inverse colour transform (in-place to avoid 2 large buffer allocations)
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        t0 = DispatchTime.now()
        try applyInverseColorTransformInPlace(&spatialData, metadata: metadata)
        var rgbData = spatialData
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordInverseColorTransform(dt / 1000)
            if profileDecode {
                print("PROFILE: inverseColorTransform   = \(String(format: "%.1f", dt)) ms")
            }
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
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordDcLevelUnshift(dt / 1000)
            if profileDecode {
                print("PROFILE: dcLevelUnshift          = \(String(format: "%.1f", dt)) ms")
            }
        }

        // Stage 7: Image reconstruction
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        t0 = DispatchTime.now()
        let image = try reconstructImage(rgbData, metadata: metadata)
        do {
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            J2KDecodeTimings.recordReconstructImage(dt / 1000)
            if profileDecode {
                print("PROFILE: reconstructImage        = \(String(format: "%.1f", dt)) ms")
            }
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

    /// v10.6.0 ROI Stage 1 skipped entropy decode for off-region
    /// code-blocks but still ran the inverse DWT full-tile. v10.7.0
    /// Stage 2 — tile-granular skip: when `regionOfInterest` is set and
    /// a tile lies entirely outside it, every pixel the tile would
    /// produce is cropped away by `decodeRegion`. JPEG 2000 tiles
    /// decode independently — no inverse-DWT halo crosses a tile
    /// boundary — so the whole tile (entropy, dequant, inverse DWT,
    /// colour transform, DC shift) can be skipped. Returns a
    /// correctly-shaped zero `DecodedTile` to short-circuit with, or
    /// nil when the tile overlaps the region and must be decoded.
    private func roiSkippedTile(
        tileX: Int, tileY: Int, tileW: Int, tileH: Int,
        metadata: CodestreamMetadata
    ) -> DecodedTile? {
        guard let roi = regionOfInterest else { return nil }
        let overlaps = tileX < roi.x + roi.width && tileX + tileW > roi.x
                    && tileY < roi.y + roi.height && tileY + tileH > roi.y
        if overlaps { return nil }
        let zeroRGB: [[Double]] = metadata.components.map { comp in
            let w = max(0, tileW / comp.subsamplingX)
            let h = max(0, tileH / comp.subsamplingY)
            return [Double](repeating: 0, count: w * h)
        }
        return DecodedTile(tileX: tileX, tileY: tileY, tileW: tileW, tileH: tileH, rgb: zeroRGB)
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

        // v10.7.0 ROI Stage 2 — skip tiles entirely outside the region.
        if let skipped = roiSkippedTile(
            tileX: tileX, tileY: tileY, tileW: tileW, tileH: tileH, metadata: metadata) {
            return skipped
        }

        var tileMeta = metadata
        tileMeta.width = tileW
        tileMeta.height = tileH
        tileMeta.tileSize = (width: tileW, height: tileH)

        // v7.2.0 Phase 0 — per-tile stage instrumentation. Mirrors the
        // `decodeSingleTile` pattern. Stage times are accumulated into
        // process-global `J2KDecodeTimings` counters; on multi-tile
        // decodes invoked from `withThrowingTaskGroup`, each parallel
        // tile contributes its CPU-time to the same accumulator, so a
        // sum across stages can exceed the decode wall (semantics
        // identical to the encode-side stage profile).
        var t0 = DispatchTime.now()
        let codeBlocks = try extractTileData(
            tileData, metadata: tileMeta,
            tileOriginX: tileX, tileOriginY: tileY,
            maxResolutionLevel: partialResolutionLevel, regionOfInterest: regionOfInterest,
            maxQualityLayer: maxQualityLayer)
        J2KDecodeTimings.recordExtractTileData(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        let (decodedBlocks, _) = try await applyEntropyDecoding(codeBlocks, metadata: tileMeta)
        J2KDecodeTimings.recordEntropyDecoding(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: tileMeta)
        J2KDecodeTimings.recordDequantization(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        var spatialDataTile = try await applyInverseWaveletTransform(
            dequantizedSubbands, metadata: tileMeta,
            tileOriginX: tileX, tileOriginY: tileY)
        J2KDecodeTimings.recordInverseWaveletTransform(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        try applyInverseColorTransformInPlace(&spatialDataTile, metadata: tileMeta)
        J2KDecodeTimings.recordInverseColorTransform(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < spatialDataTile.count else { break }
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                spatialDataTile[compIdx].withUnsafeMutableBufferPointer { buf in
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset, buf.baseAddress!, 1, vDSP_Length(buf.count))
                }
            }
        }
        J2KDecodeTimings.recordDcLevelUnshift(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        return DecodedTile(tileX: tileX, tileY: tileY, tileW: tileW, tileH: tileH, rgb: spatialDataTile)
    }

    /// Same as `decodeTilePayload` but routes the inverse wavelet transform
    /// through the GPU pipeline.
    ///
    /// **v7.2.0 Phase E** — `preBatchedGPUCoefficients` lets the
    /// caller (`decodeMultiTileGPUBatched`) supply pre-decoded HT
    /// entropy results obtained from a single shared GPU dispatch
    /// across all tiles. When non-nil, this function skips its own
    /// per-tile entropy GPU dispatch (the v7.1.1 1-MP per-tile gate)
    /// and consumes the pre-batched dict instead. Saves the per-tile
    /// MTLCommandBuffer overhead × N tiles which dominates wall-time
    /// on small per-tile sizes (per the V720PhaseEThresholdSweepTests
    /// finding).
    private func decodeTilePayloadGPU(
        metadata: CodestreamMetadata,
        tileIndex: Int,
        tileData: Data,
        preBatchedGPUCoefficients: [Int: [Int32]]? = nil
    ) async throws -> DecodedTile {
        let (tileX, tileY, tileW, tileH) = metadata.tileDimensions(tileIndex: tileIndex)

        // v10.7.0 ROI Stage 2 — skip tiles entirely outside the region.
        if let skipped = roiSkippedTile(
            tileX: tileX, tileY: tileY, tileW: tileW, tileH: tileH, metadata: metadata) {
            return skipped
        }

        var tileMeta = metadata
        tileMeta.width = tileW
        tileMeta.height = tileH
        tileMeta.tileSize = (width: tileW, height: tileH)

        // v6.3.0 E1.1: pass tile-component canvas origin so the
        // canvas-anchored code-block partition (ISO 15444-1 B.7)
        // matches the encoder's grid for non-32-aligned tiles.
        // Pre-fix this defaulted to (0, 0) which silently broke
        // multi-tile decode whenever the tile origin's modulo-32 was
        // non-zero (XA 1024² survived because every tile was 32-
        // aligned; MR/PX/DX failed). Mirrors `decodeTilePayload`.
        // v7.2.0 Phase 0 — per-tile stage instrumentation; same
        // semantics as `decodeTilePayload` (process-global accumulator,
        // CPU-time across parallel tiles).
        var t0 = DispatchTime.now()
        let codeBlocks = try extractTileData(
            tileData, metadata: tileMeta,
            tileOriginX: tileX, tileOriginY: tileY,
            maxResolutionLevel: partialResolutionLevel, regionOfInterest: regionOfInterest,
            maxQualityLayer: maxQualityLayer)
        J2KDecodeTimings.recordExtractTileData(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)
        // v7.1.0 H1.1 — multi-tile per-tile entropy on GPU.
        //
        // E1.2 (#322) was wrong about the root cause. H1.0 (#334)
        // proved per-block GPU HT entropy is bit-exact in every
        // multi-tile per-tile context (1881 blocks, 0 drift). H1.1
        // located the actual bug: the v5.9 zero-copy fast-lane
        // (line ~1902 in `applyEntropyDecoding`) returns
        // ([], batch) and assumes the IDWT will consume `batch`
        // via the GPU fused path. E1.2 forced CPU IDWT for multi-
        // tile per-tile, which then received empty `[SubbandInfo]`
        // → all zeros → DC unshift adds +32768 = exactly the
        // observed Defect A pixel diff.
        //
        // The fix: pass `isMultiTilePerTile: true` to suppress the
        // fast-lane. The slow-lane regroup runs and populates
        // `[SubbandInfo]` with the correct GPU-decoded coefficients
        // (gpuPreDecoded[i]) for downstream CPU IDWT consumption.
        //
        // Net result: GPU HT entropy is restored on the multi-tile
        // per-tile path (gain back the +37-46 % entropy stage win
        // single-tile decode already enjoys); CPU IDWT remains as
        // the safety net against Defect B (still pending H2 — GPU
        // 5/3 IDWT parity-aware boundary lifting).
        // v7.1.1 hotfix — per-tile pixel threshold on H1.1's GPU
        // entropy routing. v7.1.0 unconditionally took `isGPUPath:
        // true` on multi-tile per-tile decode, which won on big-per-
        // tile fixtures (DX 2x2 = 1.6 M px/tile gained +44–60 %) but
        // regressed on small-per-tile fixtures (DX 4x4 = 16 × 400 K
        // px/tile lost 2.14× because per-tile GPU dispatch overhead
        // dominates). Below ~1 MP per tile fall back to CPU entropy
        // (the v7.0.0 behaviour) — recovers DX 4x4 to ~60 ms.
        // v7.2.0 Phase E — pre-batched coefficients short-circuit. When
        // the caller already ran one shared GPU dispatch for all tiles,
        // we skip the per-tile dispatch and feed the pre-batched
        // coefficients into the slow-lane regroup. Otherwise apply the
        // v7.1.1 per-tile threshold gate.
        let perTilePixels = tileMeta.width * tileMeta.height
        let useGPUEntropy = (preBatchedGPUCoefficients != nil)
            || perTilePixels >= Self._gpuHTEntropyMultiTilePerTilePixelThreshold
        t0 = DispatchTime.now()
        let (decodedBlocks, gpuBatch) = try await applyEntropyDecoding(
            codeBlocks, metadata: tileMeta,
            isGPUPath: useGPUEntropy, isMultiTilePerTile: true,
            preBatchedGPUCoefficients: preBatchedGPUCoefficients)
        J2KDecodeTimings.recordEntropyDecoding(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        let dequantizedSubbands = try await applyDequantization(decodedBlocks, metadata: tileMeta)
        J2KDecodeTimings.recordDequantization(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)
        // v6.3.0 E1.2 — multi-tile per-tile IDWT routes to CPU. The
        // GPU IDWT kernels were designed for single-tile (canvas
        // origin 0, 0; tile dims = image dims) and produce wrong
        // pixels in the multi-tile per-tile context (parity-aware
        // boundary handling + tile-local fused-from-codeblocks
        // descriptors). Single-tile decode goes via
        // `decodeSingleTileGPU` (NOT this function) and keeps the
        // full GPU IDWT path. E1.3 (deferred): GPU IDWT multi-tile
        // support to recover the IDWT win.
        //
        // **v8.2 mg-corruption fix**: when `preBatchedGPUCoefficients`
        // is non-nil (the cross-tile batched-entropy caller), force
        // CPU IDWT explicitly rather than going through
        // `applyInverseWaveletTransformGPU`'s threshold-gated route.
        // The reason: with the pre-batched short-circuit, the slow-
        // lane returns `(coeffs, batch=nil)` — `gpuBatch` is `nil`,
        // so `applyInverseWaveletTransformGPU` skips its
        // `hasFusedFromCodeblocksPlan` CPU-fallback branch and runs
        // the GPU multi-tile per-tile IDWT, which silently corrupts
        // the bottom-tile bottom-row coefficients on certain
        // dimensions (smallest reproducer 1760×2392 split 2x2;
        // production reproducer mg DICOM 3520×4784).
        // v10.3 Phase 1A refinement (2026-05-15) — d117dcc shipped the
        // v8.2 routing-fix bypass as a global flag flip, which unlocked
        // the MG GPU IDWT win (-18 ms substitute) but ALSO regressed PX
        // (+11 ms) and DX (+17 ms) because their multi-tile 4x4 layouts
        // produce ~2 MP per tile, where CPU IDWT remains faster than
        // GPU IDWT.
        //
        // Substitute-driver A/B finding (post-d117dcc, this branch):
        //   - DX 4x4 tiles, ~2 MP each: CPU IDWT wins
        //   - MG 2x2 tiles, ~4.2 MP each: GPU IDWT wins
        // The trade-off flips at ~3 MP per tile. The predicate below
        // routes CPU IDWT for tiles below that threshold and GPU IDWT
        // above — capturing both modalities' wins simultaneously.
        //
        // The `_v82_disableIDWTRoutingFix` flag continues to override
        // the size gate when set true (forces GPU IDWT regardless of
        // tile size, used for diagnostic A/B).
        let tilePixels = tileMeta.width * tileMeta.height
        let useCPUIDWTForSmallTile = preBatchedGPUCoefficients != nil
            && !Self._v82_disableIDWTRoutingFix
            && tilePixels < 3_000_000
        t0 = DispatchTime.now()
        let spatialData: [[Double]]
        if useCPUIDWTForSmallTile {
            spatialData = try await applyInverseWaveletTransform(
                dequantizedSubbands, metadata: tileMeta,
                tileOriginX: tileX, tileOriginY: tileY)
        } else {
            spatialData = try await applyInverseWaveletTransformGPU(
                dequantizedSubbands, metadata: tileMeta,
                tileOriginX: tileX, tileOriginY: tileY,
                isMultiTilePerTile: true, gpuBatch: gpuBatch)
        }
        J2KDecodeTimings.recordInverseWaveletTransform(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        var tileRGB = try await applyInverseColorTransformGPU(spatialData, metadata: tileMeta)
        J2KDecodeTimings.recordInverseColorTransform(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

        t0 = DispatchTime.now()
        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < tileRGB.count else { break }
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                tileRGB[compIdx].withUnsafeMutableBufferPointer { buf in
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset, buf.baseAddress!, 1, vDSP_Length(buf.count))
                }
            }
        }
        J2KDecodeTimings.recordDcLevelUnshift(
            Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000)

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

    // MARK: - JP3D bridge SPI (v10.20-research Phase 1)
    //
    // Two new internal entry points that EXPOSE the pipeline split
    // between dequantization and inverse-wavelet-transform without
    // changing the production single-tile decode path. The composition
    //
    //     iDWTAndFinalizeCoefficients(decodeToCoefficients(data))
    //
    // is byte-identical to `decodeSingleTile(parseCodestream(data))`
    // on every single-tile codestream — which is what JP3D's slice-
    // stack codec emits for each Z-slice. The JP3D side then has the
    // freedom to:
    //
    //  • decode N slices to coefficients (Stage A — entropy + dequant)
    //  • submit ONE batched GPU iDWT dispatch across all N slices
    //  • finalize each slice (Stage C — colour + DC + reconstruct)
    //
    // which is the structural shape Phase 2 needs. Phase 1 ships only
    // the split — single-slice batched iDWT collapses to today's behaviour.

    /// JP3D bridge — internal Phase 1 helper. Runs the single-tile
    /// pipeline through Stage 4 (dequantization) and stops. Returns
    /// the dequantized subbands + the codestream metadata so the
    /// caller can later run iDWT + colour + DC + reconstruct via
    /// `iDWTAndFinalizeCoefficients`.
    ///
    /// Multi-tile is rejected — JP3D slices are always single-tile
    /// 2D J2K codestreams (per JP3DSliceStackCodec wire format).
    /// Routing a multi-tile codestream through this bridge would
    /// either need a per-tile-group decode or an explicit caller-
    /// side multi-tile orchestration, both of which are out of scope.
    mutating func decodeToCoefficients(
        _ data: Data
    ) async throws -> _JP3DSliceCoefficientsInternal {
        return try await decodeToCoefficients(data, options: .default)
    }

    /// v10.21-research — JP3D bridge SPI overload accepting options.
    /// `options.partialResolutionLevel` truncates entropy + iDWT to
    /// the target level (v10.5 Stage B); `options.regionOfInterest`
    /// engages the v10.6 ROI footprint-skip. The captured options
    /// ride along inside the returned payload so the matching
    /// finalize call sizes / crops the output without re-plumbing
    /// the same parameters.
    mutating func decodeToCoefficients(
        _ data: Data,
        options: JP3DBridgeOptions
    ) async throws -> _JP3DSliceCoefficientsInternal {
        // Honour caller-passed options by setting the corresponding
        // pipeline knobs (they may have been pre-set on `self` too —
        // bridge SPI sets both; per-slice serial paths set on `self`).
        if options.partialResolutionLevel != nil {
            partialResolutionLevel = options.partialResolutionLevel
        }
        if options.regionOfInterest != nil {
            regionOfInterest = options.regionOfInterest
        }
        let (metadata, tiles) = try parseCodestream(data)
        guard !metadata.isMultiTile else {
            throw J2KError.notImplemented(
                "JP3D bridge: decodeToCoefficients does not yet "
                + "support multi-tile codestreams (slice-stack slices "
                + "are always single-tile).")
        }
        let tileData = tiles.first?.tileData ?? Data()

        let codeBlocks = try extractTileData(
            tileData, metadata: metadata,
            maxResolutionLevel: partialResolutionLevel,
            regionOfInterest: regionOfInterest,
            maxQualityLayer: maxQualityLayer)

        let (decodedBlocks, _) = try await applyEntropyDecoding(
            codeBlocks, metadata: metadata)

        let dequantizedSubbands = try await applyDequantization(
            decodedBlocks, metadata: metadata)

        return _JP3DSliceCoefficientsInternal(
            metadata: metadata,
            dequantizedSubbands: dequantizedSubbands,
            options: options)
    }

    /// v10.20-research Phase 3b — JP3D batched bridge SPI. Takes a
    /// batch of N slice coefficient bundles (each previously produced
    /// by `decodeToCoefficients`) and runs ONE batched multi-level
    /// GPU iDWT across all N slices via
    /// `J2KMetalDWT.inverse2DInt32MultiLevelFusedBatched`, then
    /// finalises each slice into a `J2KImage`.
    ///
    /// **JP3D production-shape only**: requires 5/3 reversible filter,
    /// single-component slices (componentIndex 0 only), full-
    /// resolution decode (no `partialResolutionLevel`), uniform
    /// dimensions across the batch (JP3D slice-stack guarantees this).
    /// Any other shape falls back to per-slice serial via
    /// `iDWTAndFinalizeCoefficients` so the SPI never errors on the
    /// non-JP3D case — it just doesn't get the batched win.
    ///
    /// Bit-exact composition guarantee: for every slice `i`,
    ///     batched[i].components[0].data ==
    ///         iDWTAndFinalizeCoefficients(coefs[i]).components[0].data
    /// on every JP3D-shape input.
    mutating func iDWTAndFinalizeCoefficientsBatched(
        _ coefsBatch: [_JP3DSliceCoefficientsInternal]
    ) async throws -> [J2KImage] {
        guard !coefsBatch.isEmpty else { return [] }

        // v10.20-research Phase 3d — orchestrator integration. The
        // four-way diagnostic V10_20_BridgeInputsFourWayDiagnostic
        // proved that on the per-slice GPU-chain shape this method
        // builds, all four CPU/GPU 5/3 iDWT implementations
        // (batched orchestrator / serial GPU multi-level fused /
        // J2KMetalDWT per-level CPU / J2KDWT2DOptimizer multi-level
        // CPU) produce bit-exact identical output. So the previous
        // two integration attempts diverged not because the
        // orchestrator was wrong but because the chain construction
        // didn't match the per-slice raw-coefficient shape the
        // diagnostic uses. This integration mirrors the diagnostic
        // exactly — raw `.coefficients` for every band, no
        // `getSubbandAsInt32` rounding (which only fires for the
        // irreversible 9/7 path that JP3D doesn't use anyway since
        // dequantization sets `doubleCoefficients = nil` for 5/3).
        //
        // **Eligibility gate.** Only JP3D-production shapes route
        // through the batched path:
        //   • 5/3 reversible filter
        //   • single-component slices (`componentCount == 1`)
        //   • uniform dimensions across the batch
        //   • uniform options across the batch (partial-res K + ROI)
        //   • ≥ 1 effective iDWT level (K=0 thumbnail falls back —
        //     no iDWT to dispatch in the first place)
        // Anything else falls back to the per-slice serial loop —
        // same output, no batched win, never errors on a valid
        // bundle.

        let head = coefsBatch[0]
        let isReversible53: Bool = {
            if case .irreversible97 = head.metadata.configuration.waveletFilter {
                return false
            }
            return true
        }()
        let levels = head.metadata.configuration.decompositionLevels
        let headW = head.metadata.width
        let headH = head.metadata.height
        let headComponentCount = head.metadata.componentCount
        let headOptions = head.options

        // v10.21-research Phase 2 — compute effectiveLevels from
        // partial-resolution. K=N (or nil) → full chain; K ∈ [1, N-1]
        // → truncated chain; K=0 → no iDWT to dispatch.
        let effectiveLevels: Int = {
            if let k = headOptions.partialResolutionLevel {
                return max(0, min(k, levels))
            }
            return levels
        }()

        var batchable = isReversible53
            && headComponentCount == 1
            && levels >= 1
            && effectiveLevels >= 1

        if batchable {
            for slice in coefsBatch {
                if slice.metadata.width != headW
                    || slice.metadata.height != headH
                    || slice.metadata.componentCount != 1 {
                    batchable = false
                    break
                }
                if case .irreversible97 = slice.metadata.configuration.waveletFilter {
                    batchable = false
                    break
                }
                if slice.metadata.configuration.decompositionLevels != levels {
                    batchable = false
                    break
                }
                // v10.21 — uniform options requirement. JP3D slice-
                // stack guarantees the caller passes identical options
                // to every slice (decodeRegion / decodeResolution are
                // per-volume not per-slice), so this almost always
                // holds; the check is defensive.
                if slice.options != headOptions {
                    batchable = false
                    break
                }
            }
        }

        guard batchable else {
            var results: [J2KImage] = []
            results.reserveCapacity(coefsBatch.count)
            for coefs in coefsBatch {
                results.append(try await iDWTAndFinalizeCoefficients(coefs))
            }
            return results
        }

        // Build the per-slice GPU chain. Identical shape to what
        // V10_20_BridgeInputsFourWayDiagnostic builds — raw
        // `sb.coefficients`, padding via `padFlatInt32`, level chain
        // deepest-first, LL only at the deepest level (subsequent
        // levels rely on GPU-resident chain reuse).
        let subsX = head.metadata.components[0].subsamplingX
        let subsY = head.metadata.components[0].subsamplingY
        let compW = headW / subsX
        let compH = headH / subsY
        var levelSizes: [(width: Int, height: Int)] = []
        for d in 0...levels {
            let denom = 1 << d
            let bandX1 = EncoderPipeline.ceilDivIntegerOrigin(compW, denom)
            let bandY1 = EncoderPipeline.ceilDivIntegerOrigin(compH, denom)
            levelSizes.append((bandX1, bandY1))
        }

        let llDimsW = levelSizes[levels].width
        let llDimsH = levelSizes[levels].height

        // v10.21 — orchestrator output dims after `effectiveLevels`
        // iDWT steps. For K=N (or .default): output = full image.
        // For K<N: output = `levelSizes[N - K]` (the K-th level from
        // the deepest, mirroring the v10.5 Stage B.2 truncation).
        let outputLevel = levels - effectiveLevels
        let outputW = levelSizes[outputLevel].width
        let outputH = levelSizes[outputLevel].height

        var perSliceChains: [[J2KMetalDWTSubbandsInt32]] = []
        perSliceChains.reserveCapacity(coefsBatch.count)

        for slice in coefsBatch {
            let subs = slice.dequantizedSubbands.filter {
                $0.componentIndex == 0
            }

            // LL lookup: drop the `level ==` filter and match
            // `subband == .ll` only — the entropy stage stores LL
            // at `level: 0` in the HT 5/3 path, not at `level: levels`
            // (the only legacy helper that uses `level: levels` is
            // `buildLLSubbandsFromBuffer` which is no longer called).
            // The production serial path at line ~4245
            // (`compSubbands.first(where: { $0.subband == .ll })`)
            // works because there is always exactly ONE LL per
            // component regardless of which level field it carries.
            let initialLL: [Int32]
            if let ll = subs.first(where: { $0.subband == .ll }) {
                initialLL = padFlatInt32(
                    ll.coefficients, srcW: ll.width, srcH: ll.height,
                    dstW: llDimsW, dstH: llDimsH)
            } else {
                initialLL = [Int32](repeating: 0, count: llDimsW * llDimsH)
            }

            var chain: [J2KMetalDWTSubbandsInt32] = []
            chain.reserveCapacity(effectiveLevels)
            // v10.21 — only the deepest `effectiveLevels` levels run.
            // The chain stops at `outputLevel + 1`, mirroring how
            // `applyInverseWaveletTransform` truncates `levelSubbands53`
            // to `prefix(effectiveLevels)`.
            for level in ((outputLevel + 1)...levels).reversed() {
                let parentW = levelSizes[level - 1].width
                let parentH = levelSizes[level - 1].height
                let llW = levelSizes[level].width
                let llH = levelSizes[level].height
                let hlW = parentW - llW
                let lhH = parentH - llH

                func raw(_ band: J2KSubband, _ dstW: Int, _ dstH: Int) -> [Int32] {
                    if let sb = subs.first(where: { $0.level == level && $0.subband == band }) {
                        return padFlatInt32(sb.coefficients,
                                            srcW: sb.width, srcH: sb.height,
                                            dstW: dstW, dstH: dstH)
                    }
                    return [Int32](repeating: 0, count: dstW * dstH)
                }

                let llForLevel: [Int32] = chain.isEmpty ? initialLL : []
                chain.append(J2KMetalDWTSubbandsInt32(
                    ll: llForLevel,
                    lh: raw(.lh, llW, lhH),
                    hl: raw(.hl, hlW, llH),
                    hh: raw(.hh, hlW, lhH),
                    llWidth: llW, llHeight: llH,
                    originalWidth: parentW, originalHeight: parentH,
                    tileOriginX: 0, tileOriginY: 0))
            }
            perSliceChains.append(chain)
        }

        // ONE batched multi-level dispatch across all slices.
        let metalDWT = J2KMetalDWT(
            configuration: J2KMetalDWTConfiguration(
                filter: .reversible53, decompositionLevels: levels),
            device: metalSession?.device,
            bufferPool: metalSession?.bufferPool,
            shaderLibrary: metalSession?.shaderLibrary)
        try await metalDWT.initialize()
        let perSliceFlatInt32 = try await metalDWT.inverse2DInt32MultiLevelFusedBatched(
            perSliceSubbandsPerLevel: perSliceChains)

        // v10.21 — for partial-resolution we must set
        // `outputDimensions` so `reconstructImage` sizes the per-
        // slice J2KImage / J2KComponent at the truncated dims rather
        // than the metadata's full dims. ROI is post-iDWT crop.
        if headOptions.partialResolutionLevel != nil {
            outputDimensions = (width: outputW, height: outputH)
        }

        // Per-slice finalize: Int32 → Double → DC unshift → reconstruct.
        // Output is full-image (or reduced-dim for partial-res); ROI
        // crops at the end.
        var results: [J2KImage] = []
        results.reserveCapacity(coefsBatch.count)
        for (sIdx, slice) in coefsBatch.enumerated() {
            var spatialData: [[Double]] = [
                vDSPConvert.int32sToDoubles(perSliceFlatInt32[sIdx])
            ]
            // 1-component MCT is a no-op; call for parity with serial path.
            try applyInverseColorTransformInPlace(&spatialData,
                                                  metadata: slice.metadata)
            let compInfo = slice.metadata.components[0]
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                spatialData[0].withUnsafeMutableBufferPointer { buf in
                    #if canImport(Accelerate)
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset,
                                buf.baseAddress!, 1, vDSP_Length(buf.count))
                    #else
                    for i in 0..<buf.count { buf[i] += dcOffset }
                    #endif
                }
            }
            let image = try reconstructImage(spatialData,
                                             metadata: slice.metadata)
            if let roi = headOptions.regionOfInterest {
                results.append(try Self.cropImage(image, region: roi))
            } else {
                results.append(image)
            }
        }
        return results
    }

    /// JP3D bridge — companion to `decodeToCoefficients`. Takes the
    /// dequantized subbands previously produced by that method and
    /// runs Stage 5 (iDWT) + Stage 6 (inverse colour transform) +
    /// DC level unshift + Stage 7 (image reconstruction) to return
    /// the final J2KImage.
    ///
    /// Bit-exact composition guarantee: for a single-tile codestream
    /// `data`, the bytes of the returned image equal the bytes of
    /// the image produced by the public `decode(data)`.
    mutating func iDWTAndFinalizeCoefficients(
        _ coefs: _JP3DSliceCoefficientsInternal
    ) async throws -> J2KImage {
        let metadata = coefs.metadata

        // v10.21-research — honour captured options. For partial-
        // resolution we must set `partialResolutionLevel` AND
        // `outputDimensions` on this pipeline before `applyInverseWaveletTransform`
        // / `reconstructImage` run; the CPU iDWT path reads
        // `partialResolutionLevel` to truncate the chain, and
        // `reconstructImage` reads `outputDimensions` to size the
        // component buffers. ROI is post-iDWT crop (the iDWT itself
        // runs full-tile; finalize crops at the end), so just stash
        // the region for the post-step.
        if let level = coefs.options.partialResolutionLevel {
            partialResolutionLevel = level
            let N = metadata.configuration.decompositionLevels
            let halvings = max(0, N - max(0, min(level, N)))
            let factor = 1 << halvings
            let outW = (metadata.width + factor - 1) / factor
            let outH = (metadata.height + factor - 1) / factor
            outputDimensions = (width: outW, height: outH)
        }

        var spatialData = try await applyInverseWaveletTransform(
            coefs.dequantizedSubbands, metadata: metadata)

        try applyInverseColorTransformInPlace(&spatialData, metadata: metadata)
        var rgbData = spatialData

        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < rgbData.count else { break }
            if !compInfo.signed {
                var dcOffset = Double(1 << (compInfo.bitDepth - 1))
                rgbData[compIdx].withUnsafeMutableBufferPointer { buf in
                    #if canImport(Accelerate)
                    vDSP_vsaddD(buf.baseAddress!, 1, &dcOffset,
                                buf.baseAddress!, 1, vDSP_Length(buf.count))
                    #else
                    for i in 0..<buf.count { buf[i] += dcOffset }
                    #endif
                }
            }
        }

        let fullImage = try reconstructImage(rgbData, metadata: metadata)
        if let roi = coefs.options.regionOfInterest {
            return try Self.cropImage(fullImage, region: roi)
        }
        return fullImage
    }

    /// v10.21-research — per-component byte-level crop. Mirrors
    /// `J2KDecoder.extractRegion` (private in J2KAdvancedDecoding)
    /// so the JP3D bridge can produce region-sized images without
    /// reaching into a sibling file's private. 1-byte and 2-byte
    /// samples both supported; `sampleByteOrder` preserved.
    static func cropImage(_ image: J2KImage, region: J2KRegion) throws -> J2KImage {
        try region.validate(imageWidth: image.width, imageHeight: image.height)
        let cropped = image.components.map { component -> J2KComponent in
            let bytesPerSample = (component.bitDepth + 7) / 8
            let srcStride = component.width
            let dstRowBytes = region.width * bytesPerSample
            var dst = Data(count: region.height * dstRowBytes)
            component.data.withUnsafeBytes { srcRaw in
                dst.withUnsafeMutableBytes { dstRaw in
                    guard let src = srcRaw.baseAddress,
                          let out = dstRaw.baseAddress else { return }
                    for y in 0..<region.height {
                        let srcY = region.y + y
                        let srcOffset = (srcY * srcStride + region.x) * bytesPerSample
                        let dstOffset = y * dstRowBytes
                        memcpy(out + dstOffset, src + srcOffset, dstRowBytes)
                    }
                }
            }
            return J2KComponent(
                index: component.index, bitDepth: component.bitDepth,
                signed: component.signed,
                width: region.width, height: region.height,
                subsamplingX: component.subsamplingX,
                subsamplingY: component.subsamplingY,
                data: dst, sampleByteOrder: component.sampleByteOrder)
        }
        return J2KImage(
            width: region.width, height: region.height,
            components: cropped, colorSpace: image.colorSpace)
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
    /// Internal (was private through v7.0.0); promoted to allow
    /// v7.1.0 H1.0 Defect A diagnostic test to extract per-tile
    /// codeblock data. Not part of the public API surface.
    /// v10.5.0 Stage B.2 — peek metadata without committing to a
    /// full decode. Used by `J2KDecoder.decodePartialResolution` to
    /// compute the reduced output dimensions from the codestream's
    /// SIZ + COD markers before the decode runs.
    static func peekMetadata(_ data: Data) throws -> CodestreamMetadata {
        let pipeline = DecoderPipeline()
        let (metadata, _) = try pipeline.parseCodestream(data)
        return metadata
    }

    func parseCodestream(_ data: Data) throws -> (CodestreamMetadata, [(tileIndex: Int, tileData: Data)]) {
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

        // Per-resolution precinct sizes (Scod bit 0). v5.35.0d-decode:
        // ISO 15444-1 A.6.1 — one byte per resolution level (decompositionLevels + 1
        // entries); low nibble = width exponent, high nibble = height exponent.
        if (scod & 0x01) != 0 {
            var pps: [(widthExp: Int, heightExp: Int)] = []
            for _ in 0...config.decompositionLevels {
                let byte = try reader.readUInt8()
                let wExp = Int(byte & 0x0F)
                let hExp = Int((byte >> 4) & 0x0F)
                pps.append((widthExp: wExp, heightExp: hExp))
            }
            config.precinctExponents = pps
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
    ///
    /// Multi-precinct support (v5.35.0d-decode): when the codestream's COD
    /// marker specifies precinct sizes (Scod bit 0 = 1), each (resolution,
    /// component) emits one packet per precinct. Iterates the precinct
    /// grid in raster order; for each precinct, reads ONE packet whose
    /// tag trees cover only the blocks within that precinct's region.
    /// Default codestreams (one precinct per band) work as before.
    /// Internal (was private through v7.0.0); promoted to allow
    /// v7.1.0 H1.0 Defect A diagnostic test to inspect per-tile
    /// codeblock layout. Not part of the public API surface.
    func extractTileData(
        _ tileData: Data,
        metadata: CodestreamMetadata,
        // v6-alpha3 step 6B slice 4 — tile-component canvas-coord
        // origin used to canvas-anchor the code-block partition
        // per ISO/IEC 15444-1 B.7. Default (0, 0) preserves
        // single-tile and 32-aligned multi-tile decode bit-for-bit.
        tileOriginX: Int = 0,
        tileOriginY: Int = 0,
        // v10.5.0 Stage B.1 — partial-resolution decode filter.
        // When non-nil, code-blocks at decomposition levels outside
        // the kept range are dropped after parsing (their data bytes
        // are still consumed from the stream to keep the reader in
        // sync, but they don't enter the result array). Filter rule:
        //   keep iff (block.level == 0)           // LL (deepest)
        //         OR (block.level > N - r)        // details at deepest r levels
        // where N = metadata.configuration.decompositionLevels and
        // r = maxResolutionLevel ∈ [0, N]. nil = full decode.
        //
        // This saves the dominant entropy decode stage when the
        // caller wants a partial-resolution output. Stage B.2 will
        // also truncate the inverse DWT to skip iDWT levels.
        maxResolutionLevel: Int? = nil,
        // v10.6.0 ROI decode — region of interest in full-image pixel
        // coordinates. When non-nil, code-blocks whose inverse-DWT
        // spatial footprint (plus a conservative synthesis-filter
        // halo) does not overlap the region are dropped after parsing
        // — entropy decode is skipped for them, just like the B.1
        // resolution filter above. The LL band is always kept. Every
        // block influencing an in-region pixel is retained, so a full
        // decode + crop and an ROI decode + crop produce bit-identical
        // region pixels.
        regionOfInterest: J2KRegion? = nil,
        // v10.9.0 quality-layer decode — caps the multi-layer packet
        // decode at layers `0...maxQualityLayer`. nil = all layers.
        // Ignored for single-layer codestreams.
        maxQualityLayer: Int? = nil
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

        // Precinct size in BAND-LOCAL coords for a given resolution.
        // r=0 (LL): 2^PPx × 2^PPy. r > 0: 2^(PPx-1) × 2^(PPy-1).
        // Default (no precinct sizes in COD): 2^15 (effectively one
        // precinct covers the whole band).
        let precinctExps = metadata.configuration.precinctExponents
        func bandPrecinctSize(forRes res: Int) -> (w: Int, h: Int) {
            guard let exps = precinctExps, res < exps.count else {
                return (1 << 15, 1 << 15)
            }
            let pp = exps[res]
            let wExp = res == 0 ? pp.widthExp : max(0, pp.widthExp - 1)
            let hExp = res == 0 ? pp.heightExp : max(0, pp.heightExp - 1)
            return (1 << wExp, 1 << hExp)
        }

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

        // LRCP progression: layer × resolution × component × precinct.
        //
        // v10.9.0 — codestreams with more than one quality layer need
        // the layer-aware packet decode. The loop below handles the
        // single-layer case (the common path, byte-exact unchanged);
        // multi-layer codestreams route to `extractTileDataMultiLayer`.
        if metadata.configuration.qualityLayers > 1 {
            let mlBlocks = try extractTileDataMultiLayer(
                tileData, metadata: metadata,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                maxQualityLayer: maxQualityLayer)
            return applyPartialDecodeFilters(
                mlBlocks, levels: levels,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                maxResolutionLevel: maxResolutionLevel, regionOfInterest: regionOfInterest)
        }

        // Single-layer packet decode — precincts iterated in raster
        // order per (resolution, component).
        for resLevel in 0...levels {
            for compIdx in 0..<numComponents {
                let subbands: [J2KSubband] = resLevel == 0 ? [.ll] : [.hl, .lh, .hh]

                // Determine the precinct grid extent at this resolution.
                // For r > 0, all sub-bands HL/LH/HH share the same grid;
                // use one of them as a reference. For r = 0, the LL band's
                // dimensions define the grid.
                let referenceSubband: J2KSubband = resLevel == 0 ? .ll : .hl
                let (sbWRef, sbHRef) = Self.subbandDimensions(
                    tileWidth: tileWidth, tileHeight: tileHeight,
                    tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                    levels: levels, resLevel: resLevel, subband: referenceSubband)
                guard sbWRef > 0 && sbHRef > 0 else { continue }

                let (pw, ph) = bandPrecinctSize(forRes: resLevel)
                let numPrecinctsX = max(1, (sbWRef + pw - 1) / pw)
                let numPrecinctsY = max(1, (sbHRef + ph - 1) / ph)

                for py in 0..<numPrecinctsY {
                    for px in 0..<numPrecinctsX {
                        guard reader.bytesRemaining > 0 || reader.bitOffset > 0 else { break }
                        let notEmpty = try reader.readBit()
                        guard notEmpty else {
                            try reader.alignToByte()
                            continue
                        }

                        var pendingBlocks: [PendingBlock] = []

                        for subband in subbands {
                            let (sbWidth, sbHeight) = Self.subbandDimensions(
                                tileWidth: tileWidth, tileHeight: tileHeight,
                                tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                                levels: levels, resLevel: resLevel, subband: subband)
                            guard sbWidth > 0 && sbHeight > 0 else { continue }

                            // v6-alpha3 step 6B slice 4 — canvas-anchored
                            // code-block partition per ISO/IEC 15444-1 B.7.
                            // Mirror of the encoder's step-6A canvas-anchored
                            // grid in `applyEntropyCodingHTJ2KFused`. For
                            // tile origin (0, 0) the formulas reduce to the
                            // legacy tile-relative grid; single-tile and
                            // 32-aligned multi-tile decode are byte-identical.
                            let (tbx0, tby0) = Self.subbandCanvasOrigin(
                                tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                                levels: levels, resLevel: resLevel, subband: subband)

                            // Precinct region intersected with the tile band.
                            // Default precinct (2^15 × 2^15) covers the whole
                            // band, so px/py are always 0 in that case and
                            // pStartX/pStartY are 0. For non-default precincts
                            // this preserves the precinct-anchored sub-region
                            // while the inner block grid is canvas-anchored.
                            let pStartX = px * pw
                            let pStartY = py * ph
                            let pEndX = min(pStartX + pw, sbWidth)
                            let pEndY = min(pStartY + ph, sbHeight)
                            guard pEndX > pStartX, pEndY > pStartY else { continue }

                            // Canvas-anchored cell range intersecting this
                            // precinct's tile-band region [tbx0+pStartX,
                            // tbx0+pEndX) × [tby0+pStartY, tby0+pEndY).
                            let firstCanvasX = (tbx0 + pStartX) / cbWidth
                            let firstCanvasY = (tby0 + pStartY) / cbHeight
                            let lastCanvasX  = (tbx0 + pEndX + cbWidth  - 1) / cbWidth
                            let lastCanvasY  = (tby0 + pEndY + cbHeight - 1) / cbHeight
                            let pBlocksX = lastCanvasX - firstCanvasX
                            let pBlocksY = lastCanvasY - firstCanvasY
                            let pBlockCount = pBlocksX * pBlocksY

                            let bandKey: String
                            if subband == .ll {
                                bandKey = "LL_0"
                            } else {
                                bandKey = "\(subband.rawValue)_\(resLevel)"
                            }
                            let kb = metadata.bandKbValues[bandKey] ?? (metadata.components[compIdx].bitDepth + metadata.quantizationGuardBits)
                            let decomLevel = resLevel == 0 ? 0 : (levels - resLevel + 1)

                            // Per-precinct tag trees (fresh for each
                            // packet — the standard's "tag tree per
                            // precinct" model).
                            var inclusionTree = J2KTagTree(width: pBlocksX, height: pBlocksY)
                            var zbpTree = J2KTagTree(width: pBlocksX, height: pBlocksY)

                            for localLeafIdx in 0..<pBlockCount {
                                let included = try inclusionTree.decode(
                                    reader: &reader, leafIndex: localLeafIdx, threshold: 1)
                                guard included else { continue }

                                var zbp: Int32 = 0
                                while !(try zbpTree.decode(
                                    reader: &reader, leafIndex: localLeafIdx, threshold: zbp + 1)) {
                                    zbp += 1
                                    if zbp > 100 { break }
                                }

                                let passes = try Self.decodeCodingPasses(&reader)
                                let length = try Self.decodeDataLength(&reader, numPasses: passes)

                                let localY = localLeafIdx / pBlocksX
                                let localX = localLeafIdx % pBlocksX

                                // Canvas position of this block in band-canvas
                                // coords, then clipped to tile-band-relative
                                // [pStartX, pEndX) × [pStartY, pEndY).
                                let canvasStartX = (firstCanvasX + localX) * cbWidth
                                let canvasEndX   = canvasStartX + cbWidth
                                let canvasStartY = (firstCanvasY + localY) * cbHeight
                                let canvasEndY   = canvasStartY + cbHeight
                                // Tile-band-relative coordinates the dequant /
                                // IDWT scatter expects (matches encoder's
                                // PendingCodeBlock.originX/originY).
                                let tileStartX = max(pStartX, canvasStartX - tbx0)
                                let tileEndX   = min(pEndX,   canvasEndX   - tbx0)
                                let tileStartY = max(pStartY, canvasStartY - tby0)
                                let tileEndY   = min(pEndY,   canvasEndY   - tby0)
                                let actualW    = tileEndX - tileStartX
                                let actualH    = tileEndY - tileStartY

                                pendingBlocks.append(PendingBlock(
                                    componentIndex: compIdx,
                                    decomLevel: decomLevel,
                                    subband: subband,
                                    x: tileStartX, y: tileStartY,
                                    width: actualW, height: actualH,
                                    passCount: passes,
                                    zeroBitPlanes: Int(zbp),
                                    bandKb: kb,
                                    dataLength: length))
                            }
                        }

                        try reader.alignToByte()
                        reader.setByteStuffing(false)

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
                                bandKb: pb.bandKb))
                        }
                        reader.setByteStuffing(true)
                    }
                }
            }
        }

        return applyPartialDecodeFilters(
            blocks, levels: levels,
            tileOriginX: tileOriginX, tileOriginY: tileOriginY,
            maxResolutionLevel: maxResolutionLevel, regionOfInterest: regionOfInterest)
    }

    /// Applies the v10.5.0 Stage B.1 partial-resolution code-block
    /// filter and the v10.6.0 ROI spatial filter. Factored out of
    /// `extractTileData` so the single-layer and multi-layer packet
    /// decode paths share one implementation.
    private func applyPartialDecodeFilters(
        _ blocks: [CodeBlockInfo], levels: Int,
        tileOriginX: Int, tileOriginY: Int,
        maxResolutionLevel: Int?, regionOfInterest: J2KRegion?
    ) -> [CodeBlockInfo] {
        var blocks = blocks

        // v10.5.0 Stage B.1 — partial-resolution filter. Keep blocks
        // where level == 0 (the LL, always needed) OR level > N - r
        // (detail bands at the deepest r levels).
        if let r = maxResolutionLevel {
            let keepThreshold = levels - r
            blocks = blocks.filter { block in
                block.level == 0 || block.level > keepThreshold
            }
        }

        // v10.6.0 ROI decode — spatial code-block filter. A code-block
        // at decomposition depth d holds band samples that upsample to
        // full-image pixels at scale 2^d; its image-space footprint is
        // the band rect scaled by 2^d, anchored at the tile origin,
        // expanded by a conservative 8·2^d synthesis-filter halo. A
        // block is kept iff that footprint overlaps the region.
        if let roi = regionOfInterest {
            let haloFactor = 8
            blocks = blocks.filter { block in
                if block.level == 0 { return true }
                let d = block.level
                let scale = 1 << d
                let halo = haloFactor << d
                let fpX0 = tileOriginX + block.x * scale - halo
                let fpX1 = tileOriginX + (block.x + block.width) * scale + halo
                let fpY0 = tileOriginY + block.y * scale - halo
                let fpY1 = tileOriginY + (block.y + block.height) * scale + halo
                let overlapsX = fpX0 < (roi.x + roi.width) && fpX1 > roi.x
                let overlapsY = fpY0 < (roi.y + roi.height) && fpY1 > roi.y
                return overlapsX && overlapsY
            }
        }

        return blocks
    }

    /// v10.9.0 — multi-layer (LRCP) packet decode per ISO/IEC 15444-1
    /// B.10. The single-layer `extractTileData` loop reads one packet
    /// per `(resolution, component, precinct)`; a codestream with
    /// `qualityLayers > 1` emits `layer × resolution × component ×
    /// precinct` packets, with each code-block's coding passes
    /// distributed across the layers it contributes to.
    ///
    /// This routine adds the layer loop, persists the per-precinct
    /// inclusion / zero-bit-plane tag-trees and the per-block `Lblock`
    /// state across layers, and accumulates each block's passes and
    /// data into a single `CodeBlockInfo`. When `maxQualityLayer` is
    /// set, only layers `0...maxQualityLayer` are processed — the
    /// basis for `decodeQuality`.
    private func extractTileDataMultiLayer(
        _ tileData: Data, metadata: CodestreamMetadata,
        tileOriginX: Int, tileOriginY: Int,
        maxQualityLayer: Int?
    ) throws -> [CodeBlockInfo] {
        let cbWidth = metadata.configuration.codeBlockSize.width
        let cbHeight = metadata.configuration.codeBlockSize.height
        let levels = metadata.configuration.decompositionLevels
        let tileWidth = metadata.tileSize.width
        let tileHeight = metadata.tileSize.height
        let numComponents = metadata.components.count
        let totalLayers = max(1, metadata.configuration.qualityLayers)
        let lastLayer = min(maxQualityLayer ?? (totalLayers - 1), totalLayers - 1)

        var reader = J2KBitReader(data: tileData)
        reader.setByteStuffing(true)

        let precinctExps = metadata.configuration.precinctExponents
        func bandPrecinctSize(forRes res: Int) -> (w: Int, h: Int) {
            guard let exps = precinctExps, res < exps.count else {
                return (1 << 15, 1 << 15)
            }
            let pp = exps[res]
            let wExp = res == 0 ? pp.widthExp : max(0, pp.widthExp - 1)
            let hExp = res == 0 ? pp.heightExp : max(0, pp.heightExp - 1)
            return (1 << wExp, 1 << hExp)
        }

        struct PrecinctKey: Hashable {
            let res: Int, comp: Int, subband: J2KSubband, py: Int, px: Int
        }
        struct BlockAccum {
            var included = false
            var lblock = 3
            var zeroBitPlanes = 0
            var passCount = 0
            var data = Data()
            var componentIndex = 0
            var decomLevel = 0
            var subband: J2KSubband = .ll
            var x = 0, y = 0, width = 0, height = 0
            var bandKb = 0
            var emitOrder = 0
        }

        var inclusionTrees: [PrecinctKey: J2KTagTree] = [:]
        var zbpTrees: [PrecinctKey: J2KTagTree] = [:]
        var blockAccums: [PrecinctKey: [BlockAccum]] = [:]
        var emitCounter = 0

        for layer in 0...lastLayer {
            for resLevel in 0...levels {
                for compIdx in 0..<numComponents {
                    let subbands: [J2KSubband] = resLevel == 0 ? [.ll] : [.hl, .lh, .hh]
                    let referenceSubband: J2KSubband = resLevel == 0 ? .ll : .hl
                    let (sbWRef, sbHRef) = Self.subbandDimensions(
                        tileWidth: tileWidth, tileHeight: tileHeight,
                        tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                        levels: levels, resLevel: resLevel, subband: referenceSubband)
                    guard sbWRef > 0 && sbHRef > 0 else { continue }
                    let (pw, ph) = bandPrecinctSize(forRes: resLevel)
                    let numPrecinctsX = max(1, (sbWRef + pw - 1) / pw)
                    let numPrecinctsY = max(1, (sbHRef + ph - 1) / ph)

                    for py in 0..<numPrecinctsY {
                        for px in 0..<numPrecinctsX {
                            guard reader.bytesRemaining > 0 || reader.bitOffset > 0 else { break }
                            let notEmpty = try reader.readBit()
                            guard notEmpty else {
                                try reader.alignToByte()
                                continue
                            }

                            // Blocks that contribute data in THIS
                            // packet, in header order — the packet
                            // body is read in the same order.
                            var layerContrib: [(pkey: PrecinctKey, leaf: Int, length: Int)] = []

                            for subband in subbands {
                                let (sbWidth, sbHeight) = Self.subbandDimensions(
                                    tileWidth: tileWidth, tileHeight: tileHeight,
                                    tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                                    levels: levels, resLevel: resLevel, subband: subband)
                                guard sbWidth > 0 && sbHeight > 0 else { continue }
                                let (tbx0, tby0) = Self.subbandCanvasOrigin(
                                    tileOriginX: tileOriginX, tileOriginY: tileOriginY,
                                    levels: levels, resLevel: resLevel, subband: subband)
                                let pStartX = px * pw
                                let pStartY = py * ph
                                let pEndX = min(pStartX + pw, sbWidth)
                                let pEndY = min(pStartY + ph, sbHeight)
                                guard pEndX > pStartX, pEndY > pStartY else { continue }
                                let firstCanvasX = (tbx0 + pStartX) / cbWidth
                                let firstCanvasY = (tby0 + pStartY) / cbHeight
                                let lastCanvasX  = (tbx0 + pEndX + cbWidth  - 1) / cbWidth
                                let lastCanvasY  = (tby0 + pEndY + cbHeight - 1) / cbHeight
                                let pBlocksX = lastCanvasX - firstCanvasX
                                let pBlocksY = lastCanvasY - firstCanvasY
                                let pBlockCount = pBlocksX * pBlocksY
                                guard pBlockCount > 0 else { continue }

                                let bandKey = subband == .ll
                                    ? "LL_0" : "\(subband.rawValue)_\(resLevel)"
                                let kb = metadata.bandKbValues[bandKey]
                                    ?? (metadata.components[compIdx].bitDepth + metadata.quantizationGuardBits)
                                let decomLevel = resLevel == 0 ? 0 : (levels - resLevel + 1)

                                let pkey = PrecinctKey(
                                    res: resLevel, comp: compIdx, subband: subband, py: py, px: px)
                                var accums = blockAccums[pkey]
                                    ?? Array(repeating: BlockAccum(), count: pBlockCount)
                                var incTree = inclusionTrees[pkey]
                                    ?? J2KTagTree(width: pBlocksX, height: pBlocksY)
                                var zbpTree = zbpTrees[pkey]
                                    ?? J2KTagTree(width: pBlocksX, height: pBlocksY)

                                for leaf in 0..<pBlockCount {
                                    var accum = accums[leaf]
                                    if !accum.included {
                                        let inc = try incTree.decode(
                                            reader: &reader, leafIndex: leaf,
                                            threshold: Int32(layer + 1))
                                        if !inc {
                                            accums[leaf] = accum
                                            continue
                                        }
                                        accum.included = true
                                        var zbp: Int32 = 0
                                        while !(try zbpTree.decode(
                                            reader: &reader, leafIndex: leaf, threshold: zbp + 1)) {
                                            zbp += 1
                                            if zbp > 100 { break }
                                        }
                                        accum.zeroBitPlanes = Int(zbp)
                                        // Block geometry — computed once.
                                        let localY = leaf / pBlocksX
                                        let localX = leaf % pBlocksX
                                        let canvasStartX = (firstCanvasX + localX) * cbWidth
                                        let canvasStartY = (firstCanvasY + localY) * cbHeight
                                        let tileStartX = max(pStartX, canvasStartX - tbx0)
                                        let tileEndX   = min(pEndX, canvasStartX + cbWidth - tbx0)
                                        let tileStartY = max(pStartY, canvasStartY - tby0)
                                        let tileEndY   = min(pEndY, canvasStartY + cbHeight - tby0)
                                        accum.componentIndex = compIdx
                                        accum.decomLevel = decomLevel
                                        accum.subband = subband
                                        accum.x = tileStartX
                                        accum.y = tileStartY
                                        accum.width = tileEndX - tileStartX
                                        accum.height = tileEndY - tileStartY
                                        accum.bandKb = kb
                                        accum.emitOrder = emitCounter
                                        emitCounter += 1
                                    } else {
                                        // Already included — one bit signals
                                        // whether it contributes this layer.
                                        let contributes = try reader.readBit()
                                        if !contributes {
                                            accums[leaf] = accum
                                            continue
                                        }
                                    }
                                    let passes = try Self.decodeCodingPasses(&reader)
                                    while try reader.readBit() { accum.lblock += 1 }
                                    let passLog = passes > 1 ? Int(log2(Double(passes))) : 0
                                    let length = Int(try reader.readBits(accum.lblock + passLog))
                                    accum.passCount += passes
                                    accums[leaf] = accum
                                    layerContrib.append((pkey, leaf, length))
                                }

                                inclusionTrees[pkey] = incTree
                                zbpTrees[pkey] = zbpTree
                                blockAccums[pkey] = accums
                            }

                            // Packet body — code-block data bytes, header order.
                            try reader.alignToByte()
                            reader.setByteStuffing(false)
                            for contrib in layerContrib {
                                let d = try reader.readBytes(contrib.length)
                                if var accums = blockAccums[contrib.pkey] {
                                    accums[contrib.leaf].data.append(d)
                                    blockAccums[contrib.pkey] = accums
                                }
                            }
                            reader.setByteStuffing(true)
                        }
                    }
                }
            }
        }

        // Emit one CodeBlockInfo per included block, first-inclusion order.
        var included: [BlockAccum] = []
        for accums in blockAccums.values {
            for a in accums where a.included { included.append(a) }
        }
        included.sort { $0.emitOrder < $1.emitOrder }
        return included.map { a in
            CodeBlockInfo(
                componentIndex: a.componentIndex, level: a.decomLevel, subband: a.subband,
                x: a.x, y: a.y, width: a.width, height: a.height,
                data: a.data, passCount: a.passCount,
                zeroBitPlanes: a.zeroBitPlanes, bandKb: a.bandKb)
        }
    }

    /// Computes subband dimensions for a given resolution level and subband type.
    ///
    /// v6-alpha3 step 6B slice 4 — accepts `tileOriginX/Y` (default
    /// 0) and computes spec-correct band sizes per ISO/IEC 15444-1
    /// Eq. B-15 when origin is non-zero. For origin (0, 0) the
    /// formula reduces to the legacy recursive `(w + 1) / 2`
    /// outputs — single-tile and 32-aligned multi-tile decode are
    /// byte-identical.
    ///
    /// Eq. B-15:
    ///   tbx0 = ceil((tcx0 - x_offset_b) / 2^d)
    ///   tbx1 = ceil((tcx1 - x_offset_b) / 2^d)
    ///   bandW = tbx1 - tbx0
    /// where (x_offset_b, y_offset_b) is (0, 0) for LL, (2^(d-1), 0)
    /// for HL, (0, 2^(d-1)) for LH, (2^(d-1), 2^(d-1)) for HH; and
    /// d is the decomposition depth (= `levels` for LL, = `levels -
    /// resLevel + 1` for HL/LH/HH at resolution `resLevel`).
    private static func subbandDimensions(
        tileWidth: Int, tileHeight: Int,
        tileOriginX: Int = 0, tileOriginY: Int = 0,
        levels: Int, resLevel: Int, subband: J2KSubband
    ) -> (width: Int, height: Int) {
        let d: Int
        if resLevel == 0 {
            d = levels   // LL at deepest decomposition level
        } else {
            d = levels - resLevel + 1
        }
        let denom = 1 << d
        let half  = d >= 1 ? (1 << (d - 1)) : 0
        let xOff: Int
        let yOff: Int
        switch subband {
        case .ll: xOff = 0;    yOff = 0
        case .hl: xOff = half; yOff = 0
        case .lh: xOff = 0;    yOff = half
        case .hh: xOff = half; yOff = half
        }
        let tcx0 = tileOriginX
        let tcy0 = tileOriginY
        let tcx1 = tileOriginX + tileWidth
        let tcy1 = tileOriginY + tileHeight
        let tbx0 = EncoderPipeline.ceilDivIntegerOrigin(tcx0 - xOff, denom)
        let tby0 = EncoderPipeline.ceilDivIntegerOrigin(tcy0 - yOff, denom)
        let tbx1 = EncoderPipeline.ceilDivIntegerOrigin(tcx1 - xOff, denom)
        let tby1 = EncoderPipeline.ceilDivIntegerOrigin(tcy1 - yOff, denom)
        return (tbx1 - tbx0, tby1 - tby0)
    }

    /// v6-alpha3 step 6B slice 4 — band canvas-coord origin per
    /// ISO/IEC 15444-1 Eq. B-15. Used by `extractTileData` to
    /// canvas-anchor the code-block partition (mirror of the
    /// encoder's step-6A canvas-anchored grid).
    private static func subbandCanvasOrigin(
        tileOriginX: Int, tileOriginY: Int,
        levels: Int, resLevel: Int, subband: J2KSubband
    ) -> (x: Int, y: Int) {
        let d: Int
        if resLevel == 0 {
            d = levels
        } else {
            d = levels - resLevel + 1
        }
        let denom = 1 << d
        let half  = d >= 1 ? (1 << (d - 1)) : 0
        let xOff: Int
        let yOff: Int
        switch subband {
        case .ll: xOff = 0;    yOff = 0
        case .hl: xOff = half; yOff = 0
        case .lh: xOff = 0;    yOff = half
        case .hh: xOff = half; yOff = half
        }
        return (
            EncoderPipeline.ceilDivIntegerOrigin(tileOriginX - xOff, denom),
            EncoderPipeline.ceilDivIntegerOrigin(tileOriginY - yOff, denom)
        )
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
    /// Internal (was private through v7.0.0); promoted to allow
    /// v7.1.0 H1.1 Defect A diagnostic test to compare per-tile
    /// `[SubbandInfo]` output between GPU-entropy and CPU-entropy
    /// paths. Not part of the public API surface.
    ///
    /// v7.1.0 H1.1 — `isMultiTilePerTile` parameter added to suppress
    /// the v5.9 zero-copy fast-lane (line ~1902) when the caller is
    /// `decodeTilePayloadGPU` and the downstream IDWT is forced to
    /// CPU per E1.2 (`isMultiTilePerTile: true`). The fast-lane
    /// returns `([], batch)` assuming a downstream GPU IDWT will
    /// consume `batch` via `inverse2DInt32FullFusedFromCodeblocks`;
    /// when CPU IDWT runs instead, the empty `[SubbandInfo]`
    /// produces zero coefficients → zero spatial output → DC
    /// unshift adds +32 768 = exactly the Defect A pixel diff.
    /// Suppressing the fast-lane forces the slow-lane regroup,
    /// which populates `[SubbandInfo]` correctly for CPU IDWT.
    func applyEntropyDecoding(
        _ blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata,
        // v6.2.0 D4 — `true` only when the caller is on the GPU
        // pipeline path (decodeSingleTileGPU / decodeTilePayloadGPU).
        // Constrains the `_gpuHTEntropyEnabled` static-flag-driven
        // GPU HT entropy decode so it doesn't fire on CPU pipeline
        // paths where the regroup downstream can't consume the
        // GPU-decoded output. CPU `decodeWithGPUHT(_:)` callers
        // still get GPU HT entropy via the `useGPUHT` instance var
        // independent of this parameter — the OR-with-flag at the
        // consume sites is the load-bearing gate.
        isGPUPath: Bool = false,
        // v7.1.0 H1.1 — set true by `decodeTilePayloadGPU` for every
        // tile in a multi-tile decode. Suppresses the v5.9 zero-copy
        // fast-lane (line ~1902) which assumes a downstream GPU IDWT
        // will consume `batch` via `inverse2DInt32FullFusedFromCodeblocks`.
        // For multi-tile per-tile decode, E1.2 forces CPU IDWT
        // (`applyInverseWaveletTransformGPU` falls back when
        // `isMultiTilePerTile: true`); the fast-lane's empty
        // `[SubbandInfo]` would produce zero coefficients → DC
        // unshift adds +32 768 to all pixels = exactly the Defect A
        // observed diff. Suppressing the fast-lane forces the slow-
        // lane regroup, which populates `[SubbandInfo]` correctly
        // for CPU IDWT consumption.
        isMultiTilePerTile: Bool = false,
        // v7.2.0 Phase E — pre-batched GPU HT entropy results.
        // When non-nil, the function skips its own per-tile GPU
        // dispatch (the `gpuEarly` block) and instead consumes the
        // supplied `[blockIdxWithinThisTile: [Int32]]` as if it had
        // performed the dispatch itself. Used by
        // `decodeMultiTileGPUBatched` to amortize the per-tile
        // MTLCommandBuffer overhead across all tiles in one CB.
        // The returned `batch: J2KGPUHTBatch?` is always nil on this
        // path — the caller is responsible for the IDWT routing
        // (multi-tile per-tile uses CPU IDWT, no batch needed).
        preBatchedGPUCoefficients: [Int: [Int32]]? = nil
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
        // v8 Phase 1 — also gate on `_gpuInverse53Enabled` BEFORE
        // calling `J2KMetalDWT.isAvailable`. When --no-gpu is set
        // via the CLI (or the env var/flag is otherwise off), GPU
        // IDWT can never run, so this whole probe is wasted —
        // worse, calling `J2KMetalDWT.isAvailable` here costs
        // ~50 ms cold the first time Metal is touched per process.
        // On small/medium CLI invocations this was the dominant
        // overhead.
        let idwtWillBeGPU =
            Self._gpuInverse53Enabled &&
            pixelCount >= 256 * 256 &&
            dwtLevels >= 1 &&
            metadata.configuration.waveletKernelConfiguration == nil &&
            J2KMetalDWT.isAvailable
        if idwtWillBeGPU,
           // v7.1.0 H1.1 — must be false for multi-tile per-tile.
           // The fast-lane returns ([], batch) and assumes the IDWT
           // will consume batch via the GPU fused path. E1.2 forces
           // CPU IDWT for multi-tile per-tile, which then receives
           // empty subbands → 32 768 pixel diff (Defect A). See
           // applyEntropyDecoding signature comment + #335 H1.0/H1.1.
           !isMultiTilePerTile,
           !isIrreversible, useHT, useConformant,
           // v6.2.0 D4: static flag only fires on GPU pipeline path
           (useGPUHT || (isGPUPath && Self._gpuHTEntropyEnabled)),
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
            // v7.2.0 Phase E — pre-batched coefficients short-circuit.
            // The caller (`decodeMultiTileGPUBatched`) already ran one
            // big GPU dispatch for all tiles and is feeding this tile's
            // slice in via `preBatchedGPUCoefficients`. Skip our own
            // dispatch entirely and use the supplied dict.
            if let pre = preBatchedGPUCoefficients {
                return (pre, nil)
            }
            // v6.2.0 D4: static flag only fires on GPU pipeline path
            guard (useGPUHT || (isGPUPath && Self._gpuHTEntropyEnabled)),
                  useHT, useConformant,
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

            // v5.8 fused path: 5/3 lossless via Int32 fused IDWT.
            // v5.26.0: 9/7 lossy via Float fused IDWT (scatter+dequant
            // baked into a Float scatter kernel; CPU dequant skipped
            // downstream by `applyDequantization` when the batch
            // carries `floatPlansByComponent`).
            if let session = metalSession {
                let fusedT0 = DispatchTime.now()
                let fusedRes = try await J2KGPUHTDispatch.decodeBatchGPUResident(
                    blocks: gpuInputs, session: session)
                let fusedDt = Double(DispatchTime.now().uptimeNanoseconds - fusedT0.uptimeNanoseconds) / 1_000_000_000
                J2KDecodeTimings.recordGPUHTDispatch(fusedDt)
                if let res = fusedRes {
                    var remappedCoeffs: [Int: [Int32]] = [:]
                    var remappedOffsets: [Int: Int] = [:]
                    for (gpuIdx, coeffs) in res.decodedBlockCoefficients {
                        remappedCoeffs[inputOriginalIndices[gpuIdx]] = coeffs
                    }
                    for (gpuIdx, offset) in res.decodedBlockOutputOffsets {
                        remappedOffsets[inputOriginalIndices[gpuIdx]] = offset
                    }
                    if res.cpuFallbackIndices.isEmpty {
                        let batch: J2KGPUHTBatch
                        if isIrreversibleFilter {
                            batch = buildGPUHTBatchFromResultFloat(
                                codeblockBuffer: res.codeblockBuffer,
                                outputSampleCount: res.outputSampleCount,
                                decodedBlockOutputOffsets: remappedOffsets,
                                blocks: blocks, metadata: metadata,
                                bufferPool: session.bufferPool)
                        } else {
                            batch = buildGPUHTBatchFromResult(
                                codeblockBuffer: res.codeblockBuffer,
                                outputSampleCount: res.outputSampleCount,
                                decodedBlockOutputOffsets: remappedOffsets,
                                blocks: blocks, metadata: metadata,
                                bufferPool: session.bufferPool)
                        }
                        return (remappedCoeffs, batch)
                    }
                    await session.bufferPool.returnBuffer(res.codeblockBuffer)
                    return (remappedCoeffs, nil)
                }
            }

            // v5.6.0 path (no session, or 9/7 lossy, or fused
            // dispatcher returned nil).
            let dispatchT0 = DispatchTime.now()
            let result = try await J2KGPUHTDispatch.decodeBatch(
                blocks: gpuInputs, session: metalSession)
            let dispatchDt = Double(DispatchTime.now().uptimeNanoseconds - dispatchT0.uptimeNanoseconds) / 1_000_000_000
            J2KDecodeTimings.recordGPUHTDispatch(dispatchDt)
            var dict: [Int: [Int32]] = [:]
            for (i, gpuInputIdx) in result.decodedBlockIndices.enumerated() {
                dict[inputOriginalIndices[gpuInputIdx]] = result.results[i].coefficients
            }
            return (dict, nil)
        }()
        let gpuPreDecoded: [Int: [Int32]] = gpuEarly.preDecoded
        let gpuBatch: J2KGPUHTBatch? = gpuEarly.batch

        // v5.27.0 short-circuit: when the Float fused batch is built
        // (9/7 lossy on session-warm path; all blocks GPU-decoded;
        // dequant baked into the scatter kernel), the downstream IDWT
        // consumes the codeblock buffer directly via
        // `inverse2DFullFusedFromCodeblocks`. The CPU regroup that
        // follows would build `[SubbandInfo]` only for the dead-code
        // case where the IDWT falls back to per-level upload — and
        // that fallback never fires when `floatPlansByComponent` is
        // populated (the IDWT routes to the fused path first). Skip
        // the regroup entirely; return empty `[SubbandInfo]`. The
        // downstream `applyDequantization` becomes a no-op (empty
        // input → empty output), saving the CPU dequant work too
        // (which was already wasted, since the GPU scatter applied
        // dequant). Net savings on dx_002 (2800×2288): ~5 ms (regroup
        // ~1 ms + dequant ~4 ms).
        if let batch = gpuBatch, batch.floatPlansByComponent != nil {
            return ([], batch)
        }

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
        let zcT0 = DispatchTime.now()
        let zcRes = try await J2KGPUHTDispatch.decodeBatchGPUResident(
            blocks: gpuInputs, session: session,
            includePerBlockCoefficients: false)
        let zcDt = Double(DispatchTime.now().uptimeNanoseconds - zcT0.uptimeNanoseconds) / 1_000_000_000
        J2KDecodeTimings.recordGPUHTDispatch(zcDt)
        guard let result = zcRes else { return nil }
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
            floatPlansByComponent: nil,
            bufferPool: bufferPool)
    }

    /// v5.26.0 Float counterpart of `buildGPUHTBatchFromResult` for
    /// the 9/7 lossy fused-from-codeblocks path. Identical descriptor
    /// layout per block; additional `stepSize` per descriptor is
    /// looked up via the same QCD-key convention `applyDequantization`
    /// uses, with the HTJ2K `stepSize` (no ×0.5 EBCOT compensation —
    /// HTJ2K coefficients are at natural scale).
    private func buildGPUHTBatchFromResultFloat(
        codeblockBuffer: any MTLBuffer,
        outputSampleCount: Int,
        decodedBlockOutputOffsets: [Int: Int],
        blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata,
        bufferPool: J2KMetalBufferPool
    ) -> J2KGPUHTBatch {
        let levels = metadata.configuration.decompositionLevels
        var floatPlans: [Int: [J2KMetalDWT.LevelScatterPlanFloat]] = [:]
        let maxComponent = max(
            metadata.componentCount - 1,
            blocks.map { $0.componentIndex }.max() ?? 0)
        let quantSteps = metadata.quantizationSteps

        for compIdx in 0...maxComponent {
            let compW = metadata.width / max(metadata.components[compIdx].subsamplingX, 1)
            let compH = metadata.height / max(metadata.components[compIdx].subsamplingY, 1)
            var levelSizes: [(width: Int, height: Int)] = [(compW, compH)]
            for _ in 0..<levels {
                let (pw, ph) = levelSizes.last!
                levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))
            }

            var levelPlans: [J2KMetalDWT.LevelScatterPlanFloat] = []
            for level in (1...levels).reversed() {
                let parentW = levelSizes[level - 1].width
                let parentH = levelSizes[level - 1].height
                let llW = levelSizes[level].width
                let llH = levelSizes[level].height
                let hlW = parentW - llW
                let lhH = parentH - llH

                var descs: [J2KMetalSubbandScatterDescriptorFloat] = []
                var maxBlockW = 0
                var maxBlockH = 0
                for (i, block) in blocks.enumerated() {
                    guard block.componentIndex == compIdx,
                          let outputOffset = decodedBlockOutputOffsets[i]
                    else { continue }
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
                    // Same key convention as applyDequantization:
                    // LL is "LL_0"; detail subbands use resolution
                    // numbering (resLevel = NL - decomLevel + 1).
                    let key: String
                    if block.subband == .ll {
                        key = "LL_0"
                    } else {
                        let resLevel = levels - level + 1
                        key = "\(block.subband.rawValue)_\(resLevel)"
                    }
                    let stepSize = Float(quantSteps[key] ?? 1.0)
                    descs.append(J2KMetalSubbandScatterDescriptorFloat(
                        codeblockOffset: UInt32(outputOffset),
                        blockWidth: UInt32(block.width),
                        blockHeight: UInt32(block.height),
                        subbandX: UInt32(block.x),
                        subbandY: UInt32(block.y),
                        subbandStride: UInt32(stride),
                        targetSubband: target,
                        stepSize: stepSize))
                    maxBlockW = max(maxBlockW, block.width)
                    maxBlockH = max(maxBlockH, block.height)
                }

                levelPlans.append(J2KMetalDWT.LevelScatterPlanFloat(
                    scatterDescriptors: descs,
                    llWidth: llW, llHeight: llH,
                    lhWidth: llW, lhHeight: lhH,
                    hlWidth: hlW, hlHeight: llH,
                    hhWidth: hlW, hhHeight: lhH,
                    originalWidth: parentW, originalHeight: parentH,
                    maxBlockWidth: max(maxBlockW, 1),
                    maxBlockHeight: max(maxBlockH, 1)))
            }
            floatPlans[compIdx] = levelPlans
        }

        return J2KGPUHTBatch(
            codeblockBuffer: codeblockBuffer,
            outputSampleCount: outputSampleCount,
            plansByComponent: [:],
            floatPlansByComponent: floatPlans,
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
        metadata: CodestreamMetadata,
        // v6-alpha3 step 6B slice 3 — tile-component canvas-coord
        // origin for the parity-aware inverse 5/3 DWT. Default
        // (0, 0) preserves single-tile and 32-aligned multi-tile
        // decode byte-for-byte.
        tileOriginX: Int = 0,
        tileOriginY: Int = 0
    ) async throws -> [[Double]] {
        let filter = metadata.configuration.waveletFilter
        let levels = metadata.configuration.decompositionLevels

        // v10.5.0 Stage B.2 — partial-resolution iDWT truncation.
        // When `partialResolutionLevel = r` is set (in [0, levels]),
        // only the deepest `r` iDWT steps run. The `levelSubbands53`
        // array (built later, deepest-first) is truncated to the
        // first `r` elements before being passed to the iDWT, so
        // the inverse transform stops after producing the LL at
        // decomposition level (N - r). For r = 0, no iDWT runs;
        // the function returns the deepest LL directly.
        let effectiveLevels: Int = {
            if let r = partialResolutionLevel {
                return min(max(r, 0), levels)
            }
            return levels
        }()

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

            // Compute expected subband dimensions at each decomposition level.
            //
            // v6-alpha3 step 6B slice 3 — for non-zero tile-component
            // canvas origin, use the spec formula per ISO/IEC 15444-1
            // Eq. B-15:
            //   LL_d width  = ceil((tcx0 + compW) / 2^d) - ceil(tcx0 / 2^d)
            //   LL_d height = ceil((tcy0 + compH) / 2^d) - ceil(tcy0 / 2^d)
            // For origin (0, 0) this reduces to ceil(compW / 2^d), which
            // is what the recursive `(pw + 1) / 2` gives — single-tile
            // and 32-aligned multi-tile decode are byte-identical.
            let compW = metadata.width / metadata.components[compIdx].subsamplingX
            let compH = metadata.height / metadata.components[compIdx].subsamplingY
            let tcx0 = tileOriginX / metadata.components[compIdx].subsamplingX
            let tcy0 = tileOriginY / metadata.components[compIdx].subsamplingY
            var levelSizes: [(width: Int, height: Int)] = []
            for d in 0...levels {
                let denom = 1 << d
                let bandX0 = EncoderPipeline.ceilDivIntegerOrigin(tcx0, denom)
                let bandX1 = EncoderPipeline.ceilDivIntegerOrigin(tcx0 + compW, denom)
                let bandY0 = EncoderPipeline.ceilDivIntegerOrigin(tcy0, denom)
                let bandY1 = EncoderPipeline.ceilDivIntegerOrigin(tcy0 + compH, denom)
                levelSizes.append((bandX1 - bandX0, bandY1 - bandY0))
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
                    // v6-alpha3 step 6B slice 3 — pass tile-component
                    // canvas origin into the parity-aware multi-level
                    // inverse so non-32-aligned multi-tile codestreams
                    // self-decode correctly. For origin (0, 0) the
                    // overload routes to the existing optimised
                    // flat-buffer fast path — byte-identical, zero-cost.
                    //
                    // v10.5.0 Stage B.2 — when partial-resolution decode
                    // is active, truncate the subbands array to the
                    // deepest `effectiveLevels` entries. The iDWT does
                    // exactly N steps for N subband elements; passing
                    // fewer elements stops the inverse transform at the
                    // corresponding decomposition level, producing
                    // reduced-dimension LL output directly. For
                    // effectiveLevels == 0, the iDWT short-circuits and
                    // returns the deepest LL unchanged.
                    let truncatedSubbands = (effectiveLevels < levelSubbands53.count)
                        ? Array(levelSubbands53.prefix(effectiveLevels))
                        : levelSubbands53
                    let result = try await optimizer.inverseTransformMultiLevel53(
                        ll: llFlat, llW: expectedLLW, llH: expectedLLH,
                        subbands: truncatedSubbands,
                        tileOriginX: tcx0, tileOriginY: tcy0
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
        // v6.3.0 E1.2 — tile-component canvas-coord origin. Non-zero
        // origin signals a non-first tile in a multi-tile codestream;
        // forwarded to the CPU IDWT fallback (which is parity-aware).
        tileOriginX: Int = 0,
        tileOriginY: Int = 0,
        // v6.3.0 E1.2 — set true by `decodeTilePayloadGPU` for every
        // tile in a multi-tile decode (including the (0, 0) origin
        // first tile). Forces the CPU IDWT path regardless of
        // origin; see in-function comment for the rationale.
        isMultiTilePerTile: Bool = false,
        gpuBatch: J2KGPUHTBatch? = nil
    ) async throws -> [[Double]] {
        // Fall back to CPU for custom wavelet kernels only
        if metadata.configuration.waveletKernelConfiguration != nil {
            return try await applyInverseWaveletTransform(
                subbands, metadata: metadata,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY)
        }

        let levels = metadata.configuration.decompositionLevels
        guard levels >= 1 else {
            return try await applyInverseWaveletTransform(
                subbands, metadata: metadata,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY)
        }

        // Fall back to CPU when Metal GPU is not available (e.g. Linux, CI servers)
        guard J2KMetalDWT.isAvailable else {
            return try await applyInverseWaveletTransform(
                subbands, metadata: metadata,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY)
        }

        // Fall back to CPU for small images where GPU dispatch overhead exceeds compute benefit.
        let pixelCount = metadata.width * metadata.height
        guard pixelCount >= 256 * 256 else {
            return try await applyInverseWaveletTransform(
                subbands, metadata: metadata,
                tileOriginX: tileOriginX, tileOriginY: tileOriginY)
        }

        // v6.3.0 E1.2 → v7.1.0 H3: multi-tile per-tile fallback.
        // The original gate (E1.2) forced CPU IDWT for ALL tiles in
        // multi-tile decode because the GPU 5/3 kernels lacked
        // parity-aware boundary lifting (Defect B). H2 (#346) shipped
        // parity-aware odd-origin kernels; H2.2 (#348) wired them
        // into `J2KMetalDWT.inverse2DInt32`. H3 (this PR) flows the
        // tile origin through to the multi-level dispatch so the
        // GPU IDWT can handle non-zero origin tiles.
        //
        // The fall-back to CPU still fires for paths that don't yet
        // have origin awareness:
        //   - 9/7 irreversible (no parity-aware Float kernels yet)
        //   - The fused-from-codeblocks path when a `gpuBatch` is
        //     present (the scatter expects image-global descriptors;
        //     covering this needs separate work)
        // Single-tile decode goes via `decodeSingleTileGPU` (not
        // `decodeTilePayloadGPU`) and takes the full GPU IDWT path
        // unchanged — preserves the v6.2.0 +37–46 % single-tile win.
        if isMultiTilePerTile {
            let isReversible: Bool
            if case .irreversible97 = metadata.configuration.waveletFilter {
                isReversible = false
            } else {
                isReversible = true
            }
            // Path that runs `inverse2DInt32FullFusedFromCodeblocks`
            // — the GPU scatter has image-global assumptions. Routing
            // this to CPU IDWT until that path gains origin awareness.
            let hasFusedFromCodeblocksPlan = gpuBatch?.plansByComponent.isEmpty == false
                || (gpuBatch?.floatPlansByComponent?.isEmpty == false)
            // v7.1.1 hotfix — per-tile pixel threshold. v7.1.0 H3
            // shipped without this gate; DX 4x4 (16 tiles × 400 K
            // px each) regressed 2.14× vs v7.0.0 CPU IDWT because
            // the per-tile GPU dispatch overhead × 16 tiles
            // dominated. Below ~1 MP per tile, fall back to CPU.
            let perTilePixelCount = metadata.width * metadata.height
            let belowPerTileThreshold =
                perTilePixelCount < Self._gpuInverse53MultiTilePerTilePixelThreshold
            if !isReversible || hasFusedFromCodeblocksPlan || belowPerTileThreshold {
                return try await applyInverseWaveletTransform(
                    subbands, metadata: metadata,
                    tileOriginX: tileOriginX, tileOriginY: tileOriginY)
            }
            // Fall through: the 5/3 reversible non-fused path with
            // ≥ 1 MP/tile runs through the GPU multi-level-fused /
            // per-level dispatch with origin awareness via
            // subbands.tileOriginX/Y.
        }

        // v5.21.0: GPU 9/7 IDWT scaling fix removes the v5.20.0 gate.
        // Pre-v5.21 the GPU 9/7 forward and inverse kernels both used
        // inverted scaling (lowpass *= K, highpass /= K) vs the
        // ISO/IEC 15444-1 Annex F.4.1.1 spec convention (lowpass /= K,
        // highpass *= K). The GPU kernels were SELF-CONSISTENT but
        // could not interoperate with CPU-encoded codestreams (which
        // produce spec-compliant output). Result: when the CPU
        // encoded an image and the GPU decoded it, lowpass came out
        // 1/K² ≈ 0.66× too small and highpass K² ≈ 1.51× too large,
        // producing the ~19k LSB error v5.20.0 caught and gated.
        // v5.21.0 swaps the GPU scaling lines (in J2KShaders.metal AND
        // the embedded J2KMetalShaderLibrary kernelSource fallback)
        // to spec-compliant direction. The v5.20.0 regression test
        // (testBisectDecodePaths) now asserts max-diff = 0 with the
        // gate removed, proving the kernel fix is correct.

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
            // v5.27.0: include Float plans alongside Int32 plans —
            // when 9/7 lossy fused-from-codeblocks fires, the
            // Int32 `plansByComponent` is empty but
            // `floatPlansByComponent` carries the live plan, so the
            // fast-out must not zero-fill in that case.
            let hasGPUBatchPlan =
                gpuBatch?.plansByComponent[compIdx] != nil
                || (gpuBatch?.floatPlansByComponent?[compIdx]?.isEmpty == false)
            if compSubbands.isEmpty && !hasGPUBatchPlan {
                componentData.append([Double](repeating: 0.0, count: metadata.width * metadata.height))
                continue
            }

            // Compute expected subband dimensions at each level.
            //
            // **v8.3 fix**: use the canvas-anchored ISO/IEC 15444-1
            // Eq. B-15 spec formula (`bandX1 - bandX0`), matching
            // the CPU path's `applyInverseWaveletTransform`. The
            // previous naive `(pw + 1) / 2` recursion produced
            // wrong dimensions on tiles whose canvas origin made
            // an intermediate-depth band partition ODD-aligned
            // (e.g. tile (0, 1) of 1760×2392 split 2x2: tcx0=880,
            // depth 5 → naive recursion gives LL width 28, but the
            // encoder produces width 27 per spec). Result was
            // 100 % corruption of tiles with non-zero canvas X
            // origin. CPU IDWT used the spec formula already.
            let compW = metadata.width / metadata.components[compIdx].subsamplingX
            let compH = metadata.height / metadata.components[compIdx].subsamplingY
            let tcx0 = tileOriginX / metadata.components[compIdx].subsamplingX
            let tcy0 = tileOriginY / metadata.components[compIdx].subsamplingY
            var levelSizes: [(width: Int, height: Int)] = []
            for d in 0...levels {
                let denom = 1 << d
                let bandX0 = EncoderPipeline.ceilDivIntegerOrigin(tcx0, denom)
                let bandX1 = EncoderPipeline.ceilDivIntegerOrigin(tcx0 + compW, denom)
                let bandY0 = EncoderPipeline.ceilDivIntegerOrigin(tcy0, denom)
                let bandY1 = EncoderPipeline.ceilDivIntegerOrigin(tcy0 + compH, denom)
                levelSizes.append((bandX1 - bandX0, bandY1 - bandY0))
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
                } else if (useGPUHT || Self._gpuHTEntropyEnabled), metalSession != nil {
                    // v7.1.0 H3: per-level OUTPUT canvas origin —
                    // determines parity for the inverse 5/3 lifting
                    // at each decomposition level. tcx0/tcy0 are the
                    // tile-component canvas origins; output of level
                    // `k` lives at depth (k-1) where origin is
                    // ceil(tcx0 / 2^(k-1)) per ISO 15444-1 Eq. B-15.
                    let tcx0 = tileOriginX / metadata.components[compIdx].subsamplingX
                    let tcy0 = tileOriginY / metadata.components[compIdx].subsamplingY
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
                        // Output of inverse at level `k` lives at
                        // depth (k-1) on the canvas.
                        let outputDepth = level - 1
                        let denom = 1 << outputDepth
                        let outOriginX = EncoderPipeline.ceilDivIntegerOrigin(tcx0, denom)
                        let outOriginY = EncoderPipeline.ceilDivIntegerOrigin(tcy0, denom)
                        subbandsPerLevel.append(J2KMetalDWTSubbandsInt32(
                            ll: llForThisLevel, lh: lhInt, hl: hlInt, hh: hhInt,
                            llWidth: llW, llHeight: llH,
                            originalWidth: parentW, originalHeight: parentH,
                            tileOriginX: outOriginX, tileOriginY: outOriginY))
                    }
                    currentLL = try await metalDWT.inverse2DInt32MultiLevelFused(
                        subbandsPerLevel: subbandsPerLevel)
                } else {
                    // v7.1.0 H3: per-level path also threads
                    // tile-component origin → output origin via
                    // ceilDiv for parity-aware lifting selection.
                    let tcx0 = tileOriginX / metadata.components[compIdx].subsamplingX
                    let tcy0 = tileOriginY / metadata.components[compIdx].subsamplingY
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

                        let outputDepth = level - 1
                        let denom = 1 << outputDepth
                        let outOriginX = EncoderPipeline.ceilDivIntegerOrigin(tcx0, denom)
                        let outOriginY = EncoderPipeline.ceilDivIntegerOrigin(tcy0, denom)
                        let subbandData = J2KMetalDWTSubbandsInt32(
                            ll: currentLL, lh: lhInt, hl: hlInt, hh: hhInt,
                            llWidth: llW, llHeight: llH,
                            originalWidth: parentW, originalHeight: parentH,
                            tileOriginX: outOriginX, tileOriginY: outOriginY
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
                let initialLL: [Float]
                if let ll = llSubband {
                    if let dc = ll.doubleCoefficients {
                        initialLL = padFlatFloat(vDSPConvert.doublesToFloats(dc), srcW: ll.width, srcH: ll.height,
                                                  dstW: expectedLLW, dstH: expectedLLH)
                    } else {
                        initialLL = padFlatFloat(vDSPConvert.int32sToFloats(ll.coefficients), srcW: ll.width, srcH: ll.height,
                                                  dstW: expectedLLW, dstH: expectedLLH)
                    }
                } else {
                    initialLL = [Float](repeating: 0, count: expectedLLW * expectedLLH)
                }

                let currentLL: [Float]
                if let batch = gpuBatch,
                   let floatPlans = batch.floatPlansByComponent?[compIdx] {
                    // v5.26.0 Float fused-from-codeblocks: scatter +
                    // dequant + multi-level IDWT in one cb, sourcing
                    // LH/HL/HH from the GPU-resident codeblock buffer.
                    // No per-level CPU upload of subbands; dequant
                    // baked into the scatter kernel (HTJ2K conformant
                    // cleanup-only formula `(coeff ± 0.5) * stepSize`).
                    currentLL = try await metalDWT.inverse2DFullFusedFromCodeblocks(
                        codeblockBuffer: batch.codeblockBuffer,
                        levelsPlan: floatPlans,
                        initialLL: nil)
                } else if metalSession != nil {
                    // v5.25.0 multi-level Float fused: chains all levels
                    // into one cb, single readback at the outermost
                    // level. Closes the per-level upload/readback that
                    // the per-level `inverse2D(...)` path pays. CPU
                    // still uploads LH/HL/HH per level (Float scatter
                    // from a GPU-resident codeblock buffer is the next
                    // increment after this).
                    var subbandsPerLevel: [J2KMetalDWTSubbands] = []
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

                        let llForThisLevel: [Float] =
                            subbandsPerLevel.isEmpty ? initialLL : []
                        subbandsPerLevel.append(J2KMetalDWTSubbands(
                            ll: llForThisLevel, lh: lhFloat, hl: hlFloat, hh: hhFloat,
                            llWidth: llW, llHeight: llH,
                            originalWidth: parentW, originalHeight: parentH))
                    }
                    currentLL = try await metalDWT.inverse2DMultiLevelFused(
                        subbandsPerLevel: subbandsPerLevel)
                } else {
                    var rolling: [Float] = initialLL
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
                            ll: rolling, lh: lhFloat, hl: hlFloat, hh: hhFloat,
                            llWidth: llW, llHeight: llH,
                            originalWidth: parentW, originalHeight: parentH
                        )

                        rolling = try await metalDWT.inverse2D(subbands: subbandData, backend: .auto)
                    }
                    currentLL = rolling
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

        // v10.5.0 Stage B.2 — substitute outputDimensions for
        // metadata.width × height when partial-resolution decode is
        // active. The truncated iDWT has already produced reduced-
        // dimension component data; the J2KImage and its components
        // must carry the reduced dimensions to stay consistent.
        let effectiveWidth = outputDimensions?.width ?? metadata.width
        let effectiveHeight = outputDimensions?.height ?? metadata.height

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
            let width = effectiveWidth / compInfo.subsamplingX
            let height = effectiveHeight / compInfo.subsamplingY
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
            width: effectiveWidth,
            height: effectiveHeight,
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
