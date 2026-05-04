//
// J2KCodec.swift
// J2KSwift
//
/// # J2KCodec
///
/// Codec module for JPEG 2000 encoding and decoding.
///
/// This module provides the core encoding and decoding functionality for JPEG 2000 images,
/// including support for various compression modes and quality settings.
///
/// ## Topics
///
/// ### Encoding
/// - ``J2KEncoder``
///
/// ### Decoding
/// - ``J2KDecoder``

import Foundation
import J2KCore

/// Encodes images to JPEG 2000 format.
///
/// `J2KEncoder` provides a high-level API for encoding images to JPEG 2000 codestreams.
/// It connects all encoding components — colour transform, wavelet transform, quantization,
/// entropy coding, and rate control — into a complete encoding pipeline.
///
/// ## Basic Usage
///
/// ```swift
/// let encoder = J2KEncoder()
/// let image = J2KImage(width: 256, height: 256, components: 3, bitDepth: 8)
/// let data = try encoder.encode(image)
/// ```
///
/// ## Custom Configuration
///
/// ```swift
/// let config = J2KEncodingPreset.quality.configuration(quality: 0.95)
/// let encoder = J2KEncoder(encodingConfiguration: config)
/// let data = try encoder.encode(image)
/// ```
///
/// ## Progress Reporting
///
/// ```swift
/// let data = try encoder.encode(image) { update in
///     print("\(update.stage): \(Int(update.overallProgress * 100))%")
/// }
/// ```
public struct J2KEncoder: Sendable {
    /// The configuration to use for encoding.
    public let configuration: J2KConfiguration

    /// The detailed encoding configuration.
    public let encodingConfiguration: J2KEncodingConfiguration

    /// Creates a new encoder with the specified configuration.
    ///
    /// - Parameter configuration: The encoding configuration.
    public init(configuration: J2KConfiguration = J2KConfiguration()) {
        self.configuration = configuration
        self.encodingConfiguration = J2KEncodingConfiguration(
            quality: configuration.quality,
            lossless: configuration.lossless
        )
    }

    /// Creates a new encoder with a detailed encoding configuration.
    ///
    /// - Parameter encodingConfiguration: The detailed encoding configuration.
    public init(encodingConfiguration: J2KEncodingConfiguration) {
        self.configuration = J2KConfiguration(
            quality: encodingConfiguration.quality,
            lossless: encodingConfiguration.lossless
        )
        self.encodingConfiguration = encodingConfiguration
    }

    /// Encodes an image to JPEG 2000 format.
    ///
    /// This method processes the image through the complete JPEG 2000 encoding pipeline:
    /// 1. Preprocessing and input validation
    /// 2. Colour transform (RCT for lossless, ICT for lossy)
    /// 3. Multi-level wavelet transform
    /// 4. Quantization
    /// 5. EBCOT entropy coding
    /// 6. Rate control and layer formation
    /// 7. Codestream generation
    ///
    /// - Parameter image: The image to encode. Must have valid dimensions and components.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the image is invalid.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    public func encode(_ image: J2KImage) async throws -> Data {
        // v5.19.0 — `.constantBitrateViaQstep` runs an outer loop that
        // binary-searches qstep until achieved bpp matches target.
        // Bypasses PCRD-opt entirely; each iteration uses `.fixedQstep`.
        //
        // v5.32.0 note: explicit `.constantBitrateViaQstep` users
        // opted in for quality, so the bounded-rate refinement is
        // disabled here (`maxOvershootRatio: .infinity`). They get
        // v5.31.0 behaviour (no overshoot cap, max-quality). The
        // auto-promote `.constantBitrate` path below uses a 2.0×
        // bound to keep rate predictable for callers who didn't ask
        // for the qstep route.
        if case .constantBitrateViaQstep(let bpp, let tol, let maxIter) = encodingConfiguration.bitrateMode {
            let (data, _) = try await encodeViaQstepSearch(
                image,
                targetBpp: bpp,
                tolerance: tol,
                maxIterations: maxIter,
                maxOvershootRatio: .infinity)
            return data
        }

        // v5.31.0 — auto-promote `.constantBitrate` → Qstep-search
        // for HT-conformant lossy when the image bit-depth is ≥ 12
        // (medical workloads). PCRD-opt selects entire blocks at
        // once on conformant cleanup-only (single-pass, no mid-block
        // truncation), so block-level include/exclude decisions
        // become discrete and produce wildly scale-dependent quality
        // on high-bit-depth content (13–43 dB across the medical
        // corpus at 2 bpp). Qstep-search uses uniform quantisation
        // tuned to the byte target and produces consistent quality
        // across scale (~45–65 dB on the same corpus). This is the
        // correct λ formulation for this block format on
        // high-bit-depth content.
        //
        // The `≥ 12` gate avoids changing 8-bit (typically RGB
        // photographic) content where:
        //   1. PCRD-opt's block selection works fine — coefficient
        //      magnitudes are smaller, so cross-block R-D ranking
        //      doesn't collapse.
        //   2. The Qstep-search 8-iteration loop noticeably slows
        //      encoding, which matters for interactive workflows.
        //
        // Callers can opt out at any bit-depth by configuring
        // `.constantBitrateViaQstep` explicitly (no behaviour change
        // for them), `.fixedQstep` for strict-rate guarantees, or by
        // using a non-conformant HT block format / EBCOT / lossless
        // mode.
        let maxBitDepth = image.components.map { $0.bitDepth }.max() ?? 8
        if case .constantBitrate(let bpp) = encodingConfiguration.bitrateMode,
           encodingConfiguration.useHTJ2K,
           encodingConfiguration.htj2kBlockFormat == .conformant,
           !encodingConfiguration.lossless,
           !encodingConfiguration.useReversibleFilter,
           maxBitDepth >= 12 {
            let (data, _) = try await encodeViaQstepSearch(
                image, targetBpp: bpp, tolerance: 0.05, maxIterations: 8)
            return data
        }

        let pipeline = EncoderPipeline(config: encodingConfiguration)
        return try await pipeline.encode(image)
    }

    /// Encode with `.constantBitrateViaQstep` and return both the
    /// encoded data and diagnostic stats about the search loop.
    /// Useful for batch workflows to measure cache-hit rate, average
    /// iterations per encode, etc.
    ///
    /// The encoder configuration MUST have
    /// `bitrateMode == .constantBitrateViaQstep(...)` for this to be
    /// meaningful — other modes throw `J2KError.invalidParameter`.
    public func encodeWithQstepStats(_ image: J2KImage)
        async throws -> (data: Data, stats: J2KEncodeQstepStats)
    {
        guard case .constantBitrateViaQstep(let bpp, let tol, let maxIter) = encodingConfiguration.bitrateMode else {
            throw J2KError.invalidParameter(
                "encodeWithQstepStats requires .constantBitrateViaQstep mode")
        }
        return try await encodeViaQstepSearch(
            image,
            targetBpp: bpp,
            tolerance: tol,
            maxIterations: maxIter,
            maxOvershootRatio: .infinity)
    }

    /// Binary search on qstep until achieved bpp matches `targetBpp`
    /// within `tolerance`.
    ///
    /// v5.19.1 improvements over v5.19.0:
    /// 1. **Probe-based refinement**: the first iteration acts as a
    ///    probe — its result is used to scale the initial guess
    ///    (multiplicatively in log space) before binary search begins.
    ///    Empirical bpp/qstep relationship is content-dependent
    ///    (see V5_19_1_CALIBRATION.md), so a single probe outperforms
    ///    any static calibration table for non-typical content.
    /// 2. **Tighter initial bracket**: starts at [guess/16, guess*16]
    ///    instead of v5.19.0's [guess/64, guess*64]. Saves ~1
    ///    iteration on average.
    /// 3. **Cache lookup**: if a `J2KQstepCache` was set on the encoder
    ///    config, query it first using (bitDepth, components, target).
    ///    On cache hit, the cached qstep replaces the calibration
    ///    guess. After convergence, the result is stored back.
    /// 4. **Early-exit on bracket narrowing**: if [lower, upper] ratio
    ///    falls below 1.05 AND we've done ≥3 iterations, return the
    ///    closest achieved (within reach of tolerance, no point in
    ///    further narrowing).
    private func encodeViaQstepSearch(
        _ image: J2KImage,
        targetBpp: Double,
        tolerance: Double,
        maxIterations: Int,
        maxOvershootRatio: Double = 2.0
    ) async throws -> (Data, J2KEncodeQstepStats) {
        let totalSamples = image.width * image.height * image.componentCount
        guard totalSamples > 0 else {
            throw J2KError.invalidParameter("image has zero pixel area")
        }
        let targetBytes = Double(totalSamples) * targetBpp / 8.0
        let bitDepth = image.components.first?.bitDepth ?? 8
        let componentCount = image.components.count

        // 1. Initial guess: cache > calibration table.
        let cacheKey = J2KQstepCache.Key(
            bitDepth: bitDepth,
            componentCount: componentCount,
            targetBpp: targetBpp)
        let cachedGuess = await encodingConfiguration.qstepCache?.lookup(cacheKey)
        let cacheHit = cachedGuess != nil
        let initialQstep = cachedGuess ?? Self.initialQstepGuess(
            targetBpp: targetBpp, bitDepth: bitDepth)
        var qstep = initialQstep

        // 2. Tighter initial bracket. v5.19.0 used 64×; halve the log
        //    span. Probe-refinement below adapts further.
        var lower = qstep / 16.0
        var upper = qstep * 16.0

        var bestEncoded: Data = Data()
        var bestRatioErr = Double.infinity
        var bestQstep = qstep
        var iterationCount = 0

        while iterationCount < max(1, maxIterations) {
            iterationCount += 1
            // Encode with current qstep candidate.
            var iterConfig = encodingConfiguration
            iterConfig.bitrateMode = .fixedQstep(qstep: qstep)
            iterConfig.lossless = false
            let pipeline = EncoderPipeline(config: iterConfig)
            let encoded = try await pipeline.encode(image)
            let achievedBytes = Double(encoded.count)
            let ratio = achievedBytes / targetBytes
            let ratioErr = abs(ratio - 1.0)
            if ratioErr < bestRatioErr {
                bestRatioErr = ratioErr
                bestEncoded = encoded
                bestQstep = qstep
            }
            if ratioErr < tolerance {
                // Cache the successful qstep for future similar images.
                await encodingConfiguration.qstepCache?.store(cacheKey, qstep: qstep)
                let stats = J2KEncodeQstepStats(
                    iterations: iterationCount,
                    initialQstep: initialQstep,
                    convergedQstep: qstep,
                    achievedBpp: Double(encoded.count * 8) / Double(totalSamples),
                    targetBpp: targetBpp,
                    cacheHit: cacheHit,
                    convergedWithinTolerance: true)
                return (encoded, stats)
            }

            // 3. After the first iteration acts as a probe, scale the
            //    qstep based on observed bytes-vs-target ratio. This is
            //    the v5.19.1 probe-based refinement: works in log space
            //    so multiplicative errors compose. Past empirical data:
            //    bpp ≈ k * qstep^-α with α∈[0.13, 1.03] depending on
            //    bit-depth and content. Using α=1.0 as a first-order
            //    correction; the residual error is what subsequent
            //    binary-search steps clean up.
            if iterationCount == 1 {
                // Refine: multiply qstep by the achieved/target ratio.
                // Higher achieved bytes → need higher qstep (coarser
                // quantization → smaller output).
                let scaleHint = ratio
                let refined = qstep * scaleHint
                // Clamp to within an order of magnitude of the
                // calibration prior (avoids runaway on outliers).
                let priorGuess = Self.initialQstepGuess(
                    targetBpp: targetBpp, bitDepth: bitDepth)
                qstep = max(priorGuess / 32, min(priorGuess * 32, refined))
                // v5.31.0 — widen the bracket when iter-1 ratio is
                // far from 1.0. The previous fixed `±8×` bracket was
                // too narrow for HT-conformant high-bitdepth content
                // (16-bit medical) where the bytes-vs-qstep curve is
                // very flat; iter-2..8 converge to upper-cap without
                // hitting target. Scale the upper bracket by the
                // observed ratio so we always have headroom to grow.
                let bracketFactor = max(8.0, abs(log2(scaleHint)) * 8.0)
                lower = qstep / bracketFactor
                upper = qstep * bracketFactor
                continue
            }

            // 4. Standard log-binary-search narrowing for iter ≥ 2.
            //    v5.31.0 — extend the upper bound dynamically when
            //    the search keeps hitting the ceiling (bytes still
            //    over target at qstep ≈ upper). Without this, very-
            //    flat curves produce a terminated-but-not-converged
            //    result with bytes far above target.
            if achievedBytes > targetBytes {
                if qstep >= upper * 0.95 {
                    upper = upper * 4.0  // widen ceiling
                }
                lower = qstep
                qstep = (qstep * upper).squareRoot()
            } else {
                if qstep <= lower * 1.05 {
                    lower = lower / 4.0  // widen floor
                }
                upper = qstep
                qstep = (qstep * lower).squareRoot()
            }

            // 5. Early-exit when bracket has narrowed but tolerance not
            //    reached — further iterations won't help meaningfully.
            //    This kicks in when the bytes/qstep curve is nearly
            //    flat at the target (16-bit medical content can have
            //    α as low as 0.13 — qstep changes hardly move bpp).
            if iterationCount >= 3 && (upper / lower) < 1.05 {
                break
            }
        }

        // v5.32.0 — bounded-rate refinement.
        //
        // The main search may terminate without hitting tolerance on
        // flat-curve content (16-bit medical at low bpp can have
        // bytes-vs-qstep slope as low as α=0.13, so even at upper
        // bracket the bytes stay over target). When that happens
        // the closest-achieved encoding can overshoot the target
        // significantly — the v5.31.0 cross-scale probe showed
        // 1.6–3× overshoot at 2 bpp on large fixtures.
        //
        // Bounded-rate refinement: after the main search, if
        // achieved bytes still exceed `maxOvershootRatio × target`,
        // run up to 3 additional iterations that aggressively scale
        // qstep up to push bytes down. Each iteration multiplies
        // qstep by `ratio^0.7` (sub-linear so we don't overshoot
        // the other direction; works for α≈0.13–1.0 curves). Stop
        // when within bound, when no further byte reduction is
        // achieved, or when the iteration cap is hit.
        //
        // Trade-off: caps the rate overshoot at the cost of some
        // PSNR (typically 5–10 dB) on the worst-overshoot cases.
        // The user spec is "bounded rate, keep most of the quality" —
        // this delivers both within the realistic bounds of the
        // conformant cleanup-only block format.
        var refinementIters = 0
        let maxRefinementIters = 3
        while bestEncoded.count > Int(targetBytes * maxOvershootRatio),
              refinementIters < maxRefinementIters {
            refinementIters += 1
            let currentRatio = Double(bestEncoded.count) / targetBytes
            // Aggressive but stable: ratio^0.7 advances faster than
            // a pure log step but doesn't overshoot the other direction.
            let scaleFactor = pow(currentRatio, 0.7)
            let newQstep = bestQstep * scaleFactor

            var iterConfig = encodingConfiguration
            iterConfig.bitrateMode = .fixedQstep(qstep: newQstep)
            iterConfig.lossless = false
            let pipeline = EncoderPipeline(config: iterConfig)
            let refined = try await pipeline.encode(image)

            // Accept only if it makes progress AND doesn't push under
            // target (don't trade overshoot for undershoot — the
            // user wants bounded above-target, not strict-below).
            if refined.count >= bestEncoded.count {
                // No progress (qstep increase didn't reduce bytes —
                // we may be hitting a structural floor like LL
                // overhead). Stop.
                break
            }
            if Double(refined.count) < targetBytes * 0.9 {
                // Undershoot — qstep was too aggressive. Don't
                // accept; keep the previous over-target encoding
                // since over-target is better than undershoot for
                // bounded mode.
                break
            }
            bestEncoded = refined
            bestQstep = newQstep
            iterationCount += 1
        }

        // Convergence either succeeded above or fell back to closest-
        // achieved. Cache the best qstep regardless — even if we
        // didn't hit tolerance, this is the encoder's best estimate.
        await encodingConfiguration.qstepCache?.store(cacheKey, qstep: bestQstep)
        let achievedBpp = Double(bestEncoded.count * 8) / Double(totalSamples)
        let stats = J2KEncodeQstepStats(
            iterations: iterationCount,
            initialQstep: initialQstep,
            convergedQstep: bestQstep,
            achievedBpp: achievedBpp,
            targetBpp: targetBpp,
            cacheHit: cacheHit,
            convergedWithinTolerance:
                abs(achievedBpp / targetBpp - 1.0) < tolerance)
        return (bestEncoded, stats)
    }

    /// Calibrated initial qstep for a (targetBpp, bitDepth) pair.
    /// Empirically derived from J2KSwift's HT conformant lossy path
    /// on natural-image content. The binary search refines from here.
    /// Values targeted at within ~50% of the converged qstep on a
    /// typical natural image; the search burns 2–3 iterations beyond
    /// that to converge to within 5% tolerance.
    private static func initialQstepGuess(targetBpp: Double, bitDepth: Int) -> Double {
        // J2KSwift's qstep semantics differ from OpenJPH's — see
        // V5_18_0_DESIGN.md and v5.18.0 release notes. These
        // calibrations match J2KSwift's `J2KStepSizeCalculator`.
        // Empirically: bytes ≈ k / qstep on natural images, so for
        // a target bpp B we estimate qstep ≈ k / B where k depends
        // on bit-depth.
        let bd = max(8, bitDepth)
        let k: Double
        switch bd {
        case 8:    k = 80.0
        case 9...12:  k = 50.0
        default:   k = 30.0   // 16-bit and beyond
        }
        return k / max(0.05, targetBpp)
    }

    /// Encodes an image to JPEG 2000 format with progress reporting.
    ///
    /// - Parameters:
    ///   - image: The image to encode.
    ///   - progress: A callback invoked with progress updates during encoding.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(
        _ image: J2KImage,
        progress: ((EncoderProgressUpdate) -> Void)?
    ) async throws -> Data {
        let pipeline = EncoderPipeline(config: encodingConfiguration)
        return try await pipeline.encode(image, progress: progress)
    }

    /// Encodes an image to JPEG 2000 format with GPU acceleration.
    ///
    /// Uses Metal GPU for the CDF 9/7 wavelet transform stage when available.
    /// Falls back to CPU for lossless (5/3) and custom wavelet filters.
    ///
    /// - Parameter image: The image to encode.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encodeGPU(_ image: J2KImage) async throws -> Data {
        let pipeline = EncoderPipeline(config: encodingConfiguration)
        return try await pipeline.encodeGPU(image)
    }

    /// Encodes an image to JPEG 2000 format with GPU acceleration and progress reporting.
    ///
    /// - Parameters:
    ///   - image: The image to encode.
    ///   - progress: A callback invoked with progress updates during encoding.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encodeGPU(
        _ image: J2KImage,
        progress: ((EncoderProgressUpdate) -> Void)?
    ) async throws -> Data {
        let pipeline = EncoderPipeline(config: encodingConfiguration)
        return try await pipeline.encodeGPU(image, progress: progress)
    }
}

/// Decodes JPEG 2000 images.
///
/// `J2KDecoder` provides a high-level API for decoding JPEG 2000 codestreams to images.
/// It connects all decoding components — codestream parsing, entropy decoding, dequantization,
/// inverse wavelet transform, and inverse colour transform — into a complete decoding pipeline.
///
/// ## Basic Usage
///
/// ```swift
/// let decoder = J2KDecoder()
/// let codestreamData = // ... load from file
/// let image = try decoder.decode(codestreamData)
/// ```
///
/// ## Progress Reporting
///
/// ```swift
/// let image = try decoder.decode(data) { update in
///     print("\(update.stage): \(Int(update.overallProgress * 100))%")
/// }
/// ```
/// v5.27.0 routing recommendation for the GPU decode APIs. Returned
/// by `J2KDecoder.recommendedDecodeAPI(for:)` to help callers pick
/// between `decode`, `decodeGPU(_:session:)`, and
/// `decodeWithGPUHT(_:session:)` based on image dimensions.
public enum J2KRecommendedDecodeAPI: Sendable {
    /// CPU `decode(_:)`. Recommended for tiny images (< 256×256)
    /// where Metal startup + dispatch overhead exceeds CPU decode
    /// time even on a warm session.
    case cpu
    /// `decodeGPU(_:session:)`. CPU HT entropy + GPU IDWT. The
    /// fastest path for the typical medical-imaging size range
    /// (256×256 to ~1730×1730).
    case decodeGPU
    /// `decodeWithGPUHT(_:session:)`. Full GPU pipeline. Wins on
    /// large images (≥ ~1730×1730) where the GPU HT dispatch cost
    /// amortizes across the larger codeblock count.
    case decodeWithGPUHT
}

public struct J2KDecoder: Sendable {
    /// Creates a new decoder.
    public init() {}

    /// v5.27.0: recommended decode API for an image of the given
    /// dimensions on a warm `J2KMetalSession`.
    ///
    /// Threshold derived from the v5.27.0 medical-corpus benchmark
    /// on M2 (see MEDICAL_BENCHMARK.md "Decode Performance"):
    ///   - ≤ 256×256 (65k px): CPU `decode` is within noise of GPU
    ///     paths; either is fine. Defaults to CPU because cold-start
    ///     Metal overhead penalises tiny one-off decodes.
    ///   - 256×256 to ~1730×1730 (~3M px): `decodeGPU` is the clear
    ///     winner (1.3–3.0× CPU); `decodeWithGPUHT` lags here because
    ///     GPU HT dispatch overhead doesn't amortise.
    ///   - ≥ 1730×1730 (~3M px): `decodeWithGPUHT` overtakes (3–4×
    ///     CPU vs `decodeGPU`'s 3–3.7×) as the dispatch cost
    ///     amortises.
    ///
    /// Cold-start Metal overhead (~50 ms first decode on a fresh
    /// session) is unrelated to image size — for genuine one-off
    /// decodes prefer CPU `decode` regardless of dimensions.
    public static func recommendedDecodeAPI(
        width: Int, height: Int
    ) -> J2KRecommendedDecodeAPI {
        let pixels = width * height
        if pixels < 256 * 256 { return .cpu }
        if pixels < 3_000_000 { return .decodeGPU }
        return .decodeWithGPUHT
    }

    /// Decodes JPEG 2000 data into an image.
    ///
    /// This method processes the codestream through the complete JPEG 2000 decoding pipeline:
    /// 1. Codestream parsing and marker validation
    /// 2. Tile data extraction from packets
    /// 3. EBCOT entropy decoding
    /// 4. Dequantization
    /// 5. Inverse wavelet transform
    /// 6. Inverse colour transform (YCbCr → RGB)
    /// 7. Image reconstruction
    ///
    /// - Parameter data: The JPEG 2000 codestream data to decode.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the codestream is malformed.
    public func decode(_ data: Data) async throws -> J2KImage {
        let pipeline = DecoderPipeline()
        return try await pipeline.decode(data)
    }

    /// Decodes JPEG 2000 data into an image with progress reporting.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data to decode.
    ///   - progress: A callback invoked with progress updates during decoding.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decode(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        let pipeline = DecoderPipeline()
        return try await pipeline.decode(data, progress: progress)
    }

    /// Decodes JPEG 2000 data into an image with GPU acceleration.
    ///
    /// Uses Metal GPU for both wavelet families:
    /// - **Reversible 5/3 (lossless):** Int32 integer kernels with arithmetic-
    ///   shift lifting, **bit-exact** with the JPEG 2000 spec. Output is
    ///   identical to the CPU path, so lossless byte-equality round-trips
    ///   (e.g. DICOM HTJ2K-Lossless verify) succeed on GPU.
    /// - **Irreversible 9/7 (lossy):** Float kernels.
    ///
    /// Falls back to CPU when Metal is unavailable, for custom wavelet
    /// kernels, or for images smaller than the GPU dispatch threshold.
    ///
    /// - Parameter data: The JPEG 2000 codestream data to decode.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodeGPU(_ data: Data) async throws -> J2KImage {
        let pipeline = DecoderPipeline()
        return try await pipeline.decodeGPU(data)
    }

    /// Decodes JPEG 2000 data into an image with GPU acceleration and progress reporting.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data to decode.
    ///   - progress: A callback invoked with progress updates during decoding.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodeGPU(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        let pipeline = DecoderPipeline()
        return try await pipeline.decodeGPU(data, progress: progress)
    }

    /// Decodes JPEG 2000 data with GPU acceleration **reusing a long-
    /// lived `J2KMetalSession`** across calls. CPU runs HT entropy +
    /// regroup; GPU runs IDWT + colour transform + quantisation.
    ///
    /// This is the GPU-IDWT-only counterpart to
    /// `decodeWithGPUHT(_:session:)`. On 9/7 lossy workloads where the
    /// per-tile GPU HT dispatch overhead exceeds the parallelised CPU
    /// HT cost (small/medium images, low block counts) this entry
    /// point is faster than `decodeWithGPUHT`. On large workloads
    /// `decodeWithGPUHT` wins because the GPU HT dispatch amortises.
    public func decodeGPU(
        _ data: Data,
        session: J2KMetalSession
    ) async throws -> J2KImage {
        var pipeline = DecoderPipeline()
        pipeline.metalSession = session
        return try await pipeline.decodeGPU(data)
    }

    /// Decodes JPEG 2000 data into an image with **opt-in GPU HTJ2K
    /// entropy decode** in addition to the existing GPU inverse DWT.
    ///
    /// When the codestream is HTJ2K conformant cleanup-only AND Metal
    /// is available, eligible codeblocks are batched through the
    /// Metal HT cleanup kernel instead of decoded one at a time on
    /// CPU. Ineligible blocks (refinement passes, custom format,
    /// empty data, parse failure) fall through to the existing CPU
    /// HT path automatically. The decoded output is bit-exact with
    /// `decodeGPU` byte-for-byte; this entry point exists for callers
    /// who want to opt in to the M2-prime production-integration path
    /// shipping in v5.5.0.
    ///
    /// - Parameter data: The JPEG 2000 codestream data to decode.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodeWithGPUHT(_ data: Data) async throws -> J2KImage {
        var pipeline = DecoderPipeline()
        pipeline.useGPUHT = true
        return try await pipeline.decodeGPU(data)
    }

    /// Decodes JPEG 2000 data with opt-in GPU HTJ2K entropy decode
    /// and a progress callback. See ``decodeWithGPUHT(_:)``.
    public func decodeWithGPUHT(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        var pipeline = DecoderPipeline()
        pipeline.useGPUHT = true
        return try await pipeline.decodeGPU(data, progress: progress)
    }

    /// Decodes JPEG 2000 data with opt-in GPU HTJ2K entropy decode,
    /// **reusing a long-lived `J2KMetalSession`** across calls.
    ///
    /// The first decode that uses a fresh session pays the ~50 ms
    /// Metal device init + shader compile cost; subsequent decodes
    /// using the same session reuse the cached MSL library, compute
    /// pipelines, and buffer pool. This is the warm-process pattern
    /// v5.6.0 introduces — the right choice for any caller that
    /// decodes more than one image in a single process.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data to decode.
    ///   - session: A reusable Metal session. Construct once, pass
    ///     to every decode call.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decodeWithGPUHT(
        _ data: Data,
        session: J2KMetalSession
    ) async throws -> J2KImage {
        var pipeline = DecoderPipeline()
        pipeline.useGPUHT = true
        pipeline.metalSession = session
        return try await pipeline.decodeGPU(data)
    }

    /// Decodes JPEG 2000 data with a session and a progress callback.
    /// See ``decodeWithGPUHT(_:session:)``.
    public func decodeWithGPUHT(
        _ data: Data,
        session: J2KMetalSession,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        var pipeline = DecoderPipeline()
        pipeline.useGPUHT = true
        pipeline.metalSession = session
        return try await pipeline.decodeGPU(data, progress: progress)
    }
}
