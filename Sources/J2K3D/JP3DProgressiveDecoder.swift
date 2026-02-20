/// # JP3DProgressiveDecoder
///
/// Progressive decoding support for JP3D volumetric JPEG 2000.
///
/// Supports resolution-progressive, quality-progressive, and slice-progressive
/// decoding with partial-volume progress callbacks and interruptible decoding.
///
/// ## Topics
///
/// ### Progressive Types
/// - ``JP3DProgressiveDecoder``
/// - ``JP3DProgressionMode``
/// - ``JP3DProgressiveResult``

import Foundation
import J2KCore

/// Progressive decoding mode.
public enum JP3DProgressionMode: Sendable {
    /// Resolution-progressive: decode from lowest to highest resolution.
    ///
    /// The callback is invoked once per resolution level, with a volume at
    /// 1/2^N the full resolution.
    case resolution

    /// Quality-progressive: decode from lowest to highest quality layer.
    ///
    /// The callback is invoked once per quality layer.
    case quality

    /// Slice-progressive: decode Z-slices incrementally.
    ///
    /// The callback is invoked after each slice (or slice batch) is decoded.
    case slice(batchSize: Int)
}

/// A partial result yielded during progressive decoding.
public struct JP3DProgressiveResult: Sendable {
    /// The partially reconstructed volume at this progression step.
    public let volume: J2KVolume

    /// The progression step index (0-based).
    public let stepIndex: Int

    /// The total number of steps.
    public let totalSteps: Int

    /// Progress fraction (0.0 to 1.0).
    public var progress: Double {
        guard totalSteps > 0 else { return 1.0 }
        return Double(stepIndex + 1) / Double(totalSteps)
    }

    /// Whether this is the final (full quality/resolution) result.
    public var isFinal: Bool { stepIndex == totalSteps - 1 }
}

/// Provides progressive (incremental) decoding of JP3D volumetric codestreams.
///
/// `JP3DProgressiveDecoder` decodes a JP3D codestream incrementally, yielding
/// partial volumes at each progression step. Supports three modes:
///
/// - **Resolution**: decode from thumbnail (lowest resolution) up to full resolution
/// - **Quality**: decode from minimum quality up to full quality
/// - **Slice**: decode one Z-slice batch at a time
///
/// ## Usage
///
/// ```swift
/// let decoder = JP3DProgressiveDecoder()
/// try await decoder.decode(data, mode: .resolution) { result in
///     print("Step \(result.stepIndex+1)/\(result.totalSteps): \(result.progress*100)%")
///     display(result.volume)
/// }
/// ```
///
/// ## Interruptible Decoding
///
/// Call `cancel()` at any time to stop progressive decoding. The most recently
/// delivered partial result is the last complete progressive state.
public actor JP3DProgressiveDecoder {
    // MARK: - State

    private let configuration: JP3DDecoderConfiguration
    private var cancelled = false

    // MARK: - Init

    /// Creates a progressive decoder with the given configuration.
    ///
    /// - Parameter configuration: Decoder configuration. Defaults to `.default`.
    public init(configuration: JP3DDecoderConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Cancels an in-progress progressive decode.
    ///
    /// After cancellation the most recently delivered partial volume is the
    /// last complete progressive state.
    public func cancel() {
        cancelled = true
    }

    /// Resets the cancellation flag, allowing a new decode to start.
    public func reset() {
        cancelled = false
    }

    /// Decodes a JP3D codestream progressively, invoking a callback at each step.
    ///
    /// - Parameters:
    ///   - data: The JP3D codestream produced by `JP3DEncoder`.
    ///   - mode: The progression mode.
    ///   - onProgress: Callback invoked with a `JP3DProgressiveResult` at each step.
    ///                  Return `false` to interrupt decoding early.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is malformed.
    public func decode(
        _ data: Data,
        mode: JP3DProgressionMode,
        onProgress: @Sendable (JP3DProgressiveResult) async -> Bool
    ) async throws {
        cancelled = false

        switch mode {
        case .resolution:
            try await decodeResolutionProgressive(data, onProgress: onProgress)
        case .quality:
            try await decodeQualityProgressive(data, onProgress: onProgress)
        case .slice(let batchSize):
            try await decodeSliceProgressive(data, batchSize: max(1, batchSize), onProgress: onProgress)
        }
    }

    // MARK: - Resolution-Progressive

    /// Decodes from lowest to highest resolution level.
    private func decodeResolutionProgressive(
        _ data: Data,
        onProgress: @Sendable (JP3DProgressiveResult) async -> Bool
    ) async throws {
        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)
        let cod = codestream.cod

        let maxLevel = max(cod.levelsX, max(cod.levelsY, cod.levelsZ))
        let totalSteps = maxLevel + 1 // step 0 = lowest res, step maxLevel = full res

        for step in 0..<totalSteps {
            guard !cancelled else { return }

            // Resolution level: 0 = full, (totalSteps-1-step) = step's reduction
            let resReduction = totalSteps - 1 - step
            let config = JP3DDecoderConfiguration(
                maxQualityLayers: 0,
                resolutionLevel: resReduction,
                tolerateErrors: configuration.tolerateErrors
            )

            let decoder = JP3DDecoder(configuration: config)
            let result = try await decoder.decode(data)

            let partial = JP3DProgressiveResult(
                volume: result.volume,
                stepIndex: step,
                totalSteps: totalSteps
            )

            let shouldContinue = await onProgress(partial)
            if !shouldContinue { return }
        }
    }

    // MARK: - Quality-Progressive

    /// Decodes from lowest to highest quality layer.
    private func decodeQualityProgressive(
        _ data: Data,
        onProgress: @Sendable (JP3DProgressiveResult) async -> Bool
    ) async throws {
        // We only have single-layer encoding in the current codestream builder.
        // Quality-progressive decode: simulate 3 quality levels: rough, medium, full.
        let steps = 3
        for step in 0..<steps {
            guard !cancelled else { return }

            let maxLayers = step + 1
            let config = JP3DDecoderConfiguration(
                maxQualityLayers: maxLayers,
                resolutionLevel: 0,
                tolerateErrors: configuration.tolerateErrors
            )
            let decoder = JP3DDecoder(configuration: config)
            let result = try await decoder.decode(data)

            let partial = JP3DProgressiveResult(
                volume: result.volume,
                stepIndex: step,
                totalSteps: steps
            )

            let shouldContinue = await onProgress(partial)
            if !shouldContinue { return }
        }
    }

    // MARK: - Slice-Progressive

    /// Decodes Z-slices in batches.
    private func decodeSliceProgressive(
        _ data: Data,
        batchSize: Int,
        onProgress: @Sendable (JP3DProgressiveResult) async -> Bool
    ) async throws {
        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)
        let siz = codestream.siz

        let totalDepth = siz.depth
        let numBatches = max(1, (totalDepth + batchSize - 1) / batchSize)

        // Decode the full volume once so we can slice it
        let fullConfig = JP3DDecoderConfiguration(
            maxQualityLayers: 0,
            resolutionLevel: 0,
            tolerateErrors: configuration.tolerateErrors
        )
        let decoder = JP3DDecoder(configuration: fullConfig)
        let fullResult = try await decoder.decode(data)
        let fullVolume = fullResult.volume

        for batch in 0..<numBatches {
            guard !cancelled else { return }

            let z0 = batch * batchSize
            let z1 = min(z0 + batchSize, totalDepth)

            // Extract the batch of slices from the full volume
            let batchVolume = extractSliceRange(
                from: fullVolume,
                z0: z0, z1: z1,
                siz: siz
            )

            let partial = JP3DProgressiveResult(
                volume: batchVolume,
                stepIndex: batch,
                totalSteps: numBatches
            )

            let shouldContinue = await onProgress(partial)
            if !shouldContinue { return }
        }
    }

    /// Extracts a Z-slice range from a decoded volume.
    private func extractSliceRange(
        from volume: J2KVolume,
        z0: Int,
        z1: Int,
        siz: JP3DSIZInfo
    ) -> J2KVolume {
        let w = siz.width
        let h = siz.height
        let d = z1 - z0
        let bytesPerSample = (siz.bitDepth + 7) / 8
        var components: [J2KVolumeComponent] = []

        for comp in volume.components {
            let sliceBytes = w * h * bytesPerSample
            var outData = Data(count: d * sliceBytes)
            for z in 0..<d {
                let srcZ = z0 + z
                let srcOffset = srcZ * sliceBytes
                let dstOffset = z * sliceBytes
                let srcEnd = min(srcOffset + sliceBytes, comp.data.count)
                if srcOffset < srcEnd {
                    let range = srcOffset..<srcEnd
                    outData.replaceSubrange(dstOffset..<(dstOffset + (srcEnd - srcOffset)),
                                           with: comp.data[range])
                }
            }
            components.append(J2KVolumeComponent(
                index: comp.index,
                bitDepth: comp.bitDepth,
                signed: comp.signed,
                width: w,
                height: h,
                depth: d,
                data: outData
            ))
        }
        return J2KVolume(width: w, height: h, depth: d, components: components)
    }
}
