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
        if case .constantBitrateViaQstep(let bpp, let tol, let maxIter) = encodingConfiguration.bitrateMode {
            let (data, _) = try await encodeViaQstepSearch(
                image,
                targetBpp: bpp,
                tolerance: tol,
                maxIterations: maxIter)
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
            maxIterations: maxIter)
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
        maxIterations: Int
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
                // Reset bracket around the refined guess. Tighter than
                // the calibration-only bracket since we have a fresh
                // observation.
                lower = qstep / 8.0
                upper = qstep * 8.0
                continue
            }

            // 4. Standard log-binary-search narrowing for iter ≥ 2.
            if achievedBytes > targetBytes {
                lower = qstep
                qstep = (qstep * upper).squareRoot()
            } else {
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

        // Convergence either succeeded above or fell back to closest-
        // achieved. Cache the best qstep regardless — even if we
        // didn't hit tolerance, this is the encoder's best estimate.
        await encodingConfiguration.qstepCache?.store(cacheKey, qstep: bestQstep)
        let stats = J2KEncodeQstepStats(
            iterations: iterationCount,
            initialQstep: initialQstep,
            convergedQstep: bestQstep,
            achievedBpp: Double(bestEncoded.count * 8) / Double(totalSamples),
            targetBpp: targetBpp,
            cacheHit: cacheHit,
            convergedWithinTolerance: false)
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
public struct J2KDecoder: Sendable {
    /// Creates a new decoder.
    public init() {}

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
